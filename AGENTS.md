# 小记日记 - AI协作指南

版本: 1.27.5 (2026-09-30) | 技术栈: Flutter 3.x + Provider + SQLite

> **注意**：本文档版本号仅用于 AI 协作记录，软件实际版本号以 `pubspec.yaml` 和软件内显示为准。

## 快速开始

```bash
flutter pub get
flutter run
flutter build apk --release
```

## 核心规范

### 1. 屏幕布局规范（重要）

非全面屏设备必须正确处理系统导航栏：

```dart
return Scaffold(
  extendBody: false,
  body: Stack(
    children: [
      Positioned.fill(
        bottom: systemNavBarHeight + 96,
        child: PageView(...),
      ),
      Positioned(
        left: 0, right: 0,
        bottom: systemNavBarHeight,
        height: 96,
        child: CustomBottomNav(...),
      ),
    ],
  ),
);
```

**关键要点：**
1. `extendBody: false`
2. `Stack` + `Positioned` 手动控制布局
3. 内容底部留出 `systemNavBarHeight + 96`
4. 软件导航栏位于 `bottom: systemNavBarHeight`

### 2. 导航栏行为（强制）

- 下滑隐藏导航栏
- 上滑显示导航栏，3秒后自动隐藏
- 点击无效区域显示导航栏，3秒后自动隐藏

### 3. 主题使用（强制）

```dart
final scheme = AppTheme.schemeOf(context);
return Container(color: scheme.backgroundColor);
// ❌ 禁止硬编码 Colors.white
```

### 4. 编码处理（⚠️ 重要）

文件操作必须使用 UTF-8：
```dart
await File('file.dart').readAsString(encoding: utf8);
await File('file.dart').writeAsString(content, encoding: utf8);
```

PowerShell: `Get-Content file.dart -Encoding UTF8 | Set-Content file.dart -Encoding UTF8`

## 项目结构

```
lib/
├── screens/      # 页面（calendar, write_diary, profile, self_talk, course_schedule...）
├── services/     # 数据库、加密、云同步、PDF导出、徽章、图片缓存、浮窗、备份、课表
│   ├── course_widget_plan.dart   # 小组件「未来 14 天课表计划」（纯逻辑、可单测）
│   ├── course_widget_service.dart # 推计划给原生 + 后台入口点（开机/每日定时跑）
│   └── course_import/  # 课表导入（模板 / ICS / 教务系统可用；OCR 暂缓、代码在 ocr/ 未接线）
│       └── jwapp/      # 教务系统（金智教育 ehall）取数与解析：endpoints / client / parser / semester
├── providers/    # 状态管理（DiaryProvider, ThemeProvider, SettingsProvider, CourseProvider...）
├── models/       # 数据模型（Diary, Mood, Tag, Anniversary, QuickNote, Course...）
├── widgets/      # 组件（贴图覆盖层、音效按钮、浮窗UI...）
├── utils/        # 工具类（平台图片、图片缓存）
└── config/       # 主题配置（design_tokens.dart, app_theme.dart）

android/app/src/main/kotlin/com/example/diary_app/
├── MainActivity.kt / FloatingWindow* / IconThemePlugin   # 既有原生实现
└── CourseWidget*                # 课表桌面小组件（自绘 RemoteViews + 刷新调度，见「常见陷阱」）
    ├── CourseWidgetPlan.kt      # 计划数据模型 + JSON 解析 + 落盘
    ├── CourseWidgetRenderer.kt  # RemoteViews 渲染（⚠️ 只能调 remotable 方法与白名单 View）
    ├── CourseWidgetProvider.kt  # AppWidgetProvider
    ├── CourseWidgetBootReceiver.kt / CourseWidgetScheduler.kt / CourseWidgetWorker.kt
    ├── CourseWidgetBackgroundRunner.kt  # 起无界面 Flutter 引擎跑 Dart
    └── CourseWidgetPlugin.kt    # MethodChannel（Dart ↔ 原生）

android/app/src/main/res/
├── layout/widget_course.xml / widget_course_row.xml   # ⚠️ 标签必须在 RemoteViews 白名单内
├── drawable/widget_course_bg_light.xml / _dark.xml    # 圆角底板（ImageView 图层切换）
└── xml/course_widget_info.xml                         # updatePeriodMillis 等配置
```

