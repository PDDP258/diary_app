# 日记 × AI 接入架构（规划稿）

> 状态：**规划阶段，未部署**。麦麦处于生产使用中，本文档不含任何对生产环境的改动。
> 最后更新：2026-10-28

## 一句话结论

**手机写日记 → PUT 到自己的云服务器（加密备份）→ 本机 diary-mcp 拉取解密建索引 → 麦麦通过 stdio 调 8 个工具。**
云服务器只当「信封」，明文日记只落在 PD 自己的电脑上。

## 一、现状盘点

### 服务器（腾讯云 Lighthouse，广州 4 区）

| 项 | 值 |
|---|---|
| 实例 | `lhins-ggb1rpzf` / Ubuntu 24.04.4 / 2 核 2 GB |
| 公网 | 203.195.219.170（内网 10.1.0.16） |
| 磁盘 | 50 GB，已用 5.9 GB（13%） |
| 内存 | 已用 619 MB，**available 1348 MB**，swap 1987 MB 未动 |
| 流量 | 300 GB/月，已用 782 MB（0.26%） |
| 带宽 | 出方向 4 Mbps |
| 到期 | **2026-11-20（手动续费）** |
| 已跑服务 | **已清空（2026-10-28）**，仅剩系统服务 + nginx（无站点、无 80 服务块） |
| 可用端口 | **全部空闲**，规划 8010 |
| 归档 | `/root/_archive_20261028-1255/services.tar.gz`（95 MB，原四服务代码+数据库+nginx/systemd 配置） |

### App 侧（`cloud_sync_service.dart`）

云同步只发 6 种请求，地址栏自由填，无域名白名单：

| 方法 | 用途 | 行号 |
|---|---|---|
| `PROPFIND` Depth 0 | 测连接 | 356 |
| `PROPFIND` Depth 1 | 列目录 | 597 / 836 / 1643 |
| `MKCOL` | 建目录 | 614 |
| `PUT` | 传 backup.mbk / images_*.enc | 519 / 1038 |
| `GET` | 下载 | 677 / 741 / 1093 |
| Basic Auth | 认证 | 360 等 |

其他关键事实：
- `_serverUrl` 用户可填，支持 `http://` 前缀补全（338 行）；
- `badCertificateCallback => true` —— **自签证书可用**；
- 保存日记后自动同步（`write_diary_screen.dart:619`），条件是「已登录 + 自动同步开」；
- 备份正文**明文**，外层 `__CLOUD__` 信封是 AES-256-CBC；
- `images` 字段存的是本地路径字符串，图片单独走 `images_<ts>.enc`。

### 已建代码（`cloud/`）

| 目录 | 内容 | 状态 |
|---|---|---|
| `diary-mcp/` | 8 个 MCP 工具 + 索引 + WebDAV 客户端 | 27 测试绿，stdio 实测通过 |
| ~~`maibot-plugin-diary/`~~ | 麦麦插件（3 个命令） | **已迁到 `E:\main\work\bot\maibot-plugin-diary\`** |
| 已部署 | `my-maibot/plugins/diary-recall/` | 源码在 cloud/，用 `deploy.py` 同步 |

## 二、架构定案

```
┌─ 手机 App ──────────────────────────────────────┐
│  写完日记 → 自动同步 → PUT 加密备份              │
└────────────────────┬────────────────────────────┘
                     │ HTTPS/HTTP + Basic
                     ▼
┌─ 云服务器 203.195.219.170 ──────────────────────┐
│  nginx :80  ── /dav/ ──> 127.0.0.1:8010         │
│                              │                   │
│                              ▼                   │
│  /opt/diary-webdav/  (WebDAV 子集，~150 行)      │
│  └─ data/diary_backups/<folder>/backup.mbk      │
│     └─ 只存密文，密钥不在服务器上                 │
└────────────────────┬────────────────────────────┘
                     │ GET（每小时 / 手动）
                     ▼
