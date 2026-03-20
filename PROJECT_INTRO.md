# 小记日记 - 一款用心打造的个人日记应用

> **版本**: 1.0.3 | **技术栈**: Flutter 3.x + Provider + SQLite
> 
> 📖 专注日记体验，用温暖的方式记录生活的每一天

## 项目简介

**小记日记** 是一款专为记录生活而设计的移动应用。它不仅仅是一个日记本，更是一个陪伴你记录每一天的贴心伙伴。从日历视图到图片记录，从主题定制到数据安全，每一个细节都经过精心打磨。

---

## 核心功能

### 📅 智能日历视图
- 直观的日历界面，一眼查看全年日记分布
- 点击日期快速预览当天记录
- 支持年份快速跳转，轻松回顾过往
- 有图片的日期显示图片背景，视觉更丰富

### 📝 丰富的日记编辑
- 支持文字和图片混合记录
- 自定义贴图系统，让日记更生动
- 标签分类管理，轻松整理日记
- 纪念日/倒数日自动提醒

### 🎨 个性化主题
- **9套精美预设主题**：温馨米、薄荷绿、樱花粉、天空蓝、活力橙、薰衣草紫、珊瑚红、森林绿、玫瑰红
- **5套商店特殊主题**：星空、樱花、海洋、极光、黄金（可通过扭蛋商店获得）
- 支持自定义配色，打造专属风格
- 全应用响应式主题切换

### 🔒 隐私保护
- 九宫格手势密码锁
- 启动保护，防止他人偷看
- 密码备份图片，忘记密码也能找回
- 数据本地加密存储

### ☁️ 云同步备份
- 支持 WebDAV 协议（坚果云等）
- 自动同步，写日记后自动备份
- 数据导出/导入，支持 .mbk 和 .txt 格式
- 换机无忧，数据随时恢复

### 💡 智能写作辅助
- **60+深度写作提示**，引导你更好地记录生活
- **8大类别**：回忆、未来规划、感恩珍惜、深度反思、人际关系、自我成长、生活仪式感、纪念日联动
- **智能联动**：检测即将到来的纪念日，提供相关写作提示
- 例："今天哪个瞬间让你感到生活很美好？描述那个画面。"

### 🎨 专属图标设计
- **「笔迹·成长」图标理念**：笔（记录）+ 螺旋轨迹（成长路径）+ 星星（里程碑）
- **Android 自适应图标**：支持 Android 8.0+ 自适应图标规范
- **4种颜色变体**：珊瑙红（默认）、薄荷绿、樱花粉、深夜黑
- **即时切换**：在设置中一键更换手机桌面图标颜色

### 🎯 习惯养成辅助
- **扭蛋奖励**：写日记获得抽奖机会，用小游戏的方式激励坚持
- **徽章识别**：自动检测记录成就（48个徽章），让坚持变得有成就感
- **里程碑庆祝**：记录天数达到目标时给予温暖鼓励
- 所有游戏化设计**只为辅助**，让你更喜欢写日记这件事情

### 🎨 主题美化
- **14套精美主题**：9套预设 + 5套可兑换特殊主题
- **贴纸装饰**：19款精美贴纸（扭蛋11款 + 商店8款）装点日记
- 主题和装饰**不影响核心功能**，让写日记变得更有趣

### 🎬 日记影院
- 将日记以电影形式播放
- 动态文字效果，沉浸式回顾
- 支持图片展示，重温美好瞬间

### 🔍 全文搜索
- 快速搜索日记内容
- 关键词高亮显示
- 支持按标签筛选

---

## 技术亮点

| 技术领域 | 实现方案 | 亮点 |
|---------|---------|------|
| **跨平台框架** | Flutter 3.x | 一套代码，Android/iOS 双端运行 |
| **状态管理** | Provider | 简洁高效，易于维护 |
| **本地存储** | SQLite + 加密 | 数据安全，隐私有保障 |
| **图片处理** | 多级缓存策略 | 400x400/800x800/原图，性能与清晰度平衡 |
| **动画效果** | 自定义翻页、3D变换 | 流畅自然的交互体验 |
| **音效反馈** | audioplayers | 点击音效，触感反馈 |
| **习惯培养** | 抽奖 + 徽章 + 里程碑 | 用游戏化辅助坚持，日记体验始终是核心 |
| **图标系统** | Android Adaptive Icons + Activity 别名 | 支持4种颜色切换，Flutter 与原生通信 |
| **自定义绘制** | CustomPainter | 开屏动画双层叠加效果，主题色实时变化 |

