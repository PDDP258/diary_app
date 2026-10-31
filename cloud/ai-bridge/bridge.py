"""小记日记 · 麦麦 AI 对话桥（独立进程，不改麦麦代码）

为什么需要它
------------
App 要能「直接和麦麦对话」，但不能把麦麦 WebUI 的管理后台权限装进手机。
麦麦的 WebUI 有 418 个 API（改配置 / 删会话 / 管插件 / 读全部 QQ 记录），
把 basic auth 口令 + access_token 放进 App，等于手机丢了后台就失守。

本桥跑在麦麦同一台机器上，用 127.0.0.1 直连 WebUI 的「网页聊天室」通道
（internal chat），对外只暴露「发一句话、拿回复」一个能力。
凭据全部留在服务器，App 只拿一个专用 Bearer token。

通道已验证（2026-10-31 实测）
-----------------------------
    POST /api/webui/auth/verify {access_token}  -> maibot_session cookie
    GET  /api/webui/ws-token                    -> 60s 一次性 token
    WS   /api/webui/ws?token=...                -> {"op":"call","domain":"chat",
                                                     "method":"session.open"}
                                                -> {"op":"call","domain":"chat",
                                                     "method":"message.send"}
    <- {"op":"event","domain":"chat","event":"bot_message","data":{"content":...,
        "sender":{"is_bot":true}}}

记忆隔离（2026-10-31 实测，probe_memory_scope2.py）
--------------------------------------------------
internal 会话（session_id 3a2048f0...）在 A_memorix 全库零记录：
chat_summary_checkpoints 的 6 个 chat_id 全是 QQ 会话；
PD 在网页聊天室说过的 5 句话在 paragraphs 里 5/5 未命中。
所以日记对话不会污染 QQ 记忆，也不需要 platform 隔离补丁。

用法
----
    python3 bridge.py --config config.toml
    curl -H "Authorization: Bearer <app_token>" \
         -d '{"text":"今天有点累"}' http://127.0.0.1:8021/chat
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import httpx
import websockets
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

try:  # Python 3.11+
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore[no-redef]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s | %(message)s",
)
log = logging.getLogger("ai-bridge")


# --------------------------------------------------------------------------- #
# 配置
# --------------------------------------------------------------------------- #


@dataclass
class BridgeConfig:
    webui_base: str = "http://127.0.0.1:8001"
    webui_token_file: str = "/opt/maibot/data/webui.json"
    listen_host: str = "127.0.0.1"
    listen_port: int = 8021
    app_token: str = ""
    client_session: str = "diary-app"
    user_name: str = "小记"
    reply_quiet_seconds: float = 1.6
    reply_timeout_seconds: float = 75.0
    max_history_events: int = 400

    @classmethod
    def load(cls, path: str) -> "BridgeConfig":
        raw: dict[str, Any] = {}
        file_path = Path(path)
        if file_path.exists():
            with file_path.open("rb") as handle:
                raw = tomllib.load(handle)
        else:
            log.warning("配置文件不存在，使用默认值：%s", path)
        known = {f for f in cls.__dataclass_fields__}  # type: ignore[attr-defined]
        clean = {k: v for k, v in raw.items() if k in known}
        return cls(**clean)


# --------------------------------------------------------------------------- #
# 麦麦会话
# --------------------------------------------------------------------------- #


@dataclass
class Reply:
    text: str = ""
    events: list[dict[str, Any]] = field(default_factory=list)
    duration_ms: int = 0
    cursor: int = 0

    def payload(self) -> dict[str, Any]:
        return {
            "text": self.text,
            "duration_ms": self.duration_ms,
            "cursor": self.cursor,
            "events": [
                {"type": e.get("type"), "content": e.get("content"), "ts": e.get("timestamp")}
                for e in self.events
            ],
        }


class MaibotSession:
    """维护一条到麦麦网页聊天室的常驻 WebSocket。"""

    def __init__(self, config: BridgeConfig) -> None:
        self.config = config
        self._ws: Optional[Any] = None
        self._reader: Optional[asyncio.Task[None]] = None
        self._events: list[dict[str, Any]] = []
        self._cursor = 0
        self._opened = asyncio.Event()
        self._lock = asyncio.Lock()
        self._reconnect_lock = asyncio.Lock()

    # -- 连接 ------------------------------------------------------------- #

    def _read_access_token(self) -> str:
        raw = json.loads(Path(self.config.webui_token_file).read_text(encoding="utf-8"))
        for key in ("access_token", "token", "accessToken"):
            value = raw.get(key)
            if isinstance(value, str) and value:
                return value
        raise RuntimeError(f"webui.json 里没有 access_token，现有键：{list(raw)}")

    async def _fetch_ws_token(self) -> str:
        async with httpx.AsyncClient(base_url=self.config.webui_base, timeout=15.0) as client:
            resp = await client.post(
                "/api/webui/auth/verify", json={"token": self._read_access_token()}
            )
            body = resp.json() if resp.content else {}
            if not body.get("valid"):
                raise RuntimeError(f"访问令牌被拒：{body.get('message') or resp.status_code}")
            resp = await client.get("/api/webui/ws-token")
            ticket = resp.json()
            token = ticket.get("token")
            if not token:
                raise RuntimeError(f"未拿到 ws-token：{ticket.get('message')}")
            return token

    async def ensure_connected(self) -> None:
        if self._ws is not None and self._opened.is_set():
            return
        async with self._reconnect_lock:
            if self._ws is not None and self._opened.is_set():
                return
            await self._connect_locked()

    async def _connect_locked(self) -> None:
        if self._reader is not None:
            self._reader.cancel()
            self._reader = None
        if self._ws is not None:
            try:
                await self._ws.close()
            except Exception:  # noqa: BLE001
                pass
            self._ws = None

        self._opened.clear()
        token = await self._fetch_ws_token()
        url = f"{self.config.webui_base.replace('http', 'ws', 1)}/api/webui/ws?token={token}"
        log.info("连接麦麦 WebSocket")
        self._ws = await websockets.connect(url, max_size=16 * 1024 * 1024, open_timeout=15)
        self._reader = asyncio.create_task(self._read_loop())
        await asyncio.wait_for(self._opened.wait(), timeout=20)
        log.info("会话已就绪")

    async def _read_loop(self) -> None:
        assert self._ws is not None
        try:
            async for raw in self._ws:
                try:
                    message = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                await self._dispatch(message)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            log.warning("WebSocket 读取中断：%s", exc)
        finally:
            self._opened.clear()
            self._ws = None

    async def _dispatch(self, message: dict[str, Any]) -> None:
        op = message.get("op")
        if op == "event" and message.get("domain") == "system" and message.get("event") == "ready":
            await self._open_chat_session()
            return

        if op == "response" and message.get("id") == "open-1":
            if message.get("ok"):
                self._opened.set()
            else:
                log.error("session.open 失败：%s", message.get("error"))
            return

        if op == "event" and message.get("domain") == "chat":
            data = message.get("data") or {}
            kind = data.get("type")
            # 会话建立时的三条元事件不进缓冲
            if kind in {"session_info", "history", "system"}:
                return
            self._cursor += 1
            record = dict(data)
            record["cursor"] = self._cursor
            self._events.append(record)
            if len(self._events) > self.config.max_history_events:
                self._events = self._events[-self.config.max_history_events :]

    async def _open_chat_session(self) -> None:
        assert self._ws is not None
        await self._ws.send(
            json.dumps(
                {
                    "op": "call",
                    "id": "open-1",
                    "domain": "chat",
                    "method": "session.open",
                    "session": self.config.client_session,
                    "data": {"user_name": self.config.user_name, "restore": False},
                }
            )
        )

    # -- 对话 ------------------------------------------------------------- #

    async def ask(self, text: str, context: str = "") -> Reply:
        async with self._lock:  # 一次只跑一轮，避免会话串台
            await self.ensure_connected()
            assert self._ws is not None

            start_cursor = self._cursor
            started = time.monotonic()

            await self._ws.send(
                json.dumps(
                    {
                        "op": "call",
                        "id": f"send-{int(started * 1000)}",
                        "domain": "chat",
                        "method": "message.send",
                        "session": self.config.client_session,
                        "data": {"content": _compose(text, context)},
                    }
                )
            )

            collected: list[dict[str, Any]] = []
            last_bot_at: Optional[float] = None
            loop = asyncio.get_running_loop()
            deadline = loop.time() + self.config.reply_timeout_seconds

            while loop.time() < deadline:
                fresh = [e for e in self._events if e.get("cursor", 0) > start_cursor]
                new_bots = [e for e in fresh if e.get("type") == "bot_message"]
                if new_bots:
                    collected = new_bots
                    last_bot_at = loop.time()
                    # 有回复后，静默若干秒视为本轮结束
                    break
                await asyncio.sleep(0.15)

            if last_bot_at is not None:
                while loop.time() < deadline:
                    await asyncio.sleep(0.2)
                    fresh = [
                        e
                        for e in self._events
                        if e.get("cursor", 0) > start_cursor and e.get("type") == "bot_message"
                    ]
                    if len(fresh) > len(collected):
                        collected = fresh
                        last_bot_at = loop.time()
                    elif loop.time() - last_bot_at >= self.config.reply_quiet_seconds:
                        break

            duration_ms = int((time.monotonic() - started) * 1000)
            text_out = _join_bot_text(collected)
            if not text_out:
                log.warning("本轮无可见回复（可能被 stale 判定丢弃或模型空转）")
            return Reply(
                text=text_out, events=collected, duration_ms=duration_ms, cursor=self._cursor
            )


    async def clear_remote_history(self) -> str:
        """清空麦麦侧「内部统一聊天」的历史和内存上下文。

        走 WebUI 的 ``DELETE /api/chat/history``：它同时清数据库和 heartflow
        的内存上下文。比给麦麦发 ``/clear`` 干净——那条命令要管理员权限，
        ``internal:owner`` 会被回一句「你没有权限使用此命令」。
        """
        async with httpx.AsyncClient(base_url=self.config.webui_base, timeout=30.0) as client:
            resp = await client.post(
                "/api/webui/auth/verify", json={"token": self._read_access_token()}
            )
            cookie = (resp.headers.get("set-cookie") or "").split(";")[0]
            if not cookie:
                raise RuntimeError("verify 没有返回 cookie，无法清历史")
            resp = await client.delete("/api/chat/history", headers={"Cookie": cookie})
            body = resp.json() if resp.content else {}
        self._events.clear()
        return str(body.get("message") or "已清空")


def _compose(text: str, context: str = "") -> str:
    """把「正在看的那一页」贴在用户这句话前面。

    用中文括号做旁白而不是 ``[context]`` 这类标签：麦麦的人设是「两个人在灯下
    说话」，方括号会把整段变成结构化数据，她的回话立刻跟着变硬、变成客服腔。
    """
    page = (context or "").strip()
    if not page:
        return text
    return f"（我这一页写的是）\n{page}\n\n{text}"


def _join_bot_text(events: list[dict[str, Any]]) -> str:
    """把同一轮的多个 bot_message 合成一段，跳过纯表情包占位。"""
    parts: list[str] = []
    for event in events:
        content = str(event.get("content") or "").strip()
        if not content:
            continue
        if content.startswith("[表情包:") or content.startswith("[图片"):
            continue
        parts.append(content)
    return "\n".join(parts)


# --------------------------------------------------------------------------- #
# HTTP 接口
# --------------------------------------------------------------------------- #


class ChatRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    # App 把「用户此刻在看的那篇日记」一起带过来。
    # 带过来的好处：她不用调工具去查（一次 show_emoji_list 就要 20 秒），
    # 而且上下文里只有这一页，不会掺进别处的杂聊。
    context: str = Field(default="", max_length=4000)


class ChatResponse(BaseModel):
    ok: bool
    text: str = ""
    duration_ms: int = 0
    error: str = ""
    events: list[dict[str, Any]] = Field(default_factory=list)


def create_app(config: BridgeConfig) -> FastAPI:
    app = FastAPI(title="小记日记 · 麦麦对话桥", version="0.1.0")
    session = MaibotSession(config)

    def _auth(authorization: Optional[str]) -> None:
        if not config.app_token:
            return  # 未配置则不校验（仅限本机回环调试）
        expected = f"Bearer {config.app_token}"
        if (authorization or "").strip() != expected:
            raise HTTPException(status_code=401, detail="token 无效")

    @app.get("/health")
    async def health() -> dict[str, Any]:
        return {
            "ok": True,
            "connected": session._ws is not None and session._opened.is_set(),
            "cursor": session._cursor,
        }

    @app.post("/chat", response_model=ChatResponse)
    async def chat(
        request: ChatRequest, authorization: Optional[str] = Header(default=None)
    ) -> ChatResponse:
        _auth(authorization)
        try:
            reply = await session.ask(request.text, request.context)
        except Exception as exc:  # noqa: BLE001
            log.exception("对话失败")
            return ChatResponse(ok=False, error=str(exc))
        return ChatResponse(
            ok=bool(reply.text),
            text=reply.text,
            duration_ms=reply.duration_ms,
            error="" if reply.text else "麦麦本轮没有给出可见回复",
            events=reply.payload()["events"],
        )

    @app.post("/warmup")
    async def warmup(authorization: Optional[str] = Header(default=None)) -> dict[str, Any]:
        _auth(authorization)
        await session.ensure_connected()
        return {"ok": True}

    @app.post("/reset")
    async def reset(authorization: Optional[str] = Header(default=None)) -> dict[str, Any]:
        """把这条流的历史清空，回到「第一次说话」。

        对话聊久了麦麦那边会攒上百条上下文，每轮 prompt 涨到几万 token，
        回答要十几秒。清一次就回到几条，肉眼可见地快。
        """
        _auth(authorization)
        try:
            return {"ok": True, "message": await session.clear_remote_history()}
        except Exception as exc:  # noqa: BLE001
            log.exception("清空上下文失败")
            return {"ok": False, "error": str(exc)}

    app.state.session = session
    app.state.config = config
    return app


def main() -> int:
    import argparse

    import uvicorn

    parser = argparse.ArgumentParser(description="小记日记 · 麦麦对话桥")
    parser.add_argument("--config", default="config.toml")
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", type=int, default=None)
    args = parser.parse_args()

    config = BridgeConfig.load(args.config)
    if args.host:
        config.listen_host = args.host
    if args.port:
        config.listen_port = args.port
    if not config.app_token:
        log.warning("app_token 为空：接口不做鉴权，只应监听回环地址")

    app = create_app(config)
    log.info("监听 %s:%s", config.listen_host, config.listen_port)
    uvicorn.run(app, host=config.listen_host, port=config.listen_port, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
