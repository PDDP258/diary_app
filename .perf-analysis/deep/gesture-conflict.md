# 深挖 2：手势冲突与 Gesture Arena 审计

> 项目：小记日记（Flutter 3.x）｜审计日期：2026-11-03
> 范围：`lib/` 全部手势竞技场冲突点。**只读审计，未改动任何源码。**
> 结论先行：**最严重的问题是 `main_screen.dart` 用「onTapDown + 2s Timer」伪造长按**。
> 它同时踩中 3 个坑：① 绕过竞技场裁决（onTapDown 在裁决前触发）；② 2s 与系统 500ms
> 标准长按不同步；③ 松手时又让下层 onTap 照常执行 → **一次按住可能触发两个动作**。

---

## 0. 审计口径与事实基线

| 项 | 值 | 采集方式 |
|---|---|---|
| 全 lib `GestureDetector` | 155 | `Select-String` 全量扫描 |
| `onLongPress` | 27 | 同上（去重后 27 个回调点） |
| `onTapDown` / `onTapUp` | 11 / 9 | 同上；**不成对**（11 按下只有 9 抬起） |
| `Dismissible` | 9 字面命中 → **真 widget 仅 1 处** | 8 处是 `barrierDismissible`（见 §1.5 校正） |
| `Draggable` 字面命中 | 2 | 实际是 `_buildDraggableSticker` 方法名，**全库无 `Draggable` widget** |
| `InteractiveViewer` | 5 | diary_detail:1243 / stats_detail:1239 / write_diary:2615 / image_cache_service:753,756 |
| `HitTestBehavior.translucent` | 3 | main_screen:658 / custom_sticker_overlay:91 / swipeable_list_item:247 |
| 框架常量（Flutter 源码） | — | `kPressTimeout=100ms`、`kLongPressTimeout=500ms`、`kTouchSlop=18`、`kPanSlop=36`、`kDoubleTapTimeout=300ms` |

三条必须先讲清的框架语义（后面所有结论都建立在它上面）：

1. **`onTapDown` 不是「按下即触发」**。`BaseTapGestureRecognizer` 的 deadline 是
   `kPressTimeout = 100ms`（`gestures/tap.dart:212`），`didExceedDeadline()` 才 `_checkDown()`
   （`tap.dart:343-345`）。若此指针的竞技场在 100ms 内就只剩它一个成员，则会
   立刻 `acceptGesture → _checkDown()`（`tap.dart:348-355`）。**但无论哪种路径，都在
   竞技场裁决之前或同时**——此时 `onTapCancel` 还没来，业务代码已经把副作用（起 Timer）做掉了。
2. **`translucent` 的语义是「加进命中链，但不算命中」**。`RenderProxyBoxWithHitTestBehavior.hitTest`
   （`rendering/proxy_box.dart:183-192`）：`hitTarget = 子命中 || hitTestSelf`，
   `hitTestSelf => behavior == opaque`；而 `translucent` 只是在 `hitTarget` 为 false 时
   **仍然把自己的 BoxHitTestEntry 塞进 result**。返回值仍为 false。
   后果：父级 `Stack` 的 `hitTestChildren` 会**继续往更下层找**（因为 false），
   但本 recognizer 已经拿到 down 事件 → **参加竞技场**。
3. **`Stack` 命中从「最后一个子级（视觉最上层）」往前找，第一个返回 true 就停**
   （`RenderBoxContainerDefaultsMixin.defaultHitTestChildren` 逆序遍历）。
   所以 main_screen 里导航栏（Stack 第 3 个孩子）会**先于**内容层 GestureDetector 拿到命中。

---

## 1. 长按冲突矩阵（区域 × 手势 × 竞技场优先级 × 实际结果）

先给结论：**凡是本区域内存在「自己的 500ms onLongPress」的位置，外层的 2s 速记 Timer
永远不会触发**——因为内层 long press 在 500ms `resolve(accepted)` 时把外层 tap 判负，
外层 `onTapCancel`（forced）取消 Timer。**真正会「炸」的是「只有 onTap、没有 onLongPress」
的区域**：2s 到了先弹速记，松手后那个 onTap 还会照常执行（见 §1.3）。

### 1.1 竞技场成员与裁决顺序

`GestureArenaManager` 的规则（`gestures/arena.dart`）：
- `sweep(pointer)`：**第一个成员赢**（`arena.dart:170-178`）——在 `PointerUpEvent` 时发生；
- 任一成员 `resolve(accepted)` → 立即给它，其余全部 `rejectGesture`（`arena.dart:233-240`）；
- 成员顺序 = **命中链从深到浅**（子级 recognizer 先 add）。所以「深者优先」，同 sweep 时子级赢。

`main_screen.dart:632-674` 的手势树：

```
Positioned.fill(bottom: systemNavBarHeight)      // :630-631
└ GestureDetector( behavior: translucent,        // :632 / :658
    onTapDown/onTapUp/onTapCancel )              // :634 / :652 / :655
  └ NotificationListener<ScrollNotification>     // :659
    └ SafeArea → ThemeBackgroundFactory.wrap     // :661-663
      └ PageView(physics: NeverScrollable)       // :665-669  ← 竖向滚动全部下放到 tab 内
        └ TimelineScreen / Calendar / Stats / Profile
          └ RefreshIndicator → ListView.builder  // timeline:208-213
            └ item → TiltCard(pan+tap+longPress) // timeline:773-786, diary_interactions:181-188
              └ 横向 ListView(图片条)            // timeline:953-954
```

