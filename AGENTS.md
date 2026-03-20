# 小记日记 - AI协作指南

版本

: 1.0.2 (2026-03-19) 🔧 Profile修复 + 🐛 编码问题 |   技术栈  : Flutter 3.x + Provider + SQLite

## 快速开始

```bash
# 1. 安装依赖
flutter pub get

# 2. 运行调试版本
flutter run

# 3. 构建发布版本
# Android APK
flutter build apk --release

# iOS（需要Mac）
flutter build ios --release
```

详细的构建说明请参考下方的【构建与发布】章节。

## 核心规范

### 1. 主题使用（强制）

```dart
// ✅ 正确
final scheme = AppTheme.schemeOf(context);
return Container(color: scheme.backgroundColor);

// ❌ 错误 - 禁止硬编码
return Container(color: Colors.white);
```

### 2. 数据库操作（自动加密）

```dart
// 直接读写明文，加密由底层处理
await DatabaseService.insertDiary(diary);
final diaries = await DatabaseService.getAllDiaries();
```

### 3. Provider状态管理

```dart
// 读取
final provider = context.read<DiaryProvider>();
// 监听
Consumer<DiaryProvider>(builder: (context, provider, child) => ...)
// 标签管理
await provider.addTag/updateTag/deleteTag
```

### 4. 编码处理（⚠️ 重要）

**文件操作必须使用 UTF-8 编码：**

```dart
// ✅ 正确 - 显式指定 UTF-8
import 'dart:convert';
import 'dart:io';

// 读取文件
final content = await File('file.dart').readAsString(encoding: utf8);

// 写入文件
await File('file.dart').writeAsString(content, encoding: utf8);
```

**PowerShell 特别注意：**

```powershell
# ❌ 错误 - 使用系统默认编码（GBK）
Get-Content file.dart | Set-Content file.dart

# ✅ 正确 - 显式指定 UTF-8
Get-Content file.dart -Encoding UTF8 | Set-Content file.dart -Encoding UTF8
```

**VS Code 设置：**

```json
{
  "files.encoding": "utf8",
  "files.autoGuessEncoding": true
}
```

## 项目结构

```
lib/
├── screens/           # 页面（calendar, write_diary, profile...等）
│   ├── tags_classification_screen.dart  # 按标签分类
│   ├── tag_diaries_screen.dart          # 标签日记列表
│   └── ...
├── services/          # 数据库、加密、云同步、PDF导出、徽章、图片缓存
├── providers/         # 状态管理（DiaryProvider, ThemeProvider, SettingsProvider等）
├── models/            # 数据模型（Diary, Mood, Tag, Anniversary等）
├── widgets/           # 组件（贴图覆盖层、音效按钮）
├── utils/             # 工具类（平台图片、图片缓存）
└── config/            # 主题配置
```

## AI Skills

本项目使用以下 Kimi Code skills 来增强开发体验和 UI 质量：

### 1. interaction-design（交互设计）

位置

: `.kimi/skills/interaction-design/`

用于设计和实现微交互、动画过渡和用户反馈：

- 微交互反馈（按钮点击、状态切换）
- 页面和组件转场动画
- 加载状态和骨架屏
- 手势交互（滑动、拖拽）

### 2. visual-design-foundations（视觉设计基础）

位置

: `.kimi/skills/visual-design-foundations/`

提供设计系统基础规范：

- 8-point 网格间距系统
- 字体排版层级
- 色彩系统（主色、语义色、中性色）
- 图标系统规范
- WCAG 无障碍对比度标准

### 3. design-system-patterns（设计系统模式）

位置

: `.kimi/skills/design-system-patterns/`

用于构建可扩展的设计系统：

- 设计令牌（Design Tokens）层级
- 主题切换架构
- 组件变体系统
- 多平台适配

### 4. react-native-design（React Native 设计）

位置

: `.kimi/skills/react-native-design/`

跨平台移动开发最佳实践（Flutter 可参考）：

- SafeArea 和刘海屏适配
- 平台特定样式（iOS/Android 差异）
- 手势驱动动画
- 性能优化

### 可用组件

