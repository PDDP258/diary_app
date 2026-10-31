"""MCP 工具层：把日记暴露成麦麦能调用的工具。

设计约束（踩过的坑，别改）：
1. stdio 模式下 stdout 只能走 JSON-RPC，所有日志必须写 stderr。
2. 工具名不加服务器前缀，MaiBot 会原样交给模型，所以统一用 diary_ 开头避免撞名。
3. 工具描述要写"什么时候该用"，planner 靠它决定调不调。
4. 写操作只落草稿箱，绝不直接改日记库——AI 的产出必须经人确认。
"""

from __future__ import annotations

import json
import sys
import threading
from datetime import date, datetime, timedelta
from typing import Any

from mcp.server.fastmcp import FastMCP

from .config import AppConfig
from .store import Store


def _log(message: str) -> None:
    print(f"[diary-mcp] {message}", file=sys.stderr)


def _json(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False)


def _period_range(period: str) -> tuple[str, str]:
    today = date.today()
    p = (period or "month").lower()
    if p in ("week", "7d"):
        start = today - timedelta(days=7)
    elif p in ("month", "30d"):
        start = today - timedelta(days=30)
    elif p in ("year", "365d"):
        start = today - timedelta(days=365)
    elif p in ("all", ""):
        return "", ""
    else:
        return "", ""
    return start.isoformat(), today.isoformat()