### 1.2 矩阵表

| # | 区域（file:line） | 区内意图 | 竞技场成员（深→浅） | 500ms 时 | 2s 时 | 实际结果 |
|---|---|---|---|---|---|---|
| A | 日记卡片 `timeline_screen.dart:773-786`（TiltCard） | ①看详情 ②长按菜单 ③滚动 ④外层速记 | TiltCard 6 个识别器（pan / tap / longPress）+ ListView 竖向 drag + 外层 tap | **TiltCard longPress 赢**：`_onDiaryLongPress` 弹底部菜单 | 外层已被判负，Timer 已 cancel | ✅ 菜单正常；速记**不会**二次触发 |
| B | 卡片内图片条 `timeline_screen.dart:953-991` | ①横滑看图 ②长按菜单(父) ③竖滚 ④外层速记 | 内层横向 drag + TiltCard(pan/tap/longPress) + 外层竖向 drag + 外层 tap | TiltCard longPress 赢（500ms）→ 弹**日记菜单**（用户只想横滑看图） | 已判负 | ⚠️ 横滑图片时误触卡片长按菜单（除非在 500ms 前滑过 36px panSlop / 18px 横滑 slop） |
| C | 日历贴图 `custom_sticker_overlay.dart:90-112` | ①拖动 ②长按菜单 ③日历滚动 ④外层速记 | 贴图 pan + 贴图 longPress + 外层 tap(+日历滚动) | 贴图 longPress 赢 → 贴图选项 sheet | 已判负 | ✅ 面板正常，但**贴图本身不可见/不可点**（见 §3.5 坐标 bug） |
| D | 导航栏 FAB `custom_bottom_nav.dart:87-89` | ①点击写日记 ②长按选写日记/自言自语 | FAB tap + FAB longPress（**外层不在**：Stack 命中先停在导航栏） | FAB longPress 赢 → `_onAddLongPress` | **外层根本不参与**（未收到 down） | ✅ 无冲突（见 §2 为何「点导航栏不会起速记 Timer」） |
| E | 右上速记悬浮球 `main_screen.dart:681-683` | ①点击开速记 ②长按开列表 | 悬浮球 tap + 悬浮球 longPress + 外层 tap | 悬浮球 longPress 赢 → `_openQuickNotesList` | 已判负 | ✅ 无冲突 |
| F | **纯 onTap 区域**（月历日期格 `calendar_screen.dart:572/664`、profile 卡、统计卡、各类 InkWell 行） | ①点击 ②（无长按） ③外层速记 | 内层 tap + 外层 tap | 无 long press 成员 → 无人 accept | **2s Timer 准点触发 → 弹速记编辑器** | ❌ **按住 2 秒（≥2.0s）→ 速记；松手 → 内层 onTap 仍然执行。一次操作两个动作** |
| G | 空白/无命中区（导航栏隐藏时的底部带、卡片间空隙） | ①外层速记 | 仅外层 tap（单成员竞技场立刻 accept，`arena.dart:254-255`） | — | **T+2.0s 触发**（空白区是立即 accept，比 F 早 100ms） | ✅ 设计意图（空白长按速记），但无进度反馈 |
| H | 内嵌 InteractiveViewer 图（diary_detail:1237-1243 等） | ①双指缩放/拖动 ②实况长按播放 ③外层速记 | 外层 GestureDetector longPress + InteractiveViewer scale/pan | 外层 longPress 赢 → 播放实况 | 已判负 | ⚠️ 单指按住 500ms 即触发「播放实况」，与「捏合缩放起手」同区域（缩放要 2 指，通常不冲突） |

**一句话版**：A/C/D/E/H 都靠「内层 long press 抢赢」自洽；**F 是黑洞**——2s 后再叠一次
松手 onTap，是真正会伤到用户的「二次触发」。

### 1.3 F 类的量化与典型受害面

- 时序：`down → (100ms, onTapDown) → 起 Timer(2000ms) → T+2100ms 弹速记 → 用户松手 up
  → 竞技场 sweep → 内层 tap 赢 → 执行 onTap`。
- 空白区时：单成员竞技场在 down 后下一 microtask 即 accept（`arena.dart:251-263`），
  `onTapDown` **约 0ms** 触发，2s 到点时刻 = **T+2.000s**，比 F 早 100ms。
- 受害面（`onTapDown` 只在 main_screen 一处，但 onTap 遍布全库）：
  `calendar_screen.dart` 的日期格（572/664）、`profile_screen.dart` 各类入口卡
  （250/491/620/740/841/1238/1275…）、`stats_screen.dart:1411`、
  `custom_bottom_nav.dart` 的 `AnimatedFAB:238-244`（但它不在命中链里）、
  `diary_interactions.dart:55-62` 心情选择器、`bento_card.dart:66-69`。
- 因果链的「松手仍执行」是 Flutter 正确行为：外层 tap 在 sweep 时被 reject，
  但**内层 tap 是赢家**，它执行自己的 onTap 与 fling 无关；外层 `onTapCancel` 只是取消 Timer。

### 1.4 「2s vs 系统 500ms」结论

