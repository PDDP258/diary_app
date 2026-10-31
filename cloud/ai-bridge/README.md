# 小记日记 · 麦麦 AI 对话桥

App 直连麦麦，做一个「只拿得到聊天」的窄接口。

## 为什么不是直连 WebUI

麦麦 WebUI 有 418 个 API（改配置、删会话、管插件、读全部 QQ 聊天记录）。
如果让 App 存 nginx basic 口令 + `access_token`，手机丢了就等于后台失守。

本桥跑在麦麦同机，用 `127.0.0.1` 连 WebUI 的「网页聊天室」（internal chat）通道，
对外只暴露两个动作：发一句话、拿回复。凭据全在服务器，App 只有一个专用 token。

## 通道与隔离（均已实测）

| 项 | 结论 | 取证 |
|---|---|---|
| 通道 | WebUI 统一 WS `/api/webui/ws`，`domain=chat` 的 `session.open` / `message.send` | `probe_internal_chat.py` 实收 `bot_message` |
| 记忆写入 | internal 会话**不写** A_memorix | `chat_summary_checkpoints` 6 个 chat_id 全是 QQ；5 条原话在 `paragraphs` 5/5 未命中 |
| 记忆读取 | 不读 QQ 记忆 | `_is_chat_memory_allowed` 走白名单补丁，internal 的 `user_id="owner"` 不在 `owner_users` 里 |
| 走麦麦本体 | 是，`chat_bot.message_process()`，人格 / planner / replyer / 插件工具全在 | `chat/service.py:1285` |

⚠️ **不要**改成 `/api/webui/agent`：那是 ACP 外接 Agent（`connection = "dsh"`），
连上去是外部 CLI 程序，不是麦麦，且默认 `[agent] enabled = false`。

## 部署

```bash
# 1. 代码
mkdir -p /opt/ai-bridge
cp bridge.py config.example.toml requirements.txt ai-bridge.service /opt/ai-bridge/
cd /opt/ai-bridge && cp config.example.toml config.toml

# 2. 生成 App 专用 token（与麦麦任何凭据无关，可随时轮换）
sed -i "s/^app_token = \"\"/app_token = \"$(openssl rand -hex 24)\"/" config.toml
grep '^app_token' config.toml

# 3. systemd
cp /opt/ai-bridge/ai-bridge.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now ai-bridge

# 4. 自检
curl -s http://127.0.0.1:8021/health
```

## nginx（公网入口）

在 `/etc/nginx/conf.d/maibot.conf` 的 `server { }` 里加一段——注意 `auth_basic off`，
否则 App 还得带 basic 口令：

```nginx
location /ai/ {
    auth_basic off;
    proxy_pass http://127.0.0.1:8021/;
    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_read_timeout 120s;   # 麦麦思考 + 生成可能要几十秒
    proxy_buffering off;
}
```

## 接口

```http
GET  /health
-> {"ok": true, "connected": true, "cursor": 12}

POST /chat
Authorization: Bearer <app_token>
{"text": "今天有点累", "context": "2026-10-31 · 晴 · 平静\n今天跑了三公里。"}
-> {"ok": true, "text": "…", "duration_ms": 8420, "events": [...]}

POST /warmup
Authorization: Bearer <app_token>
-> {"ok": true}      # 提前建连，避免第一句话多等 1~2 秒

POST /reset
Authorization: Bearer <app_token>
-> {"ok": true, "message": "已清空 17 条聊天记录"}
```

`context` 是「用户此刻在看的那一页日记」，桥把它贴在话前面一起发过去。带上它
麦麦不用调工具去查，上下文里也不会掺别处的杂聊；不带也能用，只是她会自己翻。
实测带「今天跑了三公里」→ 回「三公里啊。」，9.6 秒。