def build_server(cfg: AppConfig) -> FastMCP:
    mcp = FastMCP("diary")
    lock = threading.Lock()
    state: dict[str, Store | None] = {"store": None}

    def store() -> Store:
        with lock:
            if state["store"] is None:
                state["store"] = Store(cfg.path(cfg.storage.db_path))
            return state["store"]

    @mcp.tool()
    def diary_search(
        query: str,
        date_from: str = "",
        date_to: str = "",
        mood: str = "",
        limit: int = 6,
    ) -> str:
        """在用户的历史日记里做全文检索。

        什么时候用：用户问「我以前写过 XX 吗」「我是什么时候开始做某事的」
        「我之前对某件事怎么想的」这类需要翻旧账的问题。

        参数：
        - query：关键词，可以空格分隔多个词（中文也支持）
        - date_from / date_to：可选，格式 YYYY-MM-DD
        - mood：可选，按心情过滤（如「开心」「焦虑」）
        - limit：返回条数，默认 6

        返回命中的日记 id、日期、标题、心情、标签和正文片段。
        片段只是线索，需要看全文时再调 diary_read。
        """
        hits = store().search(
            query, limit=limit, date_from=date_from, date_to=date_to, mood=mood
        )
        if not cfg.privacy.expose_snippet:
            for h in hits:
                h.snippet = ""
        return _json(
            {
                "total": len(hits),
                "hint": "" if hits else "没有命中，换个说法或放宽日期试试",
                "items": [h.as_dict() for h in hits],
            }
        )

    @mcp.tool()
    def diary_read(diary_id: int) -> str:
        """按 id 读取一篇日记的完整内容。

        先 diary_search 拿到 id，再调这里看全文。一次只读一篇，
        不要为了回答一个问题把整年的日记都读一遍。
        """
        row = store().read(diary_id)
        if not row:
            return _json({"ok": False, "error": f"没有 id={diary_id} 的日记"})
        row.pop("words", None)
        return _json({"ok": True, "diary": row})

    @mcp.tool()
    def diary_recent(days: int = 14, limit: int = 10) -> str:
        """列出最近 N 天的日记标题和时间线。

        什么时候用：用户问「我最近怎么样」「这周发生了什么」「帮我总结一下最近」。
        返回按日期倒序的列表，含每条的字数，方便判断哪几篇值得细读。
        """
        start = (date.today() - timedelta(days=max(1, days))).isoformat()
        rows = store().timeline(date_from=start, limit=limit)
        for r in rows:
            content = str(r.pop("content", "") or "")
            r["preview"] = content[:80] + ("…" if len(content) > 80 else "")
        return _json({"ok": True, "days": days, "total": len(rows), "items": rows})

    @mcp.tool()
    def diary_on_this_day(month_day: str = "") -> str:
        """查「历史上的今天」：历年同一天写过的日记。

        什么时候用：用户问「去年今天我在干嘛」「往年的这个时候」。
        month_day 留空表示今天，格式 MM-DD。
        """
        md = month_day or date.today().strftime("%m-%d")
        rows = store().on_this_day(md, exclude_date=date.today().isoformat())
        for r in rows:
            content = str(r.pop("content", "") or "")
            r["preview"] = content[:100] + ("…" if len(content) > 100 else "")
        return _json({"ok": True, "month_day": md, "total": len(rows), "items": rows})

    @mcp.tool()
    def diary_stats(period: str = "month") -> str:
        """统计一段时间的写作情况：篇数、字数、写了多少天、心情分布、最长连续天数。

        什么时候用：用户问「我这个月写了多少」「我最近心情怎么样」
        「我坚持得如何」。period 可选 week / month / year / all。
        注意：心情分布来自用户手选的标签，不代表模型推断的情绪。
        """
        start, end = _period_range(period)
        data = store().stats(date_from=start, date_to=end)
        data.update({"ok": True, "period": period or "month", "from": start, "to": end})
        return _json(data)

    @mcp.tool()
    def diary_write_draft(
        title: str,
        content: str,
        day: str = "",
        mood: str = "",
    ) -> str:
        """把一段内容写进「待确认草稿箱」，不会直接成为日记。

        什么时候用：聊天里聊出了值得记下来的东西（今天发生的事、一个想法、
        一次复盘），用户明确表示想记下来时。不要主动往里塞东西。

        写进去之后必须告诉用户「已放进草稿箱，需要你在 App 里确认」。
        day 格式 YYYY-MM-DD，留空表示今天。
        """
        if not cfg.privacy.enable_write:
            return _json({"ok": False, "error": "当前配置关闭了写入"})
        if not content.strip():
            return _json({"ok": False, "error": "content 不能为空"})

        target_day = day or date.today().isoformat()
        title_text = title.strip()

        # 1. 本地 outbox：留个底，万一上传失败也知道写过什么
        target = cfg.path(cfg.storage.outbox_dir)
        path = store().write_draft(
            target,
            {
                "title": title_text,
                "content": content.strip(),
                "date": target_day,
                "mood": mood.strip(),
            },
        )
        _log(f"draft written: {path}")

        # 2. 收件箱：上传到 WebDAV，App 才能看到
        result: dict[str, Any] = {
            "ok": True,
            "file": path.name,
            "date": target_day,
        }

        if not cfg.inbox.enabled:
            result["message"] = "已放入草稿箱（收件箱已关闭，用户暂时看不到）"
            return _json(result)

        try:
            from .inbox import upload_draft
            from .webdav import WebdavClient

            filename = upload_draft(
                WebdavClient(cfg.webdav),
                cfg.inbox.remote_dir,
                cfg.crypto.cloud_key,
                title=title_text,
                content=content,
                day=target_day,
                mood=mood,
            )
            _log(f"inbox uploaded: {filename}")
            result["inbox_file"] = filename
            result["message"] = (
                "已放进草稿箱，需要你在 App 的「数据管理 → 麦麦写来的日记」里确认"
            )
        except Exception as exc:  # noqa: BLE001
            # 上传失败**不能**让整个调用失败：草稿已经落本地了
            _log(f"inbox upload failed: {exc}")
            result["ok"] = False
            result["error"] = f"收件箱上传失败：{exc}"
            result["message"] = (
                "已放入本地草稿箱，但同步到 App 失败，请检查 diary-mcp 的 WebDAV 配置"
            )

        return _json(result)

    @mcp.tool()
    def diary_drafts(limit: int = 10) -> str:
        """查看草稿箱里还没确认的条目。

        除了本地 outbox，也会列出已经送到 App 收件箱、但用户还没确认的条目
        （文件名带时间戳，`pending` 表示用户那边还没处理）。
        """
        items = store().list_drafts(cfg.path(cfg.storage.outbox_dir))[:limit]

        pending: list[dict[str, Any]] = []
        if cfg.inbox.enabled and cfg.webdav.url:
            try:
                from .webdav import WebdavClient

                root = cfg.inbox.remote_dir.strip("/") + "/"
                entries = WebdavClient(cfg.webdav).list_dir(root)
                for entry in entries:
                    if entry.is_dir or not entry.name.endswith(".mbk"):
                        continue
                    pending.append(
                        {
                            "file": entry.name,
                            "size": entry.size,
                            "modified": entry.modified.isoformat() if entry.modified else "",
                        }
                    )
                pending.sort(key=lambda x: x["file"], reverse=True)
                pending = pending[:limit]
            except Exception as exc:  # noqa: BLE001
                _log(f"inbox list failed: {exc}")

        return _json(
            {
                "ok": True,
                "total": len(items),
                "items": items,
                "pending_count": len(pending),
                "pending": pending,
            }
        )

    @mcp.tool()
    def diary_who_am_i() -> str:
        """报告这份日记数据的覆盖范围：总篇数、最早和最晚日期、最近同步时间。

        什么时候用：用户问的问题可能超出数据范围时，先用这个确认有没有得答；
        也可以用来回答「你记得我多少事」。
        """
        s = store()
        rows = s.timeline(limit=1)
        first = s._conn.execute(
            "SELECT date FROM diaries ORDER BY date ASC LIMIT 1"
        ).fetchone()
        last = s._conn.execute(
            "SELECT date FROM diaries ORDER BY date DESC LIMIT 1"
        ).fetchone()
        return _json(
            {
                "ok": True,
                "count": s.count(),
                "first_date": str(first["date"]) if first else "",
                "last_date": str(last["date"]) if last else "",
                "last_sync": s.get_meta("last_sync", ""),
                "latest_title": rows[0]["title"] if rows else "",
                "now": datetime.now().isoformat(timespec="seconds"),
            }
        )

    return mcp