- `kLongPressTimeout = 500ms`（`gestures/constants.dart:29`），是 Material 全平台一致的长按标准；
  `main_screen` 用 2000ms，**4 倍于系统阈值**，用户肌肉记忆完全不匹配。
- 更糟的是它**不是 long press recognizer**，所以：无 `onLongPressUp` 语义、无 `onLongPressStart`、
  无可配置 `duration`、无法 hedge 到竞技场、**且不产生任何进度反馈**（只在到点时
  `HapticFeedback.heavyImpact()`，`main_screen.dart:648`）。
- 直接后果：用户按 1.5s 松手 → 什么都发生（Timer 被 `onTapUp` 取消，`:652-654`）；
  按 2.0s+ → 突然弹编辑器。**区间外全是死区**，这是「按了没反应 / 有时候突然弹」投诉的根因。

---

## 1.5 事实校正（逐行复核 9 处 Dismissible / 3 处 translucent 后）

| 原口径 | 复核结果 | 说明 |
|---|---|---|
| `Dismissible` **9 处** | **实际 1 处** | 9 处字符串命中里 **8 处是 `barrierDismissible`**（`showDialog` 的属性，与手势无关）：app_lock:511 / data_management:1461 / gacha:1909,2198 / inbox:90 / badge_service:2353,2572 / milestone_service:199。真正的 `Dismissible` 只有 `quick_notes_screen.dart:232`（`direction: DismissDirection.horizontal`）。 |
| `Draggable` **2 处** | **实际 0 处** | 两处命中是方法名 `_buildDraggableSticker`（custom_sticker_overlay.dart:71/75），全库无 `Draggable` widget。 |
| translucent `swipeable_list_item.dart:247` | 属 **`ExpandableListItem`（手风琴 header）**，不是 `SwipeableListItem` 的自实现侧滑 | 且 `swipeable_list_item.dart` **全库零 import**（只有自身定义）→ **死代码**，运行期零影响。`swipeable_list_item.dart` 与 `real_page_turn.dart` 的 `RealPageTurn` 均未被引用（后者仅 `splash_screen.dart:7` 引入 `SplashPageTurn`）。 |
| `PageView` 参与横向竞技场 | **零成员** | `main_screen.dart:668` `physics: NeverScrollableScrollPhysics` → `Scrollable.setCanDrag(false)` 会清空 `_gestureRecognizers`（`scrollable.dart:775-780`），PageView 不进竞技场。跨 tab 只由 `_onNavTap` / `animateToPage` 驱动。 |
| `onTapDown` 11 处中 1 处是死代码 | `custom_bottom_nav.dart:238-244` 的 `AnimatedFAB` 全库只定义、**零调用** | 其余 10 处活的：main_screen:634 / MoodSelector（`diary_interactions.dart:60`）/ TiltCard（`:185`，方法体 `:163`）/ _AnimatedTag（`:295`）/ BentoCard:66 / InteractiveButton:116 / AnimatedFeedback:77,238 / VoiceRecorder:536 |

> 结论：**3 处 translucent 中运行期真正生效的只有 2 处**（main_screen:658、custom_sticker_overlay:91）；
> swipeable_list_item:247 是死代码。`Dismissible` 也不存在「9 处叠加」问题。

---

## 2. translucent 命中语义与「点导航栏会不会起速记 Timer」

### 2.1 三种 behavior 的框架语义（`rendering/proxy_box.dart:147-195`）

| behavior | `hitTestSelf` | 行为 | 对下层/同层后果 |
|---|---|---|---|
| `deferToChild`（默认） | false | 只有**子级命中**才把自己加入命中链 | 空白处既不加自己、也不拦截 → 手势收不到 |
| `opaque` | **true** | 自己一定命中，且返回 true | **阻断**之后（视觉更下层/更早的兄弟）的命中 |
| `translucent` | false | **无论子级是否命中，都把自己 add 进 result**；返回值仍是 `hitTarget`（false） | recognizer **参与竞技场**，但不阻断下层 |

关键推论：`GestureDetector` 的识别器是否参与竞技场，**只取决于它有没有进入 hitTestResult**；
`translucent` 保证「指针落在盒内就进入」，所以 main_screen 的外层 tap 识别器
**在页面内容区的每一次按下都会参赛**，哪怕按的是卡片/列表——它只是永远输给更深的识别器。

### 2.2 `main_screen.dart:658` 逐条定性

**(a) 页面内容区：外层每次都参赛 → 每次按下都起 2s Timer。**
`Positioned.fill`（`:630-631`）+ `translucent` ⇒ 点到卡片、列表、空白，外层都被 add 进链，
`TapGestureRecognizer` 在 `kPressTimeout=100ms`（或竞技场提前只剩它时立刻）发出 `onTapDown`
→ `_justTapped=true` + `_showNavBar()` + `Timer(2s)`（`:634-651`）。这就是 §1 F 类黑洞的放大器。