## 设计系统

品牌视觉语言：**温暖手账风**

| Token | 值 | 用途 |
|-------|-----|------|
| 暖木棕 | `#C4956A` | 品牌主色、强调按钮 |
| 暖纸白 | `#FDF8F0` | 应用/官网浅色背景 |
| 墨色 | `#2C241F` | 深色区块、反色背景 |
| 缓动 | `cubic-bezier(0.16, 1, 0.3, 1)` | 进入/展开动画 |
| 时长 | 150ms / 250ms / 400ms | 微交互 / 小过渡 / 大过渡 |

完整设计规范参考官网 `DESIGN_SYSTEM.md`。

## AI Skills

- **interaction-design**：微交互、动画过渡、加载状态
- **visual-design-foundations**：8-point网格、字体层级、色彩系统
- **design-system-patterns**：Design Tokens、主题切换、组件变体
- **react-native-design**：SafeArea、手势动画、性能优化

### 可用组件

| 组件 | 文件 | 用途 |
|------|------|------|
| `InteractiveButton` | `lib/widgets/interactive_button.dart` | 带缩放反馈的按钮 |
| `PageTransitions` | `lib/widgets/page_transitions.dart` | 页面转场动画 |
| `SwipeableListItem` | `lib/widgets/swipeable_list_item.dart` | 可滑动列表项 |
| `SkeletonLoading` | `lib/widgets/skeleton_loading.dart` | 骨架屏加载效果 |

## 功能速查

| 功能 | 关键文件 | 说明 |
|------|---------|------|
| 速记浮窗 | `floating_window_service.dart`, `native_floating_service.dart` | 原生 Kotlin Service + Android View + MethodChannel |
| 自言自语 | `self_talk_screen.dart`, `self_talk_service.dart` | 聊天式记录，me/alterEgo/system 三身份 |
| 速记 | `quick_note_editor_screen.dart`, `quick_notes_screen.dart` | 快速笔记，标签，置顶，搜索 |
| 贴图拖动 | `custom_sticker_overlay.dart` | 页面上直接拖拽，长按菜单 |
| PDF导出 | `pdf_export_service.dart` | 思源宋体，图片嵌入，封面+页眉页脚 |
| WebDAV | `cloud_sync_service.dart` | 坚果云预设 |
| 应用锁 | `app_lock_service.dart` | 九宫格手势密码，指纹/面容识别 |
| 纪念日 | `anniversary.dart` | 日历页定制，写日记自动添加纪念文字 |
| 扭蛋系统 | `gacha_service.dart`, `gacha_screen.dart` | 每日抽奖，80+ 奖励，徽章联动 |
| 主题背景 | `theme_backgrounds.dart` | 5款动态主题（星空/樱花/海洋/极光/黄金） |
| 农历日历 | `lunar_calendar_service.dart` | 内置算法 1900-2100 年 |
| 目标系统 | `goal_provider.dart`, `goal_service.dart` | 月度目标，进度追踪 |
| 三级标签 | `tag_system_service.dart` | 分类→子分类→标签 |
| 徽章系统 | `badge_service.dart` | 84 个徽章，8 种类型 |
| 课表网格 | `course_schedule_screen.dart`, `course_provider.dart` | 7 列周网格，周切换，单双周/冲突显示 |
| 课表模型 | `course.dart`, `week_parser.dart` | Course/CourseSession/SemesterConfig；周次字符串解析只在导入边界 |
| 课表导入 | `course_import/`, `course_import_preview_screen.dart` | Excel/CSV、ICS、教务系统三条路径进入统一预览确认页 |
| 图片识别（暂缓） | `course_import/ocr/`, `cloud/ocr-proxy/` | 云函数中转腾讯云表格识别 V3；**代码保留但未接入 UI，重启用前先问 PD** |
| 教务系统导入 | `course_import/jwapp/`, `jwapp_login_screen.dart` | WebView 内登录后注入 JS `fetch` 取数（接口要 CAS 登录态，原生 HTTP 带不上 Cookie）；预置西农 ehall，其它学校可手填域名；**WebView 内置桌面模式**（`buildJwappWebViewSettings()`） |
| 课前提醒 | `course_reminder_service.dart` | 滚动窗口 14 天调度，不用系统级每周重复 |
| 今日课程小组件 | `course_widget_service.dart` + `course_widget_plan.dart`（Dart）／`android/.../CourseWidget*.kt`（原生） | **自绘 RemoteViews**（不再用 glance_widget）：Dart 预计算未来 14 天计划推给原生，原生自行渲染 + 开机/每日 11 点/每 30 分钟刷新；minSdk 26 |

