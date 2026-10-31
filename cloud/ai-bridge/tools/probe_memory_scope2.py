"""只读探针 v2：交叉验证 internal 聊天流是否进入 A_memorix 记忆。

v1 已确认：
- MaiBot.db: platform='internal' 有 30 条消息、1 个 chat_session（session_id 3a2048f0...）
- A_memorix metadata.db: chat_summary_checkpoints 只有 6 个 chat_id，肉眼未见该值

本脚本做三件更硬的验证：
1. 列出 memorix 中所有「像 chat 标识」的列 + 取值集合
2. 列出 MaiBot 全部 chat_sessions（session_id / platform / user_id），逐个到 memorix 里查存在性
3. 文本级交叉：取 internal 会话的用户原话，在 paragraphs 正文里搜（前 12 条）
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

MAIBOT_DB = Path("/opt/maibot/data/MaiBot.db")
MEMORIX_DB = Path("/opt/maibot/data/a-memorix/metadata/metadata.db")

CHAT_HINTS = ("chat", "stream", "session")


def conn_ro(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(str(path), timeout=5)


def cols(conn: sqlite3.Connection, table: str) -> list[str]:
    return [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")').fetchall()]


def tables(conn: sqlite3.Connection) -> list[str]:
    return [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]


def chat_like_columns(conn: sqlite3.Connection) -> list[tuple[str, str, int]]:
    """返回 (table, column, distinct_count)，只保留名字像 chat/stream/session 且非空的列。"""
    found = []
    for table in tables(conn):
        for col in cols(conn, table):
            if not any(hint in col.lower() for hint in CHAT_HINTS):
                continue
            try:
                n = conn.execute(
                    f'SELECT COUNT(DISTINCT "{col}") FROM "{table}" WHERE "{col}" IS NOT NULL'
                ).fetchone()[0]
            except Exception:  # noqa: BLE001
                continue
            if n:
                found.append((table, col, n))
    return found


def main() -> int:
    mb = conn_ro(MAIBOT_DB)
    mx = conn_ro(MEMORIX_DB)

    print("=" * 66)
    print("[1] MaiBot 全部 chat_sessions")
    sessions = mb.execute(
        "SELECT session_id, platform, user_id, group_id, last_active_timestamp "
        "FROM chat_sessions ORDER BY last_active_timestamp DESC"
    ).fetchall()
    for sid, platform, uid, gid, ts in sessions:
        print(f"  {sid}  platform={platform:12} user={uid} group={gid}")

    internal_sids = [s[0] for s in sessions if s[1] == "internal"]
    print(f"\ninternal session_id: {internal_sids}")

    print("\n" + "=" * 66)
    print("[2] memorix 中所有 chat/stream/session 类列")
    found = chat_like_columns(mx)
    for table, col, n in found:
        print(f"\n-- {table}.{col}  (distinct={n})")
        try:
            rows = mx.execute(
                f'SELECT "{col}", COUNT(*) FROM "{table}" WHERE "{col}" IS NOT NULL '
                f'GROUP BY 1 ORDER BY 2 DESC LIMIT 12'
            ).fetchall()
        except Exception as exc:  # noqa: BLE001
            print(f"   [WARN] {exc}")
            continue
        for value, count in rows:
            mark = "  <<< 命中 internal" if str(value) in internal_sids else ""
            print(f"   {str(value)[:52]:52} {count}{mark}")

    print("\n" + "=" * 66)
    print("[3] 逐个 session_id 在 memorix 全库查存在性")
    targets = [(s[0], s[1]) for s in sessions]
    for sid, platform in targets:
        hits = []
        for table, col, _ in found:
            try:
                n = mx.execute(
                    f'SELECT COUNT(*) FROM "{table}" WHERE "{col}" = ?', (sid,)
                ).fetchone()[0]
            except Exception:  # noqa: BLE001
                continue
            if n:
                hits.append(f"{table}.{col}={n}")
        status = ", ".join(hits) if hits else "无任何记录"
        print(f"  {sid}  platform={platform:12} -> {status}")

    print("\n" + "=" * 66)
    print("[4] 文本级交叉：internal 用户原话是否进了 paragraphs")
    try:
        samples = mb.execute(
            "SELECT processed_plain_text FROM mai_messages "
            "WHERE platform='internal' AND user_id='owner' AND length(processed_plain_text)>6 "
            "ORDER BY timestamp DESC LIMIT 12"
        ).fetchall()
    except Exception as exc:  # noqa: BLE001
        print(f"   [WARN] 取 internal 消息失败：{exc}")
        samples = []

    pcols = cols(mx, "paragraphs")
    text_col = next((c for c in ("content", "text", "body", "raw_text") if c in pcols), None)
    print(f"   paragraphs 列：{pcols}")
    print(f"   正文列：{text_col}；样本数 {len(samples)}")
    if text_col:
        for (text,) in samples:
            snippet = (text or "").strip()[:24]
            if not snippet:
                continue
            try:
                n = mx.execute(
                    f'SELECT COUNT(*) FROM paragraphs WHERE "{text_col}" LIKE ?', (f"%{snippet}%",)
                ).fetchone()[0]
            except Exception as exc:  # noqa: BLE001
                print(f"   [WARN] {exc}")
                break
            mark = "命中记忆" if n else "未进记忆"
            print(f"   {mark:6} | {snippet}")

    mb.close()
    mx.close()
    print("\n完成（全程只读）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
