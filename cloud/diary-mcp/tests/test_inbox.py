"""收件箱：加密 → PUT → App 能拉到。

重点验三件事：
1. 上传出去的密文能被**同一个密钥**解开（格式必须和 Dart 侧一致）；
2. 信封结构和 backup.mbk 同构（App 侧可以复用同一套解密代码）；
3. 文件名带时间戳且不撞名。
"""

from __future__ import annotations

import base64
import json
from datetime import datetime

import pytest

from diary_mcp.crypto import decrypt_text
from diary_mcp.inbox import (
    KIND_DRAFT,
    InboxError,
    _make_filename,
    build_envelope,
    upload_draft,
)

KEY = base64.b64encode(b"0123456789abcdef0123456789abcdef").decode()


class _FakeClient:
    """记录上传内容的假 WebDAV 客户端。"""

    def __init__(self, fail: bool = False):
        self.uploads: list[tuple[str, str]] = []
        self.fail = fail

    def upload(self, path: str, content: str) -> None:
        if self.fail:
            from diary_mcp.webdav import WebdavError

            raise WebdavError("PUT 返回 500")
        self.uploads.append((path, content))


def test_envelope_roundtrip_with_same_key():
    """上传的密文必须能被同一把 cloud_key 解回原文。"""
    payload = {
        "title": "今天的雨",
        "content": "早上出门没带伞，狼狈。",
        "date": "2026-10-29",
        "mood": "无奈",
        "created_at": "2026-10-29T12:00:00",
        "source": "maibot",
    }
    envelope = build_envelope(payload, KEY)

    outer = json.loads(envelope)
    assert outer["_encrypted"] is True
    assert outer["_version"] == 2
    assert outer["kind"] == KIND_DRAFT
    assert outer["data"].startswith("__CLOUD__")

    plain = decrypt_text(outer["data"], KEY)
    assert json.loads(plain) == payload


def test_envelope_is_not_plaintext():
    """信封里不能出现明文正文（服务器上只有密文是硬要求）。"""
    envelope = build_envelope({"title": "秘密", "content": "不能明文落盘"}, KEY)
    assert "秘密" not in envelope
    assert "不能明文落盘" not in envelope


def test_wrong_key_cannot_decrypt():
    envelope = build_envelope({"content": "x"}, KEY)
    data = json.loads(envelope)["data"]
    other = base64.b64encode(b"fedcba9876543210fedcba9876543210").decode()
    with pytest.raises(Exception):
        decrypt_text(data, other)


def test_filename_has_timestamp_prefix():
    name = _make_filename(datetime(2026, 10, 29, 12, 30, 45))
    assert name.startswith("draft_20261029-123045_")
    assert name.endswith(".mbk")


def test_filename_unique_within_same_second():
    a = _make_filename(datetime(2026, 10, 29, 12, 30, 45))
    b = _make_filename(datetime(2026, 10, 29, 12, 30, 45))
    assert a != b


def test_upload_draft_writes_into_remote_dir():
    client = _FakeClient()
    filename = upload_draft(
        client,
        "inbox",
        KEY,
        title="标题",
        content="正文",
        day="2026-10-29",
        mood="开心",
    )

    assert len(client.uploads) == 1
    path, body = client.uploads[0]
    assert path == f"inbox/{filename}"
    assert path.startswith("inbox/")

    data = json.loads(body)["data"]
    plain = json.loads(decrypt_text(data, KEY))
    assert plain["title"] == "标题"
    assert plain["content"] == "正文"
    assert plain["date"] == "2026-10-29"
    assert plain["mood"] == "开心"
    assert plain["source"] == "maibot"


def test_upload_draft_without_key_raises():
    client = _FakeClient()
    with pytest.raises(InboxError):
        upload_draft(
            client, "inbox", "", title="t", content="c", day="2026-10-29", mood=""
        )
    assert client.uploads == []


def test_upload_draft_wraps_webdav_error():
    client = _FakeClient(fail=True)
    with pytest.raises(InboxError):
        upload_draft(
            client, "inbox", KEY, title="t", content="c", day="2026-10-29", mood=""
        )


# ---------- 跨语言契约（反向：Dart 产出 → Python 解密）----------


def test_dart_produced_envelope_is_decryptable():
    """App 侧（Dart）产出的密文，Python 必须能解开。

    fixture 由 `dart tool/make_inbox_dart_fixture.dart` 生成，
    锁的是「两边信封格式必须一致」这个契约。
    """
    import json
    import pathlib

    fixture = (
        pathlib.Path(__file__).resolve().parents[3]
        / "test"
        / "fixtures"
        / "inbox_dart_envelope.json"
    )
    assert fixture.exists(), f"缺少 fixture：{fixture}"

    envelope = json.loads(fixture.read_text(encoding="utf-8"))
    assert envelope["_encrypted"] is True
    assert envelope["_version"] == 2
    assert envelope["kind"] == KIND_DRAFT

    plain = decrypt_text(envelope["data"], KEY)
    payload = json.loads(plain)
    assert payload["title"] == "来自 Dart 的回程"
    assert payload["mood"] == "平静"
    assert "换行" in payload["content"]
