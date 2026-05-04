# 小记日记 - AI协作指南

版本: 1.23.0 (2026-05-04) | 技术栈: Flutter 3.x + Provider + SQLite

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
| 速记浮窗 | `floating_window_service.dart`, `floating_quick_note_bar.dart` | 系统悬浮窗，可拖拽，速记条+设置面板 |
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

**核心文件**：
- `lib/services/floating_window_service.dart` — 浮窗生命周期
- `lib/services/floating_permission_service.dart` — 权限管理
- `lib/services/floating_notification_service.dart` — 通知同步
- `lib/services/floating_settings_service.dart` — 设置持久化
- `lib/services/quick_note_backup_service.dart` — 外部存储备份
- `lib/widgets/floating_button.dart` — 小浮窗UI（拖拽+吸附+双击）
- `lib/widgets/floating_quick_note_bar.dart` — 速记条横条
- `lib/widgets/floating_settings_panel.dart` — 设置面板（两页）
- `lib/main_floating.dart` — 浮窗专用Flutter入口

**数据流**：存储速记 → 数据库 + 通知（内容同步）+ 自言自语（最后一条用户消息）

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
  - 新增依赖：`flutter_overlay_window`, `flutter_local_notifications`
  - 权限：SYSTEM_ALERT_WINDOW, POST_NOTIFICATIONS, FOREGROUND_SERVICE
  - 浮窗：可拖拽圆点，边框吸附缩小，双击展开速记条横条
  - 速记条：粘贴/输入/存储/设置，拖动调节大小，双击还原
  - 设置面板：功能设置 + 外观设置（两页PageView）
  - 数据流：存储 → 数据库 + 通知 + 自言自语
  - 外部备份：速记+自言自语导出JSON到外部存储（可指定目录，日记不备份）
  - 新增10个文件，修改4个文件

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

- **v1.20.0** (2026-04-10) - 自言自语 + 设计系统升级:
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
