# C3 复核（第 4 轮）：heavy-perf 判据条款重构 + 自曝新错修正

> 复核对象：`heavy-features.md:657-687`（三步判据条款 + 五行实测表）、`heavy-features-appendix.md:321-337`、以及它自曝并修正的「四文件两步均为 0」错误。
> 方式：只读源码 + 独立复跑计数。**未修改被复核报告。**
> 结论：**成立。数字与归属逐项核对无误，且它新报的一条事实使我的 A3 结论需要加限定。**

---

## C3-1 ✅ 五行实测表的数字：**全部准确**

我按「声明数」口径独立复跑（这是唯一正确口径 —— `AnimationController` 的引用数会被 `_controller.forward()` 等放大，不能当声明数用）：

| 文件 | addListener | AnimationController（声明） | AnimatedBuilder | TweenAnimationBuilder | `.repeat()` |
|---|---|---|---|---|---|
| `stats_screen.dart` | **0** | **2** | **2** | **1** | 0 |
| `gacha_screen.dart` | **0** | **2** | **1** | **3** | **1** |
| `profile_screen.dart` | **0** | **0** | **0** | **0** | 0 |
| `emotion_stats_screen.dart` | **0** | **0** | **0** | **0** | 0 |
| `theme_backgrounds.dart` | **0** | **14** | **5** | 0 | **7** |

**与 `heavy-features.md:681-685` 表格逐格吻合。**

⚠️ 附一条**口径陷阱说明**（我首次复跑时踩到，记录以免后续复核者重复）：
我最初用 `grep 'AnimationController'` 得到 `stats=4 / gacha=9`，与表格的 `2 / 2` 不符 —— 但那是把**声明 + 类型标注 + 引用**混算了。按声明（`AnimationController(`）复跑才是 `2 / 2`，与表格一致。
**报告表格用的是正确口径，我首次的差异是我的计数方法问题，不是报告错误。**

---

## C3-2 ✅ `gacha_screen` 的 `setState` = 5 处：**准确，且它修正了自己漏掉的那处**

它说 `:70`（`_loadRemainingDraws`）+ 动画状态切换 `:79/:100/:114/:126`，共 5 处。我复跑：

```
70: setState(() {      ← 来自 _loadRemainingDraws()
79: setState(() {      ← _startDraw 开始晃动
100: setState(() {     ← _stopShakeAndDraw
114: setState(() {     ← 拿到抽奖结果
126: setState(() {     ← finally 收尾
```

**精确 5 处，行号全对。** 它此前写 4 处、本轮自查补上 `:70`，修正正确。

---

## C3-3 ✅ 三个 `TweenAnimationBuilder` 的归属：**全部准确**

它说 `:660` 在 `_buildRewardCard`、`:1929`/`:2218` 在成功动画方法内。我逐个追溯 enclosing method：

| 行 | enclosing method | 起始行 |
|---|---|---|
| `:660` | `_buildRewardCard()` | `:482` |
| `:1929` | `_showPurchaseSuccessAnimation()` | `:1903` |
| `:2218` | `_showThemePurchaseSuccessAnimation()` | `:2192` |

**三处归属全部正确。** 且这三处都是**局部子树**（奖励卡自身、成功弹窗自身），不包含首屏 `build()` —— 与它「A5 不成立」的结论一致。
其中 `:1929`/`:2218` 用于 600ms 的礼花/缩放动画，作用域是 `Column > TweenAnimationBuilder > Transform.scale`，确实只影响该弹窗自身的子树。

---

## C3-4 ✅ 三步判据条款：**结构正确，防误用警告位置已按要求前移**

`heavy-features.md:657-687` 现在的结构（我逐行读）：

1. **前置认知**（`:659`）：`AnimatedBuilder`/`TweenAnimationBuilder` 只重建 builder 子树；`Transition` 不触发 rebuild。
2. **判定规则**（`:661-663`）：**(a) 有 `addListener`+`setState`** 或 **(b) 目标子树被动画 widget 包住**，满足其一即成立。
3. ⚠️ **紧跟规则下方的防误用警告**（`:665-668`）—— **这正是我上轮建议的核心，已落地**：
   > **(b) 不要求 `addListener`。** `AnimatedBuilder` 通过 `animation:` 自行订阅 `Listenable`，不需要文件里出现任何 `addListener`。因此 **`grep addListener` 返回 0 时，只能排除 (a)，绝不能据此判定「不会每帧重建」—— 必须继续查 (b)。**
   并给出现成反例：`theme_backgrounds.dart` addListener=0 但满足 (b) → P2-1 成立。
4. **两步验证命令**（`:670-676`），并明确「第二步即使第一步为 0 也要跑」。
5. **五行实测表**（`:679-685`）。
6. ⚠️ **表下教训**（`:687`）：**「文件里有动画 widget ≠ 整棵树每帧重建；判据 (b) 问的是『目标子树有没有被包住』」**。

**结构合理，警告位置正确。** 我上轮建议的「把 (b) 不要求 addListener 贴到条款本身」已完整落地，且比我建议的更细（它还加了「三步」的第三层：作用域判定）。

---

## C3-5 ✅ 它自曝的「新写错的一处」——**确实存在，且修正正确**

