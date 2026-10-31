# MEMORY.md — 小记日记（长期项目笔记）

> 只放跨会话有长期价值的事实与约定。日期流水见 `YYYY-MM-DD.md`。

## 项目
- Flutter 3.x + Provider + SQLite（原生）/ SharedPreferences（Web 双端）。工作区 `E:\main\work\diary_app`。
- 视觉：温暖手账风。暖木棕 `#C4956A`、暖纸白 `#FDF8F0`、墨色 `#2C241F`。**禁止硬编码颜色**，一律 `AppTheme.schemeOf(context)`。
- 布局遵循 `AGENTS.md`：`extendBody: false` + `Stack/Positioned` + 底部留 `systemNavBarHeight + 96`。
- 主追踪器 `docs/wayfinder/course_schedule_map.md`（本地 Markdown）。改课表功能要同步它 + `AGENTS.md`。
- **当前版本 2.1.0（2026-09-30）**：课表模块整体入库并推送（commit `d3ce486`，90 files），主线分支 `backup-2026-03-19`。APK 核验 `versionCode=2100 / versionName=2.1.0`。
- **远程 `origin` = `git@github.com:PDDP258/diary_app.git`（SSH）**。2026-09-30 从 https 切过来：原 URL 里内嵌的 PAT 已失效，且明文写在 `.git/config` 是隐患。本机 `~/.ssh/id_ed25519` 已挂在该账号上，可直接推。
  ⚠️ PD 会**在 GitHub 网页上直接改 README** → **push 前先 `git fetch`**，否则 `fetch first` 被拒（本次踩到：远程多一个 `5f360b6 Update README.md`，rebase 后才推上去）。

- **麦麦（MaiBot）已迁出本仓** → `E:\main\work\bot\`（补丁 / 插件 / 运维脚本 / 服务器文档 /
  长期记忆都在那边，入口是它的 `AGENTS.md`）。本仓只管 App 与 `cloud/diary-mcp`、`cloud/diary-webdav`。
  两边只通过 **WebDAV（备份 / 收件箱）+ MCP（diary-mcp）** 相连，协议见 `docs/agent-working-doc.md` §6。

## 环境坑（每次会话都可能踩）
1. **静态检查用 `dart analyze lib test`**。`flutter analyze` 会隐式 `pub get`：重写 `pubspec.lock`、重新解压 pub 包，还会崩在 Windows 插件符号链接创建上。
2. **跑 Flutter 命令前 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY`**。注入的本地代理会让 `flutter test` 报 `Invalid WebSocket upgrade request`，`flutter analyze` 网络检查超时。
3. Bash 里 Git Bash 的 PATH 常不完整，命令前导：
   `export PATH="/c/Users/PDXX/.workbuddy/binaries/PortableGit/versions/1.2.0/usr/bin:/c/flutter/flutter/bin:/c/flutter/flutter/bin/cache/dart-sdk/bin:/c/WINDOWS/System32:$PATH"`
   PowerShell 工具在本机不回显输出，别用。
4. **`--no-pub` 构建不重生成 Android 插件注册表**：`GeneratedPluginRegistrant.java` 由 **`pub get` 阶段**生成。**新增/移除原生插件后必须先 `flutter pub get`**，否则 APK 里插件类在但没注册 → 真机 `MissingPluginException`。
   核查：`unzip -p <apk> classes.dex | grep -a -o "<插件类名>" | wc -l`，已注册的通常 ≥2。**别用 `grep -c`（数「行」）**。
   → 通用：**「build 成功」≠「功能可用」**，PD 验收看产物。
5. **移除依赖要连它的构建配置一起清**：glance 移除后，`android/gradle.properties` 里 `android.builtInKotlin=false` / `glance.kotlinVersion` 两行一直留到 2026-09-30 才清掉。固定动作：`grep -ri "<依赖名>" android/ pubspec.yaml .gitignore`。
6. `.gitignore` 已忽略 `.capture/`、`.rollback/`（含真实教务数据）、`.venv_removebg/`（618MB 本地 venv）、`.superpowers/`、`.workbuddy/`。**`git add -A` 前先核对清单**（查有无本地目录 / >2MB 文件）。

7. **本机 bash 的 `find` 是坏的**（`FIND: 参数格式不正确`，非 ASCII 报错还乱码），`tasklist` / `netstat` 也基本无输出。找文件用 Glob / Grep 工具，别用 `find`。**「全盘搜索没找到」不能当结论**（麦麦主程序就是这么被误判成不存在的）。

