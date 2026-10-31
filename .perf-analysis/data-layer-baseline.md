# 数据层查询形态基线 & 最小索引集（B7 独立基线）

> **性质**：本文件不依赖 `data-layer.md`。它是复核员 startup-native 根据**自己的 task-3 全量 API 普查**（`DatabaseService.` 138 处调用 / 67 个 distinct API / ~40 个文件）反推出的「真实查询形态」，用于后续与 `data-layer.md` 的索引设计逐条比对。
> **用途**：若 `data-layer.md` 出现「加索引即可优化分页」「给 content 加索引」这类建议，用本文件即可判定为无效建议。
> 只读产出，未修改任何源码。

---

## 0. 一句话结论

**当前 Android 端根本没有 SQL 层**（`lib/services/database_service.dart` 无条件 `export 'database_service_web.dart'`，真 SQLite 实现 `database_service_native.dart` 无任何 import），所以「索引设计」在当前形态下**全部无法落地**——讨论索引的前提是先完成 P0-1 的存储层迁移。本文件给出的索引集是**迁移时必须一次性建对的清单**，不是「现在就能加的优化」。

---

## 1. 真实查询形态（按读路径调用次数降序）

统计口径：`DatabaseService.<API>` 在 `lib/` 内的全部显式调用点。次数 = 调用点数（非运行时次数）。

| 次数 | API | 语义 | 等价 SQL 需求 | 能否靠索引改善 |
|---|---|---|---|---|
| **15** | `getAllDiaries` | 全量取日记 | `SELECT * FROM diaries ORDER BY date DESC` | ⚠ 只能免掉排序（`date` 索引），**全表读无法避免** |
| **6** | `getAllMoods` | 全量心情 | 小表全读 | 不需要（数据量极小） |
| **5** | `getDiariesPaged` | 分页取日记 | `… ORDER BY date DESC LIMIT ? OFFSET ?` | ✅ **必须** `diaries(date)`，且必须真用 LIMIT/OFFSET |
| **5** | `getAllTags` | 全量标签 | 小表全读 | 不需要 |
| **4** | `getAllAnniversaries` | 全量纪念日 | 小表全读 | 不需要（若按日期查才需要） |
| **3** | `getAllDiaryTags` | 全量关联（导出/同步用） | 全表 | 不需要 |
| **3** | `getDiariesByDate` | 按日取 | `WHERE date = ?` | ✅ `diaries(date)` |
| **3** | `getQuickNoteById` | 按主键 | `WHERE id = ?` | 主键自动 |
| **2** | `getDiary(id)` | 按主键 | `WHERE id = ?` | 主键自动 |
| **2** | `getTagsByDiaryId` | 日记→标签 | `WHERE diary_id = ?` + join tags | ✅ `diary_tags(diary_id)` |
| **2** | `getAllCourses` / `getSemesterConfig` | 小表全读 | — | 不需要 |
| **1** | `getDiariesByTagId` | 标签→日记 | `WHERE tag_id = ?` → 再取 diaries | ✅ `diary_tags(tag_id)` |
| **1** | `getDiariesByMonth` | 按月取 | `WHERE date LIKE 'YYYY-MM%'` / `BETWEEN` | ✅ `diaries(date)`（范围扫） |
| **1** | `getDiariesByTagIdV3` | 三级标签→日记 | `WHERE tag_id = ?` | ✅ `diary_tags_v3(tag_id)` |
| **1** | `getDiaryTagIdsV3` | 日记→三级标签 | `WHERE diary_id = ?` | ✅ `diary_tags_v3(diary_id)` |
| **1** | `getSelfTalkMessagesByDate` | 按日取自言自语 | `WHERE date = ?` + `ORDER BY created_at` | ✅ `self_talk_messages(date, created_at)` |
| **1** | `getSelfTalkTasksByDate` | 按日取任务 | 同上 | ✅ `self_talk_tasks(date, created_at)` |
| **1** | `getSelfTalkTasksByMessageId` | 任务挂消息 | `WHERE message_id = ?` | ✅ `self_talk_tasks(message_id)` |
| **1** | `getSelfTalkMessagesByDateRange` | 区间 | `WHERE date BETWEEN ? AND ?` | ✅ `self_talk_messages(date)` |
| **1** | `searchQuickNotes` | 关键词 | `WHERE content LIKE '%kw%'` | ❌ **普通索引无效** → FTS5 |
| **1** | `searchSelfTalkMessages` | 关键词 | 同上 | ❌ **普通索引无效** → FTS5 |
| **1** | `searchSelfTalkTasks` | 关键词 | 同上 | ❌ **普通索引无效** → FTS5 |
| **1** | `getMoodDistribution` | 统计聚合 | `GROUP BY mood_id` | 可选 `diaries(mood_id)` |
| **1** | `getQuickNoteCount` | 计数 | `COUNT(*)` | 不需要 |

