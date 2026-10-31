# P1 UI/渲染层性能审计（滚动 / 动画 / 重绘 / 图片）

审计范围：`lib/screens/{main_screen,timeline_screen,calendar_screen}.dart`、`lib/widgets/{theme_backgrounds,starry_background,animated_feedback,scroll_reveal,page_transitions,interactive_button,skeleton_loading,real_page_turn,paged_diary_list,custom_sticker_overlay,random_sticker_overlay,immersive_experience,swipeable_list_item,smart_notifications}.dart`，以及被上述页面直接消费的 `diary_interactions.dart`、`platform_helpers.dart`、`image_cache_service.dart`、`lazy_image.dart`、`custom_bottom_nav.dart`、`app_theme.dart`、`diary_provider.dart`、`lunar_calendar_service.dart`、`models/diary.dart`。纯静态阅读，未执行任何 flutter/dart 命令。

## 0. 方法与基线数据

统计口径：`lib/` 下 169 个 dart 文件、2738 KB。

| 指标 | 实测值 | 备注 |
|---|---|---|
| `AnimationController(` 构造 | 58（`= AnimationController(` 57） | 任务给的 139 是「`AnimationController` 字符串出现次数 149」的口径，含类型声明/字段/形参 |
| `.repeat(` 常驻循环 | 18 | 清单见 §3 |
| `Opacity(` | 23（`\bOpacity\(`），另有多处 `AnimatedOpacity` | 非 0/1 时走 saveLayer |
| `BackdropFilter` | 2 | `custom_bottom_nav.dart:46`、`glass_panel.dart:95` |
| `MediaQuery.of` | 46 | 任务给 45，实测含 `main_screen` 3 处 |
| `shrinkWrap: true` | 8 | §2 |
| `Image.file(` | 10 | 全屏查看器 1 处无 cacheWidth |
| `RepaintBoundary` | 9 | 全部在 `utils/performance_optimizations.dart`，**业务代码 0 处使用** |
| `AppTheme.schemeOf` | 194 | 内部就是 `context.watch<ThemeProvider>()`（`app_theme.dart:151-153`） |
| `DateFormat(` | 72 | 每次构造都要查 zh_CN locale 数据 |
| `setState(` | 385 | — |

两个交叉事实（Lead 已核实，本报告据此估算成本，不再复述论证）：
- `lib/services/database_service.dart` 只有 3 行 `export 'database_service_web.dart';` → **Android 跑的是 SharedPreferences + 全量 JSON**。任何 `getAllDiaries()` 都是全量排序拷贝（`database_service_web.dart:379-382`），任何写入都是「全量 AES 加密 + 全量 jsonEncode + 整键 setString」（`:269-280`、`:439-449`），无 SQLite 索引。
- `main.dart:24-79` 在 `runApp` 前串行 await 7 项初始化。

### 「后台/被覆盖时还在跑吗」——结论：不会，但前台可见时是每帧跑

`lib/` 里 `TickerMode` 出现 0 次，不靠业务代码控制。Framework 两层兜底：
- App 进入 paused：不产帧，`Ticker` 不再消耗 raster/UI 线程（`SchedulerBinding` 不调度帧）。
- 被不透明路由覆盖：`Overlay` 对 `maintainState` 条目注入 `tickerEnabled: false`，即 `TickerMode(enabled: false)`（Flutter 3.41 `packages/flutter/lib/src/widgets/overlay.dart:877-884`、`:419-420`）→ 背景动画/滚动揭示全部 mute。

所以「后台也在跑」这个怀疑不成立；真正的热点是 **MainScreen 前台可见的任意一帧**（§1）。但注意反例：`main_screen.dart:262-296` 用 `Future.delayed(2s/3s)` + `_checkMilestone`，返回前台后仍会继续，属于逻辑层问题（不在本文件范围，仅标注）。

---

## 1. P0 清单（6 条，按修复收益排序）

### P0-1 日历页 42 格 × 4 次 `DateFormat` 构造 + 每格线性扫全量日记（`calendar_screen.dart:410-447`、`:1418-1428`、`:93-95`）

- 位置：`calendar_screen.dart:93`（整页 `Consumer<DiaryProvider>`）、`:95`（`provider.datesWithDiaries` 每次 build 新建 `Set`）、`:410-440`（`GridView.count(children: _getDaysInMonth().map(...))` 42 格）、`:411-415`（每格 2 次 `DateFormat('yyyy-MM-dd')`）、`:421`（每格 `provider.getDiariesByDate(dateStr)`）、`:1427-1428`（`_buildDayCell` 内再 2 次 `DateFormat`）。
- 机制：每次 `DiaryProvider.notifyListeners()`（收藏、编辑、删除、加载更多、从写日记页返回）→ 整页 rebuild → 42 格 ×（4 次 `DateFormat` 构造 + 1 次 O(N) 扫描并新建 List）。`getDiariesByDate` 是 `_diaries.where(...).toList()`（`diary_provider.dart:39-41`），N=日记总数。每次重建约 **168 次 DateFormat 构造 + 42 次 O(N) 扫描 + 42 个新 List + 1 个新 Set**。
- 现象：日历页切月/点选日期/收藏/从详情页返回时掉帧；日记量越大越慢（N=1000 时 42×1000=4.2 万次字符串比较）。
- 预估收益：日历页 build 从约 4-8ms 降到 1-2ms；切月从「掉一帧」到「稳 60」。岁入随 N 线性，属于主要 jank 源。
- 改法（索引化 + 预格式化，全部在 Provider/局部层做，不动 UI 结构）：

