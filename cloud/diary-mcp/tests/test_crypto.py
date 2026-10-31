import base64
import json

import pytest
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

from diary_mcp.crypto import CLOUD_PREFIX, BackupDecryptError, decrypt_text, unwrap_backup

KEY = base64.b64encode(b"0123456789abcdef0123456789abcdef").decode()
OTHER_KEY = base64.b64encode(b"fedcba9876543210fedcba9876543210").decode()


def encrypt_like_dart(plain: str, key_b64: str, iv: bytes = b"\x00" * 16) -> str:
    """复刻 EncryptionService.encryptWithCloudKey 的输出格式。"""
    key = base64.b64decode(key_b64)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(plain.encode("utf-8")) + padder.finalize()
    encryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    cipher = encryptor.update(padded) + encryptor.finalize()
    inner = f"{base64.b64encode(iv).decode()}:" + base64.b64encode(cipher).decode()
    return CLOUD_PREFIX + base64.b64encode(inner.encode("utf-8")).decode()


def test_roundtrip_ascii():
    payload = encrypt_like_dart("hello diary", KEY)
    assert decrypt_text(payload, KEY) == "hello diary"


def test_roundtrip_chinese():
    text = "今天下了很大的雨，伞忘在实验室了。"
    assert decrypt_text(encrypt_like_dart(text, KEY), KEY) == text


def test_wrong_key_raises():
    payload = encrypt_like_dart("secret", KEY)
    with pytest.raises(BackupDecryptError):
        decrypt_text(payload, OTHER_KEY)


def test_plaintext_passthrough():
    assert decrypt_text("not encrypted", KEY) == "not encrypted"


def test_bad_key_length():
    with pytest.raises(BackupDecryptError):
        decrypt_text(encrypt_like_dart("x", KEY), base64.b64encode(b"short").decode())


def test_unwrap_envelope():
    backup = {
        "version": "1.3.0",
        "diaries": [{"id": 1, "date": "2026-10-01", "content": "国庆"}],
    }
    envelope = {
        "_encrypted": True,
        "_version": 2,
        "data": encrypt_like_dart(json.dumps(backup, ensure_ascii=False), KEY),
    }
    result = unwrap_backup(json.dumps(envelope), KEY)
    assert result["diaries"][0]["content"] == "国庆"


def test_unwrap_plain_json():
    backup = {"diaries": [{"id": 2, "date": "2026-10-02", "content": "直读"}]}
    assert unwrap_backup(json.dumps(backup), "")["diaries"][0]["id"] == 2
