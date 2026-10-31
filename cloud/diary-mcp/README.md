# diary-mcp

把「小记日记」的备份变成一组 MCP 工具，让 MaiBot（麦麦）在聊天里真的能记得你写过什么。

这个服务不产生数据，也不改 App。它只做三件事：

1. 从 WebDAV 拉你 App 已经上传的加密备份；
2. 解密、建本地索引；
3. 通过 MCP 把「查日记」的能力暴露出去。

```
手机 App（AES 加密，密钥在设备）
   │  云同步
   ▼
WebDAV  diary_backups/<folder>/backup.mbk   ← 已加密的 JSON
   │  本服务定时拉取 + 解密
   ▼
SQLite 索引（FTS5 + 中文 bigram）
   │  MCP
   ▼
MaiBot ── 麦麦在聊天里调用 diary_search / diary_read / ...
```

## WebDAV 到底被用来干什么（以及流量账）

**只读，只下载一个文件，从不写入。** 具体三件事：

| 动作 | 频率 | 流量 |
|---|---|---|
| `PROPFIND` 列 `diary_backups/` 下的 `backup_*` 目录 | 每次 sync，2 个请求 | 几百字节 |
| `GET backup.mbk` | **仅当备份变了** | 一份备份的大小 |
| 上传 / 删除 / 改权限 | 从不 | 0 |

不碰 `images_*.enc`。App 里 `syncImages` 会把日记图片打成单独归档上传，那是 App 自己的上行流量，
本服务一份都不下载 —— 它只要文字。

**备份是纯文本**：`diaries.images` 存的是逗号分隔的**本地路径字符串**，不是 base64 图片。
所以 `backup.mbk` ≈ JSON 体积 × 1.33（AES + base64）。按每篇 300 字估：

| 日记篇数 | `backup.mbk` 约 | 每月下载量（每天写日记，6 小时一跑） |
|---|---|---|
| 100 篇 | 130 KB | 4 MB |
| 1000 篇 | 1.3 MB | 40 MB |
| 5000 篇 | 6.5 MB | 200 MB |

关键点：**下载量跟「跑多勤」无关，只跟「备份有多大 × 一个月里有几天真的写了」有关。**
因为内容没变就不下载 —— `sync` 会用 PROPFIND 里本来就返回的 `ETag`（没有就退回 `修改时间 + 字节数`）
和上次记在索引里的指纹比对，一致就直接跳过，一个字节都不拉。

所以 6 小时一次的计划任务在没写日记的日子是**零下载**，只有开销很小的 PROPFIND。
第一次 `sync` 会打印真实字节数，拿去算你自己的账：

```
已导入 1234 篇日记
来源：https://.../backup.mbk（1331200 字节，本次已计入下载流量）
```

不放心时用 `sync --force` 强制重下；`sync.skip_unchanged = false` 可关掉跳过逻辑。

`images_*.enc` 不下载，代价是**日记配图不进索引**（现在也不进，`diary_read` 只给文字）。

如果哪天备份涨到几十 MB，改的方向不是降低频率，而是**增量拉取**：
App 侧已有 `incremental_sync_service`，但云端上传的仍是全量快照 —— 那需要先改 App 的导出格式。

## 为什么不用 App 直连模型

App 里塞 LLM key 会重演 OCR 那条老路（密钥进 APK）。这里的做法是：
**数据留在你手里，工具跑在你自己机器上，模型只拿到被查出来的那几条。**

## 快速开始

```bash
cd cloud/diary-mcp
python -m venv .venv
.venv/Scripts/python.exe -m pip install -e .        # Windows
# .venv/bin/python -m pip install -e .              # Linux/macOS

cp config.example.toml config.toml                  # 然后填 webdav 和 cloud_key
```

`cloud_key` 从 App 里取：设置 → 云同步 → 云端备份密钥（一串 base64）。
没有它只能读明文备份，线上那份是解不开的。

```bash
# 拉备份、解密、建索引
.venv/Scripts/python.exe -m diary_mcp sync

# 先确认索引对不对
.venv/Scripts/python.exe -m diary_mcp status
.venv/Scripts/python.exe -m diary_mcp ask "焦虑"

# 起 MCP 服务（stdio，给 MaiBot 用）
.venv/Scripts/python.exe -m diary_mcp serve
```

也可以完全绕开 WebDAV，用本地文件：

```bash
.venv/Scripts/python.exe -m diary_mcp import path/to/backup.mbk --key <base64>
```

## 让索引保持新鲜

MCP 只读索引，索引得有人定时灌。`tool/sync_once.bat` 就是为计划任务写的
（绝对路径 + 输出重定向到 `data/sync.log`）：