```dart
// diary_provider.dart —— 写时建索引，读时 O(1)
Map<String, List<Diary>> _byDate = const {};
Map<String, List<Diary>> get byDate => _byDate;
void _rebuildIndex() {
  final m = <String, List<Diary>>{};
  for (final d in _diaries) { (m[d.date] ??= <Diary>[]).add(d); }
  _byDate = m;
  _datesWithDiaries = m.keys.toSet();
}
List<Diary> getDiariesByDate(String date) => _byDate[date] ?? const [];
```
在 `loadRecentDiaries`/`loadDiaries`/`loadMoreDiaries`/`deleteDiary`/`toggleFavorite` 的 `notifyListeners()` 之前调用 `_rebuildIndex()`。

```dart
// calendar_screen.dart —— 每帧只用日期字符串算一次 key
static final _ymd = DateFormat('yyyy-MM-dd');   // 顶层 final，构造一次
// 外层 build 预先算好当月字符串表：
final days = _getDaysInMonth();
final dayKeys = List.generate(days.length, (i) => _ymd.format(days[i]), growable: false);
final selKey = _ymd.format(_selectedDate);
final todayKey = _ymd.format(DateTime.now());
// 传入 _buildDayCell，内部禁止再 new DateFormat
```

- 风险：低。`byDate` 与 `_diaries` 必须同一处更新（建议统一走一个 `_syncIndex()`），漏调会出现「日历不亮灯」；有 `test/` 覆盖时可加一条单测。

### P0-2 特殊主题：全屏 `CustomPaint` 每帧重绘，且整棵页面树在动画层的 child 位置（`theme_backgrounds.dart:396-403,810-816,1320-1325,1680-1689,2076-2101`）

- 位置：5 套背景统一结构 `Container(gradient) > AnimatedBuilder(animation: _controller) > CustomPaint(painter: XxxPainter(...), child: widget.child)`；`shouldRepaint => true` 在 `:624, :1244, :1494, :1983, :2250`；`Ocean` 3 条波 `for (double x = 0; x <= size.width; x += 2)`（`:910`），1080 宽 ≈ 1620 次/帧；`Starry` 80 星 + `MaskFilter.blur` 光晕（`:2189`）。
- 机制：`AnimatedBuilder` 每帧 rebuild `CustomPaint` → `RenderCustomPaint.markNeedsPaint`。业务代码 `RepaintBoundary` 用量为 0，`CustomPaint` 的 `child`（= 整棵 `PageView` 页面树）与 painter 属于**同一绘制层**，因此背景脏 → 整页内容重绘（`PageView` 内部 `Viewport` 是 `isRepaintBoundary => true`，见 `packages/flutter/lib/src/rendering/viewport.dart:604`，这一层挡住了「滚动内容」但挡不住 `Positioned` 之外的内容与页面整体重绘路径，且背景层自身 60fps 满屏 fill）。触发条件：`main_screen.dart:558-561` 只在 5 个特殊主题时走背景层，**默认「温馨米」不受影响**。
- 现象：开「星空/樱花/海洋/极光/黄金」后在任意标签页持续 60fps 满屏绘制，低端机固定掉帧、发热、耗电；滚动手感明显劣化。
- 预估收益：背景脏区从「整屏」缩到「背景层自身」；配合 `isComplex/willChange` 可让 raster cache 命中；低端机帧时间预计 16ms→6-9ms。
- 改法（两处，最小改动）：

```dart
// 1) child 包一层 RepaintBoundary，背景独立成层
return CustomPaint(
  painter: OceanPainter(...),
  isComplex: true,          // 允许 raster cache
  willChange: true,         // 动画层不缓存为静态
  child: RepaintBoundary(child: widget.child),
);
```
```dart
// 2) 主题背景可整体由开关关闭（省电模式/低端机默认关）
// main_screen.dart:615
child: ThemeBackgroundFactory.wrap(
  themeName: settings.reduceMotion ? '' : currentTheme,  // reduceMotion 新设置项
  child: pageView,
),
```
- 风险：`RepaintBoundary` 会让页面内容单独成层（多一层合成开销，约 0.3-0.8ms，可接受）；个别机型首帧会短暂空白。`willChange: true` 会禁用该 layer 的 raster 缓存收益，需 A/B；若只想修「整页重绘」而不动背景缓存策略，只加 `RepaintBoundary` 即可。

### P0-3 时间线每个列表项都套 `ScrollReveal`（VisibilityDetector + 独立 AnimationController + Opacity）（`timeline_screen.dart:256-260`、`scroll_reveal.dart:60-125`）

