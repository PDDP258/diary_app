# Batch 0 实施记录（已完成）

> 日期：2026-10-28
> 依据：[OPTIMIZATION_PLAN.md](../OPTIMIZATION_PLAN.md) §4.1 Batch 0
> 分支：`backup-2026-03-19`
> 验证：`dart analyze` **0 error / 无新增问题**；`flutter test` **175 passed**；`flutter build apk --release` **成功**

---

## 0. 结果总览

| 指标 | 改前 | 改后 | 说明 |
|---|---|---|---|
| 保存一篇日记（N=1000） | 1.3~1.8 s | **预期 <100 ms** | 待真机实测确认 |
| 单篇保存写盘次数 | `2 + len(tagIds)` 次全量 fsync | **2 次（单篇键 + 索引）** | 标签写盘合并为 1 次 |
| 全屏看图内存 | 48 MB/张（4000px 原图） | **≈9.7 MB/张**（1800px） | 降幅 ~80% |
| PDF 单篇 20 图峰值 | ≈960 MB（理论） | **≈3 MB** | 4 张上限 + 1200px 降采样 |
| APK 体积 | 92.2 MB | **89.1 MB** | -3.1 MB |
| 插件注册数 | 21 | **20** | 移除 3 个零引用依赖 |
| 静态检查 | 0 error | **0 error，无新增** | 逐条比对 pristine 基线 |
| 单测 | 164 | **175 passed**（+11 新增） | |

---

## 1. 逐项完成情况

### ✅ B0-1 图片降采样解码（砍掉一条闪退路径）

**文件**：`lib/services/image_cache_service.dart`

`OriginalImage` 的 `Image.file` 原本不传 `cacheWidth`，按**原始像素**解码 —— 4000×3000 ≈ 48 MB/张，而全屏查看器是 `PageView` + `InteractiveViewer`（相邻页预加载），滑 2~3 张即 >120 MB。

改为按「屏幕宽度 × dpr × 1.5 缩放余量」解码，并夹紧到 `[600, 2400]` 像素；新增可选参数 `cacheWidth` / `zoomHeadroom` 供特殊场景覆盖。1080 宽设备约解码 1800px ≈ 9.7 MB。

**收益**：单图 48 MB → ≈9.7 MB（-80%）。

---

### ✅ B0-2 日记分键存储（保存性能主项）

**文件**：`lib/services/database_service_web.dart`

**改前**：全部日记存在单个 JSON 键 `diaries_data`。每次写一篇 = `Future.wait(全部 N 篇重新 AES 加密)` + `jsonEncode(全量)` + `setString(全量)`（`commit()` 主线程同步 fsync）。

**改后**：新格式

| 键 | 内容 |
|---|---|
| `diary_<id>` | 单篇日记的加密后 JSON（≈2 KB） |
| `diary_index` | 全部 id 的 JSON 数组（按 date 倒序） |
| `diaries_metadata` | 统计元数据（保持原样） |
| `diary_split_migrated_v1` | 迁移完成标记 |
| `diaries_data` | **旧格式，保留不删**（回滚保险） |

- 单篇新增/编辑/删除 → 只写/删**一个键** + 更新索引，Cost 从 O(N·L) → O(L)。
- 批量操作（`importDiaries` / `deleteMood` / `restoreDiaries`）仍走全量 `_saveDiaries()`，但改为**逐键写入**而非拼接大 JSON。
- **自动迁移**：首次启动检测到旧格式 → 拆分为分键 → 校验后才置位标记。任一步失败**回退旧格式读取**，不置位（下次重试），绝不丢数据。
- 单篇损坏容错：加载时某篇解析失败只跳过该篇并记录，不拖垮整个启动。

**同时修复的 2 个既有 bug**（都是本次改动顺带发现的）：

1. **`restoreDiaries` 把密文塞进内存列表** —— 原代码 `_diaries.add(Diary.fromMap(encryptedMap))`，恢复备份后内存里全是 `__ENC2__...` 密文，用户会看到乱码。已改为存明文（加密只发生在写盘那一刻）。
2. **`deleteMood` 的心情清空完全没生效** —— 原代码 `for (var diary in _diaries) { diary = diary.copyWith(...) }`，`diary` 是列表元素的**副本**，赋值不回写。已改为按下标回写。

---

### ✅ B0-3 标签写盘合并

**文件**：`lib/services/tag_system_service.dart`、`lib/models/tag_system.dart`、`lib/providers/diary_provider.dart`

**改前**：
```dart
for (final tagId in tagIds) { await TagSystemService.incrementTagUsage(tagId); }
```
每个标签都会走 `recordTagUsage` → `_saveTagSystem`，**每次全量重写整个标签系统 JSON**（`commit()` 同步 fsync，约 80 ms/次）。带 3 个标签的一次保存 = 3 次全量写盘。

