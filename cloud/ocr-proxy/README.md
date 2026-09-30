# 课表图片识别中转云函数（腾讯云 SCF）

> 对应 wayfinder 票 **T9**。做完这里，App 端只需要一个函数 URL 就能用图片识别导入课表。
> 为什么需要它：SecretId / SecretKey 一旦打进 APK 就等于公开泄露，必须放在服务端。

## 1. 准备工作（人工，约 10 分钟）

1. 注册/登录腾讯云，完成**实名认证**。
2. 开通**文字识别 OCR** 服务：<https://console.cloud.tencent.com/ocr/overview>
   - 开通后自动发放 **1,000 次/月免费资源包**（当月生效，每月重置）。
   - 计费口径（2026-09 核对）：资源包 1,000 次 = 120 元 / 10,000 次 = 800 元；后付费 0~1 万次 = **0.15 元/次**。
   - 接口默认 QPS 上限 **2 次/秒**（个人使用完全够）。
3. 开通**云函数 SCF**：<https://console.cloud.tencent.com/scf>

## 2. 部署云函数

### 2.1 创建函数

| 项 | 值 |
|---|---|
| 创建方式 | 从头开始 |
| 函数类型 | Web 函数（或「事件函数 + 函数 URL」） |
| 函数名称 | `diary-course-ocr-proxy` |
| 运行环境 | Node.js 18（20 亦可） |
| 地域 | `ap-guangzhou`（与 OCR 服务同地域，延迟最低） |
| 执行方法 | `index.main_handler` |
| 内存 / 超时 | 256 MB / 30 s |

### 2.2 配置运行角色（推荐，免硬编码密钥）

在函数配置 → **权限配置** 里，为函数绑定一个角色，策略挂 `QcloudOCRFullAccess`。
SCF 会自动向运行环境注入临时密钥（`TENCENTCLOUD_SECRETID` / `TENCENTCLOUD_SECRETKEY` /
`TENCENTCLOUD_SESSIONTOKEN`），`index.js` 直接读取，**不需要在代码或环境变量里写死 SecretKey**。

> 不想建角色也可以：在函数「环境变量」里手工设置 `OCR_SECRET_ID` 与 `OCR_SECRET_KEY`。
> 但这样密钥以明文存在函数配置里，权限一旦泄露影响面更大，属于次选。

### 2.3 上传代码

把本目录（`index.js` + `package.json`）打成 zip 上传，或在控制台「在线编辑器」里粘贴 `index.js`，
并在「依赖管理」中安装依赖：

```bash
npm install tencentcloud-sdk-nodejs-ocr
```

### 2.4 环境变量

| 变量名 | 必填 | 说明 |
|---|---|---|
| `APP_KEY` | 建议填 | 客户端调用凭据。App 端填同一个值；不填表示不校验（**别不填**，否则 URL 被扫到就会被白嫖） |
| `TENCENTCLOUD_REGION` | 可选 | 默认 `ap-guangzhou` |
| `OCR_SECRET_ID` / `OCR_SECRET_KEY` | 可选 | 仅在上一步用「手工环境变量」方案时填 |

### 2.5 创建访问入口

推荐用 **函数 URL**（自带 HTTPS 地址，无需自有域名、无需 ICP 备案）。
在「函数 URL」里创建，鉴权方式选**免鉴权**（鉴权靠上面的 `APP_KEY`），勾选 `POST` + `OPTIONS`。

拿到形如 `https://<id>-<region>.tencentscf.com/` 的地址。

> CORS：`index.js` 已回 `Access-Control-Allow-Origin: *`。App 端是原生 HTTP 请求，不受同源限制；
> 万一以后做 Web 端，也已能直接跨域调用。

## 3. 自测

```bash
# 把课表截图转 base64（Linux/macOS）
IMG=$(base64 -i schedule.png | tr -d '\n')

curl -sS -X POST "https://<你的函数URL>" \
  -H "Content-Type: application/json" \
  -H "X-App-Key: <你的APP_KEY>" \
  -d "{\"image\":\"$IMG\"}" | head -c 800
```

成功时应返回 `{"ok":true,"tables":[...],"angle":0}`，`tables[0].cells` 里能看到
`{"r":0,"c":1,"rs":1,"cs":1,"text":"高等数学"}` 这类结构。

用腾讯云控制台函数自带的「测试」也很快，事件模板填：

```json
{ "headers": { "x-app-key": "<你的APP_KEY>" }, "body": "{\"image\":\"<base64>\"}" }
```

## 4. 额度告警

控制台 → 文字识别 → **用量**：按月查看调用次数。
建议在「费用中心 → 预算与告警」设一个月度消费告警（例如 10 元），防止出现异常调用。

## 5. 常见错误码

| code | 含义 | 处理 |
|---|---|---|
| `BAD_APP_KEY` | App 端密钥与函数 `APP_KEY` 不一致 | 两端改成一致 |
| `NO_CREDENTIAL` | 函数没拿到密钥 | 绑定运行角色，或设置 `OCR_SECRET_*` |
| `NO_TABLE` | 图片里没找到表格 | 换更清晰、边框完整的课表截图 |
| `IMAGE_TOO_LARGE` | base64 超过 8 MB | App 端已自动压缩，若仍触发说明图特别大 |
| `FailedOperation.ImageDecodeFailed` | 图片无法解码 | 换图 |
| `RequestLimitExceeded` | 超过 2 次/秒 | 稍后重试 |
| `ResourceUnavailable.InArrears` / `FailedOperation.OcrResourceNotEnough` | 额度用尽或欠费 | 充值或购买资源包 |
| `AuthFailure.*` | 密钥无效/未授权 OCR | 检查角色策略 `QcloudOCRFullAccess` |

## 6. 客户端约定

App 端（`lib/services/course_import/ocr/ocr_client.dart`）会向该 URL `POST`：

```json
{ "image": "<JPEG base64，长边已压到 2000px 以内>" }
```

并带请求头 `X-App-Key`。响应按上面的归一化结构解析。