---

## 项目结构

```
lib/
├── screens/           # 20+个页面模块
│   ├── calendar_screen.dart      # 日历视图
│   ├── write_diary_screen.dart   # 写日记
│   ├── diary_detail_screen.dart  # 日记详情
│   ├── diary_cinema_screen.dart  # 日记影院
│   ├── stats_screen.dart         # 统计页面
│   ├── gacha_screen.dart         # 扭蛋抽奖
│   ├── tags_classification_screen.dart  # 标签分类
│   └── ...
├── services/          # 15+个核心服务
│   ├── database_service.dart     # 数据库
│   ├── encryption_service.dart   # 加密服务
│   ├── cloud_sync_service.dart   # 云同步
│   ├── gacha_service.dart        # 扭蛋系统
│   ├── badge_service.dart        # 徽章系统
│   ├── pdf_export_service.dart   # PDF导出
│   └── ...
├── providers/         # 状态管理
├── models/            # 数据模型
├── widgets/           # 自定义组件
└── config/            # 主题配置
```

---

## 开发历程

这个项目从最初的简单日历日记，逐步迭代成为一个功能完善的个人记录应用。每一个功能都源于真实的使用需求：

- **v0.2.0** - 基础功能、日历、数据导出
- **v0.3.0** - 贴图拖拽、PDF导出、标签编辑
- **v0.4.0** - 徽章系统、里程碑、全文搜索、日记影院
- **v0.7.0** - 徽章系统升级（24→48个）、图片缓存、音效支持
- **v0.8.0** - 应用锁、九宫格密码、启动保护
- **v0.9.0** - 纪念日系统、标签分类、图片预览优化
- **v1.0.0-beta.1~10** - 版本统一、云同步优化、调试工具、日记模板
- **v1.0.0-beta.11~14** - 头像奖励、调试面板、标签奖励、重复奖励联动机制、用户等级系统
- **v1.0.0-beta.15~19** - 照片回忆重设计、贴纸商店独立化、日记模板可用化、主题商店完善、写作灵感扩展、开屏动画优化、**「笔迹·成长」图标重设计**

---

## 应用截图

> 建议放置 3-5 张应用截图，展示主要界面：
> 1. 日历视图页面
> 2. 写日记页面
> 3. 日记详情页面
> 4. 主题切换页面
> 5. 徽章系统页面

---

## 下载体验

- **Android APK**: [点击下载 v1.0.0-beta.19](小记日记-v1.0.beta19.apk)
- **文件大小**: 65.6 MB
- **系统要求**: Android 5.0 及以上

---

