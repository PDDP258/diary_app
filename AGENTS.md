# 小记日记 - AI协作指南

版本: 1.25.0 (2026-05-13) | 技术栈: Flutter 3.x + Provider + SQLite

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
// ✅ 正确 - MainScreen 使用 Stack 精确定位
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
// ❌ 错误 - SafeArea(bottom: true) 或 Scaffold(bottomNavigationBar: ...) 会导致遮挡
```

**关键要点：**
1. `extendBody: false`
2. `Stack` + `Positioned` 手动控制布局
3. 内容底部留出 `systemNavBarHeight + 96`
4. 软件导航栏位于 `bottom: systemNavBarHeight`

### 2. 导航栏行为（强制）

```dart
bool _onScrollNotification(ScrollNotification notification) {
  if (notification is ScrollUpdateNotification) {
    final maxScroll = notification.metrics.maxScrollExtent;
    if (maxScroll > 0) {
      final scrollDelta = notification.scrollDelta ?? 0;
      if (scrollDelta > 10) { _hideNavBar(); _inactivityTimer?.cancel(); }
      else if (scrollDelta < -5) { _showNavBar(); _resetInactivityTimer(); }
    }
  }
  return false;
}
```

**行为规则：** 下滑隐藏，上滑显示+3秒后隐藏，点击无效区域显示+3秒后隐藏。

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
├── screens/      # 页面（calendar, write_diary, profile, self_talk...）
├── services/     # 数据库、加密、云同步、PDF导出、徽章、图片缓存、浮窗、备份
├── providers/    # 状态管理（DiaryProvider, ThemeProvider, SettingsProvider...）
├── models/       # 数据模型（Diary, Mood, Tag, Anniversary, QuickNote, SelfTalkMessage...）
├── widgets/      # 组件（贴图覆盖层、音效按钮、浮窗UI...）
├── utils/        # 工具类（平台图片、图片缓存）
└── config/       # 主题配置
```

## AI Skills

- **interaction-design** (`.kimi/skills/interaction-design/`)：微交互、动画过渡、加载状态
- **visual-design-foundations** (`.kimi/skills/visual-design-foundations/`)：8-point网格、字体层级、色彩系统
- **design-system-patterns** (`.kimi/skills/design-system-patterns/`)：Design Tokens、主题切换、组件变体
- **react-native-design** (`.kimi/skills/react-native-design/`)：SafeArea、手势动画、性能优化

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
| 速记浮窗 | `floating_window_service.dart`, `native_floating_service.dart` | 原生Android View系统悬浮窗，MethodChannel通信 |
| 外部备份 | `quick_note_backup_service.dart` | 速记+自言自语导出到外部存储JSON |
| 自言自语 | `self_talk_screen.dart`, `self_talk_service.dart` | 聊天式记录，me(右)/alterEgo(左)/system(对侧) |
| 速记 | `quick_note_editor_screen.dart`, `quick_notes_screen.dart` | 快速笔记，标签，置顶，搜索 |
| 贴图拖动 | `custom_sticker_overlay.dart` | 页面上直接拖拽，长按菜单 |
| 标签编辑 | `profile_screen.dart` | 支持颜色选择、编辑、删除确认 |
| PDF导出 | `pdf_export_service.dart` | 思源宋体，图片嵌入，封面+页眉页脚 |
| WebDAV | `cloud_sync_service.dart` | 坚果云预设，自动错误提示 |
| 自动备份 | `auto_backup_service.dart` | 每天自动备份，保存7次历史 |
| 应用锁 | `app_lock_service.dart` | 九宫格手势密码，启动保护 |
| 纪念日 | `anniversary.dart` | 日历页定制，写日记自动添加纪念文字 |
| 扭蛋系统 | `gacha_service.dart`, `gacha_screen.dart` | 每日3次，80+奖励，徽章联动 |
| 主题背景 | `theme_backgrounds.dart` | 5款动态主题（樱花/海洋/极光/黄金/星空） |
| 农历日历 | `lunar_calendar_service.dart` | 内置算法1900-2100年 |
| 目标系统 | `goal_provider.dart`, `goal_service.dart` | 月度目标，进度追踪 |
| 三级标签 | `tag_system_service.dart` | 分类→子分类→标签 |
| 徽章系统 | `badge_service.dart` | 84个徽章，8种类型 |