┌─ 本机 Windows（E:\main\work） ──────────────────┐
│  diary-mcp（venv）                               │
│  ├─ 解密 → SQLite + FTS5 索引（本机 data/diary.db）│
│  └─ stdio                                        │
│       ▲                                          │
│       │                                          │
│  麦麦 my-maibot                                  │
│  └─ 插件 /drecall /drecall today /drecall brief  │
└──────────────────────────────────────────────────┘
```

**关键点：服务器上没有明文，也没有解密密钥。** `cloud_key` 只存在本机
`cloud/diary-mcp/config.toml`。服务器被攻破最多拿到密文备份。

## 三、四个关键取舍

### 1. 不用坚果云，用自己的服务器
App 说的「WebDAV」是协议不是服务商。服务器实现 6 个 verb 就能被 App 直接使用，
Dart 一行不用改（只改地址栏）。收益：不受 1 GB 配额、不经过第三方、300 GB 月流量基本用不完。

### 2. 索引放本机，不放手服务器
- **隐私**：解密后的全文只在自己电脑上；
- **依赖**：麦麦本来就在本机，索引跟着它走，少一跳网络；
- **成本**：索引 5000 篇约 60–80 MB，本机磁盘无压力，服务器 42 GB 也够但没必要占。

### 3. 麦麦不迁服务器
- 服务器已跑 4 个服务，2 GB 内存加麦麦（Python + 插件运行时 + 向量）会吃紧；
- 麦麦在生产使用中，迁移风险大于收益；
- 服务器只跑一个极轻的 WebDAV 进程（常驻约 30–40 MB）。

### 4. MCP 走 stdio，不走 HTTP
`mcp` 支持 `streamable_http`，但 PD 那份配置的 transport 支持情况未验证；
stdio 已用官方客户端实测通过（8 工具注册、5 次调用成功）。
**能验证的东西不做假设。**

## 四、阶段计划

| 阶段 | 做什么 | 验收标准 | 触碰生产？ |
|---|---|---|---|
| **M0** 检索验证 | 用现有坚果云备份跑通 `sync` + 检索 | `status` 篇数不为 0；问「焦虑」能命中 | 否，纯本机 |
| **M1** 换数据源 | ✅ **服务端已部署并全链路验证**；剩 App 改地址栏 + 填真实 `cloud_key` | 手机上点同步，服务器出现真实 `backup.mbk` | 是，只加新服务 |
| **M2** 接麦麦 | 填 `bot_config.toml`，重启麦麦 | WebUI 出现插件；`/drecall brief` 能回 | 是，改麦麦配置 |
| **M3** 自动化 | 本机计划任务每小时 sync + 每日简报 | 隔天开机看到今天的课 + 昨天没做完的 | 否 |

**顺序不能反。** M0 是判据：如果检索出来的东西没用，M1 之后全是白做。

## 五、M1 实施细节（待执行）

### 服务器侧

```
/opt/diary-webdav/
├── venv/               # python3 -m venv
├── server.py           # WebDAV 子集：PROPFIND/MKCOL/PUT/GET/DELETE + Basic
├── data/               # 落盘目录
└── config.toml         # 用户名 / 密码 / 路径白名单
```

- systemd unit `diary-webdav.service`，`--host 127.0.0.1 --port 8010`（**不对外**，只走 nginx）
- 参照现有 `/opt/poke-server` 的模式（venv + systemd + nginx 反代）

### nginx（关键参数，别漏）

```nginx
location /dav/ {
    proxy_pass http://127.0.0.1:8010/;
    client_max_body_size 256m;      # ⚠️ 默认 1m，图片包必 413
    proxy_read_timeout 300s;
    proxy_request_buffering off;
    # PROPFIND/MKCOL/PUT/GET/DELETE 默认均转发，无需额外声明
}
```

- `client_max_body_size` 是**最容易踩的坑**：默认 1 MB，图片归档一定超
- 原 `poke` 站点已删除，`sites-enabled` 为空 —— 直接新建 `diary` 站点即可，不与任何现有配置冲突

### App 侧

设置 → 云同步 → 服务器地址改 `http://203.195.219.170/dav/`，填服务器上设的账号密码。
备份文件夹名会按 `cloud_key` 派生，服务器侧不需要预建目录（`MKCOL` 会建）。

### 部署结果（2026-10-28 已完成）

| 项 | 实际值 |
|---|---|
| 服务 | `/opt/diary-webdav/server.py`（337 行，纯标准库，零 PyPI 依赖） |
| 进程 | `diary-webdav.service`，监听 `127.0.0.1:8010`，`Restart=always` |
| 公网 | `https://203.195.219.170/dav/` |
| 证书 | 自签，SAN=IP:203.195.219.170，10 年；防火墙已加 **443** |
| 控制台 | `/opt/diary-webdav/config.toml`（`chmod 600`），账号 `diary` |
| 数据 | 只有密文，`cloud_key` 不在服务器上 |

**全链路实测**（不是"应该能跑"）：

1. 生成 App 格式密文（`{"_encrypted":true,"_version":2,"data":"__CLOUD__..."}`）
2. 经公网 `PUT` → 服务器 201
3. `diary-mcp` 从公网拉取 → 解密 → **导入 3 篇日记**
4. `ask 焦虑` 命中 1 条，正文与心情正确
5. 第二次 `sync` 正确识别「备份没变化，跳过下载」
6. 10 MB 文件上传 4.3 秒（入方向约 2.4 MB/s），md5 一致
7. 28 个单测全绿

### 还差的

1. **App 侧改地址**（唯一需要人操作的）：设置 → 云同步 → 服务器地址填
   `https://203.195.219.170/dav/`，账号 `diary`，密码见 `diary-webdav/README.md`。
2. **真实 `cloud_key`**：App 里导出后填进 `diary-mcp/config.toml`，
   `backup_<hash>` 目录名才会与 App 一致。
3. **图片问题仍在 App 侧**：每次同步把**全部图片重打一遍**上传
   （`cloud_sync_service.dart` 无增量、无旧文件 DELETE）。100 张 × 2 MB = 每次 200 MB 上行。
   有 300 GB 流量兜底，但这是真问题，改它要动 App。

## 六、红线

1. **AI 永不直接写业务表**。产出先进 `ai_suggestions`，用户确认。
2. **原文分级**。绝密日记不生成 embedding、不进索引。需要给 `diaries` 加 `privacy_level`。
3. **不往日记里塞聊天框**。AI 是旁路，不是主界面。
4. **不部署时不动系统服务**。原 kaoyan / poke / poke-world / poke-link 已于 2026-10-28 按 PD 指示全部删除
   （归档于 `/root/_archive_20261028-1255/`），当前机器的业务负载为零，专供日记链路使用。
5. **密钥不进 App、不进服务器**。`cloud_key` 只在本机 config.toml。

## 七、未验证项（别当成已完成）

- 麦麦插件是否被宿主接受、命令参数键名、`stream_id` 来源、热重载是否重复起任务；
- `bot_config.toml` 的 `[[mcp.servers]]` 是否会与已有 `[mcp.client.elicitation]` 冲突（TOML 已校验通过，运行时未验）；
- 服务器上 Python 包能否正常安装（未测试出网）。
