# 数据层审计：Android 真实存储 = SharedPreferences + 全量 JSON

> 审计员：data-perf-2 ｜ 日期：2026-10-28 ｜ 方式：纯静态阅读（未运行 flutter/dart analyze/pub get）
>
> 结论先行：**这不是"查询慢"，而是"每次读写都把全部日记重新加密、重新序列化、重新落盘"**。
> N=1000 时用户点一次"保存"，UI 线程要背 1~3 秒；N=5000 时是 5~10 秒 + 几十 MB 峰值内存，
> 已经进入 ANR/OOM 区间——这与"频繁闪退"的反馈一致，而不是索引问题。

## 0. 已采纳的前提（Lead 已核实，本文不重复论证）

1. `lib/services/database_service.dart` 仅 3 行：`export 'database_service_web.dart';`
   → Android 上真实实现是 **prefs + 内存全量列表**；`database_service_native.dart`（sqflite，v15）**无任何生产 import，是死代码**。
2. 全量数据在 `_diaries` / 单键 `diaries_data`（一个 JSON 字符串）；冷启动 `_loadData():91-232` 一次性 `jsonDecode` 全部 → `_decryptDiariesSync():235-267` 逐篇逐字段 `await` 解密。
3. 每次写：`_saveDiaries():270-280` = `Future.wait(全部 N 篇重新 AES 加密)` + `jsonEncode(全量)` + `setString(全量)`；`_updateMetadata():331-339` 再 fold 一遍全量算字数 + **第二次全量 setString**。
4. `getAllDiaries():379-382` / `getDiariesPaged():388-402` / `getRecentDiaries():405-412` 均为 `List.from(_diaries)..sort(...)`；`getDiariesByDate():415-423` 为线性 `where`。
5. `shared_preferences_android` legacy 的 `setString` = `editor.putString(...).commit()` → **平台主线程同步 fsync**；`getInstance()` 首次把**所有键**全部载入内存。
6. `encryption_service.dart`：AES-256-CBC 纯 Dart（`pointycastle`/`encrypt`），在主 isolate 跑；`_cachedKey` 有缓存（这点不误报）；每次调用 `new Encrypter` + base64 编解码。
7. `models/diary.dart:102-105` `imageList` 每次 `split(',')` 新建 List；`:108-121` `wordCount` 每次 **new RegExp + replaceAll 全文**（全仓库 `.wordCount` 17 处、`.imageList` 38 处）。
8. `diary_provider.dart`：`addDiary():207-229` 后 `loadRecentDiaries((page+1)*20)`；`updateDiary():232-251` 后 **全量 `loadDiaries()`**；getter `getDiariesByDate:39-41`/`datesWithDiaries:44-46`/`favoriteDiaries:49-51`/`totalWordCount:54-56` 每次调用都新建 List/Set 并遍历。

---

## P0 速览（四节各一条，详细见正文）

| 节 | P0 条目 |
|---|---|
| **A** | 写一篇的代价与 N 成正比：**2+len(tagIds) 次主线程同步 fsync + 全库重加密**。N=1000 保存一次 1.3~1.8s，N=5000 必 ANR。这是"卡顿"的第一性原理，不是索引问题。 |
| **B** | 加索引**救不了分页**：`getDiariesPaged` 每页都全量重排，必须同时改成 `LIMIT/OFFSET`（深层用 keyset）；搜索类**普通索引完全无效**，只能 FTS5（且需 trigram + SQLite≥3.34 探测降级）。 |
| **C** | Day 1 不是改 export。先补 **5 个**缺失 API（另实测还缺 8 个）并统一 `import*` 的 upsert/skip 语义，否则切过去第一天就 `NoSuchMethodError` + 云同步静默丢数据。 |
| **D** | 两条最值钱：D1 `_saveDiaries` 改增量分键、D9 合并 tagSystem 写盘。两者合计把"保存一篇 1~3s"降到 **<100ms**，且不改存储引擎，1~2 天可上线。 |

---

## A. 量化模型（本文最重要的一节）

### A.1 参数与假设

