# P1 重功能页性能审计（统计 / 搜索 / 抽卡 / 徽章 / PDF / 云同步）

> 已按 crosscheck 更正 A1/A5/A6（见 `.perf-analysis/crosscheck.md`）。

> 审计范围：`lib/screens/stats_screen.dart`(51KB)、`stats_detail_screen.dart`(44KB)、`emotion_stats_screen(_v2).dart`、`profile_screen.dart`(111KB)、`gacha_screen.dart`(80KB)、`diary_search(_enhanced)_screen.dart`、`data_management_screen.dart`、`backup_manager_screen.dart` + `lib/services/gacha_service.dart`(85KB)、`badge_service.dart`(99KB)、`pdf_export_service.dart`、`cloud_sync_service.dart`(67KB)、`backup_export_service.dart`、`incremental_sync_service.dart`、`auto_backup_service.dart`、`text_analysis_service.dart`、`sentiment_analysis_service.dart`、`image_cache_service.dart`、`theme_backgrounds.dart`。
>
> 方法：只读静态审计（file:line 证据）。未运行 flutter/dart 工具链、未修改任何源码。
>
> **关键前置事实（决定了全部量级估算）**：`lib/services/database_service.dart` 全文只有 3 行 —— `export 'database_service_web.dart';`。也就是说 **Android 上跑的存储层是 SharedPreferences + 全量 JSON 内存列表**，`database_service_native.dart`（sqflite，40KB）**没有任何文件 import，是死代码**（`grep "database_service_native"` 只命中注释）。因此本项目里每一个"数据库查询"实际都是：
> 1. `await _ensureInitialized()`（首次会把**全部日记从 JSON 解出并逐条 AES 解密**，`database_service_web.dart:235-267`）；
> 2. 对内存 `_diaries` 做 `List.from(...)..sort(...)` 或线性 `where`；
> 3. 返回**新的 List 副本**（每次调用都复制引用数组）。
>
> 所以本报告里所有 `getAllDiaries()` / `getTagsByDiaryId()` 的真实成本是 **O(N log N) 排序 + O(N) 拷贝**，不是 SQL 索引查询。这是所有统计页/搜索页/徽章页慢的共同乘数。

---

## 0. 概览（按严重度排序）

| ID | 严重度 | 区域 | 一句话 | 主要证据 |
|---|---|---|---|---|
| P0-1 | **P0 闪退** | PDF 导出 | 每张图 `readAsBytes` **原图整张**进 `pw.MemoryImage`、不缩放；`exportSingleDiary` **无张数上限**；加上 23.97MB 字体**一份**的解析 → 主 isolate 峰值轻松 200MB+ | `pdf_export_service.dart:356,507`（图片）;`:98,100`（字体，仅 1 份） |
| P0-2 | **P0 卡死** | 统计页 | `initState→_loadStats` 里 `for (diary in diaries) await getTagsByDiaryId(...)` = N+1，且每次调用都 `List.from(_diaryTags)` 线性扫描 → 千篇日记 ≈ 千次全表扫描 | `stats_screen.dart:147-152` |
| P0-3 | **P0 卡死** | 增强搜索 | **每敲一个字符**都 `getAllDiaries()`(全量解密+排序) ×3 次 `toLowerCase()` 全量文本 + `sort`，无防抖 | `diary_search_enhanced_screen.dart:73-129, 412-415` |
| P0-4 | **P0 卡顿** | 云同步图片 | `_createEncryptedImageArchive` 把所有图片字节**同时堆进一个 `Archive`**，峰值 = 全部图片字节之和；Isolate 只分摊了 read 与 zip 编码，字节本身一直在主 isolate 堆里 | `cloud_sync_service.dart:1138-1214` |
| P0-5 | **P0 卡死** | 徽章/里程碑 | 写日记保存后**串行跑 8 组徽章检查**，每组都遍历全部 79 个 Badge，且每次 `unlockBadge` 都 `SharedPreferences.getInstance()` + 每篇日记 `wordCount` 内联编译 RegExp | `write_diary_screen.dart:792-854`，`badge_service.dart:2184-2186`，`diary.dart:108-121` |
| P0-6 | **P0 闪退/卡死** | 存储层 | **每写/改一篇日记 = 对全部 N 篇重跑 AES 加密 + 全量 `jsonEncode` + 全量 `setString` 写盘**（Android SharedPreferences 全文件重写+fsync）；启动时还要一次性解析+解密全量 JSON | `database_service_web.dart:270-280, 235-267, 329-339`；`diary_provider.dart:222` |
| P1-1 | P1 卡顿 | 统计页 | **每次切到"统计"tab 都会重新 `initState → _loadStats()`**（`PageView` 未设 `allowImplicitScrolling`、四个 tab 页也都没用 `AutomaticKeepAliveClientMixin` → 离屏即 dispose）→ 每次重新全量重算，且**每次都把 P0-2 的 N+1 再跑一遍** | `main_screen.dart:617-621, 89-94`；`stats_screen.dart:50-53, 95-174` |
| P1-2 | P1 卡顿 | 情绪页 | `SentimentAnalysisService.analyzeDiaries` 对每篇日记做 55+66 个 `contains` × 23 个修饰词 double loop，情绪页再加 `days×diaries` 的 O(7N)+O(30N) 重扫 | `sentiment_analysis_service.dart:131-306`，`emotion_stats_screen.dart:69-140` |
| P1-3 | P1 卡顿 | 统计详情 | 进页即 `TextAnalysisService.getTopIdioms`：797 个成语 × N 篇 `contains`，再加 `extractMoodSnippets` 里 `content.split(RegExp(...))` **每篇编译一次 RegExp** | `stats_detail_screen.dart:47-81`，`text_analysis_service.dart:178-184, 328` |
| P1-4 | P1 卡顿 | profile | 首屏 `SingleChildScrollView` 一次性 build 15 个 `_MenuItem` + 9 组卡片 + 徽章区（无懒加载）；`initState` 4 个并发服务调用各自 `setState` → 4 次 111KB 整页 rebuild | `profile_screen.dart:58-107, 208-425` |
| P1-5 | P1 卡顿 | 搜索（简版） | `provider.diaries` 里当前只有**前 20 篇**（分页），却当作"全部日记"搜；`onChanged` 里 `Future.delayed(300ms)` 假防抖（不 cancel 旧 timer），`setState` 清空前仍会触发 `build` | `diary_search_screen.dart:52-74, 215-223`；`diary_provider.dart:25,80-94` |
| P2-1 | P2 抖动 | 全局 | 特殊主题（星空/樱花/海洋/极光/黄金）每帧 80 星/25 花瓣/15 气泡 + `shouldRepaint => true` 恒真，`CustomPaint` 包裹**整棵页面树**，每帧全页重绘 | `theme_backgrounds.dart:398,624,1244,1494,1983,2250`；`main_screen.dart:615-623` |
| P2-2 | **P3 轻微** | 抽卡页 | 4 处 `FutureBuilder(future: ...)` 内联建 future，**其中仅 `gacha_screen.dart:248` 真正在首屏 build 路径**（另 3 处在 `showModalBottomSheet` builder 内，是独立 route）；首屏每次 rebuild 会**重新发 Future 并短暂闪空**。动画期间父级 `build()` 不重跑（动画只在 `AnimatedBuilder` 内消费，且 `SharedPreferences.getInstance()` 有 completer 单例、`getInt` 是纯内存查表零 IO） | `gacha_screen.dart:248`（首屏）、`:1193/:1767/:2042`（弹窗内）；`:320-345`（AnimatedBuilder）；`:79/:100/:114/:126`（仅 4 次 setState） |
| P2-3 | P2 卡顿 | 抽卡 | `GachaService.getHistory()` 对最多 20 条 JSON 逐条 `_allRewards.firstWhere`（97 条）线性查找 | `gacha_service.dart:1558-1596` |
| P2-4 | P2 | 备份 | `.mbk` 导出/导入整个 JSON 在内存里 `jsonEncode`→`utf8.encode`→AES→`ZipEncoder`，**全程主 isolate**，无进度回调 | `backup_export_service.dart:40-93, 104-136` |
| P2-5 | P2 | 自动备份 | 启动即触发 `performBackup`：`getAllDiaries()+getAllMoods()+getAllTags()` 全量 → `jsonEncode` 一个大字符串 | `main.dart:62`，`auto_backup_service.dart:64-114` |
| P2-7 | **P1 实际影响** | 图片展示 | 全屏看大图走 `OriginalImage` → `Image.file` **无 `cacheWidth`**，4000×3000 原图解码 48MB；`PlatformImage` 的 `cacheWidth/cacheHeight` 声明了却**从未往下传**（死参数），且每个图片 widget build 期都发一次 `File.exists()` Future | `image_cache_service.dart:536-543, 629-634`；`platform_helpers.dart:21-22, 50-71, 63-69` |

---

## P0-1｜PDF 导出：原图整张进内存（不缩放、单篇无上限）——闪退首选嫌疑

> ⚠️ **crosscheck A1 更正**：本条原先的「字体被解析两次 → 峰值 90~130MB」**因果不成立**，已剔除。真实机制是**图片**。字体部分降级为 P3-1 死代码清理（见本节末尾）。

### 位置
- 字体资产：`assets/fonts/NotoSerifCJKsc-VF.ttf` = **24,540.2 KB = 23.97 MB**（实测；`pubspec.yaml:65` 打包，`pubspec.yaml` 无 `fonts:` 段，只作为 asset 给 `pw.Font.ttf` 用）。
- `lib/services/pdf_export_service.dart`
  - `_loadChineseFont()`：第 **98** 行 `rootBundle.load(...)` → 第 **100** 行 `pw.Font.ttf(fontData)`。**这是导出路径上唯一真正加载字体处**（`exportDiaries:280`、`exportSingleDiary:483` 都直接调它）。
  - `_loadChineseBoldFont()`：第 **187** 行 → 第 **190** 行。**其唯一调用点是 `preloadFonts()`（`:31`），而 `preloadFonts()` 全仓库无任何调用者** → **该 24MB 在实际导出路径上从未被解析**（crosscheck A1）。它是**死代码**，见 P3-1。
  - **`exportDiaries()` 图片**：第 **352-357** 行 `for (final imagePath in diary.imageList.take(4)) { final bytes = await file.readAsBytes(); final image = pw.MemoryImage(bytes); }`
  - **`exportSingleDiary()` 图片**：第 **503-508** 行 `for (final imagePath in diary.imageList)`（**无 take 限制**）同样 `readAsBytes` → `pw.MemoryImage(bytes)`。
- 调用点：`data_management_screen.dart:1171-1182` `_exportPdf()`，**在 UI 线程直接 await**，无 loading 遮罩、无 isolate、无 `compute`。

### 现象
用户点"导出 PDF"→ 进度环卡死数秒到数十秒 → 全部日记越多越久 → 图片多时闪退（部分机型直接 `OutOfMemoryError`，Flutter 侧表现为白屏/`Lost connection to device`）。

### 机制
1. **字体（仅 1 份，不是峰值主因）**：`pw.Font.ttf(ByteData)` 会把整个 TTF 交给 pdf 包做 glyph 表解析。23.97MB 单份解析后常驻 ≈ **36~60MB**（按 1.5~2.5× 估）。**粗体那份在真实路径上不加载，不计入。**
2. **图片不缩放（真正的峰值来源）**：`pw.MemoryImage(bytes)` 直接把**相机原图**交给 PDF 引擎。3000×4000 JPEG 常见 3~8MB → 解码后 RGBA 12M 像素 × 4B ≈ **48MB/张**。
   - `exportDiaries` 每篇最多 4 张（`take(4)`）；
   - `exportSingleDiary` **不限张数**（单篇上限 20 张，见 `write_diary_screen.dart:101`/`:1969` 的 `_maxImageCount`）→ 单篇 20 张 × 48MB ≈ **960MB 直接爆**。
3. **全量日记一次性 addPage**：第 347 行 `for (final diary in diaries)` 在**同一个** `pw.Document` 里 `addPage` N 次，`pdf.save()`（第 465 行）要在内存里序列化**整本 PDF**（含内嵌字体子集 + 所有图片）。**峰值 ≈ 字体(1份) + 全部图片字节 + 输出 PDF 字节**。

