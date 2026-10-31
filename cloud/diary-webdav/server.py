#!/usr/bin/env python3
"""极简 WebDAV 服务端 —— 只服务小记日记 App 的云同步。

App 侧实际只发 6 种请求（见 cloud_sync_service.dart）：
    PROPFIND(Depth 0)  目录探测 / 只认 207 与 404
    PROPFIND(Depth 1)  列目录 / 只解析 <d:displayname>
    MKCOL              建目录 / 认 201
    PUT                上传 backup.mbk、images_*.enc
    GET                下载
    HEAD / OPTIONS     可选

另外补了 DELETE（App 侧新增的「麦麦写来的日记」收件箱用）：
    DELETE             删收件箱里的某一条 —— **只允许删 inbox/ 目录下的文件**

因此这里不实现完整 RFC 4918：不做 LOCK、不做 MOVE/COPY、不做 Range。
纯标准库，零第三方依赖（避开服务器访问 PyPI 的问题）。

注意：不做任何解密。落盘的就是 App 上传的 `__CLOUD__` 密文，
以及 diary-mcp 用同一把 cloud_key 加密后上传的收件箱密文。
"""

from __future__ import annotations

import base64
import os
import sys
import tomllib
import urllib.parse
from datetime import datetime, timezone
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

CFG_PATH = os.environ.get("DAV_CONFIG", "/opt/diary-webdav/config.toml")
CHUNK = 256 * 1024
# 收件箱目录名（相对 root）。只有这里的文件允许 DELETE。
INBOX_NAME = "inbox"


def load_config() -> dict:
    cfg = {
        "username": "",
        "password": "",
        "root": "/opt/diary-webdav/data",
        "host": "127.0.0.1",
        "port": 8010,
        "prefix": "/dav",
    }
    try:
        with open(CFG_PATH, "rb") as fh:
            raw = tomllib.load(fh)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"[dav] 读配置失败 {CFG_PATH}: {exc}", file=sys.stderr)
        return cfg
    for section in ("auth", "storage", "server"):
        for key, value in (raw.get(section) or {}).items():
            if key in cfg:
                cfg[key] = value
    cfg["port"] = int(cfg["port"])
    cfg["root"] = os.path.abspath(cfg["root"])
    cfg["prefix"] = "/" + str(cfg["prefix"]).strip("/")
    return cfg


CFG = load_config()


def http_date(ts: float) -> str:
    return format_datetime(datetime.fromtimestamp(ts, timezone.utc), usegmt=True)


class DavHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "diary-dav/1.0"

    # ---------- 基础 ----------

    def log_message(self, fmt: str, *args) -> None:
        # 只记方法 + 路径 + 状态码，别刷屏
        print(f"[dav] {self.address_string()} {fmt % args}", file=sys.stderr, flush=True)

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        try:
            raw = base64.b64decode(header[6:]).decode("utf-8")
        except Exception:
            return False
        user, _, pwd = raw.partition(":")
        # 配置为空时拒绝一切（避免"忘配密码 = 裸奔"）
        if not CFG["username"] or not CFG["password"]:
            return False
        return user == CFG["username"] and pwd == CFG["password"]

    def _deny(self) -> None:
        body = b"auth required"
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="diary"')
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _fs_path(self) -> str | None:
        """把 URL 路径映射到数据根下的绝对路径；越界返回 None。"""
        path = urllib.parse.unquote(self.path.split("?", 1)[0])
        prefix = CFG["prefix"]
        if path == prefix:
            rel = "/"
        elif path.startswith(prefix + "/"):
            rel = path[len(prefix):]
        else:
            return None
        rel = rel.lstrip("/")
        # 归一化 + 拦截 .. 穿越
        normalized = os.path.normpath("/" + rel).lstrip("/")
        if normalized.startswith("..") or os.path.isabs(normalized):
            return None
        full = os.path.abspath(os.path.join(CFG["root"], normalized))
        if full != CFG["root"] and not full.startswith(CFG["root"] + os.sep):
            return None
        return full

    def _send_simple(self, code: int, body: bytes = b"", ctype: str = "text/plain; charset=utf-8") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)

    # ---------- 方法 ----------

    def do_OPTIONS(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._deny()
        self.send_response(200)
        self.send_header("DAV", "1")
        self.send_header("Allow", "OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, PROPFIND")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_PROPFIND(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._deny()
        target = self._fs_path()
        if target is None:
            return self._send_simple(403, b"forbidden")
        if not os.path.exists(target):
            # App 依赖这个 404 去触发 MKCOL
            return self._send_simple(404, b"not found")

        depth = (self.headers.get("Depth") or "0").strip()
        entries: list[tuple[str, str, bool, float, int]] = []

        def add(full: str) -> None:
            rel = os.path.relpath(full, CFG["root"])
            suffix = "/" if os.path.isdir(full) else ""
            href = CFG["prefix"] + "/" + ("" if rel == "." else urllib.parse.quote(rel.replace(os.sep, "/")) + suffix)
            entries.append(
                (
                    href,
                    os.path.basename(full),
                    os.path.isdir(full),
                    os.path.getmtime(full),
                    0 if os.path.isdir(full) else os.path.getsize(full),
                )
            )

        add(target)
        if depth != "0" and os.path.isdir(target):
            try:
                for name in sorted(os.listdir(target)):
                    add(os.path.join(target, name))
            except OSError:
                pass

        body = self._multistatus(entries)
        self.send_response(207)
        self.send_header("Content-Type", 'application/xml; charset="utf-8"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @staticmethod
    def _multistatus(entries: list[tuple[str, str, bool, float, int]]) -> bytes:
        out = ['<?xml version="1.0" encoding="utf-8"?>', '<d:multistatus xmlns:d="DAV:">']
        for href, name, is_dir, mtime, size in entries:
            out.append("<d:response>")
            out.append(f"<d:href>{escape(href)}</d:href>")
            out.append("<d:propstat><d:prop>")
            # 必须保持 <d:displayname>名字</d:displayname> 这个裸形式：
            # App 用正则 `<d:displayname>([^<]+)</d:displayname>` 解析，带属性就匹配不上。
            if name:
                out.append(f"<d:displayname>{escape(name)}</d:displayname>")
            if is_dir:
                out.append("<d:resourcetype><d:collection/></d:resourcetype>")
            else:
                out.append("<d:resourcetype/>")
                out.append(f"<d:getcontentlength>{size}</d:getcontentlength>")
            out.append(f"<d:getlastmodified>{http_date(mtime)}</d:getlastmodified>")
            out.append("</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>")
            out.append("</d:response>")
        out.append("</d:multistatus>")
        return "\n".join(out).encode("utf-8")

    def do_MKCOL(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._deny()
        target = self._fs_path()
        if target is None:
            return self._send_simple(403, b"forbidden")
        if os.path.isdir(target):
            # 已存在：App 只在 404 后才 MKCOL，真撞上给 405 是 RFC 语义
            return self._send_simple(405, b"already exists")
        parent = os.path.dirname(target)
        if not os.path.isdir(parent):
            return self._send_simple(409, b"parent missing")
        try:
            os.makedirs(target, exist_ok=True)
        except OSError as exc:
            return self._send_simple(500, str(exc).encode())
        self._send_simple(201, b"created")

    def do_PUT(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._deny()
        target = self._fs_path()
        if target is None:
            return self._send_simple(403, b"forbidden")
        if os.path.isdir(target):
            return self._send_simple(405, b"is a directory")

        parent = os.path.dirname(target)
        if not os.path.isdir(parent):
            try:
                os.makedirs(parent, exist_ok=True)
            except OSError as exc:
                return self._send_simple(409, str(exc).encode())

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0:
            return self._send_simple(411, b"length required")

        existed = os.path.exists(target)
        tmp = target + ".part"
        written = 0
        try:
            with open(tmp, "wb") as fh:
                remaining = length
                while remaining > 0:
                    chunk = self.rfile.read(min(CHUNK, remaining))
                    if not chunk:
                        break
                    fh.write(chunk)
                    written += len(chunk)
                    remaining -= len(chunk)
        except OSError as exc:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            return self._send_simple(500, str(exc).encode())

        if written != length:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            return self._send_simple(400, b"incomplete body")

        os.replace(tmp, target)  # 原子替换，避免半截文件被 sync 读到
        print(
            f"[dav] PUT {self.path} {written} bytes -> {'updated' if existed else 'new'}",
            file=sys.stderr,
            flush=True,
        )
        self._send_simple(201 if not existed else 204)

    def do_GET(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._deny()
        target = self._fs_path()
        if target is None:
            return self._send_simple(403, b"forbidden")
        if os.path.isdir(target):
            return self._send_simple(405, b"is a directory")
        if not os.path.isfile(target):
            return self._send_simple(404, b"not found")
        size = os.path.getsize(target)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("Last-Modified", http_date(os.path.getmtime(target)))
        self.end_headers()
        with open(target, "rb") as fh:
            while True:
                chunk = fh.read(CHUNK)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def do_HEAD(self) -> None:  # noqa: N802
        if not self._authorized():
            return self._deny()
        target = self._fs_path()
        if target is None or not os.path.isfile(target):
            return self._send_simple(404, b"not found")
        size = os.path.getsize(target)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("Last-Modified", http_date(os.path.getmtime(target)))
        self.end_headers()

    def do_DELETE(self) -> None:  # noqa: N802
        """删除收件箱里的一条（App 确认导入或丢弃后调用）。

        ⚠️ **只允许删 inbox/ 下的文件。** diary_backups 是 App 的云备份，
        删错了就等于丢数据，所以这里做硬限制：路径不在 inbox/ 里一律 403。
        """
        if not self._authorized():
            return self._deny()
        target = self._fs_path()
        if target is None:
            return self._send_simple(403, b"forbidden")

        inbox_root = os.path.join(CFG["root"], INBOX_NAME)
        # 必须严格位于 inbox/ 之内（用分隔符拼，避免 inbox_evil 这种前缀撞车）
        if not target.startswith(inbox_root + os.sep):
            return self._send_simple(403, b"only inbox items can be deleted")

        if os.path.isdir(target):
            return self._send_simple(405, b"is a directory")
        if not os.path.isfile(target):
            return self._send_simple(404, b"not found")

        try:
            os.unlink(target)
        except OSError as exc:
            return self._send_simple(500, str(exc).encode())

        print(f"[dav] DELETE {self.path}", file=sys.stderr, flush=True)
        self._send_simple(204)


def main() -> int:
    if not CFG["username"] or not CFG["password"]:
        print(
            f"[dav] 拒绝启动：{CFG_PATH} 里 auth.username / auth.password 为空",
            file=sys.stderr,
        )
        return 2
    os.makedirs(CFG["root"], exist_ok=True)
    # 收件箱：麦麦写来的日记先落这里，App 拉走确认后 DELETE 掉
    os.makedirs(os.path.join(CFG["root"], INBOX_NAME), exist_ok=True)
    httpd = ThreadingHTTPServer((CFG["host"], CFG["port"]), DavHandler)
    print(
        f"[dav] listening {CFG['host']}:{CFG['port']} prefix={CFG['prefix']} root={CFG['root']}",
        file=sys.stderr,
        flush=True,
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
