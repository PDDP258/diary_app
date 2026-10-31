# 小记日记 · 性能优化方案（v2.1.0 → v2.2）

> 编制：Lead（含 4 路并行审计 + 1 路交叉复核，共 5 名审计员 / 8 份报告）
> 日期：2026-10-28
> 依据：`.perf-analysis/` 下 8 份文件（合计约 2,600 行，逐条带 `file:line` 证据）
> 性质：**只读审计产出**。本文与全部审计均未修改任何源码（`git status` 确认 `lib/`、`android/`、`pubspec.yaml`、`test/` 零改动）。
> 状态：**已通过 13 条交叉复核，7 处方向性错误已更正**（见 §8）。

---

## 〇、结论先行（90 秒版）

**这不是"某个页面有点慢"，是一处架构级的实现错位。** 项目里有一份 1,189 行的 SQLite（sqflite）实现 `lib/services/database_service_native.dart`（schema v15，写得相当完整），**但没有任何一行代码 import 它**。`lib/services/database_service.dart` 全文只有 3 行：

```dart
// lib/services/database_service.dart
export 'database_service_web.dart';
```

于是 Android 真机上跑的是那份「Web 版」存储层：**全部日记（含 AES 密文）存在 SharedPreferences 的单个 JSON 字符串键 `diaries_data` 里，全部数据常驻内存 List**。它的三条特征直接生成了用户反馈的两种症状：

| 症状 | 机制 | 量级（N=1000 篇日记） |
|---|---|---|
| **卡顿** | 每写一篇日记 = **全部 N 篇重新 AES 加密 + 全量 `jsonEncode` + 全量写入**，且是 `2 + len(tagIds)` 次**主线程同步 fsync** | 保存一次 **1.3~1.8 s**；N=5000 时 6~9 s，必 ANR |
| **闪退** | 冷启动把全部日记一次性 `jsonDecode` 进内存再逐篇解密，峰值 ≈4~6× 数据体积；叠加图片按原图解码（48 MB/张）与 PDF 导出无上限读图 | 冷启动 N=5000 峰值 **~50 MB** 仅数据层；看图 2~3 张即可能 OOM |
| **启动慢** | `main()` 在 `runApp` 前串行 `await` 7 项初始化（3 项结果完全没被使用）；Splash 是 **1.2~2.0 s 的纯空转**（期间一次数据都没加载） | 冷启动到可交互 **2.5~4.5 s** |

**一句话**：卡顿与闪退是**同一个根因**（存储层错位导致的写放大与内存放大）的两个不同表现；把存储层切回 SQLite 是唯一能同时消掉两者的动作。渲染层的若干热点（特殊主题全屏每帧重绘、日历 42 格重复格式化、原图解码）是**叠加项**，需要并行修复，但它们单独修不会解决"保存卡 2 秒"。

**推荐路径**：先做 3 条止血（1~2 天，保存从 1~3 s 降到 <100 ms，且能立刻砍掉一条闪退路径）→ 并行做 SQLite 切换的 Phase 0（零用户可见）→ 再灰度切存储引擎。**不要先切存储引擎**，因为 native 实现是"从未被编译过的死代码"，且**缺 13 个被生产代码调用的 API**（含 `getRecentDiaries`、`getDiariesPaged` —— 直接改 export 会让首页和列表页当天就崩）。

---

## 一、第一轮思考：先把"卡顿"和"闪退"拆成两条独立的故障链

用户说的"卡顿、闪退频繁"听起来是一个问题，但审计证据显示它们是两条因果链，只是共享同一个根因节点。

### 1.1 故障链 A：卡顿（占反馈量主体）

```
写一篇日记 / 收藏 / 编辑 / 删除
   ↓
DatabaseService.insertDiary → _saveDiaries()            ← 全量 N 篇重新 AES 加密
   ↓                                                    ← 全量 jsonEncode
   ↓                                                    ← 全量 prefs.setString（同步 commit/fsync）
   ↓
_updateMetadata() 再 fold 全量算字数 + 第二次全量写盘
   ↓
+ insertDiaryTagsV3 → _saveDiaryTagsV3（又一次全量写）
+ 每个 tag 一次 incrementTagUsage → _saveTagSystem（每次都全量重写标签系统 JSON）
   ↓
+ Provider.loadRecentDiaries() 又一次全量 sort 拷贝
   ↓
notifyListeners() → Timeline + Calendar 两个 Consumer 同时整页 rebuild
                    （日历 42 格 × 每格线性扫全量 + 4 次 DateFormat 构造）
```

**关键洞察：写一篇日记的代价与 N 成正比，与你改了多少个字完全无关。** 这是本 App 卡顿的第一性原理。

### 1.2 故障链 B：闪退

四条独立的内存峰值路径，可分别复现：

| 路径 | 峰值来源 | 触发动作 |
|---|---|---|
| B1 冷启动 | 全量 JSON 字符串 + 全量 List + 逐篇解密后的 Diary 三份并存（≈4~6× 数据体积） | 每次冷启动 |
| B2 全屏看图 | `OriginalImage` 的 `Image.file` **无 `cacheWidth`** → 4000×3000 原图解码 ≈48 MB/张，`PageView` 同时持有多张 | 滑 2~3 张 |
| B3 导出 PDF | 字体单份 23.97 MB（解析后 36~60 MB）+ 每张图 `readAsBytes` 原图直喂 `pw.MemoryImage`，且 `exportSingleDiary` **无张数上限** | 单篇 20 图 ≈960 MB |
| B4 云同步图片包 | 单个 `Archive` 装全部图片字节；`Isolate.spawn` 深拷贝一份、`Uint8List.fromList` 再拷一份 → **进程峰值 ≈4.7× 总图片体积** | 300 张 × 3 MB ≈ 4 GB 理论 |

**判定**：B1 解释了"用户数据越多越容易崩"，B2/B3/B4 解释了"某些操作一触发就崩"。两者都需要修，但 B1 是结构性的、B2 是最便宜的。

### 1.3 一个必须纠正的认知

审计中出现了**三次**同类误判（`gacha_screen`、`stats_screen`、`profile_screen`，已全部由交叉复核抓出并更正）：把 `AnimatedBuilder` 的**局部重建**误判为"整棵树每帧 rebuild"。例如 `gacha_screen` 被断言"动画期间每帧 240 次 SharedPreferences 读取"，实际 `build()` 里**零 `addListener`**，动画只在 `AnimatedBuilder` 内部消费，`setState` 全程只有 5 次；`stats_screen` 同样 `addListener` 命中为 0。