## 架构约定
- **导入统一管线**：`CourseImportSource.collect()` → `ImportDraft` → `CourseImportPreviewScreen` → 入库。四条路径（模板 / ICS / 教务 WebView / OCR-暂缓）都走这条。
- **周次字符串解析只发生在导入边界**，内部一律 `List<int>`（`lib/utils/week_parser.dart`）。
- 星期解析统一 `lib/utils/day_of_week.dart`；课程色板统一 `Course.presetColors`；别再各写一份。
- 课前提醒用滚动窗口调度（14 天），**不用**系统级每周重复——表达不了单双周，且撞 iOS 64 / 三星 500 条上限。
- **⚠️ OCR 整体已暂缓（2026-09-29 PD 决定）**：代码保留（`course_import/ocr/`、`ocr_service_settings_dialog.dart`、`cloud/ocr-proxy/`），但**导入菜单无入口**，用户不可达。**重新推进前先问 PD。**
  PRD 的 `D4`、调研文档、User Story #4/#5 仍写「要做 OCR」——历史文本，别照着开工；以 map 里 M3 的 🔒 为准。
  OCR 密钥绝不进 APK：自部署云函数中转，App 只存「URL + APP_KEY」。
- **文档冲突时先问，别挑一条顺着走**（OCR 就是这么被 PD 纠正的）。

## 教务系统导入（jwapp / 金智 ehall）—— 已实现，首家西农
- 西农 = `ehall.nwafu.edu.cn` + `/jwapp/`（金智教育 ehall + jwapp，BHUI 前端，全国多校在用）。
- **课表是纯 JSON API**：`POST /jwapp/sys/wdkbby/modules/xskcb/cxxszhxqkb.do`，body `XNXQDM=<学年-学期>`；学期配置 `jshkcb/cxjcs.do`（开学日、总周数、节数划分）。
- 字段直接对应模型：`SKXQ` 星期几、`KSJC`/`JSJC` 节次、`SKZC` **周次位图**（→ `List<int>`）、`KCM`/`SKJS`/`JASMC`/`XF`。
- **必须走 App 内 WebView**（要 CAS 登录态）；但**不需要 DOM 适配器**，注入 `fetch` 即可，可用真实 JSON 做 fixture 单测。
- **⚠️ 四个解析坑（都有单测锁）**：
  ① `SKZC` 位图长度不固定（20/18 位混用）→ 按实际长度解析；
  ② 调课把同一时段拆多条 → 按「课程+周几+节次+地点」合并 weeks 并集；
  ③ 课程标识不能用 `KCH`+`KXH`（`01S01` 与 `01` 并存）→ 按「课程名 + 归一化教师」合并；
  ④ **当前学期不能用 `PX` 判定** —— `cxjcs.do` 有 `PX=null` 的脏行（`2025-2026-3` 暑假小学期）→ 把 null 当 0 会选错学期 → 课表查**返回空**、开学日也写错。改**按日期判定**（`JwappSemesterParser.pickCurrent(all, {now})`）。
- **⚠️ fixture 不要有损裁剪**：曾因 `SEMESTER_KEEP=12` 截掉 80 行末尾的毒行，bug 在单测里看不见。现在学期全量保留。
- **WebView 内置桌面模式（必须）**：固定桌面 Chrome UA（`JwappClient.desktopUserAgent`）+ `preferredContentMode: DESKTOP`（iOS）+ `useWideViewPort: true` + `loadWithOverviewMode: false` + `supportZoom` + `thirdPartyCookiesEnabled`（应对 iframe 里的 CAS）。由 `buildJwappWebViewSettings()` 统一给出，**有单测锁定**。
- **缩放默认就要能缩小**：`loadWithOverviewMode: true` 会把「适配宽度」钉成**最小**缩放，而手机上真实 fit ≈0.3，脚本写死 `minimum-scale=0.5` 比它还高 → 只能放大。现在 `onLoadStop` 注入 `buildViewportScript()`，按 `fit = min(1, deviceWidth/1280)` 算 `minimum-scale = max(0.15, fit*0.5)`；`displayZoomControls: true`。**别写死 minimum-scale、别把 loadWithOverviewMode 改回 true**。
- **取数兜底**：带 `XNXQDM` 取到 0 条 → 不带参数重取一次（接口默认当前学期）。学期配置以课表行自带的 `XNXQDM` 反查。回包归属用 `JwappClient.belongsTo(result, path)` 判（丢迟到旧包）。
- **落点**：`lib/services/course_import/jwapp/`、`jwapp_import_source.dart`、`lib/screens/jwapp_login_screen.dart`（WebView 登录 + 手动「读取课表数据」）、`jwapp_endpoints_dialog.dart`。**App 只存学校地址、不存账密**；登录成功不做自动探测。
- fixture：`node tool/make_jwapp_fixture.js`（读 `.capture/` → 脱敏 → `test/fixtures/jwapp/`）；工具 `tool/cdp.js`（CDP 只读客户端）。
- **真机验证**：2026-09-29 首轮暴露「0 课 + 开学日错」已修（坑 ④）；**待 PD 复验**。其它学校未适配（金智系预计只加一条预设 + fixture）。

