#!/usr/bin/env python3
"""生成一份「App 格式」的加密云端备份，用来模拟手机上传。

用途：在没有真实手机同步的情况下，端到端验证
    生成密文 → PUT 到 WebDAV → diary-mcp 拉取解密 → 建索引

加密格式与 Dart 侧 `EncryptionService.encryptWithCloudKey` 完全一致：
    "__CLOUD__" + base64( utf8( "<iv_base64>:<cipher_base64>" ) )
AES-256-CBC + PKCS7，密钥 32 字节随机。

用法：
    python tool/make_fake_backup.py <输出文件>
输出：
    stdout 打印 cloud_key（base64）与对应的 backup_<hash> 目录名
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
from datetime import date, timedelta

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

CLOUD_PREFIX = "__CLOUD__"


def encrypt(raw: str, key: bytes) -> str:
    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(raw.encode("utf-8")) + padder.finalize()
    enc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    ct = enc.update(padded) + enc.finalize()
    inner = f"{base64.b64encode(iv).decode()}:{base64.b64encode(ct).decode()}"
    return CLOUD_PREFIX + base64.b64encode(inner.encode("utf-8")).decode()


def build_backup() -> dict:
    today = date.today()
    rows = [
        (
            "组会开到十点",
            "组会开到十点，老师让我重做实验。心里很烦，感觉自己什么都没做出来。",
            "焦虑",
            1,
        ),
        (
            "在图书馆待了一天",
            "在图书馆待了一天，把第三章看完了，比想象中顺利，晚上吃了碗面。",
            "平静",
            2,
        ),
        (
            "跑步",
            "晚上跑了五公里，出了一身汗，脑子清醒了很多。",
            "愉快",
            3,
        ),
    ]
    diaries = []
    for idx, (title, content, mood, back) in enumerate(rows, start=1):
        d = today - timedelta(days=back)
        diaries.append(
            {
                "id": idx,
                "date": d.isoformat(),
                "title": title,
                "content": content,
                "mood_name": mood,
                "weather": "晴",
                "location": "西安",
                "images": "",
                "is_encrypted": 0,
                "created_at": f"{d.isoformat()} 21:00:00",
                "updated_at": f"{d.isoformat()} 21:00:00",
            }
        )
    return {
        "version": 1,
        "exported_at": f"{today.isoformat()}T12:00:00Z",
        "diaries": diaries,
        "moods": [],
        "tags": [],
        "diary_tags": [],
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: python tool/make_fake_backup.py <输出文件>", file=sys.stderr)
        return 2
    out = sys.argv[1]

    key = os.urandom(32)
    key_b64 = base64.b64encode(key).decode()
    folder = "backup_" + hashlib.sha256(key_b64.encode("utf-8")).hexdigest()[:8]

    backup = build_backup()
    # 与 Dart 侧 uploadBackup 的顺序一致：
    #   1) 对原始数据算 sha256 得到 _hash
    #   2) 加 _encrypted
    #   3) 整体加密成 __CLOUD__...
    #   4) 外面再包一层 {_encrypted, _version, data}
    raw = json.dumps(backup, ensure_ascii=False, separators=(",", ":"))
    data = dict(backup)
    data["_hash"] = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    data["_encrypted"] = True

    inner = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    envelope = encrypt(inner, key)
    outer = json.dumps(
        {"_encrypted": True, "_version": 2, "data": envelope},
        ensure_ascii=False,
        separators=(",", ":"),
    )
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(outer)

    print(f"cloud_key = {key_b64}")
    print(f"folder    = {folder}")
    print(f"inner_bytes = {len(inner)}  file_bytes = {len(outer)}  -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
