"""本地索引：把备份里的日记落成可检索的 SQLite。

为什么不用纯 LIKE：中文没有空格，LIKE 只能整段匹配。
这里把 CJK 文本切成双字（bigram）再喂给 FTS5，
查询同样切一遍，等于用零依赖拿到了可用的中文全文检索。
"""

from __future__ import annotations

import json
import re
import sqlite3
from dataclasses import dataclass
from datetime import date as date_cls
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Iterable

CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+")
SPACE_RE = re.compile(r"\s+")

SCHEMA = """
CREATE TABLE IF NOT EXISTS diaries (
    id          INTEGER PRIMARY KEY,
    date        TEXT NOT NULL,
    title       TEXT,
    content     TEXT,
    mood        TEXT,
    weather     TEXT,
    location    TEXT,
    favorite    INTEGER DEFAULT 0,
    tags        TEXT,
    images      TEXT,
    created_at  TEXT,
    updated_at  TEXT,
    words       INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_diaries_date ON diaries(date);
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);
CREATE VIRTUAL TABLE IF NOT EXISTS diary_fts USING fts5(
    body,
    tokenize = 'unicode61 remove_diacritics 2'
);
"""


def _bigrams(segment: str) -> list[str]:
    if len(segment) <= 1:
        return [segment]
    return [segment[i : i + 2] for i in range(len(segment) - 1)]


def index_text(text: str | None) -> str:
    """把中英混排文本变成 FTS5 友好的 token 串。"""
    if not text:
        return ""
    pieces: list[str] = []
    cursor = 0
    for match in CJK_RE.finditer(text):
        pieces.append(text[cursor : match.start()])
        pieces.extend(_bigrams(match.group()))
        cursor = match.end()
    pieces.append(text[cursor:])
    merged = " ".join(p for p in pieces if p)
    return " ".join(t for t in SPACE_RE.split(merged) if t)


def _match_expr(query: str) -> str:
    tokens = [t for t in index_text(query).split() if t]
    if not tokens:
        return ""
    # 每个 token 加引号，避免用户输入里的 - * : 被当成 FTS 语法
    return " ".join('"' + t.replace('"', '""') + '"' for t in tokens)


def _word_count(text: str | None) -> int:
    if not text:
        return 0
    return len(re.sub(r"\s+", "", text))


@dataclass
class SearchHit:
    id: int
    date: str
    title: str
    mood: str
    tags: str
    snippet: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "date": self.date,
            "title": self.title,
            "mood": self.mood,
            "tags": self.tags,
            "snippet": self.snippet,
        }


