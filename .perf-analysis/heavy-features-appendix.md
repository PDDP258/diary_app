# 附录：重功能页卡顿问题地图（按用户旅程重排）

> 已按 crosscheck 更正 A5、按 startup-native 复核更正 A6（见 `.perf-analysis/crosscheck.md`）。

> 配套主报告 [heavy-features.md](./heavy-features.md)。本附录**不重复 P0 机制细节**，只引用 ID + 一句话，重点回答两件事：**排期怎么排**、**验收怎么验**。
>
> 口径：徽章 = **79**（去重 id 数）；扭蛋奖励 = **97**；字体 23.97MB（PDF **只解析 1 份**，粗体那份是死代码，见主报告 P3-1）。
> 旅程覆盖的 8 条路径全部来自真实 UI 入口（已核对 import 链，**不含死代码页**）。

---

## 0. 摘要表（先看这个）

| # | 旅程 | 主卡顿时长量级 | 有无 loading 反馈 | 修复成本 |
|---|---|---|---|---|
| J1 | 冷启动 → 首屏可交互 | **1.5~4s**（1000 篇时） | 有（全屏转圈，无骨架） | M |
| J2 | 切底部 4 个 tab | stats: **1~5s**；calendar: 50~200ms；timeline/profile: <100ms | stats 有转圈，其余无（纯冻结感） | S |
| J3 | 滚动时间线列表 | 首屏后 **每滚动到 20 篇边界卡 200~600ms** | 有（底部 loading indicator） | S |
| J4 | 写日记 → 保存 → 返回 | **1~3s**，页面卡住不退出 | 有按钮转圈，但**卡住超过 1s 不 pop** | S |
| J5 | 打开带图日记 → 点开大图 → 滑 | 打开 <300ms；**滑第 2~3 张起 300~800ms/张，或 OOM** | 无（黑屏等解码） | S |
| J6 | 日历翻月 / 点某天 | 翻月 **50~200ms**；点某天 30~150ms | 无 | S |
| J7 | 搜索 / 统计详情 / 情绪页 | 搜索 **每键 100~800ms**；统计详情 **1~5s**；情绪页 **300~1500ms** | 搜索有 spinner；详情有卡片级 spinner；情绪页有 spinner | S~M |
| J8 | 数据管理：PDF / 云同步 / 本地备份 | PDF **5s~分钟级 + 可能 OOM**；云同步 **10s~分钟级 + 可能 OOM**；本地备份 **200~800ms** | PDF **完全无反馈**；云同步有 spinner；备份有 spinner | M~L |

**一句话结论**：8 条旅程里有 **5 条**（J1/J2/J5/J7/J8）在"用户会反复走的路径"上，其中 **J5 和 J8 是闪退来源**、**J2 和 J4 是最容易被投诉"卡"的来源**（因为出现频率最高）。

---

## 1. 按用户旅程分组

### J1｜冷启动 → 首屏可交互

**触发**：点击桌面图标。
**卡顿时长量级**：**1.5~4s** 白屏/开屏动画期（1000 篇日记、3.2MB JSON 时）；低端机更久。
**证据（file:line）**：
- `main.dart:24-76` —— `main()` 内 **7 个串行 `await`** 后才 `runApp()`：`initializeDateFormatting` → `AppProtectionService.checkAppIntegrity`（仅 release）→ `CloudSyncFactory.initialize` → `SyncLogService.initialize` → `SoundService.initialize` → `ThemeProvider.loadSettings` → `CourseWidgetService.initialize`。**任何一环慢都直接推迟首帧**。
- `database_service_web.dart:91-112` `_loadData()` → `:235-267` `_decryptDiariesSync()`：**逐条 `await _decryptDiaryMap`**（串行 AES），1000 篇 = 2000 次 AES 解密。
- `splash_screen.dart:153-154` `delayBeforeStart: 1200ms` + `flipDuration: 800ms`（每月一次的完整动画固定占 **2s**，日常简版也有 ~1.2s 动画时间）。
- `main_screen.dart:546-556` 首屏 gate 是**全屏 `CircularProgressIndicator`**（无骨架屏）。
- `main_screen.dart:243` `provider.loadAllData()` 只加载最近 20 篇（`diary_provider.dart:80-94`）—— 这点是**做对的**，但被前面 7 个 await 和 splash 固定动画拖累。
- 启动后 `main.dart:62` `AutoBackupService.checkAndBackup()` 立即触发全量备份序列化（P2-5）。

**加载反馈**：✅ 有全屏转圈；❌ 无骨架屏（`lib/widgets/skeleton_loading.dart` 有现成 `DiaryCardSkeleton`，但只在 `paged_diary_list.dart:282` 用过，**主流程没用**）。
**修复成本**：**M**（要拆 `main()` 的串行 await + 改 splash 逻辑，有回归面）。

> **最小止血（≤0.5 天）**：把 `main.dart:40-54` 的 `SyncLogService.initialize()` / `SoundService.initialize()` / `CourseWidgetService.initialize()` 改成 `unawaited()` 后置（它们不影响首屏）；`AppProtectionService.checkAppIntegrity()` 移到 `runApp` 后。
> **根治方案（重构）**：① 存储层切 sqflite（P0-6）→ 启动只查 20 行而非解析全量 JSON；② `main()` 只保留 `ensureInitialized` + `ThemeProvider.loadSettings`，其余全部 `Provider` 内部懒加载；③ 首屏改骨架屏（复用现有 `DiaryCardSkeleton`）。

---

### J2｜切底部 4 个 tab（timeline / calendar / stats / profile）

**触发**：点底部导航。
**卡顿时长量级**：
| tab | 切过去后多久可用 | 原因 |
|---|---|---|
| timeline | <50ms | 数据已在 Provider（`Consumer<DiaryProvider>`） |
| calendar | **50~200ms** | 42 格 `GridView.count` + 每格若干 `Container`/渐变（`calendar_screen.dart:406-410`），且外层 `Consumer<DiaryProvider>` 会随任何 provider 通知重算"本月 N 篇"（`:203-211` 每次 `DateFormat('yyyy-MM').format`） |
| **stats** | **1~5s** | **每次重新 `initState → _loadStats()`**（见下） |
| profile | <100ms（首帧），但**随后 4 次整页 rebuild** | `profile_screen.dart:58-64` 并发 4 个服务调用各自 `setState`（P1-4） |