> **方法论要求（三步判据，本方案全部"每帧"断言均已按此验证）**：
> 1. 查 `addListener` + `setState` —— 有则成立（路径 a）；
> 2. 查动画 widget（`AnimatedBuilder` / `TweenAnimationBuilder`）—— 其 builder 每帧执行；
> 3. **看作用域是否真的包住目标子树** —— 这是前两步都会漏的一步，也是全部三处误判的共同根因。
>
> ⚠️ **两个方向的陷阱都要防**：
> - `grep addListener` 返回 0 **只排除路径 (a)**，不能据此判定"不会每帧重建"：`theme_backgrounds.dart` 的 `addListener` 也是 0，但它走路径 (b) **确实每帧重绘**（我独立复跑：`addListener`=0 / `AnimatedBuilder`=5 / `..repeat()`=7）。
> - **文件里有动画 widget ≠ 整棵树每帧重建**：`stats_screen` 有 2 个 `AnimatedBuilder` + 1 个 `TweenAnimationBuilder`，`gacha_screen` 有 1 + 3，但都不包住被指控的子树（我独立复跑确认）。
>
> 已对 `stats_screen.dart`、`gacha_screen.dart`、`profile_screen.dart` 独立 verify（`addListener` 均为 0），并据此把相关条目从 P0/P2 降级。

---

## 二、第二轮思考：根因分层 —— 什么是"乘数"，什么是"加数"

把 30+ 条问题按"影响面"重新分层，避免把力气花在加数上：

### 第 0 层：架构错位（乘数级，改一处收益覆盖全 App）

| ID | 问题 | 证据 | 为什么是乘数 |
|---|---|---|---|
| **A-1** | **Android 实跑 SharedPreferences+全量 JSON，SQLite 实现是死代码** | `database_service.dart:3`；`database_service_native.dart` 零 import | 所有"数据库查询"退化为内存 `List.from(...)..sort()`；所有写入退化为全量重加密+全量落盘。**67 个 API / 138 处调用全部受此影响** |

### 第 1 层：写放大与读放大（由 A-1 派生，但可独立止血）

| ID | 问题 | 证据 | 量级 |
|---|---|---|---|
| **A-2** | 每次写 = 全量重加密 + 全量落盘 | `database_service_web.dart:270-280` | N=1000：~1.3-1.8 s/次 |
| **A-3** | 一次保存 = **2 + len(tagIds)** 次主线程同步 `commit()` fsync | `web:270-280` + `web:301-304` + `tag_system_service.dart:46-49,193-195` | 带 3 标签 = 5 次 fsync |
| **A-4** | 全量元数据再写一次盘 | `web:331-339` | 第二次全量写 |
| **A-5** | `getDiariesPaged` 每页都全量重排（分页无收益） | `web:388-402` | O(N log N)/页 |
| **A-6** | `getTagsByDiaryId` 全表扫 + 内层 `contains` → 统计页 N+1 变 O(N²·k) | `web:725-732`；`stats_screen.dart:147-152` | 1000 篇 ≈ 200 万次比较 |
| **A-7** | Provider getters 每次调用新建 List/Set | `diary_provider.dart:39-56` | 日历 42 格 × O(N) |
| **A-8** | `Diary.wordCount` 每次 new RegExp + 全文 replaceAll | `models/diary.dart:108-121` | 17 处调用点 |
| **A-9** | `updateDiary` 后全量 `loadDiaries()`；`addDiary` 后全量重载 | `diary_provider.dart:222,244` | 每次编辑两次 O(N log N) |

### 第 2 层：渲染层热点（叠加项，影响前台手感）

| ID | 问题 | 证据 | 触发条件 |
|---|---|---|---|
| **B-1** | 特殊主题：5 套背景 `AnimationController..repeat()` + `CustomPaint(child: 整棵 PageView)` + `shouldRepaint=>true` + 业务 `RepaintBoundary` 用量 **0** | `theme_backgrounds.dart:396-403,810-816,1320-1325,1680-1689,2076-2101`；`:624,1244,1494,1983,2250` | 仅 5 个特殊主题；**默认"温馨米"不受影响** |
| **B-2** | 日历 42 格 ×（4 次 `DateFormat` 构造 + 1 次线性扫全量 + 新建 List），`datesWithDiaries` 每次 build 新建 Set | `calendar_screen.dart:93,95,410-447,1427-1428` | 每次 Provider 通知 |
| **B-3** | 时间线每项套 `ScrollReveal`（每项一个 VisibilityDetector + AnimationController + `Opacity(0..1)`）→ 非 0/1 走 saveLayer | `timeline_screen.dart:256`；`scroll_reveal.dart:60-125` | 滚动/首次揭示 |
| **B-4** | 特殊主题下 `BackdropFilter(sigma 20)` 常驻底部导航，背后是每帧变化的背景 | `custom_bottom_nav.dart:44-48` | 特殊主题 + 导航可见 |
| **B-5** | `BreathingAnimation` 常驻重绘「我的」页大卡（渐变+多层阴影+头像，无 RepaintBoundary） | `animated_feedback.dart:354-417`；`profile_screen.dart:812` | **默认主题下唯一的常驻 60fps 热点** |
| **B-6** | 4 个 tab 页均无 `AutomaticKeepAliveClientMixin` → 切回即 `initState` 重跑 | `main_screen.dart:617-621` | 每次切 tab |
| **B-7** | `SystemChrome.setSystemUIOverlayStyle` 在 `build` 里每次调用（平台通道） | `main_screen.dart:566-569` | 每次 MainScreen rebuild |

### 第 3 层：图片（闪退最便宜的一条）

| ID | 问题 | 证据 |
|---|---|---|
| **C-1** | `OriginalImage` 的 `Image.file` 无 `cacheWidth/cacheHeight` → 原图解码 | `image_cache_service.dart:505-553`；`diary_detail_screen.dart:1227` |
| **C-2** | `PlatformImage` 声明了 `cacheWidth/cacheHeight` 但**从未透传**（死参数） | `platform_helpers.dart:21-22,63-69` |
| **C-3** | `PlatformImage` 在 `build` 里 `FutureBuilder(File.exists())` → 每次 rebuild 重新 IO，图片闪白块 | `platform_helpers.dart:50-55` |
| **C-4** | 选图不带 `maxWidth/imageQuality`（对比时间胶囊页带了 1200/85） | `write_diary_screen.dart:238-247` |

### 第 4 层：启动链路

