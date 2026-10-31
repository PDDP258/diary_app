"""读取 config.toml，缺省值都能跑。"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:  # pragma: no cover - 仅 Python 3.10
    import tomli as tomllib

DEFAULT_CONFIG_NAME = "config.toml"


@dataclass
class WebdavConfig:
    url: str = ""
    username: str = ""
    password: str = ""
    # 备份根目录，App 实际写到 <remote_root>/<folder>/backup.mbk
    remote_root: str = "diary_backups"
    timeout: float = 30.0
    # 自建服务多用自签证书；App 放行自签，这里也要能关。
    # 生产环境若有正式证书，保持 True。
    verify_ssl: bool = True


@dataclass
class CryptoConfig:
    # App「云端备份密钥」的 base64。留空则只能读明文 JSON 备份。
    cloud_key: str = ""


@dataclass
class StorageConfig:
    db_path: str = "data/diary.db"
    outbox_dir: str = "data/outbox"


@dataclass
class InboxConfig:
    """收件箱：把草稿送到 App 能看到的地方。"""

    # 是否开启上传。关掉后 diary_write_draft 只写本地 outbox。
    enabled: bool = True
    # WebDAV 上的目录（相对 root）。App 侧按同一路径拉取。
    remote_dir: str = "inbox"


@dataclass
class SyncConfig:
    interval_minutes: int = 360
    # 单篇日记超过这么多字符时，写入索引前截断（防止极端长文拖慢索引）
    max_content_chars: int = 8000
    # 备份没变化就不重新下载（PROPFIND 里的 ETag / mtime+size 已足够判断）。
    # WebDAV 服务大多按月算流量，一次全量下载几 MB，天天拉很快见底。
    skip_unchanged: bool = True


@dataclass
class PrivacyConfig:
    # 是否暴露 diary_write_draft（让麦麦往草稿箱里写）。
    # 关掉后工具仍在，但调用会返回拒绝——避免模型以为工具消失了。
    enable_write: bool = True
    # 搜索命中后是否回传正文片段（False 只回标题+日期，让模型再决定要不要读全文）
    expose_snippet: bool = True


@dataclass
class AppConfig:
    base_dir: Path
    webdav: WebdavConfig = field(default_factory=WebdavConfig)
    crypto: CryptoConfig = field(default_factory=CryptoConfig)
    storage: StorageConfig = field(default_factory=StorageConfig)
    inbox: InboxConfig = field(default_factory=InboxConfig)
    sync: SyncConfig = field(default_factory=SyncConfig)
    privacy: PrivacyConfig = field(default_factory=PrivacyConfig)

    def path(self, relative: str) -> Path:
        p = Path(relative)
        return p if p.is_absolute() else (self.base_dir / p)


def _section(data: dict, name: str) -> dict:
    value = data.get(name, {})
    return value if isinstance(value, dict) else {}


def load_config(config_path: str | Path | None = None) -> AppConfig:
    """加载配置。查找顺序：显式路径 → 环境变量 → 当前目录 → 包所在目录。"""
    if config_path:
        path = Path(config_path).expanduser()
    elif os.environ.get("DIARY_MCP_CONFIG"):
        path = Path(os.environ["DIARY_MCP_CONFIG"]).expanduser()
    elif Path(DEFAULT_CONFIG_NAME).exists():
        path = Path(DEFAULT_CONFIG_NAME)
    else:
        path = Path(__file__).resolve().parent.parent / DEFAULT_CONFIG_NAME

    data: dict = {}
    if path.exists():
        with path.open("rb") as fh:
            data = tomllib.load(fh)

    # base_dir 一定要绝对：麦麦起子进程时工作目录不可控，
    # 传相对路径 -c 时 Path("config.toml").parent 就是 "."，
    # data/diary.db 会被解析到调用方的当前目录，索引永远对不上。
    base_dir = (
        path.parent.resolve()
        if path.exists()
        else Path(__file__).resolve().parent.parent
    )

    webdav_raw = _section(data, "webdav")
    webdav = WebdavConfig(
        url=str(webdav_raw.get("url", "")),
        username=str(webdav_raw.get("username", "")),
        password=str(webdav_raw.get("password", "")),
        remote_root=str(webdav_raw.get("remote_root", "diary_backups")),
        timeout=float(webdav_raw.get("timeout", 30.0)),
        verify_ssl=bool(webdav_raw.get("verify_ssl", True)),
    )
    # 环境变量优先，方便在服务器上用 secret 注入
    webdav.password = os.environ.get("DIARY_WEBDAV_PASSWORD", webdav.password)
    webdav.username = os.environ.get("DIARY_WEBDAV_USERNAME", webdav.username)

    crypto_raw = _section(data, "crypto")
    crypto = CryptoConfig(
        cloud_key=os.environ.get(
            "DIARY_CLOUD_KEY", str(crypto_raw.get("cloud_key", ""))
        )
    )

    storage_raw = _section(data, "storage")
    storage = StorageConfig(
        db_path=str(storage_raw.get("db_path", "data/diary.db")),
        outbox_dir=str(storage_raw.get("outbox_dir", "data/outbox")),
    )

    inbox_raw = _section(data, "inbox")
    inbox = InboxConfig(
        enabled=bool(inbox_raw.get("enabled", True)),
        remote_dir=str(inbox_raw.get("remote_dir", "inbox")),
    )

    sync_raw = _section(data, "sync")
    sync = SyncConfig(
        interval_minutes=int(sync_raw.get("interval_minutes", 360)),
        max_content_chars=int(sync_raw.get("max_content_chars", 8000)),
        skip_unchanged=bool(sync_raw.get("skip_unchanged", True)),
    )

    privacy_raw = _section(data, "privacy")
    privacy = PrivacyConfig(
        enable_write=bool(privacy_raw.get("enable_write", True)),
        expose_snippet=bool(privacy_raw.get("expose_snippet", True)),
    )

    return AppConfig(
        base_dir=base_dir,
        webdav=webdav,
        crypto=crypto,
        storage=storage,
        inbox=inbox,
        sync=sync,
        privacy=privacy,
    )
