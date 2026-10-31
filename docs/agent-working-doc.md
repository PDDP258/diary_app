# Agent 工作文档 —— lad × 小记日记

> **给接手的 AI 助手看的操作手册。**
> 目标：会话被压缩、换机器、隔几天再来，**照着这份就能接着干活，不用重新踩坑**。
>
> 📌 **本文只管日记侧**（Flutter App + WebDAV / diary-mcp 两个日记服务）。
> 麦麦（MaiBot）的补丁、插件、运维脚本、排障表，**已迁到 `E:\main\work\bot\`**，
> 入口是那边的 `AGENTS.md` 与 `docs/agent-working-doc.md`。
>
> Flutter 端细节规范看 `AGENTS.md`。与本文冲突时，**先问 PD，别自己挑一条顺着走**。

最后更新：2026-10-31（麦麦部分拆出独立工作区）

---

## 0. 身份与协作方式

| 项 | 内容 |
|---|---|
| 助手代号 | **lad**（PD 起的名字） |
| 用户 | **PD**，坐标西安。**固定称呼「PD」，不要改** |
| 语言 | 简体中文 |
| 风格 | **先结论后要点，少寒暄**。PD 懂技术，不用铺垫 |
| 反馈习惯 | 精准，会直接纠正错误假设。**他纠正时先信他的现场观察，再回头查代码** |
| 「按你的想法推进」 | = 完全放权，自己拿主意并做完整闭环，不用逐步确认 |
| 验收标准 | 看**产物**，不只看「编译通过」。要确认改动真的进了最终产物 |

---

## 1. 红线（违反即事故）

1. **文档冲突先问 PD**，别挑一条顺着走。
2. **禁止硬编码颜色**，一律 `AppTheme.schemeOf(context)`（`Colors.white` 这类直接禁）。
3. **别信自己写进文档的「已完成 / 已部署」记录**，只信**当前磁盘与服务器的实际状态**。
4. **批量下载/生成脚本「自报成功」不等于落对了位置** —— 必须用权威清单独立比对。
5. **删除**：个人目录走回收站，小批量（≤10 个/批），逐批验证。
6. **同一文件一次消息里只发一个 Edit**。改多处要拆成多条消息，改完用 Grep/Read 复核落盘。
7. **不擅自放开日记工具的群聊权限**：`mcp_acl.json` 的 `allow_groups` 为空是**设计意图**
   （日记只对主人开放），放开等于让群里的人翻 PD 的日记。
8. **OCR 整体暂缓（2026-09-29 PD 决定）**：代码保留但导入菜单无入口，**重新推进前先问 PD**。

---

## 2. 两套系统（别搞混）

```
┌─ A. 小记日记 App（本仓）──────────┐        ┌─ B. 麦麦 MaiBot（另一个仓）────┐
│  Flutter 3.x / Provider / SQLite  │        │  E:\main\work\bot              │
│  E:\main\work\diary_app           │        │  服务器 203.195.219.170         │
│  AGENTS.md 管 Flutter 端规范      │        │  systemd maibot + NapCat(Docker)│
└───────────────┬──────────────────┘        └───────────────┬───────────────┘
                │                                            │
                │  ① WebDAV 云备份/收件箱                      │
                │     https://203.195.219.170/dav/             │
                │     diary_backups/  备份    inbox/  麦麦写来的日记
                │                                            │
                │  ② MCP（diary-mcp，stdio）                   │
                └────────────────────────────────────────────┘