## 常见问题

Q: 异步回调获取主题报错？  
A: `Provider.of<ThemeProvider>(context, listen: false).currentScheme`

Q: 底部弹窗被键盘遮挡？  
A: `isScrollControlled: true` + `MediaQuery.of(context).viewInsets.bottom`

Q: 构建失败/缓存问题？  
A: `flutter clean && flutter pub get`

Q: 徽章不触发？  
A: 连续徽章需要真正连续记录；检查 `BadgeService.checkStreakBadges()`

## 构建与发布

```bash
# APK
flutter build apk --release
# AppBundle
flutter build appbundle --release
# Windows
flutter build windows --release
```

**发布前检查**：更新 `pubspec.yaml` 版本号 → `flutter analyze` → 构建 Release → 检查 APK 大小（60-100MB 正常）。

## 常见陷阱

### ⚠️ 文件编码问题

Windows PowerShell 默认 GBK，会导致 UTF-8 文件乱码：

```powershell
# ❌ 错误
Get-Content file.dart | Set-Content file.dart
# ✅ 正确
Get-Content file.dart -Encoding UTF8 | Set-Content file.dart -Encoding UTF8
```

预防措施：使用 Git 提交后再修改；优先使用 IDE 替换功能。

### ✅ glance_widget 已于 v1.27.3 移除（老坑作废）

之前课表小组件用 `glance_widget` 的 Calendar 模板，踩过一个持续的坑：它的原生模块指望 Flutter ≥3.47 的加载器注入 `kotlin-android`，本项目在 Flutter 3.41，得靠 `tool/repatch_glance_widget.py` 往 pub 缓存里打补丁，而任何 `pub get` 都可能把补丁冲掉。

**现在小组件改为 App 模块内自绘 RemoteViews**（`android/app/src/main/kotlin/com/example/diary_app/CourseWidget*`），`glance_widget` 已从 `pubspec.yaml` 移除 —— 补丁、repatch 脚本这套流程**全部不再需要**。`tool/repatch_glance_widget.py` 保留但已无用。

### ⚠️ 桌面小组件的刷新机制（2026-09-30 踩到「开机后还显示昨天」）

小组件不是 App 的一部分：它由**系统广播**唤醒，App 进程往往不存在。所以刷新链路是这样设计的：

| 触发 | 谁来做 | 做什么 |
|---|---|---|
| 系统定时（`updatePeriodMillis=1800000`，至少 30 分钟一次） | `CourseWidgetProvider.onUpdate` | 按**已存计划**重画 —— 跨天就靠这条，不需要 App 前台 |
| 开机 / 应用更新 | `CourseWidgetBootReceiver` | 立刻重画 + 排一次后台任务 |
| 每日 11 点 | `CourseWidgetScheduler`（WorkManager 周期任务） | 起无界面 Flutter 引擎跑 Dart：续排提醒窗口 + 重算计划 |
| App 内课表/主题变更 | Dart 推计划（MethodChannel） | 落盘 + 立刻重画 |

两个必须记住的点：