| ID | 问题 | 证据 |
|---|---|---|
| **D-1** | `runApp` 前串行 await 7 项；其中 `AppProtectionService`（结果硬编码 `allPassed=true`、`_strictMode=false`、不做 APK 哈希）、`CloudSyncFactory`、`SyncLogService`、`SoundService`（构造的 AudioPlayer 全程未被使用）**四项结果/对象完全没被使用** | `main.dart:24-79`；`app_protection_service.dart:36-59,191-195`；`sound_service.dart:12-21` |
| **D-2** | 主题被读取**两次**（`CourseWidgetService._ensureTheme()` 内部又 new 一个 ThemeProvider 再 `loadSettings`） | `course_widget_service.dart:133-143` |
| **D-3** | Splash 固定等待 1.2 s（日常）/ 2.0 s（完整），**期间一次数据都没加载**；`_showFullAnimation` 初值 `true` → prefs 返回 false 时把已跑的动画整棵丢弃重来（还白解码一次 2.3 MB/≈8 MB 位图） | `splash_screen.dart:97,109-131,141-165,343-385` |
| **D-4** | 数据加载在 `MainScreen` postFrame 才启动，导致 splash 后又一次全屏 spinner | `main_screen.dart:58,116-121,235-256,546-554` |
| **D-5** | `CourseWidgetBackgroundRunner` 每次 new 一个**完整 FlutterEngine + 注册 20 个插件**，开机广播立刻入队；App 前台时可能同进程两引擎并存 | `CourseWidgetBackgroundRunner.kt:43-96`；`CourseWidgetBootReceiver.kt:26-31` |
| **D-6** | `FloatingWindowService` 前台服务 + 常驻通知 + **INFINITE ValueAnimator 呼吸动画**；`START_STICKY` 但 `intent==null` 无分支 | `FloatingWindowService.kt:163,390-407,118-127` |

### 第 5 层：包体与构建

| ID | 问题 | 证据/量级 |
|---|---|---|
| **E-1** | APK 92 MB 打包 **3 套 ABI**（arm64/armeabi-v7a/x86_64）的 `libflutter.so`+`libapp.so`，无 `abiFilters` | APK 内容实测 |
| **E-2** | `assets/fonts/NotoSerifCJKsc-VF.ttf` **23.97 MB**（占 APK 26%），**仅 PDF 导出用**（启动不加载） | 实测；`pdf_export_service.dart:98` |
| **E-3** | `assets/images/splash_cover.png` 1080×1920 2.3 MB（≈8 MB 解码），可压到 <300 KB | 实测 |
| **E-4** | release 用 **debug keystore** 签名 | `android/app/build.gradle.kts:36-42` |
| **E-5** | 3 个依赖零 import：`table_calendar`、`turn_page_transition`、`cupertino_icons` | 实测 grep = 0 |
| **E-6** | 死代码约 **8,465 行**（另 1,189 行 SQLite 实现与 191 行 OCR 有意保留，见附录 B） | 实测（import 计数） |

> **已纠正的一处误判**：`build.gradle.kts` 里没有 `isMinifyEnabled`/`isShrinkResources`，**但 Flutter Gradle 插件会自动给 release 开启 R8 + 资源收缩**（`FlutterPlugin.kt:264-267`）。证据：`build/app/outputs/mapping/release/mapping.txt` 34.1 MB、APK 内仅 1 个 1.8 MB 的 `classes.dex`。**混淆是开着的**，不要重复劳动。

---

## 三、第三轮思考：方案权衡 —— 为什么不能"直接切 SQLite"

直觉方案是"改一行 export，切回 SQLite"，成本最低、收益最大。审计后判定：**这是最危险的方案**，因为它会以三种方式在发布当天炸掉。

### 3.1 硬阻塞：native 实现缺 13 个被生产代码调用的 API

成员级 diff（web 97 个 static 成员 vs native 76 个）实测：

| 缺失 API | 调用点 | 不补的后果 |
|---|---|---|
| `getRecentDiaries({limit})` | `diary_provider.dart:82` | **首页当天崩** |
| `getDiariesPaged({page,pageSize})` | `paged_diary_list.dart:85,112,594,618` | **列表页当天崩** |
| `getAllDiaryTags` | 4 处（`data_management:696,741`、`write_diary_screen:621`、`incremental_sync`） | 数据管理/写日记页崩 |
| `getAllDiaryTagsV3` / `getDiaryTagIdsV3` | 增量同步 | 同步链断 |
| `getDiariesByTagId(int)` | `tag_diaries_screen:52` | 签名不匹配，编译失败 |
| `importDiaryTags` / `importDiaryTagsV3` | `cloud_sync_service:1576`、`incremental_sync_service:173` | 云同步恢复崩 |
| `restoreDiaries` / `restoreMoods` / `restoreTags` | `auto_backup_service:210,215,220`、`incremental_sync_service:156,162` | 本地备份恢复崩 |
| `getDiaryIdsByTagIdV3` / `getDatesWithDiaries` | parity（0 直调） | 可延后 |

**我已独立 verify**：`getRecentDiaries`、`getDiariesPaged`、`getAllDiaryTags`、`getAllDiaryTagsV3`、`getDiaryTagIdsV3`、`getDiariesByTagId` 在 native 文件中命中数**均为 0**。

### 3.2 更隐蔽：3 处语义漂移（能编译，但行为悄悄改变）

`importDiaries` / `importMoods` / `importTags`：**web 版是按 id upsert（覆盖），native 版是"已存在则跳过"**。一旦切换，云同步行为从"覆盖"变成"忽略" → **远端修改永远同步不进来**。这是最难排查的一类 bug（无异常、无报错、只是数据不对）。必须在切换前统一为 upsert。

### 3.3 结构性：native 实现本身也不够快

即便切过去，`_onCreate`（`native:58-132`）**零业务索引**；缺 `word_count` 列；`getAllDiaries` 里 `Future.wait` 对 N 条无上限并发解密，内存峰值与 web 版同源。**切过去只是"换了个慢法"**，必须同时补索引、补列、改列表查询字段裁剪。

### 3.4 三条路线对比

| 路线 | 内容 | 周期 | 收益 | 风险 | 判定 |
|---|---|---|---|---|---|
| **R1 纯止血** | 只做 D1/D9（分键增量写 + 合并 tag 写盘）+ 图片 cacheWidth | 1~2 天 | 保存 1~3 s → **<100 ms**；砍掉一条闪退路径 | 极低 | ✅ **立刻做** |
| **R2 增量重构**（推荐） | R1 + Provider 索引化 + 渲染层热点 + Phase 0 契约化 → 灰度切 SQLite | 3~4 周 | 冷启动 2.5~4.5 s → **1.0~1.4 s**；保存 → **<100 ms**；闪退路径基本清零 | 中（可控，见 §5） | ✅ **主路线** |
| **R3 大重写** | 重写数据层 + 引入 Riverpod/状态重构 + 拆包 | 2~3 月 | 上限最高 | 高，且当前没有测试网兜底（仅 8 个测试文件，全在课表模块） | ❌ **本轮不做** |

**选 R2 的理由**：R1 单独做会在两周后被新功能重新拖回原状（因为 A-2/A-3 的根因没除）；R3 在当前测试覆盖度（`test/` 仅 8 个文件、164 个用例、**全部集中在课表/OCR/小组件，日记主链路零测试**）下等于裸奔。R2 的关键设计是**把"止血"和"换引擎"解耦成可独立上线、可独立回滚的两段**。

---

## 四、第四轮思考：分阶段落地计划（含依赖关系）

### 4.1 Batch 0：立即止血（0.5~2 天，全部可并行，无需评审架构）

