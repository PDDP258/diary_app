"""命令行入口。

    python -m diary_mcp sync                 # 从 WebDAV 拉最新备份并重建索引
    python -m diary_mcp import backup.mbk    # 用本地文件重建索引
    python -m diary_mcp ask "毕业设计"        # 终端里试一下检索效果
    python -m diary_mcp status               # 看索引状态
    python -m diary_mcp serve                # 起 MCP（stdio，给 MaiBot 用）
    python -m diary_mcp serve --http         # 起 MCP（HTTP，给远程 MaiBot 用）
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .config import load_config
from .crypto import BackupDecryptError, unwrap_backup
from .store import Store
from .webdav import WebdavClient, WebdavError


def _err(message: str) -> int:
    print(f"错误：{message}", file=sys.stderr)
    return 1


def cmd_sync(args: argparse.Namespace) -> int:
    cfg = load_config(args.config)
    if not cfg.crypto.cloud_key:
        return _err("没有配置 crypto.cloud_key（App → 云同步 → 导出云端备份密钥）")

    store = Store(cfg.path(cfg.storage.db_path))
    try:
        known = ""
        if cfg.sync.skip_unchanged and not args.force:
            known = store.get_meta("last_backup_fp", "")

        try:
            text, entry = WebdavClient(cfg.webdav).latest_backup(known)
        except WebdavError as exc:
            return _err(str(exc))

        if text is None:
            print(f"备份没有变化，跳过下载：{entry.name}（{entry.size} 字节）")
            print(f"上次同步：{store.get_meta('last_sync', '从未')}")
            return 0

        try:
            backup = unwrap_backup(text, cfg.crypto.cloud_key)
        except BackupDecryptError as exc:
            return _err(f"解密失败：{exc}")

        count = store.replace_all(backup, cfg.sync.max_content_chars)
        store.set_meta("last_backup_fp", entry.fingerprint)
        store.set_meta("last_backup_size", str(entry.size))
        store.set_meta("last_backup_href", entry.href)
    finally:
        store.close()

    print(f"已导入 {count} 篇日记")
    print(f"来源：{entry.href}（{entry.size} 字节，本次已计入下载流量）")
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    cfg = load_config(args.config)
    path = Path(args.file).expanduser()
    if not path.exists():
        return _err(f"文件不存在：{path}")

    key = args.key or cfg.crypto.cloud_key
    try:
        backup = unwrap_backup(path.read_text(encoding="utf-8"), key)
    except (BackupDecryptError, UnicodeDecodeError) as exc:
        return _err(f"解析失败：{exc}")

    store = Store(cfg.path(cfg.storage.db_path))
    count = store.replace_all(backup, cfg.sync.max_content_chars)
    store.close()
    print(f"已导入 {count} 篇日记 ← {path.name}")
    return 0


def cmd_ask(args: argparse.Namespace) -> int:
    cfg = load_config(args.config)
    store = Store(cfg.path(cfg.storage.db_path))
    if store.count() == 0:
        store.close()
        return _err("索引是空的，先跑一次 sync 或 import")

    hits = store.search(args.query, limit=args.limit)
    print(f"命中 {len(hits)} 条\n")
    for hit in hits:
        head = hit.title or hit.snippet[:20]
        print(f"[{hit.id}] {hit.date}  {head}")
        if hit.mood:
            print(f"     心情：{hit.mood}")
        if hit.snippet:
            print(f"     {hit.snippet}")
        print()
    store.close()
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    cfg = load_config(args.config)
    store = Store(cfg.path(cfg.storage.db_path))
    print(f"数据库：{cfg.path(cfg.storage.db_path)}")
    print(f"日记数：{store.count()}")
    print(f"上次同步：{store.get_meta('last_sync', '从未')}")
    size = store.get_meta("last_backup_size", "")
    if size:
        print(f"上次下载：{int(size):,} 字节（这份算过一次下载流量）")
    data = store.stats()
    if data["count"]:
        print(f"时间跨度：{store.timeline(limit=100000)[-1]['date']} → "
              f"{store.timeline(limit=1)[0]['date']}")
        print(f"总字数：{data['words']}")
        print(f"最长连续：{data['streak']} 天")
        if data["moods"]:
            print("心情分布：" + "，".join(f"{k} {v}" for k, v in data["moods"].items()))
    print(f"草稿箱：{cfg.path(cfg.storage.outbox_dir)}")
    store.close()
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    cfg = load_config(args.config)
    from .server import build_server

    mcp = build_server(cfg)

    if args.http:
        try:
            mcp.settings.host = args.host
            mcp.settings.port = args.port
        except AttributeError:
            pass
        print(f"HTTP 模式：http://{args.host}:{args.port}/mcp", file=sys.stderr)
        mcp.run(transport="streamable-http")
    else:
        mcp.run(transport="stdio")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="diary_mcp", description="小记日记 MCP 服务")
    parser.add_argument("-c", "--config", help="config.toml 路径")
    sub = parser.add_subparsers(dest="command")

    p_sync = sub.add_parser("sync", help="从 WebDAV 拉最新备份")
    p_sync.add_argument(
        "--force", action="store_true", help="即使备份没变化也重新下载（正常不需要）"
    )
    p_sync.set_defaults(func=cmd_sync)

    p_import = sub.add_parser("import", help="从本地备份文件导入")
    p_import.add_argument("file")
    p_import.add_argument("--key", help="云端备份密钥（缺省用 config 里的）")
    p_import.set_defaults(func=cmd_import)

    p_ask = sub.add_parser("ask", help="终端里试检索")
    p_ask.add_argument("query")
    p_ask.add_argument("--limit", type=int, default=8)
    p_ask.set_defaults(func=cmd_ask)

    sub.add_parser("status", help="索引状态").set_defaults(func=cmd_status)

    p_serve = sub.add_parser("serve", help="启动 MCP 服务")
    p_serve.add_argument("--http", action="store_true", help="用 streamable-http 而不是 stdio")
    p_serve.add_argument("--host", default="127.0.0.1")
    p_serve.add_argument("--port", type=int, default=8077)
    p_serve.set_defaults(func=cmd_serve)

    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        parser.print_help()
        return 0
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