| 符号 | 含义 | 取值（保守估计） |
|---|---|---|
| N | 日记篇数 | 200 / 1000 / 5000 |
| L | 平均正文字符数 | 300 汉字 ≈ 900 UTF-8 字节（另加标题 15 字 ≈ 45 字节） |
| I | 平均图片数 | 2（列表不读图，但 `imageList` 被反复 split） |
| 每篇 prefs 体积 | base64(密文) 后 | ≈ **2.0 KB/篇**（content 912B→base64 1216B + title + 字段名） |
| 总 blob | `diaries_data` 字符串 | N=200→0.4MB；1000→2MB；5000→10MB |
| 加解密吞吐 | 纯 Dart AES-CBC，Android arm64 AOT，**无硬件 AES 指令** | **3~8 MB/s**（按机型取中位 4 MB/s）→ 每篇 **0.3~0.8 ms** @L=300；L=1000 约 1~3ms；L=3000 约 3~8ms |
| jsonEncode/Decode | base64 大字符串 map | ≈ 100 ms/MB（decode 与 encode 同量级） |
| prefs `setString` | `commit()` 同步 fsync | ≈ **40 ms/MB**（Android 中低端机），即 2MB≈80ms、10MB≈400ms |
| Dart 字符串开销 | base64 全 ASCII → 单字节存储；解密后中文 → UTF-16 2B/字 | 冷启动峰值 ≈ **4~6× blob** |

**成本公式（可直接用于估算任何操作）**

```
冷启动   T ≈ t_prefs_load(blob) + 100ms/MB × blob + N × 1ms
写一篇   T ≈ N × 1ms + 80ms/MB × blob + 40ms/MB × blob + (N × 0.05ms 字数统计) + 2 次 commit
删除一篇 T ≈ 同上（_saveDiaries + _saveDiaryTags 两次全量写） + N × 0.05ms
```

注意：**写一篇的代价与 N 成正比，与"改了多小一段文字"完全无关**。这是本 App 卡顿的第一性原理。

**但真正的写盘次数比 `_saveDiaries` ×2 更多**（链路已闭环）：一次「保存日记」实际是

```
2 + len(tagIds) 次同步 commit()
  = 1× insertDiary → _saveDiaries（全量 N 篇重加密+全量 setString）
  + 1× insertDiaryTagsV3 → _saveDiaryTagsV3（全量 setString）
  + len(tagIds)× TagSystemService.incrementTagUsage → recordTagUsage
          → _saveTagSystem（每次把整个 tagSystem JSON 全量重写）
  + 1× Provider.loadRecentDiaries → 又一次全量 sort 拷贝（纯 CPU，落盘之外）
```

带 3 个标签的一篇日记 = **5 次主线程同步 fsync**；N=1000 时约 5×80ms=400ms 光落盘，
再加 2 次全库加密 + 2 次 jsonEncode。**这个乘数才是"保存一次卡 2 秒"的完整解释。**

另：`_encryptDiaryMap` 里的 `isEncrypted(...)` 短路 **对内存明文不生效** —— `_diaries`
存的是解密后的明文，所以每次写都是**真加密遍历全库**，不是空转。

### A.2 七个关键操作（N=200 / 1000 / 5000）

| 操作 | 实际做的事（代码位置） | 复杂度 | N=200 | N=1000 | N=5000 |
|---|---|---|---|---|---|
| **冷启动首屏** | prefs 全键载入 → `jsonDecode` 全量 → `_decryptDiariesSync` 逐篇 await 解密 title+content（`web:91-267`），期间平台主线程也被 prefs 占着 | O(N·L) | **0.3~0.5 s**，峰值 ~2MB | **1.4~2.0 s**，峰值 ~10MB | **7~12 s**，峰值 **~50MB**（低端机 OOM 高危） |
| **新增一篇** | 全量 N 篇重新 AES 加密 + jsonEncode + 2 次全量 setString（`web:270-280, 331-339`）；再由 provider `loadRecentDiaries` 全量排序（`provider:222`） | O(N·L) | **0.25~0.4 s** | **1.3~1.8 s**（ANR 边缘） | **6~9 s**（必 ANR，首页无响应） |
| **编辑一篇** | 同上 + `deleteDiaryTagsV3`/`insertDiaryTagsV3` + provider **全量 `loadDiaries()`**（`provider:244`） | O(N·L) | 0.3~0.5 s | 1.5~2.0 s | 7~10 s |
| **删除一篇** | `_saveDiaries` + `_saveDiaryTags`，**两次全量加密落盘**（`web:525-531`） | O(N·L) | 0.3~0.4 s | 1.4~1.9 s | 6~9 s |
| **切到统计页** | `getAllDiaries` 全量排序（`stats:98`）+ 对每篇 `await getTagsByDiaryId`（`stats:148`，内部 `_diaryTags` 全表扫 + `tagIds.contains`，`web:725-735`）+ N 次 `wordCount` + `getMoodDistribution` 再扫一遍 | **O(N²)** | 15~30 ms | **60~120 ms** | **0.5~1.5 s** |
| **日历翻月** | 42 个格子每格 `getDiariesByDate`（每次 `List.where` 全量线性扫 + 排序，`web:415-423`）+ 每次 build 重建 `datesWithDiaries` Set | O(42·N) | 2~5 ms | **8~20 ms（掉帧）** | **40~100 ms/次 build（明显卡顿）** |
| **搜索一次** | `getAllDiaries` 全量排序（`search:77`）+ **每个按键**对 N 篇 content 做 `toLowerCase().contains()`（无防抖，`diary_search_enhanced_screen` onChanged）→ 等价每键 O(N·L) 字符串分配 | O(N·L) | 5~10 ms/键 | 10~25 ms/键 | **30~80 ms/键**（输入直接掉字/卡死） |