**查询形态归纳（只有 6 类）：**
1. 全表读 + 按 `date` 排序（`getAllDiaries` / `getRecentDiaries` —— 15+1 次，**最高频**）
2. 分页读 + 按 `date` 排序（`getDiariesPaged` —— 5 次，且**每次翻页都是全量重排**，见 §3.1）
3. 按 `date` 等值/范围（`getDiariesByDate` / `getDiariesByMonth` / `getSelfTalk*ByDate*`）
4. 按主键（`getDiary` / `getQuickNoteById`）
5. 关联表两向查询（`diary_tags`：`diary_id` ↔ `tag_id`；`diary_tags_v3` 同）
6. 文本关键词（3 个 `search*`）

---

## 2. 最小索引集（7 项，迁移到 SQLite 时一次建对）

按「共享 API 数 × 调用频次」排序，前两项收益最大：

| # | 索引 | 覆盖的 API | 收益 |
|---|---|---|---|
| **1** | **`diaries(date)`** | `getAllDiaries`(15) / `getRecentDiaries`(1) / `getDiariesPaged`(5) / `getDiariesByDate`(3) / `getDiariesByMonth`(1) | **5 个 API 共享，单一最大收益项**；`ORDER BY date DESC` 免全量排序，范围查询免全扫 |
| **2** | **`diary_tags(diary_id)`** + **`diary_tags(tag_id)`** | `getTagsByDiaryId`(2) / `getDiariesByTagId`(1) | 把当前 O(M) 线性扫（M=全部关联）降为 O(k) |
| 3 | `diary_tags_v3(diary_id)` + `diary_tags_v3(tag_id)` | `getDiaryTagIdsV3`(1) / `getDiariesByTagIdV3`(1) | 同上，三级标签体系 |
| 4 | `self_talk_messages(date, created_at)` | `getSelfTalkMessagesByDate` / `…ByDateRange` | 复合索引同时满足 WHERE 与 ORDER |
| 5 | `self_talk_tasks(date, created_at)` + `self_talk_tasks(message_id)` | `getSelfTalkTasksByDate` / `…ByMessageId` | 同上 |
| 6 | `anniversaries(date)` | 若日历页按日查纪念日（`calendar_screen.dart:69` 目前是全量读，未来可优化） | 低优先 |
| 7 | `diaries(mood_id)`（可选） | `getMoodDistribution`(1) | 可选，聚合用 |

**不需要索引**：`moods`、`tags`、`courses`、`semester_config` —— 全部是小表全量读（最高 6 次调用），索引反而增加写开销。

---

## 3. 两个「报告很容易写错」的易漏点（复核重点）

### 3.1 🔴 `getDiariesPaged` 每翻一页都重排全量 —— **加索引救不了**