**(b) 点导航栏：外层收不到 down → 不起速记 Timer（主结论成立）。**
导航栏是 Stack 第 3 个孩子（`:710`，`bottom: systemNavBarHeight, height: 88`）。
`Stack`/`defaultHitTestChildren` 逆序遍历（`rendering/box.dart:3337-3352`，`lastChild → firstChild`，
第一个 `isHit == true` 立即 return）。导航栏内部的底板 `Container`（`custom_bottom_nav.dart:30-32`）
带 `BoxDecoration(borderRadius…)` → `RenderDecoratedBox.hitTestSelf → BoxDecoration.hitTest`
（`proxy_box.dart:2468-2470` / `painting/box_decoration.dart:375+`）**返回 true** →
Stack 在该孩子处停下 → 内容层（含外层 GestureDetector）**根本不在命中链** → 不起 Timer。

**(c) 但导航栏有 3 个「命中洞」，落在洞里就会起 Timer（这才是真问题）。**
几何：带内 y = 0..88；底板 `Container(height: 80, margin: LTRB(12,0,12,8))` → 只覆盖 **y = 0..80**
（margin-box 对齐 bottomCenter）；FAB `Positioned(bottom: 12)` 72dp → y = 4..76 圆形区。
于是带内以下区域**没有任何 DecoratedBox 覆盖 → hitTest 返回 false → 继续往下穿透到内容层**：

| 洞 | 区域 | 后果 |
|---|---|---|
| ① 底部条 | y = 80..88 整条（8dp） | 点导航栏下沿 → 无导航动作，且外层起 2s Timer（按住 2s 弹速记） |
| ② 左右边距 | x < 12 或 x > W-12，y = 0..80 | 同上（点导航栏两侧空白 → 起 Timer） |
| ③ 动画期 | 见 (d) | 幽灵命中 |

面积占比（W=400dp）：`(8×400 + 12×2×80) / (88×400) = (3200+1920)/35200 ≈ 14.5%`。
即**约 1/7 的导航栏带是「假导航区」**：点了没导航反应，按住却会弹速记。

**(d) 隐藏态的幽灵命中（AnimatedOpacity 只影响绘制，不影响命中）。**
`AnimatedSlide(offset: (0, 1.5))` 把整块下移 `1.5×88 = 132dp`（`:716`），完全移出屏幕 → 静息态基本收不到命中。
但 **250ms 滑出/滑入期间**：`AnimatedOpacity → FadeTransition → RenderAnimatedOpacity` 只覆写
`paint()` / `paintsChild()`，**未覆写 `hitTestChildren`**（`proxy_box.dart:1107-1117` + `RenderAnimatedOpacityMixin:1075-1087`）
→ 半透明的导航栏仍然**可点可拦**。这就是「导航栏刚淡出时点底部会误触/没反应」的来源。
（补充：200ms 时 `AnimatedOpacity` 已到 0，但 `AnimatedSlide` 还要再走 50ms —— 这 50ms 里
「完全看不见但仍在拦」最典型，是幽灵命中的直接证据。）

**(e) 隐藏态下「导航栏应该在的位置」会把点击直通给外层。**
滑出结束后（offset 1.5 → 下移 132dp），导航栏整块离开屏幕，命中全部穿透；
而内容层 `Positioned.fill` 的底边正好是 `H - systemNavBarHeight`，覆盖了这条带子
⇒ **导航栏隐藏时，点底部原本放导航栏的位置会直接打到外层 GestureDetector**
（起 2s Timer + `_showNavBar`）。这本身符合 AGENTS.md「点击无效区域显示导航栏」的意图，
但代价是：**在这条带上按住 2s 会弹速记**——用户只是想「把导航栏唤回来」，却拿到了编辑器。

### 2.3 `custom_sticker_overlay.dart:91` —— 一个真 bug + 一个热区问题

**bug（贴图不可见/不可点）：坐标系错配。**
`:76-90` 用 `MediaQuery.size` 归一化的 `positionX/Y` 算出 `left/top`（约 0.08~0.92 × 屏高 = **80~720dp**），
但 `Positioned` 是相对**所在 Stack** 的坐标。日历页把 overlay 挂在
`Container(height: 80)` → `ClipRRect` → `Stack` 里（`calendar_screen.dart:461-463, 468-503`）：
- `top ≈ 80..720dp` **全部落在 80dp 高的 Stack 之外**；
- `Stack` 默认 `Clip.hardEdge` → `RenderClipRRect`（`_RenderCustomClip.hitTest`，`proxy_box.dart:1628-1638`）
  对 clip 外坐标**直接 `return false`** → 贴图**画不出来也点不到**（`RandomStickerOverlay` 同挂法，同样被裁）。

**热区（20dp 隔离带的反例）：**
`:83-90` `hitAreaSize = maxSize < 100 ? 100 : maxSize + 20`，child 是
`Container(decoration: BoxDecoration(color: transparent, borderRadius: 12))` →
`RenderDecoratedBox.hitTestSelf → BoxDecoration.hitTest` **不看 alpha**，矩形/RRect 内一律 true
⇒ 60dp 的贴图实际吞掉 **100×100** 触摸面积，四周各 20dp 隐形热区会抢走日历日期格的点击。
（在日历页因 bug 不可见；在写日记页 `write_diary_screen.dart:1060` 是全屏 Stack，热区是真生效的。）

### 2.4 `swipeable_list_item.dart:247`（死代码）

属 `ExpandableListItem` 手风琴 header 的 `GestureDetector`（`onTap: _toggle` + translucent），
全库零引用 → 运行期无影响。若将来启用：translucent + 父级列表项 tap ⇒ 双触发，应改 `opaque`。