```

- **App ↔ 麦麦只有两条通道**：WebDAV（文件）和 MCP（工具）。
- 方向性：
  - App → 云端：备份上传（`PUT diary_backups/<folder>/backup.mbk`）
  - 云端 → App：**收件箱**（`inbox/<file>.mbk`，App 确认导入后 DELETE）
  - 麦麦 → App：走 MCP 工具 `diary_write_draft`（麦麦自己写草稿 → 落 inbox/）
- **服务器上只有密文**：解密密钥 `cloud_key` 只在 App 的 `flutter_secure_storage`
  和 diary-mcp 的 `config.toml` 里。

---

## 3. 服务器速查（日记相关部分）

| 项 | 值 |
|---|---|
| 实例 | `lhins-ggb1rpzf`（**地域 `ap-guangzhou`**），Ubuntu 24.04.4 LTS，2C2G |
| 公网 IP | `203.195.219.170` |
| 日记侧目录 | `/opt/diary-mcp`（MCP 服务）、`/opt/diary-webdav`（云同步 + 收件箱） |
| systemd 服务 | `diary-webdav`（`maibot` / `nginx` 是麦麦侧的，别在这边重启） |
| WebDAV 账号 | `diary` / `4kqPcYlbMRGGRcjfOmSl` |

**本机没有 SSH 密钥**，改文件走 WebDAV + 云助手，**不要试图配 SSH**。

---

## 4. 部署通道（唯一可靠的路）

云助手 `execute_command` 有**内容过滤**：命令里出现 URL、`curl`、`ssh-ed25519`、
`docker cp`、**真实换行**之类会被 `AccessDeny` 拒掉，且不可绕过。
所以规矩是：**文件走 WebDAV 传，命令只留 `bash /path/x.sh` 这种短命令**。

### 4.1 上传（在本机执行）

```bash
curl -sS -k --noproxy '*' -u 'diary:4kqPcYlbMRGGRcjfOmSl' \
  -T <本地文件> "https://203.195.219.170/dav/_deploy/<远端名>"
```

⚠️ 坑：
- `--noproxy '*'` 的 `*` **必须带引号**，否则被 bash 展开成目录列表。
- `-T` 传本地路径给 Windows 版 curl 时，MSYS 会把 `/tmp/x` 翻译成
  `C:/Users/.../Temp/x`（找不到）。**先用 `cygpath -w` 转成 Windows 路径**。

### 4.2 回读校验（必做）

`curl -T` 覆盖写返回 **204 不代表内容变了**。必须回读比对 md5：

```bash
curl -sS -k --noproxy '*' -u 'diary:...' -o <本地临时> "https://203.195.219.170/dav/_deploy/<远端名>"
md5sum <本地临时> <本地文件>     # 两个必须一样
```

### 4.3 执行（云助手）

```
bash /opt/diary-webdav/data/_deploy/<脚本>.sh
```

### 4.4 重启顺序（日记侧）

| 场景 | 动作 |
|---|---|
| 改了 `cloud/diary-webdav/server.py` | `systemctl restart diary-webdav` |
| 改了 `cloud/diary-mcp/` | 覆盖 `/opt/diary-mcp/diary_mcp/`（**保留 config.toml 与 data/**）→ `systemctl restart maibot` |
| 改了 App（Flutter） | 正常 `flutter build` / `flutter run`，不涉及服务器 |

⚠️ 麦麦侧的 `plugins/` 与内核补丁**不在本仓**，改了要走 `E:\main\work\bot` 的流程。

---

## 5. 排障速查表（日记侧）

| 症状 | 真实原因 | 处理 |
|---|---|---|
| `flutter test` 报 `Null check operator used on a null value` | 沙箱 bash 没导出 `LOCALAPPDATA`，`package:test_core` 的 `_globalConfigPath` 空值炸 | 用 `tool/run_flutter_test.bat` |
| `flutter.bat` 报 `PowerShell executable not found` / `%PROGRAMFILES(X86)% not found` | 沙箱 PATH 缺项 | 同上，wrapper 已处理 |
| `dart analyze` 在本机必崩 | 沙箱环境问题，与代码无关 | 改用 `cmd //c "flutter.bat analyze --no-pub"` |
| `flutter analyze` 卡住 / 重写 lock | 它会隐式 `pub get` | 一律加 `--no-pub` |
| 真机 `MissingPluginException` | `--no-pub` 构建不重生成 `GeneratedPluginRegistrant.java` | 先 `flutter pub get` 再 build |
| 备份上传成功但 App 列表没变 | 云同步只认 `backup.mbk` 的 `_version` / 时间戳 | 查 `backup_manager_screen` 的列表刷新逻辑 |
| 收件箱条目不出现 | 文件名不合规 / 时间戳解析失败 | 见 §6；`DateTime.parse` **不认 RFC 1123** → 用 `HttpDate.parse` |
| 删除备份报 403 | WebDAV 只允许 DELETE `inbox/` | 设计如此，`diary_backups` 一律 403 |
| 课表小组件不刷新 / 跨天还显示昨天 | `updatePeriodMillis=0` 或 WorkManager 用了 `UPDATE` | 见 `AGENTS.md` 的「桌面小组件的刷新机制」 |