`database_service_web.dart:388-402`：
```dart
388: static Future<List<Diary>> getDiariesPaged({required int page, int pageSize = 20}) async {
392:   await _ensureInitialized();
394:   final sorted = List<Diary>.from(_diaries)
395:     ..sort((a, b) => b.date.compareTo(a.date));      // ★ 每次调用都全量排序 O(n log n)
397:   final start = page * pageSize;
398:   if (start >= sorted.length) return [];
400:   final end = (start + pageSize).clamp(0, sorted.length);
401:   return sorted.sublist(start, end);                  // ★ 只取 20 条
402: }
```

- **每次翻页 = 一次全量 `List.from` 拷贝 + 一次全量排序**，只为拿 20 条。
- 滚动加载 10 页 → **10 次全量排序**；1000 篇时分页浏览明显卡顿，且随数据量平方级恶化（O(pages × n log n)）。
- **这是设计层问题，不是索引问题**：即使迁到 SQLite，如果沿用 `SELECT *` 全取再 Dart 排序，加 `diaries(date)` 索引也不会变快。**必须改成真正的 `LIMIT ? OFFSET ?` 让 SQLite 用索引走一趟就停。**
- ⚠️ **若 `data-layer.md` 写「给 `diaries(date)` 加索引即可优化分页」，即为无效建议** —— 索引只免排序，免不了「全表拷贝」，必须同时改查询形态。

### 3.2 🟡 三个 `search*` API 在 SQLite 下**普通索引无效**

- `searchQuickNotes` / `searchSelfTalkMessages` / `searchSelfTalkTasks` 语义是 `LIKE '%关键词%'`（前后都有通配符）。
- **B-tree 索引对前导通配符 `%kw` 完全失效**，加 `content` 索引是零收益。
- 正确做法：**FTS5 虚表**（`CREATE VIRTUAL TABLE ... USING fts5(content)`）+ 触发器同步，或维持当前内存过滤（数据量小的话后者可接受）。
- ⚠️ **若 `data-layer.md` 建议「给 content 加索引」，即为错误建议。** 可顺带提醒：FTS5 会增大 DB 体积并需要维护触发器，属于迁移期的额外工作量，应单独排期而非塞进 P0-1。

---

## 4. 与 P0-1 迁移的关系（供 Lead 汇总排序）

| 结论 | 含义 |
|---|---|
| **索引讨论的前提是存储层迁移** | 当前 web 实现是 `List` + `where` + `sort` 内存过滤，**没有 SQL 层可加索引**。B7 的所有索引结论都是「迁移后要一次建对」的清单。 |
| **迁移时最容易漏的不是索引而是查询形态** | 若把 `getDiariesPaged` 原样翻译成「`SELECT *` + Dart sort + sublist」，那么迁了 SQLite 依然慢（§3.1）。**必须同时改写为 LIMIT/OFFSET。** |
| **迁 native 会编译失败（已知地雷）** | `database_service_native.dart` **缺 5 个 public API**：`importDiaryTags`、`importDiaryTagsV3`、`restoreDiaries`、`restoreMoods`、`restoreTags`（共 7 个调用点，见 startup-native.md §4.1）。必须先补齐才能切 export。 |

---

## 5. 方法说明与局限

- 全部为**静态源码阅读**（`read` + grep），未运行 flutter/dart 工具链、未改任何源码。
- 调用次数是**静态调用点数**，不等于运行时频次；运行时高频路径（如首屏 `loadAllData`）的实际权重更高。
- 「等价 SQL 需求」为语义推断，迁移时需按实际表结构（`database_service_native.dart` schema v15）核对字段类型与 `date` 的存储格式（当前是 `yyyy-MM-dd` 字符串 → 索引/范围比较可用，但**不是 DATE 类型**，需注意 SQLite 的类型亲和性）。
- 本基线与 `data-layer.md` 的索引清单是**独立并行**产出的，两者一致处可互证，冲突处以本文件的 file:line 证据为准（可再复核）。

---

*生成时间：2026-10-28 · 只读产出*