| # | 任务 | 改动量 | 收益 | 证据 |
|---|---|---|---|---|
| **B0-1** | `OriginalImage` 的 `Image.file` 加 `cacheWidth: (屏幕宽 × dpr).round()` | 2~5 行 | 单图 **48 MB → 4~6 MB**，直接砍掉 B2 闪退路径 | `image_cache_service.dart:505-553` |
| **B0-2** | `_saveDiaries` 改**增量分键**：写单篇只重写 `diaries_{id}`，列表顺序用 `diaries_meta`（id 数组）维护，`diaries_data` 保留作迁移/备份 | ~80~150 行 | 保存 **1~3 s → <50 ms**，消除 2 次全量 fsync | `web:270-280,439-449,512-532` |
| **B0-3** | 消灭"每个 tag 一次全量 tagSystem 写盘"：合并成一次写 / 页面退出时 flush | ~20 行 | 带 3 标签时省 **3×~80 ms** | `tag_system_service.dart:46-49,193-195` |
| **B0-4** | `Diary.wordCount`：`RegExp` 提 `static final` + 加 `_wcCache` | ~6 行 | 消除 17 处调用点的正则编译 | `models/diary.dart:108-121` |
| **B0-5** | `exportSingleDiary` 加 `take(4)`；图片导出前 `compute` 缩到 1200px | ~15 行 | 单篇 20 图 **960 MB → ~3 MB** | `pdf_export_service.dart:503-517` |
| **B0-6** | 保存后徽章检查移到 `Navigator.pop` **之后** | 2 行（调换顺序） | 保存的感知延迟 **200~800 ms → 0** | `write_diary_screen.dart:653-656` |
| **B0-7** | 真实搜索入口 `diary_search_screen.dart`：加 300 ms **可取消**防抖 + 最少 2 字 → **并修数据源**：目前只搜 `provider.diaries`（仅最近 20 篇），改为 `getAllDiaries()` 或先 `loadDiaries()` | ~20 行 | **修正确性 bug**（现在搜不到第 21 篇以后的日记，用户会以为日记丢了）+ 每键 30~80 ms → 一次 | `diary_search_screen.dart:58,215-223` |
| **B0-8** | 统计页 N+1 改批量：一次 `getAllDiaryTags()` 拉平 + 本地聚合 | ~20 行 | O(N²·k) → O(N) | `stats_screen.dart:147-152` |
| **B0-9** | 删 3 个零引用原生大图（`icon_bulb_original.png` 3.41 MB + `bg_wooden_frame.png` 2.93 MB） | 删文件 | **APK 直接 -6.3 MB**（已实测 refs=0） | `android/app/src/main/res/drawable/` |
| **B0-10** | 移除 3 个零 import 依赖：`table_calendar`、`turn_page_transition`、`cupertino_icons` | pubspec 3 行 | 少 251.6 KB 字体 + 少 1 个插件注册 | 实测 grep = 0 |

> **B0-2 与 B0-3 是唯一能把"保存 1~3 秒"降到"<100 ms"的两条。** 其余优化 CPU 或读路径，量级小一个数量级。
>
> ⚠️ **B0-7 有一处必须先知道的限定**：审计最严重指认的「增强搜索每键全量 `getAllDiaries` + 无防抖」位于 `diary_search_enhanced_screen.dart`，而**该文件是死代码（零 import，我已独立核实）**——缺陷属实、但**当前零用户影响**。真实入口是 `diary_search_screen.dart`（被 `calendar_screen.dart:22`、`stats_screen.dart:8` 引用），它的实际问题是**数据源只覆盖 20 篇**（`:58` `provider.diaries`）+ 假防抖（`:218` 的 `Future.delayed` 不可取消）。**两者都要修，但"用户可感知"的是后者。**

### 4.2 Batch 1：渲染层与启动（1 周，需要 PD 确认视觉取舍）

| # | 任务 | 依赖 | 收益 |
|---|---|---|---|
| **B1-1** | 日历：`DateFormat` 提 `static final` + build 前一次性算好 42 格的 Map | 无 | build 4~8 ms → 1~2 ms |
| **B1-2** | `DiaryProvider` 预计算 `Map<String,List<Diary>> _byDate` + `Set _dates` + `_favorites`，在变更处增量维护 | 无 | 日历 42×O(N) → 42×O(1) |
| **B1-3** | 特殊主题背景：`CustomPaint` 外包 `RepaintBoundary`，`child` 移出 painter 层；新增「减弱动画」设置项 | 需 PD 确认 | 帧时 16 ms → 6~9 ms（仅特殊主题） |
| **B1-4** | `main()` 删掉/后移 4 项无效初始化（AppProtection、CloudSync、SyncLog、Sound），主题复用避免二次读 | 无 | 首帧前省 **100~150 ms** |
| **B1-5** | Splash 固定延时改为「与数据加载并行，最早完成即进入」；`_showFullAnimation` 初值改 `false` 避免白跑 | 需 B0-2 完成 | **省 1.2~2.0 s** |
| **B1-6** | 数据加载前移到 Splash 期间；MainScreen 首帧用骨架屏替代全屏 spinner | B1-5 | 消除"二次启动"观感 |
| **B1-7** | `ScrollReveal` 只保留首屏前 3 项 | 需 PD 确认 | 滚动期 saveLayer 归零 |
| **B1-8** | `BreathingAnimation` 加 `RepaintBoundary` 或改为有限周期 | 无 | 默认主题下唯一常驻热点消除 |
| **B1-9** | `SystemChrome.setSystemUIOverlayStyle` 移出 `build` | 无 | 每次 rebuild 省一次平台调用 |
| **B1-10** | 给 Calendar/Timeline 加 `AutomaticKeepAliveClientMixin` | 需权衡内存 | 切 tab 不再重新加载 |

### 4.3 Batch 2：存储引擎切换（3 周，分 4 个 Phase，每个 Phase 可独立上线）

#### Phase 0（3~5 天，**零用户可见变化，风险≈0**）

1. **建编译门**：新建 `test/database_service_native_contract_test.dart`，import native 文件并以 tear-off 形式引用全部 public API，让死代码被工具链看见。
2. **跑真实读写测试**：加 `sqflite_common_ffi` dev 依赖，测建库/迁移到 v15/插入/查询/级联删除/加密往返。
3. **补齐 13 个缺失 API**。
4. **统一 `import*` 语义为 upsert by id**（与 web 现状一致，避免云端行为漂移），加单测：同 id 二次导入必须覆盖。
5. **加 `word_count` 列**（写入时算一次）。
6. **补全部业务索引**（放 v16 升级脚本，不建在 `_onCreate` 里，避免老库漏建）。
7. **加 CI 门禁**：`web` / `native` 两边 static 成员名集合必须相等（私有除外）。