**核心证据（stats 是重灾区）**：
- `main_screen.dart:617-621` `PageView(children: _screens, physics: NeverScrollableScrollPhysics)` —— **没有 `allowImplicitScrolling`，四个 tab 页也都没有 `AutomaticKeepAliveClientMixin`**（全仓 grep 零命中）→ 离屏即 `dispose`，**切回"统计"就重新 `initState`**。
- `stats_screen.dart:50-53` `initState → _initAnimations() + _loadStats()`；`_loadStats`（95-174）内含 **P0-2 的 N+1**（147-152）+ 全量 `DateFormat.parse`（108）+ 全量 `wordCount`（118）+ `getMoodDistribution()` 再一次全量（127）。
- `stats_screen.dart:245-254` loading 时是**整页转圈**，所以用户看到的是"切到统计 → 白转圈 1~5 秒 → 内容"。

**加载反馈**：stats ✅ 整页转圈（但**每次切都转**，体验差）；calendar/timeline/profile ❌ 无（直接冻结一下）。
**修复成本**：**S**（只改 keepalive + 缓存，不动架构）。

> **最小止血（≤0.5 天）**：给四个 tab 页加 `AutomaticKeepAliveClientMixin`（`wantKeepAlive => true` + `super.build(context)`），一行改动让 stats 只算一次。**风险**：四个页面常驻内存（stats 有 2 个 AnimationController，profile 111KB 树），低端机会多占 20~40MB → 建议**只给 stats 加**（它最贵），另三个保持现状。
> **根治方案**：把统计聚合搬到 `DiaryProvider`（存一个 `StatsSnapshot`，`loadDiaries` 后算一次，写日记时增量更新）→ 页面纯读，`initState` 只剩 `_animateFromSnapshot()`。同时 profile 的 4 个服务调用合并为 1 个 `Future.wait` + 1 次 `setState`。

---

### J3｜滚动时间线列表

**触发**：在时间线上下滑。
**卡顿时长量级**：通常 <16ms/帧，但**每滚到 `hasMoreData` 边界触发 `loadMoreDiaries()` 时卡 200~600ms**（1000 篇时）。
**证据**：
- `timeline_screen.dart:203-208` `ListView.builder(itemCount: diaries.length + (hasMoreData ? 1 : 0))` —— ✅ 用了 builder，✅ 未一次性建全量。
- `timeline_screen.dart:53-62` `_onScroll` 在距底 200px 时触发 `provider.loadMoreDiaries()`（第 55-59 行）。
- `diary_provider.dart:97-127` `loadMoreDiaries` → `getDiariesPaged`（`database_service_web.dart:388-402`：**每次分页都 `List.from(_diaries)..sort()` 全量排序**）→ 每加载 20 篇就 **O(N log N) 排序 + O(N) 拷贝**。
- `timeline_screen.dart:218-229` 前 10 项套 `AnimatedBuilder` 入场动画（✅ 只前 10 个，做对了）。
- `timeline_screen.dart:844-877` 每张卡最多 4 个横向缩略图，用 `PlatformImage(cacheWidth: 200)` —— ⚠️ **但 `cacheWidth` 是死参数**（P2-7a），实际靠 `CacheQuality.small`(300px) 兜底，尚可。
- `main_screen.dart:611-612` `NotificationListener<ScrollNotification>` 在**整棵页面树外层**，每个滚动事件都进 `_onScrollNotification` 并可能 `setState`（隐藏/显示导航栏）→ 滚动时**额外 rebuild `MainScreen`**（含 `PageView` + 导航栏 `AnimatedSlide`）。

**加载反馈**：✅ 底部有 `_buildLoadMoreIndicator`（`timeline_screen.dart:211`）。
**修复成本**：**S**。

> **最小止血（≤0.5 天）**：`_onScrollNotification` 里加节流（同一帧只处理一次，或 `ScrollUpdateNotification` 间隔 <50ms 直接 return）；`getDiariesPaged` 加个"已排序缓存"（`_sortedCache` 在 `_saveDiaries` 时失效）→ 滚动加载从 200~600ms 降到 <20ms。
> **根治方案**：切 sqflite（`LIMIT/OFFSET` 走索引，无排序）；`MainScreen` 的导航栏状态用 `ValueNotifier` + `ValueListenableBuilder` 只重建导航栏，不重建整个 `PageView`。

---

### J4｜写日记 → 点保存 → 返回

**触发**：在写日记页点"保存"。
**卡顿时长量级**：**1~3s**，且**页面不退出**（`Navigator.pop` 在 await 之后）。
**证据（按耗时排序）**：
1. **写放大（最大头，P0-6）**：`diary_provider.dart:207-229` `addDiary` → `database_service_web.dart:439-449` `insertDiary` → `:270-280` `_saveDiaries()`：**全部 N 篇重跑 AES + 全量 `jsonEncode` + 全量 `setString`**；再 `:329-339` `_updateMetadata()` 又跑**全量 `wordCount`**（每篇 new RegExp，`diary.dart:108-121`）+ 第二次全量写盘。
2. `diary_provider.dart:222` `loadRecentDiaries(limit: (_currentPage+1)*20)` → 又一次 `getRecentDiaries`（全量 sort + sublist）。
3. **徽章检查（P0-5）**：`write_diary_screen.dart:792-854` 串行 8 组；`:814-845` 每组遍历 79 个 Badge；`badge_service.dart:2184-2186` 全量 `wordCount`；`:1300-1314` `unlockBadge` 每次 `SharedPreferences.getInstance()` + 3 次写。
4. `write_diary_screen.dart:653-655` `await _checkMilestoneAfterSave(); if (mounted) Navigator.pop(...)` —— **pop 在最后**，用户必须等完所有检查。
5. `write_diary_screen.dart:616-635` 保存后 `Future.delayed(3s)` 触发云同步（不阻塞保存，✅ 做对了）。
6. `write_diary_screen.dart:128, 132-152` `_contentController.addListener(_analyzeSentiment)` —— **每输入一个字符**都跑 `SentimentAnalysisService.analyze`（121 个 `contains` + 46 次字符串拼接）。打字时可能掉帧（这条归 J4 的"输入期"）。
7. `write_diary_screen.dart:539-542` `_validateInput` 里 `RegExp` 每次 new + 全文 `replaceAll`。

