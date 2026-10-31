#!/opt/maibot-venv/bin/python3
"""用真实 MCP stdio 客户端调一次 diary_write_draft，验证「模型写日记」这条路。

比直接调模块更接近真实：走的是麦麦拉起 diary_mcp 子进程的那条路
（同样的 command / args / env），走完再看 inbox/ 里有没有落文件。
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import tomllib

sys.path.insert(0, "/opt/diary-mcp")

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

DAV_ROOT = tomllib.load(open("/opt/diary-webdav/config.toml", "rb"))["storage"]["root"]
INBOX = os.path.join(DAV_ROOT, "inbox")


async def main() -> int:
    before = set(os.listdir(INBOX)) if os.path.isdir(INBOX) else set()

    params = StdioServerParameters(
        command="/opt/maibot-venv/bin/python3",
        args=["-m", "diary_mcp", "-c", "/opt/diary-mcp/config.toml", "serve"],
        env={
            "PYTHONPATH": "/opt/diary-mcp",
            "PYTHONUTF8": "1",
            "PYTHONIOENCODING": "utf-8",
            "PYTHONUNBUFFERED": "1",
            "PATH": "/usr/bin:/bin",
            "HOME": "/root",
        },
    )

    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            tools = await session.list_tools()
            names = [t.name for t in tools.tools]
            print(f"工具数：{len(names)}")
            print(f"工具列表：{', '.join(names)}")
            assert "diary_write_draft" in names, "缺少 diary_write_draft"
            assert "diary_drafts" in names, "缺少 diary_drafts"

            res = await session.call_tool(
                "diary_write_draft",
                {
                    "title": "MCP 链路自检",
                    "content": "通过真实 MCP stdio 调用写进来的收件箱条目。\n第二行：emoji 🌧️ 也在。",
                    "day": "2026-10-29",
                    "mood": "平静",
                },
            )
            text = res.content[0].text
            print(f"write_draft 返回：{text}")
            payload = json.loads(text)
            assert payload.get("ok") is True, f"写入失败：{payload}"
            assert payload.get("inbox_file"), f"没有拿到 inbox_file：{payload}"

            res2 = await session.call_tool("diary_drafts", {"limit": 5})
            drafts = json.loads(res2.content[0].text)
            print(f"drafts 待确认数：{drafts.get('pending_count')}")
            print(f"drafts 待确认文件名：{[p['file'] for p in drafts.get('pending', [])]}")
            assert payload["inbox_file"] in [p["file"] for p in drafts.get("pending", [])]

    after = set(os.listdir(INBOX))
    new = sorted(after - before)
    print(f"inbox 新增文件：{new}")
    assert new, "inbox 目录没有新增文件"

    # 导出**真实**的 PROPFIND 响应，给 Dart 侧的解析器当 fixture。
    # App 侧最怕的就是「自己造 XML 测自己」——服务器真正吐出来的格式才算数。
    dav = tomllib.load(open("/opt/diary-webdav/config.toml", "rb"))
    auth = dav.get("auth", {})
    prefix = "/" + str(dav.get("server", {}).get("prefix", "/dav")).strip("/")
    import httpx

    with httpx.Client(
        auth=(auth["username"], auth["password"]), timeout=30, trust_env=False
    ) as c:
        resp = c.request(
            "PROPFIND",
            f"http://127.0.0.1:8010{prefix}/inbox/",
            headers={"Depth": "1", "Content-Type": "application/xml"},
            content=(
                '<?xml version="1.0"?>'
                '<d:propfind xmlns:d="DAV:">'
                "<d:prop><d:displayname/><d:getcontentlength/>"
                "<d:getlastmodified/><d:resourcetype/></d:prop>"
                "</d:propfind>"
            ),
        )
    fixture = "/opt/diary-webdav/data/_deploy/inbox_propfind_real.xml"
    with open(fixture, "w", encoding="utf-8") as fh:
        fh.write(resp.text)
    print(f"真实 PROPFIND 响应已存到 {fixture}（{len(resp.text)} 字节）")
    print(resp.text)

    # 清理自检条目，别留脏数据给 App
    for name in new:
        os.unlink(os.path.join(INBOX, name))
    print(f"已清理 {len(new)} 个自检文件")
    print("=== MCP 链路自检通过 ===")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