### A.3 内存峰值与闪退的直接关联

- 冷启动峰值 ≈ 4~6× blob：N=5000 时 40~60MB **仅用于把数据读进来**，还没算 Flutter 自身（~100~150MB）、图片解码、WebView。Android 2~3GB 设备上 `OutOfMemoryError` 概率高。
- 写盘峰值同时持有：N 篇原始 `Map` + N 篇加密 `Map`（各 ~2KB 字符串）+ 整个 jsonEncode 结果字符串 + prefs 内部副本 → N=5000 约 **3~4×10MB**。
- **写放大**：N=1000 时写一次日记 = 4.8MB 落盘 × 2 次 = 近 10MB；N=5000 时约 48MB/次。这不是"慢"，是**闪存寿命 + 主线程 fsync**双重问题。
- 与另一个报告的交叉确认：`.perf-analysis/startup-native.md` 把"prefs 体积"列为启动第一枪，与本节公式独立吻合。

---

## B. 索引 / 查询 miss 清单（前提：切回 native SQLite 才谈得上索引）

### B.1 高频查询 → 需要的索引

| 查询 | 调用点 | 现状（prefs 实现） | 推荐 DDL | 理由 |
|---|---|---|---|---|
| `getAllDiaries()` 列表首页 | **15 处**（provider/stats/smart_recall/gacha/goal/auto_backup…） | 全量排序 O(N log N) + 无 LIMIT 概念 | `CREATE INDEX idx_diaries_date ON diaries(date DESC, created_at DESC);` | 覆盖 `ORDER BY date DESC` 与后续分页 |
| `getDiariesByDate(date)` | 3 处（`calendar_screen:421,713,1437,1770`、`stats:1449`） | `where(d.date == date)` 线性扫 | `CREATE INDEX idx_diaries_date_created ON diaries(date, created_at DESC);` | 日历每格/详情页高频，单条索引即可消除 42×N |
| `getDiariesByMonth(y,m)` | `web:424`；native 用 `date LIKE ?` | 线性扫 | 改写成范围查询 `date >= 'YYYY-MM-01' AND date < 'YYYY-(MM+1)-01'` + 复用 `idx_diaries_date` | **`LIKE 'x%'` 默认大小写不敏感，SQLite 不会走索引**；范围查询才会 |
| `getDiariesPaged(page,size)` | 5 处（`paged_diary_list:85,112,594,618`、`web:388`） | 每次全量 sort 再 sublist | `SELECT ... ORDER BY date DESC LIMIT ? OFFSET ?` + `idx_diaries_date` | **⚠️ 只加 date 索引救不了分页**：索引只消除排序，`OFFSET k` 仍要从头数 k 行。分页必须同时改 SQL（LIMIT/OFFSET），深层再改 keyset：`WHERE (date,created_at) < (?,?) ORDER BY date DESC,created_at DESC LIMIT ?` |
| `getRecentDiaries(limit)` | 1 处（`provider:82`） | 全量 sort 再取前 N | `ORDER BY date DESC LIMIT ?` | 同上，且首页只该读这么多 |
| `getTagsByDiaryId(diaryId)` | 2 处（`stats:148`、`provider:357`） | `_diaryTags` 全表扫 + `_tags.where(tagIds.contains)` | `CREATE INDEX idx_diary_tags_diary ON diary_tags(diary_id, tag_id);` 与 v3：`CREATE INDEX idx_diary_tags_v3_diary ON diary_tags_v3(diary_id, tag_id);` | 统计页 N+1 里最痛的一环；有索引后单查 O(logD) |
| `getDiariesByTagIdV3(tagId)`（`tag_diaries_screen:49`、`tag_system_service:317`） | 2 处 | 全表扫 `diary_tags_v3` 再 `contains` | `CREATE INDEX idx_diary_tags_v3_tag ON diary_tags_v3(tag_id, diary_id);` | **native `_onCreate` 里完全没有 `diary_tags_v3` 的任何索引**，切过去照样全表扫 |
| `getMoodDistribution()` | 1 处（`stats_screen:127`） | 遍历 N 篇 | `CREATE INDEX idx_diaries_mood ON diaries(mood_id);` 或直接 `SELECT mood_name, COUNT(*) ... GROUP BY mood_name` | 聚合走索引，不必取回正文 |
| 收藏列表 | provider getter | `where(isFavorite)` | `CREATE INDEX idx_diaries_fav ON diaries(is_favorite) WHERE is_favorite = 1;`（SQLite 3.9+ 部分索引） | 只索引真收藏行，体积小 |
| 统计"总字数/篇均字数/最长日记" | `stats:118`、`text_analysis:392,402,406`、`badge_service:2185`、`goal_service:190` | **每次都解密全部正文**才能算字数 | 加材料化列 `word_count INTEGER` + `CREATE INDEX idx_diaries_word_count ON diaries(word_count DESC);`，写入时算一次 | **最大的单点优化**：字数统计不需要正文 |
| 搜索（`LIKE '%kw%'` / 客户端 `contains`） | `diary_search_enhanced_screen:77`、`web:1083,1195` | 全量解密后客户端 `contains` | **普通索引无效，必须 FTS5**，见 B.3 | content/title 是加密串，`LIKE`/`B-tree` 索引都命中不了；且 `LIKE '%x%'` 前导通配天然全表扫 |

