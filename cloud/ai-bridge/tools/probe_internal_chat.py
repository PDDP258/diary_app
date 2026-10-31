"""端到端验证：从服务器本机走 WebUI 统一 WebSocket，向「网页聊天室」投一句话，
看能否收到麦麦的真正回复。

为什么走 127.0.0.1
------------------
本机直连 8001 端口，不需要 nginx basic auth，也不需要公网暴露。
这条验证只回答一个问题：**internal chat 通道能不能拿到麦麦的回复**。
（记忆隔离已由 probe_memory_scope2.py 证实：internal 会话在 A_memorix 全库零记录）

流程
----
POST /api/webui/auth/verify {access_token}  -> 种下 maibot_session cookie
GET  /api/webui/ws-token                    -> 60s 一次性 token
WS   /api/webui/ws?token=...                -> {"op":"call","domain":"chat","method":"session.open"}
                                            -> {"op":"call","domain":"chat","method":"message.send"}
                                            -> 收 domain=chat 的事件

用法：
    python3 probe_internal_chat.py ["要发的话"]
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

import httpx
import websockets

BASE_HTTP = "http://127.0.0.1:8001"
WS_URL = "ws://127.0.0.1:8001/api/webui/ws"
WEBUI_JSON = Path("/opt/maibot/data/webui.json")
CLIENT_SESSION = "probe-app-1"
WAIT_SECONDS = 60


def load_access_token() -> str:
    raw = json.loads(WEBUI_JSON.read_text(encoding="utf-8"))
    for key in ("access_token", "token", "accessToken"):
        value = raw.get(key)
        if isinstance(value, str) and value:
            return value
    raise SystemExit(f"webui.json 里找不到 access_token，现有键：{list(raw)}")


def brief(obj: object, limit: int = 260) -> str:
    text = json.dumps(obj, ensure_ascii=False) if not isinstance(obj, str) else obj
    return text if len(text) <= limit else text[:limit] + "…"


async def main() -> int:
    text = sys.argv[1] if len(sys.argv) > 1 else "在吗，随便聊两句"

    async with httpx.AsyncClient(base_url=BASE_HTTP, timeout=15.0) as client:
        resp = await client.post("/api/webui/auth/verify", json={"token": load_access_token()})
        payload = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
        print(f"[1] verify  status={resp.status_code} valid={payload.get('valid')}")
        if not payload.get("valid"):
            print(f"    body={brief(payload)}")
            return 1

        resp = await client.get("/api/webui/ws-token")
        ticket = resp.json()
        print(f"[2] ws-token success={ticket.get('success')} expires_in={ticket.get('expires_in')}")
        ws_token = ticket.get("token")
        if not ws_token:
            print(f"    body={brief(ticket)}")
            return 1

    url = f"{WS_URL}?token={ws_token}"
    print(f"[3] 连接 {WS_URL}")
    async with websockets.connect(url, max_size=16 * 1024 * 1024, open_timeout=15) as ws:
        # 1) 等 ready
        try:
            first = json.loads(await asyncio.wait_for(ws.recv(), timeout=10))
            print(f"[4] 首帧 {brief(first, 180)}")
        except asyncio.TimeoutError:
            print("[4] 未收到 ready 帧（继续）")

        # 2) 打开会话
        await ws.send(json.dumps({
            "op": "call", "id": "open-1", "domain": "chat", "method": "session.open",
            "session": CLIENT_SESSION,
            "data": {"user_name": "探针", "restore": False},
        }))
        deadline = asyncio.get_event_loop().time() + 10
        while asyncio.get_event_loop().time() < deadline:
            raw = await asyncio.wait_for(ws.recv(), timeout=10)
            msg = json.loads(raw)
            if msg.get("id") == "open-1" and ("ok" in msg or "error" in msg):
                print(f"[5] session.open ok={msg.get('ok')} error={brief(msg.get('error'))}")
                break
            print(f"    (open 期间) {brief(msg, 160)}")

        # 3) 发消息
        print(f"[6] 发送：{text}")
        await ws.send(json.dumps({
            "op": "call", "id": "send-1", "domain": "chat", "method": "message.send",
            "session": CLIENT_SESSION,
            "data": {"content": text},
        }))

        # 4) 收集事件直到出现 bot 消息
        bot_texts: list[str] = []
        loop = asyncio.get_event_loop()
        deadline = loop.time() + WAIT_SECONDS
        while loop.time() < deadline:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=max(1.0, deadline - loop.time()))
            except asyncio.TimeoutError:
                break
            msg = json.loads(raw)
            domain = msg.get("domain")
            event = msg.get("event")
            data = msg.get("data") or {}
            if msg.get("id") == "send-1":
                print(f"[7] message.send 回执 ok={msg.get('ok')}")
                continue
            if domain != "chat":
                print(f"    (其它) domain={domain} event={event}")
                continue
            etype = data.get("type")
            sender = data.get("sender") or {}
            content = str(data.get("content") or data.get("raw_content") or "")
            print(f"[8] chat event={event} type={etype} is_bot={sender.get('is_bot')} "
                  f"len={len(content)}  {content[:120]!r}")
            if sender.get("is_bot") or etype in {"bot_message", "assistant_message"}:
                if content:
                    bot_texts.append(content)

        print("\n" + "=" * 60)
        if bot_texts:
            print(f"收到 {len(bot_texts)} 条麦麦回复：")
            for item in bot_texts:
                print(f"  - {item[:200]}")
            print("\n结论：internal chat 通道可用 ✅")
            return 0
        print("未收到 bot 消息 ❌")
        return 2


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