1. **`updatePeriodMillis="0"` 等于「系统永远不唤醒小组件」** —— 只能靠 App 前台同步，所以才出现「9/30 开机还显示 9/29 的课」。新配置给了 30 分钟兜底。
2. **每日任务必须用 `ExistingPeriodicWorkPolicy.KEEP`**：小组件每 30 分钟触发一次 `onUpdate`，里面会调 `ensure()` 排期；若用 `UPDATE`，每次都会按「距下一个 11 点」重算延迟，任务被无限往后推，**永远等不到执行**。

Dart 与原生之间靠一份「未来 14 天计划」JSON 解耦（`lib/services/course_widget_plan.dart` ↔ `CourseWidgetPlan.kt`），字段契约有单测锁（`test/course_widget_plan_test.dart`）。原生只按 `yyyy-MM-dd` 查表，不碰任何课表业务逻辑。

### ⚠️⚠️ 小组件布局只能用 RemoteViews 白名单里的 View（2026-09-30 踩到「无法加载小部件」）

**症状**：桌面上小组件显示 Android 自己的「无法加载小部件」/「problem loading widget」占位块。旧实例、删掉重加、全新添加**三种情况全挂**，而且 App 侧**看不到任何异常**——因为 RemoteViews 是在**启动器进程**里 inflate 并 apply 的，`onUpdate` 里的 `try/catch` 拦不住对方进程的炸。

框架里有**两道运行时硬校验**（都在 AOSP `RemoteViews.java`）：

| 校验 | 位置 | 要求 |
|---|---|---|
| 布局里的 View 类 | `INFLATER_FILTER = clazz -> clazz.isAnnotationPresent(@RemoteView)` | 类必须带 `@RemoteView`，否则 `InflateException: Class not allowed to be inflated xxx` |
| `setInt(id, "方法名", v)` 反射调用的方法 | `getMethod()` 里 `if (!method.isAnnotationPresent(RemotableViewMethod.class)) throw ActionException(...)` | 方法必须带 `@RemotableViewMethod`，否则 `ActionException: view: ... can't use method with RemoteViews: xxx` |

**白名单**（容器）`FrameLayout / LinearLayout / RelativeLayout / GridLayout`；（控件）`AnalogClock / Button / Chronometer / ImageButton / ImageView / ProgressBar / TextView / ViewFlipper / ListView / GridView / StackView / AdapterViewFlipper / ViewStub`。**自定义 View 和它们的子类一律不行。**

本次就是两个坑叠在一起，各自都能单独把小组件打挂：

1. **`<View>` 不在白名单里**。`android.view.View` 没有 `@RemoteView`，拿它当 1dp 分隔线 → `InflateException`。改用一个 1dp 高的 **`ImageView`**（或 TextView）。
2. **`setInt(id, "setBackgroundResource", resId)` 不是 remotable 方法** → `ActionException: can't use method with RemoteViews: setBackgroundResource(int)`。背景别用反射，**走官方 API `setImageViewResource()`**（`widget_bg` 那张 ImageView 图层）；非要改颜色就用 `setBackgroundColor`（这个是带 `@RemotableViewMethod` 的）。

**回归测试**：`test/course_widget_layout_test.dart` 会解析 `res/layout/widget_*.xml` 的每个标签、以及渲染器里所有 `setInt` 的方法名，一旦越界就报错。改小组件布局后**务必跑它**。

**离线查证的坑**：`@RemotableViewMethod` 是 **SOURCE 保留级**注解，编译后**不会出现在 class 文件里**（`TextView.class` 里搜不到这个字符串），所以**别指望用 android.jar 核方法白名单**；类级的 `@RemoteView` 倒是能查到（`tool/inspect_android_jar_annotations.py`，如 `View`/`ViewGroup` 都没有该注解）。

### ⚠️ `--no-pub` 构建不会重生成插件注册表（2026-09-29 踩到）

Android 的 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 是 **`pub get` 阶段生成的**，`flutter build --no-pub` 不碰它。所以：**新增/移除原生插件后，必须跑一次 `flutter pub get`，否则构建出来的 APK 里插件类在、但没注册**——装到手机上一点功能就 `MissingPluginException`。

