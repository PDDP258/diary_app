# 阿里云盘同步 - 最简单方案

## 方案对比

| 方案 | 难度 | 成本 | 稳定性 | 推荐度 |
|------|------|------|--------|--------|
| **方案1：alist+WebDAV** | ⭐⭐ 简单 | 免费 | ⭐⭐⭐ 高 | ✅ 最推荐 |
| **方案2：aliyundrive-webdav** | ⭐⭐ 简单 | 免费 | ⭐⭐⭐ 高 | ✅ 推荐 |
| **方案3：官方API** | ⭐⭐⭐⭐⭐ 极难 | 免费 | ⭐⭐⭐⭐⭐ 最高 | ❌ 不推荐 |

---

## ✅ 方案1：AList + WebDAV（最简单）

**原理**：AList是一个开源工具，可以把阿里云盘转成WebDAV服务器，App直接连接即可。

### 方法一：Windows/Mac 本地运行（适合个人使用）

#### 步骤1：下载 AList

1. 访问 https://github.com/alist-org/alist/releases
2. 下载对应系统的版本（Windows选`alist-windows-amd64.zip`）
3. 解压到任意文件夹

#### 步骤2：启动 AList

**Windows：**
```bash
# 1. 打开命令提示符，进入alist目录
cd C:\Users\你的用户名\Downloads\alist

# 2. 运行（第一次运行会显示密码）
alist server

# 会看到类似输出：
# INFO[2024-01-20] init log...
# INFO[2024-01-20] start server @ 0.0.0.0:5244
# INFO[2024-01-20] admin password: xxxxxxxx
```

#### 步骤3：配置阿里云盘

1. 浏览器打开 http://localhost:5244
2. 登录（用户名admin，密码是刚才显示的）
3. 点击底部"管理" → "存储" → "添加"
4. 驱动选择：**阿里云盘Open**
5. 挂载路径填：`/aliyun`
6. 点击"刷新令牌"旁边的链接获取token
7. 按提示扫码登录阿里云盘
8. 复制token填入，保存

#### 步骤4：开启WebDAV

1. 在管理页面 → "设置" → "其他"
2. 找到 WebDAV，开启
3. WebDAV用户名：admin
4. WebDAV密码：设置一个密码（和登录密码可以不同）
5. 保存

#### 步骤5：App中连接

在"小记日记"App中：

1. 我的 → 数据管理 → 登录 WebDAV
2. 选择"自定义"
3. 服务器地址：`http://你电脑的IP:5244/dav`
   - 本机测试：`http://127.0.0.1:5244/dav`
   - 手机连接电脑：`http://192.168.x.x:5244/dav`（看下方获取IP）
4. 用户名：admin
5. 密码：刚才设置的WebDAV密码
6. 点击连接

**获取电脑IP：**
```bash
# Windows
ipconfig

# 找"IPv4地址"，通常是 192.168.x.x
```

---

### 方法二：手机Termux运行（无需电脑）

如果只有手机，可以用Termux安装AList：

```bash
# 1. 安装Termux（F-Droid下载）
# 2. 在Termux中执行：

pkg update
pkg install alist

# 启动
alist server

# 查看密码
alist admin
```

然后用 http://127.0.0.1:5244/dav 在App中连接（仅限本机）。

---

### 方法三：VPS/云服务器部署（最稳定）

如果有云服务器，可以24小时运行：

```bash
# 1. 下载
curl -fsSL "https://alist.nn.ci/v3.sh" | bash -s install

# 2. 启动
systemctl start alist

# 3. 查看密码
./alist admin
```

然后配置阿里云盘和WebDAV，App连接服务器IP即可。

---

## ✅ 方案2：aliyundrive-webdav（轻量级）

**适合**：只需要阿里云盘WebDAV，不需要其他网盘

### Windows/Mac 使用方法

#### 步骤1：下载

访问 https://github.com/messense/aliyundrive-webdav/releases

下载对应系统的版本。

#### 步骤2：获取阿里云盘Token

1. 浏览器打开阿里云盘 https://www.aliyundrive.com/
2. 按F12打开开发者工具
3. 切换到 Application/应用 → Local Storage
4. 找到 `token` 字段
5. 复制 `refresh_token` 的值

或者使用扫码工具：https://alist.nn.ci/tool/aliyundrive.html

#### 步骤3：运行

**Windows 命令行：**
```bash
aliyundrive-webdav.exe --refresh-token "你的token" --port 8080
```

**Mac/Linux：**
```bash
aliyundrive-webdav --refresh-token "你的token" --port 8080
```

#### 步骤4：App连接

在"小记日记"App中：

1. 我的 → 数据管理 → 登录 WebDAV
2. 服务器地址：`http://127.0.0.1:8080`
3. 用户名：留空或任意
4. 密码：留空或任意
5. 点击连接

---

## ❌ 方案3：官方API（不推荐）

阿里云盘官方API需要：
1. 企业资质申请
2. 审核周期长（可能不通过）
3. 需要服务器后端配合

除非是企业级应用，否则不建议。

---

## 常见问题

### Q: 电脑重启后AList没了？
A: 需要重新运行`alist server`。可以设置为开机自启：

**Windows 开机自启：**
1. 新建文件`start-alist.bat`：
```batch
@echo off
cd /d C:\路径\到\alist
start /b alist server > nul 2>&1
```

2. Win+R 输入 `shell:startup`
3. 把bat文件放进去

### Q: 手机连不上电脑的AList？
A: 确保手机和电脑在同一WiFi下，检查Windows防火墙是否允许5244端口。

**关闭防火墙测试（仅测试）：**
```powershell
# 以管理员身份运行PowerShell
netsh advfirewall set allprofiles state off

# 测试完记得开启
netsh advfirewall set allprofiles state on
```

### Q: 阿里云盘Token过期了？
A: Token通常有效期几个月，过期后需要重新获取。

### Q: 数据安全吗？
A: 
- AList和aliyundrive-webdav都是开源软件，代码可查
- Token只保存在你自己的设备上
- 传输使用HTTPS加密

---

## 推荐配置流程

**第一次使用，推荐这样操作：**

1. **电脑**下载 AList
2. 按照"方案1：方法一"配置阿里云盘
3. 开启WebDAV，设置密码
4. **手机**和电脑连同一个WiFi
5. 在App中连接（用电脑的局域网IP）
6. 测试同步功能
7. 觉得好用再考虑其他部署方案

---

## 需要我做什么？

App端的WebDAV功能已经做好，您只需要：

1. 选择一个方案（推荐AList）
2. 按照步骤配置阿里云盘WebDAV
3. 在App中输入地址和账号密码

**不需要修改任何代码！**

如果配置过程中遇到问题，可以告诉我，我帮您排查。