```sql
-- Phase 0 需要补的索引（B 节结论）
CREATE INDEX idx_diaries_date        ON diaries(date DESC, created_at DESC);
CREATE INDEX idx_diaries_date_created ON diaries(date, created_at DESC);
CREATE INDEX idx_diaries_mood        ON diaries(mood_id);
CREATE INDEX idx_diaries_fav         ON diaries(is_favorite) WHERE is_favorite = 1;
CREATE INDEX idx_diaries_word_count  ON diaries(word_count DESC);
CREATE INDEX idx_diary_tags_diary    ON diary_tags(diary_id, tag_id);
CREATE INDEX idx_diary_tags_v3_diary ON diary_tags_v3(diary_id, tag_id);
CREATE INDEX idx_diary_tags_v3_tag   ON diary_tags_v3(tag_id, diary_id);
-- 注意：分页仅加索引无效，必须同时把 getDiariesPaged 改成 LIMIT/OFFSET（深层用 keyset）
-- 注意：搜索不要给 content 建普通索引（密文 + 子串语义），见 §4.4
```

#### Phase 1（2~3 天）：门面 + 运行时开关（**比裸条件导出更安全**）

```dart
// lib/services/database_service.dart —— 门面（facade），全部 138 处调用点零改动
import 'db_impl_native.dart' if (dart.library.js_interop) 'db_impl_web.dart';
// 门面按运行时开关转发：prefs 里 db_engine = 'prefs' | 'sqflite'
```

- web 判定用 **`dart.library.js_interop`** 而非 `dart.library.html`（后者在 wasm 下为 false，未来开 wasm 会炸）。
- `db_impl_native.dart` 里**同时 import web 实现做兜底**（web 实现只依赖 shared_preferences，Android 上也能跑）→ 得到**运行时回退能力**：出问题改一个 prefs 键即刻回退，不用发版。**反向不成立**（web 实现不能 import sqflite），所以兜底方向只能是 native → web。

#### Phase 2（1~2 天）：一次性迁移器

```
读 prefs 各键 → 沿用 EncryptionService 解密（不新写解密逻辑）
  → 打开临时库 diary_v15_migrating.db，单事务 + Batch（每 100 条 commit）
  → 逐表 insert（显式 id）
  → 校验四项：行数 / SUM(word_count) == metadata.totalWordCount /
              SELECT date 集合 == metadata.uniqueDates / 抽样 20 篇逐字段比对
  → 通过：close → rename 为目标库 → prefs 写 migration_v1_done=1, db_engine='sqflite'
     **不删除任何 prefs 键**（回滚保险）
  → 失败：删临时库 + 上报 + 继续用 prefs（用户无感）
```

要求：迁移在**首帧之后** + 进度弹窗（N=5000 需 10~30 s）；**幂等**（`migration_v1_done==1` 跳过，临时库残留直接删）；迁移后校验一次"冷启动用 sqflite 读到 N 篇且首篇 content 与 prefs 解密值一致"才切开关。

#### Phase 3（观察 1~2 个版本）：清理
确认无回退请求 → 停止写 prefs → 再观察 → 才删 prefs 大键。**永远不要在同一版本里既迁移又删源。**

#### 灰度顺序
`Phase 0` 全量（零风险）→ `Phase 1` 内部账号 → `Phase 2` 按**设备**抽样 5%/20%/100%（不按账号，避免同步问题）→ `Phase 3`。

### 4.4 一个需要产品拍板的决策：搜索与加密的冲突

FTS5 要能做中文子串检索，索引里就得存**明文**（中文无空格分词，`unicode61` 切不开，必须 `tokenize='trigram'`，且要求 SQLite ≥3.34 —— Android 14 才普遍满足，必须版本探测降级）。这与"日记本地加密"承诺冲突。三个选项：

1. **FTS5 + 明文索引** —— 搜索最好用，但明文落盘，削弱加密承诺；
2. **FTS5 + 仅存分词 token** —— 不存原文，安全性居中；
3. **不做 FTS** —— 后台 isolate 分批 `SELECT id,title,content` → 解密 → `contains` → 只回传 id。N=5000 约 300~800 ms，配合 300 ms 防抖 + 2 字下限可接受。

> **推荐**：本轮先做第 3 条（零 schema 变更、可立即上线），Phase 1 迁移时再按产品决策上 FTS5。

### 4.5 依赖关系图

```
B0-1 图片 cacheWidth ────────────────────────────► 无依赖，最先做
B0-2 分键增量写 ──┬──► B0-3 合并 tag 写盘（同文件，先合后拆）
                  └──► B1-5/B1-6 Splash 与加载并行（需先有"写不慢"才敢保证启动快）
B0-4 wordCount ──► B0-8 统计批量（wordCount 缓存后才能省统计页 CPU）
B0-2 ─────────────► Phase 0 ─► Phase 1 ─► Phase 2 ─► Phase 3
                    （Phase 0 可与 Batch 1 完全并行，互不冲突）
B1-1 ─► B1-2 （先提 DateFormat 常量，再上索引，否则索引收益被格式化吃掉）
```

---

## 五、第五轮思考：验收、风险与门禁

### 5.1 验收指标（**必须真机 + release/profile 包**，debug 包结论无效）

| 指标 | 当前（估） | 目标 | 测量方法 |
|---|---|---|---|
| 冷启动到可交互 | 2.5~4.5 s | **1.0~1.4 s** | `adb shell am start -W` 看 `TotalTime`；或 DevTools Performance 首帧时间戳 |
| 保存一篇日记（N=1000） | 1.3~1.8 s | **<100 ms** | DevTools Timeline 找 `jsonEncode` / `encryptTextV2` / `setString` span |
| 日历翻月单帧 | 8~20 ms（N=1000） | **<2 ms** | Performance overlay / Timeline build 段 |
| 统计页进入 | 60~120 ms | **<20 ms** | 同上 |
| 特殊主题帧时间 | 16 ms 打满 | **6~9 ms** | Timeline；对照切默认主题 |
| 全屏看图内存峰值 | ~150 MB（3 张原图） | **<20 MB** | DevTools Memory 面板 `currentSizeBytes`（ImageCache） |
| 冷启动内存峰值（N=1000） | ~10 MB 仅数据层 | **<3 MB** | Memory 面板 |
| jank 率（滚动 10 s） | 待测 | **<1%** | DevTools Performance 帧统计 |
| APK 体积 | 92 MB | **<45 MB**（单 ABI）+ 字体内联则 <25 MB | `abiFilters` 分 ABI 包 |

### 5.2 必须真机验证的假设（静态分析无法定论）