### 内存与耗时量级（以 1000 篇日记、平均 1.5 张 4MB 图为假设场景）
- 字体：**1 × 24MB(原始) + 1 × 解析结构 ~36MB ≈ 36~60MB**（原报告「90~130MB」已更正）
- 图片字节：`readAsBytes` 是全量串行读、但 `pw.MemoryImage` 持有的 `bytes` **不会释放**（每张图的 `MemoryImage` 挂在 `imageWidgets` 里直到整本 save 完）→ 1000×1.5×4MB ≈ **6GB 理论**，实际受 `take(4)` 与去重影响也会是**数百 MB** → **必 OOM**。**这才是 P0 的支撑点。**
- 单篇导出（`exportSingleDiary`，20 张图）≈ **960MB 图片 + 60MB 字体** → **单篇就能崩**，这是最容易复现的闪退场景。
- 1000 篇、每篇平均 800 字、`pw.Text` 逐字排版 + 中日韩字形查找：**数十秒到分钟级** UI 冻结（主 isolate 100% 占用，`SnackBar` 都弹不出来）。

### 改法（含代码片段）
**(a) 图片先缩到 ~1200px 再进 `MemoryImage`（用 image 包 + isolate）—— 这是唯一真正省内存的项**
```dart
// 新增顶层函数，配合 compute 在 isolate 里跑
Uint8List _shrinkForPdf(_ShrinkArg a) {
  final decoded = img.decodeImage(a.bytes);
  if (decoded == null) return a.bytes;
  final resized = img.copyResize(decoded,
      width: a.maxWidth, height: a.maxWidth, interpolation: img.Interpolation.linear);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
}

// 导出时
for (final imagePath in diary.imageList.take(4)) {
  final file = File(imagePath);
  if (!await file.exists()) continue;
  final raw = await file.readAsBytes();
  final small = await compute(_shrinkForPdf, _ShrinkArg(raw, 1200));  // 1200px 足够 PDF 150dpi
  imageWidgets.add(pw.Image(pw.MemoryImage(small), fit: pw.BoxFit.cover));
}
```
1200px JPEG(质量 82) 典型 **150~300KB/张**，比 4MB 降 **~95%**；且 `compute` 不阻塞 UI。**注意**：`_ShrinkArg` 必须是顶层/静态可发送类型（`Uint8List` + `int` 即可，不要传 `File`）。
**同时**：`exportSingleDiary`（`:503`）必须先加 `take(N)` 上限（建议 `take(4)`）——当前无上限是单篇 OOM 的根因。

**(b) 分批 + 丢掉中间态**
```dart
// 每导出完 k 篇就强制让出事件循环，并只保留当前批的 MemoryImage
for (final diary in diaries) { ... }              // 现有循环
// 改成：先把图片缩略 + 立即 addPage，addPage 后清空 imageWidgets（局部变量天然如此），
// 关键是 pdf.save() 之前不要再持有 raw bytes
```

**(c) 整本 PDF 放到 isolate（推荐但需改造 pdf 包用法或改用"先写文件流"）**
- 最低成本版：`exportDiaries` 里在 `await pdf.save()` 前后加 `await Future.delayed(Duration.zero)` 无效（同步阻塞），必须 `compute`；`pw.Document` 不可发送 → 只能把「日记 List → 图片缩略图字节 → PDF」拆分，或改用 `Printing.sharePdf` 之外的两段式。

### 风险
- `compute` 缩图会让导出稍慢（多一次 JPEG 编解码），但 OOM 换稳定性值得。
- 如果图片是 HEIC/PNG 大图，`img.decodeImage` 可能返回 null → 要 fallback 到原 bytes 并**降级跳过**（不要硬塞原图）。

### 相关：P3-1 死代码清理（非内存优化项）
`_loadChineseBoldFont()`（`pdf_export_service.dart:177-239`）整段 + 其唯一入口 `preloadFonts()`（`:22-43`）**全仓库无任何调用者**（crosscheck A1 已 grep `lib/`、`test/`、`tool/`）。
- **删它不会带来任何运行时收益**（因为它本来就不跑），但应删除以防未来有人接 `preloadFonts()` 时误触发第二次 24MB 解析。
- 完整条目见下文 **§P3-1**（在 P2-9 之后）。

---

## P0-2｜统计页 N+1：每篇日记一次"全表标签扫描"（叠加内存列表线性扫描）

### 位置
`lib/screens/stats_screen.dart`
```dart
146:    // 统计标签分布
147:    for (final diary in diaries) {
148:      final tags = await DatabaseService.getTagsByDiaryId(diary.id!);
149:      for (final tag in tags) {
150:        _tagDistribution[tag.name] = (_tagDistribution[tag.name] ?? 0) + 1;
151:      }
152:    }
```
`lib/services/database_service_web.dart`
```dart
725:  static Future<List<Tag>> getTagsByDiaryId(int diaryId) async {
726:    await _ensureInitialized();
727:    final tagIds = _diaryTags
728:        .where((dt) => dt['diary_id'] == diaryId)      // ← 对全部关联线性扫 N 次
729:        .map((dt) => dt['tag_id'] as int)
730:        .toList();
731:    return _tags.where((t) => t.id != null && tagIds.contains(t.id)).toList();
732:  }                                                    // ← 内层 tagIds.contains 又是 O(k) × O(T)
```

### 现象
统计页从 0.3s 涨到 3~10s；日记越多越慢，且**每次下拉刷新 / 每次切到"统计"tab 都重来一遍**（`initState` 第 53 行 `_loadStats()`，且 `main_screen.dart:617-621` 是 `PageView`，切 tab 不销毁但不重建也不重算 —— 只有首次进入和 `RefreshIndicator` 触发。切 tab 不会重算，这点是好的）。

### 机制与量级
- N 篇日记 × 每次 `getTagsByDiaryId`：`await _ensureInitialized()`（首次很贵，后续 cheap）→ `_diaryTags.where(...)` O(M) 其中 M=全部日记-标签关联数（≈ N × 平均标签数）→ 所以**总 = O(N × M) = O(N² × 平均标签数)**。
- 实测假设：1000 篇、平均 2 标签 → M ≈ 2000；1000 次 × 2000 扫描 = **2,000,000 次 map 比较**，另有 1000 次 `List` 分配 + 1000 次 async 调度（微任务洪泛）。
- 叠加 `getAllDiaries()`（第 98 行）本身已是全量解密 + 排序拷贝，且**这已经是本页第 2 次全量解密**（Provider 已有一份，见 `diary_provider.dart:130-144`）。

### 改法
**一次性把「日记→标签」拉平成循环，而不是 N 次 await**：
```dart
// 1) 拿全部关联（一次）
final allDiaryTags = await DatabaseService.getAllDiaryTags();       // 已是 List<Map>, O(M) 拷贝
final tagIdToName = {
  for (final t in await DatabaseService.getAllTags()) t.id: t.name,
};

// 2) 本地聚合，无 await
final tagDist = <String, int>{};
for (final dt in allDiaryTags) {
  final name = tagIdToName[dt['tag_id']];
  if (name != null) tagDist[name] = (tagDist[name] ?? 0) + 1;
}
```
或更彻底：**不要在这页做这件事**，把 `tagDistribution` 交给一次 `SELECT tag_id, COUNT(*) ... GROUP BY tag_id` 的等价实现（当前存储层语境下就是上面这段）。风险：`_diaryTags` 与 `_tags` 可能不同步（删除标签时关联未清），需要在聚合时容忍 null name（已用 `if (name != null)` 兜住）。

---

## P0-3｜增强版搜索：每敲一个字就"全量解密 + 全量小写 + 排序"，无防抖

### 位置
`lib/screens/diary_search_enhanced_screen.dart`
```dart
 72:  /// 执行搜索
 73:  Future<void> _performSearch() async {
 74:    setState(() => _isSearching = true);
 76:    try {
 77:      final diaries = await DatabaseService.getAllDiaries();   // ← 全量（内存 List.from + sort）
 79:      final results = diaries.where((diary) {
 81:        if (_keyword.isNotEmpty) {
 82:          final titleMatch =
 83:              diary.title?.toLowerCase().contains(_keyword.toLowerCase()) ?? false;
 85:          final contentMatch =
 86:              diary.content?.toLowerCase().contains(_keyword.toLowerCase()) ?? false;
 88:          if (!titleMatch && !contentMatch) return false;
 ...  // 心情筛选里 firstWhere 也对 _moods 线性找
106:          final moodMatch = _selectedMoodIds.any((moodId) {
107:            final mood = _moods.firstWhere((m) => m.id == moodId, orElse: ...);
119:      results.sort((a, b) => b.date.compareTo(a.date));      // ← 又排一次
128:    }
129:  }
...
412:                onChanged: (value) {
413:                  setState(() => _keyword = value);
414:                  _performSearch();          // ★ 每个字符直接触发全量搜索
415:                },
```

### 关键结论：**触发点是 `TextField.onChanged`（第 412-415 行），即每输入一个字符就触发一次 `_performSearch`，没有任何防抖/timer/按钮门槛**。
（措辞更正：`TextEditingController` 本身没有 `onChanged` 成员，这里挂的是 `TextField.onChanged`；不影响结论。）
（同一文件第 401-409 行有清除按钮，点它也会触发；用户按键盘"搜索"键**不会**触发，因为没有 `onSubmitted`。）
另外 `_resetFilters`（132-143，第 141 行）与心情筛选的"完成"按钮（`_selectMoods` 内 `_performSearch()`）也会触发全量搜索。

> 🐞 **重入守卫缺失（正确性 bug，不只是性能）—— crosscheck A3 补充**：
> `_performSearch()`（`:73-129`）**没有 `if (_isSearching) return;` 守卫**，且它在入口 `:74` 和出口 `:122` 各 `setState` 一次。快速输入时会出现「上一个搜索还没跑完、下一个又进来」的**并发重入** → **旧关键词的结果可能后返回、覆盖掉新关键词的结果**（乱序显示）。
> 修法：加请求序号，回来时校验（见下方改法 (a) 的 `_searchSeq`），或在入口直接 `if (_isSearching) return;`（更简单，但会丢输入）——**推荐序号方案**。

> ⚠️ **但请注意可达性**：全项目**没有任何文件 import `diary_search_enhanced_screen.dart`**（grep 零命中），也就是说**这个页面当前是死代码，用户点不到**。真正在用的是 `diary_search_screen.dart`（`calendar_screen.dart:237`、`stats_screen.dart:367`）。
> 因此本条应作为「**若将来接线则必须先修**」的预防性 P0；如果要立即止血，**直接删除该文件**比修它更安全。真正需要修的是下面 P1-5（简版搜索）。

### 机制与量级（1000 篇、每篇 800 字）
- 每次按键：`getAllDiaries()` = 全量 `List<Diary>` 拷贝 + `sort` O(N log N) + `await _ensureInitialized()` → 之后 `where` 里**每篇都新建 2 个 `toLowerCase()` 字符串**（`diary.title`/`diary.content` 各一次，中文 800 字 → 800 char 新串），即 **每次按键分配 ≈ 2 × 800 × 1000 = 1.6M 字符 ≈ 3.2MB 临时字符串**，快速输入 5 个字符 = 16MB 垃圾 → 触发 GC → 掉帧/卡顿。
- 排序再来一次 O(N log N)，`DateTime.parse` 不在这条路径上（好），但 `_moods.firstWhere` 在心情筛选里对每个结果 × 每个选中 mood 重复找。
- 没有 FTS/倒排索引；`contains` 对长正文无法提前剪枝。

### 改法（最小改动优先级排序）
**(a) 真防抖（重建式），并丢弃过期请求**
```dart
Timer? _debounce;
int _searchSeq = 0;
...
@override
void dispose() { _debounce?.cancel(); _searchController.dispose(); super.dispose(); }

onChanged: (v) {
  _keyword = v;                                     // 不要在这里 setState
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 250), () {
    if (mounted) _performSearch();
  });
},
...
Future<void> _performSearch() async {
  final seq = ++_searchSeq;                         // ★ 请求序号，防重入乱序
  setState(() => _isSearching = true);
  final diaries = await DatabaseService.getAllDiaries();
  if (!mounted || seq != _searchSeq) return;         // 过期结果直接丢
  ... // 过滤 + 排序
  if (!mounted || seq != _searchSeq) return;
  setState(() { _searchResults = results; _isSearching = false; });
}
```

