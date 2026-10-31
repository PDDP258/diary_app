# P0 启动链路与 Android 原生层审计（task-3）

审计范围：`lib/main.dart`、`lib/screens/splash_screen.dart`、`lib/providers/*`、
`lib/services/*`（启动路径）、`android/app/src/main/kotlin/com/example/diary_app/*`、
`AndroidManifest.xml`、`build.gradle.kts`、`gradle.properties`、assets。
方式：纯静态阅读（未运行 flutter/dart 工具链、未改动任何源码）。
估算值标注 `≈`，为按文件体积 / 插件实现 / 常见中端机（骁龙 7 系、UFS）经验的量级估算，非实测。

---

## 0. 概览（按严重度）

### P0（直接决定「卡顿 / 闪退」，建议本轮就改）

| # | 问题 | 位置 | 影响 |
|---|---|---|---|
| P0-1 | **Android 端根本没有用 SQLite**：`database_service.dart` 无条件 `export 'database_service_web.dart'`，全部数据（含**所有日记正文的 AES 密文**）存在 SharedPreferences 一个 JSON 字符串里；每篇日记每个字段 `await` 一次 AES 解密 | `lib/services/database_service.dart:3`、`database_service_web.dart:63-87, 91-267, 344-374` | 启动时**全量解密全部日记**（串行 await），数据越多越慢；写日记/删除时**全量重新加密 + 全量 JSON 重写**，且 legacy 插件用 `commit()` **同步落盘** → 主线程卡死 / ANR |
| P0-2 | `main()` 在 `runApp` 前串行 `await` 7 项初始化，其中 **3 项结果完全没被使用**（保护检查、云同步、音效）；主题设置被**读取两次** | `main.dart:24-80`、`course_widget_service.dart:133-143` | 首帧前多阻塞 ≈70–340ms（典型 ≈150–250ms），且全在 UI isolate |
| P0-3 | Splash 固定等待：完整动画 **1200ms + 800ms = 2.0s**，日常路径 **200ms 延迟 + 1200ms = 1.2s**；且 `_showFullAnimation` 初值 `true`，prefs 返回 false 时**会中途切换、把已跑的动画整个丢掉重来** | `splash_screen.dart:97, 109-131, 141-165, 343-385`、`real_page_turn.dart:66-71` | 用户的「启动慢」观感里，**最大的单项就是这 1.2–2.0s 纯等待**（与数据加载无关） |
| P0-4 | `MainScreen` 首帧是**全屏 CircularProgressIndicator + 空数据**，真正数据在 postFrame 才加载 | `main_screen.dart:58, 116-121, 235-256, 546-554` | 「空数据闪屏」+ splash 结束后又出现一次 loading，观感上等于二次启动 |
| P0-5 | `SoundService.initialize()` 创建一个**从未被使用**的 `AudioPlayer()`（audioplayers 每次构造都会走 platform channel 建原生播放器）；`AppProtectionService` 结果被硬编码 `allPassed = true`，纯浪费 | `sound_service.dart:12-21`、`app_protection_service.dart:36-59,191-195`、`main.dart:32-34,42-43` | 白付原生音频引擎初始化 + 4 次 `/proc` 与 `/proc/self/status` 同步读 |
| P0-6 | `CourseWidgetBackgroundRunner` **每次都新建一个完整 FlutterEngine**（20 个插件全注册），开机广播会立刻入队；App 在前台时若该 Worker 触发，**同进程并存两个 Flutter 引擎** | `CourseWidgetBackgroundRunner.kt:43-96`、`CourseWidgetBootReceiver.kt:26-31`、`CourseWidgetScheduler.kt:65-76` | 内存瞬时 +30–60MB；引擎 `destroy()` 时 Dart isolate 可能仍在跑 → native 崩溃/闪退候选 |
| P0-7 | `FloatingWindowService` 前台服务 + 常驻通知 + **INFINITE ValueAnimator 呼吸动画（2200ms 循环，改 scaleX/Y）持续重绘一个 overlay 窗口**；`START_STICKY` 但 `intent == null` 时无任何处理 | `FloatingWindowService.kt:163, 118-127, 390-407` | 浮窗开启后**永久 60fps 重绘 + 额外 window** → 全局掉帧/发热；服务被系统重启后仅剩一条通知、没有浮窗，永不退出 |
| P0-8 | release 签名用 **debug keystore**；**没有 abiFilters / APK 分包**，92MB 的 APK 里打包 arm64-v8a + armeabi-v7a + x86_64 三套 `libflutter.so` / `libapp.so` | `android/app/build.gradle.kts:36-42` | 安装体积翻倍、x86_64 与 v7a 对 99% 设备是死重；debug 签名影响升级/分发信任链 |

### P1

- **调试日志包装器在 release 常驻**：`builder: (context, child) => DebugLogOverlay(child!)`（`main.dart:129-131`）。`DebugLogService` 全仓库**没有任何一处调用 `enable()`**（grep 仅自身），`log()` 首行 `if (!_isEnabled) return;` → release 下它是**纯死代码**，不写文件（这套 service 其实完全没有文件 IO，只在内存 `List<String>`），也不每帧重建（仅 `notifyListeners` 时 `setState`）。真实成本是一个 `StatefulWidget + Stack` 包壳长期占位，**不是**热门元凶，建议直接删除而非优化。
- `CourseProvider()..load()` 在首个 build 就被调起（`main.dart:119`），`load()` 结束即 `_refreshReminders()`（`course_provider.dart:32-47`）→ `CourseReminderService.reschedule` 里 **`tz_data.initializeTimeZones()` 加载 1.1MB Dart 数据 + `pendingNotificationRequests()` + 逐条 `zonedSchedule` 平台调用**，并且还推一次桌面小组件。这些在用户没进课表页时全无必要。
- `ImageCacheService.initialize()` 挂在首屏 `_loadData` 的串行 await 里（`main_screen.dart:240`），启动时扫一遍临时目录（`_cleanOldCache` 是 `void ... async` 未被 await，实际不阻塞，但仍是并发 IO）。
- `CustomGoalProvider()..loadGoals()` → `CustomGoalService.resetDailyProgress()` 启动即读 prefs、可能有写（`custom_goal_provider.dart:21-34`）。
- `SyncLogService.initialize()` 做文档目录 + 文件存在性判断（首次还写 header），只为了一个 1 处调用点的日志（`sync_log_service.dart:12-32`，唯一调用点 `cloud_sync_service.dart:1768`）。
- `MANAGE_EXTERNAL_STORAGE` + `requestLegacyExternalStorage` + 无 `android:allowBackup`（默认 true）在 Manifest 里长期挂着。
- `gradle.properties` 的 `kotlin.incremental=false`、`android.enableJetifier=true`：只拖慢构建，不影响运行时。

### P2