这次加 `flutter_inappwebview` 就是这么踩的：APK 构建「成功」，dex 里也搜得到 `InAppWebViewFlutterPlugin`，但 dex 中出现次数只有 1（对照已注册插件通常 ≥2），说明只有 Gradle 编译进去的类，没有注册调用。

**核查办法**（构建后确认插件真的注册了）：

```bash
unzip -p build/app/outputs/flutter-apk/app-release.apk classes.dex \
  | grep -a -o "你的插件类名" | wc -l   # 已注册的插件通常 >= 2（new + 日志串）
```

**教训**：`build 成功` ≠ `功能可用`。加了原生插件后要验「注册表里有它」，别只看 APK 有没有生成。

### ⚠️ AI/CI 会话里的环境坑

- 跑 Flutter 命令前 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY`（注入的本地代理会让 `flutter test` 报 `Invalid WebSocket upgrade request`）。
- 只做静态检查用 `dart analyze lib test`，别用 `flutter analyze`——后者会隐式 `pub get` 并重写 `pubspec.lock`。
- 验 AOT 产物里的字符串要**两种编码都试**：Dart AOT 对部分字符串用 UTF-16LE 存（纯 ASCII 串也会中招），只搜 ASCII 会把已进包的代码误判成没进包。

### ⚠️ 教务 WebView 的缩放：`minimum-scale` 必须比「铺满缩放」更小

桌面模式下页面会被缩到很宽（手机上铺满缩放常在 0.3 左右）。如果 viewport 里写的 `minimum-scale` **大于**这个铺满值，浏览器会把「最小值」当成下限 → **只能放大、缩不回去**（2026-09-30 PD 反馈「只能够放大，我的需求就是缩小」）。

`JwappClient.buildViewportScript()` 因此**按实际算**而不是写死：`fit = min(1, 设备宽/布局宽)`，`minimum-scale = max(0.15, fit*0.5)`。同时 `loadWithOverviewMode` 设为 **false**（它会把铺满缩放当成下限），改由注入的 `initial-scale` 负责「打开即铺满」。布局宽度钉在 `desktopLayoutWidth = 1280`，避免页面自带的 `width=device-width` 把桌面布局挤成移动布局；页面自己声明了数字宽度时尊重它。

### ⚠️ 教务系统（jwapp）解析的四个坑

`jwapp` 是**金智教育**标准产品，接口回的是结构化 JSON（`{"code":"0","datas":{"<表名>":{"rows":[…]}}}`），**不需要 DOM 适配器**。但实测有四个必须小心的点，单测已锁定（`jwapp_course_parser.dart` / `jwapp_semester_parser.dart` 头部注释有完整说明）：

1. `SKZC` 周次位图**长度不固定**（同一次响应里 20 位与 17 位混用）→ 按实际长度解析，**不能**用学期总周数截断。
2. 调课会把同一时段**拆成多条**（`周3 第1-4节 [1,2,3]` + `[4]`）→ 按「课程 + 周几 + 节次 + 地点」合并 weeks 并集，否则课表画出重叠格子。
3. 课程标识**不能用 `KCH` + `KXH`**（同一门课 `01S01` 与 `01` 并存）→ 按「课程名 + 归一化教师」合并。
4. **当前学期不能用 `PX` 判定**（2026-09-29 真机踩到）。`cxjcs.do` 的 80 行里有一条 `PX=null` 的脏行（`2025-2026-3` 暑假小学期，`SFSY` 同样是 1），把 null 当 0 参与排序会把它选成当前学期 → 课表按错的 `XNXQDM` 查询**一门课都查不到**，学期配置也被写成错的开学日。改为**按日期判定**：今天落在 `[开学日, 开学日 + 总周数×7)` 内的学期优先。`JwappSemesterParser.pickCurrent(all, now:)` 的 `now` 可注入以便单测。

> 同一次踩坑的教训：**fixture 不要做有损裁剪**。`make_jwapp_fixture.js` 原本只留最新 12 条学期，恰好把那条毒行截掉了 —— bug 在单测里完全看不见。现在全量保留（80 条）。

另外：接口要 CAS 登录态，**不能用原生 HTTP 客户端**取数，只能在 WebView 页面上下文里 `fetch(..., {credentials:'include'})`；App 只存学校接入点，**不存账密**。原始响应抓包放在 `.capture/`（已 gitignore，含学号姓名，**勿提交**），fixture 用 `node tool/make_jwapp_fixture.js` 脱敏生成。

## 版本记录

- **v1.27.5** (2026-09-30) - 版本发布 **2.1.0**（课表模块首个正式版）+ 清理 glance 遗留：
  - `pubspec.yaml` 版本 `2.0.0+2000` → **`2.1.0+2100`**；`profile_screen.dart` 关于页/版本信息/版本更新条目同步到 2.1.0（`android/app/build.gradle.kts` 的 `versionCode/versionName` 已改为跟随 `flutter.versionCode/versionName`，即 `pubspec.yaml` 单一来源）
  - 清掉 `android/gradle.properties` 里两行**专为 glance 加的**配置（`android.builtInKotlin=false` / `glance.kotlinVersion`）——glance 已移除，留着会改变 Kotlin 编译策略
  - `CHANGES.md` 补 v2.1.0 段（此前停留在 1.0.0）
  - `.gitignore` 增补 `.venv_removebg/`（618MB 本地 venv）、`.superpowers/`、`.workbuddy/`
  - 测试：全量 **164 passed**
  - 新增依赖：无；移除依赖：`glance_widget`（本条目配套 v1.27.3）

- **v1.27.4** (2026-09-30) - 修复小组件「无法加载小部件」（PD 真机反馈：旧实例/删除重加/全新添加**三种场景全挂**）：
  - **根因是两个 RemoteViews 运行时硬校验同时被违反**（都在 AOSP `RemoteViews.java`，且异常抛在**启动器进程**，App 侧完全看不到）：
    1. `INFLATER_FILTER` 要求布局里每个 View 类带 `@RemoteView` —— 我们拿 **`<View>` 当 1dp 分隔线**，而 `android.view.View` 没有该注解 → `InflateException: Class not allowed to be inflated android.view.View`。改用 1dp 高的 `ImageView`。
    2. `getMethod()` 要求 `setInt(id, "方法名", v)` 的方法带 `@RemotableViewMethod` —— 根布局背景用了 **`setBackgroundResource`**（没有该注解）→ `ActionException: view: ... can't use method with RemoteViews: setBackgroundResource(int)`。背景改为官方 API `setImageViewResource` + 新增 `widget_bg` ImageView 图层（同时彻底去掉反射调用）。
  - 顺带修掉布局隐患：根容器改 `FrameLayout`（承载背景图层），内容层由 `wrap_content` 改 `match_parent`，让 `layout_weight` 的行高分配不再依赖父级 `wrap_content` 的测量行为
  - **新增回归测试** `test/course_widget_layout_test.dart`（6 项）：解析两个布局的每个标签做白名单校验、锁死「不许出现 `<View>`/androidx/自定义 View」、校验 `initialLayout` 指向的布局同样合规、校验 `updatePeriodMillis != 0`、扫描渲染器所有 `setInt` 的方法名必须在已知 remotable 白名单内
  - 清理 `proguard-rules.pro`：删掉已随 glance 移除而作废的 `androidx.glance.**` 规则，改为显式 keep 我们自己的 `CourseWidgetProvider/BootReceiver/Worker`（Worker 由 WorkManager 按类名反射实例化）
  - 新增工具 `tool/inspect_android_jar_annotations.py`：离线读 android.jar 里的 `@RemoteView` 类级标注
  - 测试：全量 **164 passed**
  - 新增依赖：无