## 技术栈

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)
![SQLite](https://img.shields.io/badge/SQLite-3-003B57?logo=sqlite)
![Provider](https://img.shields.io/badge/Provider-6.x-FF6F00)

---

## 开源信息

- **项目状态**: 持续迭代中
- **开源协议**: MIT License
- **主要语言**: Dart
- **代码行数**: 约 18,000+ 行
- **最近更新**: 2026-03-09

---

## 开发者说

> 做这个应用的初衷很简单——想要一个好看、好用、能长期陪伴的日记本。
> 
> 在这个信息爆炸的时代，能够静下心来记录生活，本身就是一种奢侈。
> 希望「小记日记」能成为你生活中的一份小确幸，记录每一个值得珍藏的瞬间。

### 产品特色

- 🎁 **游戏化设计**: 扭蛋抽奖、徽章收集、用户等级，让记日记变得更有趣
- 🎨 **高度可定制**: 14套主题配色，支持自定义颜色，打造专属风格
- 🔐 **隐私保护**: 手势密码锁、数据加密，安全存储个人记忆
- 💬 **智能提示**: 60+写作灵感提示，引导你更深入地记录生活

---

## 联系与反馈

如果你有任何建议或反馈，欢迎通过以下方式联系：

- 📧 Email: [你的邮箱]
- 💬 GitHub Issues: [项目地址]

---

*用代码记录生活，用设计温暖人心。*

---

## 技术文档

### 快速开始

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

### 核心规范

#### 1. 主题使用（强制）

```dart
// ✅ 正确
final scheme = AppTheme.schemeOf(context);
return Container(color: scheme.backgroundColor);

// ❌ 错误 - 禁止硬编码
return Container(color: Colors.white);
```

#### 2. 数据库操作（自动加密）

```dart
// 直接读写明文，加密由底层处理
await DatabaseService.insertDiary(diary);
final diaries = await DatabaseService.getAllDiaries();
```

#### 3. Provider状态管理

```dart
// 读取
final provider = context.read<DiaryProvider>();
// 监听
Consumer<DiaryProvider>(builder: (context, provider, child) => ...)
// 标签管理
await provider.addTag/updateTag/deleteTag
```

### 功能速查

| 功能      | 关键文件                                | 说明                                           |
| :------ | :---------------------------------- | :------------------------------------------- |
| 贴图拖动    | `custom_sticker_overlay.dart`       | 页面上直接拖拽，长按菜单                                 |
| 随机贴图    | `random_sticker_overlay.dart`       | 日记页和日历页随机出现                                 |
| 标签编辑    | `profile_screen.dart`               | 支持颜色选择、编辑、删除确认                              |
| PDF导出   | `pdf_export_service.dart`           | 中文字体支持，图片嵌入，封面+页眉页脚                          |
| WebDAV  | `cloud_sync_service.dart`           | 坚果云预设，自动错误提示                                 |
| 自动备份    | `auto_backup_service.dart`          | 每天自动备份，保存7次历史                               |
| 备份管理    | `backup_manager_screen.dart`        | 查看、恢复、删除备份                                  |
| 增量同步    | `incremental_sync_service.dart`     | 只同步变更数据，减少流量                                 |
| 图片缓存    | `image_cache_service.dart`          | 内存缓存，预加载，提升显示速度                              |
| 懒加载    | `lazy_image.dart`                   | 图片进入视口才加载，渐进式显示                             |
| 分页加载    | `paged_diary_list.dart`             | 日记列表分页，下拉刷新上拉加载                             |
| 图片预览    | `diary_detail_screen.dart`          | 大尺寸缩略图，点击全屏浏览                               |
| 搜索增强    | `diary_search_enhanced_screen.dart` | 关键词+日期范围+心情筛选                               |
| 日记模板    | `diary_templates.dart`              | 8种预设模板，快速开始写日记                               |
| 写作灵感    | gacha_service.dart                 | 60+深度写作提示，8大主题类别                             |
| 空状态    | `empty_state.dart`                  | 统一空状态组件，9种预设类型                              |
| 徽章系统    | `badge_service.dart`                | 48个徽章，8种类型，解锁动画                              |
| 连续记录    | `badge_service.dart`                | 真正计算连续天数触发徽章                                 |
| 里程碑    | `milestone_service.dart`            | 记录天数里程碑，五彩纸屑动画                               |
| 日历上滑    | `calendar_screen.dart`              | 日记>2篇时可上滑展开预览                                |
| 日历图片    | `calendar_screen.dart`              | 有图片的日期显示图片背景                                 |
| 文本分析    | `text_analysis_service.dart`        | 成语提取、心情片段                                   |
| 日记影院    | `diary_cinema_screen.dart`          | 电影风格预览，动态文字，图片显示                             |
| 启动页     | splash_screen.dart                 | 3D翻书动画（每月一次）+ 快速淡入动画（日常）                     |
| 音效      | `sound_service.dart`                | 点击音效，触感反馈                                   |
| 应用锁    | `app_lock_service.dart`             | 九宫格手势密码，启动保护，备份保存到私有目录                       |
| 纪念日    | `anniversary.dart`                  | 日历页定制纪念日/倒数日，写日记自动添加纪念文字                    |
| 标签分类    | `tags_classification_screen.dart`   | 按标签浏览日记，标签8格预览                             |
| 照片回忆    | `stats_detail_screen.dart`          | 统计页照片展览，点击可查看所有照片                           |
| 照片展览    | `PhotoGalleryScreen`                | 全屏浏览所有照片，支持左右滑动、缩略图跳转                        |
| 实况图片    | `motion_photo_service.dart`         | Android Motion Photo 检测与视频提取（小米/三星/OPPO等）    |
| 实况播放    | `motion_photo_widget.dart`          | 长按播放实况视频，全屏查看器支持                             |
| PDF自动字体 | `font_download_service.dart`        | 自动下载思源黑体，无需用户手动配置                            |
| 日历预览    | `calendar_screen.dart`              | 点击日期弹出日记预览，不再遮挡日历                           |
| 日历顶部    | `calendar_screen.dart`              | 显示日期/今天跳转/本月统计/搜索/纪念日入口                     |
| 扭蛋系统    | `gacha_service.dart`                | 每日免费3次抽奖，80+种奖励，徽章联动                         |
| 扭蛋页面    | `gacha_screen.dart`                 | 精美扭蛋机UI，炫酷抽奖动画                              |
| 重复奖励联动  | `gacha_service.dart`                | 系统联动转化4种资源类型                               |
| 贴纸商店    | gacha_service.stickerShop          | 用碎片兑换商店专属贴纸（与扭蛋机完全独立）                        |
| 主题商店    | `gacha_service.profileThemeShop`    | 用装饰点兑换个人主页主题                                 |
| 用户等级    | `gacha_service.getUserLevelInfo()`  | 经验值系统，6级称号                                  |
| 徽章深度优化  | `badge_service.dart`                | 智能关键词匹配，新增10+新徽章                            |
| 主题背景    | `theme_backgrounds.dart`            | 5款动态主题：樱花/海洋/极光/黄金/星空（Flutter CustomPainter） |
| 贴图动画    | `random_sticker_overlay.dart`       | 淡入淡出动画，全局随机数避免重叠                             |
| 主题字体优化  | `theme_provider.dart`               | 星空主题"我的"页面黑色字体，独立图标颜色                        |

### 开屏动画说明

#### 双模式开屏动画

完整动画（每月一次）：

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

### 主题背景技术说明

#### v1.0.2 主题背景全面增强

##### 贴图系统优化

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

##### 星空主题（4向流星 + 性能优化）

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

##### 极光主题（完美循环 + 增强视觉效果）

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

##### 海洋主题（海洋生灵）

生物生成机制：

```dart
// 低频率随机生成（6-15秒间隔）
Timer.periodic(Duration(seconds: _random.nextInt(10) + 6), (_) {
  final creatureType = _random.nextInt(4); // 0:鱼, 1:海龟, 2:虾, 3:无
  if (creatureType < 3) _spawnCreature(creatureType);
});
```

##### 黄金主题（性能优化版）

粒子数量优化：

| 类型   | 优化前 | 优化后 | 节省  |
| ---- | --- | --- | --- |
| 金沙粒子 | 50  | 15  | 70% |
| 能量水晶 | 8   | 4   | 50% |
| 金色箔片 | 30  | 10  | 67% |
| 控制器  | 5个  | 1个  | 80% |

##### 樱花主题（唯美樱花版）

轻飘飘落地效果（无吸附）：

```dart
// 落地时添加随机偏移，模拟自然堆积
final randomOffset = random.nextDouble() * 0.018; 
return baseGround + randomOffset; // 0-15px随机高度

// 落地时稍微滑动，更自然
flower.x += (random.nextDouble() - 0.5) * 0.02;
```

### 徽章系统说明

#### 徽章类型（8类共78个）

| 类型   | 数量 | 说明                         |
| :--- | :- | :------------------------- |
| 里程碑 | 5  | 累计不同天数（3/7/30/100/365天）    |
| 连续记录 | 6  | 真正连续写日记（3/7/14/30/60/100天） |
| 日记总数 | 5  | 累计篇数（10/50/100/500/1000篇）  |
| 内容创作 | 9  | 字数、标题、照片数量等                |
| 时间类 | 8  | 特定时段、周末、节假日                |
| 照片类 | 5  | 累计照片数、连续发照片                |
| 情感类 | 7  | 关键词触发（爱情、家人、工作等）          |
| 隐藏徽章 | 7  | 特殊条件、收集成就                 |

### 应用锁说明

#### 功能特性

- **九宫格手势密码**：3x3 点阵，最多9个点
- 启动保护  ：开场动画后显示解锁界面
- 密码备份  ：自动生成可视化备份图片
- 忘记密码  ：可查看本地备份图片找回

### 纪念日/倒数日说明

#### 功能特性

- **日历页定制**：顶部常驻纪念日按钮，为选中日期添加纪念日或倒数日
- 自动纪念文字  ：写日记时自动在底部添加纪念日相关文字
- 特殊日子提示  ：周年（365天）、百天（100/200/500/1000天）、月纪念日等特殊日子配有佳句
- **倒数日提醒**：距离倒数日7天内会显示提醒文字
- 文字样式  ：比正文小两号，居中显示，特殊日子加粗

### 日历顶部功能区说明

#### 功能特性

日历页顶部卡片集成了多种实用功能，方便快速操作：

- 日期显示  ：显示当前选中的日期和星期
- 今天跳转  ：当选中日期不是今天时，显示"今天"快捷按钮，一键回到当前日期
- 本月统计  ：显示当前月份的日记数量（如"本月 12 篇"）
- 搜索入口  ：快速跳转到日记搜索页面
- **纪念日入口**：快速打开纪念日管理对话框

### 实况图片（Motion Photo）说明

#### 功能特性

- **自动检测**：自动识别小米、三星、OPPO、Pixel 等 Android 实况照片
- 全屏播放  ：图片查看器支持长按播放实况视频
- 视觉标识  ：实况图片显示发光"实况"角标和"长按播放"提示

### 按标签分类说明

#### 功能特性

- **统计页入口**：统计页新增"按标签分类"卡片
- 标签网格  ：每个标签占一个大格，显示名称、数量和预览
- **8格预览**：每个标签下8个小格，预览最近使用该标签的日记
- 点击查看  ：点击标签查看所有使用该标签的日记，点击日记跳转详情

### PDF 自动字体说明

#### 功能特性

- 自动下载  ：首次导出 PDF 时自动从 CDN 下载思源黑体
- 国内 CDN  ：使用 jsdelivr 加速，约16MB
- 字体缓存  ：下载后缓存到应用文档目录，后续导出直接使用
- 降级策略  ：下载失败时自动使用系统字体或默认字体

### 图片缓存说明

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

### 扭蛋系统说明

#### 功能特性

- **写日记获得抽奖**：每日初始3次，写第一篇日记+1次，满3篇再+1次
- 四种稀有度  ：普通(60%)、稀有(25%)、史诗(12%)、传说(3%)
- **40+种奖励**：贴图类、日记提示、徽章提示、幸运语、额外抽奖、里程碑祝福、回忆提示、心情建议、标签创意、贴图包、日记模板、照片挑战、情感分析、纪念日提示、成就加成
- 重复奖励转换  ：获得已有奖励时自动转换为额外抽奖，每次扭蛋都有价值
- 精美动画  ：扭蛋机缩放+旋转动画，奖励卡片渐显效果
- 历史记录  ：保存最近10次抽奖记录
- 收藏统计  ：记录每个奖励的获得次数
- 特效显示  ：传说奖励显示特殊特效说明

### 照片展览说明

#### 功能特性

- 全屏浏览  ：黑色背景沉浸式体验
- 左右滑动  ：手势切换上一张/下一张照片
- 双指缩放  ：支持放大查看细节
- **底部缩略图**：快速跳转到任意照片
- 页码指示  ：显示当前页码和总页数

### 常见问题

**Q: 异步回调获取主题报错？**
A: `Provider.of<ThemeProvider>(context, listen: false).currentScheme`

Q: 底部弹窗被键盘遮挡？

A: `isScrollControlled: true` + `MediaQuery.of(context).viewInsets.bottom`

**Q: 构建失败/缓存问题？**
A: `flutter clean && flutter pub get`

**Q: 图标生成？**
A: `dart run tool/generate_icons.dart`

Q: 徽章不触发？

A: 连续徽章需要真正连续记录，不能中断；检查 `BadgeService.checkStreakBadges()`

### 构建与发布

#### 构建APK（Android）

```bash
# 清理缓存（如有构建问题）
flutter clean
flutter pub get

# 构建Release版本APK
flutter build apk --release

# 构建完成后APK位置
build/app/outputs/flutter-apk/app-release.apk
```

#### 构建AppBundle（Google Play）

```bash
# 构建AAB格式（用于Google Play上架）
flutter build appbundle --release

# 输出位置
build/app/outputs/bundle/release/app-release.aab
```

#### 构建Windows版本

```bash
flutter build windows --release
```

#### 构建Web版本

```bash
flutter build web --release
```

### 版本记录

- v1.0.3   (2026-03-17) - 开屏动画优化:
- 双模式开屏动画
  - 完整动画（每月一次）：3D翻书效果
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
  \- 添加应用完整性检查（包名、调试检测）
  \- 防止APK被重新打包和修改
  \- 保护作者劳动成果
  \- 允许用户自由使用（Root、模拟器均可）
- 版权信息入口\
  \- 在"关于日记"设置中添加版权信息查看
  \- 显示版权声明、使用声明、免责声明
- 主题切换后跳转到日记页\
  \- 所有主题切换后自动跳转到日记页（TimelineScreen）
  \- 底部导航栏同步切换到日记页（索引 0）
  \- 涉及页面：个人主页主题选择、扭蛋机主题商店、图标主题选择
- 头像奖励降低50%\
  \- 重复获得头像的基础装饰点降低50%
  \- 普通：10→5，稀有：20→10，史诗：30→15，传说：50→25
  \- 仍保留50%额外加成
- 8个提示类型藏品增加重复获得奖励\
  \- 日记提示、标签创意、照片挑战、情感分析、纪念日提示
  \- 心情建议、回忆提示、幸运语
  \- 重复获得时额外给予5-10装饰点
- 重复获得奖励增加50%\
  \- 所有重复奖励类型额外增加50%加成
  \- 包括：贴图、头像、徽章提示、日记模板、心情建议、回忆提示、里程碑、幸运语、货币奖励等
- 完善所有扭蛋藏品重复奖励
  - 主题色重复 → 装饰点 + 贴纸碎片
  - 额外抽奖次数重复 → 更多抽奖次数 + 经验值
  - 贴图包重复 → 大量贴纸碎片 + 装饰点
  - 所有重复奖励均含50%额外加成
  - 重复获得奖励递增机制
    - 每次重复获得同一藏品，奖励额外+1
    - 第2次重复：基础奖励+1
    - 第3次重复：基础奖励+2，以此类推
    - 所有藏品类型均享受此加成
    - 奖励提示显示重复次数
  - 部分藏品获得/重复获得给予灵感点
    - 获得时给予1点灵感点：标签、日记提示、标签创意、照片挑战、幸运语、心情建议
    - 重复获得时额外给予1点灵感点：日记提示、标签创意、照片挑战、心情建议
    - 幸运语重复获得已包含灵感点转化
- 关于日记页彩蛋增加扭蛋机会\
  \- 每日首次双击"关于日记"触发秘密彩蛋时，额外获得1次扭蛋机会
  \- 在秘密弹窗中显示绿色奖励提示
- 主题商店门槛修复\
  \- 修复按钮启用逻辑与UI显示不一致的问题
  \- 统一为30装饰点
- 藏品说明修复\
  \- 移除藏品详情页中固定的"重复获得"说明
  \- 只在真正重复获得时显示该说明
