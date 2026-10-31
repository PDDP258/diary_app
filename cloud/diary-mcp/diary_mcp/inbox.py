"""收件箱：把麦麦写的日记送进 App 的「待确认」列表。

为什么要有这一层
----------------
`diary_write_draft` 原来只写本机 `data/outbox/`，那是**服务器本地的一个黑洞**：
App 根本读不到，麦麦写完东西用户永远看不到。

现在改成：草稿同时用**和云备份同一把 cloud_key** 加密，PUT 到 WebDAV 的
`inbox/` 目录。App 在「数据管理 → 麦麦写来的日记」里拉到这些条目，
用户逐条「确认导入」或「丢弃」，确认后 App 会 DELETE 掉服务器上的原件。

⚠️ 为什么用和备份一样的密钥
--------------------------
服务器上**只有密文**。解密密钥 `cloud_key` 只在 App 的安全存储和
diary-mcp 的本地 config 里。这样即便服务器被攻破，也拿不到日记正文。
App 侧复用现成的 `EncryptionService.decryptWithCloudKey`，格式必须一模一样：

    "__CLOUD__" + base64( utf8( "<iv_base64>:<cipher_base64>" ) )

条目外层信封（与 backup.mbk 同构，多一个 kind 字段）：

    {
      "_encrypted": true,
      "_version": 2,
      "kind": "diary_draft",
      "data": "__CLOUD__..."
    }

解密后的内容：

    {
      "title": "...", "content": "...",
      "date": "2026-10-29", "mood": "开心",
      "created_at": "2026-10-29T12:00:00", "source": "maibot"
    }
"""

from __future__ import annotations

import json
import secrets
from datetime import datetime
from typing import Any

from .crypto import encrypt_text
from .webdav import WebdavClient, WebdavError

# 条目种类。App 侧按这个字段决定怎么渲染。
KIND_DRAFT = "diary_draft"

# 文件名里的时间戳格式，App 侧靠它排序（不需要下载就能看时间）。
STAMP_FORMAT = "%Y%m%d-%H%M%S"


class InboxError(Exception):
    """收件箱上传失败。"""


def _make_filename(created: datetime) -> str:
    """生成条目文件名。

    带时间戳前缀 → App 侧 PROPFIND 一次就能按文件名倒序排；
    带 4 位随机后缀 → 同一秒内写多条也不会撞名。
    """
    stamp = created.strftime(STAMP_FORMAT)
    return f"draft_{stamp}_{secrets.token_hex(2)}.mbk"


def build_envelope(payload: dict[str, Any], key_b64: str) -> str:
    """把草稿内容打包成可上传的密文信封（JSON 字符串）。"""
    plain = json.dumps(payload, ensure_ascii=False)
    envelope = {
        "_encrypted": True,
        "_version": 2,
        "kind": KIND_DRAFT,
        "data": encrypt_text(plain, key_b64),
    }
    return json.dumps(envelope, ensure_ascii=False)


def upload_draft(
    client: WebdavClient,
    remote_dir: str,
    key_b64: str,
    *,
    title: str,
    content: str,
    day: str,
    mood: str,
    source: str = "maibot",
) -> str:
    """加密并上传一条草稿，返回服务器上的文件名。

    失败抛 `InboxError`（底层是 `WebdavError`）。
    """
    if not key_b64:
        raise InboxError("没有配置 cloud_key，无法加密收件箱条目")

    created = datetime.now()
    payload = {
        "title": title.strip(),
        "content": content.strip(),
        "date": day,
        "mood": mood.strip(),
        "created_at": created.isoformat(timespec="seconds"),
        "source": source,
    }
    envelope = build_envelope(payload, key_b64)
    filename = _make_filename(created)
    path = f"{remote_dir.strip('/')}/{filename}"

    try:
        client.upload(path, envelope)
    except WebdavError as exc:
        raise InboxError(str(exc)) from exc

    return filename