## 桌面小部件（课程表 Widget）—— 自绘 RemoteViews，不用 glance_widget
> 2026-09-30 重写。起因：PD 反馈「开机后还是昨天的课」「UI 很粗糙」。glance 的 Calendar 模板布局/文案全写死（英文 `+1 more events`、Material 蓝日期块），改不成手账风 → 整体弃用，改 app 模块自绘。
- **数据契约 = 预计算计划**：Dart `CourseWidgetPlan.build(...)` 算出**未来 14 天**每天的课（节次→分钟、色、星期/周次）→ JSON → MethodChannel → 原生存 `course_widget_prefs` → 渲染只按 `yyyy-MM-dd` 查表。**「算」与「画」解耦**：刷新不需要 App 进程活着。
- **落点**：Dart `course_widget_plan.dart`（纯逻辑可单测）+ `course_widget_service.dart`（channel + 后台入口）；Kotlin `CourseWidgetPlan/Store`、`CourseWidgetRenderer`、`Provider`、`Scheduler`、`Worker`、`BackgroundRunner`、`Plugin`；布局 `widget_course.xml` / `widget_course_row.xml`；背景 `widget_course_bg_light/dark.xml`。
- **跨天/开机刷新是三条腿，缺一不可**：
  1. `course_widget_info.xml` 的 `updatePeriodMillis=1800000`（30min）—— 旧值 `0` = 系统**永不唤醒**，这是 staleness 根因；
  2. `CourseWidgetBootReceiver` 收 `BOOT_COMPLETED`/`MY_PACKAGE_REPLACED`/`QUICKBOOT_POWERON` → 立即 `updateAll` + 排下一班；
  3. `CourseWidgetScheduler` WorkManager 周期任务**每天 11:00**（PD：那点一般还没关机）。
- **⚠️ WorkManager 周期任务必须 `ExistingPeriodicWorkPolicy.KEEP`**：`onUpdate` 每 ~30min 触发，用 `UPDATE` 会把下次执行不断往后推 → 任务**永远不到期**。踩过。
- **后台跑 Dart 用 headless FlutterEngine**：`CourseWidgetBackgroundRunner` → `GeneratedPluginRegistrant.registerWith` + `CourseWidgetPlugin.install` → `DartExecutor.DartCallback(assets, "flutter_assets", FlutterCallbackInformation.lookupCallbackInformation(handle))` 跑 `courseWidgetBackgroundEntry`（排提醒 + 重算 plan）。handle 由 `PluginUtilities.getCallbackHandle` 在 `initialize()` 写入原生；入口必须 `@pragma('vm:entry-point')`。
- **⚠️⚠️ 两条 RemoteViews 运行时硬校验 —— 违反就「无法加载小部件」，且 App 侧完全不可观测**（2026-09-30 踩到，PD 三种场景全挂）：
  1. 布局里**每个 View 类必须带 `@RemoteView`**（AOSP `INFLATER_FILTER`）→ 白名单只有 `FrameLayout/LinearLayout/RelativeLayout/GridLayout` + `Button/Chronometer/ImageButton/ImageView/ProgressBar/TextView/ViewFlipper/ListView/GridView/StackView/AdapterViewFlipper/ViewStub`。**`<View>` 不在里面** —— 分隔线用 1dp 的 ImageView/TextView。
  2. `setInt(id, "方法名", v)` 的方法必须带 `@RemotableViewMethod`（AOSP `getMethod()` 强校验）→ `setBackgroundResource` **不行**，`setBackgroundColor` 可以。背景走官方 `setImageViewResource` + ImageView 图层，彻底不碰反射。
  - 异常抛在**启动器进程**，`try/catch` 拦不到 → **只能靠测试**：`test/course_widget_layout_test.dart` 锁死「布局标签白名单 + `setInt` 方法名白名单」，改布局后必跑。
  - **离线查证**：`@RemotableViewMethod` 是 **SOURCE 保留级**，编译后不在 class 文件里 → **方法白名单查不了**；只能查类级 `@RemoteView`（RUNTIME，`tool/inspect_android_jar_annotations.py`）。
- 其它：**不能用 ConstraintLayout**；圆角色条用 `setImageViewBitmap` 预画（别用 `setColorFilter`）；深链 `diaryapp://courses`；主题跟随 `AppTheme`（`main.dart` 挂 listener → `updateTheme(scheme)` 只换色重推）。
- **核查产物**：R8 会改名 Kotlin 类名，**别用类名计数**——查 Manifest receiver 注册 + dex 字面量（`updatePlan`/`backgroundDone`/`course_widget_prefs`/`diaryapp://courses`/文案）。`updatePeriodMillis` 编译进 `res/**.xml` 二进制描述文件，**不在 arsc**。