**加载反馈**：✅ 保存按钮转圈（`write_diary_screen.dart:919-923`）；❌ 但**卡 1~3 秒不 pop**，用户会以为没生效而重复点（二次触发）。
**修复成本**：**S**（止血）/ **L**（写放大根治）。

> **最小止血（≤0.5 天）**：
> ① `diary.dart:113` `RegExp` 提为 `static final`；
> ② `write_diary_screen.dart:653-656` **先 `Navigator.pop` 再 `_checkMilestoneAfterSave()`**（用 `rootNavigator` 弹徽章）；
> ③ `write_diary_screen.dart:132-152` 情绪分析加 300ms debounce。
> 预期：1~3s → **300~800ms**（写放大仍在）。
> **根治方案**：P0-6 的按 id 分 key 存储（只写变更行）+ 徽章检查改增量计数（不要每次全量遍历）→ 保存降到 **<100ms**。最后切 sqflite。

---

### J5｜打开一篇带图日记 → 点开大图 → 左右滑

**触发**：时间线点一篇有图的日记 → 点缩略图。
**卡顿时长量级**：
- 打开详情页：<300ms（`DiaryDetailScreen.initState` 只做 `Future.wait([_loadTags, _loadAnniversaries, _loadAdjacentDiaries])`，`diary_detail_screen.dart:43-47, 54-79`；`_loadAdjacentDiaries` 内部有一次全量 `List.from(provider.diaries)..sort`，但只有一次）。
- **点开大图 → 滑到第 2~3 张：300~800ms/张，或直接 OOM 闪退**。
**证据**：
- **`OriginalImage` 无 `cacheWidth`（P2-7b，闪退 Top2.5）**：`diary_detail_screen.dart:1221-1230` 全屏查看器 → `OriginalImage` → `image_cache_service.dart:536-543` `Image.file(File(path))` **裸解码原图**。4000×3000 → **48MB/张**，`ImageCache` 默认上限 100MB → **滑 2~3 张必爆**。
- `diary_detail_screen.dart:1204-1211` `PageView.builder` 默认预载相邻页 → 同一时刻 2~3 张原图在 cache 里。
- `diary_detail_screen.dart:1145-1168` `_checkMotionPhotos()`：**对每张图串行 `await isMotionPhoto()` + 可能的 `extractVideo()`**（`motion_photo_service.dart:14-20, 27+`，每次都 `File.exists()` + 读图片元数据），每完成一张就 `setState` → **N 次 rebuild**。图片多时点开大图后还在后台跑这个循环。
- `stats_detail_screen.dart:1243-1246` 统计详情"照片回忆"同样 `useOriginal: true`（同一路径）。

**加载反馈**：❌ **完全没有**（黑屏等解码，或直接崩）。
**修复成本**：**S**（一条 `cacheWidth` 解决 90%）。

> **最小止血（≤0.5 天）**：`image_cache_service.dart:536-543` 给 `Image.file` 加 `cacheWidth: 1200, cacheHeight: 1600` —— **单张从 48MB 降到 ~4MB**，滑 20 张都不爆。同时把 `_checkMotionPhotos` 改成懒检测（只在长按时检查当前这张）。
> **根治方案**：图片入库时生成并存储 2 档缩略图（1200px 预览 + 300px 列表），全屏只读 1200px 档；原图仅"下载/分享"时用。需要写日记保存时加一步压缩（`image_picker` 已带 `maxWidth` 参数但 `write_diary_screen.dart:238` 未传）。

---

### J6｜日历页翻月 / 点某天

**触发**：日历页左右翻月；点某一天。
**卡顿时长量级**：翻月 **50~200ms**；点某天 **30~150ms**。
**证据**：
- `calendar_screen.dart:694-703` `_previousMonth` / `_nextMonth` 只 `setState(_currentMonth = ...)` → **不重新查数据**（✅ 数据来自 `provider.diaries` 已在内存）→ 卡顿全部来自**重建 42 格网格**。
- `calendar_screen.dart:406-410` `GridView.count(children: _getDaysInMonth().map(...))` —— ⚠️ **`children:` 而非 `builder`**，42 个格子**全部立即构建**（每格含 `GestureDetector` + `Container` + 渐变 + 可能 `CalendarImage`）。
- `calendar_screen.dart:203-211` 顶部"本月 N 篇"在 `Consumer<DiaryProvider>` 里，**每次 rebuild 都 `DateFormat('yyyy-MM').format(_currentMonth)` 再全量 `where`**（1000 篇逐条 `startsWith`）。
- `calendar_screen.dart:1391-1415` `_getDaysInMonth()` 每月调用一次，构 42 个 `DateTime`（便宜）。
- `calendar_screen.dart:1432-1437` 点某天 → `context.read<DiaryProvider>().getDiariesByDate(dateStr)` → `diary_provider.dart:39-41` `_diaries.where((d) => d.date == date).toList()` = **O(N) 线性过滤**（1000 篇 = 1000 次字符串比较，约 30~100ms）。
- `calendar_screen.dart:90-93` build 顶部 `AppTheme.schemeOf`（`context.watch<ThemeProvider>`）+ `Consumer<DiaryProvider>` 包整页 → 两个 provider 任一通知都全页 rebuild。

**加载反馈**：❌ 无（但 50~200ms 尚在可感知边缘，多数用户不会投诉）。
**修复成本**：**S**。