---

## 6. 收件箱协议（麦麦写日记 → App 确认）

- 目录：WebDAV 的 `inbox/`，每条一个 `.mbk` 文件，
  文件名 `draft_<YYYYMMDD-HHMMSS>_<4位hex>.mbk`（时间戳前缀让 App 一次 PROPFIND 就能排序）。
- 信封与 `backup.mbk` 同构：
  `{"_encrypted": true, "_version": 2, "kind": "diary_draft", "data": "__CLOUD__..."}`
- 密文格式：`"__CLOUD__" + base64( utf8( "<iv_b64>:<cipher_b64>" ) )`，AES-256-CBC + PKCS7，IV 随机 16 字节。
  **Python（diary-mcp）与 Dart（App）必须一模一样** —— 有双向 fixture 契约测试守着。
- **DELETE 只允许删 `inbox/` 下的文件**，`diary_backups` 一律 403（删错了等于丢数据）。
- 麦麦侧工具：`diary_write_draft`（写草稿 + 上传收件箱）、`diary_drafts`（看待确认条目）。
- App 侧入口：**数据管理 → 收件箱 → 麦麦写来的日记**（列表 + 详情 + 确认导入 / 丢弃）。
- ⚠️ **Dart 的 `DateTime.parse` 不认 RFC 1123** → 用 `HttpDate.parse`；fixture 要用服务器真实响应。

---

## 7. 文档索引

| 文档 | 内容 |
|---|---|
| `AGENTS.md` | **Flutter 端** AI 协作规范（布局、主题、命名、数据库、常见陷阱）—— 改 App 前必读 |
| `docs/project-notes.md` | 项目长期笔记（架构约定、教务导入、桌面小部件、环境坑） |
| `docs/ai-diary-architecture.md` | AI 写日记的整体架构设计 |
| `docs/course_schedule_prd.md` / `course_schedule_import_research.md` | 课表导入 PRD 与调研 |
| `docs/skills-directory.md` | 可用 skills 索引 |
| `cloud/diary-webdav/README.md` | 自建 WebDAV 服务协议与配置 |
| `cloud/diary-mcp/README.md` | diary-mcp 配置、CLI、工具说明 |
| `E:\main\work\bot\` | **麦麦的一切**（补丁 / 插件 / 运维脚本 / 服务器文档） |

### 记忆机制

- **项目记忆**：`.workbuddy/memory/MEMORY.md`（长期）+ `YYYY-MM-DD.md`（每日流水，追加式）
- **跨项目记忆**：`C:\Users\PDXX\.workbuddy\user-.../MEMORY.md`
- ⚠️ 2026-10-28 起的流水（含当时日记改动）随麦麦迁到
  `E:\main\work\bot\.workbuddy\memory\`。
- 做完实质性工作要往当日流水里追加；长期约定才进 `MEMORY.md`。

---

## 8. 改完必做的自检

```bash
# Python 侧（diary-mcp）
cd cloud/diary-mcp && python -m pytest tests/ -q          # 应 39 passed

# Flutter 侧（沙箱里必须用 wrapper）
cmd //c "tool\run_flutter_test.bat test/<文件>.dart"        # 契约测试
cmd //c "flutter.bat analyze --no-pub lib test"             # 只看新增告警

# 部署后（服务器）
bash /opt/diary-webdav/data/_deploy/verify_inbox.py        # 收件箱链路 24 项
bash /opt/diary-webdav/data/_deploy/verify_mcp_write.py     # MCP 写入链路
```

**验收不是「编译通过」**，是：
- Python 测试全绿 + Dart 测试全绿
- 服务器端到端自检全绿
- 改动**真的进了产物**（回读 md5 / 数补丁标记文件个数）