## 速记浮窗系统

### 设计原则：快速记录 + 强化提醒

**架构**：原生 Kotlin Service + 原生 Android View + MethodChannel
> 放弃 `flutter_overlay_window` 方案（Flutter 引擎无法在 WindowManager overlay 中初始化渲染管线），改为 100% 原生 View 实现。

**核心文件（Dart 侧）**：
- `lib/services/floating_window_service.dart` — 浮窗生命周期（对外接口层）
- `lib/services/native_floating_service.dart` — MethodChannel 通信层（Dart ↔ Kotlin）
- `lib/services/floating_permission_service.dart` — 权限管理
- `lib/services/floating_notification_service.dart` — 通知同步
- `lib/services/floating_settings_service.dart` — 设置持久化
- `lib/services/quick_note_backup_service.dart` — 外部存储备份

**核心文件（Kotlin 侧）**：
- `android/.../FloatingWindowService.kt` — 前台 Service + WindowManager 管理
- `android/.../FloatingWindowPlugin.kt` — MethodChannel 注册与处理
- `android/.../res/layout/floating_button.xml` — 浮窗按钮布局
- `android/.../res/layout/floating_panel.xml` — 速记面板布局
- `android/.../res/drawable/bg_floating_button.xml` — 圆形按钮背景
- `android/.../res/drawable/bg_floating_panel.xml` — 面板圆角背景
- `android/.../res/drawable/bg_save_button.xml` — 保存按钮背景

**通信协议**：
```
Channel: "com.diary_app/floating_window"
Dart → Kotlin: showFloatingButton / hideFloatingWindow / showQuickNotePanel / hideQuickNotePanel / updateSettings
Kotlin → Dart: onSaveQuickNote / onPanelShown / onPanelHidden / onPositionChanged
```

**数据流**：用户在浮窗面板输入 → Kotlin Service 通过 MethodChannel 回调 Dart → `QuickNoteService.insert()` → SQLite + 通知更新

**设置项**：使用标签、字体大小、同步通知、字数统计、自动隐藏、输入框透明度、双击灵敏度、靠边自动隐藏、悬浮窗大小（大/中/小）、自定义图标颜色+透明度。

## 自言自语说明

### 消息对齐规则

| 身份 | 消息位置 | 系统回复位置 |
|------|---------|------------|
| **我** (me) | 右侧，主色气泡 | 左侧，灰色气泡 |
| **另一个我** (alterEgo) | 左侧，紫色气泡+🧠 | 右侧，灰色气泡+📝 |
| **系统** (system) | 取决于回复对象 | — |

### AI 开关
- 控制**之后是否生成新的系统回复**
- 不影响已有历史回复的显示
- 关闭后任何用户消息都不触发 AI 回复

## 主题背景技术说明

5款动态主题使用 Flutter CustomPainter：
- **星空**：4向流星 + 80颗星星 + Bhaskara I快速sin近似
- **极光**：整数倍频率正弦波（1x/2x/4x），完美无缝循环
- **海洋**：波浪 + 海洋生物（鱼/海龟/虾）低频率生成
- **黄金**：粒子系统（金沙/水晶/箔片），性能优化版
- **樱花**：花瓣飘落 + 花朵生成，落地自然堆积效果

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
# 构建Release APK
flutter build apk --release
# 输出: build/app/outputs/flutter-apk/app-release.apk

# 构建AppBundle
flutter build appbundle --release