> **最小止血（≤0.5 天）**：`GridView.count` → `GridView.builder`；"本月 N 篇"改成 `provider.datesWithDiaries` 预建 `Map<String,int>`（按月聚合）或直接删掉这个实时 `where`；`getDiariesByDate` 改成 `provider.diaries.where(...)` 只算一次并缓存为 `Map<String, List<Diary>>`（Provider 内、`loadDiaries` 时重建）。
> **根治方案**：日历网格改 `CustomPainter` 一次绘制（或 `SliverGrid` + `RepaintBoundary`），日期→日记索引由 Provider 预聚合。

---

### J7｜搜索（简版）/ 统计详情页 / 情绪页

**触发**：日历搜索按钮 / 统计页"查看详情" / 统计页"情绪分析"卡片。

#### J7-a 搜索（`diary_search_screen.dart`，实际在用）
- 卡顿：**每键 100~800ms**（1000 篇时）。
- 证据：`diary_search_screen.dart:215-223` **假防抖**（`Future.delayed(300ms)` 不可取消，靠第 219 行文本比对过滤）→ 快速输入排队多次；`:58` 用 `provider.diaries`（**只有最近 20 篇**，`diary_provider.dart:25,80-84`）→ **正确性 bug**：搜不到第 21 篇以后的日记；`:62-69` 每篇 2 次 `toLowerCase()` + `sort`。
- loading：✅ 结果区有 spinner；但**输入框每键触发 `setState`** 也重绘整页。
- 成本 **S**。

#### J7-b 统计详情页（`stats_detail_screen.dart`）
- 卡顿：**1~5s**（成语分析）。
- 证据：`stats_detail_screen.dart:47-49` `initState → _analyzeTexts()`；`:62` `TextAnalysisService.getTopIdioms` → `text_analysis_service.dart:178-184` **797 成语 × N 篇 `contains`**（P1-3）；`:71` `extractMoodSnippets` → `:328` **每篇 `split(RegExp(...))` 编译一次**。
- loading：✅ **有卡片级 spinner**（`stats_detail_screen.dart:216-248` `_buildLoadingCard` "正在分析日记内容..."）—— 这是全 app 做得最好的加载反馈。
- 成本 **S**（提 RegExp + 成语改 4-gram 哈希，半天内）。

#### J7-c 情绪页（`emotion_stats_screen_v2.dart`，实际在用）
- 卡顿：**300~1500ms**。
- 证据：`emotion_stats_screen_v2.dart:36-52` `_loadData` → `:42` `SentimentAnalysisService.analyzeDiaries(diaries)` → `sentiment_analysis_service.dart:275-285` **每篇调 `analyze()`**，而 `analyze`（131-182）是 55+66 词 × 23 修饰词的 double loop，每命中还新建 `mod.key + entry.key` 字符串（P1-2）；`:54-90` `_generateWeeklyData` = 7 天 × 全部日记 `where` + 每篇 `DateTime.parse`。
- loading：✅ `:132` 转圈。
- 成本 **M**（要改 analyze 算法或搬 isolate）。

**统一最小止血（≤0.5 天）**：
① 搜索：`Timer? _debounce` 真防抖 + 数据源改 `getAllDiaries()`；
② 统计详情：`RegExp` 提 `static final`；成语匹配改一次 4-gram 滑窗；
③ 情绪页：`analyzeDiaries` 用 `compute` 丢 isolate（`List<Diary>` 可发送），UI 只等结果。
**统一根治方案**：三个页面都改成"Provider 预聚合 + 页面只读"，分析结果带版本号缓存（数据没变就不重算）。

---

### J8｜数据管理：导出 PDF / 云同步 / 本地备份

**触发**：我的 → 数据管理。

#### J8-a 导出 PDF（最危险）
- 卡顿：**5s ~ 分钟级**；**可能直接 OOM 闪退**。
- 内存量级（**已按 crosscheck A1 更正**）：字体 **只解析 1 份 ≈ 36~60MB**（`pdf_export_service.dart:98-100`；粗体那份 `:187` 是**死代码从未执行**，见主报告 P3-1）+ **全部原图字节**（每张 4000×3000 解码 ≈ 48MB；`exportDiaries` 每篇 `take(4)`，`exportSingleDiary` **无上限**→单篇 20 张 ≈ 960MB 即可崩）+ `pdf.save()` 整本序列化。**峰值由图片主导，不是字体。**
- 证据：`data_management_screen.dart:1171-1182` `_exportPdf()` **在 UI 线程 `await`，无 loading flag、无遮罩**；`pdf_export_service.dart:356/:507` 原图 `readAsBytes` → `pw.MemoryImage`（不缩放）、`:464-467` `pdf.save()` 整本序列化。
- loading：❌ **零反馈**（`_buildMenuItem` 的 `isLoading` 参数在 PDF 这个 item 上**没传**，见 `:158-165`；只有 `.mbk` 导出/导入传了）。
- 成本 **M**（止血）/ **L**（完整 isolate 化）。

#### J8-b 云同步（含"手动同步图片"）
- 卡顿：**10s ~ 分钟级**；图片多时 OOM。
- 证据：`data_management_screen.dart:717-760` `_syncImages` → `cloud_sync_service.dart:1138-1214` `_createEncryptedImageArchive`：**单个 `Archive` 装全部图片字节**（P0-4）。
- 内存量级（**已按 crosscheck A4 上调**）：设总图片字节 S、zip 后 Z≈0.9S，共 **5 份存活物** → **主 isolate ≈ 3.7S，进程峰值 ≈ 4.7S**（`Archive` 累积 S + `Isolate.spawn` 深拷贝 S + `zipBytes` Z + `Uint8List.fromList` 拷贝 Z + 密文 Z）。300 张×3MB → 进程 ≈ **4.2GB**。详见主报告 P0-4 机制表。
- 另一条：`data_management_screen.dart:692-714` `_startSync`（不含图片）→ `uploadBackup`（`:468-571`）**同一份 bytes PUT 两次**（新路径 + 旧路径兼容，`:534-552`）→ 上传时间 ×2、流量 ×2。
- loading：✅ 有 spinner（`:253-262`、`:374-383`、`:516-525` 三处 `_isSyncing`）；❌ **但无进度百分比**、无取消按钮。
- 成本 **M**（分卷止血）/ **L**（流式）。