| 组件                  | 文件                                     | 用途       |
| ------------------- | -------------------------------------- | -------- |
| `InteractiveButton` | `lib/widgets/interactive_button.dart`  | 带缩放反馈的按钮 |
| `PageTransitions`   | `lib/widgets/page_transitions.dart`    | 页面转场动画   |
| `SwipeableListItem` | `lib/widgets/swipeable_list_item.dart` | 可滑动列表项   |
| `SkeletonLoading`   | `lib/widgets/skeleton_loading.dart`    | 骨架屏加载效果  |

### 使用示例

```dart
// 交互按钮
InteractiveButton(
  onTap: () => Navigator.push(context, PageTransitions.fade(NextPage())),
  child: Icon(Icons.add),
);

// 骨架屏
SkeletonLoading(
  child: ListView.builder(
    itemBuilder: (context, index) => SkeletonItem(),
  ),
);
```

## 功能速查

| 功能      | 关键文件                                | 说明                                           |
| :------ | :---------------------------------- | :------------------------------------------- |
| 贴图拖动    | `custom_sticker_overlay.dart`       | 页面上直接拖拽，长按菜单                                 |
| 随机贴图    | `random_sticker_overlay.dart`       | 日记页和日历页随机出现                                  |
| 标签编辑    | `profile_screen.dart`               | 支持颜色选择、编辑、删除确认                               |
| PDF导出   | `pdf_export_service.dart`           | 中文字体支持，图片嵌入，封面+页眉页脚                          |
| WebDAV  | `cloud_sync_service.dart`           | 坚果云预设，自动错误提示                                 |
| 自动备份    | `auto_backup_service.dart`          | 每天自动备份，保存7次历史                                |
| 备份管理    | `backup_manager_screen.dart`        | 查看、恢复、删除备份                                   |
| 增量同步    | `incremental_sync_service.dart`     | 只同步变更数据，减少流量                                 |
| 图片缓存    | `image_cache_service.dart`          | 内存缓存，预加载，提升显示速度                              |
| 懒加载     | `lazy_image.dart`                   | 图片进入视口才加载，渐进式显示                              |
| 分页加载    | `paged_diary_list.dart`             | 日记列表分页，下拉刷新上拉加载                              |
| 图片预览    | `diary_detail_screen.dart`          | 大尺寸缩略图，点击全屏浏览                                |
| 搜索增强    | `diary_search_enhanced_screen.dart` | 关键词+日期范围+心情筛选                                |
| 日记模板    | `diary_templates.dart`              | 8种预设模板，快速开始写日记                               |
| 写作灵感    | gacha\_service.dart                 | 60+深度写作提示，8大主题类别                             |
| 空状态     | `empty_state.dart`                  | 统一空状态组件，9种预设类型                               |
| 徽章系统    | `badge_service.dart`                | 48个徽章，8种类型，解锁动画                              |
| 连续记录    | `badge_service.dart`                | 真正计算连续天数触发徽章                                 |
| 里程碑     | `milestone_service.dart`            | 记录天数里程碑，五彩纸屑动画                               |
| 日历上滑    | `calendar_screen.dart`              | 日记>2篇时可上滑展开预览                                |
| 日历图片    | `calendar_screen.dart`              | 有图片的日期显示图片背景                                 |
| 文本分析    | `text_analysis_service.dart`        | 成语提取、心情片段                                    |
| 日记影院    | `diary_cinema_screen.dart`          | 电影风格预览，动态文字，图片显示                             |
| 启动页     | splash\_screen.dart                 | 3D翻书动画（每两天一次）+ 快速淡入动画（日常）                    |
| 音效      | `sound_service.dart`                | 点击音效，触感反馈                                    |
| 应用锁     | `app_lock_service.dart`             | 九宫格手势密码，启动保护，备份保存到私有目录                       |
| 纪念日     | `anniversary.dart`                  | 日历页定制纪念日/倒数日，写日记自动添加纪念文字                     |
| 标签分类    | `tags_classification_screen.dart`   | 按标签浏览日记，标签8格预览                               |
| 照片回忆    | `stats_detail_screen.dart`          | 统计页照片展览，点击可查看所有照片                            |
| 照片展览    | `PhotoGalleryScreen`                | 全屏浏览所有照片，支持左右滑动、缩略图跳转                        |
| 实况图片    | `motion_photo_service.dart`         | Android Motion Photo 检测与视频提取（小米/三星/OPPO等）    |
| 实况播放    | `motion_photo_widget.dart`          | 长按播放实况视频，全屏查看器支持                             |
| PDF自动字体 | `font_download_service.dart`        | 自动下载思源黑体，无需用户手动配置                            |
| 日历预览    | `calendar_screen.dart`              | 点击日期弹出日记预览，不再遮挡日历                            |
| 日历顶部    | `calendar_screen.dart`              | 显示日期/今天跳转/本月统计/搜索/纪念日入口                      |
| 扭蛋系统    | `gacha_service.dart`                | 每日免费3次抽奖，80+种奖励，徽章联动                         |
| 扭蛋页面    | `gacha_screen.dart`                 | 精美扭蛋机UI，炫酷抽奖动画                               |
| 重复奖励联动  | `gacha_service.dart`                | 系统联动转化4种资源类型                                 |
| 贴纸商店    | gacha\_service.stickerShop          | 用碎片兑换商店专属贴纸（与扭蛋机完全独立）                        |
| 主题商店    | `gacha_service.profileThemeShop`    | 用装饰点兑换个人主页主题                                 |
| 用户等级    | `gacha_service.getUserLevelInfo()`  | 经验值系统，6级称号                                   |
| 徽章深度优化  | `badge_service.dart`                | 智能关键词匹配，新增10+新徽章                             |
| 主题背景    | `theme_backgrounds.dart`            | 5款动态主题：樱花/海洋/极光/黄金/星空（Flutter CustomPainter） |
| 贴图动画    | `random_sticker_overlay.dart`       | 淡入淡出动画，全局随机数避免重叠                             |
| 主题字体优化  | `theme_provider.dart`               | 星空主题"我的"页面黑色字体，独立图标颜色                        |
| 农历日历    | `lunar_calendar_service.dart`       | 内置算法支持1900-2100年，2026年预计算数据                  |
| 目标系统    | `goal_provider.dart`                | 月度目标设定，进度追踪，连续记录，达成庆祝动画                      |
| 目标提醒    | `goal_service.dart`                 | 进度提醒、即将完成提醒、连续记录中断提醒、目标达成奖励                  |
| 三级标签    | `tag_system_service.dart`           | 分类→子分类→标签三级结构，智能迁移，同步支持                      |
| 标签搜索    | `tag_selector_v3.dart`              | 按名称搜索标签，支持三级结构浏览                             |