class Store:
    def __init__(self, db_path: Path | str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.executescript(SCHEMA)
        self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    # ---------- 写入 ----------

    def replace_all(self, backup: dict[str, Any], max_content_chars: int = 8000) -> int:
        """用一份完整备份覆盖本地索引，返回日记篇数。"""
        diaries = backup.get("diaries") or []
        if not isinstance(diaries, list):
            return 0

        tag_names = {}
        for tag in backup.get("tags") or []:
            if isinstance(tag, dict) and tag.get("id") is not None:
                tag_names[str(tag["id"])] = str(tag.get("name") or "")

        # App 的 Diary.toMap 里 mood_name 常常是 null（只写了 mood_id），
        # 所以这里要能用 mood_id 回查 moods 表，否则心情一律变成「未记录」。
        mood_names = {}
        for mood in backup.get("moods") or []:
            if isinstance(mood, dict) and mood.get("id") is not None:
                mood_names[str(mood["id"])] = str(mood.get("name") or "")

        by_diary: dict[str, list[str]] = {}
        for link in backup.get("diary_tags") or []:
            if not isinstance(link, dict):
                continue
            did = link.get("diary_id")
            tid = link.get("tag_id")
            if did is None or tid is None:
                continue
            name = tag_names.get(str(tid))
            if name:
                by_diary.setdefault(str(did), []).append(name)

        rows = []
        for item in diaries:
            if not isinstance(item, dict):
                continue
            did = item.get("id")
            if did is None:
                continue
            content = item.get("content") or ""
            if len(content) > max_content_chars:
                content = content[:max_content_chars]
            title = item.get("title") or ""
            tags = ",".join(sorted(set(by_diary.get(str(did), []))))
            mood_name = item.get("mood_name") or ""
            if not mood_name and item.get("mood_id") is not None:
                mood_name = mood_names.get(str(item["mood_id"]), "")
            rows.append(
                (
                    int(did),
                    str(item.get("date") or ""),
                    title,
                    content,
                    mood_name,
                    item.get("weather") or "",
                    item.get("location") or "",
                    1 if item.get("is_favorite") else 0,
                    tags,
                    item.get("images") or "",
                    item.get("created_at") or "",
                    item.get("updated_at") or "",
                    _word_count(f"{title}{content}"),
                )
            )

        with self._conn:
            self._conn.execute("DELETE FROM diaries")
            self._conn.execute("DELETE FROM diary_fts")
            self._conn.executemany(
                "INSERT INTO diaries (id, date, title, content, mood, weather, location,"
                " favorite, tags, images, created_at, updated_at, words)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                rows,
            )
            self._conn.executemany(
                "INSERT INTO diary_fts (rowid, body) VALUES (?, ?)",
                [
                    # 心情和标签也进索引：用户搜「焦虑」时，正文没写但标了焦虑标签的
                    # 日记也该命中——这是日记这种数据特有的召回来源。
                    (r[0], index_text(f"{r[2]} {r[3]} {r[4]} {r[8]}"))
                    for r in rows
                ],
            )
            self._set_meta("last_sync", datetime.now().isoformat(timespec="seconds"))
            self._set_meta("diary_count", str(len(rows)))
        return len(rows)

    def _set_meta(self, key: str, value: str) -> None:
        self._conn.execute(
            "INSERT INTO meta (key, value) VALUES (?, ?)"
            " ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )

    def set_meta(self, key: str, value: str) -> None:
        """公开版，给 sync 记录「上次下的是哪一份备份」用。"""
        with self._conn:
            self._set_meta(key, value)

    def get_meta(self, key: str, default: str = "") -> str:
        row = self._conn.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        return str(row["value"]) if row else default

    # ---------- 读取 ----------

    def count(self) -> int:
        row = self._conn.execute("SELECT COUNT(*) AS c FROM diaries").fetchone()
        return int(row["c"]) if row else 0

    def read(self, diary_id: int) -> dict[str, Any] | None:
        row = self._conn.execute("SELECT * FROM diaries WHERE id = ?", (diary_id,)).fetchone()
        return dict(row) if row else None

    def search(
        self,
        query: str,
        limit: int = 8,
        date_from: str = "",
        date_to: str = "",
        mood: str = "",
        snippet_len: int = 120,
    ) -> list[SearchHit]:
        expr = _match_expr(query)
        if not expr:
            return []

        sql = (
            "SELECT d.* FROM diary_fts f JOIN diaries d ON d.id = f.rowid"
            " WHERE diary_fts MATCH ?"
        )
        params: list[Any] = [expr]

        if date_from:
            sql += " AND d.date >= ?"
            params.append(date_from)
        if date_to:
            sql += " AND d.date <= ?"
            params.append(date_to)
        if mood:
            sql += " AND d.mood LIKE ?"
            params.append(f"%{mood}%")

        sql += " ORDER BY bm25(diary_fts), d.date DESC LIMIT ?"
        params.append(max(1, min(limit, 50)))

        try:
            rows = self._conn.execute(sql, params).fetchall()
        except sqlite3.OperationalError:
            return []

        hits: list[SearchHit] = []
        for row in rows:
            hits.append(
                SearchHit(
                    id=int(row["id"]),
                    date=str(row["date"]),
                    title=str(row["title"] or ""),
                    mood=str(row["mood"] or ""),
                    tags=str(row["tags"] or ""),
                    snippet=self._snippet(str(row["content"] or ""), query, snippet_len),
                )
            )
        return hits

    def _snippet(self, content: str, query: str, length: int) -> str:
        if not content:
            return ""
        flat = SPACE_RE.sub(" ", content)
        for token in index_text(query).split():
            pos = flat.find(token)
            if token and pos >= 0:
                start = max(0, pos - length // 3)
                return ("…" if start else "") + flat[start : start + length] + "…"
        return flat[:length] + ("…" if len(flat) > length else "")

    def by_date(self, day: str, limit: int = 10) -> list[dict[str, Any]]:
        rows = self._conn.execute(
            "SELECT id, date, title, mood, tags, content FROM diaries"
            " WHERE date = ? ORDER BY id DESC LIMIT ?",
            (day, limit),
        ).fetchall()
        return [dict(r) for r in rows]

    def on_this_day(
        self, month_day: str, limit: int = 6, exclude_date: str = ""
    ) -> list[dict[str, Any]]:
        """month_day 形如 '10-28'，返回历年同一天写过的日记。

        `exclude_date` 传今天的完整日期，用来把「今天刚写的」从「往年」里剔掉 ——
        否则「往年的今天」会显示成今天这一篇，读起来就是错的。
        """
        sql = (
            "SELECT id, date, title, mood, tags, content FROM diaries"
            " WHERE substr(date, 6, 5) = ?"
        )
        params: list[Any] = [month_day]
        if exclude_date:
            sql += " AND date <> ?"
            params.append(exclude_date)
        sql += " ORDER BY date DESC LIMIT ?"
        params.append(limit)
        rows = self._conn.execute(sql, params).fetchall()
        return [dict(r) for r in rows]

    def timeline(self, date_from: str = "", date_to: str = "", limit: int = 20) -> list[dict[str, Any]]:
        sql = "SELECT id, date, title, mood, tags, words, content FROM diaries WHERE 1=1"
        params: list[Any] = []
        if date_from:
            sql += " AND date >= ?"
            params.append(date_from)
        if date_to:
            sql += " AND date <= ?"
            params.append(date_to)
        sql += " ORDER BY date DESC, id DESC LIMIT ?"
        params.append(max(1, min(limit, 100)))
        rows = self._conn.execute(sql, params).fetchall()
        return [dict(r) for r in rows]

    def stats(self, date_from: str = "", date_to: str = "") -> dict[str, Any]:
        where, params = "WHERE 1=1", []
        if date_from:
            where += " AND date >= ?"
            params.append(date_from)
        if date_to:
            where += " AND date <= ?"
            params.append(date_to)

        rows = self._conn.execute(
            f"SELECT date, mood, words FROM diaries {where} ORDER BY date", params
        ).fetchall()
        if not rows:
            return {"count": 0, "words": 0, "days": 0, "moods": {}, "months": {}, "streak": 0}

        moods: dict[str, int] = {}
        months: dict[str, int] = {}
        total_words = 0
        days: set[str] = set()
        for row in rows:
            moods[str(row["mood"] or "未记录")] = moods.get(str(row["mood"] or "未记录"), 0) + 1
            months[str(row["date"])[:7]] = months.get(str(row["date"])[:7], 0) + 1
            total_words += int(row["words"] or 0)
            days.add(str(row["date"]))

        return {
            "count": len(rows),
            "words": total_words,
            "days": len(days),
            "moods": dict(sorted(moods.items(), key=lambda kv: -kv[1])[:8]),
            "months": dict(sorted(months.items())),
            "streak": _longest_streak(days),
        }

    # ---------- 草稿箱 ----------

    def outbox(self, outbox_dir: Path) -> Path:
        outbox_dir.mkdir(parents=True, exist_ok=True)
        return outbox_dir

    def write_draft(self, outbox_dir: Path, payload: dict[str, Any]) -> Path:
        outbox_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        path = outbox_dir / f"draft-{stamp}.json"
        body = {
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "source": "mcp",
            **payload,
        }
        path.write_text(json.dumps(body, ensure_ascii=False, indent=2), encoding="utf-8")
        return path

    def list_drafts(self, outbox_dir: Path) -> list[dict[str, Any]]:
        if not outbox_dir.exists():
            return []
        items = []
        for path in sorted(outbox_dir.glob("*.json"), reverse=True)[:50]:
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            items.append({"file": path.name, **data})
        return items


def _longest_streak(days: Iterable[str]) -> int:
    parsed = []
    for d in days:
        try:
            parsed.append(date_cls.fromisoformat(d))
        except ValueError:
            continue
    if not parsed:
        return 0
    parsed.sort()
    best = current = 1
    for prev, cur in zip(parsed, parsed[1:]):
        if cur - prev == timedelta(days=1):
            current += 1
            best = max(best, current)
        elif cur != prev:
            current = 1
    return best