| # | 假设 | 验证方法 | 若成立则影响排期 |
|---|---|---|---|
| V1 | 保存耗时 >60% 在 Dart 侧全量重加密 | Timeline flame chart 看 span 占比 | 成立则 B0-2 提到最高优先 |
| V2 | ImageCache 峰值 >80 MB | Memory 面板 | 成立则 B0-1 最高优先 |
| V3 | 切 tab 后 1 s 内 MainScreen build ≥4 次 | Timeline + `debugPrint` 计数 | 成立则 B1-9/B1-2 提前 |
| V4 | 统计页每次进入都全量重算（无缓存） | 打点 Stopwatch 包 `_loadStats` | 成立则 B0-8 提前 |
| V5 | 特殊主题帧时间显著高于默认主题 | 对照 A/B | 成立则 B1-3 提到 Batch 0 |
| V6 | 云同步峰值 ≈4.7× 总图片体积 | heap snapshot（确认 `ArchiveFile.content` 实际类型） | 成立则必须改分卷 |
| V7 | 冷启动 7 个 await 各自耗时 | 每项前后打 Stopwatch，release 包 | 决定 B1-4 能省多少 |
| V8 | PDF 导出峰值 | Memory 面板 + 单篇 20 图复现 | 决定 B0-5 是否足够 |

> ⚠️ **V7/V8 必须用 release 或 profile 包**：`AppProtectionService` 仅 release 执行，debug 包测不出真实启动路径。

### 5.3 风险清单与对策

| 风险 | 级别 | 对策 |
|---|---|---|
| native 是**从未编译的死代码** | 高 | Phase 0 的编译门 + ffi 单测是**强制前置**，否则切换当天 `NoSuchMethodError` |
| 补 API 时漏了（5 → 13） | 高 | CI 门禁：两边 static 成员名集合必须相等 |
| `import*` upsert/skip 漂移导致云同步静默丢数据 | 高 | 统一 upsert + 单测（同 id 二次导入必须覆盖） |
| `is_encrypted` 语义 | 高 | 现状写入恒置 1、读取**不看该列一律解密** → 历史明文行会解出乱码。迁移时逐行 `isEncrypted()` 判定并写真实值 |
| 自增 id 冲突 | 中 | 迁移用显式 id；校验 `SELECT MAX(id)` 后再插入不冲突；云同步远端 id 混用问题**现状已存在**，需回归一次 |
| `flutter test` 会选到 native | 中 | 条件导出下 `dart.library.io` 在测试 VM 为 true → 现有 164 个用例任何碰 `DatabaseService` 的都会 `MissingPluginException`。对策：`setUpAll` 设 `databaseFactory = databaseFactoryFfi`，或门面在 `kDebugMode` 仍走 prefs |
| 迁移中断（杀进程/OOM） | 中 | 临时库 + 幂等 + 事务 + 成功后才 rename；绝不半写目标库 |
| R1 止血后"回退"到旧行为 | 中 | B0-2 保留 `diaries_data` 整库键作为迁移/回滚源，双写直到 Phase 3 |
| 测试网太薄（日记主链路零测试） | 高 | Phase 0 必须补数据层契约测试；Batch 0 每条改动都要求手写一条回归用例 |

### 5.4 工程门禁（建议本轮就建）

1. **`dart analyze lib test`** 进 CI（不要用 `flutter analyze`，它会隐式 `pub get` 并重写 `pubspec.lock`）。
2. **死代码门禁**：CI 报告"零 import 的 lib 文件"清单（本方案已产出基线，见附录 B）。
3. **依赖门禁**：`pubspec.yaml` 里零 import 的依赖必须删（见附录 A）。
4. **性能预算**：CI 里跑 `flutter build --profile` + 真机脚本，冷启动/保存耗时超预算即红灯。
5. **无 `print`／`debugPrint` 进 release**：当前 `lib/` 有 132 处 `print` + 253 处 `debugPrint`，建议统一走 `debugPrint`（`print` 在 release 仍输出）。

---

## 六、附录 A：包体与依赖清理（低风险，可立即做）

### A.1 实测收益表（含精确测量结果）

| 项 | 现状（实测） | 动作 | 实测/预期收益 |
|---|---|---|---|
| `table_calendar` | 零 import（日历页是手写 `GridView.count`） | 删除依赖 | 少一个包 |
| `turn_page_transition` | 零 import | 删除依赖 | 少一个包 |
| `cupertino_icons` | 零 import；唯一内容 `CupertinoIcons.ttf` **251.6 KB** | 删除依赖 | -251.6 KB |
| `sqflite` | 仅 `database_service_native.dart` 引用 | **保留**（Phase 2 要用） | 移除后原生注册 21 → 20 |
| `NotoSerifCJKsc-VF.ttf` | **23.97 MB**（占 APK 26%），**UI 层零使用**（`design_tokens.dart:183` 的 `serifHeading` 无消费者），**仅服务 PDF 导出** | ① **fontTools 子集化：GB2312 7,542 字符 + VF 全轴 = 5.45 MB（省 18.5 MB）**；② 先钉 `wght=400` 静态实例再子集 = **3.22 MB（省 20.7 MB）**；③ 或改为运行时下载 | **最多 -20.7 MB** |
| `splash_cover.png` | 1080×1920 RGBA **2.35 MB** | 720×1280 WebP q82 = **40.7 KB**（即便保原分辨率 WebP q82 也仅 75.6 KB） | **-2.3 MB**，解码 8 MB → ~1 MB |
| `icon_bulb_original.png` | **3.41 MB**，refs=**0** | 删 | **-3.41 MB** |
| `bg_wooden_frame.png` | **2.93 MB**，refs=**0** | 删 | **-2.93 MB** |
| `icon_bulb.png` | 431 KB / 2088×2088，refs=3 | 缩到 512px WebP ≈ 9.5 KB | -421 KB |
| `abiFilters` | 3 套 ABI 全打（arm64 + v7a + x86_64） | `--split-per-abi` 或 `abiFilters += ["arm64-v8a","armeabi-v7a"]` | 92 MB → **~35 MB/包** |
| release 签名 | debug keystore | 换正式 keystore | 分发信任链 |

**合计保守可省：约 6.3 MB（原生大图）+ 2.3 MB（splash）+ 0.25 MB（图标字体）+ 字体内联取舍 18.5~20.7 MB ≈ 27~30 MB**，叠加 ABI 拆分后**目标 <45 MB（单 ABI）**。

### A.2 字体方案的可执行路径（已核实"只差接线"）

`font_download_service.dart` **已具备完整下载能力**：`http` + `IOClient` + 12 个镜像 URL（jsDelivr / 清华 / 中科大 / 阿里云 / ghproxy 等）+ 重试 + 字体头校验。但 `_fonts` 里两个 `url` 都写死 `''`（注释"已打包到APK，无需下载"）。

→ **方案③（运行时下载）只差两步**：把 `:20`/`:26` 的 `url` 改成镜像路径 + 删 `pubspec.yaml` 的 font asset 条目。**但要注意**：字体**只服务 PDF 导出**（UI 层零使用），所以首次导出时下载 6~8 MB 会带来等待，需要配合进度提示；离线用户则会导出失败。**建议优先选方案①（子集化 5.45 MB 内联）**——兼顾包体与离线可用性，且 PDF 只用常用字集完全够用。

> ⚠️ `assets/images/` 下 6 个图标（`app_icon` / `icon_coral` / `icon_mint` / `icon_pink` / `icon_starry` / `playstore_icon`）实测零引用且**未被 pubspec 声明**（不进包），仅作源文件保留，无需处理。