- 位置：`timeline_screen.dart:256` 每项 `ScrollReveal(key: ValueKey('diary_${diary.id}'), child: _buildDiaryItem(...))`；`scroll_reveal.dart:108-124` 每项一个 `VisibilityDetector` + `AnimatedBuilder` + `Opacity` + `Transform.translate`；`:114` `Opacity(opacity: _opacity.value)`。
- 机制：① 每个 item 一个 `AnimationController`（`scroll_reveal.dart:70`），列表可见 6-8 项时就有 6-8 个 ticker 对象；② 揭示动画期间 `opacity ∈ (0,1)`，`RenderOpacity` 走 saveLayer（`packages/flutter/lib/src/rendering/proxy_box.dart:896-898` 明确写「非 0/1 需要中间缓冲」）→ 每帧 N 个全卡片离屏合成；③ `VisibilityDetector` 每次挂载/滚动批量回调（`visibility_detector` 的 controller 默认 `updateInterval = 500ms`，`visibility_detector-0.4.0+2/lib/src/visibility_detector_controller.dart:25`），依赖 `scheduleTask`+post-frame（`render_visibility_detector.dart:53,161`），滚动时每 500ms 扫一遍所有 detector。
- 现象：列表滚动（尤其快速滑动）时闪烁/掉帧；进页面首次揭示 10+ 项同时动画时最卡。
- 预估收益：滚动期 saveLayer 从「每项 1 个」降为 0；首屏揭示峰值帧时间约 -30%。
- 改法：默认关闭逐项揭示，只在首屏前 3 项保留；或改用 `FadeTransition`（`Opacity` 换成 `FadeTransition` 同样需要 saveLayer，但 `Opacity` 每帧重建 widget 树、`FadeTransition` 只更新 layer，能省 build）：

```dart
// timeline_screen.dart:256
// 方案 A（推荐）：去掉逐项 reveal，只保留首屏 3 项的入场
index < 3
    ? ScrollReveal(key: ValueKey('reveal_${diary.id}'), child: item)
    : item;
// 方案 B：保留 reveal，但把 Opacity 换成 FadeTransition + RepaintBoundary
FadeTransition(opacity: _controller, child: RepaintBoundary(child: child))
```
- 风险：视觉上少了「逐项浮现」，需要 PD/设计确认；`ValueKey` 变化会导致 item 重建，保持 key 稳定。

### P0-4 `Diary.wordCount` 每次调用 new RegExp + `replaceAll`（`models/diary.dart:108-121`）

- 位置：`models/diary.dart:113-117` 每次 getter 调用都 `RegExp(r'[\n]*[🎉⏰][^\n]*(?:纪念日|倒数日)[^\n]*', multiLine: true)` + `replaceAll`；消费点：`timeline_screen.dart:908`（每项）、`paged_diary_list.dart:496,860`（每项）、`stats_screen.dart:118`（全量 fold）、`text_analysis_service.dart:392,402,406`（全量 + 排序）、`badge_service.dart:2185`（全量）、`diary_provider.dart:54-56`。
- 机制：正则不是 `const` 无法被 Dart 缓存（`RegExp` 只有字面量 `RegExp(...)` 在部分场景被复用，这里每次 new），编译 + 全字符串扫描；一次 `stats` 页进入 = N 次正则编译 + N 次 replaceAll。列表项每次 rebuild 都算一次（`Consumer` 通知时 6-8 项 × 每次滚动 rebuild 不可见项不计，但可见项每帧布局里若重建就会重算）。
- 现象：统计页/搜索页进入明显停顿；列表滚动时每项多一次正则编译。
- 预估收益：统计页 N=1000 时省掉 1000 次正则编译（约 20-60ms 主线程）；列表项每项省 ~0.05-0.2ms。
- 改法：

```dart
// models/diary.dart
static final RegExp _anniversaryPattern = RegExp(
  r'[\n]*[🎉⏰][^\n]*(?:纪念日|倒数日)[^\n]*', multiLine: true);
int? _wordCountCache;
int get wordCount => _wordCountCache ??=
    (title?.length ?? 0) +
    (content == null ? 0 : content!.replaceAll(_anniversaryPattern, '').trim().length);
```
（`Diary` 不可变、字段 final，`_wordCountCache` 安全；`copyWith` 产生新实例自然重算。）
- 风险：低。若 `content` 曾就地被改（当前代码无此路径）需改回不缓存。

### P0-5 图片解码：全屏/详情用原图、`PlatformImage` 的 cacheWidth 是死参数、FutureBuilder 每 build 新建 future（`image_cache_service.dart:505-553`、`platform_helpers.dart:16-72`、`diary_detail_screen.dart:1227`）

