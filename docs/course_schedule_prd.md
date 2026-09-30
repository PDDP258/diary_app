# 课表功能 PRD —— 小记日记

> 生成方式：to-prd（从已有讨论合成，无访谈） | 日期：2026-09-08
> 前置调研：[course_schedule_import_research.md](./course_schedule_import_research.md)
> 词汇表：[/CONTEXT.md](../CONTEXT.md) | 任务地图：[wayfinder/course_schedule_map.md](./wayfinder/course_schedule_map.md)

## Problem Statement

大学生用户每天要看好几次课表，但现有工具各有硬伤：WakeUp课程表带广告，小爱课程表不覆盖所有教务系统，独立课表 App 与个人记录场景割裂。用户已经在小记日记里记录生活，缺一个「课程 → 日程 → 日记」打通的体验：上课是大学生活的主线，但日记 App 对此一无所知。

## Solution

在小记日记内建课表模块：三条导入路径（模板文件兜底、教务系统 WebView 适配、图片 OCR 识别）统一汇入标准课程模型，配上课前提醒通知和「今日课程」桌面小组件，并与日记场景联动（写日记时提示当天课程）。

## User Stories

**导入**
1. 作为用户，我希望手动逐门添加课程，以便在没有其他导入方式时也能用。
2. 作为用户，我希望下载 Excel/CSV 模板填好后导入，以便批量录入课表。
3. 作为用户，我希望导入学校导出的 .ics 日历文件，以便零手工迁移。
4. 作为用户，我希望拍一张课表截图就能识别成课程，以便最快完成导入。
5. 作为用户，我希望识别后能在可视化课表上逐格确认和修正，以便放心入库。
6. 作为用户，我希望在 App 内登录自己学校的教务系统一键导入，以便 10 秒完成。
7. 作为用户，我希望教务登录全程我本人操作、密码不被 App 保存，以便放心授权。
8. 作为已适配学校改版后的用户，我希望适配规则自动更新，以便不用等 App 发版。

**使用**
9. 作为用户，我希望看到本周课表网格视图，以便了解课程分布。
10. 作为用户，我希望单双周、冲突课程正确显示，以便符合真实课表。
11. 作为用户，我希望设置每门课的颜色，以便一眼区分。
12. 作为用户，我希望配置开学日期、总周数、每节课起止时间，以便匹配自己学校。
13. 作为用户，我希望上课前收到提醒（可配置提前量），以便不迟到。
14. 作为用户，我希望换手机/重启后提醒依然有效，以便不漏课。
15. 作为用户，我希望桌面小组件直接显示今日课程和下节课，以便不打开 App。

**联动**
16. 作为用户，我希望写日记时看到今天上了哪些课的提示，以便快速回顾。
17. 作为用户，我希望课程能一键转为日程事件，以便和待办统一管理。
18. 作为用户，我希望课表跟随 App 主题配色，以便视觉统一。

## Implementation Decisions

### D1. 标准课程模型先行（最高优先级决策）
三条导入路径、通知、小组件、日记联动全部只依赖 `Course / CourseSession / SemesterConfig`（定义见 CONTEXT.md）。任何路径的产出都归一化到该模型 + 预览确认页。**周次字符串解析只在导入边界发生**，内部统一 `List<int>`。

### D2. 导入模块接口（design-an-interface：三方案对比后取舍）

考虑过三种形态：
- **方案 A「一个大 import 方法」**：`import(source) → List<Course>`，内部 if-else 分流。接口最小但模块浅——每条路径的预览、错误处理、进度提示差异巨大，会撑爆实现。
- **方案 B「每路径独立 Service」**：`ExcelImportService / OcrImportService / EduImportService` 各自暴露自己的方法，UI 分别对接。灵活但三条路径的「解析→预览→入库」公共流程会在 UI 层重复三遍。
- **方案 C「统一 ImportSource 抽象 + 模板方法」（选定）**：
  ```
  abstract class CourseImportSource {
    Future<ImportDraft> collect();   // 各路径特有：选文件/开WebView/拍照
  }
  // ImportDraft = 原始课程数据 + 来源元信息
  // 之后公共管线：parse → normalize → ImportPreview 页 → 入库
  ```
  公共流程收在管线里（深模块），路径差异收在 collect() 里。选中理由：预览确认是三条路径的强制公共环节，接口形状应直接表达这一点。

### D3. 教务导入 = flutter_inappwebview + JS 适配器
- 插件：`flutter_inappwebview`（非官方 webview_flutter），因其 `evaluateJavascript` / `callAsyncJavaScript` / `injectJavascriptFileFromAsset` / `addJavaScriptHandler` 完整支持「注入 JS 取数据回传 Dart」。（来源：inappwebview.dev 官方文档）
- 流程：WebView 打开教务登录页 → 用户手动登录（验证码/统一认证全交给用户）→ 注入 Provider JS 取课表 HTML/JSON → Dart 侧 Parser 归一化 → 预览确认。
- 适配器（SchoolAdapter）按「Provider / Parser / Timer」三段式组织（小爱课程表验证过的架构），**JSON 清单云端下发**（先放 GitHub Raw / 对象存储，无备案域名需求），学校改版不发版。
- 不代存学号密码（合规红线）。