**(b) 只做一次 load + 缓存小写文本（真正解决量级）**
```dart
// initState 里加载一次，之后每次搜索只做内存过滤
List<Diary>? _all;
List<String>? _lowerTitle, _lowerContent;

Future<void> _ensureLoaded() async {
  if (_all != null) return;
  final d = await DatabaseService.getAllDiaries();
  _all = d;
  _lowerTitle   = [for (final x in d) (x.title   ?? '').toLowerCase()];
  _lowerContent = [for (final x in d) (x.content ?? '').toLowerCase()];
}
// 搜索：q = _keyword.toLowerCase；for (i...) if (_lowerTitle[i].contains(q) || _lowerContent[i].contains(q))
// 注意：写日记后要 invalidate 缓存（可在 provider notify 时清空）
```

**(c) 数据层上 FTS**（长期）：存储层是 SharedPreferences+JSON 时没有 FTS 可言；若迁回 sqflite，建 `CREATE VIRTUAL TABLE diary_fts USING fts4(title, content)`。**当前架构下这条不可行**，需先修存储层。

### 风险
- 缓存小写文本会让常驻内存 +≈ 1.6M 字符（3MB 级），可在 5 分钟无搜索后释放。
- 若用户数据在搜索页打开期间被改（别的入口写日记），缓存会脏 → 需要在 `DiaryProvider.notifyListeners` 或返回搜索页时 `_all = null`。

---

## P0-4｜云同步图片：所有图片字节同时堆在一个 `Archive` 里（Isolate 只分摊了读盘与 zip）

### 位置
`lib/services/cloud_sync_service.dart`
```dart
1138:  Future<List<int>?> _createEncryptedImageArchive(List<Diary> diaries) async {
1143:      final allImagePaths = <String>{};                 // 全部图片路径
1145:      for (final diary in diaries) { ...addAll(diary.images!.split(',')) }
1160:      const batchSize = 50;
1162:      final archive = Archive();                        // ★ 一个 Archive 装全部
1165:      for (int i = 0; i < allPaths.length; i += batchSize) {
1166:        final batch = allPaths.skip(i).take(batchSize).toList();
1169:        final batchResult = await _processImageBatchInIsolate(batch);  // Isolate 只负责 readAsBytes
1171:        for (final fileData in batchResult) {
1172:          archive.addFile(ArchiveFile(                // ★ 字节从 Isolate 传回主 isolate，挂进 Archive
1173:            fileData['name'] as String,
1174:            (fileData['bytes'] as List<int>).length,
1175:            fileData['bytes'] as List<int>,
1176:          ));
1177:          successCount++;
1178:        }
1181:        await Future.delayed(const Duration(milliseconds: 10));
1182:      }
1192:      final zipBytes = await _encodeInIsolate(archive);  // zip 也在 Isolate，但 archive 在主堆
1200:      final encrypted = await EncryptionService.encryptData(Uint8List.fromList(zipBytes));
```
配套：`_processImageBatchInIsolate`（1217-1236）**每批 spawn 一个新 Isolate**，`_processImageBatch`（1245-1266）用 `readAsBytesSync` 同步读 → 传回的 `result` 是 `List<Map<String, dynamic>>`，**包含原始字节**。

### 现象
"同步图片"期间内存暴涨，几十~几百 MB 图片 → 低端机闪退；进度完全静默（只有 `_debugPrint`），用户以为卡死。

### 机制与量级（crosscheck A4 已加固）
设**总图片原始字节 = S**，zip 后 ≈ **Z ≈ 0.9S**（图片本身已压缩，zip 几乎不省）。同一时刻的**存活物共 5 份**：

| # | 存活物 | 大小 | 位置 | 证据 |
|---|---|---|---|---|
| 1 | `archive` 内全部原始 bytes | **S** | 主 isolate 堆 | `:1162` 建一次、`:1172-1176` 累积、永不释放 |
| 2 | `Isolate.spawn(_encodeIsolate, _EncryptMessage(archive: ...))` 的**深拷贝** | **S** | 编码 isolate 堆 | `:1192` → `:1269-1280`；`Archive` 是普通对象，`spawn` 默认**深拷贝**（非 `TransferableTypedData`） |
| 3 | `zipBytes`（`receivePort.first` 收到） | **Z** | 主 isolate | `:1192`/`:1281` |
| 4 | `Uint8List.fromList(zipBytes)` 拷贝 | **Z** | 主 isolate | `:1200` |
| 5 | `encrypted`（AES-CBC 输出） | **Z** | 主 isolate | `:1200` |

→ **主 isolate 峰值 ≈ S + Z + Z + Z ≈ 3.7S**；加上编码 isolate 的 S → **进程峰值 ≈ 4.7S**。
（原报告写「≈3×」偏保守，已按 A4 上调。）

- 计算：300 张 × 3MB → S ≈ **900MB** → 主 isolate ≈ **3.3GB**、进程 ≈ **4.2GB** → **必 OOM**。
- 「分批」只限制了**每次 Isolate 的峰值**，不限制**主 isolate 累积总量**（`:1165-1182` 每批结果都 `addFile` 进同一个 archive）。
- ⚠️ 另需真机确认：`:1175` 传的是 `fileData['bytes'] as List<int>`；来源是 `readAsBytesSync()`（返 `Uint8List`，侥幸不膨胀），但若 `archive` 包内部发生 `.toList()` 拷贝，每字节 boxed int 会显著膨胀。**此项待 heap snapshot 验证，未断言**（见 appendix V6）。

### 改法（关键：不要把所有字节聚在内存）
```dart
// 方案 A（推荐）：流式写出 zip → 加密 → 上传，逐文件、逐批落盘
Future<String?> _buildEncryptedArchiveToFile(List<String> allPaths) async {
  final tmp = File('${(await getTemporaryDirectory()).path}/img_${DateTime.now().millisecondsSinceEpoch}.zip');
  final sink = tmp.openWrite();            // 但 archive 包 ZipEncoder 不支持流式写出
  // archive 包 3.x 提供 ZipFileEncoder，支持 addFile(name, bytes, ...) 增量写盘：
  final enc = ZipFileEncoder()..create(tmp.path);   // ← 每次 addFile 后内部 flush，不驻留全部
  for (final p in allPaths) {
    final f = File(p);
    if (!await f.exists()) continue;
    final bytes = await f.readAsBytes();   // 单张 ≤3MB，处理完即释放
    enc.addFile(ArchiveFile(path.basename(p), bytes.length, bytes));
    await Future.delayed(Duration.zero);   // 让出
  }
  await enc.close();
  // 然后分块读这个 zip 文件做 AES-CBC 加密并直接 PUT（或直接用 200MB 上限的设备算力评估）
}
```
或者更简单：**分卷**。每卷 ≤ 20MB 的图片包，独立加密上传，恢复时按卷下载解压 → 峰值降到 ~40~60MB（1 卷 + zip + 密文）。

```dart
// 方案 B（改最小）：分批成卷
const maxBytesPerVolume = 20 * 1024 * 1024;
var vol = Archive(); var volSize = 0;
for (final p in allPaths) {
  final f = File(p);
  if (!await f.exists()) continue;
  final bytes = await f.readAsBytes();
  if (volSize + bytes.length > maxBytesPerVolume && vol.files.isNotEmpty) {
    await _uploadOneVolume(vol);            // encode→encrypt→upload
    vol = Archive(); volSize = 0;           // 旧 vol 出作用域 → GC 回收
  }
  vol.addFile(ArchiveFile(path.basename(p), bytes.length, bytes));
  volSize += bytes.length;
}
if (vol.files.isNotEmpty) await _uploadOneVolume(vol);
```

### 风险
- `ZipFileEncoder` 的 API 名在不同 archive 版本有差异（本项目 `archive: ^3.4.10`），落地前先看 `zip_file_encoder.dart` 实际签名。
- 分卷会让"整套图片"变成多个云端文件，恢复逻辑 `_restoreImageArchives`（扫描 `images_*.enc`）必须按卷遍历 —— 该函数已经是按文件名循环的（`_scanImageArchives`），兼容性尚可。
- 流式加密：`encrypt` 包的 AES-CBC 是整块 API，分块加密要做 PKCS7 对齐管理，**建议改成每卷整体加密**（即方案 B），不要真的去流式加密。

---

## P0-5｜写日记保存后：串行 8 组徽章全量检查 + 每次 unlock 都重开 SharedPreferences

### 位置
`lib/screens/write_diary_screen.dart`
```dart
792:  Future<void> _checkMilestoneAfterSave() async {
793:    final provider = context.read<DiaryProvider>();
794:    final diaries = provider.diaries;
797:    final uniqueDates = diaries.map((d) => d.date).toSet();
   ...
804:    final milestone = await MilestoneService.checkMilestone(uniqueDays);
   ...
814:    allNewBadges.addAll(await BadgeService.checkMilestoneBadges(uniqueDays));
817:    allNewBadges.addAll(await BadgeService.checkStreakBadges(diaries));       // 内部 sort + toSet
820:    allNewBadges.addAll(await BadgeService.checkTotalCountBadges(totalCount));
825:    allNewBadges.addAll(await BadgeService.checkContentBadges(_savedDiary!, ...));
832:    allNewBadges.addAll(await BadgeService.checkTimeBadges(DateTime.now()));
835:    allNewBadges.addAll(await BadgeService.checkEmotionBadges(_savedDiary!, allDiaries: diaries));
842:    allNewBadges.addAll(await BadgeService.checkPhotoBadges(diaries));         // 全量照片遍历
845:    allNewBadges.addAll(await BadgeService.checkHiddenBadges(diaries));        // 全量 wordCount
```
`lib/services/badge_service.dart`
```dart
1300:  static Future<bool> unlockBadge(String badgeId) async {
1301:    final prefs = await SharedPreferences.getInstance();    // ★ 每次调用都取一次单例（await）
...
2184:    for (final diary in allDiaries) { totalChars += diary.wordCount; }  // ★ 每篇都跑 RegExp
```
`lib/models/diary.dart`
```dart
107:  // 计算内容字数（排除纪念日文字）
108:  int get wordCount {
110:    if (title != null) count += title!.length;
113:      final anniversaryPattern = RegExp(                     // ★ 每次 getter 调用都新建 RegExp
114:        r'[\n]*[🎉⏰][^\n]*(?:纪念日|倒数日)[^\n]*',
115:        multiLine: true,
116:      );
117:      final userContent = content!.replaceAll(anniversaryPattern, '').trim();  // ★ 全串正则替换
```
另外 `lib/screens/main_screen.dart:300-347` 在 **App 启动 2 秒后**也跑一遍同样的 5 组检查（`_checkMilestone`），与保存后重复。

### 机制与量级
- 8 组检查里，`checkMilestoneBadges` / `checkStreakBadges` / `checkTotalCountBadges` / `checkContentBadges` / `checkTimeBadges` / `checkPhotoBadges` / `checkEmotionBadges` / `checkSpecialBadges` / `checkHiddenBadges` **每组都遍历全部 79 个 Badge**（`badge_service.dart:1393,1474,1491,1513,1652,1754,1944,2102,2206`）。79 × 8 ≈ **632 次 Badge 遍历**（很便宜），但：
- 每次命中条件 → `await unlockBadge(id)` → `SharedPreferences.getInstance()`（首次后是内存单例，但仍是 async 边界）+ 2 次 `setBool` + 1 次 `setInt`。最坏 79 次写入 ≈ **237 次 SharedPreferences 写**（每次写都触发平台 channel + Android 磁盘 edit-apply）。
- `checkHiddenBadges`（2184-2186）对**全部日记**取 `wordCount`，而 `wordCount` 每次 **new RegExp + replaceAll 全文**：
  - 1000 篇 × 平均 800 字 → 1000 × (正则编译 + 800 char 扫描 + 新建 800 char 串) ≈ **1000 次正则编译 + 800K char 处理**。单次约 0.05~0.2ms → **50~200ms 纯卡顿**，发生在"点保存后"的同步路径上。