- 位置：
  - `OriginalImage`（`image_cache_service.dart:505-552`）`Image.file(File(path), width, height)` **无 `cacheWidth/cacheHeight`** → 手机照片 4000×3000 按原图解码（≈48MB/张 ARGB）；使用点 `diary_detail_screen.dart:1227`（全屏查看器 `PageView.builder`，滑到下一张又多一张 48MB）。
  - `PlatformImage`（`platform_helpers.dart:21-22`）声明了 `cacheWidth/cacheHeight`，但 `:63-69` 构造 `OptimizedCachedImage` 时**没有传**；而 `OptimizedCachedImage` 的 `Image.file`（`image_cache_service.dart:486-491`）本身也不吃 cacheWidth → 参数链路全断（`platform_helpers.dart:21-22` 是死参数）。
  - `PlatformImage` `:50-52` `FutureBuilder<bool>(future: File(path).exists(), ...)`：future 建在 `build` 里 → 每次 rebuild 重新发起 IO，先回到 `ConnectionState.waiting` 显示 loading 占位（`:53-55`），随后再切图。列表项所在父级任何 setState 都会让可见图片「闪一下」。
  - `LazyImage`（`lazy_image.dart`）**全库 0 处使用**（grep `LazyImage(`/`LazyImageList`/`LazyImageGrid` 只有定义与 import），所谓「懒加载」未接线。
- 机制：解码在 UI/raster 线程外的 engine image decoder 做，但内存占用直接进 GPU 纹理；48MB/张 × 3 张预加载 = OOM 风险（Android 上低端机 heap 128-256MB），这也是「频繁闪退」的候选原因之一。
- 现象：进详情页/全屏看图卡 300-800ms，快速翻图更差；列表图片偶尔闪烁。
- 预估收益：全屏查看内存 48MB→约 4-6MB（`cacheWidth = 屏幕宽×dpr`）；详情缩略图 800px 缓存已有（`DetailImage` 走 `OptimizedCachedImage`，已经是对的）。
- 改法：

```dart
// image_cache_service.dart —— OriginalImage 加超采样尺寸
return Image.file(
  File(path),
  width: width,
  height: height,
  fit: fit,
  cacheWidth: width == null
      ? (MediaQuery.of(context).size.width *
              MediaQuery.of(context).devicePixelRatio)
          .round()
      : (width * MediaQuery.of(context).devicePixelRatio).round(),
  gaplessPlayback: true,
  errorBuilder: ...,
);
```
```dart
// platform_helpers.dart —— 把已有参数真正传下去
return OptimizedCachedImage(
  path: path, width: width, height: height, fit: fit,
  quality: CacheQuality.small,
  cacheWidth: cacheWidth, cacheHeight: cacheHeight,  // 新增字段并透传给 Image.file
);
```
```dart
// PlatformImage —— 不要每次 build 都发 IO
// 改为 StatefulWidget：initState 里算一次 exists()，didUpdateWidget 里只在 path 变化时重查；
// 或直接去掉 exists() 预检，交给 errorBuilder（Image.file 自身会走错误分支）。
```
- 风险：`cacheWidth` 只降采样宽度，`BoxFit.contain` 下长边仍按比例，正确；`gain` 是首帧略模糊（缩略放大），全屏看图建议 `cacheWidth = 屏幕宽 dpr × 1.2`。

### P0-6 一次「收藏/编辑/删除/写日记返回」= 全量 DB 重写 + 全量 UI 重建（`diary_provider.dart:39-46,130-144,269-288`）

- 位置：`timeline_screen.dart:125,161,689`、`calendar_screen.dart:1373,1387`、`diary_detail` 返回路径都调 `provider.loadDiaries()`；`loadDiaries` → `DatabaseService.getAllDiaries()`（全量排序拷贝）+ `notifyListeners()`。`toggleFavorite`（`diary_provider.dart:269-288`）虽然本地替换，但 `updateDiary` 会走 `DatabaseService.updateDiary`（全量加密写，`database_service_web.dart:269-280`）。
- 机制：一次收藏 = 1 次全量 JSON 序列化 + AES 加密（N 条 title/content）+ 1 次 `notifyListeners()` → TimelineScreen + CalendarScreen 两个 `Consumer` 同时整页 rebuild（42 格日历又走一遍 P0-1）。写日记返回同理，且写日记页还在栈里时 `PageView` 两页都是活的。
- 现象：点一次收藏卡 1-2 帧，日记多时肉眼可见顿一下；删除后列表「跳」一下。
- 预估收益：从 O(N) 全量 → O(1) 局部更新，收藏/删除的 UI 反馈延迟从 >50ms（N=1000）降到 <8ms。
- 改法：

```dart
// diary_provider.dart
Future<bool> deleteDiary(int id) async {
  await DatabaseService.deleteDiary(id);       // DB 侧仍全量写（见 DB 报告，属另一模块）
  _diaries.removeWhere((d) => d.id == id);
  _syncIndex();                                // P0-1 的索引
  notifyListeners();
  return true;
}
// timeline/calendar 的返回刷新改为「乐观更新」：
// if (result == true) 不调 loadDiaries()，改为 provider.refreshOne(id) / 或依赖 notifyListeners
```
- 风险：与 Lead 侧 DB 报告强耦合——DB 仍是全量 JSON，Provider 侧只能把「读放大」消掉，「写放大」需 DB 侧改增量。两边必须一起改，否则收益减半。

---

## 2. 列表虚拟化 / 布局

