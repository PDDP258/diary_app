"""解密小记日记的云端备份。

对应 Dart 侧 `EncryptionService.encryptWithCloudKey` / `decryptWithCloudKey`：

    "__CLOUD__" + base64( utf8( "<iv_base64>:<cipher_base64>" ) )

- 算法：AES-256-CBC，PKCS7 填充
- 密钥：App 里生成的 cloud_backup_key_v1（base64，32 字节）
- IV：每次随机 16 字节，随密文一起存

注意 `__CLOUD__` 是 9 个字符，Dart 侧有一条注释专门强调过这点，
这里用 len(PREFIX) 而不是硬编码下标。
"""

from __future__ import annotations

import base64
import json
import os
from typing import Any

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

CLOUD_PREFIX = "__CLOUD__"


class BackupDecryptError(Exception):
    """备份解密失败。"""


class BackupEncryptError(Exception):
    """备份加密失败。"""


def _load_key(key_b64: str) -> bytes:
    clean = "".join(key_b64.split())
    if not clean:
        raise BackupDecryptError("云端备份密钥为空")
    try:
        key = base64.b64decode(clean, validate=True)
    except Exception as exc:  # noqa: BLE001
        raise BackupDecryptError(f"密钥不是合法的 base64：{exc}") from exc
    if len(key) not in (16, 24, 32):
        raise BackupDecryptError(f"密钥长度不合法：{len(key)} 字节（应为 16/24/32）")
    return key


def decrypt_text(payload: str, key_b64: str) -> str:
    """解密单条 __CLOUD__ 密文；非密文原样返回。"""
    if not payload.startswith(CLOUD_PREFIX):
        return payload

    key = _load_key(key_b64)

    try:
        decoded = base64.b64decode(payload[len(CLOUD_PREFIX) :])
        inner = decoded.decode("utf-8")
        iv_b64, cipher_b64 = inner.split(":", 1)
    except Exception as exc:  # noqa: BLE001
        raise BackupDecryptError(f"密文信封格式不对：{exc}") from exc

    try:
        iv = base64.b64decode(iv_b64)
        cipher_bytes = base64.b64decode(cipher_b64)
    except Exception as exc:  # noqa: BLE001
        raise BackupDecryptError(f"IV/密文 base64 解码失败：{exc}") from exc

    if len(iv) != 16:
        raise BackupDecryptError(f"IV 长度不合法：{len(iv)} 字节")

    decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    padded = decryptor.update(cipher_bytes) + decryptor.finalize()

    unpadder = padding.PKCS7(128).unpadder()
    try:
        plain = unpadder.update(padded) + unpadder.finalize()
    except ValueError as exc:
        raise BackupDecryptError("解密后填充校验失败，密钥可能不匹配") from exc

    return plain.decode("utf-8")


def encrypt_text(payload: str, key_b64: str) -> str:
    """加密成与 Dart 侧 `EncryptionService.encryptWithCloudKey` 完全一致的格式。

    收件箱（inbox/）里的条目要由 App 用同一把 cloud_key 解密，
    所以格式必须一模一样：

        "__CLOUD__" + base64( utf8( "<iv_base64>:<cipher_base64>" ) )

    - 算法：AES-256-CBC，PKCS7 填充
    - IV：每次随机 16 字节，随密文一起存
    """
    if not payload:
        return payload

    key = _load_key(key_b64)

    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(payload.encode("utf-8")) + padder.finalize()

    encryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    cipher = encryptor.update(padded) + encryptor.finalize()

    inner = f"{base64.b64encode(iv).decode()}:{base64.b64encode(cipher).decode()}"
    return CLOUD_PREFIX + base64.b64encode(inner.encode("utf-8")).decode()


def unwrap_backup(raw: str, key_b64: str) -> dict[str, Any]:
    """把一个 backup.mbk 的文本内容还原成备份字典。

    WebDAV 上的 backup.mbk 长这样：

        {"_encrypted": true, "_version": 2, "data": "__CLOUD__..."}

    `data` 解出来才是真正的备份 JSON（diaries / moods / tags / diary_tags ...）。
    也兼容直接给明文 JSON 的情况，方便本地调试。
    """
    try:
        outer = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise BackupDecryptError(f"备份不是合法 JSON：{exc}") from exc

    if not isinstance(outer, dict):
        raise BackupDecryptError("备份顶层不是对象")

    if "diaries" in outer:
        return outer

    envelope = outer.get("data")
    if not isinstance(envelope, str):
        raise BackupDecryptError("备份缺少 data 字段")

    plain = decrypt_text(envelope, key_b64)
    try:
        inner = json.loads(plain)
    except json.JSONDecodeError as exc:
        raise BackupDecryptError(f"解密后的内容不是合法 JSON：{exc}") from exc

    if not isinstance(inner, dict):
        raise BackupDecryptError("解密后的备份顶层不是对象")
    return inner