- `initializeDateFormatting('zh_CN')` 在 intl 0.19.0 里是**把全部 locale 的 `dateTimeSymbolMap` / `dateTimePatternMap` 一次性装上**（`date_symbol_data_local.dart` 466KB 源文件），≈5–20ms，可移到首帧后。
- `ThemeProvider.theme` getter 每次 `Consumer<ThemeProvider>` 重建都**新建整个 ThemeData + TextTheme**（`theme_provider.dart:293-423`），主题一变和字体滑块拖动都会全树重建。
- `SplashScreen._buildCoverPage` 用 `Image.asset('splash_cover.png')`（1080×1920，2.3MB）**没有 cacheWidth**，解码 ≈8.3MB 位图，只在完整动画那一次发生。
- `NotoSerifCJKsc-VF.ttf` **23.97MB**（APK 内压缩后 14.76MB）只为 PDF 导出用（`pdf_export_service.dart:50/98/187` 用 `rootBundle.load`），**启动不加载、不在 Application 级注册**，所以不是启动耗时项，但它是包体第一名，可考虑下发/子包化。
- 每个 `activity-alias` 启动器图标 4 套（仅 1 个 enabled），资源体积意义不大，但会多 4 个 launcher 入口。

---

## 1. 启动时间线拆解

### 1.1 阶段表（release，中端机，末列是优化后目标）

| 阶段 | 触发点 | 当前阻塞项 | 估算 | 优化后 |
|---|---|---|---|---|
| A. 进程/Activity 起 | `LaunchTheme`（纯色 windowBackground，无 bitmap）→ `MainActivity.onCreate` | 无 | ≈120–250ms | 不变 |
| B. 引擎/Dart 起 | Flutter JIT-less AOT 加载 `libflutter.so` + `libapp.so`（12MB，`extractNativeLibs=false`） | 无 | ≈150–300ms | 不变（但要砍 ABI） |
| C. **main() 串行 await** | `main.dart:24-80` | 见 1.2 逐项 | **≈70–340ms（典型 150–250）** | **≈0–30ms** |
| D. 首帧 + 原生 splash | `runApp` → `SplashScreen` | 固定动画等待（1.2s / 2.0s）+ 封面图解码 | **≈1200–2000ms + ≈60ms 解码** | ≈150–350ms（动画与加载并行，且只在「愿意等」时播） |
| E. MainScreen 首帧 | `_isLoading = true` | 全屏 spinner（空数据） | ≈16ms 一帧 | 用骨架屏 + 缓存首屏 |
| F. 首屏数据 | postFrame → `_loadData()` | 见 1.3 | **≈300–2500ms（随日记数线性）** | ≈80–250ms |
| G. 后台抢线程 | 首帧后立刻 | tz 数据 + 通知重排 + 小组件推送 + 自动备份 | ≈200–800ms 的竞争 | 挪到 idle/延迟 |

**冷启动到可交互估算：2.5–4.5s → 目标 1.0–1.4s。**

### 1.2 `main()` 串行 await 逐项判定（`lib/main.dart`）

| # | 行 | 调用 | 实际动作 | 阻塞首帧? | 估算 | 结论 / 改法 |
|---|---|---|---|---|---|---|
| 1 | 28 | `initializeDateFormatting('zh_CN', null)` | intl 把**全 locale** 符号表+pattern 表装上（不看入参） | 是 | 5–20ms | 不必阻塞。`DateFormat('...','zh_CN')` 只在少数页面用；移到 `postFrameCallback`。要更狠：只 `initializeDateFormatting()` 后手动 `initializeDateSymbols` 也不行（intl 0.19 数据是常量表），接受这点成本即可 |
| 2 | 32-34 | `AppProtectionService.checkAppIntegrity()`（**仅 release**） | `Directory('/data/data/<pkg>').exists()`、`Directory.current`、读 `/proc/self/cmdline`、**同步**读 `/proc/self/status`、3 次 `Directory.existsSync()`。**不做 APK/dex 哈希**（`_checkFileIntegrity()` 直接 `return true`，`app_protection_service.dart:191-195`），而且最终 `allPassed = true` 硬编码（第 50 行）、`_strictMode=false` → **结果对运行毫无影响** | 是 | 10–30ms | **直接删掉这次调用**（保留 `ProtectionViolationApp` 分支代码不影响）。若一定要留：全部塞 `compute()` 或延到首帧后，且不要把结果作为 `runApp` 的分叉条件 |
| 3 | 37 | `CloudSyncFactory.initialize()` | 懒建 `WebDAVSyncService` → `_loadSettings()`：prefs + `_loadAuthInfo()` 里 **3 次 `FlutterSecureStorage.read`**（首次会触发 EncryptedSharedPreferences/Keystore 初始化） | 是 | 20–100ms | 不必阻塞。云同步只有数据管理页/写日记后 3s 的自动同步用 → 改成真正被用到时 `await CloudSyncFactory.instance.initialize()` |
| 4 | 40 | `SyncLogService.initialize()` | `getApplicationDocumentsDirectory()` + `File.exists()`（首次 `writeAsString` header） | 是 | 5–30ms | 不必阻塞。只有 1 处调用（同步日志） → 改成 `log()` 里懒初始化（它自己已有 `if (_logFilePath == null) await initialize();` 兜底） |
| 5 | 43 | `SoundService.initialize()` | `AudioPlayer()` → audioplayers `_create()` platform channel → 原生播放器实例 | 是 | 15–80ms + 常驻原生对象 | **删掉**。`playClick/playConfirm/...` 全部只用 `HapticFeedback`/`SystemSound`，`_audioPlayer` 只被 null 判空（`sound_service.dart:41`）——连播放都没用它 |
| 6 | 46 | `FloatingWindowService.initialize()` | 同步：`NativeFloatingService.registerCallbacks()` → `MethodChannel.setMethodCallHandler` | 否（同步、极廉价） | <1ms | 保留 |
| 7 | 49-50 | `ThemeProvider().loadSettings()` | `SharedPreferences.getInstance()`（首调 → legacy 插件 `getAll()` 全表读）+ 名称匹配 + 颜色回退 + 字体大小 | 是（但**值得**） | 5–40ms | **保留**（避免主题闪变），但见 #8 的重复读 |
| 8 | 54 | `CourseWidgetService.initialize()` | `_ensureTheme()` → **又 new 一个 ThemeProvider 再 `loadSettings()`（第二次读 prefs）** + `PluginUtilities.getCallbackHandle` + `invokeMethod('registerBackground')`（原生侧顺带 `CourseWidgetScheduler.ensure()` → `WorkManager.getInstance` + `enqueueUniquePeriodicWork`） | 是 | 10–40ms | 拆分：`_ensureTheme` 接受外部传入的 `ThemeScheme`（main 里已有 `themeProvider`），去掉第二次 prefs 读；`registerBackground` 移到首帧后（开机/每日任务不差这 100ms） |
| 9 | 57-59 | `themeProvider.addListener(...)` | 主题变更 → 重推小组件计划 | 否 | — | 保留 |
| 10 | 62-68 | `AutoBackupService.checkAndBackup()` | **未 await**（.then/.catchError）：判断是否 24h 到点，到点则 `getAllDiaries()` + `jsonEncode` + 写文件 + 清理 | 否（并发） | 到点那次 ≈100ms–2s | 已合理，但会与首屏数据加载**抢同一份全量数据/IO**；建议 `Future.delayed(5s)` 或首帧空闲后再跑 |
| 11 | 79-100 | `_autoRestoreFloatingWindow()` | 未 await：`Future.delayed(2s)` → prefs → 权限检查 → **拉起前台服务（常驻通知 + overlay + 无限动画）** | 否 | 2s 后 | 保留延迟思路，但要跟 P0-7 一起改（服务生命周期） |