| ID | 严重度 | 位置 | 现象与机制 | 改法 |
|---|---|---|---|---|
| V-1 | P1 | `main_screen.dart:89-94,617-621` | `PageView(children: _screens)` 用 `SliverChildListDelegate`（`page_view.dart:699`），`cacheExtent: 0.0`（`:975`）→ 只建当前页；4 个页面**都没有 `AutomaticKeepAliveClientMixin`**（全库 grep `wantKeepAlive` 为 0）→ 切回即 `initState` 重跑（日历重新读纪念日/目标、时间线滚动位置丢失）。`animateToPage` 的 300ms 内两页同时存活 → 双倍 build。 | 给 Calendar/Timeline 加 `AutomaticKeepAliveClientMixin`（`wantKeepAlive => true` + `super.build`），或 `PageView.builder` + `KeepAlive`；代价：常驻内存 +2 页。 |
| V-2 | P1 | `main_screen.dart:557,566-569` | `build` 里 `context.watch<ThemeProvider>()` + 每次 build 都调 `SystemChrome.setSystemUIOverlayStyle`（PlatformChannel 同步调用）。`_showNavBar/_hideNavBar` 的 `setState` 每次重建整个 `Stack` + `ThemeBackgroundFactory.wrap`（新建背景 widget，非 const）。 | `SystemChrome` 移到 `didChangeDependencies`/主题变更回调；`_screens` 已是 const（`Element.updateChild` 对相同实例短路，`framework.dart:4014-4021`）所以页面不受影响，但 `Positioned`/`CustomBottomNav`/背景层每帧重建。 |
| V-3 | P1 | `gacha_screen.dart:1385-1396`、`stats_detail_screen.dart:672`、`tags_classification_screen.dart:283-296`、`diary_detail_screen.dart:1058-1067`、`diary_interactions.dart:383-390`、`calendar_screen.dart:1956-1958`、`write_diary_screen.dart:2460-2462` | 8 处 `shrinkWrap: true`（+ `NeverScrollableScrollPhysics`），外层是 `SingleChildScrollView`/`Flexible`：一次性构建全部子项、双次布局。`calendar_screen.dart:1956` 已被 `Flexible` 约束高度，`shrinkWrap` 多余。 | 外层可滚动时改为 `SliverList`/`SliverGrid`；`Flexible` 包裹的直接删 `shrinkWrap`。 |
| V-4 | P2 | `timeline_screen.dart:844-881` | 每条日记内嵌横向 `ListView.builder`（高 100 的图片条），嵌套滚动 + 无 `itemExtent`。 | 用 `Row`/`Wrap` 直接铺（≤4 张）或 `ListView` + `itemExtent: 112`。 |
| V-5 | P2 | `calendar_screen.dart:406-441` | `GridView.count(children:)` 非 builder，42 格全建（42 个 `Container` + `BoxDecoration` + 阴影 + `AnimatedDefaultTextStyle`）。42 本身不大，但每格带 implicit 动画组件（42 个 `AnimationController` 元素）。 | 保留栅格；`AnimatedDefaultTextStyle` → 选中格单独用，或改 `Text` + `AnimatedScale` 只在 1-2 格。 |
| V-6 | P2 | 全库 | `itemExtent`/`prototypeItem` 仅 1 处（`utils/performance_optimizations.dart:120`，死代码）。主列表 `timeline_screen.dart:203` 无 `itemExtent` → 滚动时逐个 layout，无法用固定步长快进。日记卡高度随内容变化，**不建议**强加 itemExtent。 | — |

---

## 3. 动画：常驻 ticker 清单（`.repeat()` 18 处，逐条核对）

| # | 位置 | 是否常驻 | 触发条件 | 说明 |
|---|---|---|---|---|
| 1 | `theme_backgrounds.dart:57`（Sakura） | 是 | 仅樱花主题 + MainScreen 可见 | 10s 循环；`build` 里 `AnimatedBuilder` 每帧还做花瓣物理（`:327-394`）+ 新建 `SakuraPainter` |
| 2-4 | `theme_backgrounds.dart:657,663,669`（Ocean 3 个） | 是 | 仅海洋主题 | `Listenable.merge` 3 控制器 → 任意一个 tick 都触发整帧 build |
| 5 | `theme_backgrounds.dart:1293`（Aurora） | 是 | 仅极光主题 | — |
| 6 | `theme_backgrounds.dart:1562`（Golden） | 是 | 仅黄金主题 | 每帧 `random.nextDouble()` 生成铭文（`:1725`）+ 沙粒更新 |
| 7 | `theme_backgrounds.dart:2012`（Starry） | 是 | 仅星空主题 | 每帧 80 星 + 流星池更新 |
| 8 | `starry_background.dart:49` | 是 | **全库 0 处引用**（死代码） | 另有 4 个流星控制器 + 4 个 Timer（`:108-115`），建议删文件 |
| 9 | `animated_feedback.dart:395` `BreathingAnimation` | 是 | `profile_screen.dart:812` 用户卡片 **常驻**、`calendar_screen.dart:2658` 高亮农历徽章 | 4s 周期 `Transform.scale`，无 `RepaintBoundary` → 「我的」页大卡片（渐变+阴影+头像 `Image.file`）**每帧重绘**。这是默认主题下唯一的持续 60fps 热点。 |
| 10 | `animated_feedback.dart:456` `PulseAnimation` | 是 | `gacha_screen.dart:552` 仅扭蛋页 | 页面内可见，可接受 |
| 11-12 | `immersive_experience.dart:246,311,394` | 是 | 仅通过 `design_extensions` 暴露，全库无直接使用 | 死代码（见 §6） |
| 13 | `motion_photo_widget.dart:46` | 是 | `write_diary_screen.dart:2053` 实况图预览 | 仅含实况图时 |
| 14 | `skeleton_loading.dart:39` `ShimmerEffect` | 是 | 由 `DiaryCardSkeleton`/`PagedDiaryList` 使用 → **无引用** | 死代码；若启用：`ShaderMask` + `GradientRotation` 每帧重建 shader |
| 15 | `diary_cinema_screen.dart:93` | 是 | 仅电影页 | 背景色渐变循环 |
| 16 | `gacha_screen.dart:90` | 是（仅摇晃时） | 抽奖中 `_startShakeAnimation` | 有 `stop()`，可控 |
| 17-18 | `voice_recorder_button(_v2).dart:52` | 是（仅录音时） | 录音中 | 可控 |