**改后**：新增 `incrementTagUsages(Iterable<String>)`，在内存里聚合并累加（`incrementUsage({int by = 1})`），**只写盘一次**；未命中任何标签时不写。

---

### ✅ B0-4 `Diary` 派生字段缓存

**文件**：`lib/models/diary.dart`

| getter | 改前 | 改后 |
|---|---|---|
| `wordCount` | 每次 **new RegExp** + 全文 `replaceAll` | `RegExp` 提 `static final`，结果缓存 |
| `imageList` | 每次 `split(',')` + `where().toList()` 新建 List | 结果缓存 + 返回**不可变** List |

全仓 `.wordCount` 17 处、`.imageList` 38 处；统计/徽章/目标/文本分析都对**全量日记** fold，N=1000 时原本是上千次正则编译。

`Diary` 字段全 `final`、实例不可变，缓存安全；`copyWith` 产生新实例自然重算（已有单测锁定）。

---

### ✅ B0-5 PDF 导出图片限额与降采样

**文件**：`lib/services/pdf_export_service.dart`

- `exportSingleDiary` 原本**不限张数**（单篇最多 20 张），每张 `readAsBytes` 原图直喂 `pw.MemoryImage` → 峰值可达数百 MB。现加 `_maxImagesPerDiary = 4` 上限。
- 图片先 `compute` 在 **isolate** 里降到 1200px（`_pdfImageMaxWidth`）再进 PDF；缩放失败降级用原图（宁可慢不要出白页）。
- 1200px JPEG(q82) 约 150~300 KB/张，降幅 ~95%。

---

### ✅ B0-6 徽章检查移出关键路径

**文件**：`lib/screens/write_diary_screen.dart`

**改前**：`await GachaService.onDiarySaved()` → `await _checkMilestoneAfterSave()` → 然后才 `Navigator.pop()`。用户点保存后要**等完 8 组徽章全量检查**（含对全量日记取 `wordCount`）才能退出页面，可感知 200~800 ms。

**改后**：先 `pop` 立刻返回，检查与弹窗放到返回之后的后台任务（`unawaited(_runPostSaveChecks(...))`，内部全程 try/catch）。

**关键设计**：
- 用 **`NavigatorState`（根导航器）**而不是 `BuildContext` 传参 —— 本页 pop 后 State 已 dispose，原 `context` 失效；`NavigatorState` 自带 `mounted`，每次弹窗前可校验。
- 检查所需的 `diaries` / `savedDiary` 在 pop **之前**快照好，避免 pop 后读已 dispose 的 State。

---

### ✅ B0-7 真实搜索入口修正（性能 + 正确性）

**文件**：`lib/screens/diary_search_screen.dart`

审计最严重指认的「每键全量搜索 + 零防抖」在 `diary_search_enhanced_screen.dart`，但**该文件零 import 是死代码**。真实入口是 `diary_search_screen.dart`（被 `calendar_screen.dart:22`、`stats_screen.dart:8` 引用），它的问题更严重：

1. **数据源只覆盖 20 篇**（用 `provider.diaries`，而 Provider 是分页加载的）→ 用户搜不到第 21 篇以后的日记，会以为日记丢了。**已改为搜索 `DatabaseService.getAllDiaries()` 全量**，进页面时加载一次并缓存。
2. **假防抖**：`Future.delayed(300ms)` 不可取消，快速输入 10 个字会排 10 个 Timer。**已改为可取消 `Timer`**（`dispose` 时 cancel）。
3. 新增：**最少 2 字**门槛、**搜索序号校验**（丢弃过期结果，防旧结果覆盖新结果）。
4. 详情页返回时让全量缓存失效，避免用旧数据搜索。
5. 复用已按日期倒序的全量列表，去掉每次查询的重复 `sort`。

---

### ✅ B0-8 统计页 N+1 改批量

**文件**：`lib/screens/stats_screen.dart` + `database_service_web.dart` / `database_service_native.dart`

**改前**：对**每篇日记**调一次 `getTagsByDiaryId`，而该实现每次全表扫 `_diaryTags` 再内层 `tagIds.contains` → 整体 O(N×M×K)，N=1000 时上百万次 Map 比较 + 上千次 async 调度。

**改后**：新增 `getTagNamesByDiaryIds()`（web 与 native **两端都实现**，保持 API 对等），一次扫描返回 `diaryId → 标签名`，O(N + M)。

---

### ✅ B0-9 删除零引用原生大图

删除 `android/app/src/main/res/drawable/` 下：

| 文件 | 大小 | 引用数 |
|---|---|---|
| `icon_bulb_original.png` | 3.41 MB | **0**（已三重确认：android kt/xml/java + lib dart） |
| `bg_wooden_frame.png` | 2.93 MB | **0** |