#### J8-c 本地备份（`.mbk`）
- 卡顿：**200~800ms**（1000 篇 ≈ 3.2MB JSON）。
- 证据：`backup_export_service.dart:40-93` 导出全程主 isolate：`jsonEncode` → `utf8.encode` → AES → `ZipEncoder` → `writeAsBytes`（峰值 ~4 份数据副本，P2-4）；`:97-148` 导入反向一遍 + `data_management_screen.dart:1063-1068` 再建 List + `importDiaries`（`database_service_web.dart:452-472` 逐条 `indexWhere` = **O(N²)**）。
- loading：✅ 有 spinner（`_isExporting`/`_isImporting` 都传给了 `_buildMenuItem`）。
- 成本 **S**（`compute` 包一层）。

**统一最小止血（≤0.5 天）**：
① PDF 菜单项传 `isLoading: _isExporting` + 进函数先 `setState(true)`（**10 分钟改动，立刻消除"点了没反应"**）；
② **PDF 图片缩到 1200px + 给 `exportSingleDiary` 加 `take(4)`**（这是真正防 OOM 的一条）；
③ `.mbk` 导出把 `jsonEncode`+`sha256` 挪 `compute`。
> ⚠️ crosscheck A1 更正：原先这里写的「删 `_chineseBoldFont` 第二次 24MB 加载」**不是止血项** —— 它唯一入口 `preloadFonts()` 无调用者，本来就不执行，删了无运行时收益（只作为 P3-1 死代码清理）。
**统一根治方案**：PDF 图片预缩 1200px + 分页流式 save；云同步图片分卷（≤20MB/卷）；`.mbk` 用 `ZipFileEncoder` 流式落盘。

---

## 2. 本轮建议的修复批次

> 原则：**batch-1 全部是"改一行/删一段"级别、零架构风险、能在真机上立刻量出效果**；batch-2 是"半天~一天一个"的中等改动；batch-3 需要设计评审与数据迁移。

### 🔴 batch-1（立即做，≤1 天总计，可并行）

| # | 任务 | 对应 ID / 旅程 | 改动量 | 依赖 |
|---|---|---|---|---|
| B1-1 | `OriginalImage` 的 `Image.file` 加 `cacheWidth:1200, cacheHeight:1600` | P2-7b / **J5 闪退** | 2 行 | 无 |
| B1-2 | `diary.dart:113` 的 `RegExp` 提为 `static final` | P0-5 子项 | 2 行 | 无 |
| B1-3 | PDF 菜单项补 `isLoading: _isExporting` + `_exportPdf` 首行 `setState(true)` | J8-a 无反馈 | 3 行 | 无 |
| B1-4 | **`exportSingleDiary` 加 `take(4)` 张数上限**（`pdf_export_service.dart:503` 现在无限制，单篇 20 图 ≈ 960MB 直接崩） | P0-1 / **J8-a 闪退** | 1 行 | 无 |
| B1-5 | `write_diary_screen.dart:653-656`：先 `Navigator.pop` 再跑徽章检查 | J4 / P0-5 | 5 行 | ⚠️ 徽章弹窗要改 `rootNavigator: true`，否则 context 失效 |
| B1-6 | `diary_search_screen.dart:215-223` 假防抖改真 `Timer` | J7-a | 10 行 | 无 |
| B1-7 | `text_analysis_service.dart:328` RegExp 提 `static final` | P1-3 | 3 行 | 无 |
| B1-8 | `main_screen.dart:160-172` 给 `_showNavBarImmediately` 加状态短路（现在**无守卫**，一次调用 = 2 次整页 rebuild，且被 5+ 处调用） | J2/J3 | 3 行 | 无；见 §3-V3(b) |
| B1-9 | 【P3，可延后】删 `preloadFonts()` / 标记 `_loadChineseBoldFont()` 勿接线（死代码，**无运行时收益**，纯防未来误用） | P3-1（crosscheck A1） | 5 行 | 无 |

**验收标准（batch-1 后必须复测）**：
- J5：滑 10 张图不闪退；DevTools Memory 面板峰值 <150MB。
- J4：保存按钮点击到页面返回 <800ms。
- J8-a：点"导出 PDF"后**立刻**出现转圈（≤100ms 内有反馈）。
- J7-a：连续输入 5 个字符，只在停止后触发 1 次搜索（DevTools Performance 看 `_performSearch` 调用次数 = 1）。

### 🟡 batch-2（一周内，按依赖排序）

| # | 任务 | 对应 ID / 旅程 | 预估 | 依赖关系 |
|---|---|---|---|---|
| B2-1 | `image_cache_service.dart:133-142`：缩略图生成改成"isolate 内部读文件"，不再把原图 bytes 跨 isolate 传 | P2-7c | 0.5d | 无 |
| B2-2 | `PlatformImage` 把 `cacheWidth/cacheHeight` 真正传给 `OptimizedCachedImage`（需要给 `OptimizedCachedImage` 加这两个参数并透传到 `Image.file`） | P2-7a | 0.5d | **必须在 B2-1 之后**（否则缩略图路径变了要重测） |
| B2-3 | 统计页聚合搬进 `DiaryProvider`，产出 `StatsSnapshot` + 版本号；`stats_screen` 只读 | P1-1 / P0-2 / J2 | 1d | 无 |
| B2-4 | 统计页 N+1 改 `getAllDiaryTags()` 一次拉平 + `Map<tagId,name>` 聚合 | P0-2 | 0.5d | 与 B2-3 同一文件，**必须 B2-3 之后或合并做** |
| B2-5 | 云同步图片**分卷**（每卷 ≤20MB，独立 encode/encrypt/upload） | P0-4 / J8-b | 1d | 无（但要先确认 `archive ^3.4.10` 的 `ZipFileEncoder` API） |
| B2-6 | PDF 图片 `compute` 缩到 1200px 再 `MemoryImage` | P0-1 / J8-a | 1d | 无 |
| B2-7 | `.mbk` 导出/导入的 `jsonEncode`+`sha256` 挪 `compute` | P2-4 / J8-c | 0.5d | 无 |
| B2-8 | `smart_recall_service`：`getSmartRecalls` 只取一次 `getAllDiaries()` 传给 4 个分支 | P2-6 子项 | 0.5d | 无 |
| B2-9 | `goal_service.dart:249-267` 365 次按日期查询改 Set 查一次 | P2-8 | 0.5d | 无 |
| B2-10 | `calendar_screen.dart:406` `GridView.count` → `builder` + "本月 N 篇"改预聚合 | J6 | 0.5d | 无 |
| B2-11 | 情绪页 `analyzeDiaries` 丢 `compute` | P1-2 / J7-c | 0.5d | ⚠️ `SentimentResult` 需可发送（当前是纯数据类，OK） |