**结论**：必须阻塞首帧的只有 **#7 主题（1 项）**；#8 应改成「复用已加载的主题、注册放首帧后」；#1–#6 全部可删或后移。删掉 #2/#3/#4/#5 后首帧前省 ≈50–210ms（典型 ≈100–150ms）。

### 1.3 Splash → 首屏时序

```
runApp
 └ SplashScreen.initState
    ├ AppLockService.initialize()          // splash_screen.dart:103，未 await ← 见「附加缺陷」
    └ _checkAnimationType()                // 未 await；_showFullAnimation 初值 true
 build #1: _showFullAnimation==true → SplashPageTurn(pages: [cover, home], delay 1200, flip 800)
          └ 封面页 Image.asset(splash_cover.png) 1080×1920 → 解码 ≈8.3MB 位图（无 cacheWidth）
 prefs 返回 false → setState → build #2: _SimpleSplashAnimation
          └ 已跑的 SplashPageTurn 整棵被丢弃（白等），新动画重新 200ms 延迟 + 1200ms 固定跳转
 onComplete → AppLockService.isEnabled ? AppLockScreen : MainScreen   // 158-187
MainScreen.initState → _isLoading=true → build #1 = 全屏 spinner（空数据）
 postFrame → _loadData()
          ├ ImageCacheService().initialize()
          └ DiaryProvider.loadAllData()   // 这里才第一次碰数据库
 then setState(_isLoading=false) → 真正首屏
```

要点：

1. **固定延时是刚性的、不与任何加载并行**：`SplashPageTurn` 是 `delayBeforeStart` 计时到才 `forward()`，`_SimpleSplashAnimation` 是 `Future.delayed(200)` 起动画 + 另一个 `Future.delayed(1200)` 直接 `onComplete`（**不等动画播完**，`600ms/500ms` 的淡入缩放会被 `pushReplacement` 打断）。
2. **`_showFullAnimation` 初值 true 导致白跑**：首帧必然先建完整动画（含 2.3MB 图片解码），prefs 回来若为 false 就切换 → 浪费一次解码 + 一次动画启动。
3. **两次 Splash→Main 的 Navigator 写法不是「重复跳转」**，而是**两条互斥路径各写一次 `pushReplacement`**：`splash_screen.dart:184`（直接进 Main）与 `app_lock_screen.dart:643/821`（解锁后进 Main）。splash 只跳一次，但都用默认 `MaterialPageRoute`（snackbar 式 300ms 转场），会与 splash 内部刚播完的动画叠加。建议：统一一个 `_enterApp()`，用 `PageRouteBuilder` 零时长或 fade-through。
4. **首屏数据不在 splash 触发**：`DiaryProvider.loadAllData()` 只在 `main_screen.dart:243` 和 `data_management_screen.dart:1090` 调用。splash 期间数据库一次没碰 → 那 1.2–2.0s 完全没用来加载数据，是**纯粹的用户等待空转**。
5. `SplashScreen` 的 `_CoverOutlinePainter`（`CustomPainter`）本身便宜，`shouldRepaint` 已正确比较颜色。

### 1.4 Provider 构造期异步初始化与空数据闪屏

`main.dart:109-120`：

```dart
ChangeNotifierProvider(create: (_) => DiaryProvider()),                       // 不加载
ChangeNotifierProvider.value(value: preloadedThemeProvider ?? (ThemeProvider()..loadSettings())),
ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
ChangeNotifierProvider(create: (_) => CustomGoalProvider()..loadGoals()),
ChangeNotifierProvider(create: (_) => CourseProvider()..load()),
```

- 四个 `..load()` 都是 **fire-and-forget**：`create` 返回时数据为空，`notifyListeners()` 在之后的某个微任务/IO 完成点才触发。首个 build 必定拿到**空 userName / 空目标 / 空课程**。
- `SettingsProvider.loadSettings()`（`settings_provider.dart:34-61`）里还有 `File(avatarPath).existsSync()` —— **同步文件系统调用**在 UI isolate。
- `ThemeProvider` 是 `ChangeNotifierProvider.value` + 顶层 `Consumer<ThemeProvider>`（`main.dart:121-134`）→ 每次 `notifyListeners()`（含 `loadSettings` 完成、字体滑块拖动）都**重建整个 `MaterialApp`**。
- `DiaryProvider` 无构造期加载是正确的；但 `MainScreen._isLoading` 掩盖了「加载完成」与「有空数据」的区分，且 `TimelineScreen.initState`（`timeline_screen.dart:36-44`）**不做任何加载**，完全依赖 MainScreen 那次 —— 于是「首屏有数据」与「进入其他 tab 时数据还在加载」之间存在竞态；`stats/calendar/profile` 还会各自再调 `loadDiaries()`（全量重载 + 全量通知）。

---

## 2. 原生层逐项

### 2.1 `FloatingWindowService.kt`（1278 行，53KB）