### D4. 图片识别 = 腾讯云表格识别 API 起步
- 表格识别 V3：每月 1000 次免费额度，超出后 0.15 元/次（后付费，万次以上 0.10）。（来源：cloud.tencent.com 计费文档，2026-08）
- 备选：阿里云表格识别 200 次/月免费（来源：help.aliyun.com，2026-07）。
- **密钥安全**：SecretKey 不能打进 APK。方案：腾讯云云函数（SCF）做中转签名（免费额度内零成本、无需域名备案），或评估临时密钥（STS）。这是 Task 型前置项。
- 管线：表格结构识别 → 合并单元格还原节次区间 → 单元格文本解析（"1-16周/单双周/一格多课"）→ 预览确认页。
- 降级通道（二期）：多模态大模型直出 JSON。

### D5. 课前提醒 = flutter_local_notifications 滚动窗口调度
- 依赖已在项目中（浮窗在用）。
- **不**用 `matchDateTimeComponents: dayOfWeekAndTime` 的无限周重复——单双周无法表达，且 Android（三星实测 500 条 AlarmManager 上限）/ iOS（64 条待触发上限）都会爆。（来源：pub.dev flutter_local_notifications caveats；GitHub issue #2231）
- 方案：只排未来 14 天的上课提醒（每天课程数 × 14 ≪ 64），App 启动时 + 每日后台续排。重启后由插件 BOOT_COMPLETED 接收器自动重排。
- Android 14+ 精确闹钟权限做引导 + 降级为非精确提醒；国产 ROM 保活引导（dontkillmyapp 清单）。

### D6. 桌面小组件 = glance_widget 优先，home_widget 兜底
- **首选 `glance_widget`（^2.0.0）**：自带 7 种现成模板（ListWidget 正好做「今日课程」、CalendarWidget 做「日期+课程列表」），Android 侧**零原生代码**（插件自带 Compose 编译器，只声明 receiver），自带 WorkManager 后台刷新与防抖更新。（来源：pub.dev/packages/glance_widget，2025-10）
- 约束：需 Flutter ≥3.32 / Dart ≥3.8 / minSdk 26 —— 升级前需核对项目当前 Flutter 版本（Fog 区跟踪）。
- 兜底：若 glance_widget 模板表现力不够（课表网格密度高），回退 `home_widget` + 手写 Glance Kotlin（成本 +3 天，AGENTS.md 遗留的 compose 插件/R8 坑已知可规避）。

### D7. 日记联动（差异化功能）
- 写日记页/详情页嵌入「今日课程」卡片（复用现有日程卡片的嵌入模式）。
- 课程一键转日程事件；日记保存时可附「今日课程」片段。
- 关联徽章（如「第一周」「满勤一周」），接入徽章体系。

### 新增依赖一览
`flutter_inappwebview`（教务导入）、`excel` + 文件选择（模板导入）、`icalendar_parser` 或手写（.ics）、`glance_widget`（小组件）、`http`（OCR 云函数调用）。通知复用现有 `flutter_local_notifications`。

## Testing Decisions

- **好测试的标准**：只测外部行为（给定输入字符串/文件 → 课程模型），不测内部实现。
- **重点模块与既有先例**：
  - 周次字符串解析器（`1-16`、`2,4,6-8周`、`1-15单`、全角逗号）——纯函数，表驱动单测，对应现有 `test/` 下服务测试模式；
  - ICS / Excel 解析 → Course 归一化——golden 文件测试；
  - 当前周计算（跨学期边界、开学日非周一）——日期边界单测；
  - 提醒滚动窗口调度逻辑——mock 通知插件接口，断言未来 14 天窗口内容；
  - OCR 单元格文本 → CourseSession 语义解析——fixture 驱动。
- WebView 适配器本身不做自动化测试（依赖真实教务系统），改为适配器契约测试：给定 fixture HTML/JSON，Parser 输出符合 schema。

## Out of Scope

- iOS / 桌面端小组件（课表功能首期 Android only，iOS 17+ 可后续用 glance_widget 同一 API 扩展）
- 成绩查询、考试安排、空教室等教务周边功能
- 多端课表同步（WebDAV 同步课表数据列入 Fog，非首期承诺）
- 教务系统适配的社区投稿平台（先人工收录）
- 多人共享课表/情侣课表

## Further Notes

- **无备案/软著的影响**：App 内直调云 API 无需 ICP 备案；OCR 中转用云函数（自带触发地址，无需自有域名）。上架应用市场需要软著——这不阻塞开发，但阻塞分发，建议尽早启动软著申请（流程 1-2 个月）。
- **包体积预算**：新增依赖预估 +3~5MB（inappwebview 为主），当前 APK 基线需重新测量（代码库回滚至 v1.3.0）。
- 代码库现状：v1.3.0+130，无日程/提醒/小组件遗留代码，全部从干净的基线出发，反而是好事——不存在兼容包袱。