### B.2 现有 native schema 的两个硬伤（切之前必须补）

1. `_onCreate`（`native:58-132`）**只有主键索引**，没有一条业务索引 —— 也就是说"切回 SQLite"并不会自动解决卡顿，`getDiariesByDate` 依然会全表扫（虽然比 JSON 快 1~2 个量级）。
2. 缺 `word_count` 列 → `native:538-541 getTotalWordCount()` 仍是 `getAllDiaries()` + 逐篇解密 + `.wordCount` getter，等于把 prefs 的毛病原样搬过去。

### B.3 搜索：普通索引无效，只能 FTS5（★ 复核员点名的易漏点）

**先说结论：不要给 `content` / `title` 建普通 `CREATE INDEX`。** 两个理由，任一条都足以判死刑：

1. 列里是 AES 密文（base64），明文的搜索词在密文里**不存在**，索引键完全对不上；即使解密后建索引，也无法在 SQL 层比对。
2. 即便改成明文，搜索语义是**子串**（`contains`），B-tree 索引只能做前缀，`LIKE '%kw%'` 必然全表扫。

正确做法：**建 FTS5 虚表 + 在写入时同步维护**。

```sql
-- 中文没有空格分词，unicode61 切不开"今天天气很好"，
-- 必须用 trigram 分词器（SQLite ≥ 3.34）才能做子串检索
CREATE VIRTUAL TABLE diary_fts USING fts5(
  title, content,
  content='',                 -- 外部内容表，不重复存储，省一半空间
  tokenize='trigram'
);
```

要点与坑：

- **trigram 分词器要求 SQLite ≥ 3.34**。sqflite 在 Android 上用的是**系统 SQLite**：Android 10 (API 29) 是 3.22、Android 12 是 3.32、**Android 14 才 ≥3.44**。也就是说大面积设备上 `tokenize='trigram'` 会直接建表失败 → **必须做版本探测 + 降级**（低于 3.34 就退回"后台 isolate 全量扫"，见下）。
- 维护时机：`insertDiary`/`updateDiary`/`deleteDiary` 在**同一事务**内 `INSERT/UPDATE/DELETE diary_fts`，否则同步/备份恢复后索引与主表不一致。
- 查询：`SELECT rowid FROM diary_fts WHERE diary_fts MATCH ? ORDER BY rank LIMIT 50` → 再按 rowid 回表 + 解密。**只解密命中的那几十条**，而不是全库。
- 加密冲突（必须由产品拍板）：FTS5 要能匹配明文，索引里就得存明文 → 与"日记本地加密"冲突。三个选项：
  - **FTS5 + 明文索引**（搜索最好用，但明文落盘，等于削弱加密承诺）→ 若产品接受"搜索索引不加密"，选这个；
  - **FTS5 + 仅存分词 token**（只存 token 不存原文，可从 token 反推部分内容，安全性居中）；
  - **不做 FTS**：后台 isolate 分批 `SELECT id,title,content` → 解密 → `contains` → 只回传 id。O(N·L) 但不在 UI 线程，N=5000 约 300~800ms，配合 300ms 防抖 + 2 字下限可接受。
  > 本审计的推荐：**短期先做第三条（零 schema 变更、可立即上线），Phase 1 迁移时再按产品决策上 FTS5**。