| 项 | 结论 | 位置 |
|---|---|---|
| 前台服务 | ✅ 是。`onCreate` → `createNotification()`（`IMPORTANCE_LOW`、`setOngoing(true)`）→ `startForeground(1001, ...)` | `118-127, 183-218` |
| 常驻通知 | 唯一一条，标题「小记速记浮窗运行中」，点回 App。**没有 `stopForeground`，`onDestroy` 里也没有**（靠系统在服务销毁时收） | `211-217, 166-171` |
| 返回策略 | `START_STICKY`（`163`）——**但没有处理 `intent == null` 的粘性重启**：重启后 `onCreate` 只发通知，`showFloatingButton()` 从不执行 → 用户得到一条「浮窗运行中」的僵尸通知 + 一个不出浮窗的服务，**且再也不会自己退出** | `131-164` |
| 视图/刷新 | 3 个 overlay window（button / panel / settings），全部 `TYPE_APPLICATION_OVERLAY`；面板拖动每帧 `windowManager.updateViewLayout`（与动画同帧） | `253-269, 759-778, 786-824` |
| **动画帧率（P0）** | `startBreathingAnimation()`：`ValueAnimator.ofFloat(1.0,1.06,1.0)` + `repeatCount = INFINITE` + 每帧改 `btn.scaleX/scaleY`，**永久运行**（只在触摸/贴边时 `pause`，pause 只是跳过赋值、动画仍在跑）。即一个 overlay 窗口**常驻 60fps 重绘**，浮窗开着时全局掉帧、耗电、发热 | `390-407`（start），`271`（addView 后启动），`409-426`（pause/resume/stop） |
| 贴边动画 | `ValueAnimator.ofFloat(0,1)` 250ms 里每帧改 `params.x/width/height` + `updateViewLayout` + `setPadding` → 每帧触发布局与窗口 resize（最贵的一类动画） | `620-674` |
| 大小动画 | 同上，200ms 逐帧改窗口尺寸 | `478-526` |
| 内存泄漏点 | **类级 `private var` 而非 static**，无 `static Activity/Context` 持有 → 这一项比预期干净。真正的共享态在 `companion object`：`customTags`（String 数组，无害）；跨类静态在 `FloatingWindowPlugin.methodChannel`（**静态 `MethodChannel`，持有 `binaryMessenger`/引擎引用**，服务活着而引擎重建时会指向旧引擎） | `43-60`、`FloatingWindowPlugin.kt:37` |
| Handler | `longPressHandler` / `autoHideHandler` 都是 main looper，`onDestroy` **未 removeCallbacks**（`hideAll()` 只 stop animator / remove view） | `85-90, 1241-1252` |
| inflate | 3 个 layout 全在需要时 inflate（未缓存）；`floating_settings_panel` 每次打开都重建 SeekBar/颜色圆 Drawable | `232, 690, 929` |
| 启动方式 | `FloatingWindowPlugin.startService()` → Android 8+ 用 `startForegroundService`；`showFloatingButton` 的 catch 会吞 `SecurityException`（无悬浮窗权限） | `FloatingWindowPlugin.kt:236-242, 167-170` |

**结论**：浮窗开启时是「严重卡顿」的高概率贡献项（常驻动画 + 多窗口 + 每帧 relayout）；不开启时该服务不运行，与冷启动无关。

### 2.2 CourseWidget 链路

| 文件 | 关键事实 | 位置 |
|---|---|---|
| `CourseWidgetBackgroundRunner.kt` | 每次 `run()` **new FlutterEngine(context)** → `GeneratedPluginRegistrant.registerWith`（**20 个插件全注册**，含 audioplayers / inappwebview / sqflite / secure_storage / notifications）→ `executeDartCallback` → `CountDownLatch.await(25s)` → `engine.destroy()` | `43-96` |
| 线程 | `run()` 由 `Worker.doWork()` 调用（WorkManager 后台线程），`await` 阻塞的是 worker 线程，**不阻塞主线程** ✅。但引擎创建/销毁本身会碰主线程（FlutterEngine 构造要求调用方线程有 Looper，`FlutterEngine(context)` 会 attach 到当前线程） | — |
| 与前台并发 | ⚠️ **会**。`CourseWidgetBootReceiver` 在 `BOOT_COMPLETED / MY_PACKAGE_REPLACED` 里 `refreshSoon()` 入队 → 若用户此时正打开 App，同进程两个引擎并存（内存 +30–60MB，插件重复注册，`destroy()` 打断仍在跑的 isolate） | `CourseWidgetBootReceiver.kt:26-31`，`CourseWidgetScheduler.kt:65-76` |
| WorkManager | 每日 24h 周期任务，`setInitialDelay` 到 11:00，`ExistingPeriodicWorkPolicy.KEEP`（这个用法是对的，注释里也解释了 UPDATE 会被 30 分钟 `onUpdate` 无限顺延的坑） | `CourseWidgetScheduler.kt:40-59` |
| RemoteViews 刷新 | `updatePeriodMillis=1800000`（30 分钟）→ 系统每 30 分钟**拉起 App 进程**跑 `onUpdate`（`updateAll` + `ensure()`，后者会 `WorkManager.getInstance`）。每次是**冷启进程**（不启 Flutter 引擎），但会重新 `getSharedPreferences` + 解析 JSON + 画位图 + `updateAppWidget` | `res/xml/course_widget_info.xml`、`CourseWidgetProvider.kt:22-30` |
| 渲染 | `CourseWidgetRenderer.render` 每次解析 `plan_json` 全量 JSON，位图缓存 `HashMap` 静态、超 48 清空；正常情况下按「今天」一天查表，成本低 ✅。`SimpleDateFormat` 每次 new（3 个），可忽略 | `CourseWidgetRenderer.kt:31-33, 291-314` |
| Worker 顺序 | `doWork()`：先 `updateAll` → 起 Dart → 再 `updateAll` → 永远 `Result.success()`（不重试）✅ 设计合理 | `CourseWidgetWorker.kt:22-38` |
| 开机 receiver 数 | 3 个都会响应 `BOOT_COMPLETED`：`CourseWidgetBootReceiver`、`flutter_local_notifications` 的 `ScheduledNotificationBootReceiver`、`androidx.work` 的 `RescheduleReceiver`（后者 `enabled=false`）。**3 个 receiver 各启动一次 App 进程/走一次 Application** | Manifest `161-170, 130-143` |

### 2.3 `MainActivity.kt`（23 行）

- 基类 `FlutterFragmentActivity`（不是 `FlutterActivity`）—— 为了 `local_auth` 的 fragment 宿主，是正确的选择，但比 `FlutterActivity` 多一层 FragmentActivity 初始化。
- `configureFlutterEngine` 注册 **3 个 channel**：`IconThemePlugin`、`FloatingWindowPlugin`、`CourseWidgetPlugin`。全部是 `setMethodCallHandler`，**无阻塞调用、无 IO**，成本可忽略 ✅。
- 没有 `enableImpeller` / `setFlutterEngine` 等自定义；无 `GeneratedPluginRegistrant` 手动调用（自动，20 插件）。

### 2.4 `AndroidManifest.xml`