- `checkPhotoBadges`（1696-1752）又全量遍历 `allDiaries` 两遍 + `DateTime.parse` 每篇一次。
- `checkEmotionBadges`（1937-2005）对**刚保存的日记**做 `_hasValidKeyword`：遍历 `_emotionKeywords`（8 个 key，共 ~300 词）+ `_positiveEmotionKeywords`（**227 词**）+ `_negativeWords`（26 词），每个词内部 `toLowerCase()` 后 `indexOf` 循环，`_isNegated` 再对 26 个否定词 `contains`。**单篇文本 × ~550 词 × 平均多次 indexOf** ≈ 数千次字符串扫描。
- **总结：保存日记的用户可感知延迟 = 徽章检查里的全量 `wordCount`（正则）+ 大量 SharedPreferences 写 + 情绪关键词全量扫描**，在 1000 篇量级上典型 **200~800ms**，且 `Navigator.pop` 在 `await _checkMilestoneAfterSave()` **之后**（第 653-656 行）→ 用户按保存后页面要卡住才退出。

### 改法
1. **`wordCount` 缓存**：`Diary` 加 `int? _cachedWordCount`，`wordCount` getter 命中缓存；或把 `RegExp` 提成 `static final` 顶层常量（最低成本、去掉 1000 次编译）：
```dart
// diary.dart
static final RegExp _anniversaryPattern =
    RegExp(r'[\n]*[🎉⏰][^\n]*(?:纪念日|倒数日)[^\n]*', multiLine: true);
```
2. **徽章检查改成"事件驱动 + 计数增量"**：只对**本次保存的日记**跑 `checkContentBadges` / `checkTimeBadges` / `checkEmotionBadges` / `checkSpecialBadges`（这 4 组是单篇判定，已经是 O(1) 语义），而 `checkMilestoneBadges` / `checkStreakBadges` / `checkTotalCountBadges` / `checkPhotoBadges` / `checkHiddenBadges` 需要的只是 **5 个整数**（uniqueDays / currentStreak / totalCount / totalPhotos / totalChars），这些应该在**写日记时就增量更新并持久化**，页面打开时直接读，不做全量遍历。
3. **`SharedPreferences` 批量化**：`getUnlockedBadges` 一次性读出 79 个 bool（现在是 1 次 getInstance + 79 次 getBool，可接受），但 `unlockBadge` 的写要改成"收集完所有新徽章后 `await prefs.setBool(...)` 循环一次"，且 `_newBadgeKey`/`_badgeLastShownKey` 合并成一次写。
4. **把保存后的检查放到 `Future.microtask` 之后 + 先 `Navigator.pop` 再检查**：用户感知从 800ms 降到 0。当前是 `await _checkMilestoneAfterSave(); if (mounted) Navigator.pop(...)`（653-656），把顺序反过来即可。
5. `main_screen` 的 `_checkMilestone` 与保存后检查**合并成一个"启动/保存共用"的 checkAllBadges 入口**（`badge_service.dart:2294` 已有 `checkAllBadges` 但两处都没用），去重。

### 风险
- 增量计数一旦与历史数据不一致（旧版本没记），需要一次性的"重建计数"迁移（在读日记列表时算一次并落盘）。
- 先 pop 再检查会导致徽章弹窗出现在**已经返回的页面**上 → 需要用 `rootNavigator: true` 的 dialog 或 `Overlay`，否则会报 `context` 失效。

---

## P0-6｜存储层：每次保存日记都"全量重新 AES 加密 + 全量写盘"（本次审计的**根因级**问题）

### 位置
`lib/services/database_service.dart`（全文 3 行）
```
1: // 所有平台都使用内存存储（web 和 desktop）
2: // 移动端原生 SQLite 实现在 database_service_native.dart 中（需要额外配置）
3: export 'database_service_web.dart';
```
`lib/services/database_service_web.dart`
```dart
270:  static Future<void> _saveDiaries() async {
272:    final encryptedList = await Future.wait(                 // ★ 对全部 N 篇各跑一次 AES
273:      _diaries.map((d) => _encryptDiaryMap(d.toMap())),
274:    );
275:    final diariesJson = jsonEncode(encryptedList);           // ★ 全量 JSON 字符串（新的一份）
276:    await _prefs?.setString(_diariesKey, diariesJson);       // ★ 全量重写 SharedPreferences
279:    _updateMetadata();
280:  }
331:  static void _updateMetadata() {
333:    _metadataCache = {
334:      'totalCount': _diaries.length,
335:      'totalWordCount': _diaries.fold(0, (sum, d) => sum + d.wordCount),  // ★ 又全量 wordCount(RegExp)
336:      'uniqueDates': _diaries.map((d) => d.date).toSet().toList(),
339:    _prefs?.setString(_metadataKey, jsonEncode(_metadataCache));          // ★ 第二次全量写
```
- `insertDiary`（439-449）→ `_diaries.add(newDiary)` → `_saveDiaries()`；`updateDiary`（512-523）同样；`deleteDiary`（525-532）还要多一次 `_saveDiaryTags()`。
- 触发链：`write_diary_screen.dart:610` `provider.addDiary` → `diary_provider.dart:209` `DatabaseService.insertDiary` → `database_service_web.dart:447` `_saveDiaries()`。
- 启动链：`_ensureInitialized()`（63-87）→ `_loadData()`（91-112）→ `_decryptDiariesSync()`（235-267）**逐条 `await _decryptDiaryMap`**（串行 AES 解密 N 次）。
- `Diary.wordCount`（`models/diary.dart:108-121`）每次调用都 `RegExp(...)` + `replaceAll` 全文。

### 机制与量级
- **写放大 = O(N)**：保存第 N+1 篇时，把 N 篇全部重新 `toMap()` → `encryptTextV2(title)` + `encryptTextV2(content)`（各一次 AES-CBC + 2 次 base64）→ 拼 JSON → 一次 5MB 级 `setString`。
- 实测规模推算（1000 篇、均 800 字）：全量 JSON ≈ **1000 × 800 字 × 3B(UTF-8) × 1.33(Base64) ≈ 3.2MB**，加密前对象树更大。
  - AES-CBC 2000 次（title+content）× 平均 ~1KB 块：Dart 纯软件实现约 **200~600ms**；
  - `jsonEncode` 3~5MB：**30~80ms**；
  - `SharedPreferences.setString` 全量落盘（Android `apply()` 后台写 + 全文件替换）：**100~300ms**，且**每次写都触发一次全 XML 序列化**；
  - 合计 **每次保存 300ms~1s**，且发生在 `_saveDiary` 的 `await` 路径上（`write_diary_screen.dart:610`），用户在保存按钮上直接感知。
- **启动更糟**：`_loadData` 把 3.2MB JSON 一次 `jsonDecode`（建 1000 个 Map）→ 逐条 `await` 解密（1000 × 2 次 AES，微任务串行）→ 建 1000 个 `Diary`。首帧前 ≈ **1~3s**（`main.dart` 里 `loadAllData` 之前还有 `initializeDateFormatting` / `CloudSyncFactory.initialize` / `SyncLogService.initialize` / `SoundService` 等串行 await）。
- Android `SharedPreferences` 对 >1MB 的 XML 有已知的启动解析开销与内存翻倍（XML 树 + 字符串），**这就是"频繁闪退"最合理的解释之一**：不是某一次 OOM，而是常驻一份 3~5MB 的 XML 字符串 + 每次编辑再生成一份（峰值 2×），叠加图片预览后超过 dalvik heap 上限。

### 改法
**(a) 立刻可做的止血（不改架构）**
1. `_saveDiaries()` 只重写**被改动的那一条**：改成按 id 分 key 存（`diaries_data_<id>`），`_saveDiaries` 只在首次/迁移时全量写。
2. 或者用"脏标记"：`insertDiary/updateDiary/deleteDiary` 只 append 一个 `pending_ops` 列表，用 500ms 防抖合并后一次性落盘；页面退出时 flush。
3. `_encryptDiaryMap` 里 `title/content` **没变就不重新加密**（`isEncrypted(map['title'])` 已有现成判断，`database_service_web.dart:349,353` 用上了，但 `_saveDiaries` 时 `d.toMap()` 出来的明文会被重新加密 —— 所以正确做法是**保留原始密文 Map**，只对变更字段加密）。

**(b) 正确解法：切回 sqflite（代码已经写好）**
```dart
// lib/services/database_service.dart
export 'database_service_native.dart';   // ← 改这一行即可切到 SQLite
```
`database_service_native.dart` 实现了 15 版 schema、加密字段、`getTagsByDiaryId` 的 JOIN 查询（730-738）、`getMoodDistribution` 的 `GROUP BY`（742-755）、`getDiaryCountByMonth`（757-766）—— **P0-2 的 N+1 在这里本来是 O(1) SQL**。切换前需验证：`isEncrypted` 兼容（V1/V2）、`_decryptDiaryMap` 一致（native 版 470-482 与 web 版同构）、以及 web 平台仍需 `_web.dart`（需要条件导入 `dart.library.io`，当前**没有**任何 conditional export，必须补）。

### 风险
- 切 sqflite 是**数据迁移**：需要一次性把 SharedPreferences 里的全量 JSON 写成 SQLite 行，失败会丢数据 → 必须双写过渡 + 校验行数。
- `database_service_native.dart` 从未被编译过（无 import），很可能有编译错误/API 漂移（如 `tableDiaryTags`、`insertDiaryTag` 签名），需先单独 `dart analyze` 该文件。
- Web 端（如果还维护 UI 预览）依赖 `_web.dart`，需 conditional import 而非直接替换。

---

## P1 级问题（逐项）

### P1-1｜统计页每次进入全量重算，且 streak 里 O(N²)
**触发频率先说清（很重要）**：`main_screen.dart:617-621` 的 `PageView` 用 `children: _screens`（非 `PageView.builder`），且 `physics: NeverScrollableScrollPhysics`；四个 tab 页（`timeline/calendar/stats/profile`）**都没有 `AutomaticKeepAliveClientMixin`**（grep 零命中）。`PageView` 默认 `allowImplicitScrolling: false`，实际只保留当前页 + 预加载 1 页的 `State`，**离开视野后 `dispose`** → **每次从别的 tab 切回"统计"，`initState` 都会重新跑 `_loadStats()` 全量聚合（含 P0-2 的 N+1）**。这是"统计页每次都慢"的直接原因。
（若想保留页面，加 `AutomaticKeepAliveClientMixin` + `wantKeepAlive => true`；但更好的做法是保留**数据**而不是保留 widget，见改法。）

`lib/screens/stats_screen.dart`
```dart
 98:  final diaries = await DatabaseService.getAllDiaries();       // 全量解密 + 排序拷贝
107:  final dates = diaries.map((d) => DateFormat('yyyy-MM-dd').parse(d.date)).toList();  // ★ 每篇 new DateFormat + parse
109:  dates.sort();
115:  _uniqueDays = dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).toSet().length;   // ★ 又 format 一遍
118:  _totalChars = diaries.fold(0, (sum, d) => sum + d.wordCount); // ★ 每篇跑 RegExp（diary.dart:108）
127:  _moodDistribution = await DatabaseService.getMoodDistribution();  // 又来一次全量 _diaries 扫描
138:  for (final diary in diaries) { _weatherDistribution[diary.weather!] = ... }  // 全量
155:  if (diaries.isNotEmpty && diaries.first.createdAt != null) { ... }            // 全量 hours
188:  while (uniqueDates.any(...)) { ... }        // ★ any() 每次 O(N) → 连续天数 X 天 = O(N×X)
199:  while (uniqueDates.any(...)) { ... }        // 同上
```
- `DateFormat('yyyy-MM-dd')` 在循环里每篇 new 一次（第 108、115、225、637、638 行等），`intl` 的 `DateFormat` 构造 + 首次 format 会做 locale 解析。**应提成 `static final _fmt = DateFormat('yyyy-MM-dd')`**。
- 第 115 行：`dates` 已经是 `DateTime`，又 `format` 回字符串再 `toSet` —— 应直接用 `DateTime(y,m,d).toSet()`。
- 第 188-206 行：`while (... uniqueDates.any(...))` —— 连续打卡 365 天时 = 365 × 1000 = **365,000 次比较**；最长连续同理（第 211-219 是 O(N) 的排序后扫，这块是对的）。
- 第 122-124 行 `_generateWeekCheckIn` 里 `uniqueDates.contains(dateStr)` 对 Set 是 O(1)（Set 正确），可接受。
- 建议：**把这段统计放进 `DiaryProvider` 做一次并缓存**（key = `diaries.length + 最后更新时间`），或做成 `Future<StatsSnapshot>` 在 `loadDiaries` 后一次性算出；页面只读。配合 `AutomaticKeepAliveClientMixin` 或（更好）把 snapshot 存 provider，切 tab 不重算。

