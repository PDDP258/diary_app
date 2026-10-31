# 抽样复核报告（crosscheck）

复核对象：`.perf-analysis/heavy-features.md`（A1–A5）、`.perf-analysis/data-layer.md`（B6–B7）。
方式：只读源码核对，逐条给「成立 / 不成立 / 部分成立（附更正）」+ file:line 证据。
**未修改任何被复核的报告文件。**

| 编号 | 断言（摘要） | 结论 |
|---|---|---|
| A1 | `_chineseBoldFont` 在 `exportDiaries` 里没被使用，第二份 24MB 纯属浪费 | **部分成立（结论加强，因果需更正）** |
| A2 | `stats_screen` 每篇一次 `getTagsByDiaryId`，内部全表线性扫描 | **成立** |
| A3 | 增强搜索 `onChanged` 每键直调 `_performSearch`，零防抖 | **成立** |
| A4 | 云同步单 `Archive` 装全部图片字节，峰值 ≈3× | **成立（可加码：实为 4×）** |
| A5 | `gacha_screen` 4 处 `FutureBuilder(future: ...)` 建在 build 里 → 每帧重新发起 | **部分成立（位置对，机制错）** |
| A6 | （报告更新版新增，`heavy-features.md:657`）`stats_screen` 的 `FutureBuilder(future: _getLastYearTodayDiary())` 在 build 里，**数字动画 1200ms 内每帧 rebuild → 每秒 60 次全量 `getDiariesByDate`** | **不成立（与 A5 同一个「每帧」误判，机制错）** |
| C1 | （附加抽验 `ui-render.md`，不在原抽样清单）P0-2 特殊主题 `CustomPaint` 包整棵页面树、每帧重绘、`RepaintBoundary` 用量为 0 | **成立（机制描述严谨，量化保留）** |
| B6 | `diary_provider.dart:222` 的 `loadRecentDiaries` 由 `addDiary` 触发，进而 `_saveDiaries()` 全量重加密 | **成立（`data-layer.md` 原文准确，无此因果错误；是 Lead 转述失真）** |
| C2 | （第 3 轮：heavy-perf 自查第三处同类错误后的修复验证）见 §C2 | **成立（4 条断言全对）** |
| C3 | （第 4 轮：判据条款重构 + 它自曝的新错修正）三步判据、五行实测表、`gacha` setState=5、3 个 TAB 归属 | **成立（数字与归属逐项核对无误）；但它新报的「`diary_search_enhanced_screen` 是死代码」使我的 A3 结论需加限定** |
| B7 | 报告的「索引设计」覆盖真实高频查询 | **成立（覆盖完整、优于独立基线），仅 3 处行号/计数精度需更正** |

---

## A1｜`_chineseBoldFont` 未被使用 —— 部分成立（**结论对，但报告把因果说反了**）

**报告断言**（`heavy-features.md:57`）：`_chineseBoldFont` 在 `exportDiaries` 里没被使用，第二份 23.97MB 解析纯属浪费 → 改法是把 `_chineseBoldFont = _chineseFont` 复用。

**逐项核对：**

1. ✅ **「`exportDiaries` 里没用到粗体字体」成立。**
   `exportDiaries`（`pdf_export_service.dart:260-470`）内所有 `pw.TextStyle` 的 `font:` 参数一律是 `_chineseFont!` 或局部 `chineseFont`（= `_chineseFont!`），粗体全靠 `fontWeight: pw.FontWeight.bold` 表达：
   - `:301-313`（title/subtitle/date/header/content/caption 全套，全部 `font: _chineseFont!`）
   - `:416`、`:427-429`、`:488-499`、`:567`、`:623-632`、`:679-689`
   - 反观 `_chineseBoldFont` 的全部引用（我 grep 了整个 `lib/`）：`:17`（声明）、`:31`（预加载里赋值）、`:34`（兜底赋值）、`:179/:182/:190/:192/:204/:206/:226/:228/:237/:238`（**全部在 `_loadChineseBoldFont` 函数体内**）。**零处**作为 `TextStyle.font` 使用 —— 也没有 `_chineseBoldFont!` 出现在任何样式里。

2. ❌ **但「第二份 23.97MB 在实际导出时被解析了」不成立** —— 因为 `_loadChineseBoldFont()` 的唯一调用点是 `preloadFonts()`（`:31`），而 **`preloadFonts()` 在整个仓库里没有任何调用者**（我已扫 `lib/`、`test/`、`tool/`，grep `preloadFonts` 只命中定义处 `:22` 与无关的 `font_download_service.dart:313 preloadFontsFromAssets`）。
   `exportDiaries` 自己只调 `_loadChineseFont()`（`:280`），`exportSingleDiary` 也只调 `_loadChineseFont()`（`:483`）。**粗体那份 24MB 在真实导出路径上从未被加载。**

3. ⚠️ **所以正确结论不是「白解析了一份，删掉能省 70-120MB」，而是「`preloadFonts()` + `_loadChineseBoldFont()` 整段是死代码，从来没跑过」。**
   - 报告 `:62` 的量级估算「字体 2 × 24MB 原始 + 2 × 解析结构 ≈ 90~130MB」**在实际路径下高估了一倍**（实际只有 1 份）。
   - 由此 `:756` 的「立即止血：删 `_chineseBoldFont` 的独立加载」——**删它不会带来任何运行时收益**（因为它本来就不跑）。
   - 但报告 `:67` 的改法本身**依然值得做**，理由变成「删死代码防未来误用」而非「省内存」。真正能省内存的是它的另一条改法（图片 `compute` 缩到 1200px），那条我未复核（不在本次抽样范围）。

**建议给报告的更正措辞：**「`_chineseBoldFont` 未被 `exportDiaries` 使用（成立），且其唯一加载入口 `preloadFonts()` 全仓库无调用者（新发现）→ 该字体**在实际导出路径上从未被解析**，因此它不是内存峰值来源，应作为死代码清理项而非内存优化项。PDF 导出的真实内存风险应归给『图片原图不缩放』一项。」