补充：`AnimatedContainer` 19 处、`AnimatedOpacity/Scale/Slide` 13 处，都是隐式动画，`didUpdateWidget` 才启动（`implicit_animations.dart:387-400`），**空闲时不耗帧**。真正「每帧都在做」的只有 §3 表里标「是」的条目。

### P1-7 `BreathingAnimation` 常驻重绘（`animated_feedback.dart:354-417` + `profile_screen.dart:812-816`）

- 机制：`Transform.scale` 每帧改 transform，`RenderTransform` 不是 repaint boundary → 子树重绘；卡片含 `LinearGradient` + 多层 `BoxShadow` + `Image.file` 头像，是整页最重的绘制单元。
- 收益：常驻 CPU/GPU 从 ~3-6ms/帧 降到 ~0（静态层），「我的」页滚动顺滑度立竿见影。
- 改法：`BreathingAnimation` 内部 `child: RepaintBoundary(child: widget.child)`；或直接把周期改成「仅入口 1 次」：
```dart
_controller.repeat(reverse: true, period: widget.duration); // 现状
// 建议：首次 forward().then 就开始 3-4 个周期后 stop，或由设置项「减弱动画」关闭
```
- 风险：极低；`RepaintBoundary` 后卡片变化（如头像更新）时重建依赖父级，正常。

### P1-8 `stats_screen` 入场动画驱动整卡 rebuild（`stats_screen.dart:392-500`、`:1158-1180`）

- 机制：`AnimatedBuilder(animation: _numberAnimation)` 的 builder 里重建 `Container(padding/decoration/Column(Row(4 个子卡)))`，动画 800ms 内每帧重建整棵统计卡；`:1158` 进度条同样每帧重建 `BoxDecoration+LinearGradient`。
- 收益：入场期帧时间 -40%；仅一次性，优先级低于常驻项。
- 改法：把 `Container/decoration` 提到 `AnimatedBuilder` 的 `child:` 参数，builder 只返回 `Text`/`FractionallySizedBox`；用 `TweenAnimationBuilder` 只包数字。

### P2-9 其它动画细节
- `scroll_reveal.dart:98-100` `Future.delayed(widget.delay)` 未取消（`dispose` 后 `mounted` 拦住，无泄漏）。
- `animated_feedback.dart:60-67` `RippleButton` 每次 tap `setState` 增删 ripple + `Future.delayed` 移除。
- `paged_diary_list.dart` `TiltCard` 已见 P1-2。
- `page_transitions.dart` 全部 `Opacity`（`:29,76,113,157,193,226`）——`Opacity` 每帧重建 widget，改 `FadeTransition`；但该文件**全库 0 处使用**（仅 `widgets.dart` 导出）。

---

## 4. 图片 / 解码清单