---

## 3. 滚动 vs 按下冲突、跨轴误判与导航栏抖动

### 3.1 「按下即副作用」的实际代价

滚动起手：down → 竞技场未裁决 → **100ms 时外层 onTapDown 已经发出** → 起 2s Timer + `_justTapped=true`（300ms）
→ 指针移动超 `kTouchSlop=18` 后竖向 drag 接受 → 外层 tap 被 reject → `onTapCancel` → Timer 取消。
所以**滚动不会误弹速记**（除非滚动前静止 ≥2s），真正的代价是：

1. 每次按下都进入 `_showNavBar` / `_resetInactivityTimer` 路径（`_showNavBar` 在不可见时 setState 一次）；
2. `_justTapped` 的 300ms 会**丢弃前 300ms 的全部滚动通知**（`:453-454`）：
   慢起手（先按 100ms 再滑）时导航栏响应滞后 300ms，之后阈值突然生效 → 观感「先不动、再突然消失」；
   快甩（slop 在 100ms 内超）不会设 `_justTapped`，行为又不一致 → 手感不稳定。

### 3.2 真 bug：`_onScrollNotification` 没有过滤 `depth` / `axis`

`NotificationListener`（`:659`）监听的是**所有后代视口**的通知。`ScrollNotification` 沿 viewport 上冒时
`depth` 自增（`ViewportNotificationMixin`，`scroll_notification.dart:28-42`）。而 `_onScrollNotification`
（`:449-489`）**既不看 `depth` 也不看 `metrics.axis`**，于是：

- `timeline_screen.dart:953-954` 的**横向**图片条 `ScrollUpdateNotification` 也会进入这个 handler；
  它的 `scrollDelta` 是**水平**位移 → **左右滑图片会让导航栏按「竖向滚动」逻辑显隐**（右滑 show、左滑 hide）；
- 同理：quick_notes 的横向 chip 条（`quick_notes_screen.dart:154-155`）、calendar 横向 row、
  gacha 横向列表等，全都会污染导航栏。

**修复的正确判据（depth 不能简单的 `!= 0`，这点很容易写错）：**
`depth` 从 Scrollable 自身起算 0，每经过一个 `_ViewportElement` +1（`scroll_notification.dart:52-59`，
`viewport.dart:239-241`）。本树的层数是：

| 滚动源 | 经过的 viewport | 到 `main_screen` listener 时的 depth |
|---|---|---|
| PageView 自身（已禁滚，无通知） | 0 个（其 viewport 是 Scrollable 的**子级**，不进上冒路径） | 0（实际不发生） |
| 各 tab 的竖向 ListView / SingleChildScrollView / GridView | PageView 的 viewport ×1 | **1** ← 唯一应处理 |
| 时间线内嵌横向图片条 | PageView ×1 + 时间线竖向 ListView ×1 | **2** |
| quick_notes 横向 chip 条、日历内嵌 ListView | 同上（各多一层） | ≥2 |

所以正确写法是 **`if (notification.depth != 1 || notification.metrics.axis != Axis.vertical) return false;`**
（即「只认 tab 内顶层竖向滚动」）。若只写 `depth != 0`，会把**所有** tab 滚动全部丢掉 → 导航栏彻底不再响应滚动。

### 3.3 抖动概率量化（`>10` 隐藏 / `<-5` 显示）

60Hz 下 `delta(px/帧) = v/60`：

| 手势速度 | 单帧 delta | 触发 |
|---|---|---|
| 300 px/s（慢读） | 5 | 显示阈值（-5）**刚好命中**；隐藏（>10）不动 |
| 600 px/s（正常滑） | 10 | 隐藏阈值临界（>10 才动） |
| 1200 px/s（快甩） | 20 | 立即隐藏 |

结论：
1. **显示阈值比隐藏灵敏 2 倍**（5 vs 10）。「滑一段（≥600px/s）→ 回一点点（≥300px/s）」：
   隐藏动画（250ms）刚起，回拉 1~2 帧就 >5 → 立刻 `_showNavBar`（再来 250ms 反向动画）→
   继续下甩 1 帧 >10 → 又 hide。**一次反向微调可产生一次完整 show→hide 循环，两段 250ms 动画互相打断 = 肉眼闪烁**；
   2~4 次/秒的往复微滑即可稳定复现。这是「抖动」的主来源，不是滚动本身。
2. **行走/手持微动**：指腹随步态的相对位移约 3~10px/帧，`σ≈6px` 高斯抖动下
   `P(|Δ|>5)≈40%`、`P(|Δ|>10)≈9.6%` ⇒ 几乎每隔几帧就会越过 -5 → 导航栏一隐藏就被轻微回拉唤醒，
   形成「**隐藏 → 抖两下冒出 → 5s 无操作再消失**」的 5 秒周期闪现（因为 `_showNavBar` 会
   `_resetInactivityTimer()`，5s 从最后一次抖动重新计时）。
3. **显示态的上滑慢滚永不自动隐藏**：每帧 `scrollDelta < -5` 都 `_resetInactivityTimer()`（`:472-474`），
   慢速上滑持续 10s 就一直重置 → 停下 5s 后才消失。语义上「上滑显示」没错，但配合 5s 计时器就变成
   「只要还在滑就永远不隐藏」，与「下滑立即隐藏」的确定性完全不对称。