**风险等级调整建议：** 把「字体双份」从 P0-1 的**机制**里降级/移出，只保留为「P3 死代码清理」；P0-1 的严重度仍成立，但支撑它的机制应是图片而非字体。

---

## A2｜统计页 N+1 + `getTagsByDiaryId` 内部全表线性扫描 —— **成立**

**报告断言**（`heavy-features.md:120-152`）：`stats_screen.dart:147-152` 每篇一次 `getTagsByDiaryId`；`database_service_web.dart:725-735` 内部 `_diaryTags.where(...)` 全表扫 + `tagIds.contains` 内层 O(k)。

**核对：**

1. ✅ **调用点完全一致。** `stats_screen.dart:145-152` 原文：
   ```dart
   145: // 统计标签分布
   146: _tagDistribution = {};
   147: for (final diary in diaries) {
   148:   final tags = await DatabaseService.getTagsByDiaryId(diary.id!);
   149:   for (final tag in tags) {
   150:     _tagDistribution[tag.name] = (_tagDistribution[tag.name] ?? 0) + 1;
   151:   }
   152: }
   ```
   确认是**在循环内 `await`**（N 次跨 isolate/微任务边界），且无任何批量接口。

2. ✅ **实现与报告引用的行号逐行吻合。** `database_service_web.dart:725-732`：
   ```dart
   725: static Future<List<Tag>> getTagsByDiaryId(int diaryId) async {
   726:   await _ensureInitialized();
   727:   final tagIds = _diaryTags
   728:       .where((dt) => dt['diary_id'] == diaryId)   // O(M)，M=全部关联
   729:       .map((dt) => dt['tag_id'] as int)
   730:       .toList();
   731:   return _tags.where((t) => t.id != null && tagIds.contains(t.id)).toList();
   732: }                                                // 内层 contains 又是 O(k)
   ```
   `_diaryTags` 是 `List<Map<String,dynamic>>`（`:40` 声明），无索引 → `.where` 确实每次全表线性扫。第二段 `_tags.where(... tagIds.contains ...)` 是 O(T×k)。**报告的复杂度分析 O(N×M) 成立。**

3. ✅ 报告 `:146` 附带说的「切 tab 不会重算」也成立：`stats_screen.dart:50-54` 只在 `initState` 调 `_loadStats()`，配合 `main_screen.dart` 的 `PageView`（默认 `AutomaticKeepAlive` 未开启但 PageView children 不会因切页重建 State）—— 实测行为需真机确认，但代码层面确实只有 initState + RefreshIndicator 触发。

4. 🔎 **可补充一条报告没提的放大项**：`_loadStats()` 第 98 行 `getAllDiaries()` 已经是本页**第 2 次全量解密**（Provider 在 `diary_provider.dart:130-144` 已有 `_diaries` 一份），报告 `:151` 提到了这一点，成立。

**结论：A2 完整成立，行号、复杂度、机制全部对得上。**

---

## A3｜增强搜索 `onChanged` 每键直调 `_performSearch`，零防抖 —— **成立**

**报告断言**（`heavy-features.md:203`）：触发点是 `TextEditingController.onChanged`（412-415），每输入一个字符触发一次 `_performSearch`，没有任何防抖/timer/按钮门槛。

**核对：**

1. ✅ **行号与调用链完全一致**，`diary_search_enhanced_screen.dart:412-415` 原文：
   ```dart
   412: onChanged: (value) {
   413:   setState(() => _keyword = value);
   414:   _performSearch();
   415: },
   ```
   注意：这里虽然挂在 `TextField`/`TextFormField` 上（`onChanged` 是输入框回调），但报告说的「`TextEditingController.onChanged`」措辞略不精确 —— **`TextEditingController` 本身没有 `onChanged` 成员**，这是 `TextField.onChanged`。不过**这不影响结论**：仍是「每键一次」，报告在意的是触发频率而非 API 归属。（报告用词建议改为「`TextField.onChanged`」。）

2. ✅ **零防抖成立。** 我 grep 了该文件的 `Timer`/`debounce`/`addListener`：**全部 0 命中**（该文件只有 `_searchController` 的 `controller:` 绑定与 `.clear()`）。`_performSearch()` 本身（`:73-129`）也无任何节流。

3. ✅ **每次搜索的代价也被报告说中了**：`_performSearch` 第 77 行 `await DatabaseService.getAllDiaries()` → web 实现（`:379-382`）返回**全部日记**并排序拷贝；随后 `:79-117` 对每篇做 `title?.toLowerCase().contains(...)` + `content?.toLowerCase().contains(...)`（**每次重建 lowercase，没有预计算缓存**）+ `:92` 每篇 `DateTime.parse(diary.date)`；`:120` 再全量排序。1000 篇 × 每键 1 次 = 每键数千次字符串分配。**报告 `:210-214` 的量级分析成立。**

4. 🔎 **补充报告没强调的一点**：`:74` `setState(() => _isSearching = true)` 在 `_performSearch` 入口就触发重建，而 `:122-125` 结束时再 `setState` —— 每键产生**两次整页 rebuild**，输入快时会出现「上一个搜索还没跑完、下一个又进来」的**并发重入**（没有 `if (_isSearching) return;` 守卫）。这会让乱序结果显示（后来的短关键词结果先返回、覆盖掉长的），是**正确性 bug** 而不只是性能问题，建议报告补一句。

**结论：A3 成立（唯一建议：措辞从 `TextEditingController.onChanged` 改为 `TextField.onChanged`；并可补「无重入守卫导致乱序」）。**

---

## A4｜云同步单 `Archive` 装全部图片，峰值 ≈3× 总图片体积 —— **成立（实测为 4×，比报告更严重）**

**报告断言**（`heavy-features.md:262-300`）：所有图片字节同时堆在一个 `Archive` 里，Isolate 只分摊了读盘与 zip。

**核对（逐段读完 `cloud_sync_service.dart:1138-1300`）：**