### P1-2｜情绪分析：`analyze()` 是 O(词表) × O(修饰词) 的 double loop，逐篇调用
`lib/services/sentiment_analysis_service.dart`
```dart
131:  static SentimentResult analyze(String text) {
141:    for (final entry in EmotionKeywords.positiveWords.entries) {      // 55 词
142:      if (text.contains(entry.key)) {
146:        for (final mod in EmotionKeywords.intensityModifiers.entries) {  // 23 词 × 2 次 contains
147:          if (text.contains(mod.key + entry.key) || text.contains(entry.key + mod.key)) {
163:    for (final entry in EmotionKeywords.negativeWords.entries) {      // 66 词
168:        for (final mod in EmotionKeywords.intensityModifiers.entries) { ... }
156:        if (!detectedKeywords.any((k) => k.contains(entry.key))) { ... }  // ★ 又一层线性
```
- 每次 `analyze`：**55+66 = 121 次 `text.contains`**，每个命中再 23×2 = 46 次 `contains` 拼接新字符串（`mod.key + entry.key` **每次循环都新建字符串**）。
- `analyzeDiaries`（257-306）对**每篇日记**调用一次（拼 `title+content` 再建新串）→ 1000 篇 ≈ **121,000 次 contains + 大量字符串拼接**，典型 **300~1500ms**。
- 情绪页还叠加：`_generateWeeklyData`（`emotion_stats_screen.dart:69-111`，**7 天 × 全部日记 where + 每篇 DateTime.parse**）+ `_generateMonthlyData`（113-140，**30 天 × 全部日记 where + 每篇 DateTime.parse**）→ O(37N) 次 parse；`_buildKeywordsCloud`（527-540，**在 build 里**！）对全部日记再跑一遍 `analyze`。
- v2 页（`emotion_stats_screen_v2.dart:42-43, 54-90`）同构，但 `_buildKeywordsCloud` 已不在 build 里（只有 `_generateWeeklyData` 的 7N）。
- 改法：词表提成 `static final` 的 **Aho–Corasick / 单遍扫描**，或至少把 `mod.key + entry.key` 预拼接成常量表；`analyzeDiaries` 用 `compute` 丢到 isolate；`_buildKeywordsCloud` 结果缓存到 `_stats` 里（不要 build 里算）。

### P1-3｜统计详情页：797 个成语 × N 篇 + 每篇编译 RegExp
`lib/screens/stats_detail_screen.dart`
```dart
47:  void initState() { super.initState(); _analyzeTexts(); }     // 进页即跑，无 loading 占位（有 _isAnalyzing）
52:  Future<void> _analyzeTexts() async {
53:    final provider = context.read<DiaryProvider>();
54:    final diaries = provider.diaries;                           // 用的是 Provider 的（可能只有 20 篇，见 P1-5）
62:    final idioms = TextAnalysisService.getTopIdioms(diaries, limit: 10);
71:    final snippets = TextAnalysisService.extractMoodSnippets(diaries);
```
`lib/services/text_analysis_service.dart`
```dart
170:  static Map<String, int> extractIdioms(List<Diary> diaries) {
173:    for (final diary in diaries) {              // N 篇
179:      for (final idiom in _commonIdioms) {      // ★ 797 个成语（实测 `_commonIdioms` 797 条）
180:        if (content.contains(idiom)) { ... }    // 每篇 797 次 contains
...
308:    for (final diary in diaries) {
316:      for (final entry in _moodKeywords.entries) { ... }        // 10 mood × ~15 词
328:      final sentences = content.split(RegExp(r'[。！？\n]+'));    // ★ 每篇一次 RegExp 编译
```
- `extractIdioms`：1000 篇 × 797 = **797,000 次 contains**（每篇 800 字 → 每次 contains 平均扫 800 char）→ 量级 **10⁸ char 比较**，典型 **1~5 秒**。
- `extractMoodSnippets`：每篇 `split(RegExp(...))` 在循环内 → **1000 次 RegExp 编译**（Dart RegExp 编译有缓存但在循环里 new 仍走构造检查）。
- 改法：`RegExp` 提成 `static final`；成语检测换成**预建 Set/HashSet 的 4-gram 切分**（对每篇做一次 4 字滑窗 800 次，再 hash 查 797 个成语 → 从 797N 降到 4N）；或直接把该功能做成"进页后延迟 300ms + 骨架屏"，别阻塞首帧。

### P1-4｜profile_screen：首屏一次性 build 全部卡片（无懒加载）+ 4 次并发 setState 整页 rebuild
`lib/screens/profile_screen.dart`
- `initState`（58-64）触发的服务调用共 4 个：`_loadBadges()`（`getUnlockedBadges` 79 次 getBool + `hasNewBadge`）、`_loadAppLockStatus()`（`AppLockService.initialize()`：SharedPreferences + `jsonDecode(pattern)`）、`_loadBiometricStatus()`（`BiometricAuthService.initialize()` + `hasAvailableBiometrics()` → **3 次 local_auth 平台通道往返**：`isDeviceSupported` / `canCheckBiometrics` / `getAvailableBiometrics`）、`_loadFloatingWindowStatus()`（SharedPreferences）。**全部并发发出，各自 `setState` → 首屏至少 4 次全页 rebuild（111KB 页面）**。
- `_loadMoods()` 不在此列（只在弹窗用，第 1854/1899/1949 行），OK。
- `build`（208-425）内：`AppTheme.schemeOf(context)` **1 次**（第 209 行）+ 9 组 `_buildMenuGroup` + **15 个 `_MenuItem`**（每个含 icon/title/subtitle/onTap）。
- **修正一处常见误判**：`profile_screen.dart` 内共 10 处 `schemeOf`（209/645/943/1538/1781/1857/2058/2367/2790/3051），但**只有第 209 行在 `build` 里**，其余 9 处都在 `_showXxx` 弹窗方法中（点开才算）。所以"一个 build 帧注册 12 个 ThemeProvider 依赖"**不成立**；真实开销来自 4 个并发 `setState` 触发的 4 次整页 rebuild。
- `Consumer<SettingsProvider>`（237）只包了用户卡片（好）。
- 真正可优化点：`_buildBadgeSection` / `_buildMenuGroup` 里大量 `Container + BoxShadow + LinearGradient` **每次 `setState` 都会全部重建**（该文件 `addListener` = **0**、`TweenAnimationBuilder`/`AnimatedBuilder` = **0** → 没有动画驱动，只有 4 次服务回调的 `setState`），且是 **`SingleChildScrollView`（不是 `ListView.builder`）** —— 整页 111KB 的所有子组件在**首帧一次性全部 build 并 layout**，无懒加载。建议把各组菜单改成 `SliverList`/`ListView` 的 builder 形式，或至少给底部几组（时间胶囊/个性化/关于）做 `Visibility` 延迟构建。
- `_showAllBadges`（644-711）：`GridView.builder` 79 格，`_buildBadgeGridItem`（713+）每格建 `BoxShadow` + `LinearGradient` + `Text`，79 格全是**非 const 的 Container**，首次展开约 79 × 多个图层；对 79 个不算灾难，但叠加 P2-1（特殊主题时整个 PageView 被 60fps 重绘）后会放大成可感知的掉帧。
- 改法：`build` 顶部取一次 `scheme` 后**传参**给所有 `_buildXxx(scheme)`（很多已经是这么做的，但内部又各自 `schemeOf`）；把 `AppTheme.schemeOf` 的 `context.watch` 换成 `Provider.of<ThemeProvider>(context)`（listen:false）+ 在需要的局部用 `Consumer<ThemeProvider>` 或 `InheritedWidget.of` 局部 rebuild。

### P1-5｜简版搜索：`provider.diaries` 只有 20 篇（分页）却被当"全部"，且"防抖"是假的
`lib/screens/diary_search_screen.dart`
```dart
 57:    final provider = context.read<DiaryProvider>();
 58:    final allDiaries = provider.diaries;         // ★ 只有最近 20 篇（diary_provider.dart:80-84）
 62:    final results = allDiaries.where(...)
 68:    results.sort(...)
215:                onChanged: (value) {
216:                  setState(() {});                 // 只为了更新清除按钮
217:                  // 防抖搜索
218:                  Future.delayed(const Duration(milliseconds: 300), () {
219:                    if (_searchController.text == value) {   // ★ 假防抖：不 cancel、不取消，300ms 后仍会跑
220:                      _performSearch(value);
221:                    }
222:                  });
223:                },
```
- `Future.delayed` 无法取消，快速输入 5 字符会**排队 5 次 300ms 回调**；虽然第 219 行用文本比对过滤了过期的，但仍会建 5 个 Timer + 5 个闭包，且**最后一次一定跑**。
- 结果语义缺陷：搜不到 20 篇以外的日记（用户会以为"日记丢了"）。**这是正确性 bug，不只是性能**。
- 改法：真 `Timer? _debounce`（参考 P0-3 代码）；数据源改成 `await DatabaseService.getAllDiaries()`（一次）或先 `provider.loadDiaries()`。
- 高亮 `_highlightText`（78-120）用 `indexOf` 循环（不用 RegExp，OK），但每个结果卡片都新建 `TextSpan` 列表（`ListView.builder` 按需构建，可接受）；`_buildDiaryCard`（342-361）对每张卡做 `toLowerCase()` + `indexOf`（第 347-349），只对可见项生效，可接受。

### P2-1｜主题背景每帧全页重绘（`shouldRepaint => true` × 5 + `CustomPaint` 包整棵树）
`lib/widgets/theme_backgrounds.dart`
> ✅ **本条是「每帧」断言的正例**（startup-native 复核 C1 独立核实成立），与 P2-2 / P2-6 的两处误判形成对照。**为什么它成立而另两处不成立**：这里的动画控制权在背景 `State` 自己手里 —— `AnimationController..repeat()`（`:57` 等 7 处）**直接驱动 `AnimatedBuilder`，而 `AnimatedBuilder` 的 builder 返回的 `CustomPaint` 又 `child: widget.child` 把整棵 PageView 树包在里面**（`:396-403`）。所以「每帧」是真的：动画 tick → `AnimatedBuilder` builder 重跑 → 新建 `CustomPaint(child: 整棵树)` → 该子树整体进入重绘。判据里的 (b) 「目标子树确实被动画 widget 包住」在这一条上是满足的。
- 5 个 painter 全部 `shouldRepaint => true`：`:624`（Sakura）、`:1244`（Ocean）、`:1494`（Aurora）、`:1983`（TimeVault/Golden）、`:2250`（`_StarryPainter`）。
- 每个背景 `State` 都有 `AnimationController..repeat()`（`:57, 657, 663, 669, 1293, 1562, 2012`，共 7 个 repeat），**`CustomPaint(child: widget.child)`**（`:396-403, 810-816, 1320-1325, 1680-1689, 2076-2101`）→ 背景层重绘会**把 child 子树一起带进重绘边界**（`CustomPaint` 本身不是 separate layer）。
- 补充：`theme_backgrounds.dart` 的 `addListener` 命中数 = **0** —— 但它**不需要** `addListener` 来达成每帧重绘，因为 `AnimatedBuilder` 内部会订阅 `Listenable`（`animation:` 参数）并每帧重跑 builder。这正是判据 (b) 的价值：**没有 addListener ≠ 不会每帧重建**。
- 代价：星空 80 星（`starCount = 80`，`:2015`）+ 大星光晕（`MaskFilter.blur` 每颗 `drawCircle`，`:2189`）；樱花 25 花瓣 + 最多 2 朵 5 瓣花（每瓣 2 次 cubicTo + 2 个 shader）；海洋 15 气泡 + 3 条波浪路径（**每条波浪 `for (double x = 0; x <= size.width; x += 2)` 逐 2px 采样 + 3 次 `sin`**，1080 宽 = 540 点 × 3 波 = 1620 次 sin/帧）。
- `MaskFilter.blur` 在 Impeller/Skia 都不便宜（离屏模糊）→ 星空主题在中低端机上掉帧最明显。
- 触发条件：`main_screen.dart:558-561` 只有主题名是 5 个特殊主题之一才 wrap；默认 `warmBeige` 不走。所以**只有付费/解锁特殊主题的用户受影响**（但这类用户往往就是"开特效就卡"的那批）。
- 改法：
  1. `CustomPaint` 外包 `RepaintBoundary`（把背景重绘与内容重绘隔离）；
  2. `CustomPaint` 用 `foregroundPainter` 或把背景做成 `Stack` 最底层 + `IgnorePointer`，**child 不放在 CustomPaint 下面**；
  3. `shouldRepaint` 改成比较 `progress`/`time`（虽然每帧都变，但可避免重复 dispose/rebuild painter 对象）；真正省的是 **painter 对象每帧在 `AnimatedBuilder` 里 new**（`:396-402` 每帧构造 `SakuraPainter` 新实例 → 每帧 alloc + 全量重绘）。
  4. 降低背景帧率：`Ticker` 用 `SchedulerBinding` 每 2 帧跳 1 帧（30fps 背景，60fps 内容）。

