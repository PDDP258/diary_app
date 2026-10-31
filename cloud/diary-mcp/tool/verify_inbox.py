#!/opt/maibot-venv/bin/python3
"""收件箱链路端到端自检（部署后跑一次）。

覆盖：
1. diary-mcp 用 cloud_key 加密后 PUT 到 WebDAV 的 inbox/
2. App 侧要做的三件事：PROPFIND 列目录、GET 拉内容、DELETE 删原件
3. 密文格式与 Dart 侧 EncryptionService 完全一致（同一把 cloud_key 能解开）
4. 删除守卫：只有 inbox/ 下的文件能删，diary_backups 一律 403
"""

from __future__ import annotations

import json
import os
import sys
import tomllib

sys.path.insert(0, "/opt/diary-mcp")

import httpx

from diary_mcp.config import load_config
from diary_mcp.crypto import decrypt_text
from diary_mcp.inbox import upload_draft
from diary_mcp.webdav import WebdavClient

PASS = 0
FAIL = 0


def check(name: str, cond: bool, extra: str = "") -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name} {extra}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name} {extra}")


def main() -> int:
    dav = tomllib.load(open("/opt/diary-webdav/config.toml", "rb"))
    auth = dav.get("auth", {})
    storage = dav.get("storage", {})
    prefix = "/" + str(dav.get("server", {}).get("prefix", "/dav")).strip("/")
    dav_root = storage.get("root", "/opt/diary-webdav/data")
    local_base = f"http://127.0.0.1:8010{prefix}/"

    cfg = load_config("/opt/diary-mcp/config.toml")
    print(f"公网 WebDAV 地址：{cfg.webdav.url}")
    print(f"本地 WebDAV 地址：{local_base}")
    print(f"收件箱目录：{cfg.inbox.remote_dir}（enabled={cfg.inbox.enabled}）")
    print()

    print("### 1) 上传一条收件箱条目（走公网地址 = App 走的同一条路）")
    client = WebdavClient(cfg.webdav)
    title = "部署自检：今天的雨"
    content = "这是一条由部署自检写入的收件箱条目。\n带换行、带中文、带 emoji 🌧️。"
    filename = upload_draft(
        client,
        cfg.inbox.remote_dir,
        cfg.crypto.cloud_key,
        title=title,
        content=content,
        day="2026-10-29",
        mood="平静",
    )
    print(f"  上传返回：{filename}")
    check("上传返回文件名", filename.endswith(".mbk"), filename)
    check(
        "文件名带时间戳前缀",
        filename.startswith("draft_"),
        filename,
    )
    disk = os.path.join(dav_root, cfg.inbox.remote_dir, filename)
    check("文件落到磁盘 inbox/", os.path.isfile(disk), disk)

    print()
    print("### 2) PROPFIND 列目录（App 列表页靠这个）")
    with httpx.Client(auth=(auth["username"], auth["password"]), timeout=30, trust_env=False) as c:
        resp = c.request(
            "PROPFIND",
            f"{local_base}{cfg.inbox.remote_dir}/",
            headers={"Depth": "1", "Content-Type": "application/xml"},
        )
        check("PROPFIND 返回 207", resp.status_code == 207, str(resp.status_code))
        check("列表里能看到刚上传的文件", filename in resp.text)
        check("带上了 getcontentlength", "getcontentlength" in resp.text)

        print()
        print("### 3) GET 拉内容 + 解密（App 详情页靠这个）")
        resp = c.get(f"{local_base}{cfg.inbox.remote_dir}/{filename}")
        check("GET 返回 200", resp.status_code == 200, str(resp.status_code))
        envelope = json.loads(resp.text)
        check("信封 _encrypted=true", envelope.get("_encrypted") is True)
        check("信封 _version=2", envelope.get("_version") == 2)
        check("信封 kind=diary_draft", envelope.get("kind") == "diary_draft")
        data = envelope.get("data", "")
        check("data 是 __CLOUD__ 密文", data.startswith("__CLOUD__"))
        check("密文里没有明文", "今天的雨" not in resp.text)

        plain = decrypt_text(data, cfg.crypto.cloud_key)
        payload = json.loads(plain)
        check("用同一把 cloud_key 能解开", True)
        check("标题对得上", payload.get("title") == title, payload.get("title", ""))
        check("正文完整（含换行与 emoji）", payload.get("content") == content)
        check("日期对得上", payload.get("date") == "2026-10-29")
        check("心情对得上", payload.get("mood") == "平静")
        check("来源标记为 maibot", payload.get("source") == "maibot")

        print()
        print("### 4) DELETE 收件箱条目（App 确认导入/丢弃后调）")
        resp = c.delete(f"{local_base}{cfg.inbox.remote_dir}/{filename}")
        check("DELETE 返回 204", resp.status_code == 204, str(resp.status_code))
        check("磁盘上已删除", not os.path.exists(disk))

        print()
        print("### 5) 删除守卫：别的目录一律 403")
        resp = c.delete(f"{local_base}diary_backups/__guard_probe__.tmp")
        check("删 diary_backups 被拒（403）", resp.status_code == 403, str(resp.status_code))
        resp = c.delete(f"{local_base}inbox_evil/x.mbk")
        check("删 inbox_evil 被拒（403）", resp.status_code == 403, str(resp.status_code))
        resp = c.delete(f"{local_base}{cfg.inbox.remote_dir}/")
        check("删整个 inbox 目录被拒（403）", resp.status_code == 403, str(resp.status_code))

        print()
        print("### 6) 未认证不能删")
        with httpx.Client(timeout=30, trust_env=False) as anon:
            resp = anon.delete(f"{local_base}{cfg.inbox.remote_dir}/whatever.mbk")
            check("无认证 DELETE 返回 401", resp.status_code == 401, str(resp.status_code))

    print()
    print(f"=== 自检结束：通过 {PASS}，失败 {FAIL} ===")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
