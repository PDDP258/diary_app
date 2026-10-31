"""按麦麦的真实配置连一次。

单测只证明逻辑对，smoke_mcp.py 只证明服务能起；这个脚本证明的是
**「写进 bot_config.toml 的那条命令」确实能连上**——包括 -c 参数位置、
env、以及从任意工作目录启动时 `-m diary_mcp` 还能不能导入。

    .venv/Scripts/python.exe tool/smoke_from_botconfig.py
    .venv/Scripts/python.exe tool/smoke_from_botconfig.py --config <bot_config.toml> --name diary
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import tempfile
from pathlib import Path

import tomllib
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

DEFAULT_BOT_CONFIG = Path("E:/main/work/maibot/my-maibot/config/bot_config.toml")


def pick_server(config_path: Path, name: str) -> dict:
    with config_path.open("rb") as fh:
        data = tomllib.load(fh)
    servers = data.get("mcp", {}).get("servers") or []
    if not servers:
        raise SystemExit(f"{config_path} 里没有 [[mcp.servers]]")
    for server in servers:
        if server.get("name") == name:
            return server
    names = ", ".join(str(s.get("name")) for s in servers)
    raise SystemExit(f"找不到名为 {name} 的服务器，现有：{names}")


async def run(server: dict) -> int:
    env = dict(os.environ)
    env.update({str(k): str(v) for k, v in (server.get("env") or {}).items()})

    params = StdioServerParameters(
        command=server["command"],
        args=[str(a) for a in server.get("args", [])],
        env=env,
        # 故意不设 cwd：麦麦起子进程时的工作目录不可控，
        # 这里就用「任意目录」验证 -m diary_mcp 是否真的装进了那个 venv。
        cwd=tempfile.gettempdir(),
    )
    print(f"命令：{params.command}")
    print(f"参数：{params.args}")
    print(f"cwd ：{params.cwd}\n")

    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            print("✓ 握手成功")

            tools = await session.list_tools()
            names = [t.name for t in tools.tools]
            print(f"✓ 工具 {len(names)} 个：{', '.join(names)}\n")

            failed = 0
            for tool, args in (
                ("diary_who_am_i", {}),
                ("diary_stats", {"period": "all"}),
                ("diary_search", {"query": "焦虑"}),
            ):
                if tool not in names:
                    print(f"✗ {tool} 未注册")
                    failed += 1
                    continue
                result = await session.call_tool(tool, args)
                text = "".join(getattr(b, "text", "") for b in result.content)
                try:
                    preview = json.dumps(json.loads(text), ensure_ascii=False)[:240]
                except json.JSONDecodeError:
                    preview = text[:240]
                bad = getattr(result, "isError", False)
                failed += 1 if bad else 0
                print(f"{'✗' if bad else '✓'} {tool} → {preview}\n")

            return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(DEFAULT_BOT_CONFIG))
    parser.add_argument("--name", default="diary")
    args = parser.parse_args()
    return asyncio.run(run(pick_server(Path(args.config), args.name)))


if __name__ == "__main__":
    sys.exit(main())