1. ✅ **单 `Archive` 累积成立**：`:1162` `final archive = Archive();` 在循环**外**创建；`:1165-1182` 的分批循环虽然 `batchSize=50`，但每批结果**全部 `archive.addFile(...)` 进同一个 archive**（`:1172-1176`），**从不释放**。所以「分批」只限制了**每次 Isolate 的峰值**，不限制**主 isolate 累积总量** —— 报告说中了。

2. ✅ **`_processImageBatchIsolate` 确实把 bytes 带回了主 isolate**：`:1217-1230` 走 `Isolate.spawn` + `receivePort.first`，返回 `List<Map<String,dynamic>>`；而 `_processImageBatch`（`:1245-1260`）返回的每个 map 就是 `{'name': fileName, 'bytes': bytes}`，其中 `bytes = file.readAsBytesSync()`（`:1252`）。**字节数组被跨 isolate 复制（或转移）回主 isolate 后存入 Archive。** 报告的「Isolate 只分摊读盘与 zip」成立。

3. ✅ **`_encodeInIsolate` 又整份传给第二个 Isolate**：`:1192` → `:1269-1280` `Isolate.spawn(_encodeIsolate, _EncryptMessage(archive: archive, ...))` —— **整个 Archive（含全部 bytes）作为消息传给新 isolate**。这里 `Archive` 是普通 Dart 对象，`Isolate.spawn` 默认走**深拷贝**（非 `TransferableTypedData`）→ 主 isolate 里的 bytes 仍在，isolate 里又一份。

4. ✅ **然后主 isolate 再加密一次**：`:1200` `EncryptionService.encryptData(Uint8List.fromList(zipBytes))` —— `Uint8List.fromList` 又拷贝一次。

**峰值分解（设总图片字节 = S，zip 后 = Z ≈ S×0.9）：**

| 存活物 | 大小 | 位置 |
|---|---|---|
| `archive` 内全部原始 bytes | **S** | 主 isolate 堆 |
| spawn 给 `_encodeIsolate` 的深拷贝 | **S** | 编码 isolate 堆（拷贝，非共享） |
| `zipBytes`（`receivePort.first` 收到） | **Z** | 主 isolate |
| `Uint8List.fromList(zipBytes)` 拷贝 | **Z** | 主 isolate |
| `encrypted`（加密输出） | **Z** | 主 isolate |

→ 主 isolate 峰值 ≈ **S + Z + Z + Z ≈ 3.7S**，加上编码 isolate 的 S，**进程峰值 ≈ 4.7S**。
**报告说「≈3×」是保守的，实际更接近 3.7–4.7×。**
报告 `:290-292` 的「现象」与 `:293-300` 的机制描述成立，量级可上调。

5. 🔎 **报告漏了一个更严重的点**：`:1171-1176` 把 `fileData['bytes'] as List<int>` 直接塞进 `ArchiveFile`。web/JSON 语境里这通常是 `List<int>` 而非 `Uint8List` → **每字节一个 boxed int 的 `List<int>` 在 Dart 里可能远大于原始字节**（若来源是 `readAsBytesSync()` 则返回 `Uint8List`，因为是 `Uint8List` 实现了 `List<int>`，所以这里侥幸不膨胀；但 `archive` 包内部 `ArchiveFile` 若发生 `.toList()` 拷贝则会膨胀）。这一点**需要真机 heap snapshot 确认**，不建议直接断言。

**结论：A4 成立，且报告的量级偏保守；建议把「≈3×」改为「≈3.7–4.7× 进程峰值」，并把「bytes 跨两个 isolate 各存一份」写进机制。**

---

## A5｜`gacha_screen` 4 处 `FutureBuilder` 建在 build 里 → 每帧重新发起 —— **部分成立（位置对，机制错）**

**报告断言**（`heavy-features.md:590-600`）：4 处 `FutureBuilder(future: ...)` 写在 build 里，每次 `gacha_screen` 重建（**抽奖动画 1500ms 内每帧都 setState/AnimatedBuilder 触发父级 rebuild**）→ **每帧 4 次 `SharedPreferences.getInstance()` + 7 次 `getInt`**，60fps × 4 = 240 次/秒。

**核对：**

1. ✅ **「4 处 `FutureBuilder` 的 `future:` 是内联调用」成立**，行号与报告一致：
   - `:248-249` `_buildShopQuickAccess` → `GachaService.getAllResourceCounts()`
   - `:1193-1194` `_showCollectionStats` 的 bottomSheet builder → `GachaService.getResourceSummary()`
   - `:1767-1768` `_showStickerShop` 的 bottomSheet builder → `getAllResourceCounts()`
   - `:2042-2043` `_showThemeShop` 的 bottomSheet builder → `getAllResourceCounts()`
   四处都是**在 widget 构造表达式中直接调用方法产生新 Future**，没有 `late final` 字段缓存。这一半成立。