## 开屏动画说明

### 双模式开屏动画

完整动画（每两天一次）：

- 3D翻书效果（SplashPageTurn）
- 双层叠加封面（轮廓 + 原图）
- 显示作者信息
- 翻页动画时长 800ms

简单动画（日常）：

- 淡入淡出效果（FadeTransition）
- 图标缩放（ScaleTransition + easeOutBack）
- 显示应用名和用户名
- 总时长 1200ms（更快进入）

切换逻辑：

```dart
// 存储上次显示完整动画的月份
final lastMonth = prefs.getString('last_full_splash_month');
final currentMonth = DateTime.now().toIso8601String().substring(0, 7);

// 每月只显示一次完整动画
_showFullAnimation = lastMonth != currentMonth;
```

## 主题背景技术说明

### v1.0.2 主题背景全面增强

#### 贴图系统优化

淡入淡出动画：

```dart
// 使用 AnimatedOpacity + AnimatedScale 组合
AnimatedOpacity(
  opacity: opacity,
  duration: Duration(milliseconds: opacity == 1.0 ? 400 : 300),
  child: AnimatedScale(
    scale: opacity == 1.0 ? 1.0 : 0.8,
    duration: Duration(milliseconds: opacity == 1.0 ? 400 : 300),
    child: StickerWidget(),
  ),
)
```

随机序列修复：

```dart
// 全局单例随机数生成器，避免毫秒级创建产生相同序列
final Random _globalRandom = Random();
// 所有随机位置/贴纸类型都使用 _globalRandom
```

#### 星空主题（4向流星 + 性能优化）

流星碰撞避免：

```dart
// 流星出现在4个对角象限，避免水平垂直碰撞
final corners = [
  Offset(-50, -50),   // 左上 (topLeft)
  Offset(size.width + 50, -50),  // 右上 (topRight)
  Offset(-50, size.height + 50), // 左下 (bottomLeft)
  Offset(size.width + 50, size.height + 50), // 右下 (bottomRight)
];
```

#### 极光主题（完美循环 + 增强视觉效果）

整数倍频率公式（完美循环修复）：