### B.4 列表页是否应该裁掉 `content` / `images` 大字段？

**应该，而且是第一优先级的读路径改造。**

- 列表卡片需要：`id,title,date,mood_*,is_favorite,created_at,word_count,images(缩略图路径)`，**不需要 content**。
- 现状：`getRecentDiaries` 返回完整 `Diary`（含 900 字正文），每次冷启动/新增后都要为这 20 条解密正文。
- 改造：列表用 `DiarySummary`（或 `Diary` 的 `content: null` + `wordCount` 字段）+ `SELECT id,title,date,...,word_count,images`，**详情页打开时再单条解密 content**。
- 收益：冷启动解密量从 `N×1ms` 降到 `min(20,N)×title(≈0.1ms)`；`getTotalWordCount` 从"解密全库"降到一次 `SUM(word_count)`。

---

## C. 迁移方案：SharedPreferences + JSON → native sqflite

### C.0 前置：**第一步不是改 export**

`database_service_native.dart` 是**从未被编译过的死代码**。用成员级 diff 比对 `web`(97 个 static 成员) vs `native`(76 个)：

```powershell
# 复现（已实际执行）
function Members($p){ $t=Get-Content $p -Raw -Encoding UTF8
  [regex]::Matches($t,'static\s+(?:Future<[^;{]*?>|void|int|List<[^;{]*?>|Map<[^;{]*?>|Set<[^;{]*?>|bool|String\?)\s+(\w+)\s*[(<{]')
  | % { $_.Groups[1].Value } | Sort-Object -Unique }
Compare-Object (Members 'lib/services/database_service_web.dart') `
               (Members 'lib/services/database_service_native.dart') |
  ? SideIndicator -eq '<=' | % { $_.InputObject }
```

**第一批（P0，Lead 已 verify native 命中为 0）—— 补这 5 个才谈得上切导出：**

| # | 缺失 API | 外部调用点 | 危害 |
|---|---|---|---|
| 1 | `importDiaryTags(List<Map>)` | `cloud_sync_service:1576` | 云同步恢复标签关系时直接 `NoSuchMethodError` |
| 2 | `importDiaryTagsV3(List<Map>)` | `incremental_sync_service:173` | 增量同步整条链断 |
| 3 | `restoreDiaries(List<Diary>)` | `auto_backup_service:210` | 本地备份恢复失败 |
| 4 | `restoreMoods(List<Mood>)` | `auto_backup_service:215`、`incremental_sync_service:156` | 同上 |
| 5 | `restoreTags(List<Tag>)` | `auto_backup_service:220`、`incremental_sync_service:162` | 同上 |

**但我这边的成员级 diff 发现实际缺 13 个**（除上 5 个外还有 8 个，同样命中真实调用点，漏了切过去一样崩）：

| # | 缺失 API | 外部调用点 | 备注 |
|---|---|---|---|
| 6 | `getAllDiaryTags` | **4 处**（`data_management:696,741`、`write_diary_screen:621`、`incremental_sync`） | 数据管理与写日记页都依赖 |
| 7 | `getAllDiaryTagsV3` | `incremental_sync_service:46` | 增量同步取本地基线 |
| 8 | `getDiaryTagIdsV3` | 1 处 | v3 标签回读 |
| 9 | `getDiaryIdsByTagIdV3` | 0（API parity 保留） | 可延后 |
| 10 | `getDiariesByTagId(int)` | `tag_diaries_screen:52` | native 只有 `...ByTagIdV3(String)`，签名都不匹配 |
| 11 | `getDiariesPaged({page,pageSize})` | **5 处**（`paged_diary_list:85,112,594,618`） | **不补则整个列表页不可用** |
| 12 | `getRecentDiaries({limit})` | `provider:82` | **不补则首页不可用** |
| 13 | `getDatesWithDiaries` | 0（parity 保留） | 日历页可受益 |

**另有 3 处签名/语义不一致（比缺失更危险 —— 能编译、但行为悄悄变了）：**

- `importDiaries(List<Diary>)`：web 是 `Future<void>` 且**按 id upsert（覆盖）**；native 是 `Future<int>` 且**已存在则跳过**。一旦切换，`cloud_sync_service:1540` 的行为从"覆盖"变"忽略" → **远端修改永远同步不进来**（静默数据丢失，最难排查）。
- `importMoods` / `importTags`：同上，同为 upsert vs skip。
- `importDiaries` 在 web 里是 **O(N²)**（`web:452-472` 的 `indexWhere` 嵌套在 for 里），native 版是 N 次单查 —— 迁移时顺手修成 Batch 单事务。

**P0 结论：迁移的 Day 1 产物不是 "改 export"，而是「编译门 + 契约测试 + 13 个 API 补齐 + 3 处语义对齐」。**

### C.1 阶段划分（可分批上线、可回滚）

#### Phase 0（3~5 天，零用户可见变化）
1. 新建 `test/database_service_native_contract_test.dart`，**import native 文件**并把 13 个 API 以 tear-off 形式引用（`_contract() { DatabaseService.getRecentDiaries; ... }`），强制 `dart analyze` 检查死代码。这是唯一能让死代码被工具链看见的低成本手段。
2. 用 `sqflite_common_ffi`（pubspec 里已注释，需加 dev_dependency）跑 native 真实读写单测：建库/迁移到 v15/插入/查询/级联删除/加密往返。
3. 补齐 13 API + 统一 import 语义（建议统一为 **upsert by id**，与 web 现状一致，避免云端行为漂移）。
4. 顺手加两列：`word_count INTEGER`、`is_encrypted` 语义统一（见 C.4）。
5. 补 B 节全部 `CREATE INDEX`（放 v16 升级脚本，不建在 `_onCreate` 里，避免老库漏建）。
6. 若导出暂不切：本阶段所有改动只影响死文件 + 测试，风险≈0。

#### Phase 1（2~3 天）：运行时开关式双实现（比裸 conditional export 更安全）

裸 conditional export 的写法：

```dart
// lib/services/database_service.dart
export 'database_service_native.dart'
    if (dart.library.js_interop) 'database_service_web.dart';
