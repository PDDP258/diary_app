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