| 项 | 值 | 评价 |
|---|---|---|
| 启动 activity theme | `@style/LaunchTheme` → `windowBackground=@color/ic_launcher_background`（`#FF6B6B` 纯色），另有 `NormalTheme` `@android:color/white` | ✅ 纯色、无大图，首帧前无额外解码。但 **`NormalTheme` 是白色**，珊瑚红→白→Flutter 首帧，深色模式也走 `Theme.Light.NoTitleBar` → 深色闪白 |
| `largeHeap` | **未声明** | 默认堆（视机型 128–512MB）。配合 8.3MB splash 位图 + 1200px 缩略图 + 全量日记密文，低内存机 OOM 风险高 |
| `android:allowBackup` | 未声明 → 默认 `true` | 加密密钥在 Keystore/EncryptedSharedPreferences，备份恢复到新机后**密钥缺失 → 全部日记解密失败**（闪退/白屏候选） |
| `exported` | `MainActivity=true`（带 `diaryapp://` deep link）、4 个 `activity-alias` 全 `exported=true`（3 个 `enabled=false`）、`CourseWidgetProvider=true`、`FloatingWindowService=false` ✅ | deep link 无条件 `VIEW` 过滤，任何应用可拉起；建议加 `host` 校验 |
| 服务 | `FloatingWindowService`，`foregroundServiceType="specialUse"` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` | 合规写法，但 Play 上架需说明；Android 14+ 需保证 `startForeground` 类型匹配 |
| receiver | 3 个开机相关 + `ScheduledNotificationReceiver` + `CourseWidgetProvider` | 见 2.2 |
| 权限 | `MANAGE_EXTERNAL_STORAGE`（Play 政策高风险）、`SYSTEM_ALERT_WINDOW`、`POST_NOTIFICATIONS`、`WAKE_LOCK`（**代码里没有任何 `PowerManager.WakeLock`/`AlarmManager` 使用** → 该权限是空申请，可删）、`FOREGROUND_SERVICE*`、`RECEIVE_BOOT_COMPLETED` | 建议清掉未使用权限，减少安装时权限面与商店审核风险 |
| `androidx.startup` provider | WorkManager + EmojiCompat + ProcessLifecycle + ProfileInstaller 四个 initializer 均随进程启动 | `EmojiCompatInitializer` 会加载 emoji2 字体元数据，≈几 ms；可考虑 `tools:node="remove"` 掉 EmojiCompat（App 未用 emoji2 兼容渲染） |

### 2.5 `build.gradle.kts` / `gradle.properties` / 构建产物

> ⚠️ **对 Lead 的一个更正**：`android/app/build.gradle.kts` 里确实**没有** `isMinifyEnabled` / `isShrinkResources`，但 **Flutter Gradle 插件会自动给 release 打开 R8 + 资源收缩**
> （`C:\flutter\flutter\packages\flutter_tools\gradle\src\main\kotlin\FlutterPlugin.kt:263-280`：`isMinifyEnabled = true`、`isShrinkResources = isBuiltAsApp(project)`、并自动加 `proguard-android-optimize.txt` + `flutter_proguard_rules.pro` + 项目的 `proguard-rules.pro`）。
> 证据：`build/app/outputs/mapping/release/` 下有 `mapping.txt`(35.8MB) / `configuration.txt` / `seeds.txt` / `usage.txt` / `resources.txt`；APK 内 `classes.dex` 只有 1 个、1.8MB。
> **所以混淆与资源收缩是开着的**，`proguard-rules.pro` 里的 keep 规则也是生效的。真正缺的是 **ABI 拆分** 与 **签名**。

| 项 | 当前 | 问题 / 建议 |
|---|---|---|
| `minSdk` | **26** | 与「桌面小组件 + 通知渠道 + 前台服务」一致 ✅。26 意味着**不能享受 Android 8 以下的分支裁剪**，但市场覆盖率 OK |
| `targetSdk` | **36**（`flutter.targetSdkVersion`，合并后 manifest 已确认 36） | targetSdk 36 意味着 Android 15/16 的**前台服务类型强制、`specialUse` 审核、后台启动限制、edge-to-edge 强制**全部生效 —— 浮窗服务与 16KB page size 也进入范围。建议先确认 16KB page size 兼容（`libflutter.so` 需 Flutter 3.29+，本项目为 3.x 较新版本） |
| `compileSdk` / `ndkVersion` | 跟随 flutter | — |
| minify / shrink | 由 Flutter 插件开启（见上） ✅ | 不用手写 `isMinifyEnabled=true`（重复无害但易误以为没开） |
| **abiFilters / splits** | **无** | ❗APK 92.2MB：`lib/armeabi-v7a/libflutter.so 7.89MB + libapp.so 13.38MB`、`lib/arm64-v8a/libflutter.so 10.79 + libapp.so 11.75`、`lib/x86_64/libflutter.so 11.98 + libapp.so 12.06` + 各 `libdartjni.so`。**x86_64 对真机完全无用、v7a 对 64 位设备无用**。建议 `splits.abi { enable true; universalApk false }`（每 ABI 约 −30MB）或 `abiFilters += listOf("arm64-v8a","armeabi-v7a")`（Play AAB 已自动按 ABI 分发，发 APK 时必须手动） |
| 签名 | **`signingConfig = signingConfigs.getByName("debug")`**（注释里还留着 TODO） | ❗发布包用 debug key：无法上架、无法与正式签名的旧包升级、可被随意重签替换。必须建正式 keystore |
| `coreLibraryDesugaring` | 开启，`desugar_jdk_libs:2.0.4` | 必要（`flutter_local_notifications` 17.x 需要），保留 |
| `android.enableJetifier=true` | 开 | 只影响构建速度；若所有依赖已完成 AndroidX 迁移可关（本项目插件较新，大概率可关，需一次全量构建验证） |
| `kotlin.incremental=false` | 关掉了增量 | 只拖慢构建（Kotlin 全量重编），不影响运行时；建议改回 true |
| `org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G` | 偏大 | 只影响构建 |
| 符号级别 | R8 默认（不保留行号时 stacktrace 无行号） | 建议 release 保留 `-keepattributes SourceFile,LineNumberTable` + 上传 `mapping.txt`，否则线上闪退堆栈无法定位（与本次「频繁闪退」排查直接相关） |

### 2.6 assets / 资源体积

| 资源 | 源文件 | APK 内 | 启动加载? | 结论 |
|---|---|---|---|---|
| `assets/fonts/NotoSerifCJKsc-VF.ttf` | 23.97MB | 14.76MB（压缩） | ❌ 不加载（仅 PDF 导出时 `rootBundle.load`，`pdf_export_service.dart:50/98/187`） | 包体第一名。**不是**启动耗时项，也不是全局字体（`pubspec.yaml` 只在 `assets:` 里列，没进 `fonts:` 段 → 不会注册成全局 fontFamily；`design_tokens.dart:183` 的 `serifHeading='NotoSerifSC'` 全仓库无使用点）。建议按需下载或放 AAB 动态模块 |
| `assets/images/splash_cover.png` | 2.3MB，1080×1920 | 2.3MB（png 不压缩） | ✅ 完整动画首帧解码 ≈8.3MB（`int` 位图 1080*1920*4） | 加 `cacheWidth`/降采样，或换成 1080 宽的 WebP；只在完整动画用 |
| `mipmap-*` 5 套启动图标 | xxxhdpi 单张 ≈57KB | — | ❌ | 无启动影响 |
| `CupertinoIcons.ttf` 0.25MB + MaterialIcons 0.02MB | — | — | Flutter 内建 | — |
| debug APK 185.5MB 仍在 `build/` | — | — | — | 确认未误发（发的是 `flutter-apk/app-release.apk` 92.2MB ✅） |

---

## 3. 闪退嫌疑：3 条假设 + 验证方法

### H1（最高概率）：SharedPreferences 当数据库 → 主线程 ANR / OOM 被杀

- 依据：`database_service.dart:3` 无条件 `export 'database_service_web.dart'`；实测 AOT 快照里有 `diaries_data`、`diaries_metadata` 字符串，**没有 `diary_app.db`**（`openDatabase` 只在无人 import 的 `database_service_native.dart:49`）。`sqflite` 依赖仍在，插件也注册了，但**代码路径从不使用**。
- 后果链：
  1. 启动 `_ensureInitialized()` → `_prefs.getString('diaries_data')`（单键巨型 JSON）→ `jsonDecode` 全部日记 → `_decryptDiariesSync` **逐篇 `await` AES-CBC 解密 title+content**（`database_service_web.dart:102-105, 235-267, 361-374`）。
  2. 写日记/删除 → `_saveDiaries()` → `Future.wait` 对**全部日记重新加密** → `jsonEncode` 全量 → `prefs.setString`。
  3. `shared_preferences_android 2.4.23` 的 **legacy** 实现（`SharedPreferences.getInstance()` 走的就是它）每个 set 都是 `preferences.edit().putString(...).commit()` —— `commit()` 是**同步磁盘 fsync**，且方法通道在平台主线程执行（`LegacySharedPreferencesPlugin.java:79-117`）。
- 症状解释：日记数上千/含长文时 —— 启动转圈很久（H1 与 P0-4 叠加）、保存一篇日记卡 1–5s、切后台被 LMK 杀、极端时 ANR「应用无响应」→ 用户描述为「卡顿 + 闪退」。
- 验证：

```bash
# 1) prefs 体积（最直接的一枪）
adb shell run-as com.example.diary_app ls -l shared_prefs/
adb shell run-as com.example.diary_app du -h shared_prefs/FlutterSharedPreferences.xml