```dart
// 关键：所有参数必须是整数倍才能确保完美循环
// 1. 速度倍数：1x, 2x, 4x - 确保在 2π 周期后同时回到起点
// 2. 频率倍数：1, 2, 4 - 整数频率
// 3. 相位偏移：0, π, 2π - 整数倍
// 4. 呼吸效果：sin(layerT) - 与速度同步

final layerT = t * config.speedMul; // t * 1, t * 2, t * 4
final layerPhase = layerIndex * pi; // 0, π, 2π

// 主波 - 整数频率
y += sin(nx * 1 + layerT + layerPhase) * amp * 0.55;
// 次波 - 整数频率，反向流动
y += sin(nx * 2 - layerT + layerPhase) * amp * 0.30;
// 细节波 - 整数频率
y += sin(nx * 4 + layerT + layerPhase) * amp * 0.15;
```

#### 海洋主题（海洋生灵）

生物生成机制：

```dart
// 低频率随机生成（6-15秒间隔）
Timer.periodic(Duration(seconds: _random.nextInt(10) + 6), (_) {
  final creatureType = _random.nextInt(4); // 0:鱼, 1:海龟, 2:虾, 3:无
  if (creatureType < 3) _spawnCreature(creatureType);
});
```

#### 黄金主题（性能优化版）

粒子数量优化：

| 类型   | 优化前 | 优化后 | 节省  |
| ---- | --- | --- | --- |
| 金沙粒子 | 50  | 15  | 70% |
| 能量水晶 | 8   | 4   | 50% |
| 金色箔片 | 30  | 10  | 67% |
| 控制器  | 5个  | 1个  | 80% |

#### 樱花主题（唯美樱花版）

轻飘飘落地效果（无吸附）：

```dart
// 落地时添加随机偏移，模拟自然堆积
final randomOffset = random.nextDouble() * 0.018; 
return baseGround + randomOffset; // 0-15px随机高度

// 落地时稍微滑动，更自然
flower.x += (random.nextDouble() - 0.5) * 0.02;
```

## 徽章系统说明

### 徽章类型（8类共78个）

| 类型   | 数量 | 说明                         |
| :--- | :- | :------------------------- |
| 里程碑  | 5  | 累计不同天数（3/7/30/100/365天）    |
| 连续记录 | 6  | 真正连续写日记（3/7/14/30/60/100天） |
| 日记总数 | 5  | 累计篇数（10/50/100/500/1000篇）  |
| 内容创作 | 9  | 字数、标题、照片数量等                |
| 时间类  | 8  | 特定时段、周末、节假日                |
| 照片类  | 5  | 累计照片数、连续发照片                |
| 情感类  | 7  | 关键词触发（爱情、家人、工作等）           |
| 隐藏徽章 | 7  | 特殊条件、收集成就                  |

## 应用锁说明

### 功能特性

- 九宫格手势密码  ：3x3 点阵，最多9个点
- 启动保护  ：开场动画后显示解锁界面
- 密码备份  ：自动生成可视化备份图片
- 忘记密码  ：可查看本地备份图片找回

## 纪念日/倒数日说明

### 功能特性

- 日历页定制  ：顶部常驻纪念日按钮，为选中日期添加纪念日或倒数日
- 自动纪念文字  ：写日记时自动在底部添加纪念日相关文字
- 特殊日子提示  ：周年（365天）、百天（100/200/500/1000天）、月纪念日等特殊日子配有佳句
- 倒数日提醒  ：距离倒数日7天内会显示提醒文字
- 文字样式  ：比正文小两号，居中显示，特殊日子加粗

## 日历顶部功能区说明

### 功能特性

日历页顶部卡片集成了多种实用功能，方便快速操作：

- 日期显示  ：显示当前选中的日期和星期
- 今天跳转  ：当选中日期不是今天时，显示"今天"快捷按钮，一键回到当前日期
- 本月统计  ：显示当前月份的日记数量（如"本月 12 篇"）
- 搜索入口  ：快速跳转到日记搜索页面
- 纪念日入口  ：快速打开纪念日管理对话框

## 实况图片（Motion Photo）说明

### 功能特性

- 自动检测  ：自动识别小米、三星、OPPO、Pixel 等 Android 实况照片
- 全屏播放  ：图片查看器支持长按播放实况视频
- 视觉标识  ：实况图片显示发光"实况"角标和"长按播放"提示