### 🟢 batch-3（重构，需要设计评审 + 数据迁移窗口）

| # | 任务 | 对应 ID | 预估 | **硬依赖 / 前置条件** |
|---|---|---|---|---|
| B3-1 | **写放大止血（不动存储后端）**：`_saveDiaries` 改按 id 分 key（`diaries_data_<id>`），只重写变更行 | P0-6 | 2d | 无。**建议先做这条**，它比切 sqflite 风险低、收益立竿见影 |
| B3-2 | 徽章检查改**增量计数**：Provider 维护 `uniqueDays/currentStreak/totalCount/totalPhotos/totalChars` 五个整数并持久化，页面直接读 | P0-5 / J4 | 2d | **B3-1 之后**（否则保存时还是要全量扫） |
| B3-3 | 合并 `main_screen._checkMilestone` 与 `write_diary._checkMilestoneAfterSave` 为一个 `BadgeService.runAll(context, trigger)` | P0-5 | 0.5d | B3-2 之后 |
| B3-4 | **切回 sqflite**（`database_service.dart` 改成 conditional export） | P0-6 根治 | 5~8d | ⚠️⚠️ **强依赖下面 4 条，必须先补完** |
| B3-4a | 前置：核实 `database_service_native.dart` 可编译（它**从未被任何文件 import**，是死代码） | — | 0.5d | B3-4 的第 0 步 |
| B3-4b | 前置：native 版补齐 web 版现有但 native 缺的 API（**至少 5 个**：`getAllDiaryTags`、`getDiaryTagIdsV3`、`mergeDiaryTags`、`importDiaries`、`restoreMoods/restoreTags` 的批量语义） | — | 1d | B3-4a |
| B3-4c | 前置：补 conditional export（`dart.library.io` → native / 否则 web），**当前全仓 0 处条件导入** | — | 0.5d | B3-4b |
| B3-4d | 前置：**数据迁移**——SharedPreferences 全量 JSON → SQLite 行，需双写过渡 + 行数校验 + 回滚开关 | — | 2d | B3-4c |
| B3-5 | 首屏骨架屏（复用 `widgets/skeleton_loading.dart` 的 `DiaryCardSkeleton`）+ `main()` 只留 `ensureInitialized` | P2-5 / J1 | 2d | B3-4（启动耗时主要来自全量 JSON 解析） |
| B3-6 | 主题背景 `CustomPaint` 外包 `RepaintBoundary` + `child` 移出 painter 子树 + 背景 30fps 限帧 | P2-1 / J3 | 3d | 独立，但**只对 5 个特殊主题生效**，优先级低 |

**批次总览（依赖图）**：
```
batch-1（并行，无依赖）──┬─→ B2-1 ─→ B2-2
                         ├─→ B2-3 ─→ B2-4
                         ├─→ B2-5 / B2-6 / B2-7 / B2-8 / B2-9 / B2-10 / B2-11（互相独立）
                         └─→ B3-1 ─→ B3-2 ─→ B3-3
                                                  │
        B3-4a → B3-4b → B3-4c → B3-4d ────────────┴─→ B3-4（sqflite 上线）
                                                          └─→ B3-5（骨架屏 + 启动瘦身）
```

---

## 3. 必须真机验证的假设（静态分析无法定论）

> 每条都给了 **观测工具 → 具体指标 → 判定阈值 → 结论如何影响排期**。建议全部在**同一台低端机**（如 4GB RAM / 中低端 SoC）上跑，因为目标是消除"用户反馈的严重卡顿"。

### V1｜存储层写放大的真实耗时占比
- **假设**：`_saveDiaries()`（全量 AES + 全量 JSON + 全量写盘）占 J4 保存耗时的 **50%~80%**。
- **测量方法**：在 `_saveDiaries()` 首尾加临时 `Stopwatch`（或直接用 DevTools **Performance → Record** 抓一次保存，在 flame chart 里找 `jsonEncode` / `encryptTextV2` / `SharedPreferences.setString` 的 span）。
- **指标**：`_saveDiaries` 自身耗时 / `_saveDiary` 总耗时。
- **判定阈值**：若 >60% → B3-1（按 id 分 key）**优先于** B2 全部任务；若 <30% → 说明卡顿主要来自徽章检查，B3-2 提前。
- **额外**：用 `adb logcat | grep -i "choreographer\|Skipped"` 看保存瞬间是否 `Skipped N frames`（N>30 即 >0.5s）。

### V2｜`ImageCache` 峰值是否真的是闪退主因（J5）
- **假设**：滑 3~5 张原图后 `ImageCache.currentSizeBytes` 逼近 100MB。
- **测量方法**：DevTools **Memory 面板** → 滑图，观察 `imageCache.currentSizeBytes` / `liveImages`；同时 `adb logcat | grep -i "OutOfMemory\|dalvikvm.*heap"`。
- **判定阈值**：单张 >30MB 或累计 >80MB → 与 P2-7b 的估算一致，B1-1 **必做且最高优先**；若单张仅 5~10MB（用户图片本身小），则 J5 的闪退另有原因（需查 `Hero` 重复解码或 `motion_video` 提取）。
- **补充**：`Flutter DevTools → App Size` 不适用；要看 **Memory → Snapshot** 里 `Image` 对象数量。