# 2) 启动时主线程在干什么
adb shell am start -W -n com.example.diary_app/.MainActivity_coral
adb logcat -c && adb logcat | Select-String -Pattern "ANR in com.example","Skipped [0-9]+ frames","Davey","Choreographer"
adb shell dumpsys activity anrs | Select-String -Pattern "diary_app" -Context 0,30

# 3) (debug 包) 用 DevTools 抓 timeline
flutter run --profile --trace-startup
#   观察 UI/Raster 线程：_ensureInitialized / _decryptDiariesSync 应占大段
adb shell dumpsys gfxinfo com.example.diary_app
```

### H2：浮窗前台服务生命周期缺陷（僵尸服务 + 无限动画 + 粘性重启）

- 依据：`START_STICKY` 且 `onStartCommand` 对 `intent == null` 无分支（`FloatingWindowService.kt:131-164`）；`onDestroy` 不 `stopForeground`、不 `removeCallbacks`；`breathingAnimator` `INFINITE`（`390-407`）；`_autoRestoreFloatingWindow` 在 App 每次启动 2s 后都会尝试拉起（`main.dart:79-100`）。
- 症状：浮窗开着时全局卡顿/发热；被系统或用户杀掉后服务重启 → 只剩通知；部分 ROM（MIUI/EMUI）对 `specialUse` 前台服务 + overlay 组合会直接强杀 → 表现为「闪退」（实际是 process kill，logcat 可能只有 `lowmemorykiller` 或 `ActivityManager: Killing`）。
- 验证：

```bash
adb shell dumpsys activity services com.example.diary_app | Select-String -Pattern "FloatingWindowService","isForeground","startId","crash"
adb logcat -b events | Select-String -Pattern "am_kill","am_proc_died","lowmemorykiller"
adb logcat | Select-String -Pattern "FloatingWindowService","SecurityException","BadTokenException","Unable to add window"
adb shell dumpsys window windows | Select-String -Pattern "TYPE_APPLICATION_OVERLAY"
```

### H3：同进程第二个 FlutterEngine（CourseWidgetBackgroundRunner）导致 native 崩溃

- 依据：每次 `run()` 都 `new FlutterEngine` + 注册 20 个插件 + `executeDartCallback` + 最多等 25s + `engine.destroy()`（`CourseWidgetBackgroundRunner.kt:43-96`）；开机/应用更新立刻 `refreshSoon()`（`CourseWidgetBootReceiver.kt:26-31`）。若此时 App 在前台 → 两个引擎、两套插件（`shared_preferences` DataStore、`flutter_local_notifications`、`audioplayers`、`inappwebview`）在同一进程重复初始化；`destroy()` 时 Dart isolate 可能未停（超时路径只 `Log.w` 不取消）。
- 症状：开机后首次打开 App 或应用更新后概率性闪退，tombstone/SIGSEGV 或 `Fatal signal 11`，堆栈常在 `libflutter.so`/`libapp.so`。
- 验证：

```bash
adb logcat | Select-String -Pattern "CourseWidgetBg","FlutterEngine","FATAL EXCEPTION","libflutter","tombstone","SIGSEGV","SIGABRT"
adb shell run-as com.example.diary_app ls /data/tombstones 2>$null
adb shell dumpsys jobscheduler | Select-String -Pattern "course_widget_daily_refresh","CourseWidgetWorker" -Context 0,3
adb shell dumpsys activity broadcasts | Select-String -Pattern "BOOT_COMPLETED" -Context 0,2
# 触发一次后台任务看是否必崩：
adb shell cmd jobscheduler run -f com.example.diary_app <jobId>
```

### 补充嫌疑（低成本排查）

- **H4 内存**：`largeHeap` 未开 + splash 8.3MB 位图 + **全屏看图用原图**：`ImageViewerScreen` 的每一页都是 `OriginalImage`（`diary_detail_screen.dart:1227`，`image_cache_service.dart:538-551` 直接 `Image.file` **无 cacheWidth/cacheHeight**）套在 `PageView + InteractiveViewer` 里 → 一张 12MP 手机照片解码 ≈48MB 位图，PageView 预加载相邻页 → **瞬时 100–150MB**，且 Flutter 的 ImageCache 默认上限 100MB/1000 张，很容易把整个堆顶到 LMK 阈值。同时 `_checkMotionPhotos()` 在 `initState` **串行遍历全部图片**（`diary_detail_screen.dart:1152-1167`，每张 `File.exists` + `MotionPhotos` 解析）—— 图片多时进看图页会明显卡。验证：`adb shell dumpsys meminfo com.example.diary_app` 看 `TOTAL PSS` 与 `Graphics`；`adb logcat | Select-String "OutOfMemoryError","Failed to allocate","onTrimMemory"`；DevTools Memory 里看 `ImageCache` 的 `currentSizeBytes`。改法：`OriginalImage` 加 `cacheWidth: deviceWidth * dpr`、PageView 只保 1 张预热、`_checkMotionPhotos` 改为仅检测当前页。另外缩略图生成走 `compute()` isolate（`image_cache_service.dart:139-142`）✅，但**每张都先 `readAsBytes()` 整文件再进 isolate**，多图详情页会瞬时占大内存。
- **H5 密钥丢失**：`EncryptionService.initialize()` 首次会生成密钥写 EncryptedSharedPreferences（`encryption_service.dart:23-35`）；若 Keystore 解锁失败/系统备份恢复导致密钥缺失，`decryptTextV2` 的 catch **返回密文**（不是 null，`encryption_service.dart:228-231`）→ 不崩但显示乱码；而 `_decryptWithStoredIV` 失败返回 `null` → `Diary.content = null` → 后续 `content!` 可能 NPE 崩溃。验证：`adb logcat | Select-String -Pattern "解密失败","EncryptionService","javax.crypto"`。
- **H6 `AppLockService` 竞态**：`SplashScreen.initState` 里 `AppLockService.initialize()` **未 await**（`splash_screen.dart:103`），而 `_onSplashComplete` 用 `AppLockService.isEnabled`（`splash_screen.dart:174`，`isEnabled` 在 `_initialized == false` 时**同步返回 false**，`app_lock_service.dart:44-50`）。若 1.2s 内 prefs 还没读完（冷启动 + 主线程被 P0-1 阻塞时很可能）→ **应用锁被静默跳过**（安全缺陷，不是闪退，但同属 P0 风险）。

---

## 4. 改法（按优先级，含片段）

### 4.1 P0-1：把数据层换回 SQLite，或至少把「全量解密」从启动路径摘掉

最小可行改法（不想动数据层的话）：`database_service` 恢复条件导出，Android 走 `database_service_native.dart`（已实现、schema v15、已加密字段），Web 走 web 版：

```dart
// lib/services/database_service.dart
export 'database_service_native.dart'
    if (dart.library.js_interop) 'database_service_web.dart';