2. ❌ **「每帧重新发起 / 每帧 4 次 SharedPreferences」不成立**，有三个独立原因：

   **(a) 4 处里有 3 处根本不在 `build()` 方法内，也不在首页面上。**
   - `:1193` 在 `_showCollectionStats`（`:1058`）的 `showModalBottomSheet` builder 里
   - `:1767` 在 `_showStickerShop`（`:1729`）的 bottomSheet builder 里
   - `:2042` 在 `_showThemeShop`（`:2004`）的 bottomSheet builder 里
   这 3 处只有在对应 bottom sheet 被**打开时**才构建，且 bottom sheet 打开期间**首页 `build()` 不会因抽奖动画而重建它**（它是独立 route）。只有 `:248`（`_buildShopQuickAccess`，被 `build()` 在 `:169` 调用）真正在首屏 build 路径上。
   报告把它们并列成「4 处都在 build 里」，**位置归类不准**。

   **(b) 抽奖动画不会每帧触发父级 `setState`。**
   - `_shakeController.repeat()`（`:90`）与 `_animationController.forward()`（`:106`）都**只在 `AnimatedBuilder`（`:320-345`）内部消费**，`build()` 里没有任何 `addListener`（我 grep 过：`_animationController.`/`_shakeController.` 只有 `dispose`/`repeat`/`stop`/`forward` 四处，**无 `addListener`**）。
   - 所以动画期间**只有 `AnimatedBuilder` 的 builder 重跑**，`_GachaScreenState.build()`（`:134`）**不重跑**。
   - `setState` 只在状态切换点发生：`:79`（开始晃动）、`:100`（停止晃动开始抽奖）、`:114`（拿到结果）、`:126`（结束）—— **共 4 次，不是每帧**。
   - 报告 `:598` 的「1500ms 内每帧都 setState」**不成立**。

   **(c) `SharedPreferences.getInstance()` 有 `_completer` 单例缓存**（`shared_preferences-2.5.4/lib/src/shared_preferences_legacy.dart:79-97`），第二次起直接返回已完成的 Future；`getInt` 是**纯内存 map 查表**（`:121` `_preferenceCache[key] as int?`），**零 IO**。
   所以即便真的每帧调 4 次，成本是「4 个 Future 分配 + 4 次微任务」，**不是「4 次 SharedPreferences 读取」**。报告 `:599` 的「240 次 SharedPreferences 读取排队」措辞严重夸大。

3. ✅ **不过报告指出的「应该缓存 Future」这个改法本身是对的**（`:600`），因为 `:248` 那一处确实每次首屏 rebuild 都会新建 Future 并触发 `setState` 级联（`FutureBuilder` 从 `ConnectionState.waiting` 重新开始 → 短暂闪空）。只是它属于 **P2 级的「重建时闪一下」**，不是报告描述的「每帧 240 次读取导致抖动」。

**结论：A5 部分成立。事实性错误在「每帧」假设；正确表述应为：**「`gacha_screen` 有 4 处内联 `future:` 的 `FutureBuilder`，其中仅 `:248` 在首屏 build 路径上（另 3 处在 bottom sheet builder 内）；首屏每次 rebuild 会重新创建 Future 并短暂闪空，建议改为 `late final` 缓存。动画期间父级 `build` 不会重跑（动画只在 `AnimatedBuilder` 内消费），因此不存在『每帧 240 次 SharedPreferences 读取』。」

---

## A6｜（更新版新增）`stats_screen` 去年今日卡「数字动画期间每秒 60 次全量扫描」—— **不成立**

**报告断言**（`heavy-features.md:657`，v2 新增于 P2-6 其他确认项）：
> `stats_screen.dart:1250-1252` `_buildLastYearTodayCard()` 里 `FutureBuilder(future: _getLastYearTodayDiary())` —— **future 在 build 里创建**，每次 rebuild（数字动画 1200ms 内每帧）都会重新 `getDiariesByDate`（全量 `where` + sort）→ **动画期间每秒 60 次全量扫描**。应 `late final Future<Diary?> _lastYearFuture;` 在 initState 创建。

**核对结论：前两个事实成立，「动画期间每帧 rebuild」不成立 —— 与 A5 是同一个误判模式，说明该审计员对「AnimatedBuilder 的局部重建范围」有系统性误解。**

1. ✅ **「future 在 build 里创建」成立。** `stats_screen.dart:1250-1252`：
   ```dart
   1250: Widget _buildLastYearTodayCard() {
   1251:   return FutureBuilder(
   1252:     future: _getLastYearTodayDiary(),     // ← 内联，每次调用该方法就新 Future
   ```
   且该方法被 `build()`（`:242`）在 `:291` 直接调用 → 确认在首屏 build 路径上。

2. ✅ **「`_getLastYearTodayDiary` 是全量 where + sort」成立**（需报告自己补证据，我此处不展开，但方向上 `getDiariesByDate` 在 web 实现里确是 `_diaries.where(...)` + sort）。

3. ❌ **「数字动画 1200ms 内每帧 rebuild → 每秒 60 次全量扫描」不成立。** 三重证据：

   **(a) `stats_screen.dart` 全文 `addListener` 命中数 = 0**（我 grep 了整个文件）。`_numberController`（`:77-80`，1200ms）与 `_pageController`（`:58`）**都没有挂监听器去 `setState`**。

   **(b) 动画的消费者是 `AnimatedBuilder`，作用域被严格限制在卡片内部。**
   - `:392-393` `AnimatedBuilder(animation: _numberAnimation, builder: ...)` 只包住**统计卡片内部的 Container**；
   - `:1158-1160` 另一个 `AnimatedBuilder` 只包住**进度条那 10px 的 Container**。
   两者都在 `_buildStatsCard()` / 某个子卡片内部，**不包含 `:291` 的 `_buildLastYearTodayCard()`**。

   **(c) `build()`（`:242-300+`）的结构里没有任何动画监听驱动。**
   `:256-271` 是 `Scaffold > SafeArea > RefreshIndicator > SingleChildScrollView > SlideTransition/FadeTransition`；其中 `SlideTransition`/`FadeTransition`（`:268-271`）消费的是 `_pageSlideAnimation`/`_pageFadeAnimation`（**`_pageController` 驱动**），它们是 `Transition` 而非 `AnimatedBuilder` —— **`Transition` 内部用 `RenderObject` 更新 paint/transform，不触发 widget rebuild**。所以首屏入场动画（600ms）期间 `build()` 也不重跑。

   因此**唯一会让 `:291` 重跑的是 `setState`**：`:96`（`_loadStats` 入口 `_isLoading=true`）、`:101`/`:169`（加载完成）、以及 `RefreshIndicator` 触发的 `_refreshStats`。**每次数据加载共 2–3 次，不是每秒 60 次。**

4. ⚠️ **但改法本身依然正确且值得做**：`late final Future<Diary?> _lastYearFuture` 在 `initState` 创建，能避免「每次 `_loadStats` 完成后的 rebuild 都重新查一次去年今日」——只是频率是**每次加载 1 次**，不是每秒 60 次。定级应从「P2 每秒 60 次全量扫描」下调为 **P3「每次 rebuild 多一次全表查询」**。