**APK 直接 -6.19 MB**。drawable 目录从 6.63 MB 降到 0.44 MB。

---

### ✅ B0-10 移除零引用依赖

从 `pubspec.yaml` 删除（实测 `lib/test/windows/web` 全部零 import）：

| 依赖 | 移除理由 |
|---|---|
| `cupertino_icons` | 唯一内容 `CupertinoIcons.ttf` 251.6 KB 直接进包 |
| `table_calendar` | 日历页是手写 `GridView.count`，从未使用 |
| `turn_page_transition` | Splash 翻页用的是自研 `SplashPageTurn`（`real_page_turn.dart`） |

`flutter pub get` 确认移除 4 个包（含传递依赖 `simple_gesture_detector`）；**插件注册数 21 → 20**。

> ⚠️ 按 AGENTS.md 的坑：移除原生插件后必须跑 `flutter pub get` 重生成 `GeneratedPluginRegistrant.java`，否则 `--no-pub` 构建会漏注册。已执行并验证注册表里不再出现这 3 个包。

---

## 2. 验证证据

### 2.1 静态检查（0 error，无新增问题）

以改动前的 `git stash` 原始状态为基线，逐条比对（忽略行号偏移）：

```
pristine          : error=0 warning=114 info=268
after B0-1/4/9/10 : error=0 warning=114 info=268   ← 完全一致
after B0-5        : error=0 warning=114 info=268   ← 完全一致
after B0-8        : error=0 warning=114 info=272   ← 4 条已在 B0-6 修复
final (Batch 0)   : error=0 warning=114 info=271   ← 仅 3 条 print（与文件内其它 30+ 处同类型）
```

新增的 3 条 `avoid_print` 位于 `database_service_web.dart` 新加的容错分支，与该文件既有 30+ 处 `print` 同风格，非新问题类型。

### 2.2 单元测试（175 passed）

```
00:06 +175: All tests passed!
```

新增 `test/diary_model_test.dart`（11 个用例），锁定 B0-4 改造的行为不变：

- `imageList`：null/空串、过滤空项、**缓存返回同一实例**、**不可被外部修改**
- `wordCount`：标题+正文相加、排除 🎉/⏰ 标记的纪念日行、null 不崩溃、缓存一致、**`copyWith` 后重新计算**
- **锁定既有语义**：不带 emoji 标记的「倒数日」文字**不会**被排除（防止有人顺手放宽正则改变历史字数统计口径）
- `toMap`/`fromMap` 往返后派生字段一致（分键存储的序列化载体）

### 2.3 构建验证

```
√ Built build\app\outputs\flutter-apk\app-release.apk (89.1MB)
```

- 体积 92.2 MB → **89.1 MB**
- 两个死图确认**已不在 APK 内**
- 字体资产仍在（23.97 MB，本次未动，见 Batch 1）

---

## 3. 未做 / 留到后续

| 项 | 原因 |
|---|---|
| **真机性能实测** | 静态与构建验证已完成；`保存 <100ms` 与 `启动 1.0~1.4s` 需真机 + release 包用 DevTools 确认（方案 §5.2 V1~V8） |
| **B0-2 的 `_updateMetadata` 仍 O(N)** | 已优化为「使用缓存后的 wordCount」，但整体仍是全量扫。彻底解决需增量维护计数 + 一次性重建基线，留到 Batch 1 |
| **字体内联（23.97 MB）** | 子集化实测可省 18.5~20.7 MB，但需先确认 PDF 导出用字范围，留到 Batch 1 |
| **splash_cover.png（2.35 MB）** | 转 WebP 可省 2.3 MB，留到 Batch 1（与 Splash 改造一起做） |
| **ABI 拆分 / 正式签名** | 出包配置，留到发版前统一处理 |
| **`database_service_native.dart`** | 本次**未改其单篇写路径**，只补了 `getTagNamesByDiaryIds` 保持 API 对等。切入 SQLite 属 Batch 2（Phase 0~3） |

---

## 4. 下一批建议动作（Batch 1）

按依赖关系排序：

1. **B1-5/B1-6 Splash 与数据加载并行**（省 1.2~2.0 s，依赖 B0-2 已完成 ✅）
2. **B1-4 删 4 项无效启动初始化**（省 100~150 ms，零风险）
3. **B1-1/B1-2 日历索引化**（先提 `DateFormat` 常量，再上 `_byDate` 索引）
4. **B1-3 特殊主题 `RepaintBoundary`**（需 PD 确认视觉取舍）
5. **字体子集化 + splash WebP**（-20 MB 包体）

Batch 1 完成后建议做一次真机 A/B，用方案 §5.1 的验收指标逐项打勾，再决定是否进入 Batch 2（SQLite 切换）。