- **v1.27.2** (2026-09-29) - 修复真机导入「0 课 + 开学日错」（PD 实测反馈）：
  - 根因：`cxjcs.do` 里有一条 `PX=null` 的脏行（`2025-2026-3` 暑假小学期，`SFSY=1`、开学日 `2026-08-31`、总周数 1）。它被当成排序权重 0 → 误判为当前学期 → 课表按 `XNXQDM=2025-2026-3` 查询**返回空**，学期配置也被写成 2026-08-31 开学 1 周。**两个症状同一个根因**
  - `JwappSemesterParser.pickCurrent` 改为**按日期判定**（`now` 可注入，便于单测）；`JwappSemester.sortOrder` 改为可空、null 排最后，`PX` 只在开学日都不可解析时兜底
  - `JwappLoginScreen` 增加**网络级兜底**：带学期码查不到课时，自动退回不带参数重取一次（接口默认返回当前学期）——宁可多一次请求，也不给用户「这学期没课」的错觉
  - 缩放：`displayZoomControls` 改为**显示**自带 +/- 按钮；新增 `JwappClient.buildZoomFixScript()`，在 `onLoadStop` 注入以放开页面自带的 `user-scalable=no`（桌面版页面字号偏小，被页面禁掉缩放就没法放大看）
  - fixture **全量保留**学期行（80 条，原先只留 12 条恰好截掉了毒行）；新增 10 个用例（当前学期判定 6 个分支 / 毒行回归 / 缩放脚本 3 项）

