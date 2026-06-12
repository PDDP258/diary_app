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
├── screens/      # 页面（calendar, write_diary, profile, self_talk...）
├── services/     # 数据库、加密、云同步、PDF导出、徽章、图片缓存、浮窗、备份
├── providers/    # 状态管理（DiaryProvider, ThemeProvider, SettingsProvider...）
├── models/       # 数据模型（Diary, Mood, Tag, Anniversary, QuickNote...）
├── widgets/      # 组件（贴图覆盖层、音效按钮、浮窗UI...）
├── utils/        # 工具类（平台图片、图片缓存）
└── config/       # 主题配置（design_tokens.dart, app_theme.dart）
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

## 版本记录

- **v1.25.0** (2026-05-13) - 浮窗系统体验优化 + 视觉语言统一：
  - 设置持久化修复（`main.dart` 注册 MethodChannel 回调）
  - 木质托盘图片图标、呼吸动画、面板展开动画
  - 应用重启后自动恢复浮窗
  - 官网升级温暖手账风格（`DESIGN_SYSTEM.md`）
  - App 主题背景统一为 `#FDF8F0`，新增品牌色 `#C4956A`

- **v1.22.0** (2026-05-04) - 自言自语数据库彻底独立
- **v1.21.0** (2026-04-22) - PDF 导出修复 + 自言自语重构 + 速记功能
- **v1.3.0** (2026-04-10) - 自言自语 + 设计系统升级
- **v1.1.6** (2026-03-28) - 徽章修复 + PDF 字体打包
- **v1.1.0** (2026-03-24) - 目标系统 + 指纹/面容解锁
- **v1.0.0** (2026-03-16) - 🎉 正式发布