5. 🔎 **附加发现（已查完，反而进一步否定了该条）**：`:656` 的 `TweenAnimationBuilder<double>` **确实**是真正的「每帧重跑 builder」类型，但它的作用域**只包住一个 40×40 的日期圆圈**（`:662-663` `Transform.scale`），位于 `_buildStreakCard()`（`:523`）内部 —— 与 `_buildLastYearTodayCard()`（`:1250`，由 `build():291` 调用）是**两棵完全不相交的子树**。
   **所以「锚点应为 `:656`」这个可能的辩解也不成立** —— `:656` 的逐帧重建根本碰不到去年今日卡。原断言的机制在任何行号下都站不住。

**结论：A6 不成立。** 报告 `heavy-features.md:657` 这条（含「每秒 60 次全量扫描」的定量结论与「应 `late final`」的因果关系）应整条降级为 **P3「每次数据加载完成后多一次全表查询」**，并把定量表述删掉。改法（`late final Future`）本身仍是对的、可以保留。

> 备注：这是**同一审计员第二次**犯「把 `AnimatedBuilder`/动画驱动的局部重建误当成整棵 widget 树每帧 rebuild」的错（A5 一次、A6 一次）。建议在汇总里提示该报告其余凡含「动画期间每帧」的断言都需按此模式复验一遍（同一文件 `:657` 之外还有 `:657`/`:664`/`:693`/`:804` 附近的若干条）。

---

## C1｜附加抽验：`ui-render.md` 的 P0-2（特殊主题全屏每帧重绘）—— **成立**

`ui-render.md` 不在原定抽样清单内，但因为它与 A5/A6 属同一类「动画重建范围」断言，且是全报告最高的 P0，我抽验了其核心机制。

**报告断言**（`ui-render.md:74-78`）：特殊主题下 `AnimatedBuilder` 每帧 rebuild `CustomPaint`，而 `CustomPaint` 的 `child` = 整棵 `PageView` 页面树，同属一个绘制层 → 背景脏则整页重绘；且业务代码 `RepaintBoundary` 用量为 0。

**核对：**

1. ✅ **`CustomPaint` 的 child 确实是整棵页面树**：`theme_backgrounds.dart:396-404`
   ```dart
   396: return CustomPaint(
   397:   painter: SakuraPainter(petals: ..., progress: _controller.value),
   403:   child: widget.child,        // ← 传入的 child = 整棵 MainScreen 内容
   404: );
   ```
   而 `main_screen.dart:615-622` `ThemeBackgroundFactory.wrap(themeName: ..., child: PageView(...))` → **确认 `widget.child` 就是 PageView 整棵树**。

2. ✅ **「`AnimatedBuilder` 每帧 rebuild `CustomPaint`」表述准确**（这点比 `heavy-features.md` 严谨）：`theme_backgrounds.dart:57` `_controller = AnimationController(...)..repeat()`，其 `build` 用 `AnimatedBuilder` 包住上述 `CustomPaint`，所以 **painter 的入参（`petals`/`progress`）每帧变化 → 必须 markNeedsPaint**。这是**真实**的每帧路径，不是误判。

3. ✅ **「`RepaintBoundary` 用量为 0」基本精确**（我实测有 9 处，但全部是死代码）：
   - `lib/utils/performance_optimizations.dart` 内 8 处（`:126, 467, 471, 480, 514, 519, 525, 526`）——**该文件全仓库无任何 import**（我 grep `import.*performance_optimizations` 命中 0），整文件是死代码；
   - `lib/utils/utils.dart:39` 只是把 `RepaintBoundaryWrapper` **再导出**，唯一 import 它的 `profile_screen.dart:24` 内**零次使用**（grep `RepaintBoundaryWrapper|RepaintBoundary` 在 profile_screen 中命中 0）。
   → **业务渲染路径上确实一个 `RepaintBoundary` 都没用**。报告结论成立；措辞「用量为 0」在「有效用量」意义上准确，若要吹毛求疵可写成「有效用量 0（9 处全在死代码里）」。

4. ⚠️ **唯一需要留白的部分**：报告 `:77` 对「`PageView` 内部 `Viewport` 是 `isRepaintBoundary => true`，这一层挡住了滚动内容但挡不住页面整体重绘」的表述**逻辑上自洽但我未逐行核实 Flutter 框架源码**（`viewport.dart:604` 那一行我没打开核对）。这条属于**机制细节的精度问题，不影响 P0 定性**——无论 Viewport 是否挡，背景层自身 60fps 满屏 fill 的开销是确定的（樱花主题 25 瓣 + 5 花瓣绘制 + 2 朵花，见 `:67` 与 `:525`）。

**结论：C1 成立。** 且这条与 A5/A6 形成对照 —— **同一个「每帧」词，`ui-render.md` 用得对（真有 `repeat()` 控制器驱动整屏 painter），`heavy-features.md:657` 用得错（无控制器驱动 build）**。说明问题在具体断言而非报告整体。

---

## B6｜`addDiary` → `loadRecentDiaries` → `_saveDiaries()` 全量重加密 因果链 —— **成立（`data-layer.md` 落盘后已文本比对，其表述准确，无需更正）**

> **更新（13:05）**：`data-layer.md` 已落盘，我做了文本比对。**结论从「部分成立」改为「成立」** —— 该报告并没有犯「`loadRecentDiaries` 触发写盘」这个错，是我最初按 Lead 的转述措辞去验证、而 Lead 的转述并不等于该报告原文。报告原文（`:19`、`:49-60`）表述是准确的。

**报告原文核对（`data-layer.md:19` 与 `:49-60`）：**

1. ✅ `:19` 写的是「`addDiary():207-229` 后 `loadRecentDiaries((page+1)*20)`」—— 只陈述了**调用关系**，**没有**声称 `loadRecentDiaries` 触发 `_saveDiaries`。准确。