### P2-2｜抽卡页 4 处 `FutureBuilder(future: ...)` 内联建 future（**已按 crosscheck A5 降级为 P3 轻微**）
`lib/screens/gacha_screen.dart`
```dart
 248: return FutureBuilder<Map<String, int>>(future: GachaService.getAllResourceCounts(), ...)   // ← 首屏 build 路径（被 build():169 调用）
1193: return FutureBuilder<Map<String, dynamic>>(future: GachaService.getResourceSummary(), ...)  // ← _showCollectionStats 的 bottomSheet builder
1767: FutureBuilder<Map<String, int>>(future: GachaService.getAllResourceCounts(), ...)           // ← _showStickerShop 的 bottomSheet builder
2042: FutureBuilder<Map<String, int>>(future: GachaService.getAllResourceCounts(), ...)           // ← _showThemeShop 的 bottomSheet builder
```
**⚠️ crosscheck A5 更正（原「每帧 240 次 SharedPreferences 读取」不成立）**，三个独立原因：
- **(a) 位置归类错**：4 处中**只有 `:248` 在首屏 `build()` 路径**；另 3 处在 `showModalBottomSheet` 的 builder 内（独立 route，只在弹窗打开时构建），不受首页 rebuild 影响。
- **(b) 动画不会每帧触发父级 rebuild**：`_shakeController.repeat()`（`:90`）与 `_animationController.forward()`（`:106`）**只在 `AnimatedBuilder`（`:320-345`）内消费**，`build()` 里**没有任何 `addListener`**；`setState` 只在状态切换点发生 —— `:79`/`:100`/`:114`/`:126` **共 4 次**，不是每帧。
- **(c) `SharedPreferences` 不贵**：`getInstance()` 有 `_completer` 单例缓存（`shared_preferences` 的 `shared_preferences_legacy.dart`），第二次起直接返回已完成的 Future；`getInt` 是**纯内存 map 查表**（`_preferenceCache[key]`），**零 IO**。即便每帧调 4 次，成本也只是 4 个 Future 分配 + 4 次微任务，**不是「240 次读取排队」**。
- **真实影响（降级后仍是 P3 收尾项）**：`:248` 那一处每次首屏 rebuild 都会新建 Future → `FutureBuilder` 从 `ConnectionState.waiting` 重新开始 → **短暂闪空一下**（不是抖动、不掉帧）。
- 改法（成本 S，仍建议做）：`late final Future<Map<String, int>> _resourceFuture = GachaService.getAllResourceCounts();`，build 里直接用 `_resourceFuture`；弹窗内 3 处同理提到对应方法的局部 `final` 一次即可。

### P2-3｜抽卡历史解析：20 条 × 97 奖励 `firstWhere`
`lib/services/gacha_service.dart:1558-1596`
```dart
1575:  for (final jsonStr in historyJson) {
1577:    final data = jsonDecode(jsonStr);
1579:    final reward = _allRewards.firstWhere((r) => r.id == rewardId, orElse: () => _allRewards.first);
```
- 20 × 97 = 1940 次比较，便宜；但**每次打开历史页都 `jsonDecode` 20 次 + 重建 20 个 `GachaRecord`**。
- 改法：`_allRewards` 预建 `Map<String, GachaReward>`（`static final _byId = {for (final r in _allRewards) r.id: r};`），O(1) 查找；历史解析结果缓存到内存（只在 `_saveToHistory`/`clearHistory` 时失效）。

### P2-4｜`.mbk` 备份导出/导入全程主 isolate + 无进度
`lib/services/backup_export_service.dart`
- 导出（23-94）：`_generateDataHash` → `jsonEncode(backupData)`（**全量日记一个巨大字符串**）→ `utf8.encode`（又一份 bytes）→ AES `encryptBytes`（第三份）→ `ZipEncoder().encode(archive)`（第四份）→ `writeAsBytes`。**全程 `await` 在 UI isolate**，1000 篇 × 800 字 ≈ 4MB JSON → 峰值 ≈ **4(JSON str) + 4(utf8) + 4(AES) + 4(zip) ≈ 16MB + 哈希再一份**；数据大时更糟。
- 导入（97-148）：`file.readAsBytes()` → `ZipDecoder().decodeBytes`（全解压到内存）→ `AES.decryptBytes` → `jsonDecode`（**再建完整对象树**）→ 之后 `data_management_screen.dart:1063-1068` 再 `Diary.fromMap` 建 List → `importDiaries` 逐条 `indexWhere`（**O(N²)**，`database_service_web.dart:455-469`）。
- 无 `onProgress` 参数（整个服务没有进度回调）；`data_management_screen.dart:887-917` 只有 `_isExporting` 一个 bool。
- 改法：`jsonEncode` + `sha256` 用 `compute`（`Map` 可发送）；zip 用 `ZipFileEncoder` 流式写临时文件再 `copy`（避免 bytes 常驻）；导入改 `compute` 解 JSON，`importDiaries` 的 `indexWhere` 换成 `Map<int, int>` 索引。

### P2-5｜启动即跑自动备份（全量 JSON）
`lib/main.dart:62` `AutoBackupService.checkAndBackup()`；`auto_backup_service.dart:64-114`
```dart
 76:  final diaries = await DatabaseService.getAllDiaries();
 77:  final moods = await DatabaseService.getAllMoods();
 78:  final tags = await DatabaseService.getAllTags();
 81:  final backupData = {...};
 96:  await file.writeAsString(jsonEncode(backupData));      // ★ 主 isolate 大 JSON
131:  'size': await File(filePath).length(),
```
- 启动后立即（若距上次 >N 小时）在**主 isolate** 做全量序列化 + 写盘；1000 篇量级 ≈ **几十~几百 ms 卡首屏**。
- 改法：延后到启动后 30s；`jsonEncode` 走 `compute`；或直接改用 `sqflite` 的 `.db` 文件复制（**但这需要先修存储层**，见下）。

### P2-6｜其他确认项

> **「每帧 rebuild」类断言的判定判据（本报告统一口径，来自 startup-native 复核 + crosscheck A5/A6/C2）**
>
> **前置认知**：`AnimatedBuilder` / `TweenAnimationBuilder` **只重建其 `builder` 子树，不会让外层 `build()` 重跑**；`SlideTransition` / `FadeTransition` 是 `Transition`，走 RenderObject 更新 transform/opacity，**同样不触发 widget rebuild**。所以「动画期间每帧 rebuild / 每秒 N 次」**不能想当然**，必须验证。
>
> **判定规则 —— 满足 (a) 或 (b) 任一即可成立：**
> - **(a) 该文件存在 `addListener` + `setState`**（动画控制器主动推 setState）；**或**
> - **(b) 目标子树确实被动画 widget 包住**（例如 `AnimatedBuilder` 的 `builder` 直接返回 `CustomPaint(child: 整棵树)`）。
>
> ⚠️ **最关键的一条防误用警告：`(b)` 不要求 `addListener`。**
> `AnimatedBuilder` 内部通过 `animation:` 参数自行订阅 `Listenable` 并每帧重跑 builder，**不需要文件里出现任何 `addListener`**。
> 因此 **`grep addListener` 返回 0 时，只能排除 (a)，绝不能据此判定「不会每帧重建」—— 必须继续查 (b)。**
> 本报告已因此避免一次误杀：`theme_backgrounds.dart` 的 `addListener` = **0**，但 `AnimatedBuilder` = 5 / `AnimationController` = 14 / `..repeat()` = 7，且 builder 返回 `CustomPaint(child: widget.child)` → **满足 (b)，P2-1 的每帧重绘真实成立**（详见 §P2-1）。
>
> **验证命令（两步，缺一不可）**：
> ```powershell
> # 第一步：查 (a)
> Select-String -Path lib\screens\<file>.dart -Pattern 'addListener'
> # 第二步：即使上一步为 0，也要查 (b) —— 是否存在重复驱动的动画 widget
> Select-String -Path lib\screens\<file>.dart -Pattern 'AnimatedBuilder|TweenAnimationBuilder|\.repeat\(\)|AnimationController'
> ```
> **本次实测结论**（三步都要看，切勿只看文件级计数）：
>
> | 文件 | (a) `addListener` | 第二步：动画 widget 存在？ | 目标子树是否被包住 (b)？ | 结论 |
> |---|---|---|---|---|
> | `stats_screen.dart` | 0 | 有（2 个 `AnimationController`、`:392`/`:1158` 两个 `AnimatedBuilder`、`:656` 一个 `TweenAnimationBuilder`） | **否**：两个 `AnimatedBuilder` 只包统计卡内部 Container 与 10px 进度条；`:656` 只包 `_buildStreakCard` 里 40×40 日期圆圈。**均不含 `build():291` 的 `_buildLastYearTodayCard()`** | 目标子树不会被每帧重建（A6 已更正） |
> | `gacha_screen.dart` | 0 | 有（2 个 `AnimationController`、`:90` `repeat()`、`:320` `AnimatedBuilder`、`:660`/`:1929`/`:2218` 三个 `TweenAnimationBuilder`） | **部分**：`:320` 的 `AnimatedBuilder` 只包 `_buildGachaMachine`（`:317`）本体，且 12 个球已提到 `child:` 常量子树；`:660` 在 `_buildRewardCard`（`:482`）内也只包奖励卡自身；`setState` 共 5 处 —— `:70`（`_loadRemainingDraws`）+ 动画状态切换 `:79/:100/:114/:126` | 首屏 `build()` 不随动画重跑（A5 已更正） |
> | `profile_screen.dart` | 0 | **无**（两个查询均 0） | — | 无动画驱动，只有 4 次 setState（P1-4 已更正） |
> | `emotion_stats_screen.dart` | 0 | **无**（两个查询均 0） | — | 无动画驱动（`_buildKeywordsCloud` 措辞已更正） |
> | `theme_backgrounds.dart` | **0** | 有且极重：`AnimatedBuilder`=5 / `AnimationController`=14 / `..repeat()`=7 | **是**：builder 返回 `CustomPaint(child: widget.child)` 包住整棵 PageView 树 | **每帧重绘成立**（P2-1 正例，**不要因为 (a)=0 而误杀**） |
>
> ⚠️ **注意第 2、3 行的教训**：`stats_screen` 与 `gacha_screen` 的文件级动画计数都不低（7 / 14），但**判据 (b) 问的是「目标子树有没有被包住」，不是「文件里有没有动画」**。文件里有动画 widget ≠ 整棵树每帧重建。（这正是 A5/A6/P1-4 三处误判的共同根因：把「局部 AnimatedBuilder 重建」当成了「外层 build() 重跑」。）

