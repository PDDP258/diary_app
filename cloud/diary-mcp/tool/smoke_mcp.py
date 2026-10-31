"""冒烟测试：用官方 MCP 客户端真的连一次 stdio 服务。

不 mock、不跳过协议层——就是要证明麦麦那样连能连上、工具能被列出、
调用能返回数据。跑法：

    .venv/Scripts/python.exe tool/smoke_mcp.py
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import tempfile
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from diary_mcp.store import Store  # noqa: E402

SAMPLE = {
    "diaries": [
        {
            "id": 1,
            "date": "2026-03-12",
            "title": "投简历",
            "content": "投了七份简历，只有一家回信，面试问了很多算法题，晚上没睡好。",
            "mood_name": "焦虑",
            "is_favorite": 0,
        },
        {
            "id": 2,
            "date": "2026-03-15",
            "title": "拿到 offer",
            "content": "面试过了，回头看那几天焦虑有点多余。",
            "mood_name": "开心",
            "is_favorite": 1,
        },
        {
            "id": 3,
            "date": "2025-10-28",
            "title": "去年的这个时候",
            "content": "在准备考研，每天六点起，图书馆三楼靠窗那个位置。",
            "mood_name": "平静",
            "is_favorite": 0,
        },
    ],
    "tags": [{"id": "t1", "name": "求职"}],
    "diary_tags": [{"diary_id": 1, "tag_id": "t1"}],
}


def prepare(tmp: Path) -> Path:
    db = tmp / "diary.db"
    store = Store(db)
    store.replace_all(SAMPLE)
    store.close()

    config = tmp / "config.toml"
    config.write_text(
        f"""
[storage]
db_path = "{db.as_posix()}"
outbox_dir = "{(tmp / 'outbox').as_posix()}"

[privacy]
enable_write = true
expose_snippet = true
""".strip(),
        encoding="utf-8",
    )
    return config


async def run(config: Path) -> int:
    env = dict(os.environ)
    env["DIARY_MCP_CONFIG"] = str(config)
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"

    params = StdioServerParameters(
        command=sys.executable,
        args=["-m", "diary_mcp", "serve"],
        env=env,
        cwd=str(ROOT),
    )

    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            tools = await session.list_tools()
            names = [t.name for t in tools.tools]
            print(f"工具 {len(names)} 个：{', '.join(names)}\n")

            checks = [
                ("diary_who_am_i", {}),
                ("diary_search", {"query": "焦虑"}),
                ("diary_stats", {"period": "all"}),
                ("diary_on_this_day", {"month_day": "10-28"}),
                ("diary_write_draft", {"title": "测试", "content": "草稿箱联通性"}),
            ]
            failed = 0
            for name, args in checks:
                if name not in names:
                    print(f"✗ {name} 未注册")
                    failed += 1
                    continue
                result = await session.call_tool(name, args)
                text = "".join(
                    getattr(block, "text", "") for block in result.content
                )
                try:
                    parsed = json.loads(text)
                    preview = json.dumps(parsed, ensure_ascii=False)[:220]
                except json.JSONDecodeError:
                    preview = text[:220]
                mark = "✗" if getattr(result, "isError", False) else "✓"
                if mark == "✗":
                    failed += 1
                print(f"{mark} {name} → {preview}\n")

            outbox = config.parent / "outbox"
            drafts = list(outbox.glob("*.json")) if outbox.exists() else []
            print(f"草稿箱落盘：{len(drafts)} 个文件")
            return 1 if failed else 0


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="diary-mcp-smoke-") as tmpdir:
        config = prepare(Path(tmpdir))
        return asyncio.run(run(config))


if __name__ == "__main__":
    raise SystemExit(main())