```

⚠️ 这是**最高收益也最高风险**的改动：需要一次性迁移脚本把 `FlutterSharedPreferences.xml` 里 `flutter.diaries_data` 等键解密后写入 SQLite，并保留回滚路径。风险点：存量用户数据、加密字段格式（`__ENC2__`）、`_diaryIdCounter` 等计数器。建议单独任务（task-4?）并先写迁移单测。

若本轮不做迁移，**至少**做：`_decryptDiariesSync` 只解密**首页需要的 20 篇**，其余懒解密（把 `_decryptDiaryMap` 从 `_loadData` 里拆出，改在 `getDiary(id)` 时按需解密）。

### 4.2 P0-2：重排 `main()`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 只要主题：首帧必须拿到（避免闪变）
  final themeProvider = ThemeProvider();
  await themeProvider.loadSettings();

  runApp(MyApp(preloadedThemeProvider: themeProvider));

  // 其余全部让出首帧
  WidgetsBinding.instance.addPostFrameCallback((_) {
    initializeDateFormatting('zh_CN', null);           // 或延到首个 DateFormat('...','zh_CN') 之前
    if (!kDebugMode) AppProtectionService.checkAppIntegrity(); // 结果本就未使用
    CloudSyncFactory.initialize();                      // 改为用到时懒初始化
    SyncLogService.initialize();                        // log() 已有兜底，可删
    // SoundService.initialize();                       // 直接删除
    CourseWidgetService.initialize(theme: themeProvider.currentScheme); // 复用已加载主题
  });
}
```

### 4.3 P0-3/P0-4：splash 与首屏并行 + 去掉空数据帧

- `_showFullAnimation` 初值改 `false`（或 `bool?` 三态：`null` 时先画静态品牌页），**先读 prefs 再决定播哪一种**；动画期间同时发起 `DiaryProvider.loadAllData()`。
- 完成条件从「动画播完」改成 `Future.wait([动画, 数据])`，并设 300ms 下限（太快反而闪）。
- `MainScreen` 首帧不要全屏 spinner：用 `SkeletonLoading`（项目已有该组件，`lib/widgets/skeleton_loading.dart`）。
- 统一入口：

```dart
// splash_screen.dart
void _enterApp() {
  if (_isCheckingLock) return;
  _isCheckingLock = true;
  final next = AppLockService.isEnabled ? const AppLockScreen() : const MainScreen();
  Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, __, ___) => next,
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
    ),
  );
}
```

- `_SimpleSplashAnimation` 的 `Future.delayed(1200)` 改为「动画完成 + 数据就绪」再跳；至少把 1200 压到 400–600。

### 4.4 P0-5/P0-6/P0-7 原生

- `SoundService`：删 `AudioPlayer`（只保留 Haptic/SystemSound）；`initialize()` 保留空壳即可。
- `CourseWidgetBackgroundRunner`：

```kotlin
// 复用引擎而不是每次新建（同进程只允许一个后台引擎）
object CourseWidgetBackgroundRunner {
    private val engineLock = Any()
    @Volatile private var bgEngine: FlutterEngine? = null

    fun run(context: Context): Boolean = synchronized(engineLock) {
        // 若主引擎正在跑且 App 在前台，直接跳过（降级为只重画，Worker 已先 updateAll）
        if (isAppForeground(context)) return false
        ...
    }
}
```

短期最低成本改法：`Worker.doWork()` 里先判断进程里是否已有活跃 Flutter 引擎/是否前台，前台就只 `updateAll` 不启引擎；并把 `DONE_TIMEOUT_SECONDS` 从 25s 降到 8s。

- `FloatingWindowService`：
  - 呼吸动画改 `AnimationController`-等价的显式时长（如 3 个循环后 `stop()`），或干脆用 `ObjectAnimator` + `setRepeatCount(2)`；`onTaskRemoved`/`intent==null` 时 `stopSelf()` + `stopForeground(STOP_FOREGROUND_REMOVE)`。
  - `onDestroy` 里 `longPressHandler.removeCallbacksAndMessages(null)`、`autoHideHandler.removeCallbacksAndMessages(null)`。
  - 贴边/缩放动画不要逐帧改窗口尺寸：改 `view` 的 `scaleX/Y + translationX`，一次动画结束再 `updateViewLayout` 定稿。

### 4.5 P0-8 构建

