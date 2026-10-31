"""从 WebDAV 拉最新备份。

App 的上传路径是  <remote_root>/<folder>/backup.mbk，
folder 形如 backup_1a2b3c4d（按密钥哈希分机器）。
这里用 PROPFIND 列目录、按 getlastmodified 取最新那份。
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import unquote, urljoin, urlparse

import httpx

from .config import WebdavConfig

NS = {"d": "DAV:"}


class WebdavError(Exception):
    """WebDAV 访问失败。"""


@dataclass
class Entry:
    href: str
    is_dir: bool
    modified: datetime | None
    size: int = 0
    etag: str = ""

    @property
    def name(self) -> str:
        return unquote(self.href.rstrip("/").rsplit("/", 1)[-1])

    @property
    def fingerprint(self) -> str:
        """用来判断「这份备份是不是同一份」。

        ETag 优先（坚果云这类实现会给，且随内容变）；
        没有 ETag 就退回「修改时间 + 字节数」——只比时间不够，
        有些服务端在覆盖写时 mtime 精度只到秒，连续两次上传会撞上。
        """
        if self.etag:
            return f"etag:{self.etag}"
        stamp = self.modified.astimezone(timezone.utc).isoformat() if self.modified else ""
        return f"mtime:{stamp}:{self.size}"


def _int_or_zero(text: str | None) -> int:
    try:
        return int(str(text).strip())
    except (TypeError, ValueError):
        return 0


def _abs_url(base: str, href: str) -> str:
    """把相对 href 拼成绝对 URL。

    ⚠️ 必须用 urljoin，不能只拼 `scheme://netloc`：
    base 常带子路径（如 `https://host/dav/`），而相对 href 是 `diary_backups/`。
    按 netloc 硬拼会得到 `https://hostdiary_backups/` —— 主机名被粘上路径，
    报错却是 `getaddrinfo failed`，看起来像 DNS 问题，极难定位。
    """
    if href.startswith("http://") or href.startswith("https://"):
        return href
    return urljoin(base if base.endswith("/") else base + "/", href)


def _parse_modified(text: str | None) -> datetime | None:
    if not text:
        return None
    try:
        dt = parsedate_to_datetime(text)
    except (TypeError, ValueError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


class WebdavClient:
    def __init__(self, cfg: WebdavConfig):
        if not cfg.url:
            raise WebdavError("没有配置 webdav.url")
        self.cfg = cfg
        self.base = cfg.url if cfg.url.endswith("/") else cfg.url + "/"

    def _client(self) -> httpx.Client:
        return httpx.Client(
            auth=(self.cfg.username, self.cfg.password) if self.cfg.username else None,
            timeout=self.cfg.timeout,
            follow_redirects=True,
            # 自建 WebDAV 常用自签证书。App 侧 badCertificateCallback 直接放行，
            # 这里必须能用配置关掉校验，否则「App 能连、机器连不上」。
            verify=self.cfg.verify_ssl,
            # httpx 默认 trust_env=True，会读系统代理（Windows 读注册表）。
            # 本机装了代理时，连「直连 IP」也会被塞给代理，报 getaddrinfo failed。
            trust_env=False,
            headers={"User-Agent": "diary-mcp/0.1"},
        )

    def propfind(self, path: str, depth: str = "1") -> list[Entry]:
        url = _abs_url(self.base, path)
        try:
            with self._client() as client:
                resp = client.request(
                    "PROPFIND", url, headers={"Depth": depth, "Content-Type": "application/xml"}
                )
        except httpx.HTTPError as exc:
            raise WebdavError(f"连接 WebDAV 失败：{exc}") from exc

        if resp.status_code == 401:
            raise WebdavError("WebDAV 认证失败，检查用户名/应用密码")
        if resp.status_code == 404:
            raise WebdavError(f"路径不存在：{path}")
        if resp.status_code >= 400:
            raise WebdavError(f"PROPFIND {path} 返回 {resp.status_code}")

        try:
            root = ET.fromstring(resp.text)
        except ET.ParseError as exc:
            raise WebdavError(f"目录列表不是合法 XML：{exc}") from exc

        entries: list[Entry] = []
        for node in root.findall("d:response", NS):
            href = node.findtext("d:href", default="", namespaces=NS)
            if not href:
                continue
            prop = node.find("d:propstat/d:prop", NS)
            if prop is None:
                continue
            resourcetype = prop.find("d:resourcetype", NS)
            is_dir = resourcetype is not None and resourcetype.find("d:collection", NS) is not None
            modified = _parse_modified(prop.findtext("d:getlastmodified", namespaces=NS))
            entries.append(
                Entry(
                    href=_abs_url(self.base, href),
                    is_dir=is_dir,
                    modified=modified,
                    size=_int_or_zero(prop.findtext("d:getcontentlength", namespaces=NS)),
                    etag=(prop.findtext("d:getetag", namespaces=NS) or "").strip('"'),
                )
            )
        return entries

    def upload(self, path: str, content: str) -> None:
        """上传一个文本文件（收件箱条目用）。

        `path` 相对 base，例如 `inbox/20261029-1.mbk`。
        服务端会在父目录不存在时自动创建（自建 diary-webdav 就是这么做的），
        这里不再单独 MKCOL，减少一次往返。
        """
        url = _abs_url(self.base, path)
        try:
            with self._client() as client:
                resp = client.put(
                    url,
                    content=content.encode("utf-8"),
                    headers={"Content-Type": "application/octet-stream"},
                )
        except httpx.HTTPError as exc:
            raise WebdavError(f"上传失败：{exc}") from exc

        if resp.status_code == 401:
            raise WebdavError("WebDAV 认证失败，检查用户名/应用密码")
        if resp.status_code >= 400:
            raise WebdavError(f"PUT {path} 返回 {resp.status_code}")

    def list_dir(self, path: str) -> list[Entry]:
        """列出目录下的条目（收件箱列表用）。"""
        return self.propfind(path, depth="1")

    def latest_backup(self, known_fingerprint: str = "") -> tuple[str | None, Entry]:
        """返回 (备份文本, 选中的条目)。

        文本为 None 表示「这份备份和上次下过的是同一份，没重新下载」。
        判断只看 PROPFIND 里本来就有的 ETag / 修改时间 + 字节数，**不额外发请求**。
        """
        root_path = self.cfg.remote_root.strip("/") + "/"
        entries = self.propfind(root_path, depth="1")

        folders = [e for e in entries if e.is_dir and e.name.startswith("backup_")]
        if not folders:
            # 兼容旧路径：diary/backup_latest.mbk
            legacy = [e for e in entries if not e.is_dir and e.name.endswith(".mbk")]
            if legacy:
                return self._download(legacy[0], known_fingerprint)
            raise WebdavError(
                f"{root_path} 下没有找到 backup_* 目录，先在 App 里做一次云同步"
            )

        folders.sort(
            key=lambda e: e.modified or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )

        for folder in folders:
            try:
                children = self.propfind(folder.href, depth="1")
            except WebdavError as exc:
                print(f"[webdav] 跳过 {folder.name}: {exc}", file=sys.stderr)
                continue
            backups = [c for c in children if not c.is_dir and c.name == "backup.mbk"]
            if backups:
                return self._download(backups[0], known_fingerprint)

        raise WebdavError("备份目录里都没有 backup.mbk")

    def _download(self, entry: Entry, known_fingerprint: str = "") -> tuple[str | None, Entry]:
        if known_fingerprint and entry.fingerprint == known_fingerprint:
            # 文本量最大的机会就在这里：不下载 = 零流量。
            return None, entry

        try:
            with self._client() as client:
                resp = client.get(entry.href)
        except httpx.HTTPError as exc:
            raise WebdavError(f"下载备份失败：{exc}") from exc
        if resp.status_code >= 400:
            raise WebdavError(f"下载备份返回 {resp.status_code}")
        return resp.text, entry
