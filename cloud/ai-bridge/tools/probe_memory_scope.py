"""只读探针：确认 internal / webui 聊天流是否进入长期记忆（A_memorix）。

用途
----
App 直连麦麦前必须确认「日记对话不会污染 QQ 记忆」。
本脚本只读，不改任何数据。

检查项
------
1. MaiBot.db 里有哪些表、session/message 的 platform 分布
2. A_memorix 的 metadata.db 里记录的 chat_id 集合，是否含 internal / webui
3. 输出 internal 会话的 session_id 形态（供后续白名单/隔离使用）

用法：
    python3 probe_memory_scope.py
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

MAIBOT_DB = Path("/opt/maibot/data/MaiBot.db")
MEMORIX_DB = Path("/opt/maibot/data/a-memorix/metadata/metadata.db")


def open_ro(path: Path) -> sqlite3.Connection | None:
    if not path.exists():
        print(f"[MISS] {path}")
        return None
    try:
        return sqlite3.connect(str(path), timeout=5)
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] 打开 {path} 失败：{exc}")
        return None


def list_tables(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
    return [r[0] for r in rows]


def columns(conn: sqlite3.Connection, table: str) -> list[str]:
    try:
        return [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")').fetchall()]
    except Exception:  # noqa: BLE001
        return []


def probe_maibot() -> None:
    print("=" * 62)
    print("MaiBot.db")
    conn = open_ro(MAIBOT_DB)
    if conn is None:
        return
    tables = list_tables(conn)
    print(f"表数量 {len(tables)}")
    print(", ".join(tables))

    for table in tables:
        cols = columns(conn, table)
        if "platform" not in cols:
            continue
        try:
            rows = conn.execute(
                f'SELECT platform, COUNT(*) FROM "{table}" GROUP BY platform ORDER BY 2 DESC'
            ).fetchall()
        except Exception as exc:  # noqa: BLE001
            print(f"  [WARN] {table}: {exc}")
            continue
        print(f"\n-- {table} ({', '.join(cols)})")
        for platform, count in rows:
            print(f"   platform={platform!r:20} count={count}")

        # 若表里有 internal 会话，把它的关键字段打出来
        if any(p == "internal" for p, _ in rows):
            key_cols = [
                c
                for c in ("session_id", "user_id", "group_id", "chat_id", "scope", "created_at")
                if c in cols
            ]
            if key_cols:
                sel = ", ".join(f'"{c}"' for c in key_cols)
                try:
                    detail = conn.execute(
                        f'SELECT {sel} FROM "{table}" WHERE platform=? LIMIT 5', ("internal",)
                    ).fetchall()
                    print(f"   internal 样本（{key_cols}）：")
                    for row in detail:
                        print(f"     {row}")
                except Exception as exc:  # noqa: BLE001
                    print(f"   [WARN] 取 internal 样本失败：{exc}")
    conn.close()


def probe_memorix() -> None:
    print("\n" + "=" * 62)
    print("A_memorix metadata.db")
    conn = open_ro(MEMORIX_DB)
    if conn is None:
        return
    tables = list_tables(conn)
    print(f"表数量 {len(tables)}")
    print(", ".join(tables))

    for table in tables:
        cols = columns(conn, table)
        chat_col = next(
            (c for c in ("chat_id", "chat_stream_id", "session_id", "stream_id") if c in cols), None
        )
        if chat_col is None:
            continue
        try:
            rows = conn.execute(
                f'SELECT "{chat_col}", COUNT(*) FROM "{table}" GROUP BY 1 ORDER BY 2 DESC LIMIT 20'
            ).fetchall()
        except Exception as exc:  # noqa: BLE001
            print(f"  [WARN] {table}: {exc}")
            continue
        print(f"\n-- {table}.{chat_col}（前 20）")
        for chat_id, count in rows:
            flag = ""
            if chat_id and ("internal" in str(chat_id) or "webui" in str(chat_id)):
                flag = "  <== 含 internal/webui"
            print(f"   {str(chat_id)[:60]:60} {count}{flag}")
    conn.close()


def probe_profile() -> None:
    path = Path("/opt/maibot/data/internal_chat_profile.json")
    print("\n" + "=" * 62)
    print("internal_chat_profile.json")
    if not path.exists():
        print("[MISS]")
        return
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        print(json.dumps(data, ensure_ascii=False, indent=1)[:800])
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] {exc}")


def main() -> int:
    probe_maibot()
    probe_memorix()
    probe_profile()
    print("\n完成（全程只读）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