```kotlin
// android/app/build.gradle.kts
android {
    defaultConfig { /* minSdk 26, targetSdk 36 保持不变 */ }
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a")   // 去掉 x86_64；需要模拟器调试时用 debug 包
            isUniversalApk = false
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true          // 显式声明，与 Flutter 插件一致，避免误解
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")  // ← 必须建正式 keystore
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            ndk { debugSymbolLevel = "SYMBOL_TABLE" }  // 便于线上 native 崩溃定位
        }
    }
}
```

并在 `gradle.properties` 恢复 `kotlin.incremental=true`、评估关掉 `android.enableJetifier`。

### 4.6 顺手清理

- 删 `DebugLogOverlay` 包壳（`main.dart:129-131`）—— 全仓库无 `enable()` 调用，release 纯死代码。
- `WAKE_LOCK` 权限（无任何使用点）、`MANAGE_EXTERNAL_STORAGE`（如非必需）从 Manifest 移除。
- `<application android:allowBackup="false" android:fullBackupContent="false">` 或提供 `data_extraction_rules`，避免密钥/密文跨设备迁移后解密失败。
- `NormalTheme` 的 `windowBackground` 改主题色（`#FDF8F0`）/ night 用深色，消除白闪。

---

## 5. 仍未覆盖 / 需要后续验证

1. `_decryptDiariesSync` 的真实耗时随日记数曲线 —— 需要真机 profile（`flutter run --profile` + DevTools）确认，我只能给量级估算。
2. ~~`shared_preferences_android` 中 `getAll` 是否跑在主线程~~ → **已核实（静态证据，无需真机）**，见下方「补充证据 A」：`SharedPreferences.getInstance()` 会把**整个 prefs 文件的所有键值一次性搬进内存缓存**，其中包括那个巨型 `flutter.diaries_data` JSON 字符串。也就是说**进程里任何一次 `SharedPreferences.getInstance()` 都会把全部日记密文读进内存**（ThemeProvider / SettingsProvider / AppLockService / FloatingSettingsService / CourseWidgetService 都各自碰它，但因为有 `_completer` 单例所以只读一次盘）。这一步是主线程之外的 IO，本身不 ANR，但**它是 `_decryptDiariesSync` 之前的那次内存翻倍点**：XML 解析出一份完整 JSON 字符串（≈日记总量），`jsonDecode` 再产出一份 List，随后逐篇解密又产出一份，峰值三份并存。这解释了「大用户 OOM / 后台被 LMK 杀」。

   **补充证据 A（已核实）**：
   - `shared_preferences-2.5.4/lib/src/shared_preferences_legacy.dart:79-97`：`getInstance()` 单例 `_completer` → `await _getSharedPreferencesMap()` → 构造 `SharedPreferences._(preferencesMap)`。
   - 同文件 `:107` `final Map<String, Object> _preferenceCache;`、`:113` `Object? get(String key) => _preferenceCache[key];` —— **所有键一次性全量载入内存**，不是按需读。
   - `shared_preferences_android` 的 legacy 插件 `LegacySharedPreferencesPlugin.java:121-131` `getAll()` 返回 `preferences.getAll()` 全表；写路径 `:75-117` 全部是 `edit().putXxx(...).commit()`（同步 fsync）。
   - 因此：**`flutter.diaries_data` 这个键的大小 = 全部日记密文总量**，每次冷启动必定全量进内存 + 全量 `jsonDecode` + 全量 AES 解密。数据量越大，启动越慢、内存峰值越高。这是 P0-1 的强佐证。
3. 未审计（不在 task-3 范围）：`lib/screens/*` 的列表滚动性能。但**已确认一项需要转给 UI 层任务的高嫌疑项**：`lib/widgets/theme_backgrounds.dart` 的 5 套特殊主题（星空/樱花/海洋/极光/黄金）都是 `AnimationController..repeat()`（`theme_backgrounds.dart:57, 657, 663, 669, 1293, 1562, 2012`）+ `shouldRepaint => true` 的 `CustomPainter`（`:624, 1244, 1494, 1983, 2250`），而 `ThemeBackgroundFactory.wrap` 在 `main_screen.dart:615` 把 PageView **整体**包在里面 → 选中特殊主题时，**4 个 tab 的所有内容都叠在一个永久 60fps 全屏重绘的 CustomPaint 之上**。粒子数本身不算离谱（樱花 25 瓣 `:67`、海洋 15 `:672`、黄金 4+15 `:1584-1598`、星空 4 流星 `:2034`+星点 `:2023`），但整屏重绘没有 `RepaintBoundary` 隔离、也没有降帧策略。**影响量级需真机 profile 确认**（估算每帧 3–8ms 的中端机成本），不作为 P0 断言，建议由 UI 任务实测后决定是否加 `RepaintBoundary` / 降到 30fps / 仅在 tab 0 启用。
4. 未做 APK 内 dex 方法数 / 启动类加载统计（需 `apkanalyzer` 或 Android Studio profiler）。
5. **未实测任何耗时**：本报告中所有 ms 均为量级估算（依据文件体积、插件实现、常见中端机经验），结论的优先级排序依据是「代码路径必然发生」+「数据量线性放大」，建议以 `flutter run --profile --trace-startup` 与 DevTools 的实测值替换。

---

## 附加缺陷清单（非性能，但审计发现，按严重度）

| 缺陷 | 位置 | 说明 |
|---|---|---|
| 🔴 应用锁可能被静默跳过 | `splash_screen.dart:103, 174` + `app_lock_service.dart:44-50` | `initialize()` 未 await，`isEnabled` 在未初始化时返回 false → 冷启动竞态下绕过锁 |
| 🟠 release 包 debug 签名 | `android/app/build.gradle.kts:36-42` | 无法上架/无法升级已有正式包 |
| 🟠 无 `allowBackup=false` | `AndroidManifest.xml:31-36` | 备份恢复后加密密钥缺失 → 数据不可读 |
| 🟠 `getDiary` NPE 风险 | `database_service_web.dart:430-437` + `decryptTextV2` 返回 null | 解密失败时 `content` 为 null，多处 `content!` 可能崩 |
| 🟡 `AppLockScreen` 也写一份 `pushReplacement → MainScreen` | `app_lock_screen.dart:643, 821` | 与 splash 的跳转重复维护，建议收敛成一个入口 |
| 🟡 `START_STICKY` 未处理 null intent | `FloatingWindowService.kt:131-164` | 僵尸通知 |
| 🟡 `WAKE_LOCK` 权限空申请 | `AndroidManifest.xml:29` | 权限面清理 |
| 🟡 `stats_screen`/`calendar_screen` 各自全量 `loadDiaries()` | `stats_screen.dart:98`、`calendar_screen.dart:1373/1387` | 数据层不分页时，每次进 tab 都是一次全量替换 + 全树通知 |

---

*生成时间：2026-10-28 · 只读审计，未修改任何源码*