## 七、附录 B：死代码基线（约 9,800 行零 import，其中约 8,500 行可清理）

> 实测口径：对 `lib/` 下 169 个文件逐个统计"被其他文件 import 次数"，含 `export` 间接引用一并计入。总计 **9,845 行**零 import；扣除 `database_service_native.dart`（1,189 行，Phase 2 目标）与 OCR 有意保留（191 行）后，**实际可清理约 8,465 行**。

| 文件 | 行数 | 说明 |
|---|---|---|
| `lib/services/database_service_native.dart` | 1,189 | **Phase 2 的目标实现**，勿删 |
| `lib/widgets/paged_diary_list.dart` | 803 | 0 import |
| `lib/screens/emotion_stats_screen.dart` | 802 | 0 import（`_v2` 是活的） |
| `lib/screens/time_capsule_list_screen.dart` | 737 | 0 import（`_v2` 是活的） |
| `lib/screens/diary_search_enhanced_screen.dart` | 679 | 0 import |
| `lib/widgets/goal_progress_card.dart` | 754 | 0 import |
| `lib/widgets/voice_recorder_button.dart` | 564 | 0 import（`_v2` 是活的） |
| `lib/screens/smart_recall_screen.dart` | 552 | 0 import（`_v2` 是活的） |
| `lib/widgets/diary_templates.dart` | 519 | 0 import |
| `lib/widgets/starry_background.dart` | 380 | 0 import（`theme_backgrounds.dart` 自带同名类） |
| `lib/screens/profile_screen_min.dart` | 334 | 0 import，但需先确认与主 profile 无逻辑分叉 |
| `lib/services/backup_reader.dart` | 338 | 0 import |
| `lib/services/incremental_sync_service.dart` | 341 | 0 import |
| `lib/widgets/lazy_image.dart` | 303 | 0 import（"懒加载"未接线） |
| `lib/widgets/swipeable_list_item.dart` | 303 | 0 import |
| `lib/services/mbk_backup_reader.dart` | 292 | 0 import |
| `lib/widgets/empty_state.dart` | 266 | 0 import |
| `lib/screens/backup_test_screen.dart` | 214 | 0 import |
| `lib/widgets/bento_card.dart` | 189 | 0 import |
| `lib/screens/ocr_service_settings_dialog.dart` | 136 | **OCR 有意保留未接线**，勿删（见 AGENTS.md） |
| `lib/utils/safe_area_helper.dart` | 95 | 0 import |
| `lib/services/course_import/ocr_import_source.dart` | 55 | **OCR 有意保留**，勿删 |

> 清理价值主要在**认知**而非运行时：`lazy_image.dart` 名为"懒加载"却从未接线，后续很容易有人以为图片已优化；`paged_diary_list.dart`（803 行）是一套完整的分页列表实现，但实际列表用的是 `timeline_screen` 里的 `ListView.builder`。**建议先清 `_v1` 系列 5 个文件（≈3,400 行）与 `paged_diary_list`/`lazy_image`/`starry_background`**，`database_service_native.dart` 留到 Phase 2。

### B.2 更精确的可达性统计（审计员用传递可达性重算）

| 口径 | 结果 |
|---|---|
| `lib/` 文件总数 | 169 |
| 从 `main.dart` **传递可达** | 141 / 169 |
| **传递不可达** | **30 个文件 / 12,976 行** |
| 其中可删（非 OCR） | **23 个文件 / 11,465 行** |
| 仅被 `export` 但零调用方 | 4 个文件 / 1,981 行（`page_transitions` 344 / `accessibility_components` 578 / `performance_optimizations` 530 / `security_utils` 529） |
| **OCR 有意保留** | 7 个文件 / 1,511 行（**勿删**：`test/ocr_import_test.dart` 有 458 行单测锁着，删了会红） |

> **这与附录 B.1 的 9,845 行不矛盾**：B.1 统计的是「直接零 import」，B.2 是「传递不可达」——后者更严谨（能抓到 A 被 B import、但 B 本身不可达的情况），所以数字更大。**排期时用 B.2 的 11,465 行作为可删上限，B.1 作为逐项清单参考。**

### B.3 同类 v1/v2 重名类（删除前必须确认导出归属）

`emotion_stats_screen.dart`(v1) 与 `emotion_stats_screen_v2.dart`(v2) **都定义了同名类 `EmotionStatsScreen`**（v1 `:12`、v2 `:9`）。已核实：`stats_screen.dart:12` import 的是 `_v2`，`:941` 调用的是 v2 的实现，**v1 零 import → 删 v1 安全**，但需确认没有并列导出造成歧义。同理需检查 `profile_screen`/`profile_screen_min`、`time_capsule_list_screen`/`_v2`、`smart_recall_screen`/`_v2`、`voice_recorder_button`/`_v2`。

## 八、本方案的置信度与已修正项

交叉复核（`.perf-analysis/crosscheck.md` 416 行 + `crosscheck-c3.md` 142 行，**共 13 条抽样**）对四份审计做了独立验证，结论分层如下。**引用本方案时请注意每一条的证据等级。**

| 报告 | 可信度 | 说明 |
|---|---|---|
| `data-layer.md` | **最高（事实密度）** | 量化模型最有决策价值；13 个缺失 API、写放大公式均经独立推导吻合 |
| `ui-render.md` | **最高（机制严谨）** | 逐条引用 Flutter 框架源码定位（`overlay.dart`、`proxy_box.dart`、`page_view.dart`），做法应作为后续审计的模板 |
| `startup-native.md` | 高 | 德国式核实（`commit()` vs `apply()`、R8 是否开启、`largeHeap` 三份 manifest 全查），并主动纠正了 Lead 的一处误判 |
| `heavy-features.md` | 方向对，机制层需谨慎 | 曾系统性把 `AnimatedBuilder` 局部重建误判为整树每帧 rebuild（**同一错误 3 次**，均已更正并沉淀三步判据）。但需注意：该报告**另有 4~5 条「每帧」表述经核实是正确的**（P2-1 特殊主题、两个 `AnimatedBuilder` 子树内重建、`gacha:389` 常量子树、`:656` `TweenAnimationBuilder`）。**结论是「个别条目机制失准」而非「该报告不可信」** —— 且它已按 crosscheck 与自查完成返工（A1/A5/A6 + 自查第三处），引用时应取当前版本 |

### 已修正的 7 处（本方案已采用更正后口径）

1. **PDF 字体"双份浪费"这个定性部分成立，需分两层看**：
   - ✅ **成立**：`_chineseBoldFont` 确实没被 `exportDiaries` 使用（全仓库零处作为 `TextStyle.font`）。
   - ✅ **新发现**：它的唯一加载入口 `preloadFonts()` **全仓库零调用者**，所以那份 23.97 MB **在真实导出路径上从未被解析**。
   - ❌ **不成立**：原报告据此推出的「峰值 90~130 MB、删掉省 70~120 MB」不成立 —— 实际只解析 1 份（≈36~60 MB）。
   - **正确性质**：`preloadFonts()` + `_loadChineseBoldFont()` 是**死代码**，删除**无运行时收益**，仅作清理防未来误接。P0 的真实支撑机制是「图片原图不缩放 + `exportSingleDiary` 无张数上限」。