# 构建Windows
flutter build windows --release
```

**版本号更新**：`pubspec.yaml` + `AGENTS.md` 同步更新。

**发布前检查**：更新版本号 → `flutter analyze` → 构建Release → 检查APK大小（60-100MB正常）。

## 常见陷阱与教训

### ⚠️ 文件编码问题（重要！）

Windows PowerShell 默认使用 GBK，会导致 UTF-8 文件乱码。

```powershell
# ❌ 错误
Get-Content file.dart | Set-Content file.dart
# ✅ 正确
Get-Content file.dart -Encoding UTF8 | Set-Content file.dart -Encoding UTF8
# ✅ 推荐 - Python
with open('lib/screens/file.dart', 'r', encoding='utf-8') as f: content = f.read()
```

预防措施：使用 Git 提交后再修改；优先使用 IDE 替换功能；修改后立即编译验证。

## 版本记录

- **v1.23.0** (2026-05-04) - 速记浮窗系统 + 外部存储备份:
  - 计划文件：`C:\Users\PDXX\.kimi\plans\quasar-jessica-cruz-kid-flash.md`
  - 新增依赖：`flutter_overlay_window`, `flutter_local_notifications`
  - 权限：SYSTEM_ALERT_WINDOW, POST_NOTIFICATIONS, FOREGROUND_SERVICE
  - 浮窗：可拖拽圆点，边框吸附缩小，双击展开速记条横条
  - 速记条：粘贴/输入/存储/设置，拖动调节大小，双击还原
  - 设置面板：功能设置 + 外观设置（两页PageView）
  - 数据流：存储 → 数据库 + 通知 + 自言自语
  - 外部备份：速记+自言自语导出JSON到外部存储（可指定目录，日记不备份）
  - 新增10个文件，修改4个文件
  - **【2026-05-06 修复】浮窗不显示 — 多轮排查：**
    - **第一轮 — 依赖缺失（已修复）**：`flutter_overlay_window` 和 `flutter_local_notifications` 从未添加到 `pubspec.yaml`。已添加三个依赖并重新构建。
    - **第二轮 — AOT 编译（已修复）**：`main_floating.dart` 未被 import 导致 `overlayMain` 入口未打包。已添加 `import 'main_floating.dart' as _;`
    - **第三轮 — 时序 + 可见性（已修复）**：
      - `showOverlay` 单位是像素不是 dp，原 48px 在高密度屏约 5mm 看不见 → 改为 180x180 像素
      - `alignment: topRight` 被系统状态栏/R角遮挡 → 改为 `center`
      - `flutter_overlay_window` 有 bug：`stopSelf()` 后 `onDestroy()` 会移除新窗口 → `showFloatingButton()` 关闭旧窗口后循环等待 `isActive()==false`（最多 3 秒）
      - `FloatingWindowScreen` 背景从 `Colors.transparent` 改为半透明黑
      - `main_floating.dart` 去掉 `SystemChrome.setSystemUIOverlayStyle()`
    - **第四轮 — 根因确认**：红色背景可见 + Flutter UI 不可见 = `WindowManager.addView()` 正常，Flutter 渲染管线在 overlay 中初始化失败。这是架构级问题，非 `flutter_overlay_window` 独有 bug。
    - **最终结论**：`flutter_overlay_window` 方案在目标设备上彻底不可行。
    - APK: 84.8MB

- **v1.3.0** (2026-05-11) - 浮窗系统全面重构（原生 Kotlin 实现）:
  - **根因**：Flutter 引擎无法在 `WindowManager` overlay 中初始化渲染管线，`FlutterTextureView`/`FlutterSurfaceView` 均失败
  - **方案**：放弃 `flutter_overlay_window`，改为原生 Kotlin Service + 原生 Android View + MethodChannel
  - **移除依赖**：`flutter_overlay_window`
  - **新增 Kotlin 文件**：
    - `FloatingWindowService.kt` — 前台 Service，管理浮窗生命周期
    - `FloatingWindowPlugin.kt` — MethodChannel 插件，处理 Dart ↔ Kotlin 通信
  - **新增 XML 资源**：
    - `floating_button.xml` — 浮窗按钮布局（ImageButton）
    - `floating_panel.xml` — 速记面板布局（EditText + Spinner + Button）
    - `bg_floating_button.xml` — 圆形背景
    - `bg_floating_panel.xml` — 面板圆角背景
    - `bg_save_button.xml` — 保存按钮圆角背景
  - **新增 Dart 文件**：
    - `native_floating_service.dart` — MethodChannel 封装，替代原 flutter_overlay_window 调用
  - **修改文件**：
    - `floating_window_service.dart` — 改为调用 `NativeFloatingService`
    - `MainActivity.kt` — 注册 `FloatingWindowPlugin`
    - `AndroidManifest.xml` — 替换 Service 声明，添加 `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`
    - `profile_screen.dart` — 增强错误反馈（SnackBar 显示具体结果）
  - **删除文件**：
    - `lib/main_floating.dart`（不再需要 Flutter overlay entry point）
    - `lib/screens/floating_window_screen.dart`
    - `lib/widgets/floating_button.dart`
    - `lib/widgets/floating_quick_note_bar.dart`
    - `lib/widgets/floating_settings_panel.dart`
  - **关键修复记录**：
    - **颜色类型不匹配**：Dart `Color` 对象被 MethodChannel 序列化为 `int`，Kotlin 侧 `call.argument<String>("color")` 抛出 `ClassCastException` → 修复：Dart 侧新增 `_colorToHex()` 转为 `#RRGGBB` 字符串传递
    - **系统 drawable 缺失**：`@android:drawable/edit_text`、`@android:drawable/btn_dropdown` 在 Android 12+ 已移除 → 修复：全部改为纯色背景 `#F5F5F5`
    - **AppCompat 属性不兼容**：`app:tint`、`?attr/selectableItemBackgroundBorderless` 在某些 ROM 上不可用 → 修复：改为 `android:tint`、普通 TextView 点击
    - **前台服务启动**：Android 8+ 必须使用 `startForegroundService()` → 已在 `FloatingWindowPlugin` 中处理
  - **【2026-05-12 修复】拖动失效 + 触摸事件冲突**：
    - **OnTouchListener 位置错误**：设置在父 FrameLayout 上，但子 ImageButton 的 OnClickListener 消费了事件，导致父布局收不到触摸 → 修复：将 OnTouchListener 移到 ImageButton 上，移除 OnClickListener/OnLongClickListener，自己实现双击/长按检测
    - **Handler + Runnable 长按检测**：ACTION_DOWN 启动 500ms 延迟 Runnable，ACTION_MOVE 超过 10px 时取消
  - **【2026-05-12 修复】设置透明度后触摸失效**：
    - **根因**：`WindowManager.LayoutParams.alpha < 0.5f` 时，某些 ROM（小米）会丢弃该窗口的触摸事件
    - **修复**：不在 `LayoutParams` 上设置 alpha，改为在 `View` 上设置 `view.alpha = buttonOpacity.coerceIn(0.2f, 1.0f)`
  - **【2026-05-12 修复】贴边缩小后不靠边且不是圆**：
    - **根因 1（不靠边）**：`snapToEdge()` 先按大按钮尺寸（60dp）计算贴边位置，动画完成后再缩小到 24dp，缩小后留下 36dp 空白
    - **根因 2（不是圆）**：`floating_button.xml` 中 FrameLayout 和 ImageButton 尺寸固定（60dp/56dp），不随 `LayoutParams` 变化。当窗口缩小时，内部 View 超出边界被裁剪成不规则形状；且 padding 固定 14dp，24dp 窗口中 padding 占满空间导致图标不可见
    - **修复**：XML 尺寸改为 `match_parent`；`snapToEdge()` 改为同时动画移动+缩小（一个 ValueAnimator 控制位置+大小+padding）；padding 随大小动态调整（24dp→3dp, 60dp→14dp）
  - **【2026-05-12 优化】UI 全面美化 + 选中状态**：
    - 浮窗按钮：渐变背景、柔和阴影、更现代的配色
    - 速记面板：更大的圆角、更清晰的排版、更好的间距
    - 设置面板：彩色色块带选中白色边框、更直观的滑块、大小选择高亮
    - **颜色选中状态**：`createColorCircle()` / `createColorCircleWithBorder()` — 当前选中颜色显示白色 3dp 边框，其余无框
    - **大小选中状态**：`updateSizeSelection()` — 当前选中尺寸显示蓝色背景+白字，其余灰色背景+灰字
    - 新增 drawable：`bg_size_option.xml`（灰色圆角背景）、`bg_size_option_selected.xml`（蓝色圆角背景）
  - **【2026-05-12 修复】速记保存后同步到自言自语**：
    - **根因**：计划书要求存储速记时自动追加到当天自言自语，但 `_saveQuickNote` 只保存到数据库+通知，未调用 `SelfTalkService.sendMessage()`
    - **修复**：`_saveQuickNote()` 现在检查 `FloatingSettings.syncToSelfTalk` 和 `syncToNotification` 开关，分别同步到自言自语和通知
    - **新增字段**：`FloatingSettings.syncToSelfTalk`（默认 true）
  - **【2026-05-12 修复】电池优化白名单**：
    - `profile_screen._toggleFloatingWindow()` 开启浮窗后，自动请求电池优化白名单（非阻塞，失败仅提示）
  - **【2026-05-12 修复】设置面板扩展为两页（外观 + 功能）**：
    - **外观页**：颜色选择（带选中白边框）、透明度滑块、大小选择（蓝底白字高亮）
    - **功能页**：同步到通知（Switch）、同步到自言自语（Switch）、显示字数统计（Switch）、贴边自动缩小（Switch）、双击灵敏度（SeekBar 100-800ms）
    - **Tab 切换**：`switchTab()` 控制 `page_appearance` / `page_function` 可见性
    - **功能设置同步**：Kotlin `notifyFunctionSettingsChanged()` → Dart `onFunctionSettingsChanged` → `FloatingSettingsService.update()`
    - **贴边自动隐藏生效**：`snapToEdge()` 开头检查 `autoHideToEdge`，false 时不贴边缩小
    - **双击灵敏度生效**：`doubleTapSensitivityMs` 替换原硬编码 `DOUBLE_CLICK_DELAY = 300L`
  - **【2026-05-12 修复】浮窗按钮自定义图标图案**：
    - 支持 `FloatingSettings.iconEmoji`（如 💡）作为浮窗按钮图标
    - `createEmojiDrawable()` 用 Canvas 绘制 emoji 为 BitmapDrawable
    - 空字符串时回退到默认 `@android:drawable/ic_menu_edit`
    - MethodChannel 协议扩展：传递 `iconEmoji` → Kotlin 读取并设置
  - **【2026-05-12 修复】面板大小拖动调节（P5）**：
    - **右下角拖动横杠**：`floating_panel.xml` 改为 FrameLayout 包裹，右下角添加 28dp 圆形拖动手柄
    - **拖动逻辑**：`dragHandle.setOnTouchListener` 监听 ACTION_DOWN/MOVE/UP，实时更新 `WindowManager.LayoutParams.width/height`
    - **尺寸限制**：宽度 200dp ~ 屏幕宽-32dp，高度 120dp ~ 屏幕高/2
    - **尺寸记忆**：拖动结束后通过 `notifyPanelSizeChanged()` → Dart `onPanelSizeChanged` → `FloatingSettingsService.saveBarSize()`
    - **恢复尺寸**：`showQuickNotePanel()` 传递 `barWidth`/`barHeight` → Kotlin 使用保存尺寸初始化面板
  - **【2026-05-12 修复】设置面板位置自适应**：
    - `showPanel()` 和 `showSettingsPanel()` 的 y 坐标计算从 `coerceAtLeast` 改为 `coerceIn`，限制最大值防止超出屏幕底部
  - **【2026-05-12 修复】pubspec.yaml 依赖恢复 + build.gradle.kts desugaring**：
    - 恢复意外缺失的 `flutter_local_notifications: ^17.2.4` 和 `device_info_plus: ^10.1.2`
    - `build.gradle.kts` 添加 `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")`
  - **【2026-05-13 修复】设置持久化不完整（核心问题）**：
    - **按钮大小不保存**：`showFloatingButton()` 未传递 `windowSize`，重启后恢复默认 60dp → 修复：Dart 侧映射 `FloatingWindowSize` → dp（48/60/72），MethodChannel 传递 `windowSize`
    - **图标 emoji 不保存**：`notifySettingsChanged()` 未传递 `iconEmoji`，重启后恢复默认 💡 → 修复：`FloatingWindowPlugin.notifySettingsChanged()` 新增 `iconEmoji` 参数，Dart 侧 `_updateFloatingSettings()` 接收并保存
    - **Kotlin `FloatingWindowService` 接收 windowSize**：`ACTION_SHOW` 读取 `windowSize` 并赋值给 `buttonSizeDp`
  - **【2026-05-13 优化】按钮外观全面重设计（解决"图标很丑"）**：
    - **渐变圆角矩形背景**：`updateButtonAppearance()` 从纯色圆形改为 TL-BR 三色渐变（`lightenColor(1.15f)` → 主色 → `darkenColor(0.75f)`）
    - **LayerDrawable 阴影层**：底层半透明黑 + 2dp/4dp 偏移，模拟真实 elevation
    - **emoji 图标精美绘制**：`createEmojiDrawable()` 新增 `BlurMaskFilter` 柔和阴影 + 白色圆形背景 + 居中 emoji，告别简陋白字
    - **动态圆角适配**：`cornerRadius = dpToPx(size) * 0.28f`，大小变化时自动调整比例
  - **【2026-05-13 新增】按钮呼吸动画**：
    - `startBreathingAnimation()`：2.2s 无限循环，`scaleX/Y` 1.0 → 1.06 → 1.0
    - **智能生命周期**：拖动 ACTION_DOWN 暂停（秒回 1.0），松开未拖动恢复；贴边缩小后暂停，展开后恢复；`hideAll()` 彻底停止
  - **【2026-05-13 优化】设置面板 UI 全面美化**：
    - **Tab 切换**：灰色胶囊 → 底部紫色指示器 + 文字加粗（`bg_tab_indicator.xml`）
    - **颜色选择器**：36dp → 40dp，`elevation="2dp"` 阴影
    - **选中颜色效果**：`createColorCircleWithBorder()` 改为 `LayerDrawable`（阴影层 + 白色 3dp 边框层）
    - **图标选择器**：灰色方框 → 圆角卡片（`bg_icon_option.xml`，12dp 圆角），选中时淡紫背景 + 主色边框 + 放大动画（scale 1.1）
    - **选中状态动画**：`updateIconSelection()` 使用 `View.animate()` 实现选中放大/未选中还原
  - **【2026-05-13 修复】resizeButton 动画结束刷新背景**：动画 `onAnimationEnd` 中调用 `updateButtonAppearance()`，确保贴边/展开后圆角比例正确
  - **【2026-05-13 修复】设置持久化最终根因**：`main.dart` 缺失 `FloatingWindowService.initialize()` 调用，导致 MethodChannel 回调未注册，Kotlin→Dart 的所有通知无人接收 → 修复：应用启动时调用 `initialize()` 注册回调
  - **【2026-05-13 新增】应用重启后自动恢复浮窗**：`main.dart` `_autoRestoreFloatingWindow()` 延迟 2 秒检查，若之前开启则自动恢复
  - **【2026-05-13 优化】木质托盘风格图片图标**：`iconEmoji == "💡"` 时使用 `R.drawable.icon_bulb`（木质托盘+灯泡完整图），`FIT_CENTER` 缩放，`setBackgroundResource(0)` 清除背景避免叠加
  - **【2026-05-13 修复】图片图标缩小超出图框**：`floating_button.xml` 中 `android:background="@drawable/bg_floating_button"`（椭圆形）+ `android:tint="#FFFFFF"` 在代码中未完全清除，缩小后方形图片超出椭圆边界 → 修复：XML 中移除默认 background/tint/src，`updateButtonAppearance()` 中 `imageTintList = null` + `clearColorFilter()` + `setBackgroundResource(0)`，`snapToEdge()` 动画结束补调 `updateButtonAppearance()`
  - **【2026-05-13 优化】按钮尺寸与字体增大**：设置/粘贴/关闭 32dp→40dp，保存 40dp→48dp，文字加粗 13/15sp→14/16sp
  - **【2026-05-13 优化】面板展开/收起动画**：`showPanel()` 先 `alpha=0, scale=0.92`，`addView` 后 `view.post { animate() }` 淡入缩放（200ms），避免闪烁
  - 功能保留：可拖拽按钮、贴边吸附缩小、双击展开面板、长按打开应用、设置面板（两页）、多行输入、标签选择、字数统计、粘贴、保存、通知同步、自言自语同步、面板大小拖动
  - APK: ~88MB

