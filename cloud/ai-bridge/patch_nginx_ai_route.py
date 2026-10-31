"""给 nginx 加 /ai/ 反代（免 basic auth），指向本机 ai-bridge。

只改 /etc/nginx/conf.d/maibot.conf 的 server 块，插在 `location /` 之前。
改完自己跑 nginx -t，失败则还原。
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from pathlib import Path

TARGET = Path("/etc/nginx/conf.d/maibot.conf")
ANCHOR = "    location / {"
MARKER = "location /ai/"

BLOCK = """    # AI 对话桥：App 直连，走自己的 Bearer token，不需要 basic auth
    location /ai/ {
        auth_basic off;
        proxy_pass http://127.0.0.1:8021/;
        proxy_http_version 1.1;
        proxy_set_header Host              $http_host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 150s;
        proxy_send_timeout 150s;
        proxy_buffering    off;
    }

"""


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    text = TARGET.read_text(encoding="utf-8")

    if mode == "check":
        if MARKER in text:
            print("[OK] /ai/ 反代已在位")
            return 0
        print("[OK] 未安装，锚点存在" if ANCHOR in text else "[MISS] 找不到 location / 锚点")
        return 0 if ANCHOR in text else 1

    if mode == "install":
        if MARKER in text:
            print("[SKIP] 已存在")
            return 0
        if ANCHOR not in text:
            print("[FAIL] 锚点缺失，拒绝修改")
            return 1
        backup = TARGET.with_name(f"maibot.conf.bak.aibridge-{time.strftime('%m%d%H%M')}")
        shutil.copy2(TARGET, backup)
        patched = text.replace(ANCHOR, BLOCK + ANCHOR, 1)
        compile_ok = patched.count("{") == patched.count("}")
        if not compile_ok:
            print(f"[FAIL] 大括号不配对 {patched.count('{')} vs {patched.count('}')}")
            return 1
        TARGET.write_text(patched, encoding="utf-8")
        test = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
        if test.returncode != 0:
            shutil.copy2(backup, TARGET)
            print(f"[FAIL] nginx -t 不通过，已还原：{test.stderr.strip()[:300]}")
            return 1
        reload_result = subprocess.run(["systemctl", "reload", "nginx"], capture_output=True, text=True)
        print(f"[OK] 已写入并 reload rc={reload_result.returncode} 备份={backup}")
        return 0

    if mode == "uninstall":
        if MARKER not in text:
            print("[SKIP] 未安装")
            return 0
        backup = TARGET.with_name(f"maibot.conf.bak.aibridge-rm-{time.strftime('%m%d%H%M')}")
        shutil.copy2(TARGET, backup)
        start = text.index("    # AI 对话桥")
        end = text.index(ANCHOR, start)
        TARGET.write_text(text[:start] + text[end:], encoding="utf-8")
        subprocess.run(["nginx", "-t"], check=False)
        subprocess.run(["systemctl", "reload", "nginx"], check=False)
        print(f"[OK] 已移除 备份={backup}")
        return 0

    print("用法：patch_nginx_ai_route.py check|install|uninstall")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