2. **云同步峰值从 3× 上调为 4.7×**：`Archive` 累积 1 份 + `Isolate.spawn` 深拷贝 1 份 + `zipBytes` + `fromList` 拷贝 + 密文 ≈ 5 份存活物。
3. **`gacha_screen` "每帧 240 次 prefs 读取"不成立**：4 处 `FutureBuilder` 中仅 1 处在首屏 build 路径（另 3 处在 bottom sheet builder 内，独立 route）；`build()` 零 `addListener`；`setState` 全程 **5 次**（`:70/:79/:100/:114/:126`）；`getInstance()` 有单例缓存、`getInt` 纯内存查表。已降级 P3。
4. **`stats_screen` "每秒 60 次全量扫描"不成立**：`addListener` 命中 0；文件虽有 2 个 `AnimatedBuilder` + 1 个 `TweenAnimationBuilder`，但**均不包住**被指控的去年今日卡子树。已降级 P3。
5. **`profile_screen` "每帧重建"不成立**：`addListener`=0、`AnimatedBuilder`=0、`TweenAnimationBuilder`=0、`AnimationController`=0，驱动是 `initState` 里 4 个并发服务回调（`:70/:83/:93/:103`）各触发一次 `setState`。
6. **搜索问题的严重度需限定（重大修正）**：审计最严重指认的「增强搜索每键全量 `getAllDiaries` + 零防抖」位于 `diary_search_enhanced_screen.dart`，而**该文件是死代码**（零 import，我已独立核实；真实入口是 `diary_search_screen.dart`，被 `calendar_screen.dart:22` 与 `stats_screen.dart:8` 引用）。→ **代码缺陷属实，但当前零用户影响**。真实入口的真问题是**数据源只覆盖 20 篇**（`:58` 用 `provider.diaries` 而非全量），这是**正确性 bug**（用户搜不到第 21 篇以后的日记，会以为日记丢了），应优先修。
7. **一处方法论缺陷（复核员自评）**：复核「搜索无防抖」时只验证了「代码里写的是什么」，**没验证「这段代码是否真会被执行」**。本项目中死代码并非孤例（已发现 4 处），这类文件会让审计报告产生"不存在的问题"并误导排期 —— **建议把「可达性验证」列为审计的强制步骤**（见附录 B.2）。

> **判据防误用说明**（审计过程中真实踩到，见 §1.3 的三步判据）：`theme_backgrounds.dart` 的 `addListener` **也是 0**，但它**确实每帧重绘** —— 走的是路径 (b)：`AnimatedBuilder` 直接驱动 `CustomPaint`，而 `child` 是整棵树。所以**「没有 addListener」≠「不会每帧重建」**，还必须看动画 widget 是否真的包住目标子树。我独立复跑确认：`theme_backgrounds` `addListener`=0 / `AnimatedBuilder`=5 / `..repeat()`=7；`stats_screen` 0 / 2 / +1 `TweenAnimationBuilder`；`gacha_screen` 0 / 1 / +3 —— 与审计报告数字一致。

### 一处需要连带修正的因果表述（重要）

早期口述中曾出现「`loadRecentDiaries` 触发全量重加密」的说法，**这是错的**。正确链路：

```
insertDiary (database_service_web.dart:439) → :447 _saveDiaries()   ← 全量重加密在这里
loadRecentDiaries (diary_provider.dart:80-94)                        ← 只读，全量排序（纯 CPU）
```

`loadRecentDiaries` 只是额外的**全量排序开销**，不落盘。本方案 §1.1 / §2 已按此口径表述。

### 一处需要修正的索引分析精度

`getDiariesByDate` 存在**两个同名但不同实现**的版本，讨论索引时必须区分：

| 实现 | 调用点 | 加索引是否有效 |
|---|---|---|
| `DatabaseService.getDiariesByDate`（真 DB 查询） | **仅 3 处**：`stats_screen.dart:1449`、`goal_service.dart:256,307` | ✅ 有索引后受益 |
| `DiaryProvider.getDiariesByDate`（内存 `where`） | 4 处：`calendar_screen.dart:421,713,1437,1770` | ❌ **加索引完全无效**，只能靠 §4.2 的 B1-2（Provider 预计算 `_byDate`） |

同理 `tag_diaries_screen.dart:52` 调的是 `DatabaseService.getDiariesByTagId(int)`（旧 ID 版），而 `tag_system_service.dart:317` 调的是 `getDiariesByTagIdV3(String)` —— 两者索引策略不同（前者走 `diary_tags`，后者走 `diary_tags_v3`）。

### 未覆盖（本方案未下结论的领域）

- `write_diary_screen` / `profile_screen` / `gacha_screen` / `stats_detail_screen` / `diary_detail_screen` 全文逐行审计。
- 网络层（WebDAV 同步成功率与重试策略）、数据库加密密钥丢失后的恢复流程。
- 内存泄漏（长期驻留对象的 heap 增长曲线）—— 需真机 heap snapshot 对比。

## 九、附录 C：审计报告索引

| 文件 | 内容 | 规模 |
|---|---|---|
| `.perf-analysis/data-layer.md` | 数据层量化模型、索引设计、迁移方案、9 条止血 | 325 行 |
| `.perf-analysis/startup-native.md` | 启动时间线拆解、原生层、闪退假设、构建配置 | 472 行 |
| `.perf-analysis/ui-render.md` | P0×6 / P1×9 / P2×11，7 条可复现卡顿路径、8 项死代码 | 341 行 |
| `.perf-analysis/heavy-features.md` | 重功能页 P0×6、机制与量级（已按 crosscheck + 自查返工 A1/A5/A6） | 825 行 |
| `.perf-analysis/heavy-features-appendix.md` | 8 条用户旅程问题地图 + 三批排期 + 8 条真机验证 | 384 行 |
| `.perf-analysis/crosscheck.md` | 抽样复核 10 条：成立 7 / 不成立 1 / 部分成立 2；含「报告可信度分层」 | 416 行 |
| `.perf-analysis/crosscheck-c3.md` | 第 4 轮复核 6 条：判据条款 / 五行实测表 / 死代码发现 | 142 行 |
| `.perf-analysis/data-layer-baseline.md` | 独立索引基线（交叉验证对照物） | 9.6 KB |
| **`OPTIMIZATION_PLAN.md`** | **本文：五轮思考 + 分阶段方案 + 验收/风险/门禁** | 519 行 |

> 阅读建议：**先看本文**，需要某个具体问题的证据链时再按 ID 去对应报告查 `file:line`。