```

要点：默认分支写第一个（非 web 环境）；web 判 **`dart.library.js_interop`** 而非 `dart.library.html`（后者在 wasm 下为 false，未来开 wasm 会炸）。**但这是编译期硬切，线上无法回滚**，所以推荐：

```dart
// lib/services/database_service.dart  —— 门面（facade），全部调用点零改动
import 'db_impl_native.dart' if (dart.library.js_interop) 'db_impl_web.dart';
// db_impl_*.dart 各自 export 一个 class DatabaseServiceImpl { static ... }
// 门面按运行时开关转发：prefs 里 db_engine = 'prefs' | 'sqflite'
```

- `db_impl_native.dart` 里可以**同时 import web 实现**做兜底（`database_service_web.dart` 只依赖 shared_preferences，Android 上也能跑）→ 得到**运行时回退能力**：设置页/远程配置写 `db_engine=prefs` 即刻回退，不用发版。
- 反过来不行（web impl 不能 import sqflite），所以兜底方向只能"native → web"。

#### Phase 2（1~2 天）：一次性数据迁移器

```
读取 prefs 各键（diaries_data / moods_data / tags_data / diaryTags / diaryTagsV3 /
anniversaries / selfTalk* / quickNotes / courses / semesterConfig）
  → 沿用 EncryptionService 解密（与读取路径同一套，不新写解密逻辑）
  → 打开临时库 diary_v15_migrating.db，单事务 + Batch（每 100 条 commit 一次）
  → 逐表 insert（显式 id）
  → 校验：
       · 行数：diaries/moods/tags/diary_tags/diary_tags_v3 各自 == prefs 数组长度
       · 字数：SUM(word_count) == prefs metadata['totalWordCount']
       · 日期：SELECT date 集合 == metadata['uniqueDates']
       · 抽样 20 篇（含最新/最旧/收藏各 1）逐字段比对（title/content/date/images/
         mood_id/mood_name/is_favorite/created_at/updated_at）
  → 全部通过：close → rename 临时库为目标库 → prefs 写
       migration_v1_done=1 / migration_v1_at=<ts> / db_engine='sqflite'
     **不删除任何 prefs 键**（回滚保险）
  → 任一失败：删临时库 + 上报 + 继续用 prefs（用户无感）