- **v1.22.0** (2026-05-04) - 自言自语数据库彻底独立:
  - 移除 `diary_id` 列（数据库v12迁移）
  - 模型层移除 `diaryId`
  - 新增搜索API：`searchMessages`, `searchTasks`, `getRecordedDates`
  - 时间戳递增偏移确保排序稳定

- **v1.21.0** (2026-04-22) - PDF导出修复 + 自言自语重构 + 速记功能:
  - PDF字体改为 `.ttf`（可变字体 `NotoSerifCJKsc-VF.ttf`）
  - 自言自语零耦合（不再读写Diary表）
  - 新增速记：QuickNote模型 + 编辑页 + 列表页 + 4个入口
  - APK: 88.3MB

- **v1.3.0** (2026-04-10) - 自言自语 + 设计系统升级:
  - 新增SelfTalkScreen（IM聊天界面）
  - 替换 `withOpacity` → `withValues(alpha:)` 适配Flutter 3.29+
  - 扩展ThemeScheme语义化颜色
  - 自定义头像持久化修复

- **v1.1.6** (2026-03-28) - 徽章修复 + PDF字体打包:
  - 徽章系统全面检查（84个徽章）
  - 彩蛋显示随机徽章tip
  - PDF打包思源宋体到APK（~49MB）
  - APK: 107.1MB

- **v1.1.5** (2026-03-24) - 云备份重构:
  - 备份按密钥分文件夹，多设备共存
  - 云端图片ZIP+AES-256加密备份
  - 时间轴顶部卡片优化（头像/昵称/签名）

- **v1.1.0** (2026-03-24) - 目标系统 + 指纹解锁:
  - 支持5个自定义目标
  - 日历页目标卡片可折叠
  - 指纹/面容识别解锁

- **v1.0.5** (2026-03-22) - 底部导航栏优化:
  - IndexedStack替代PageView保持页面状态
  - 编辑页UI修复（移除渐变背景）
  - 导航栏自动隐藏5秒

- **v1.0.4** (2026-03-19) - 主题配色统一 + SafeArea优化:
  - 所有特殊主题统一配色
  - 系统导航栏遮挡修复
  - 自定义目标系统（与日记脱钩）
  - 三级标签系统

- **v1.0.3 → v1.0.0** (2026-03-16~19) - 农历日历、目标系统、主题背景:
  - 农历日历（1900-2100）
  - 5款动态主题（星空/樱花/海洋/极光/黄金）
  - 双模式开屏动画
  - 玻璃态UI时间轴

- **v1.0.0** (2026-03-16) - 🎉 正式发布