### V3｜滚动时间线时 `MainScreen` 是否被高频 rebuild（J3）
- **假设**：`NotificationListener<ScrollNotification>` 导致滚动期间 `MainScreen.build` 被反复触发。
  > 用词已规范：不预设"每帧"。判据见主报告 §P2-6 开头 —— `main_screen.dart` 里 `_onScrollNotification` 只在 `scrollDelta > 10` / `< -5` 时调 `_hideNavBar`/`_showNavBar`，而这两个**都有状态守卫**，所以理论与帧率无关；实测只需看调用次数。
- **测量方法**：DevTools **Performance → Record**，滚动 5 秒；在 flame chart 里看 `_MainScreenState.build` 的调用次数。
- **判定阈值**：滚动 5s（300 帧）内 `build` >100 次 → 需要把导航栏状态从 `setState` 改为 `ValueNotifier` 局部刷新（新增任务，可放 batch-2）。
- **静态分析已能排除一半（重要）**：
  - `_showNavBar()`（`main_screen.dart:151-158`）✅ **有 `if (!_isNavVisible)` 守卫**；
  - `_hideNavBar()`（`:174-179`）✅ **有 `if (_isNavVisible)` 守卫**；
  - 滚动路径 `_onScrollNotification`（`:399-441`）只调这两个 → **理论上滚动不会产生无谓 setState**。
  - ⚠️ 但 **`_showNavBarImmediately()`（`:160-172`）完全没有守卫**：无条件 `setState` + 一个 `Future.delayed(100ms)` 再 `setState`，一次调用 = **2 次整页 rebuild**。它被 `_onPageChanged`（`:356/361`）、`_onNavTap`（`:370`）、各个 push/pop 返回处理（`:215/231/458/528`）调用 → **频繁切 tab / 进出页面时是真的会重建**。
  - 因此 V3 要分开测：**(a) 纯滚动时 build 次数**（预期很低，若高则查 NotificationListener 判定）；**(b) 一次 tab 切换 + 返回后 1 秒内 build 次数**（预期 ≥4 次，来自 `_showNavBarImmediately` 的双 setState × 多次调用）——(b) 才是真问题，修法是给 `_showNavBarImmediately` 加 `if (_isNavVisible && _forceShowNav) return;` 之类的短路。

> **「每帧 rebuild」类断言的统一判据（crosscheck A5/A6/C2 教训，务必先跑再断言）**
>
> `AnimatedBuilder` / `TweenAnimationBuilder` **只重建自己的 builder 子树，不会让外层 `build()` 重跑**；`SlideTransition` / `FadeTransition` 是 `Transition`（走 RenderObject 更新 transform/opacity），**也不触发 widget rebuild**。
>
> **满足 (a) 或 (b) 任一即成立：**
> - **(a) 该文件有 `addListener` + `setState`**；**或**
> - **(b) 目标子树确实被动画 widget 包住**。
>
> ⚠️ **`(b)` 不要求 `addListener`** —— `AnimatedBuilder` 通过 `animation:` 自行订阅 `Listenable` 并每帧重跑 builder。所以 **`grep addListener` 返回 0 只能排除 (a)，不能据此判定「不会每帧重建」，必须继续查 (b) 以及「目标子树是否真被包住」。**
> 反例防误杀：`theme_backgrounds.dart` 的 `addListener`=**0**，但 `AnimatedBuilder`=5 / `AnimationController`=14 / `..repeat()`=7 且 builder 返回 `CustomPaint(child: widget.child)` → 满足 (b)，**每帧重绘成立**（正例，见主报告 §P2-1）。
> 正例防误判：`stats_screen` 文件级动画计数不低（`AnimatedBuilder` 2 / `TweenAnimationBuilder` 1），但都只包**卡片内部**、不含去年今日卡 → **不成立**（A6 已更正）。
>
> 自检两步（缺一不可）：`Select-String -Path lib\screens\<file>.dart -Pattern 'addListener'`；再查 `-Pattern 'AnimatedBuilder|TweenAnimationBuilder|\.repeat\(\)'` 并结合**作用域**判断。完整实测表见主报告 §P2-6。

### V4｜统计页切 tab 的真实重算成本（J2）
- **假设**：每次切回 stats 都完整跑 `_loadStats`（含 N+1），耗时 1~5s。
- **测量方法**：DevTools **Performance** 录一次"timeline → stats → timeline → stats"；数 `_loadStats` 出现次数，并看其中的 `getTagsByDiaryId` 累计时间。
- **判定阈值**：`_loadStats` 单次 >1s → B2-3/B2-4 合并成一个任务做；<300ms → 只需加 `AutomaticKeepAliveClientMixin`（B2 优先级下调）。
- **补充**：`adb shell dumpsys gfxinfo <pkg> framestats` 看切 tab 那几帧的 `janky_frames` 占比。

### V5｜PDF 的**图片**解码占用（J8-a）—— 假设已按 crosscheck A1 改写
- **假设（原假设作废）**：原文假设「`_loadChineseBoldFont` 多占 40~70MB」。**crosscheck A1 已证否**：其唯一入口 `preloadFonts()` 全仓库无调用者，该字体在实际导出路径上**从未解析**（0 次执行），所以**没有"多占"可言**。
- **改写后的待验证假设**：PDF 导出的内存峰值**由图片主导**，字体只占 36~60MB（单份）。
- **测量方法**：DevTools **Memory → 取快照**，在 4 个点各拍一次：① `exportDiaries` 进函数、② 字体加载完（`:280` 之后）、③ 图片全部 `MemoryImage` 化之后（循环结束）、④ `pdf.save()` 之后。对比各阶段 `Dart heap` 增量。
- **判定阈值**：若阶段 ② 增量 >80MB → 说明 pdf 包对 VF 解析比预期重（仍需关注，但**不是双份**）；若阶段 ③ 增量 >> 阶段 ② → **确认图片是主因**，B2-6（缩到 1200px）与 B1-4'（`exportSingleDiary` 加 take 上限）的优先级升到最高。
- **附带验证**：导出**单篇**带 3 张图的日记，量化每张图 `pdf.save()` 前后的真实解码占用（校准 B2-6 的 1200px 目标）。
- **不要再去验证"双份字体"** —— 静态分析已定论（0 次执行），测它只会浪费时间。