附带死代码：`_lastScrollPixels`（`:66/:477`）只写不读；`_longPressTriggered`（`:77/:644/:647`）只写不读。

---

## 4. 阈值不对称的具体数值建议

**现状问题表：**

| 场景 | 现在（>10 / <-5） | 问题 |
|---|---|---|
| 慢速下滑 300~500px/s | delta 5~8 → 不隐藏 | 用户以为「滑了怎么还在」 |
| 回拉一点点 | delta -5 立即 show | 灵敏 2 倍 → 闪烁 |
| 停下后 | 5s 后隐藏 | 与「上滑显示」重叠时被不断重置 |
| 阈值带 | 无滞后、无冷却 | 相邻帧可反向翻盘 |

**建议（对称 ±8 + 方向滞后 + 冷却）：**

- 阈值：**进入隐藏需同方向累计 `> +8px`；进入显示需同方向累计 `< -8px`**（对称）；
- **滞后（hysteresis）**：`_navScrollAccum` 累加器，**方向一翻转立即清零**——这是关键：
  它保证中间不存在「一帧就翻盘」，等效形成一个 16px 的动作带宽（`[-8, +8]` 内不动作）；
- **冷却 200ms**：`_navToggleAt` 时间戳，距离上次切换 <200ms 不再切换（覆盖 250ms 动画的 80%，
  动画不再被打断）；
- **显示态不要每帧重置 inactivity**：只在「状态从隐藏→显示」或用户 tap 时重置，
  否则慢速上滑永远不自动隐藏；
- 可选：`ScrollUpdateNotification` 前 300ms 的 `_justTapped` 抑制改为「只抑制 1 帧 + 只抑制 <2px 的微抖」
  （当前 300ms 全丢，导致响应滞后）。

---

## 5. 侧滑 / 横滑 / 翻页三方叠加

**层次事实（Timeline 日记卡）：**

```
ListView（竖，depth 0，VerticalDrag）
└ TiltCard（:773-786）→ GestureDetector（diary_interactions.dart:181-188）
    onPanUpdate / onPanEnd / onPanCancel / onTapDown / onTapUp / onTapCancel / onLongPress
  └ Container
    └ Column
      └ 图片条：ListView(scrollDirection: horizontal)（timeline_screen.dart:951-954，depth 1，HorizontalDrag）
```

**接受条件（框架）：** 横/竖 drag 各自在主轴累计 > `kTouchSlop=18` 接受；
`PanGestureRecognizer` 需 `kPanSlop=36`（`gestures/constants.dart:65,76`）；
long press 在 `kLongPressTimeout=500ms` `resolve(accepted)`（`long_press.dart:641-646`）。

**裁决顺序与实际结果：**

| 输入 | 谁先 accepted | 结果 |
|---|---|---|
| 横向移动 >18px | 内层横向 drag（最深、指针事件先派发 → 先 `resolve(accepted)` 成为 winner） | 图片条滚动；页面不滚；卡片不倾斜 |
| 竖向移动 >18px | 外层竖向 drag | 页面滚动；图片条不动 |
| 斜向 >36px 但单轴都 <18 | TiltCard pan（`kPanSlop=36` 的接受条件反而更宽松） | 卡片倾斜（若到达 36 前单轴已过 18，则被滚动抢先） |
| 静止按住 500ms | TiltCard longPress（图片条无 long press、无 tap） | **弹「编辑/删除日记」底部菜单** —— 用户在图片上长按想看图，结果弹菜单 ❌ |
| 静止按住 2s | 同上（100ms 起的外层 Timer 已被 longPress 判负取消） | 仍只弹卡片菜单（不会二次弹速记 ✅） |

**结论：**
1. 横/竖双轴共存本身是 Flutter 标准解法，**不会互相抢**（方向锁），主要风险是「按住不动时卡片菜单抢走图片区的长按」与 §3.2 的通知污染；
2. `timeline_screen.dart:953-991` 的图片 item **没有 onTap** → 点图无任何反应（用户预期是看大图），
   建议补 `GestureDetector(onTap: () => 打开大图)`；
3. `Dismissible` 实际只有 `quick_notes_screen.dart:232-234` 一处（横向、左右都 `return false`，只做置顶/删除），
   在竖向 ListView 中方向锁正常，**当前不存在「同轴 Dismissible × PageView」竞争**（PageView 已禁滚）；
4. 若未来把 `Dismissible` 放进横向 PageView，才会出现「同轴竞争」（Dismissible 的 horizontal drag vs
   PageView 的 horizontal drag），那时需要 `Dismissible` 的 `dragStartBehavior: DragStartBehavior.down`
   或改用手势方向判定；当前无此结构。

---

## 6. 20dp 隔离带落点清单（widget 级）