- `emotion_stats_screen.dart:527-540` `_buildKeywordsCloud` **在 build 里**对全部日记跑 `SentimentAnalysisService.analyze` → 每次 `setState`/rebuild 都重算（不是"每帧"：该文件 **`AnimationController`/`TweenAnimationBuilder`/`AnimatedBuilder` 全为 0**，见上条判据）。**注意：v1 页 `emotion_stats_screen.dart` 已无任何文件 import（`stats_screen.dart:12` 引的是 `emotion_stats_screen_v2.dart`），是死代码** —— 不需要修，但建议删除以免误用。
- `diary_search_enhanced_screen.dart` 同样是**死代码**：全项目无任何文件 `import 'diary_search_enhanced_screen.dart'`（grep 零命中）。当前实际入口只有 `diary_search_screen.dart`（`calendar_screen.dart:237` + `stats_screen.dart:367`）。**P0-3 的修复优先级应下调为"修好再接线，或直接删"**，但若计划接线，必须先把防抖/缓存做完。
- **【P3，已按 startup-native 复核更正】** `stats_screen.dart:1250-1252` `_buildLastYearTodayCard()` 里 `FutureBuilder(future: _getLastYearTodayDiary())` —— **future 在 build 里创建**（这一点成立），所以每次 `build()` 重跑都会重新 `getDiariesByDate`（全量 `where` + sort）。
  - ❌ **原报告写的「数字动画 1200ms 内每帧 rebuild → 动画期间每秒 60 次全量扫描」不成立**，三重证据：① `stats_screen.dart` 全文 **`addListener` 命中数 = 0**（`_numberController:77-80` / `_pageController:58` 都没有挂监听器去 `setState`）；② `_numberController` 的消费点只有 `:392-393`（统计卡内部 Container）与 `:1158-1160`（10px 进度条）两个 `AnimatedBuilder`，**都不包含 `:291` 调用的 `_buildLastYearTodayCard()`**；③ `build()`（`:242`）里 `:268-271` 的 `SlideTransition`/`FadeTransition` 走 RenderObject 更新 transform/opacity，**不触发 widget rebuild**。
  - ✅ **真实影响**：唯一让 `:291` 重跑的是 `setState` —— `:96`（加载开始）、`:101`/`:169`（加载完成）、以及 `RefreshIndicator` → **每次数据加载共 2~3 次全表查询，不是每秒 60 次**。因此本条降级为 **P3**：每次加载完成后会多跑几次全表查询（浪费但不致命）。
  - 改法（仍然正确、保留）：`late final Future<Diary?> _lastYearFuture;` 在 `initState` 创建，`build` 里直接用该字段 → 把 2~3 次降到 1 次。
  - 补充排除：`:656` 的 `TweenAnimationBuilder<double>` 确实是"每帧重跑 builder"的类型，但它只包住 `_buildStreakCard()`（`:523`）里一个 40×40 日期圆圈（`:662-663`），与 `_buildLastYearTodayCard()`（`:1250`）是**两棵不相交的子树**，不能作为本条的锚点。
- `stats_screen.dart:386-476` `_buildStatsCard` 内 `AnimatedBuilder(animation: _numberAnimation, builder: (context, child) => Container(...))` —— **`child` 参数未被使用**（builder 忽略 child，整个 Container 在动画驱动下重建）；`_buildStatItemWithIcon` 里的 `DateFormat('yyyy/M/d')`（第 459 行）也随之执行。1200ms 动画 = 72 帧 × 4 个 stat item。建议把静态部分放进 `child:`。**（本条成立：`AnimatedBuilder` 确实会重建其 builder 子树，`_buildStatsCard` 就在该子树内。）**
- `stats_screen.dart:1158-1180` 第二个 `AnimatedBuilder` 同理（进度条在动画驱动下重建 `Container`+`LinearGradient`）。
- `emotion_stats_screen_v2` 的 `TabController` + `TabBarView` 三 tab：tab 之间切换不会重算（`_stats`/`_weeklyData` 已缓存），OK；但 `_buildWeeklyTab` 在 build 里对 7 条数据 map 构建（便宜）。
- `gacha_screen.dart:389` 每次 build 新建 `12` 个 `_buildGachaBall`（含 `RadialGradient` + `BoxShadow`），但位于 `_buildGachaMachine` 的 `AnimatedBuilder` 的 **`child:` 常量子树**里（第 346-419 行 `child: Container(...)` 被提到 builder 外）→ **这点做对了**，12 个球不随动画每帧重建。
- `cloud_sync_service.dart:1760-1766` `_debugPrint` 每次都会 `SyncLogService.log()` → `sync_log_service.dart:35-48` `file.writeAsString(logEntry, mode: FileMode.append)` **每条日志一次文件打开/追加**；全文件共 **131 处 `_debugPrint` 调用**，一次同步路径可产生几十条 → 几十次磁盘 IO + `DateFormat.format` 每次新建。建议加 `kDebugMode` 短路或改成内存环形缓冲 + 批量 flush。
- `cloud_sync_service.dart:819-901` `scanAllBackups` 用 `response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk))` 收集 XML（小，可接受），但 `_parseWebDAVListing`（882-899）用 `RegExp(r'<d:displayname>...')` 解析 XML（每次调用都新建 RegExp 实例）。
- `backup_manager_screen.dart:388-389` `FutureBuilder(future: EncryptionService.verifyKey(key))` 与 `:430-431` `FutureBuilder(future: EncryptionService.decryptWithCloudKey(...))` 也都在 build 里建 future → 每次 rebuild 重跑一次 AES 加解密测试（`encryption_service.dart` `verifyKey` 内含 `Key.fromBase64` + `IV.fromSecureRandom` + 一次完整 AES 加密）。
- `profile_screen.dart:691-711` `_showAllBadges` 的 `GridView.builder`：79 格（实测 **79 个唯一 Badge id**，不是文档说的 84），每格 `_buildBadgeGridItem`（713+）建 `LinearGradient` + `BoxShadow` + `Text`。79 个可接受，但**没有 `RepaintBoundary`、没有 `itemExtent`**，展开瞬间全量 measure。
- `profile_screen.dart:117-160` `_toggleFloatingWindow` 一次性串行 await 5 个平台通道（`setEnabled` → `requestNotificationPermission` → `checkOverlayPermission` → `showFloatingButton` → `checkBatteryOptimizationWhitelist` → `requestBatteryOptimizationWhitelist`），中间无 loading 态 → 用户点了像没反应。
- `profile_screen.dart:66-107` 首屏 4 个并发 `_loadXxx()` 各自 `setState` → **至少 4 次 111KB 全页 rebuild**；且 `build`（208）里的 `AppTheme.schemeOf(context)` 是 `context.watch<ThemeProvider>()`（`app_theme.dart:151-152`），`profile_screen.dart` 内共 **10 处 `schemeOf`**（行号 209/645/943/1538/1781/1857/2058/2367/2790/3051，其中只有 209 在 `build`，其余在弹窗方法里 —— 所以 build 帧内实际只注册 1 个 ThemeProvider 依赖，**问题没有最初估计的严重**；但 4 次连续 `setState` 的整页 rebuild 仍是真实开销）。
- `smart_recall_service.dart`：**一次 `getSmartRecalls()` 内部最多调用 4 次 `DatabaseService.getAllDiaries()`**（第 127、174、207、252 行各自独立全量取 + 排序）→ 每次打开"智能回忆"页 = **4 × 全量拷贝**。且 `_getThematicRecall`（199-243）对全部日记 × 关键词做 `contains` 双重循环 + 每篇 `DateTime.parse`。`stats_screen.dart:301`/`timeline_screen.dart:440` 都会进这个页面。改法：`getSmartRecalls` 里取一次 `diaries` 传给 4 个分支。
- `diary_cinema_screen.dart:147-160` `_extractSegments` 每篇 `split(RegExp(r'[。！？.!?\n]+'))`（RegExp 在方法内 new，每次切篇都编译）+ 长句 `trimmed.split('')` 逐字切（**按 UTF-16 code unit 切，中文 OK 但 emoji 会切坏**）。`_bgController.repeat()`（第 88 行）在页面存续期间**永久 60fps 跑背景色动画**。
- `self_talk_screen.dart:113-124` `_loadMessages` 串行 `getMessagesByDate` + `getTasksByDate`，两者在 web 存储层各做一次 `_selfTalkMessages.where(date).toList()..sort()`（全量扫描，但数据量通常小，P2）。
- `backup_reader.dart:27-46` / `mbk_backup_reader.dart:18-46` 都是 `readAsBytes()` → `ZipDecoder().decodeBytes()` 全解压进内存（MBK 导入第三方备份时，若备份含大图会 OOM）；`mbk_backup_reader` 还把 `_fileData` 作为**字段常驻**（第 27 行 `_fileData = await file.readAsBytes();`），对象存活期间整份备份都在内存。
- `incremental_sync_service.dart:38-86` `getChangesSince` 即使 `since != null` 也先 `getAllDiaries() + getAllMoods() + getAllTags() + getAllDiaryTagsV3()`（4 次全量），再做 `where` 过滤 → "增量同步"实际是**全量加载后内存过滤**。`applyRemoteChanges`（103-192）逐条 `getDiary(id)`（web 层 `_diaries.firstWhere`，O(N)）→ **O(N²)**。`saveSyncPackage`（195-207）又是 `jsonEncode(全量)` 写文件。

### P2-7｜图片展示层：原图解码 + `cacheWidth` 参数是死参数（低估的 OOM 来源）

**(a) `PlatformImage` 的 `cacheWidth/cacheHeight` 完全没接线（死参数）**
```dart
// lib/utils/platform_helpers.dart
21:  final int? cacheWidth;      // 声明了
22:  final int? cacheHeight;     // 声明了
30:  this.cacheWidth,           // 构造接收
31:  this.cacheHeight,
...
63:        return OptimizedCachedImage(   // ★ 但 build 里根本没往下传
64:          path: path, width: width, height: height, fit: fit,
68:          quality: CacheQuality.small,
69:        );
```
- 调用方**以为**自己在限制解码尺寸，实际全被丢弃：
  - `timeline_screen.dart:871-877` → `PlatformImage(path:, width:100, height:100, cacheWidth:200, cacheHeight:200)` ← 300×300 缩略图路径，参数被忽略（此处损失不大，因为 `quality: small` 已经限到 300px）；
  - `stats_detail_screen.dart:698-702` → `cacheWidth: 300, cacheHeight: 300` 同样被忽略；
  - `tag_diaries_screen.dart:302-306`、`diary_cinema_screen.dart:669-675`、`custom_sticker_screen.dart:275-281/391-397`、`custom_sticker_overlay.dart:156-162`、`random_sticker_overlay.dart:326-332` 全部同理。
- 更糟的是 `PlatformImage` 自己套了一层 `FutureBuilder(future: File(path).exists())`（第 50-71 行）—— **每个图片 widget 在 build 期都发起一次异步文件存在性检查**，一个可见列表页可能有几十个这类 Future 同时 pending；而 `OptimizedCachedImage` 内部又会自己再 `File.exists()` 一次（`image_cache_service.dart:415-416`）→ **同一张图两次 stat**。

**(b) 全屏看大图路径用 `OriginalImage` = 原图直解**
- `stats_detail_screen.dart:1243-1246` `PreviewImage(..., useOriginal: true)` → `image_cache_service.dart:629-634` 转 `OriginalImage` → `Image.file(File(path))` **没有 `cacheWidth/cacheHeight`**（`image_cache_service.dart:536-543`）。
- `diary_detail_screen.dart:1227` 全屏查看也是 `OriginalImage`。
- 后果：一张 4000×3000 的相机原图解码后 RGBA = 4000×3000×4 = **48MB**，Flutter `ImageCache` 默认上限 100MB/1000 张 —— **左右滑 2~3 张就吃满 100MB 并开始 OOM**。这是"翻照片翻几张就闪退"的典型机制。
- 注：`stats_screen.dart:129-134` 只取最多 10 张图给详情页（`take(10)`），`PhotoGalleryScreen` 的 `PageView.builder` 也不会全建；但**`PageView` 默认预加载相邻页**，配合 `Hero` + `InteractiveViewer` 会让 2~3 张原图同时在 `ImageCache` 里。
- 改法（低风险、收益大）：
```dart
// OriginalImage.build 里
return Image.file(
  File(path),
  width: width, height: height, fit: fit,
  cacheWidth: 1200,    // ← 全屏也就 1080p，1200 足够；显存/内存降 90%+
  cacheHeight: 1600,
  errorBuilder: ...,
);
```
- **注意**：`cacheWidth` 会**永久降质**该图在整个 app 的 `ImageCache` 条目（同一 key），若同一图片还会被其他组件按原图使用，需给 key 加后缀或用 `ResizeImage` 显式包装。推荐 `Image.file(..., cacheWidth: 1200)` 且全屏场景专用一份。