## 按标签分类说明

### 功能特性

- 统计页入口  ：统计页新增"按标签分类"卡片
- 标签网格  ：每个标签占一个大格，显示名称、数量和预览
- 8格预览  ：每个标签下8个小格，预览最近使用该标签的日记
- 点击查看  ：点击标签查看所有使用该标签的日记，点击日记跳转详情

## PDF 自动字体说明

### 功能特性

- 自动下载  ：首次导出 PDF 时自动从 CDN 下载思源黑体
- 国内 CDN  ：使用 jsdelivr 加速，约16MB
- 字体缓存  ：下载后缓存到应用文档目录，后续导出直接使用
- 降级策略  ：下载失败时自动使用系统字体或默认字体

## 图片缓存说明

```dart
// 使用缓存图片组件（自动选择清晰度）
PlatformImage(
  path: imagePath,
  fit: BoxFit.cover,
)

// 日历专用 - 400x400 清晰度
CalendarImage(
  path: imagePath,
  fit: BoxFit.cover,
)

// 详情页专用 - 800x800 高清
DetailImage(
  path: imagePath,
  fit: BoxFit.cover,
)

// 全屏预览 - 原图/1200x1200超清
PreviewImage(
  path: imagePath,
  fit: BoxFit.contain,
)

// 预加载图片
ImageCacheService().preloadImages(paths, quality: CacheQuality.medium);

// 获取缓存状态
final status = ImageCacheService().getCacheStatus();
```

## 扭蛋系统说明

### 功能特性

- 写日记获得抽奖  ：每日初始3次，写第一篇日记+1次，满3篇再+1次
- 四种稀有度  ：普通(60%)、稀有(25%)、史诗(12%)、传说(3%)
- 40+种奖励  ：贴图类、日记提示、徽章提示、幸运语、额外抽奖、里程碑祝福、回忆提示、心情建议、标签创意、贴图包、日记模板、照片挑战、情感分析、纪念日提示、成就加成
- 重复奖励转换  ：获得已有奖励时自动转换为额外抽奖，每次扭蛋都有价值
- 精美动画  ：扭蛋机缩放+旋转动画，奖励卡片渐显效果
- 历史记录  ：保存最近10次抽奖记录
- 收藏统计  ：记录每个奖励的获得次数
- 特效显示  ：传说奖励显示特殊特效说明

## 照片展览说明

### 功能特性

- 全屏浏览  ：黑色背景沉浸式体验
- 左右滑动  ：手势切换上一张/下一张照片
- 双指缩放  ：支持放大查看细节
- 底部缩略图  ：快速跳转到任意照片
- 页码指示  ：显示当前页码和总页数

## 常见问题

Q: 异步回调获取主题报错？

A: `Provider.of<ThemeProvider>(context, listen: false).currentScheme`

Q: 底部弹窗被键盘遮挡？

A: `isScrollControlled: true` + `MediaQuery.of(context).viewInsets.bottom`

Q: 构建失败/缓存问题？

A: `flutter clean && flutter pub get`

Q: 图标生成？

A: `dart run tool/generate_icons.dart`

Q: 徽章不触发？

A: 连续徽章需要真正连续记录，不能中断；检查 `BadgeService.checkStreakBadges()`

## 构建与发布

### 构建APK（Android）

```bash
# 清理缓存（如有构建问题）
flutter clean
flutter pub get

# 构建Release版本APK
flutter build apk --release

# 构建完成后APK位置
build/app/outputs/flutter-apk/app-release.apk
```

### 构建AppBundle（Google Play）

```bash
# 构建AAB格式（用于Google Play上架）
flutter build appbundle --release

# 输出位置
build/app/outputs/bundle/release/app-release.aab
```

### 构建Windows版本

```bash
flutter build windows --release
```

### 构建Web版本

```bash
flutter build web --release
```

### 版本号更新

发布新版本前，请更新以下文件中的版本号：

1. `pubspec.yaml` - 修改 `version: x.x.x`
2. `AGENTS.md` - 更新文档开头的版本号和版本记录

### 发布前检查清单

- [ ] 更新版本号
- [ ] 更新 `AGENTS.md` 版本记录
- [ ] 运行 `flutter test` 检查测试
- [ ] 构建Release版本并测试
- [ ] 检查APK大小（通常60-80MB为正常范围）

