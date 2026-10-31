"""WebDAV 只读同步：不重复下载同一份备份。

WebDAV 服务大多按流量计费（坚果云一类），一次 sync 就是一次全量下载；
所以「内容没变就不下」不是优化，是必需品。
判断依据只用 PROPFIND 里已经返回的 ETag / 修改时间 + 字节数，不额外发请求。
"""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

from diary_mcp import __main__ as cli
from diary_mcp.config import WebdavConfig
from diary_mcp.webdav import Entry, WebdavClient, WebdavError

PROPFIND_XML = """<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/diary_backups/backup_ab12/backup.mbk</d:href>
    <d:propstat>
      <d:prop>
        <d:getlastmodified>Wed, 28 Oct 2026 04:00:00 GMT</d:getlastmodified>
        <d:getcontentlength>524288</d:getcontentlength>
        <d:getetag>"abc-123"</d:getetag>
        <d:resourcetype/>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
"""


class _Resp:
    status_code = 207
    text = PROPFIND_XML


class _FakeClient:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def request(self, *args, **kwargs):
        return _Resp()

    def get(self, *args, **kwargs):  # 不该被调用
        raise AssertionError("内容没变时不应该发生下载")


def test_fingerprint_prefers_etag() -> None:
    stamp = datetime(2026, 10, 28, 4, 0, tzinfo=timezone.utc)
    a = Entry("x", False, stamp, size=100, etag="abc")
    b = Entry("x", False, stamp, size=100, etag="abc")
    c = Entry("x", False, stamp, size=100, etag="def")
    assert a.fingerprint == b.fingerprint
    assert a.fingerprint != c.fingerprint


def test_fingerprint_falls_back_to_mtime_and_size() -> None:
    stamp = datetime(2026, 10, 28, 4, 0, tzinfo=timezone.utc)
    a = Entry("x", False, stamp, size=100)
    same_time_bigger = Entry("x", False, stamp, size=101)
    assert a.fingerprint != same_time_bigger.fingerprint
    assert a.fingerprint.startswith("mtime:")


def test_propfind_reads_size_and_etag(monkeypatch) -> None:
    client = WebdavClient(WebdavConfig(url="https://dav.example.com/dav/"))
    monkeypatch.setattr(WebdavClient, "_client", lambda self: _FakeClient())

    entries = client.propfind("diary_backups/backup_ab12/")

    assert len(entries) == 1
    entry = entries[0]
    assert entry.size == 524288
    assert entry.etag == "abc-123"
    assert entry.fingerprint == "etag:abc-123"


def test_download_skipped_when_fingerprint_matches() -> None:
    entry = Entry("https://dav.example.com/x.mbk", False, None, size=10, etag="same")
    client = WebdavClient(WebdavConfig(url="https://dav.example.com/dav/"))

    text, returned = client._download(entry, entry.fingerprint)

    assert text is None  # 没有下载
    assert returned is entry


def test_download_without_known_fingerprint_still_hits_network(monkeypatch) -> None:
    entry = Entry("https://dav.example.com/x.mbk", False, None, size=10, etag="same")
    client = WebdavClient(WebdavConfig(url="https://dav.example.com/dav/"))

    class _GetClient(_FakeClient):
        def get(self, *args, **kwargs):
            class R:
                status_code = 200
                text = "payload"

            return R()

    monkeypatch.setattr(WebdavClient, "_client", lambda self: _GetClient())
    text, _ = client._download(entry, "")
    assert text == "payload"


def test_sync_reports_skip(monkeypatch, tmp_path, capsys) -> None:
    db = tmp_path / "diary.db"
    config = tmp_path / "config.toml"
    config.write_text(
        f'[storage]\ndb_path = "{db.as_posix()}"\n[crypto]\ncloud_key = "k"\n'
        '[webdav]\nurl = "https://dav.example.com/dav/"\n',
        encoding="utf-8",
    )

    seen: dict[str, str] = {}

    class _StubWebdav:
        def __init__(self, cfg):
            pass

        def latest_backup(self, known=""):
            seen["known"] = known
            return None, Entry("https://dav.example.com/b.mbk", False, None, size=1234)

    monkeypatch.setattr(cli, "WebdavClient", _StubWebdav)

    ns = type("NS", (), {"config": str(config), "force": False})()
    code = cli.cmd_sync(ns)

    assert code == 0
    assert "跳过下载" in capsys.readouterr().out
    assert seen["known"] == ""  # 首次没有记录，正常请求

    # 有记录时应把指纹传下去
    from diary_mcp.store import Store

    store = Store(db)
    store.set_meta("last_backup_fp", "etag:zzz")
    store.close()
    cli.cmd_sync(ns)
    assert seen["known"] == "etag:zzz"


def test_force_ignores_known_fingerprint(monkeypatch, tmp_path) -> None:
    db = tmp_path / "diary.db"
    config = tmp_path / "config.toml"
    config.write_text(
        f'[storage]\ndb_path = "{db.as_posix()}"\n[crypto]\ncloud_key = "k"\n'
        '[webdav]\nurl = "https://dav.example.com/dav/"\n',
        encoding="utf-8",
    )
    from diary_mcp.store import Store

    store = Store(db)
    store.set_meta("last_backup_fp", "etag:zzz")
    store.close()

    seen: dict[str, str] = {}

    class _StubWebdav:
        def __init__(self, cfg):
            pass

        def latest_backup(self, known=""):
            seen["known"] = known
            return None, Entry("https://dav.example.com/b.mbk", False, None, size=1)

    monkeypatch.setattr(cli, "WebdavClient", _StubWebdav)
    ns = type("NS", (), {"config": str(config), "force": True})()
    cli.cmd_sync(ns)

    assert seen["known"] == ""


def test_missing_cloud_key_is_reported(tmp_path) -> None:
    config = tmp_path / "config.toml"
    config.write_text('[crypto]\ncloud_key = ""\n', encoding="utf-8")
    ns = type("NS", (), {"config": str(config), "force": False})()
    assert cli.cmd_sync(ns) == 1


def test_abs_url_keeps_base_subpath() -> None:
    """base 带子路径（自建服务器的 https://host/dav/）时，相对 href 必须拼在其后。

    曾经的实现只拼 `scheme://netloc`，得到 `https://hostdiary_backups/`
    —— 主机名被粘上路径，报错却是 `getaddrinfo failed`，看起来像 DNS 问题。
    这个 bug 只有在 base 带子路径且真的发出请求时才会暴露，所以必须有测试锁。
    """
    from diary_mcp.webdav import _abs_url

    assert _abs_url("https://h/dav/", "diary_backups/") == "https://h/dav/diary_backups/"
    assert _abs_url("https://h/dav", "diary_backups/") == "https://h/dav/diary_backups/"
    # 服务端 PROPFIND 返回的 href 是绝对路径，要替换掉 base 的 path
    assert _abs_url("https://h/dav/", "/dav/x/") == "https://h/dav/x/"
    # 已经是绝对 URL 的原样返回
    assert _abs_url("https://h/dav/", "http://other/z") == "http://other/z"