| # | 落点（file:line） | 当前问题 | 改法 |
|---|---|---|---|
| 1 | `main_screen.dart:710-730` 导航栏 | 250ms 淡出期幽灵命中；底部 8dp / 左右 12dp 命中洞 | 外层包 `IgnorePointer(ignoring: !_isNavVisible)`；整带包一层 `GestureDetector(behavior: opaque, onTap: (){})` **吃掉穿透点击**（最小改动、不改视觉） |
| 2 | `main_screen.dart:632-658` 全屏 GestureDetector | `onTapDown + Timer(2s)` 绕过竞技场 → F 类黑洞 | **改为标准 `onLongPress`（500ms）**（§7 a）——内层有 long press 时天然抢赢，等价于「只有空白区生效」，**不需要任何 IgnorePointer 隔离带** |
| 3 | `main_screen.dart:630-631` 内容 `Positioned.fill(bottom: sysNav)` | 内容与导航栏 88dp 重叠，列表最后一项被压住且点击穿透 | 给各 tab 滚动容器底部加 88 + sysNav 的 padding（20dp 隔离带的实际落点） |
| 4 | `timeline_screen.dart:215-216` | `bottom: 16` → 最后一张卡在导航栏下面 | 改 `bottom: 112`（88 + 8 + 16） |
| 5 | `calendar_screen.dart:1168-1171` / `profile_screen.dart:225` | 同上（底部列表/滚动视图） | 加 `padding: EdgeInsets.only(bottom: 104)` |
| 6 | `custom_sticker_overlay.dart:83-90` | 100×100 隐形热区（+20dp/边）抢日期格点击 | 去掉 child 的透明 `color` + `borderRadius` 装饰（让 decoration 不命中）；`hitAreaSize = maxSize + 20`（**每边 +10**，不是 +20/边） |
| 7 | `calendar_screen.dart:461-503` 两个 overlay | 挂在 80dp 高容器里 → 坐标越界被裁 | 提到页面级 `Stack`（`:110`），坐标改 `LayoutBuilder` 相对本 Stack（§7 c） |
| 8 | `diary_detail_screen.dart:287` `RandomStickerOverlay` | 纯装饰但 `Container(decoration)` 的 `hitTestSelf=true`，在 Stack 顶层**吞掉正文/按钮点击** | `IgnorePointer(child: RandomStickerOverlay(...))`（`:273-318` 是 `AnimatedOpacity`，不拦命中） |
| 9 | `write_diary_screen.dart:1060-1065` | 贴图热区压在输入区；随机贴图概率 0.8 很高频 | 同 6 / 8 处理 |
| 10 | `timeline_screen.dart:951-954` 图片条 | 点图无反应；通知污染导航栏 | 显式 `hitTestBehavior: HitTestBehavior.opaque`（防回退）+ 每个 item 加 `onTap`；外层与卡片之间加 `Padding(vertical: 8)` |
| 11 | `main_screen.dart:676-708` 速记悬浮球 44dp | 无问题 | **保持默认 `deferToChild`，不要改 translucent**（改 translucent 会让它下方也收到 down） |

---

## 7. 代码级修复片段

**(a) 用标准 500ms 长按替换 `onTapDown + Timer(2s)`**（`main_screen.dart:632-658`）

```dart
// 删除：_longPressTimer / _longPressTriggered / Timer(seconds: 2) / _justTapped 联动
GestureDetector(
  behavior: HitTestBehavior.translucent, // 保留：让空白区也能收手势
  onTapDown: (_) {                       // 只做导航栏显隐，无副作用
    _showNavBar();
    _resetInactivityTimer();
  },
  // ✅ 500ms 标准长按：内层卡片/标签的 long press 会先 accepted 抢赢，
  //    因此这里天然只对「没有内层长按的空白区」生效；且长按 accepted 会
  //    把同一竞技场里的 tap 判负 → 松手不会再触发下层 onTap（消灭 F 类黑洞）。
  onLongPress: () {
    HapticFeedback.mediumImpact();
    _openQuickNoteEditor();
  },
  child: NotificationListener<ScrollNotification>(
    onNotification: _onScrollNotification,
    child: SafeArea(bottom: false,
      child: ThemeBackgroundFactory.wrap(/* … 原样 …*/),
    ),
  ),
)
```
> 若产品坚持要「2 秒」：用 `RawGestureDetector` 的
> `LongPressGestureRecognizer(duration: const Duration(seconds: 2))`，
> **不要**再自己 `Timer`——这样它才在竞技场里、松手也不会二次触发。
> 同时必须给进度反馈（长按 500ms 后显示环形进度），否则 1.5s 松手仍是死区。

**(b) 滚动阈值：同步对称 + 滞后 + 冷却 + 深度/轴过滤**（`main_screen.dart:449-489`）

```dart
double _navScrollAccum = 0;
DateTime _navToggleAt = DateTime.fromMillisecondsSinceEpoch(0);

bool _onScrollNotification(ScrollNotification n) {
  // ✅ depth==1 = 只认「PageView viewport 之下的 tab 顶层滚动」；
  //    depth>=2 是内嵌滚动（横向图片条 / chip 条 / 内层列表）一律忽略。
  //    ⚠️ 不要写 depth != 0 —— 那样会把所有 tab 滚动都丢掉。
  if (n.depth != 1 || n.metrics.axis != Axis.vertical) return false;
  if (_isPageChanging) return false;

  if (n is ScrollEndNotification) {
    _navScrollAccum = 0;
    if (n.metrics.pixels <= 0) { _showNavBar(); _resetInactivityTimer(); }
    return false;
  }
  if (n is! ScrollUpdateNotification) return false;
  if (n.metrics.maxScrollExtent <= 0) return false;

  final d = n.scrollDelta ?? 0;
  if ((d > 0 && _navScrollAccum < 0) || (d < 0 && _navScrollAccum > 0)) {
    _navScrollAccum = 0;                 // ✅ 方向翻转清零 = hysteresis 核心
  }
  _navScrollAccum += d;

  final now = DateTime.now();
  if (now.difference(_navToggleAt) < const Duration(milliseconds: 200)) return false; // ✅ 冷却

  if (_navScrollAccum > 8 && _isNavVisible) {
    _hideNavBar();
    _inactivityTimer?.cancel();
    _navScrollAccum = 0;
    _navToggleAt = now;
  } else if (_navScrollAccum < -8 && !_isNavVisible) {
    _showNavBar();
    _resetInactivityTimer();
    _navScrollAccum = 0;
    _navToggleAt = now;
  }
  return false;
}
```