## 常见陷阱与教训

### ⚠️ 文件编码问题（重要！）

问题描述：

在 Windows PowerShell 中使用字符串替换命令时，UTF-8 编码的中文字符被错误解释为 GBK，导致文件大面积乱码。

错误示例：

```powershell
# ❌ 错误 - 会导致中文乱码
(Get-Content lib\screens\profile_screen.dart -Raw).Replace("旧文本", "新文本") | 
Set-Content lib\screens\profile_screen.dart -NoNewline
```

正确做法：

```powershell
# ✅ 正确 - 显式指定 UTF-8 编码
$content = Get-Content lib\screens\profile_screen.dart -Raw -Encoding UTF8
$content = $content.Replace("旧文本", "新文本")
$content | Set-Content lib\screens\profile_screen.dart -Encoding UTF8 -NoNewline
```

或者使用 Python（推荐）：

```python
# ✅ 推荐 - Python 更可靠
with open('lib/screens/profile_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()
content = content.replace('旧文本', '新文本')
with open('lib/screens/profile_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
```

预防措施：

1. 使用 Git  ：每次修改前提交，可随时回滚
2. 备份文件  ：修改前创建 `.bak` 备份
3. 验证编码  ：修改后立即检查文件是否能正常编译
4. IDE 操作  ：优先使用 IDE（VS Code/Android Studio）的替换功能

恢复方案：

- 如果已乱码且没有 Git 备份：
  1. 立即停止继续修改
  2. 检查 `.bak` 备份文件是否完好
  3. 如备份也损坏，基于当前干净代码重新实现功能
  4. 不要尝试手动修复乱码  （信息已丢失，不可逆）

## 版本记录

- v1.0.2   (2026-03-19) - Profile修复与Git初始化:
  - 🔧 修复profile\_screen.dart中文乱码问题
    - 根因：PowerShell默认使用GBK编码导致UTF-8文件损坏
    - 解决：完全重写profile\_screen，使用UTF-8显式编码
  - ✅ 完整还原UI功能
    - 用户卡片（头像/昵称/签名编辑）
    - 徽章展示区域（已解锁预览+图鉴入口）
    - 数据管理（云同步/本地备份/导出）
    - 主题配色/桌面图标/应用锁
    - 心情管理/标签管理/自定义贴纸
    - 关于日记（彩蛋）/版权信息
  - 📝 添加编码处理规范到AGENTS.md
  - 🔒 初始化Git版本控制
- v1.0.1   (2026-03-20) - 新功能更新:
  - 📅 农历日历系统
    - 内置算法支持任意年份（1900-2100）
    - 2026年预计算数据（ holidays + 24节气）
    - 日历页面显示农历日期、节气、节日
  - 🎯 目标系统增强
    - 目标进度提醒（月底前3天自动提醒）
    - 即将完成提醒（还差1-2篇时提示）
    - 连续记录提醒（晚上8点后未写日记提醒）
    - 目标达成自动奖励扭蛋
  - 🏷️ 三级标签系统
    - 分类→子分类→标签三级结构
    - 智能标签迁移（旧标签自动归类）
    - 标签搜索与分类浏览
    - 标签同步支持（云同步）
  - 🎁 扭蛋池优化
    - 头像藏品精简至30%（11个精选头像）
    - 新增目标达成头像（4个）
    - 新增目标道具奖励（6个）
    - 新增标签收藏奖励（6个）
  - 🎨 自定义头像支持
    - 个人中心可设置自定义头像
    - 支持从相册选择图片
- v1.0.0   (2026-03-18) - 🎉 正式发布:
  - 樱花主题混乱效果优化
    - 混乱频率提高10%（0.0008 → 0.00088）
    - 混乱时间延长（90帧 → 120帧，1.5秒 → 2秒）
    - 渐入渐出时间延长（30帧 → 40帧）
    - 混乱力度减轻20%
    - 风向调整：上、左、右、下右、下左五个方向
  - 时间轴玻璃态UI效果
  - 双模式开屏动画（每两天一次完整动画）
- v1.0.3   (2026-03-17) - 开屏动画优化:
- 双模式开屏动画
  - 完整动画（每两天一次）：3D翻书效果
  - 简单动画（日常）：淡入淡出 + 图标缩放
  - 自动判断：根据上次显示月份决定动画类型
