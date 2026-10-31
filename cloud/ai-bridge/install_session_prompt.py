"""给「小记日记 App」这条聊天流装一段专属情景与人设。

为什么走会话级 Prompt
---------------------
麦麦的全局人设、全局记忆都不能动 —— QQ 群里的她还得是那个她。
`bot_config.toml` 的 `[[chat.reply_style.chat_prompts]]` 按
`platform + item_id + rule_type` 精确匹配，`internal/owner/private` 只命中
网页聊天室（也就是 App 走的这条流），QQ 的任何会话都匹配不到。

写入走官方接口 `PUT /api/chat/sessions/{id}/prompts`，它会用 tomlkit 改配置
并热重载，不会破坏原有格式。

用法：
    python3 install_session_prompt.py plan     # 看现状与将要写入的内容
    python3 install_session_prompt.py apply    # 写入（已有则更新）
    python3 install_session_prompt.py check    # 读回配置确认
"""

from __future__ import annotations

import json
import shutil
import sys
import time
from pathlib import Path

import httpx

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore[no-redef]

BASE = "http://127.0.0.1:8001"
WEBUI_JSON = Path("/opt/maibot/data/webui.json")
BOT_CONFIG = Path("/opt/maibot/config/bot_config.toml")

# 网页聊天室（App 走的这条流）的固定 session_id
TARGET_PLATFORM = "internal"
TARGET_ITEM_ID = "owner"

PROMPT = """你现在在小记日记 App 里，不是在 QQ，也不是在群里。对面是管理员本人，他刚写完日记，正跟你说话。
这一页只有你们两个人：他说的话不会流到别处，别处的聊天也不会带进来，所以你可以放心听。
你手边有他的日记（diary_recent / diary_search 这些）。他没提的时候别主动翻；他说"你还记得我上次说…"这种，可以去查一下。
不要提"日记 App""插件""系统""通道"这些词，就当两个人在灯下说话。
他愿意说今天的事，就顺一句；不想说就换个轻松的，别追问，也别急着分析他。
回复短，一两句，像随手写在页边。"""


def load_token() -> str:
    raw = json.loads(WEBUI_JSON.read_text(encoding="utf-8"))
    for key in ("access_token", "token", "accessToken"):
        value = raw.get(key)
        if isinstance(value, str) and value:
            return value
    raise SystemExit(f"webui.json 里没有 access_token：{list(raw)}")


def read_prompts() -> list[dict]:
    data = tomllib.loads(BOT_CONFIG.read_text(encoding="utf-8"))
    prompts = (
        data.get("chat", {})
        .get("reply_style", {})
        .get("chat_prompts", [])
    )
    return [p for p in prompts if isinstance(p, dict)]


def find_existing(entries: list[dict]) -> int | None:
    for index, entry in enumerate(entries):
        if (
            entry.get("platform") == TARGET_PLATFORM
            and str(entry.get("item_id")) == TARGET_ITEM_ID
        ):
            return index
    return None


def show(entries: list[dict]) -> None:
    print(f"当前 chat_prompts 共 {len(entries)} 条：")
    for index, entry in enumerate(entries):
        mark = "  <== 本插件目标" if (
            entry.get("platform") == TARGET_PLATFORM
            and str(entry.get("item_id")) == TARGET_ITEM_ID
        ) else ""
        text = str(entry.get("prompt", ""))[:46].replace("\n", " ")
        print(f"  [{index}] {entry.get('platform')}/{entry.get('item_id')}"
              f"/{entry.get('rule_type')}  {text}…{mark}")


async def resolve_session_id(client: httpx.AsyncClient) -> str:
    resp = await client.get("/api/chat/sessions")
    resp.raise_for_status()
    payload = resp.json()
    items = payload.get("sessions") if isinstance(payload, dict) else payload
    for item in items or []:
        if item.get("platform") == TARGET_PLATFORM:
            return str(item.get("session_id"))
    raise SystemExit("找不到 internal 会话，先在网页聊天室发一句话")


async def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "plan"
    entries = read_prompts()
    existing = find_existing(entries)

    if mode == "plan":
        show(entries)
        print(f"\n目标：{TARGET_PLATFORM}/{TARGET_ITEM_ID}/private")
        print("动作：" + ("更新已有条目" if existing is not None else "新增一条"))
        print("\n将写入：")
        print("-" * 60)
        print(PROMPT)
        print("-" * 60)
        print(f"字数 {len(PROMPT)}")
        return 0

    if mode == "check":
        show(entries)
        target = [
            e for e in entries
            if e.get("platform") == TARGET_PLATFORM and str(e.get("item_id")) == TARGET_ITEM_ID
        ]
        if not target:
            print("\n[FAIL] 没有找到 internal 的专属 Prompt")
            return 1
        same = target[0].get("prompt") == PROMPT
        print(f"\n[{'OK' if same else 'DIFF'}] 内容与脚本内定义"
              f"{'一致' if same else '不一致'}")
        return 0 if same else 1

    if mode != "apply":
        print("用法：install_session_prompt.py plan|apply|check")
        return 2

    backup = BOT_CONFIG.with_name(
        f"bot_config.toml.bak.diaryprompt-{time.strftime('%m%d%H%M')}"
    )
    shutil.copy2(BOT_CONFIG, backup)
    print(f"备份 {backup}")

    token = load_token()
    async with httpx.AsyncClient(base_url=BASE, timeout=20.0) as client:
        resp = await client.post("/api/webui/auth/verify", json={"token": token})
        if not resp.json().get("valid"):
            print("[FAIL] 认证失败")
            return 1
        session_id = await resolve_session_id(client)
        print(f"目标会话 {session_id}")

        url = f"/api/chat/sessions/{session_id}/prompts"
        params = {"index": existing} if existing is not None else None
        resp = await client.put(url, json={"prompt": PROMPT}, params=params)
        if resp.status_code >= 400:
            print(f"[FAIL] HTTP {resp.status_code} {resp.text[:300]}")
            shutil.copy2(backup, BOT_CONFIG)
            print("已还原配置")
            return 1
        print(f"[OK] 写入成功 HTTP {resp.status_code}")

    after = read_prompts()
    target = [
        e for e in after
        if e.get("platform") == TARGET_PLATFORM and str(e.get("item_id")) == TARGET_ITEM_ID
    ]
    if not target:
        print("[FAIL] 写入后读不到条目")
        return 1
    print(f"[OK] 读回确认：chat_prompts {len(entries)} -> {len(after)} 条，目标条目在位")
    print(f"[OK] 内容匹配：{target[0].get('prompt') == PROMPT}")
    return 0


if __name__ == "__main__":
    import asyncio

    raise SystemExit(asyncio.run(main()))