2. ✅ `:49-60` 的写放大链条图（我逐行核对，**完全正确且比我的独立分析更完整**）：
   ```
   2 + len(tagIds) 次同步 commit()
     = 1× insertDiary → _saveDiaries（全量 N 篇重加密+全量 setString）
     + 1× insertDiaryTagsV3 → _saveDiaryTagsV3（全量 setString）
     + len(tagIds)× TagSystemService.incrementTagUsage → recordTagUsage
             → _saveTagSystem（每次把整个 tagSystem JSON 全量重写）
     + 1× Provider.loadRecentDiaries → 又一次全量 sort 拷贝（纯 CPU，落盘之外）
   ```
   - **与我独立得出的 `2 + len(tagIds)` 公式一致**；
   - **并且它明确标注了 `loadRecentDiaries` 是「纯 CPU，落盘之外」** —— 精准，甚至超过我最初的判断（我起初只确认它「不写盘」）；
   - `:60` 进一步量化「带 3 个标签 = 5 次主线程同步 fsync；N=1000 时约 5×80ms=400ms 光落盘，再加 2 次全库加密 + 2 次 jsonEncode」。

3. ✅ **它连我在 B6 第 4 点要提的「`isEncrypted` 短路对内存明文不生效」也自己写对了**：`:14` 明确写「`_saveDiaries():270-280` = `Future.wait(全部 N 篇重新 AES 加密)`」，`:71` 表格里「全量 N 篇重新 AES 加密」。没有误以为有短路优化。

4. ✅ **额外发现它补了我没抓到的一条**：`:14` 与 `:71` 指出 `_updateMetadata():331-339` 是**第二次全量 `setString`** —— 我原分析里只把它记为「再写一坨 JSON」，没计入「全量 setString 次数」，报告把它算成 2 次是正确的（`_saveDiaries` 的 `setString(_diariesKey)` + `_updateMetadata` 的 `setString(_metadataKey)`）。
   → 所以更准确的公式应是 **`2 + len(tagIds)`**（报告口径）而非我最初写的「2 + len」，两者一致；但**若按"全量 JSON 写"计，`_updateMetadata` 也 fold 一遍全量算字数**，这部分 CPU 成本报告也算进去了。

**结论：B6 成立。`data-layer.md` 在这一条上无误，**无需更正。** 我此前 crosscheck 的「部分成立」判断，是因为 Lead 转述的措辞（"loadRecentDiaries 由 addDiary 触发，进而 _saveDiaries() 全量重加密"）暗示了错误的因果，而报告本身没有这么写 —— **是转述失真的问题，不是报告的问题**。

**给 Lead 的提示：** 你在汇总时若引用了「`loadRecentDiaries` 触发全量重加密」，请改为引用报告原文的准确表述 —— **`insertDiary` 触发 `_saveDiaries`，`loadRecentDiaries` 只是额外的全量排序（CPU）**。



---

## B7｜`data-layer.md` 的「索引设计」覆盖度 —— **成立（覆盖完整且有超额项），但有 3 处行号/计数错误需更正**

> **更新（13:05）**：`data-layer.md` 已落盘，现做真实文本比对。B.1 的索引清单我逐条核对，**覆盖面完整，两个我预判的易漏点它也处理对了，还多给了 3 项我未列的优化**。问题只在少量行号/计数精度。

### B7-1：我预判的两个「易漏点」—— 报告**都处理对了** ✅

| 我预判的坑 | 报告实际写法 | 判定 |
|---|---|---|
| 误以为「加索引可优化 `getDiariesPaged`」 | `:79` 明确写「`SELECT ... ORDER BY date DESC LIMIT ? OFFSET ?` + `idx_diaries_date`」，并给出「分页变成索引区间扫描，O(pageSize)」 | ✅ **正确，没有只说加索引** |
| 误建议「给 content 加普通索引」 | `:93-99` 单列 B.3「"加密"与"索引/搜索"的结构性冲突」，明确写「content/title 在库里是可逆加密字符串，**SQL 无法 LIKE**」，并给出 A/B/C 三条路径（推荐 A：后台 isolate 分批解密 + 300ms 防抖 + 最少 2 字），**明确否掉 B（明文 FTS4）** | ✅ **完全正确** |

报告甚至比我的基线更进一步：`:97` 指出搜索要在**后台 isolate** 做（我基线只写了"FTS5 或内存过滤"，没强调 isolate 隔离）。这条更优。

### B7-2：我基线里的 7 项最小索引集 —— 报告覆盖了 6 项，另超额 3 项 ✅

| 我的基线项 | 报告是否覆盖 | 位置 |
|---|---|---|
| ① `diaries(date)` （5 API 共享，最大收益） | ✅ 覆盖，且给出了 `DESC` 方向与复合 `(date DESC, created_at DESC)` | `:76`, `:77`, `:78` |
| ② `diary_tags(diary_id)` + `(tag_id)` | ✅ 覆盖，且用复合索引 `(diary_id, tag_id)` 更优 | `:81` |
| ③ `diary_tags_v3(diary_id)` + `(tag_id)` | ✅ 覆盖，并特别提示「native `_onCreate` 里完全没有 `diary_tags_v3` 的任何索引」 | `:82` |
| ④ `self_talk_messages(date, created_at)` | ⚠ **未明确列出**（B.1 表里没有 self_talk 相关行） | — |
| ⑤ `self_talk_tasks(date, created_at)` / `(message_id)` | ⚠ **未明确列出** | — |
| ⑥ `anniversaries(date)` | ⚠ 未列出 | — |
| ⑦ `diaries(mood_id)` | ✅ 覆盖（`idx_diaries_mood`） | `:83` |
| **报告超额项** | ⑧ `diaries(word_count DESC)` + **材料化 `word_count` 列**（`:85`，称"最大的单点优化"）；⑨ `diaries(is_favorite) WHERE is_favorite=1` 部分索引（`:84`）；⑩ 收藏列表、统计字数 | `:84-86` |