`/reset` 走 WebUI 的 `DELETE /api/chat/history`，同时清库和 heartflow 的内存
上下文。**不要**改成给麦麦发 `/clear`：那条要管理员权限，`internal:owner` 只会
被回一句「你没有权限使用此命令」。

`ok=false` 且 `error` 有值时，通常是麦麦这一轮没给出可见回复（被 stale 判定丢弃、
或模型空转）。桥不会重试——重试只会让用户等更久。

## 情景与人设（只作用于这条流）

App 里的她不是群里的她：刚合上日记本，坐在旁边，话比群里多，也愿意说长。

这段提示通过 `bot_config.toml` 的 `[[chat.reply_style.chat_prompts]]` 精确挂在
`internal / owner / private` 上——**不碰全局人设，也碰不到 QQ 的任何会话**。
`platform=qq` 的 5 条现有条目一行没动。

```toml
[[chat.reply_style.chat_prompts]]
platform = "internal"
item_id = "owner"
rule_type = "private"
prompt = "你现在在小记日记 App 里…"
```

安装/更新走官方接口（tomlkit 改写 + 热重载，不重启）：

```bash
python3 install_session_prompt.py plan    # 看现状与将写入的内容
python3 install_session_prompt.py apply   # 新增或更新（自动备份 + 读回校验）
python3 install_session_prompt.py check   # 确认线上内容与脚本一致
```

实测（同一篇日记连说三句，不清历史）：40 字 / 15 字 / 94 字，平均 **49.7 字**，
单轮 4.5~26.5 秒。改动前同样输入是「三公里啊。」（4 字）。

⚠️ **调这条时的反效果**（实测）：把语气写成硬要求（"至少回三句、五十个字以上"）
→ 她开始回「懒得说」（3 字）。用许可式表述（"愿意说长、能说五六句"）才有用。

⚠️ **「不知道」别急着怪提示词**：这个短回复在三种提示词下都出现过，真因是
① 清历史后第一条 ② 分段被静默窗口截断。线上版本里那句"他写得少也别只说不知道"
**没有造成问题**，带着它平均仍有 50 字。

⚠️ **清历史后第一条会明显变差**：`/reset` 之后立刻发，前 1~3 条容易得到 4~5 字的敷衍。
这不是提示词的问题，别据此判断效果。

改词只需编辑脚本里的 `PROMPT` 常量再 `apply`。

## 已知边界

- **回复延迟 6~12 秒**：planner 单轮 4~7 秒是模型固有开销，桥不额外增加。
  一轮里她分几条发就要几轮，所以 3 条回复可能 20 秒。
- **她会分段发，静默窗口要留够**：同一轮能拆成两条、间隔实测 **3 秒**
  （13:46:56 一条、13:46:59 一条）。`reply_quiet_seconds` 设 1.6 时桥在第一条后
  就收尾，后面的分段全丢——表现是"她说了不少，App 只显示半句"。**设 3.5**。
- **上下文按 `platform + user_id` 聚合，只涨不清**：`chat_manager` 用
  `calculate_session_id(platform, user_id)` 算会话，跟连接无关——重启桥、换
  `client_session` 都不会开新会话。聊久了攒到上百条，planner prompt 冲到几万
  token，一轮就要十几秒。用 `/reset` 清，别指望重启。
- **日记工具的白名单要单独给 `internal:owner`**：`data/mcp_acl.json` 的
  `allow_private` 默认只有主人 QQ 号，不带 App 身份的话 8 个 `diary_*` 工具
  全被隐藏，她会反复 `tool_search` 找不到、跑到 16 回合直到超时。
- **表情包不转图**：`bot_message` 里形如 `[表情包: …]` 的帧会被过滤，只回文字。
- **一次一轮**：桥内串行，避免同一会话并发串台。
- **cookie 7 天**：桥每次建连都重新 `verify`，不缓存会话凭据。
- **麦麦重启**：`Wants=maibot.service` 保证顺序，WS 断开由 read loop 捕获后下次请求重建。