**(c) `OptimizedCachedImage` 的缩略图生成流程本身是好的**
- `image_cache_service.dart:139` 用 `compute<_ThumbnailParams, Uint8List?>(_createThumbnail, ...)` 在 isolate 里解码+缩放+JPEG 重编码，**这点做对了**；
- `_generateThumbnail`（133-155）先 `await sourceFile.readAsBytes()` 把**原图整张读进主 isolate 内存**再传给 `compute`（`Uint8List` 跨 isolate 会拷贝/转移）→ 峰值 = 原图 bytes × 2；一张 8MB JPEG 就是 16MB，并发 3 个（`_maxConcurrentPreloads = 3`，第 34 行）就是 48MB。
- 改法：在 isolate 里直接 `File(path).readAsBytesSync()`（`_createThumbnail` 已有 isolate 环境，路径字符串可发送），**不要把原图字节跨 isolate 传**：
```dart
// _ThumbnailParams 改成 {path, width, height}
Uint8List? _createThumbnailFromPath(_ThumbParam p) {
  final bytes = File(p.path).readAsBytesSync();   // isolate 内部读
  ... // 解码/缩放/编码
}
```

### P2-8｜目标系统（`goal_service.dart`）：`_calculateCurrentStreak` 是 365 次「按日期全表扫描」
```dart
// lib/services/goal_service.dart
249:  static Future<int> _calculateCurrentStreak() async {
253:    for (int i = 0; i < 365; i++) {                       // ★ 最多 365 次循环
255:      final dateStr = '${date.year}-...';
256:      final diaries = await DatabaseService.getDiariesByDate(dateStr);   // ★ 每次 O(N) where + sort
258:      if (diaries.isNotEmpty) { streak++; } else if (i > 0) { break; }
265:    }
267:  }
```
- 每次 `getDiariesByDate`（`database_service_web.dart:415-422`）= 全部日记 `where(d.date == date)` + `toList()` + `..sort(createdAt)` → **O(N) + O(k log k)**。连续记录 X 天时循环 **X+1 次** → **O(X·N)**；X=365、N=1000 → **365,000 次日期字符串比较 + 365 次 List 分配 + 365 次 async 调度**。叠加 `_calculateStreakDays`（217-245，内部又调一次 `getAllDiaries()`）。
- 触发：`goal_provider.dart:27` `getCurrentGoal()` → `getGoal()` → `_updateProgress()`（`goal_service.dart:177-215`）→ 第 197/208 行调 `_calculateStreakDays` / `_calculateCurrentStreak`。**每次打开目标卡/写日记后刷新都会跑**（`custom_goal_card.dart` / `goal_progress_card.dart` 在时间线里）。
- `getGoalHistory`（270-285）又是 12 次 `getGoal`，每次 `_updateProgress` → **12 × 365 次扫描**（若每个都算 streak）→ 最坏 4000+ 次 O(N) 扫描。
- 改法（一次性）：
```dart
static Future<int> _calculateCurrentStreak() async {
  final diaries = await DatabaseService.getAllDiaries();   // 只取一次
  final dates = diaries.map((d) => d.date).toSet();        // Set 查询 O(1)
  var streak = 0; var cur = DateTime.now();
  for (var i = 0; i < 365; i++) {
    final s = _fmt(cur);
    if (dates.contains(s)) { streak++; cur = cur.subtract(const Duration(days: 1)); }
    else if (i > 0) break;
  }
  return streak;
}
```
- 风险：`_updateProgress` 被多处调用，改成单次加载后要注意别在循环里重复调用（应把 diaries 作为参数传入）。

### P2-9｜`milestone_service.dart`（低风险，仅记录）
- `checkMilestone`（88-110）遍历 8 个里程碑配置 + SharedPreferences 读写，O(1)，无问题。
- `getNextMilestone`（112-125）、`getUnlockedMilestones`（127-133）都是小集合遍历，OK。
- **唯一注意**：`checkMilestone` 被 `main_screen.dart:311`（启动 2 秒后）和 `write_diary_screen.dart:804`（每次保存）各调一次，重复；建议合并（与 P0-5 同一处改造）。

### P3-1｜死代码清理：`preloadFonts()` + `_loadChineseBoldFont()`（crosscheck A1 新增）
`lib/services/pdf_export_service.dart`
- `preloadFonts()`（`:22-43`）**全仓库无任何调用者**（已 grep `lib/`、`test/`、`tool/`；只命中定义处 `:22` 与无关的 `font_download_service.dart:313 preloadFontsFromAssets`）。
- 其内部唯一调用 `_loadChineseBoldFont()`（`:31`）→ 所以 `_loadChineseBoldFont()`（`:177-239`，含第 **187** 行第二次 `rootBundle.load` 24MB + 第 **190** 行 `pw.Font.ttf`）**在实际导出路径上从未执行**。
- **结论**：这不是内存问题（本来就 0 次执行），是**死代码**。删了无运行时收益，但不删有风险 —— 将来任何人给 `preloadFonts()` 接线，就会立刻多付 24MB 解析 + 一轮 glyph 表构建。
- 改法：删 `preloadFonts()`（或改成 `Future<bool> preloadFonts() async => _loadChineseFont() != null;` 只预载正常字重），`_loadChineseBoldFont()` 保留但标 `@Deprecated` / 注释说明「勿接 preloadFonts，会重复解析 24MB」。
- 顺带：`_chineseBoldFont` 字段本身可留（`:17` 声明、`:34` 已有 `_chineseBoldFont = _chineseFont` 兜底）。

### 数量事实核对（避免沿用文档旧数字）
> **计数口径说明（Lead 复核后统一）**：
> - 「徽章数」一律取 **`_allBadges` 列表内去重后的 `id` 数 = 79**。全文搜 `Badge(` 会得到 **93 处**，其中包含 `BadgeUnlockDialog` / `BatchBadgeUnlockDialog` / `_buildBadgeItem` 等**非列表位置**，不是徽章数量。本报告与附录一律用 **79（去重 id 数）**。
> - 「扭蛋奖励数」取 `_allRewards` 列表内 `GachaReward(` 条目数 = **97**。

| 项目 | 文档/需求说的 | 实际（本次 grep 计数） |
|---|---|---|
| 徽章 | 84 个 | **79 个（去重 id 数口径）**；`Badge(` 字面量 93 处含对话框等非列表用法，**非**徽章数 |
| 扭蛋奖励 | 80 个 | **97 个**（`gacha_service.dart` 的 `_allRewards` 区间 113-957 行内 97 个 `GachaReward(`） |
| 成语库 | — | **797 条字面量 / 765 条唯一**（`text_analysis_service.dart:8-153`，内部有重复：万紫千红、一丝不苟、画蛇添足等 32 条重复） |
| 情绪关键词（sentiment） | — | 积极 **55** / 消极 **66** / 强度修饰 **23** |
| 情绪关键词（badge） | — | `_emotionKeywords` 8 个 key 共 **1781 条**；`_positiveWords` **231**；`_negativeWords` **26**；`_positiveEmotionKeywords` **227** |
| PDF 字体 | — | `NotoSerifCJKsc-VF.ttf` = **23.97MB**（24,540.2KB） |

---

## 闪退风险 Top 3（内存峰值路径）

### 🥇 1. PDF 导出（`data_management_screen.dart:1171` → `pdf_export_service.dart`）
**峰值 = 字体单份 (~36~60MB) + 全部图片原始字节 (数百 MB ~ GB) + 输出 PDF 字节；单篇 20 图即可崩（~960MB）**
- 触发：数据管理 → 导出 PDF；**日记越多、图片越多越危险**，导出 200+ 篇带图日记在 4GB 中端机上必然 OOM。
- 关键行：`pdf_export_service.dart:356`、`:507`（`readAsBytes` 原图直喂 `MemoryImage`；`exportSingleDiary` **无 take 上限**）、`:98-100`（字体，**仅 1 份**）、`:464-467`（`pdf.save()` 整本序列化）。
- 立即止血：**图片 `compute` 缩到 1200px + 给 `exportSingleDiary` 加 `take(4)`**。
- ⚠️ crosscheck A1 更正：原「删 `_chineseBoldFont` 独立加载省 70~120MB」**不成立**（其唯一入口 `preloadFonts()` 无调用者，本来就不跑），见 P3-1 死代码清理。

### 🥈 2. 云同步图片包（`data_management_screen.dart:717-760` → `cloud_sync_service.dart:1138-1214`）
**峰值 ≈ 主 isolate 3.7S / 进程 4.7S（S = 总图片原始字节；5 份存活物见 P0-4 机制表）**
- 触发：数据管理 → "同步图片"（确认框里其实已经警告"可能需要较长时间"）。
- 关键行：`:1162`（单个 `Archive` 装全部）、`:1172-1176`（字节挂进 archive）、`:1192`（**`Archive` spawn 给编码 isolate → 深拷贝 +1S**）、`:1200`（`Uint8List.fromList` 再拷一次 → +1Z）。
- 立即止血：**分卷**（每卷 ≤20MB）或 `ZipFileEncoder` 流式落盘。

### 🥈 2.5. 全屏看大图（`OriginalImage` 无 `cacheWidth`）——最容易被忽略的一条
**单张 4000×3000 相机原图解码 = 4000×3000×4B = 48MB，Flutter `ImageCache` 默认上限 100MB → 滑 2~3 张就 OOM**
- 触发：日记详情页看大图（`diary_detail_screen.dart:1227`）、统计详情页"照片回忆"（`stats_detail_screen.dart:1243-1246` → `useOriginal: true`）。
- 关键行：`image_cache_service.dart:536-543`（`Image.file(File(path))` 无 `cacheWidth`）、`:629-634`（`PreviewImage(useOriginal:true)` → `OriginalImage`）；`PageView` 默认预载相邻页 + `Hero` 会让 2~3 张原图同时在 cache 里。
- 立即止血：给 `OriginalImage` 的 `Image.file` 加 `cacheWidth: 1200, cacheHeight: 1600`（见 P2-7 代码片段）。
- 附加：`PlatformImage` 的 `cacheWidth/cacheHeight`（`platform_helpers.dart:21-22`）**从未传给 `OptimizedCachedImage`**（第 63-69 行），所有调用方以为在限尺寸其实没生效；且 `PlatformImage` build 里每个 widget 都发 `FutureBuilder(File(path).exists())`，`OptimizedCachedImage` 内部又 `exists()` 一次 → 双倍 stat。

### 🥉 3. 存储层写放大 + 写日记保存后的徽章/里程碑检查（`database_service_web.dart:270-280` + `write_diary_screen.dart:792-854`）
**峰值不高（~10-20MB），但 CPU/IO 峰值导致 ANR 型"假闪退"，且是"保存一篇日记卡 1-3 秒"的真凶**：
- **写放大（最重）**：`_saveDiaries()` 对全部 N 篇重跑 AES（2000 次 CBC）→ `jsonEncode`（3-5MB）→ `setString` 全量落盘；再 `_updateMetadata()` 又跑一遍全量 `wordCount`（N 次 RegExp）+ 第二次全量写盘。1000 篇 ≈ **300ms~1s/次保存**；
- `_checkHiddenBadges` 全量 `wordCount`（1000 次 RegExp 编译 + 1000×800 char 替换）≈ 50~200ms；
- 79 个徽章 × 最坏 79 次 `unlockBadge` × 3 次 `SharedPreferences` 写；
- `Navigator.pop` 在 `await _checkMilestoneAfterSave()` **之后**（`write_diary_screen.dart:653-656`）→ 用户按保存后页面要卡住才退出。
- 关键行：`database_service_web.dart:270-280`、`:329-339`、`:344-358`、`diary_provider.dart:222`、`badge_service.dart:2184-2186`、`diary.dart:108-121`。

> **补充第 4 条（非内存但同样致命，且是"频繁闪退"的架构级解释）**：存储层用 SharedPreferences 存全量日记 JSON。Android `SharedPreferences` 对超大 XML 是**全文件重写 + fsync**，3~5MB 级数据每次保存 **100~300ms**；启动时要把整份 XML 解析成内存 Map（再叠加我们自己的解密副本）→ 常驻内存约 2×XML 大小，低端机（heap 192~256MB）叠加首页 20 篇图片预览后极易触发 `OutOfMemoryError`。长期必须切回 `sqflite` —— `database_service_native.dart` 已经写好（含 15 版 schema 与 JOIN/GROUP BY 查询），只是 `database_service.dart` 没 export 它。