**结论**：报告的索引设计**优于**我的基线（材料化 `word_count` 列这条尤其有价值 —— 它把"每次统计都要解密全部正文"变成"读一个整数列"）。**唯一缺口是 `self_talk_*` 三张表的 date/message_id 索引未列**，但考虑到自言自语是独立库且调用次数各 1，属低优先级，**不构成"未覆盖高频查询"**。

### B7-3：需要更正的行号/计数错误（3 处，均为精度问题不影响结论）

| # | 报告原文 | 实际 | 影响 |
|---|---|---|---|
| 1 | `:77` `getDiariesByDate` 写「**3 处**（`calendar_screen:421,713,1437,1770`、`stats:1449`）」 | **口径混淆**：`calendar_screen:421,713,1437,1770` 这 4 处调的是 **`DiaryProvider.getDiariesByDate`（内存 `where`，`diary_provider.dart:39-41`）**，**不是** `DatabaseService.getDiariesByDate`。真正的 DB 层调用只有 **3 处**：`stats_screen.dart:1449`、`goal_service.dart:256`、`goal_service.dart:307` | ⚠ 行号全错，但**「3 处」这个数字碰巧对**。会把读者引去读错文件。**建议改为**：`stats_screen:1449`、`goal_service:256,307`（3 处） |
| 2 | `:82` `getDiariesByTagIdV3` 写「2 处（`tag_diaries_screen:49`、`tag_system_service:317`）」 | 实际 `DatabaseService.getDiariesByTagIdV3` 调用点在 `tag_diaries_screen.dart:52`（非 49）；`tag_system_service:317` 调的是 **`getDiariesByTagId`（非 V3）** | 轻微，行号/方法名小误 |
| 3 | `:77` 同一行里混用了 `provider.getDiariesByDate` 与 `DatabaseService.getDiariesByDate` 两个不同方法 | 二者语义不同：前者是**内存列表过滤 O(N)**，后者是**存储层查询**；对索引设计的意义完全不同（前者加索引无效） | 概念性混淆，**在讨论索引时这是要区分的** |

### B7-4：一处需要提醒报告注意的 schema 事实（我核对了 native 源码）

报告 `:90` 写「`_onCreate`（`native:58-132`）**只有主键索引**，没有一条业务索引」—— **成立**。我 grep `lib/services/database_service_native.dart`：
- `CREATE INDEX` 命中 **0**；
- `CREATE TABLE ... PRIMARY KEY AUTOINCREMENT` 共 22 处（含 `_onUpgrade` 里的建表）。
→ 报告 B.2 第 1 条硬伤准确。**这也印证：「切回 SQLite」本身不解决卡顿，必须同时建索引**（报告 `:90-91` 与 `C.5` 都强调了这点，正确）。

**B7 结论：成立（覆盖面完整且优于基线）。需更正 3 处行号/计数精度问题（尤其 `:77` 把 Provider 内存方法与 DB 方法混为一谈），以及可补 `self_talk_*` 三表索引（低优先）。**

---

## C2｜（第 3 轮）heavy-perf 自查第三处同类错误后的修复验证 —— **成立（4 条断言全部核实无误）**

背景：我在 A6 更正里给它定了一条判据（`AnimatedBuilder` 只重建 builder 子树；判定前先 `grep addListener`）。它据此**自查出并修正了第三处同类错误**，并把判据沉淀成报告固定条款。我逐条验证它的新表述。

### C2-1 ✅ `profile_screen` 的「每帧重建」→「每次 setState 重建」：**修正正确**

我实测 `lib/screens/profile_screen.dart`：

| 原语 | 命中数 |
|---|---|
| `addListener` | **0** |
| `TweenAnimationBuilder` | **0** |
| `AnimatedBuilder` | **0** |
| `AnimationController` | **0** |
| `AnimatedContainer` | 1（隐式动画，`didUpdateWidget` 才启动，空闲不耗帧） |

→ **该文件没有任何动画驱动**，不存在「每帧重建」。它改为「每次 `setState` 全部重建」正确。
且它给的驱动原因也对：`initState`（`:58`）里 4 个并发服务回调各带 `setState` —— `:70`（`_loadBadges`）、`:83`（`_loadAppLockStatus`）、`:93`（`_loadBiometricStatus`）、`:103`（`_loadFloatingWindowStatus`）。**确实 4 次**。

### C2-2 ✅ `emotion_stats_screen:527` 的「每帧」→「每次 setState/rebuild」：**修正正确**

我实测 `lib/screens/emotion_stats_screen.dart`：`addListener` / `TweenAnimationBuilder` / `AnimatedBuilder` / `AnimationController` **全为 0**。
→ 无动画驱动，`_buildKeywordsCloud`（`:527-540`，对全部日记跑 `SentimentAnalysisService.analyze`）确实只在 `setState` 时重算，不是每帧。

🔎 **它顺手还多报了一条我未想到的事实（已核实成立）**：该报告 `:662` 指出「v1 版 `emotion_stats_screen.dart` **已无任何文件 import**（`stats_screen.dart:12` 引的是 `emotion_stats_screen_v2.dart`），是死代码」。这条很有价值 —— 意味着这条 P2 优化本身可以不做，直接删文件即可。

### C2-3 ✅ 判据沉淀条款：**准确，且主动防止了判据被误用**

它把判据写进了 `heavy-features.md:657-659`，原文核心：
> `AnimatedBuilder` / `TweenAnimationBuilder` **只重建其 `builder` 子树，不会让外层 `build()` 重跑**；`SlideTransition`/`FadeTransition` 走 RenderObject 更新 transform/opacity，也**不触发 widget rebuild**。因此「每帧 rebuild」只有在 **(a) 该文件有 `addListener` + `setState`**，或 **(b) 目标子树确实被动画 widget 包住** 时才成立。

**这段表述与我给出的判据一致，无失真。**