它承认：重构时在实测结论里写了「四个文件**两步均为 0**」，跑了一遍发现是错的（`stats_screen` 实际有 2 AB + 1 TAB，`gacha_screen` 有 1 AB + 3 TAB + repeat）。

**这个自曝是诚实的、内容也准确**（我 C3-1 的复跑证明两文件动画 widget 确实不为 0）。修正为「逐文件五行实测表」后：
- 保留了「文件级动画计数」这一栏（如实反映「有动画」）；
- 新增「目标子树是否被包住」一栏（真实判定）；
- 表下补教训明确「文件里有动画 ≠ 整棵树每帧重建」。

**从「两步均为 0」的错误表述 → 「三步判据 + 作用域判定」的正确框架**，这是实质进步，不是文字修饰。

---

## C3-6 🔴 它新报的一条事实，**推翻了我 A3 的适用范围** —— 需要给我自己的结论加限定

它新报（`heavy-features.md:690`）：
> `diary_search_enhanced_screen.dart` 同样是**死代码**：全项目无任何文件 `import 'diary_search_enhanced_screen.dart'`（grep 零命中）。当前实际入口只有 `diary_search_screen.dart`（`calendar_screen.dart:237` + `stats_screen.dart:367`）。

**我独立核实：成立。**

```text
=== imports of diary_search_enhanced_screen (lib + test) ===
（零命中）
=== imports of diary_search_screen (the real one) ===
lib/screens/calendar_screen.dart:22: import 'diary_search_screen.dart';
lib/screens/stats_screen.dart:8:   import 'diary_search_screen.dart';
```

**这对我的 A3 结论有实质影响：**
- 我在 A3 里判「增强搜索 `onChanged` 每键直调 `_performSearch`、零防抖」= **成立**（代码事实层面仍然成立 —— 该文件代码确实如此）。
- **但「该问题影响用户」这一层不成立**：因为该页面**从未被挂载**，用户根本碰不到。
- 因此 **A3 的严重度应下调**：从「P0-3（用户可感知的每键全量解密）」改为「**代码级缺陷，但因死代码而当前零影响**」。

**修正后的 A3 结论：**
> **成立（代码事实）**，但**该文件是死代码（零 import，我已独立核实）→ 当前无用户影响**。修复优先级应改为「若计划接线则必须先做防抖 + 重入守卫；否则直接删除文件」。真正需要关注的搜索性能问题在**实际入口 `diary_search_screen.dart`**（我未审计该文件，建议 heavy-perf 或后续任务补审）。

这条很重要 —— **它体现了我本轮复核的方法论缺陷**：我只验证了「代码里写的是什么」，**没有验证「这段代码是否真的会被执行」**。而死代码问题在本项目里并非孤例（本轮已发现 3 处：`emotion_stats_screen.dart` v1、`diary_search_enhanced_screen.dart`、`performance_optimizations.dart`）。**该审计员在这一点上比我严谨。**

---

## C3-7 附：也让 `theme_backgrounds` 的独立复跑结果对齐

它说独立复跑我的数字「全部吻合」。我确认我上轮给出的 `theme_backgrounds.dart`：`addListener`=0 / `AnimatedBuilder`=5 / `AnimationController`=14 / `.repeat()`=7 —— **本轮再次复跑，完全一致**。

---

## C3 结论

| 项 | 判定 |
|---|---|
| 五行实测表数字 | ✅ 准确（我首次口径不同，非报告问题） |
| `gacha` setState=5 及行号 | ✅ 精确，且修正了自己漏的 `:70` |
| 3 个 TAB 归属 | ✅ 全部正确（`:660`→`_buildRewardCard`、`:1929`/`:2218`→成功动画方法） |
| 三步判据条款结构 | ✅ 正确，防误用警告位置已按要求前移 |
| 它自曝的新错 | ✅ 确实存在且修正正确，是实质进步 |
| 它新报的死代码事实 | ✅ 成立，**且使我 A3 需加「死代码、零用户影响」限定** |

**总体：C3 成立。** 该审计员本轮做了三件超出要求的事：① 接受建议并重构条款；② 自查出自己新写的错（「两步均为 0」）；③ 发现 `diary_search_enhanced_screen` 与 `emotion_stats_screen` 两个死代码，**后者直接影响了我 A3 的严重度判断**。

**给 Lead 的汇总更新：**
1. **A3 严重度下调**：`diary_search_enhanced_screen.dart` 是死代码（零 import，已核实），该缺陷**当前零用户影响**。真实搜索入口是 `diary_search_screen.dart`（`calendar_screen:237`、`stats_screen:367`），未审计。
2. 本轮 crosscheck 累计发现**3 处死代码**：`emotion_stats_screen.dart`(v1)、`diary_search_enhanced_screen.dart`、`performance_optimizations.dart`（8 个 RepaintBoundary 全在无 import 文件内）+ `utils.dart:39` 的 `RepaintBoundaryWrapper` 导出但 profile_screen 零使用。**建议在汇总里单列一个「死代码清理」项** —— 这类文件会让审计报告产生「不存在的问题」，也会误导后续优化排期。

---

*复核时间：2026-10-28 · 只读核对，未修改被复核报告*