| ID | 严重度 | 位置 | 机制 | 改法 |
|---|---|---|---|---|
| I-1 | **P0** | `image_cache_service.dart:538-551`（`OriginalImage`）+ `diary_detail_screen.dart:1227` | `Image.file` 无 `cacheWidth` → 4000px 原图解码，约 48MB/张；全屏 `PageView.builder` 会同时持有多张 | 见 P0-5 |
| I-2 | **P0** | `platform_helpers.dart:63-69` + `image_cache_service.dart:486-491` | `cacheWidth/cacheHeight` 声明但未透传 → 无效参数；`OptimizedCachedImage` 的 `Image.file` 也不吃 | `cacheWidth: (width*dpr).round()` |
| I-3 | P1 | `platform_helpers.dart:50-55` | `FutureBuilder(File(path).exists())` 在 build 中建 future → 每次 rebuild 重新 IO + 回到 loading 态，图片闪烁 | 改 StatefulWidget，只在 `path` 变化时查一次（或删掉预检） |
| I-4 | P1 | `image_cache_service.dart:408-466` | 首图无缩略图时会 `readAsBytes` 原图 + `compute` 里 `decodeImage` + `encodeJpg`（`:133-155`）：4000px 解码在 isolate，但 **read 全文进内存** 仍有峰值（~12-20MB），首次滑动可见卡片时集中触发 | 用 `instantiateImageCodec`/`getThumbnailPath` 前先 `Image.file(cacheWidth)`（Flutter 自带降采样解码，不 peak 原图）；或生成缩略图时按 targetWidth 分块。风险：中 |
| I-5 | P1 | `timeline_screen.dart:328-330` | 头像 `Image.file(File(customAvatarPath))` 62×62 无 cacheWidth；头像入库时已 `maxWidth:300`（`profile_screen.dart:1010`），实际可控 → 仍建议加 | `cacheWidth: 124` |
| I-6 | P2 | `lazy_image.dart:65-91` | `LazyImage._updateVisibility` 用 `RenderAbstractViewport.getOffsetToReveal` + `addPostFrameCallback`；**全库 0 处使用** | 删或接线（接线时配 `cacheWidth`） |
| I-7 | P2 | `image_cache_service.dart:187-224` | `preloadImages` 队列：`Future.delayed(16ms)` 逐批；`main_screen.dart:292` + `diary_provider.dart:170` 两处调度，标题/顺序无去重跨调用（`_preloadQueue.contains` 是 List O(n) 线性查找，队列 100 时 100 次比较/次插入） | 用 `Set` 去重；预加载数量从 30 降到可见范围 |
| I-8 | P2 | `write_diary_screen.dart:238-247` | `pickMultiImage` 不带 `maxWidth/imageQuality`（对比 `time_capsule_write_screen.dart:81-83` 带了 1200/85）→ 选 10 张 4000px 原图直接 `persistImage` 拷贝（`image_persistence_service.dart:22`），之后所有缩略图都从原图生成 | 加 `maxWidth: 1600, maxHeight: 1600, imageQuality: 88` |

---

## 5. P0 / P1 / P2 汇总

- **P0：6 条**（P0-1 日历格式化+扫描 / P0-2 特殊主题全屏每帧重绘 / P0-3 逐项 ScrollReveal / P0-4 wordCount 正则 / P0-5 图片原图解码+死参数 / P0-6 全量重载联动）
- **P1：9 条**（V-1 PageView 无 keepAlive / V-2 MainScreen 每 build 平台调用 / V-3 shrinkWrap / P1-2 TiltCard 拖动 setState / P1-3 BackdropFilter 常驻模糊 / P1-7 BreathingAnimation 常驻 / P1-8 stats 整卡重建 / I-3 FutureBuilder 每帧 IO / I-4 首图峰值内存）
- **P2：11 条**（V-4/V-5/V-6、P2-9 动画细节、I-5/I-6/I-7/I-8、死代码清理、`MediaQuery.of` 46 处、`LunarDayLabel` 每格 `Theme.of`）

### P1-2（补）`TiltCard` 每个列表项都包一层（`diary_interactions.dart:122-203` + `timeline_screen.dart:679`、`paged_diary_list.dart:385,810`、`stats_screen.dart:389`）

- 机制：`LayoutBuilder` + `GestureDetector(onPanUpdate → setState)`（`:181-183`）+ `AnimatedContainer(transform: Matrix4…rotateX/rotateY/scale)`（`:189-198`）。列表里每个卡片 = 1 个 `LayoutBuilder`（额外 layout pass）+ 1 个隐式动画控制器；手指拖动时每个 move 事件都 `setState` 重建该卡片并触发 Matrix4 变化 → 整卡重绘。`onTapDown` 还无条件 `HapticFeedback.lightImpact()`（`:163-166`），快速滑动误触会抖。
- 收益：滚动时省掉每项一次 `LayoutBuilder` 布局；拖动跟手感提升。
- 改法：默认 `maxTilt: 0` 时直接返回 `child`（跳过 `LayoutBuilder`/`GestureDetector`）；或列表场景（timeline/paged list）用 `TiltCard(maxTilt: 0)`：
```dart
if (widget.maxTilt <= 0 && widget.onTap == null && widget.onLongPress == null) {
  return widget.child;   // 零成本退化
}
```
- 风险：低。

### P1-3 `BackdropFilter` 常驻（`custom_bottom_nav.dart:44-48`、`glass_panel.dart:93-99`）

- 机制：底部导航 `ImageFilter.blur(sigmaX: 20, sigmaY: 20)` 每帧对条带区域做高斯模糊（saveLayer + blur）；特殊主题下背后是每帧变化的 `CustomPaint` → blur 每帧重算。`glass_panel` 用于自言自语输入区，键盘弹出时也常驻。
- 收益：底部导航模糊是整屏宽度、常驻可见；降 sigma 或按需开启可省 2-4ms/帧。
- 改法：`sigma` 20→12；或特殊主题下改半透明纯色（`scheme.cardColor.withValues(alpha: 0.92)`）；或 `RepaintBoundary` 包住导航条避免跟随页面重绘。
- 风险：视觉差异需设计确认。

---

## 6. 死代码 / 未接线（不影响运行，但会误导后续优化，且 `dart analyze` 无法发现）