- **v1.27.3** (2026-09-30) - 课表小组件重做 + 修复「开机后还显示昨天」+ WebView 双向缩放（三条都来自 PD 真机反馈）：
  - **小组件自己画**：弃用 `glance_widget` Calendar 模板（布局/文案写死、暗蓝底 + Material 蓝日期块、`+1 more events` 英文），改为 App 模块内自绘 RemoteViews（`CourseWidget*.kt`，暖纸手账风、课程色条、进行中/下一节标记、行数随尺寸自适应）。顺带移除依赖 → 那套「pub 缓存补丁会被 pub get 冲掉」的坑彻底消失
  - **跨天刷新**：此前 `updatePeriodMillis="0"`（系统永不唤醒）+ 只在 App 前台同步 → 开机后仍显示昨天的课。现在三层兜底：系统至少每 30 分钟唤醒重画；开机/应用更新立刻重画；每日 11 点（`CourseWidgetScheduler`，WorkManager）起无界面 Flutter 引擎跑 Dart 续排提醒窗口 + 重算计划
  - **数据解耦**：Dart 预计算未来 14 天课表计划（`course_widget_plan.dart`）推给原生落盘，原生只按日期查表 → 刷新不需要 App 进程。字段契约有 17 个单测锁定
  - **WebView 缩放**：`loadWithOverviewMode` 关掉（它把「铺满宽度」当缩放下限），viewport 由 `JwappClient.buildViewportScript()` 重写 —— `minimum-scale` 按实际铺满缩放计算（旧脚本写死 0.5，而手机上铺满约 0.3 → 下限被钉住，只能放大）
  - 新增依赖：无（改用平台自带 WorkManager + RemoteViews）；移除依赖：`glance_widget`
  - 测试：全量 **158 passed**

- **v1.27.1** (2026-09-29) - 教务系统 WebView 内置**桌面模式**（需求来自 PD：移动 UA 下课表页显示不正常）：
  - `userAgent` 换成桌面 Chrome（`JwappClient.desktopUserAgent`）；`preferredContentMode: DESKTOP`（iOS/WKWebView 生效，Android 忽略）
  - ~~`useWideViewPort` + `loadWithOverviewMode` 让宽页面按宽度缩放铺满屏幕~~ → v1.27.3 已把 `loadWithOverviewMode` 关掉（它会让缩放只能放大不能缩小）
  - `thirdPartyCookiesEnabled` 打开：部分学校的 CAS 登录嵌在 iframe 里，缺第三方 Cookie 会登录失败
  - 设置抽成 `buildJwappWebViewSettings()` 顶层函数并加单测，防止以后被改回移动模式