```

细节要求：
- 迁移在 **首帧之后**（`addPostFrameCallback`）+ **进度弹窗**（"正在升级本地数据库 3/7，请勿退出"），N=5000 时需要 10~30s。
- **幂等**：目标库已存在且 `migration_v1_done==1` → 跳过；临时库残留 → 直接删掉重建。
- 迁移完成后再校验一次"冷启动用 sqflite 读到 N 篇，第一篇 content 与 prefs 解密值一致"，通过才切 `db_engine`。

#### Phase 3（观察 1~2 个版本后）：清理
- 确认线上无回退请求 → 停止写 prefs → 再观察 → 删 prefs 大键（可留一个 `backup_until` 时间戳）。**永远不要在同一版本里既迁移又删源。**

### C.2 回滚开关
三级，从轻到重：
1. `db_engine` 运行时开关（prefs 键）：立刻回 old 实现，代价是丢失"迁移后新增的日记"→ 因此 **Phase 2/3 期间必须双写或至少对 sqflite 新写入做 prefs 增量备份**（见风险表）。
2. 远程/设置里的 `migrate_v1_enabled=false`：阻止新用户迁移，老用户不受影响。
3. 保留 `diaries_data` 原键 2 个版本：最后手段。

### C.3 上线顺序（建议）
`Phase 0` 全量发布（零风险）→ `Phase 1` 只开内部账号 → `Phase 2` 灰度 5%/20%/100%（按设备抽样，不按账号，避免同步问题）→ `Phase 3`。

### C.4 风险清单

| 风险 | 级别 | 说明与对策 |
|---|---|---|
| native 是**从未编译的死代码** | 高 | 编译门 + ffi 单测（Phase 0），否则切过去第一天就会 `NoSuchMethodError` |
| 补 API 时**漏 8 个**（不是 5 个） | 高 | 用成员级 diff 脚本做 CI 门禁，`web`/`native` 两边 static 成员名集合必须相等（私有除外） |
| `import*` 语义不一致（upsert vs skip） | 高 | 统一为 upsert；加单测：同 id 二次导入必须覆盖 |
| `is_encrypted` 语义 | 高 | 现状：写入恒置 1，读取**不看**该列、一律解密 → 历史明文行（加密失败落盘 / 早期版本）会解出乱码或抛异常。迁移时逐行 `EncryptionService.isEncrypted()` 判定并写真实值，读取路径改为 `is_encrypted==1 ? decrypt : as-is` |
| 自增 id 冲突 | 中 | 迁移用显式 id；AUTOINCREMENT 在显式插入更大 id 后会自动抬高 `sqlite_sequence`，但要**单独校验** `SELECT MAX(id)` 后再插入新日记不冲突；云同步远端 id 与本机 id 混用的问题**现状已存在**，迁移不新增风险但要回归一次 |
| `flutter test` 会选到 native | 中 | 条件导出里 `dart.library.io` 在测试 VM 为 true → 现有 164 个测试里任何碰 `DatabaseService` 的都会 `MissingPluginException`。对策：测试 `setUpAll` 里 `databaseFactory = databaseFactoryFfi`（加 `sqflite_common_ffi` dev 依赖），或 Phase 1 的门面在读 `kDebugMode` 时仍走 prefs |
| web 端 | 低 | 保留 `database_service_web.dart` 不动；条件导出确保 web 走原实现 |
| 迁移中断（用户杀进程/OOM） | 中 | 临时库 + 幂等 + 事务 + 成功后才 rename；绝不半写目标库 |
| 双实现漂移 | 中 | 成员 diff 门禁 + 同一套契约测试分别对 web/native 跑 |

### C.5 native 侧必须同时修的 3 件事（否则迁移只是"换了个慢法"）
1. `getAllDiaries():423` / `getDiariesByDate():435` / `getDiariesByMonth():452` 里 `Future.wait(maps.map(_decryptDiaryMap))` = **对 N 条无上限并发解密**，内存峰值与 web 版同源。改为：列表路径 `SELECT` 排除 content；详情路径按需单条解密。
2. 补 `word_count` 列与全部索引（B 节）。
3. `importDiaries:912` 逐条 `await getDiary` + `insert` = N 次往返；改 Batch 单事务。

---

## D. 短期止血（不改存储引擎，1~2 天可上线）

按"收益/成本"排序：

| # | 改动 | 收益 | 位置 |
|---|---|---|---|
| **D1** | `_saveDiaries` 改**增量分键**：写日记时只重写 `diaries_{id}` 单键（`setString` 单篇 ~2KB），列表顺序用一个小 `diaries_meta`（id 数组 + 时间戳）维护；`diaries_data` 仅作整库备份/迁移用 | 保存 1~3s → **<50ms**，消除 2 次全量 fsync。**第一条就该做** | `web:270-280`、`web:439-449`、`web:512-532` |
| **D2** | 加密移出主 isolate：`_saveDiaries`/`_decryptDiariesSync` 的 `Future.wait(map(encrypt))` 用 `compute` 或 `Isolate.run` 批量处理（输入/输出都是 `List<Map<String,dynamic>>`，可序列化） | 主线程加解密时间 → 0；冷启动 N=1000 从 1.5s UI 阻塞变 100ms（其余在后台） | `web:270-280`、`web:235-267` |
| **D3** | `Diary` 加**缓存字段**：`wordCount`/`imageList` 改成 `late final`（或构造函数里预计算一次存 `int? _wc`），`RegExp` 提为 `static final` 顶层常量 | 消除 17 处 `.wordCount` 的 RegExp 编译 + 全文 replaceAll；`_updateMetadata` 从 N×0.05ms 降到 ~0 | `models/diary.dart:102-121`、`web:331-339`、`provider:54-56` |
| **D4** | `updateDiary` 不要全量 `loadDiaries()`：改为 `_diaries[index] = updated` + `notifyListeners()`（数据层已返回成功）；同样 `addDiary` 的 `loadRecentDiaries((page+1)*20)` 改为头部插入 | 编辑一篇少一次 O(N log N) 排序 + 一次 prefs 全量读 | `provider:207-251` |
| **D5** | Provider getters 改**预计算索引**：维护 `Map<String, List<Diary>> _byDate`、`Set<String> _dates`、`List<Diary> _favorites`，在 `_diaries` 变更处增量更新；getter 只返回缓存 | 日历 42 格 × O(N) → 42 × O(1)；`datesWithDiaries` 不再每次 new Set | `provider:39-56` |
| **D6** | 日历页**一次性算好 42 格**：`calendar_screen` 里 `getDiariesByDate` 调用点（`:421,713,1437,1770`）改为在 build 前用 `_byDate` 生成 `Map<DateTime, List<Diary>>` 传给格子 | 翻月从 40~100ms/帧 → 1ms | `calendar_screen:418-421,713,1437,1770` |
| **D7** | 图片先兜底 `cacheWidth/cacheHeight`：`OriginalImage:505-553` 的 `Image.file` 加 `cacheWidth: (宽×dpr)`；`preloadImages` 队列 100 改为按可见窗口 10~20 | 直接降低原图解码内存 → **闪退第一止血点**（原图 4000×3000 解码约 48MB/张） | `image_cache_service:505-553`、`:187-224` |
| **D8** | 搜索加 **300ms 防抖 + 最少 2 字 + 结果截断**；`getMoodDistribution`/统计页 N+1 的 `getTagsByDiaryId` 改一次性批量 `getTagsForDiaries(ids)`（一次扫 `_diaryTags`） | 搜索从 30~80ms/键 → 一次；统计页 O(N²) → O(N) | `diary_search_enhanced_screen:77`、`stats_screen:148`、`web:725-735` |
| **D9** | 消灭"每个标签一次全量 tagSystem 写盘"：`incrementTagUsage`→`recordTagUsage`→`_saveTagSystem` 改为**内存里累加 + 合并成一次写**（或延迟到页面退出时 flush）；`insertDiaryTagsV3` 的 `_saveDiaryTagsV3` 同理 | 一次保存的 sync fsync 从 **2+len(tagIds) 次降到 2 次**，带 3 标签时省 3×~80ms | `tag_system_service.incrementTagUsage` → `recordTagUsage` → `_saveTagSystem`；`web:301-304` |

> D1 与 D2 有依赖关系：先做 D1（分键）才能让 D2 的 isolate 只处理"变更的那几篇"，否则 isolate 里仍要搬运整库。
> D3/D4/D5 可并行独立上线，彼此无冲突。
> **D1 + D9 是唯一能把"保存一篇 = 1~3 秒"降到"<100ms"的两条**，其余只优化 CPU 或读路径。

---

## E. 已验证 vs 未验证

- **已核实（有代码行号支撑）**：A 节复杂度与常量、B 节查询清单（15/3/2/5 等计数为实际 grep 结果）、C.0 的 13 个缺失 API 与 3 处签名差异、D 节全部位置。
- **估算而非实测**：A 节所有秒数（AES 吞吐、json、fsync 三个常数）—— 需要用 `Timeline`/`Stopwatch` 在 N=1000 真机包上各打一次点校准，误差预计 ±50%。
- **未覆盖**：图片冷启动解码细节（另有报告）、云同步全量 push（另有报告）、`_metadataCache` 在 D1 分键后的一致性设计。