| 文件 | 状态 | 依据 |
|---|---|---|
| `lib/widgets/lazy_image.dart`（341 行） | **0 处使用** | `LazyImage(`/`LazyImageList`/`LazyImageGrid` 仅定义 |
| `lib/widgets/paged_diary_list.dart`（874 行） | **0 处 import** | `import ... paged_diary_list.dart` 无匹配；`PagedDiaryList` 仅定义 |
| `lib/widgets/starry_background.dart`（432 行） | **0 处使用** | `theme_backgrounds.dart` 自带同名 `StarryBackground`，外部 import 无 |
| `lib/widgets/page_transitions.dart`（~340 行） | 仅 `widgets.dart` 导出 | 无页面使用 `FadeSlideTransition` 等 |
| `lib/widgets/swipeable_list_item.dart` | **0 处 import** | — |
| `lib/utils/performance_optimizations.dart`（`RepaintBoundaryWrapper`/`OptimizedListView`） | 仅被 `utils/utils.dart` 导出，业务 0 使用 | 全库 `RepaintBoundary` 0 业务用法 |
| `lib/services/database_service_native.dart`（1314 行，sqflite） | **0 处 import** | Lead 已核实，`database_service.dart` 只 export web 版 |
| `lib/widgets/immersive_experience.dart`（`MagicText`/`NeonText`/`FloatingParticles`/`TypewriterText`） | 仅经 `design_extensions` 扩展方法或 `widgets.dart` 导出，实际 0 使用 | grep 调用点为空 |

建议：本次优化先清理这 8 个文件/导出（约 3.5k 行），避免后续有人在 `LazyImage` 上白做优化；`lazy_image.dart` 若要保留，必须接线并加 `cacheWidth` 才有意义。

---

## 7. 假设的卡顿场景复现路径（可复现 / 可量化）

1. **日历页掉帧（默认主题，与主题无关）**：准备 800+ 篇日记 → 进「日历」→ 连点左/右月切换 10 次。预期：每次切月 `setState` → 42 格 × 4 次 `DateFormat` + 42 次 `getDiariesByDate` 线性扫（P0-1）→ 单帧 4-8ms；实测 DevTools timeline 可见 `build` 段尖峰。改后应 <2ms。
2. **收藏/删除后全局顿一下**：在 800 篇规模下，在时间线点收藏 → `toggleFavorite` + `updateDiary` 全量加密写 + `notifyListeners` → 时间线整页 + 日历 42 格 rebuild（P0-6 + P0-1），叠加 DB 全量 JSON 写（另一模块）。预期 UI 线程阻塞 50-150ms（N=1000）。改后 <16ms（DB 侧另计）。
3. **开特殊主题后整机发烫 + 全程掉帧**：设置里切「星空主题」→ 回到时间线滚 10 秒。预期：`theme_backgrounds.dart:2076-2101` 每帧满屏 CustomPaint（80 星 + MaskFilter 光晕）+ 整页内容随背景重绘（P0-2）→ 帧 16ms 打满，低端机 30fps 以下。对照实验：切「温馨米」同操作应正常 —— 这条同时验证「是否背景导致」。
4. **进详情页/全屏看图卡顿 + 偶发闪退**：选一篇含 5 张手机原图的日记 → 打开 → 点首图进入全屏 → 左右快滑 3 张。预期：每张 4000px 原图解码 ≈48MB（P0-5/I-1），3 张即 >120MB → 低端机 OOM/GC 抖动，表现为「滑两下卡住然后闪退」。改后用 `cacheWidth=屏幕宽×dpr` 复测内存应 <20MB。
5. **首个可见图片「闪一下」**：在时间线快速上下滚 → `PlatformImage` 的 `FutureBuilder` 每次 rebuild 重新 `exists()`（I-3）→ 图片回到 loading 占位一格再出图，视觉上像闪烁/白块。
6. **切标签页重新加载**：日历 → 时间线 → 日历 → 时间线，每轮都触发 `initState`（V-1：无 `AutomaticKeepAliveClientMixin`）→ 日历重读纪念日/目标、时间线滚动位置归零；日记多时每次切回有可见延迟。
7. **（非默认主题下）底部导航模糊代价**：特殊主题 + 滚动时展开底部导航（下滑隐藏/上滑出现）→ `BackdropFilter(sigma 20)` 每帧对条带 blur，与背景动画叠加（P1-3 + P0-2）。

---

## 8. 未覆盖 / 交接说明

- 本次**未读**：`profile_screen.dart`（111KB，仅涉 `:812` BreathingAnimation 与 `:1010` 头像压缩）、`write_diary_screen.dart`（91KB，仅涉图片选取与 `:928` RippleButton）、`gacha_screen.dart`（80KB，仅涉 `:552`/`:1385`）、`stats_screen.dart` 余下部分、`stats_detail_screen.dart`、`diary_detail_screen.dart` 全文。如需这几页的逐项热点，建议由负责对应模块的成员补。
- 本报告的「收益」为静态推算（基于 widget 数量 × 每帧构造/扫描次数量级），非真机 profile 数据；建议修复后按 §7 的 7 条路径用 DevTools Timeline + `--profile` 复测。
- 与其它模块的耦合点：P0-6 的「写放大」需 DB 模块改增量；P0-2 的「设置项 reduceMotion」需 SettingsProvider 新增开关（跨模块）。