### V6｜云同步图片的真实峰值（J8-b）—— 量级已按 crosscheck A4 上调
- **假设**：**主 isolate ≈ 3.7S、进程峰值 ≈ 4.7S**（S = 总图片原始字节；原报告「≈3×」已作废）。5 份存活物：Archive 累积 S + `Isolate.spawn` 深拷贝 S + `zipBytes` Z + `Uint8List.fromList` 拷贝 Z + 密文 Z。
- **测量方法**：准备一个含 **50 张 3~5MB 图** 的测试账号；DevTools **Memory** 全程录曲线，或用 `adb shell dumpsys meminfo <pkg>` 在同步中每 5s 采样 `TOTAL PSS`。
- **判定阈值**：进程峰值 **>500MB** → 必须 B2-5（分卷）；<200MB → 说明测试账号图片总量小，B2-5 可延后，但"图片多"的生产账号仍需做。
- **额外要确认的两点**：
  1. `_processImageBatchIsolate` 每批 spawn 一个新 Isolate（`cloud_sync_service.dart:1217-1236`），确认 Isolate 是否及时退出（`adb shell ps -T <pkg> | grep -c dart` 观察线程数）。
  2. **crosscheck A4 第 5 点存疑项**：`:1175` 传的是 `fileData['bytes'] as List<int>`，来源是 `readAsBytesSync()`（返 `Uint8List`，不膨胀）；但若 `archive` 包内部发生 `.toList()` 拷贝，每字节 boxed int 会显著膨胀。**用 heap snapshot 看 `ArchiveFile.content` 的实际类型与大小**（`Uint8List` 还是 `List<int>`），这一条会决定峰值是 4.7S 还是更高。

### V7｜搜索"假防抖"是否真的触发多次全量搜索（J7-a）
- **假设**：连续输入 5 字符 → 触发 5 次 `_performSearch`。
- **测量方法**：DevTools **Performance** 录制输入过程，数 `_performSearch` 的调用次数与各自耗时；或临时加 `debugPrint(DateTime.now())` 在 `:57` 前后。
- **判定阈值**：调用次数 >2 且单次 >100ms → B1-6 必做；若实际只触发 1 次（因为 300ms 内文本已变，`Future.delayed` 的回调都不满足条件），则说明"假防抖"行为上近似正确，仅需清代码。
- **同时验证**：搜索第 21 篇以后的日记能否命中（**正确性 bug**，与性能无关但同样要修）。

### V8｜启动 7 个串行 await 的各自耗时（J1）
- **假设**：`main()` 的 7 个 await 合计占冷启动 30%~60%。
- **测量方法**：`adb shell am start -W <pkg>/<activity>`（拿 `TotalTime`）；再用 DevTools **Performance** 冷启动 profile（`flutter run --profile` + "Profile app startup"），看 `main()` 各 await 的 span。
- **判定阈值**：`main()` 内合计 >1s → B3-5 提前；<400ms → 冷启动慢主要是 splash 固定动画（`splash_screen.dart:153` 的 1200ms+800ms），改动画时长即可（**最小止血**：日常简版动画从 1.2s 降到 0.6s）。
- **注意**：`AppProtectionService.checkAppIntegrity()`（`main.dart:33`，仅 release）可能含文件校验/签名读取，release 包才有影响 —— **必须用 release 或 profile 包测**，debug 包结论无效。

---

## 4. 附：本附录引用的主报告 ID 速查

| ID | 一句话 | 主报告章节 |
|---|---|---|
| P0-1 | PDF：原图直入 MemoryImage 不缩放 + `exportSingleDiary` 无张数上限（字体只解析 1 份） | §P0-1 |
| P0-2 | 统计页 N+1 标签查询（存储层是内存线性扫） | §P0-2 |
| P0-3 | 增强搜索每键全量 + **无重入守卫（乱序）**（**页面是死代码，零 import**） | §P0-3 |
| P0-4 | 云同步图片全堆单个 Archive（**主 isolate ≈3.7S / 进程 ≈4.7S**） | §P0-4 |
| P0-5 | 保存后 8 组徽章全量检查 + 全量 wordCount(RegExp) | §P0-5 |
| P0-6 | 存储层写放大：每保存一次全量重加密+全量写盘 | §P0-6 |
| P1-1 | 统计页每次进入全量重算（页面不保活） | §P1-1 |
| P1-2 | 情绪分析 double loop 逐篇调用 | §P1-2 |
| P1-3 | 统计详情 797 成语 × N + 每篇编译 RegExp | §P1-3 |
| P1-4 | profile 首屏无懒加载 + 4 次并发 setState | §P1-4 |
| P1-5 | 简版搜索只有 20 篇数据 + 假防抖 | §P1-5 |
| P2-1 | 特殊主题每帧全页重绘（仅 5 个主题受影响） | §P2-1 |
| P2-2 | 抽卡 4 处内联 future（**仅 1 处在首屏；动画不触发父级 rebuild** → P3 轻微） | §P2-2 |
| P2-4 | .mbk 备份全程主 isolate + 无进度 | §P2-4 |
| P2-5 | 启动即全量自动备份 | §P2-5 |
| P2-7 | 图片层：`cacheWidth` 死参数 + 全屏原图无限制 | §P2-7 |
| P2-8 | 目标系统 365 次按日期全表扫描 | §P2-8 |
| P3-1 | 死代码：`preloadFonts()` + `_loadChineseBoldFont()` 无调用者（crosscheck A1） | §P3-1 |