- **v1.27.0** (2026-09-29) - 课表 M4：教务系统（jwapp / 金智教育 ehall）适配，首个学校 = 西北农林科技大学：
  - 取数链路：`JwappEndpoints`（校名 / 门户地址 / 模块路径 / 两张表 key，预置西农，其它学校手填域名）→ `JwappClient`（生成注入 JS，`fetch` + `credentials:'include'` 带上 CAS Cookie）→ `JwappLoginScreen`（WebView 内登录，手动点「读取课表数据」）→ `JwappCourseParser` / `JwappSemesterParser`（纯 Dart 解析）→ `JwappImportSource` → 既有公共预览页
  - 学期配置**自动带入**（学年 / 学期 / 开学日 / 总周数从教务接口取），且 `toSemesterConfig(mergeWith:)` 保留用户改过的节次时间，仅在冲突时弹确认
  - 接入点持久化 `JwappConfig`（SharedPreferences，**只存学校地址，不存账密**）；课表页导入菜单新增「教务系统导入」+「更换教务系统」
  - 新增依赖：`flutter_inappwebview ^6.1.5`（这是三条导入路径里唯一需要原生插件的一条）。⚠️ 原生插件必须 `flutter pub get` 重生成 `GeneratedPluginRegistrant.java`，`--no-pub` 构建会漏注册（见「常见陷阱」）
  - 测试：`test/jwapp_import_test.dart` 54 个用例（信封拆包 / SKZC 位图 / 教师归一 / 地点拼接 / 单行容错 / 调课合并 / 学期配置 / 真实 fixture 端到端 / 注入脚本 / 回传解析与归属判定 / 接入点配置），fixture 由 `node tool/make_jwapp_fixture.js` 从脱敏抓包生成
  - ⚠️ 解析层已全绿，但**真机登录链路未验**（CAS 登录要 PD 本人操作）；另外教务页面的「列表导出」按钮实测点了没反应，「用户自己导出 → 文件导入」这条零插件路线在西农不成立

- **v1.26.0** (2026-09-29) - 课表模块 M1~M3（T1~T10）：
  - 数据层：`Course / CourseSession / SemesterConfig` + `week_parser`（周次解析/当前周）+ SQLite v14 三表 + Web 双端
  - 视图：周网格课表页、学期设置页、手动增改课程页；「我的」页新增入口
  - 导入：`CourseImportSource` 抽象 + 公共预览确认页；Excel/CSV（动态表头 + GBK）、ICS（RRULE）
  - **图片识别（OCR）：暂缓，未接入 UI**（PD 决定）。代码已写好并保留——`cloud/ocr-proxy/` 云函数中转腾讯云表格识别 V3（密钥不进 APK）、Dart 侧合并单元格还原 + 表头/节次定位 + 单元格语义解析、32 个 fixture 测试；导入菜单里没有入口，原接线版本在 `.rollback/ocr-20260929/`
  - 提醒：滚动窗口 14 天调度，不支持系统级每周重复（单双周表达不了，且会撞系统上限）
  - 小组件：glance_widget Calendar 模板（minSdk 提升 26）
  - 日记联动：写日记页「当日课程」卡片
  - 新增依赖：excel、charset_converter、timezone、glance_widget（OCR 复用已有 image/http/image_picker，未加新依赖）

- **v1.25.0** (2026-05-13) - 浮窗系统体验优化 + 视觉语言统一：
  - 设置持久化修复（`main.dart` 注册 MethodChannel 回调）
  - 木质托盘图片图标、呼吸动画、面板展开动画
  - 应用重启后自动恢复浮窗
  - 官网升级温暖手账风格（`DESIGN_SYSTEM.md`）
  - App 主题背景统一为 `#FDF8F0`，新增品牌色 `#C4956A`
  - 动画原则同步：官网 ScrollReveal stagger/方向/hover 微交互 → App 端 `ScrollReveal`、`InteractiveButton`、`PageTransitions` 统一使用 `PrimitiveAnimation` 设计令牌

- **v1.22.0** (2026-05-04) - 自言自语数据库彻底独立
- **v1.21.0** (2026-04-22) - PDF 导出修复 + 自言自语重构 + 速记功能
- **v1.3.0** (2026-04-10) - 自言自语 + 设计系统升级
- **v1.1.6** (2026-03-28) - 徽章修复 + PDF 字体打包
- **v1.1.0** (2026-03-24) - 目标系统 + 指纹/面容解锁
- **v1.0.0** (2026-03-16) - 🎉 正式发布