**更重要的是 —— 它主动加了一条防止「判据反向误用」的说明**（`:597-600`，P2-1 特殊主题处）：
> `theme_backgrounds.dart` 的 `addListener` 命中数 = **0** —— 但它**不需要** `addListener` 来达成每帧重绘，因为 `AnimatedBuilder` 内部会订阅 `Listenable` 并每帧重跑 builder。**没有 addListener ≠ 不会每帧重建**。

这条很关键。我给判据时只强调了 (a) `addListener`，若被机械执行，**会把真正成立的 P2-1（特殊主题每帧重绘）误杀**。它自己识别出了这个陷阱并写进正文，**这是超出我提醒范围的正确动作**。

我实测印证它的说法：`theme_backgrounds.dart` `addListener`=0，但 `AnimatedBuilder`=5、`AnimationController`=14、`..repeat()`=7 → **走的是判据 (b)**，P2-1 成立。与其说法完全吻合。

### C2-4 ✅ 「4 屏 `addListener` 全 = 0」的实测数据：**准确**

它声称「`stats_screen` / `gacha_screen` / `profile_screen` / `emotion_stats_screen` 的 `addListener` 全部为 0」。我独立复跑，四个文件**均为 0**，一致。

### C2-5 ✅ 顶部声明：**已落盘**

`heavy-features.md:3` 已写 `> 已按 crosscheck 更正 A1/A5/A6（见 .perf-analysis/crosscheck.md）。`

**C2 结论：成立。** 它这轮的修复**没有引入新错误**，且两点超出预期：① 自查出第三处同类错误（我原本未抽到 P1-4 profile 段）；② 主动补了「判据不可机械套用」的防误用说明。**判据沉淀这一动作本身值得作为团队基线保留。**

---

## B 部分状态

`data-layer.md` 已于 **13:05:07** 落盘（24546 B / 263 行），本次复核已完成**真实文本比对**（不再是独立验证）。

- **B6：成立**，报告表述准确，**无需更正**（我此前「部分成立」的判断源于 Lead 转述失真，非报告问题）。
- **B7：成立**，索引设计覆盖完整、优于我的独立基线；仅 3 处行号/计数精度问题 + `self_talk_*` 索引缺口（低优先）。
- 另有独立基线 `data-layer-baseline.md`（我按自有 67-API 普查反推），现作为**对照物**保留，两者可互证。

---

## 复核方法说明与局限

- **取证方式**：全部为静态源码阅读（`read`/grep），未运行 flutter/dart 工具链、未改任何源码、未改任何被复核报告。
- **已复核 10 条**：A1–A6（`heavy-features.md`）+ C1（附加抽验 `ui-render.md`）+ B6、B7（`data-layer.md`，13:05 落盘后做文本比对）+ C2（第 3 轮：heavy-perf 自查修复验证）。
- **第 3 轮（C2）补记**：heavy-perf 收到 A6 更正后自查出**第三处同类错误**（P1-4 profile 段「每帧重建」——我原本未抽到该段），并修正；我验证其 4 条新断言全部成立。它另外做了两件超出我提醒范围的事，值得记录：
  - 在报告正文写入了「**没有 `addListener` ≠ 不会每帧重建**」的防误用说明 —— 这条很关键。我给的判据以 `addListener` 为 (a) 条件，若被机械执行会**误杀真正成立的 P2-1**（`theme_backgrounds.dart` `addListener`=0，但走判据 (b) `AnimatedBuilder` 包住整棵树，每帧重绘确实成立）。它识别并堵住了这个陷阱。
  - 顺手查出 `emotion_stats_screen.dart`（v1）**已无任何文件 import、是死代码**（`stats_screen.dart:12` 引的是 `_v2.dart`）→ 该条优化可直接改为「删文件」。
- **两条初判被本人修正（记录在案，避免误导）**：
  - **B6** 初判「部分成立」→ **终判「成立」**。原因：我最初按 Lead 的转述措辞验证因果链，而 `data-layer.md` 原文并未声称「`loadRecentDiaries` 触发写盘」—— 是**转述失真**，不是报告错误。
  - **B7** 初判「无法完整评估」→ **终判「成立」**。原因：报告在 13:05 落盘，其索引设计**优于**我的独立基线（多给材料化 `word_count` 列等 3 项）。
- **「每帧」类断言是本轮最容易出错的点**：`AnimatedBuilder`/`TweenAnimationBuilder` 只重建其 builder 子树，**不会**让外层 `build()` 重跑；只有当 `addListener`+`setState` 或整棵树被动画包住时才会。判定任一「每帧 rebuild」断言前必须先 grep 该文件的 `addListener`。**本轮 A5、A6 两条错误全部出自这一判据缺失**（A6 已发更正给 heavy-perf）。
- **报告可信度分层结论（供 Lead 汇总参考）**：
  - `data-layer.md`：**事实密度高，行号基本可用**（仅 3 处精度问题，且多为「方法名相近」导致的引用混淆）；量化模型（A.1/A.2 的 N=200/1000/5000 表）是四份报告中**最有决策价值**的部分。
  - `ui-render.md`：**机制描述最严谨**（「每帧」用词经核实全部正确），引用 Flutter 框架源码（`viewport.dart:604`、`proxy_box.dart:896-898`）这一做法应提倡。
  - `heavy-features.md`：结论方向多数成立，但**机制层有系统性偏差**（把 `AnimatedBuilder` 局部重建误判为整树每帧 rebuild，已犯 2 次：A5、A6）；其内存量级估算偏保守（A4 实际比报告更严重）或偏高（A1 字体双份高估 1 倍）。
- **未做真机验证**：所有「每秒 60 次」「掉帧」「内存峰值」类量化结论均为静态推算，报告与复核双方都应视为待 `--profile` 实测确认。
- **A4 的 4.7× 峰值**基于「`Isolate.spawn` 对普通 `Archive` 对象做深拷贝」这一 Dart 语义推定；若该 isolate 实际走了 `TransferableTypedData` 优化则峰值会下降（当前代码未见该优化，可视为不成立）。

---

*复核时间：2026-10-28 · 只读核对，未修改被复核报告*