- v1.0.2   (2026-03-16) - 主题背景全面增强:
- 贴图系统优化
  - 新增淡入淡出动画（AnimatedOpacity + AnimatedScale）
  - 修复随机序列问题，使用全局Random实例避免毫秒级重复
- 星空主题增强
  - 4方向流星（左上/右上/左下/右下），避免水平垂直碰撞
  - 流星生命周期：流动→渐隐→闪耀三阶段
  - 碰撞避免逻辑，确保不会重叠
- 极光主题完美循环 + 增强
  - 整数倍速度（1x/2x/4x）确保完美无缝循环
  - 提高透明度（0.35→0.45）和振幅，更明显
  - 更亮的霓虹绿色（#39FF14）
  - 新增8颗随机位置闪烁星星
- 海洋主题生灵
  - 新增海洋生物（鱼、海龟、虾）
  - 6-15秒低频率随机生成
  - 波浪完美循环修复
- 黄金主题性能优化
  - 粒子数量大幅减少（金沙50→15，水晶8→4，箔片30→10）
  - 5个AnimationController合并为1个
  - 简化噪声函数，波浪步长10→25px
- 樱花主题唯美优化
  - 落地效果改为轻飘飘的自然堆积（随机偏移0-15px）
  - 移除吸附效果，添加轻微滑动
  - 所有花瓣/花朵颜色加深（深粉#FF6B8A）
  - 大樱花改为唯美心形花瓣+径向渐变
  - 地面位置降低（93%→95%）
  - 大樱花生成频率提高（3秒/45%→2秒/60%）
  - 风的频率降低（0.3%→0.15%，时长2秒→1.5秒）
- 主题配色优化
  - ThemeScheme新增iconColor字段
  - 星空主题"我的"页面使用深色文字（#1A1A2E）
  - 独立图标颜色支持
- 星空主题字体优化
  - 参考自定义颜色逻辑：白色卡片 + 深色文字
  - textDarkColor: #2D2D4A（深紫黑，白色卡片可见）
  - textMediumColor: #4A4A6A（中紫灰）
  - textLightColor: #7A7A9A（浅紫灰）
  - iconColor: #7C4DFF（梦幻紫主题色）
- v1.0.1   (2026-03-16) - 主题动画优化:
- 极光主题重构
  - 改为纯绿色系（霓虹绿/翠绿/酸橙绿），与星空主题区分开
  - 使用整数周期正弦波算法，实现完美无缝循环动画
  - 背景改为深绿黑色调（#020C10）
- 星空主题算法优化（加法替代减法）
  - 星星数量：40颗 → 80颗（翻倍）
  - 使用 Float64List 存储星星数据（内存减半）
  - 流星对象池管理（4个预创建对象复用）
  - Bhaskara I 快速sin近似（10倍计算速度）
  - 按大小批量绘制（减少Paint状态切换）
  - 10点连续尾迹路径（原来4个离散圆点）
  - 更深邃的背景渐变（#030310 到 #0D0D2F）
- 樱花主题花朵修复
  - 提高花朵生成频率（6秒→3秒检查，50%→60%概率）
  - 花朵尺寸增大（12-16 → 14-20）
  - 最大同时花朵数增加（2朵 → 3朵）
- 星空主题文字颜色调整
  - textDarkColor: #F5F5FF → #E0E0F0（更柔和）
  - textMediumColor: #D0D4F0 → #B8B8D0（降低亮度）
  - textLightColor: #B0B8E0 → #9090B0（更暗的灰色）
- v1.02   (2026-03-16) - 主题价格回调:
- 所有主题价格下调100装饰点
  - 星空主题：140 → 40
  - 樱花主题：140 → 40
  - 海洋主题：150 → 50
  - 极光主题：150 → 50
  - 黄金主题：190 → 99
- v1.01   (2026-03-16) - 主题价格调整:
- 所有主题价格涨价110装饰点
  - 星空主题：30 → 140
  - 樱花主题：30 → 140
  - 海洋主题：40 → 150
  - 极光主题：40 → 150
  - 黄金主题：80 → 190
- v1.0.0   (2026-03-16) - 🎉 正式发布:
- 作者信息更新\
  \- 作者：PDDP
  \- 版权所有 © 2024-2026 PDDP
- 作品保护机制\
  \\