```bat
schtasks /create /tn "diary-mcp-sync" /tr "E:\main\work\diary_app\cloud\diary-mcp\tool\sync_once.bat" /sc hourly /mo 6
```

不建计划任务也能用，只是新写的日记要等你手动 `sync` 之后才进索引。

## 接到 MaiBot

### 方式一：stdio（同一个机器，最省事）

编辑麦麦的 `config/bot_config.toml`，把空的 `servers = []` 换成
（注意：`servers = []` 和 `[[mcp.servers]]` 不能并存，TOML 会报重复定义）：

```toml
[[mcp.servers]]
name = "diary"
enabled = true
transport = "stdio"
command = "E:/main/work/diary_app/cloud/diary-mcp/.venv/Scripts/python.exe"
args = ["-m", "diary_mcp", "-c", "E:/main/work/diary_app/cloud/diary-mcp/config.toml", "serve"]
env = { PYTHONUTF8 = "1", PYTHONIOENCODING = "utf-8", PYTHONUNBUFFERED = "1" }
read_timeout_seconds = 60.0
```

三个细节都是踩过的：

- `-c` 必须写在 `serve` **前面**（argparse 的全局选项）。
- 一定要显式给 `-c`：麦麦起子进程时工作目录不可控，靠「当前目录找 config.toml」会找不到。
- `PYTHONUTF8` / `PYTHONIOENCODING` 别省。Windows 默认 GBK，JSON-RPC 里带中文会崩在管道上。

改完用这条命令验证「写进配置的这条命令」真的能连上（会按 bot_config.toml 原样起子进程）：

```bash
.venv/Scripts/python.exe tool/smoke_from_botconfig.py
```

### 方式二：HTTP（MaiBot 和日记服务分开部署）

```bash
.venv/Scripts/python.exe -m diary_mcp serve --http --host 127.0.0.1 --port 8077
```

```toml
[[mcp.servers]]
name = "diary"
enabled = true
transport = "streamable_http"
url = "http://127.0.0.1:8077/mcp"
```

跨机部署时只绑内网地址或走 Tailscale，不要直接暴露公网 —— 这个服务没有任何鉴权。

## 工具清单

| 工具 | 用途 |
|---|---|
| `diary_search` | 全文检索（中文用 bigram 切词，心情/标签也进索引） |
| `diary_read` | 按 id 读全文 |
| `diary_recent` | 最近 N 天的日记时间线 |
| `diary_on_this_day` | 历年同一天写过什么 |
| `diary_stats` | 篇数/字数/心情分布/最长连续 |
| `diary_write_draft` | 写进草稿箱，**不直接入库** |
| `diary_drafts` | 看草稿箱 |
| `diary_who_am_i` | 报告数据覆盖范围，避免模型硬答 |

工具名不加服务器前缀（MaiBot 的行为），所以统一带 `diary_` 前缀避免和别的 server 撞。

## 三条边界

1. **只读为主，写只落草稿**。AI 的产出必须经你在 App 里确认才成为日记，
   否则半年后一半的日记不是你自己写的。
2. **不复制数据到别处**。备份解出来只进本机 SQLite，不上传、不喂给任何云服务。
3. **搜索先给片段，不让模型一次吞全年**。`diary_search` 返回 120 字片段和 id，
   要看全文得再调 `diary_read`，这样既能控成本，也能让模型带着目的去读。

如果在群里试水，建议先关掉写入：

```toml
[privacy]
enable_write = false
```

## 已知限制

- **索引是全量重建**。每次 `sync` 清表重灌，几千篇以内没问题；上万篇再改成增量。
- **只有日记 / 心情 / 标签**。云备份目前就这三类，速记、课表、自言自语还没进去。
- **没有向量检索**。先靠 FTS5 + bigram 打底，语义搜索等 `sync` 链路稳定再加。
- **`diary.content` 若在 App 侧改过加密方式**，这里会解密失败。改动 `EncryptionService`
  的格式时要同步改 `crypto.py`。

## 测试

```bash
.venv/Scripts/python.exe -m pytest -q
.venv/Scripts/python.exe tool/smoke_mcp.py              # 起一次 stdio，逐个调工具
.venv/Scripts/python.exe tool/smoke_from_botconfig.py   # 按 bot_config.toml 里那条命令连
```

`smoke_mcp.py` 不 mock 协议层，用官方客户端走一遍 initialize / list_tools / call_tool。
`smoke_from_botconfig.py` 更狠一点：它直接读 `bot_config.toml` 里的 command/args/env，
并且故意把工作目录设成临时目录，用来证明「麦麦在任意 cwd 下起这个进程也能连上」——
相对路径解析曾经在这里翻过车。
