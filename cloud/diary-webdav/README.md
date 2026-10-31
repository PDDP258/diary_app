# diary-webdav

极简 WebDAV 服务端，**只服务小记日记 App 的云同步**。部署在腾讯云 Lighthouse（广州）。

## 为什么自己做

App 的云同步说的「WebDAV」是**协议**，不是坚果云。查 `cloud_sync_service.dart` 实测，
它总共只发 6 种请求：

| 方法 | 用途 | App 依赖的返回 |
|---|---|---|
| `PROPFIND` Depth 0 | 目录探测 | 只认 **207**（存在）/ **404**（不存在，触发 MKCOL） |
| `PROPFIND` Depth 1 | 列目录 | 只解析 `<d:displayname>名字</d:displayname>` |
| `MKCOL` | 建目录 | 认 **201** |
| `PUT` | 传 backup.mbk / images_*.enc | 认 2xx |
| `GET` | 下载 | 200 |
| HEAD / OPTIONS | 可选 | — |

认证是 Basic，`serverUrl` 完全用户可填，`badCertificateCallback` 直接放行自签证书。
所以自己实现这 6 个动作，App 侧**一行 Dart 都不用改**，只改地址栏。

因此这里**不实现完整 RFC 4918**：没有 LOCK、MOVE、COPY、Range。

## 当前部署

| 项 | 值 |
|---|---|
| 路径 | `/opt/diary-webdav/` |
| 进程 | `systemd` → `diary-webdav.service`（`Restart=always`） |
| 监听 | `127.0.0.1:8010`（**不直接对外**，只走 nginx） |
| 公网 | `https://203.195.219.170/dav/` |
| 数据 | `/opt/diary-webdav/data/diary_backups/<folder>/backup.mbk` |
| 证书 | `/etc/nginx/ssl/diary.crt`（自签，SAN 含 IP，10 年） |
| nginx | `/etc/nginx/sites-available/diary`（80 + 443 同一 server 块） |

**服务器上只有密文。** 解密密钥 `cloud_key` 只在本机 `diary-mcp/config.toml` 里，
服务器被攻破也拿不到日记正文。

## 配置

`/opt/diary-webdav/config.toml`（`chmod 600`）：

```toml
[server]
host = "127.0.0.1"
port = 8010
prefix = "/dav"

[auth]
username = "diary"
password = "**********"

[storage]
root = "/opt/diary-webdav/data"
```

⚠️ **账号或密码为空时服务拒绝启动** —— 避免「忘配密码 = 公网裸奔」。

## 改动密码后

```bash
systemctl restart diary-webdav
```

App 侧和 `diary-mcp/config.toml` 里的密码要同步改。

## 自测

```bash
# 应该 401
curl -sk https://203.195.219.170/dav/ -X PROPFIND

# 应该 207
curl -sk -u diary:PASSWORD https://203.195.219.170/dav/ -X PROPFIND

# 应该 404（目录不存在）
curl -sk -u diary:PASSWORD https://203.195.219.170/dav/diary_backups/nope/ -X PROPFIND
```

⚠️ 本机 curl 必须带 `--noproxy '*'`（否则走系统代理，拿到的是代理的错误页）。

## 踩过的坑

1. **`client_max_body_size` 默认 1 MB。** 图片归档一定超过，nginx 直接 413，
   而 App 的报错只会说「上传失败」。已在 nginx 里设成 512m。
2. **`_abs_url` 不能只拼 `scheme://netloc`。** base 是 `https://host/dav/` 时，
   相对路径会被粘到主机名后面变成 `https://hostdiary_backups/`，
   报错却是 `getaddrinfo failed`（看着像 DNS）。已改 `urljoin` 并有测试锁。
3. **TAT 远程命令有内容审计。** 含大段 base64 或 XML 请求体、要写 `/etc` 的命令会被拦
   （`AccessDeny`），换 `printf` 逐行写文件可绕过。
4. **上传下载不对称**：出方向限 4 Mbps，入方向实测约 2.4 MB/s（10 MB 文件 4.3 秒）。
   日记备份是上行，基本不受限；**图片包下载会慢**。

## 已知限制

- 不支持 `DELETE`（App 不用）。清理只能上服务器 `rm`。
- 不支持 Range 请求（大文件断点续传不行）。
- 没有目录大小配额，需要时用 `du` 监控。