**(c) 贴图坐标修复（`custom_sticker_overlay.dart:64-90` + 调用点）**

```dart
// 1) 调用点（calendar_screen.dart:461-503）：把两个 overlay 从 80dp 装饰容器里拿出来，
//    挂到页面级 Stack(calendar_screen.dart:110) 的最上层：
Stack(children: [
  /* 原 Column 内容 */
  const CustomStickerOverlay(targetPage: 'calendar'),
  const IgnorePointer(child: RandomStickerOverlay(targetPage: 'calendar', appearProbability: 0.6)),
])

// 2) overlay 内改用本 Stack 的约束，而不是 MediaQuery：
Widget build(BuildContext context) {
  if (_isLoading || _stickers.isEmpty) return const SizedBox.shrink();
  return LayoutBuilder(builder: (context, c) {
    final w = c.maxWidth, h = c.maxHeight;   // ✅ 相对本 Stack，而不是 screen
    return Stack(children: [
      for (final s in _stickers)
        Positioned(
          left: (s.positionX * w - 50).clamp(0, w - 100),
          top:  (s.positionY * h - 50).clamp(0, h - 100),
          width: 100, height: 100,
          child: _buildDraggableSticker(s, w, h),
        ),
    ]);
  });
}
```

**(d) 装饰层禁止吃点击**（`RandomStickerOverlay` 的所有调用点）

```dart
IgnorePointer(child: RandomStickerOverlay(targetPage: 'calendar', appearProbability: 0.6))
```

---

## 8. 复核清单（改完后逐条验证）

> 本节给「实现者」执行；审计本身只读，未跑任何 flutter/dart 命令。
> 注意 AGENTS.md：只用 `dart analyze`，不要 `flutter analyze`（会隐式 pub get 重写 lock）。

1. **静态**：`Select-String -Pattern 'Duration\(seconds: 2\)' lib/screens/main_screen.dart` → 无命中；
   `_longPressTimer` / `_longPressTriggered` / `_justTapped` 全库应为 0（或仅剩无副作用用法）。
2. **静态**：`dart analyze lib` 无新增 warning/error；`Select-String -Pattern 'depth != 1' lib/screens/main_screen.dart` 命中 1 处。
3. **竞技场日志**：Debug 下置 `debugPrintGestureArenaDiagnostics = true`
   （`gestures/debug.dart`），在日记卡片上按住 2s：期望只见 `LongPressGestureRecognizer` 一次
   `Accepting` + 一次 `Winner`，**不再出现「速记编辑器」**；松手后不再触发卡片 onTap。
4. **F 类黑洞回归**：进「我的」页，在用户卡片（`profile_screen.dart:250`，只有 onTap）上
   按住 2.0s 后松手 → 旧行为是「弹速记 + 随后跳转编辑弹窗」；新行为应为「500ms 弹速记，松手不再跳转」。
   用断点/日志确认 `_openQuickNoteEditor` 只调用 1 次、卡片 onTap 未执行。
5. **导航栏命中洞**：手指按在导航栏**底边 8dp** 与**左右 12dp 边距**处 → 不应再弹速记；
   点 4 个 tab 图标 + 中间加号均正常切页/开菜单。
6. **导航栏淡出幽灵**：下滑隐藏导航栏后，在 250ms 动画期间立即点底部 → 不应被看不见的导航栏拦截
   （`IgnorePointer(ignoring: !_isNavVisible)` 生效）。
7. **跨轴通知**：时间线里左右滑图片条 10 次 → 导航栏**不得**显隐变化；
   同时在横向 chip 条（quick_notes:154）重复一遍。
8. **抖动**：`flutter run --profile` 下，时间线慢速下甩/回拉各 5 次 —— 导航栏位移应单调，
   单次往复最多触发 1 次切换；录屏逐帧确认 250ms 动画不被打断。
9. **行走/手持**：导航栏隐藏后轻晃手机/走 20 步 → 不应自动冒出（阈值 -8 + 方向累计 + 200ms 冷却生效）。
10. **贴图**：日历页放 3 张贴图 → **必须出现在屏幕上**（当前为空是坐标 bug）；
    拖动 20dp 能移动、松手保存；点贴图**旁边**的日期格能正常选中（热区不再 100×100）。
11. **装饰层不吞点击**：日记详情正文/底部按钮上若有随机贴图覆盖 → 点击仍生效（`IgnorePointer` 生效）。
12. **回归**：`dart test`（若实现者环境可用）全绿，重点 `test/course_widget_*` 与既有手势相关用例不受影响。
