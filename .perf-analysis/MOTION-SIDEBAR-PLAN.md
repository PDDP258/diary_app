# 小记日记 · 动效与侧边栏交互优化方案

> 证据基础：`.perf-analysis/deep/` 三份深度报告共 **1,404 行**，全部只读审计、`lib/` 零改动
> 审计方式：代码约束流逐层推导 + cubic-bezier 解析求导 + Flutter SDK 源码比对 + **实测探针验证**
> 说明：本 App **没有 Drawer 侧边栏**（全仓 grep 0 命中），「侧栏」= 「我的」页分组菜单 + 底部导航

---

## 0. 三条必须先立的根基事实

这三条决定了后面所有判定：

| # | 事实 | 出处 | 为什么重要 |
|---|---|---|---|
| **F1** | **`onTapDown` 不是「按下即触发」** —— `BaseTapGestureRecognizer` 有 `kPressTimeout = 100ms` deadline | `gestures/tap.dart:212,343-355` | 有 100ms 延迟窗口 |
| **F2** | **`onTapDown` 发生在竞技场裁决之前** | 同上 | 业务代码在「谁赢还不确定」时就做了副作用（起 Timer）→ 这是所有冲突的根 |
| **F3** | **`HitTestBehavior.translucent` = 「加进命中链但不算命中」** | `rendering/proxy_box.dart:183-192` | 它返回 false，父 Stack 会继续往下找 → 上层和下层的 recognizer **同时参加竞技场** |

补充框架常量（判定基准）：`kPressTimeout=100` / `kLongPressTimeout=500` / `kTouchSlop=18` / `kPanSlop=36` / `kDoubleTapTimeout=300`。

---

## 1. 问题诊断（含量化）

### 1.1 菜单（分组菜单 `profile_screen.dart:2283`）

| # | 别扭点 | 精确证据 | 量化后果 |
|---|---|---|---|
| M1 | 圆角层级倒挂 | 容器 `16`(:2287) vs 图标底板 `radius12`(:2317) | 内框比外框更圆 → 双重切线 |
| M2 | 分割线硬凑 | `indent: 76`(:2298) / `endIndent: 20`(:2299) | 左 76 右 20，视觉重心偏右 28dp |
| M3 | 行高不稳定 | `contentPadding vertical: 6`(:2304) | 带/不带副标题行高差 **10dp**（64 vs 74） |
| M4 | **热区与视觉错位** | 图标底板 44×44(:2306-2307) 看着是唯一可点块，实际整行可点 | 用户认知与行为不一致 |
| M5 | **组间比组内还紧** | 组间 `SizedBox(16)`(:275/288/...) vs 组内行距 64 | 16 : 64 = **0.25**，分组感消失 |

### 1.2 抽屉/弹层（**40 处** `showModalBottomSheet`）

| 参数 | 实测分布 | 判定 |
|---|---|---|
| **圆角 shape** | 未设 **13** 处 / `16` **4** 处 / `20` **17** 处 / `24` **3** 处 | **6 种并存**，且无一等于 `AppTheme.xxlRadius=48` |
| `isScrollControlled: true` | **21 / 40** | 19 处未开，键盘弹出必遮（AGENTS.md 记载的坑未全局修复） |
| `barrierColor` | **0 / 40** | 遮罩全是框架默认，无品牌一致性 |
| `sheetAnimationStyle` | **0 / 40** | 入场/退场完全走框架默认，无法做「轻退场」 |
| `useSafeArea` | 2 处 | 其余靠 `SafeArea` 手写 |

### 1.3 图标（底部导航 `custom_bottom_nav.dart:132-193`）

| # | 别扭点 | 精确证据 | 量化 |
|---|---|---|---|
| I1 | 图标远大于文字 | `Icon(26)`(:168) vs `fontSize: 11`(:178) | **2.36 倍**（常规 1.3~1.6） |
| I2 | **非整数缩放抖动** | `AnimatedScale(1.15)`(:160) | 26→29.9px，**非整数 → 边缘模糊** |
| I3 | **弹跳资源错配** | `AppTheme.spring`(:157/169) | spring 过冲 **+9.78%**（见 §2），用于二值选中态 |
| I4 | **每格 24% 死区** | `Expanded→Center→InkWell`，Center 把 InkWell 缩回内容尺寸 | 见下方 §1.3.1 |

#### 1.3.1 底部导航热区精确推导（含 0.5dp 边框）

```
W_outer = S − 24          (margin 12+12)
W_inner = W_outer − 1     (Border.all(0.5)×2)
slotW   = (S − 25 − 72) / 4 = (S − 97) / 4
```
| 屏宽 S | slotW | InkWell 实际热区 | **每格命中率** | FAB↔相邻格净距 |
|---|---|---|---|---|
| 360 | 65.75 | **50 × 57** | **54.9%** | **7.875 < 8dp ⚠️** |
| 390 | 73.25 | 50 × 57 | 49.3% | 11.625 ✅ |
| 412 | 78.75 | 50 × 57 | 45.8% | 14.375 ✅ |

**关键结论**：
- 高度 57 ✅ 合格；宽度 50 仅比 48 多 **2dp 余量**。
- 50 的来源是 `Icon 26 + padding h12×2`。**若把 horizontal 12 改成 8，热区立刻塌到 42 < 48** —— 这是改样式时必须知道的「8dp 悬崖」。
- **真正的问题不是「小」，是「格子没用满」**：360 屏上每格近一半宽度（45.1%）点了无响应。
- 上下还各有 **11dp 死带**（Row 79 vs pill 57）。
- FAB 与相邻格**现在不重叠**，净距 = `(slotW − 50) / 2`，360 档只有 7.875dp（**低于 8dp 死区标准**）。**这是 `Center` 把 InkWell 缩到 50 的功劳，不是让位 72 的功劳**。所以「撑满 slot」的修法必须**同时**把让位 72 → **88**，否则相切变重叠。

#### 1.3.2 IconButton 热区实测结论

**结论：66 处 IconButton 中 64 处恒 48×48 合格，只有 2 处塌陷。**

逐个 arg-block 解析 66 次构造调用：`padding:` **0 处**、`constraints:` **0 处**、`iconSize:` **0 处**、`visualDensity:` **仅 2 处**。

> ⚠️ **易误判点**：全仓 9 个「可疑 constraints」**没有一个属于 IconButton** —— 逐个核对 owner 后：
> `ai_chat:425` / `self_talk:483` = 气泡 maxWidth；`calendar:1855` / `badge_service:2628` = 弹窗 maxHeight；两个 `sticker_overlay` = 贴图 maxW/maxH；`accessibility:88` = `ConstrainedBox(48)`（**正确用法**）。
> 同批 `padding: EdgeInsets.zero` 里：`stats_screen:797/877/965/1104` + `timeline:621` = **InteractiveButton**；`write_diary:1744` = **Chip**；`profile:1955` = **ListTile** 的 `contentPadding`。全部与 IconButton 无关。

**唯一塌陷的 2 处**：`semester_settings_screen.dart:343` 与 `:361`

```
VisualDensity.compact = (-2, -2)          (theme_data.dart，实测)
baseSizeAdjustment = (-2,-2) × 4 = (-8,-8) (interval = 4.0)
_InputPadding.minSize = 48 − 8 = 40×40    ← 低于 48 底线
```
且 `:359↔:360` **无 SizedBox 紧贴**，右侧就是「删除本节」按钮 → **误触即删课表节次**。

#### 1.3.3 其它已确认热区缺陷

| # | 元素 | 位置 | 实测热区 | 问题 |
|---|---|---|---|---|
| H1 | 开关（应用锁） | `profile_screen.dart:1421` | **48 × 28** | 高度仅 28，设置里误点跳过功能（同款还有 `:1499`） |
| H2 | 速记入口悬浮球 | `main_screen.dart:681` | 44 × 44 | 全 App 唯一常驻 <48 |
| H3 | Chip（标签） | `write_diary_screen.dart:1729` | 高 24~28 | 三重压缩 |
| H4 | 「恢复预设」 | `semester_settings_screen.dart:161` | 高 ~28 | — |
| H5 | `InteractiveButton` | 组件默认 | **46~47**（padding v14 + 16 号字） | 本就压在 48 线下，再叠 5 处 `padding: zero` → **~42** |
| H6 | 裸 GestureDetector | 全库 133 处 | — | **129 处无 `onTapDown` ⇒ 零按下态** |

### 1.4 手势（**本轮最严重**）

| # | 缺陷 | 证据 | 后果 |
|---|---|---|---|
| **G1** | **「假长按」黑洞** | `onTapDown` + `Timer(2s)`(:634-648) | **F 类黑洞**：只有 onTap 无 onLongPress 的区域（日历日期格:573/665、profile 卡片、统计卡…），按住 2s 弹速记，**松手后内层 onTap 仍执行 → 一次操作两个动作** |
| **G2** | **横向滚动污染导航栏** | `_onScrollNotification`(:449-489) **无 depth/axis 过滤** | 左右滑图片条（timeline:953-954 横向 ListView）→ 导航栏按「竖向滚动」显隐。**真 bug** |
| **G3** | 阈值不对称导致闪烁 | `scrollDelta > 10` 隐藏 / `< -5` 显示 | 显示阈值比隐藏灵敏 **2 倍**。正常滑速 600px/s 单帧 delta=10 恰在临界；「滑一段→回一点点」可稳定复现 show→hide 互打断，**2~4 次/秒往复即肉眼闪烁** |
| **G4** | 行走微动唤醒 | 指腹随步态抖动 σ≈6px | `P(|Δ|>5)≈40%` → 隐藏后几乎每隔几帧被唤醒 → 「隐藏→抖两下冒出→5s 后再消失」周期闪现 |
| **G5** | 2s vs 系统 500ms | `kLongPressTimeout=500` | **4 倍**于系统标准；且不是 long press recognizer，无进度反馈、无 onLongPressUp |

### 1.5 其它已确认的真 bug（本轮新发现）

| # | Bug | 位置 | 后果 |
|---|---|---|---|
| B1 | **弹簧负缩放 → 镜面翻转** | `diary_interactions.dart:397-400` `AnimatedScale(1.0→0.0, curve: spring)` | spring 过冲 9.78% → 插值峰值 **−0.0978** → `Transform.scale` 负值 → **图形镜像翻转** |
| B2 | **dispose 后崩溃** | `goal_progress_card.dart:671-677` `initState` 里 `forward().then(2s delayed).then(forward)` 无 `mounted` | widget 销毁后仍执行 → **release 也崩** |
| B3 | **空回调有反馈无结果** | `timeline_screen.dart:620`、`stats_screen.dart:1103` `onPressed: () {}` | `InteractiveButton` 仍震动+音效+缩放 → 用户点了**毫无反应** |
| B4 | **涟漪永久残留** | `animated_feedback.dart:60` `_RippleButton` 闭包捕获字段非值 | 第 2 个起涟漪**永久留在树里** |
| B5 | **按下即触发、滑走不能取消** | `animated_feedback.dart:68` `_addRipple` 末尾直接 `widget.onTap!()`，而它由 `onTapDown` 调用 | 保存类比（`profile:1372`、`write_diary:994`）**按下瞬间就执行业务**，手指滑走无法反悔 |
| B6 | **贴图坐标系错配** | `custom_sticker_overlay.dart` position 按 `MediaQuery` 屏高算，却 `Positioned` 在 80dp 容器里（`calendar:461-503`） | 贴图**全被 clip 裁掉，画不出也点不到**；且 100×100 隐形热区（`BoxDecoration.hitTest` 不看 alpha） |
| B7 | 死代码只写不读 | `main_screen.dart:66/477` `_lastScrollPixels`、`:77/644/647` `_longPressTriggered` | 误导后续维护 |

#### 1.5.1 G2 的正确修法（实测数据，勿凭直觉写）

我在 `test/` 里跑了一次实测（`PageView` 内嵌竖向 ListView + item 内嵌横向 ListView，外层 `NotificationListener` 打印 `depth`/`axis`）：

| 滚动来源 | 到达 main_screen listener 时 | 应如何处理 |
|---|---|---|
| tab 内**竖向** ListView | **`depth=1, axis=vertical`** | ✅ 处理（显隐导航栏） |
| item 内**横向**图片条 | **`depth=2, axis=horizontal`** | ❌ 忽略 |

```dart
// ✅ 正确写法（两个条件都要，axis 是主判据，depth 是纵深护栏）
if (notification.depth != 1) return false;
if (notification.metrics.axis != Axis.vertical) return false;
```

> ⚠️ **不要写 `depth != 0`** —— 竖向滚动实际是 1，写 0 会把**所有** tab 滚动全部丢掉，导航栏显隐功能直接失效。
> ⚠️ **不要只靠 depth** —— 若未来有更深的竖向嵌套（如 item 内竖列表），`depth=2` 的竖向滚动会被漏掉；`axis` 才是主判据。

---

## 2. 四个动效技巧拆解（含解析求导数据）

### 核心数学表（`cubic-bezier` 解析求导，非估算）

`spring = Cubic(0.34,1.56,0.64,1)`，对 y 求导 `2.68t² − 4.24t + 1.56 = 0`，根 `t=0.5820896`，代回得：

| 曲线 | maxY | 过冲 | 峰值位置 |
|---|---|---|---|
| `spring (0.34,1.56,0.64,1)` | **1.097804** | **+9.78%** | x=0.5728，**过冲窗口占 63.1% 时长** |
| `easeOutBack` | 1.0869 | +8.69% | — |
| `easeOutExpo / smoothDecel (0.16,1,0.3,1)` | 1.0000 | 0% | — |
| `gentle (0.23,1,0.32,1)` | 1.0000 | 0% | — |
| `smoothCurve (0.65,0,0.35,1)` | 1.0000 | 0% | — |

**缓出位移完成度（x = 时长百分比 → y = 位移完成度）**：

| 曲线 | y(0.30) | y(0.50) | y(0.80) |
|---|---|---|---|
| `easeOutExpo` | **0.8772** | 0.9718 | 0.9993 |
| `gentle` | 0.8430 | 0.9660 | 0.9991 |
| `smoothCurve` | **0.1124** | 0.5000 | 0.9580 |
| `spring` | 0.9074 | 峰值 1.0874 | 1.042 |

> **最反直觉的结论**：`ScrollReveal` 用 300ms + easeOutExpo，**第 90ms 就走完 87.7%**，实际感知仅 **100~120ms**。这就是「写了 300ms 却一闪而过」的根源，也解释了 stagger（Interval 0.1 = 30ms/项）为何视觉上消失。
> 想要「慢而稳」只能用 `smoothCurve` / `slowCurve` —— 而这两个在全 lib **零使用**。

### 2.1 随时打断

**常见问题**（本项目实测）
- 52 处 `Future.delayed` **全部不可取消**，其中 **32 处驱动动画/UI 恢复**；
- `_showNavBarImmediately()` 的 100ms 二次 `setState`（`main_screen.dart`）被 13 处调用，350ms 窗口内连排 4~5 个 → 导航栏在「动画 / 瞬显」间反复横跳。

**判断方法**：连点 3 次，第 2/3 次是否 1 帧内有视觉响应；动画中途拖拽是否跟手。

**调整**：延迟一律改 `Timer` 变量 + `cancel()`；动画用 `AnimationController`（`forward()` 天然覆盖旧目标）；重复触发用**序号防竞态**（`_navSeq++`）。

### 2.2 轻轻退场

**常见问题**：40 处 sheet `sheetAnimationStyle` **全部未设** → 退场走框架默认，与入场等重。

**判断**：0.25× 慢放，退场末 20% 是否一帧消失；连续「开-关-开」第二次是否要等第一次关完。

**调整**：退场 = 入场 × 0.6~0.7；曲线用 **`easeIn`**（不要 easeOut，末段变慢会「拖」）。

### 2.3 柔和切换

**常见问题（本项目 8 类缺陷 D1~D8）**

| # | 同类语义 → 不同曲线 | 后果 |
|---|---|---|
| D1 | `interactive_button.dart:67` spring vs `:203` easeOutExpo | 两个按钮「一个回弹、一个干脆」 |
| D2 | `animated_feedback.dart:207` spring vs `custom_bottom_nav.dart:226` easeInOut | 卡片与 FAB 手感不同 |
| D3 | `diary_interactions.dart:279` easeOut vs `:191` spring | 同文件两套 |
| **D4** | **导航栏 `AnimatedSlide` 250ms easeOutCubic vs `AnimatedOpacity` 200ms linear** | **t=100ms 时位移 79.5%、透明度 50% → 视觉错帧** |
| D5 | `scroll_reveal.dart:50` 300ms easeOutExpo vs `timeline_screen.dart:48` 800ms easeOut | 两套入场并存 |
| D6 | `self_talk_screen.dart:389` linear vs `:791` easeOut | 同页开关手感分裂 |
| D7 | spring(9.78%) vs easeOutBack(8.69%) | 三套弹跳并存 |
| D8 | `swipeable_list_item:115` easeOut vs `diary_interactions:399` spring | 一处滑出、一处弹性缩没 |

**令牌体系乱象**：11 处重复定义（design_tokens 4 + app_theme 5 + page_transitions 1 + swipeable 1），**9 个令牌 6 个零引用**，同时 `Curves.easeOut` 等框架枚举被散用 40+ 处。

**时长断档**：`200ms` 用了 **21 次**，但令牌阶梯是 100/150/300/500/800 —— **根本没有 200**。这是裸数字散用的制度性成因。

### 2.4 入场缓出

**常见问题**：`spring`(1.56) 被用于二值选中态；`diary_cinema_screen.dart:54` 纯 linear 入场；`splash_screen:368` 第三套弹跳 `easeOutBack`。

**判断**：0.25× 慢放，前 30% 是否完成 60~70% 位移；有无过冲。

**关键认知**：`Cubic(0.34,1.56,0.64,1)` 的 **1.56 是控制点 y，不是过冲量**。实际过冲只有 **+9.78%**。

---

## 3. 侧边栏改稿清单（逐条结论）

### 3.1 字号

| 层级 | 现值 | 改为 | 依据 |
|---|---|---|---|
| 区块标题 `_buildSectionTitle:3041` | **20 / bold**(:3055) | **17 / w700** | 20 是页面大标题量级，做分组标签太重 |
| 条目主标题 | 16 / w600(:2328) | **15 / w600** | 与 13 副标题差 3，改后差 3 更稳 |
| 条目副标题 | 13(:2337) | **12 / w400** | 与主标题形成 3px 梯度 |
| 尾注 | — | **11 / w400** | 统一第四级 |

### 3.2 圆角（同级面板必须一致）

| 元素 | 现值 | 改为 |
|---|---|---|
| 组容器 | 16(:2287) | **16（保持）** |
| 图标底板 | `radius12`(:2317) | **10**（必须 < 16，同心圆感） |
| 分割线 | 左 76 / 右 20(:2298-2299) | **左 72 / 右 16** |

### 3.3 间距与行高（统一规则）

```
组内间距 = 0（靠 1px Divider 分隔）
组间间距 = 24        ← 现值 16，必须改
区块前后留白 = 24    ← 现值 24，保持
行高 = 64（带副标题 72）
```

| 项 | 现值 | 改为 |
|---|---|---|
| 条目 vertical padding | 6(:2304) | **10**（行高稳定 64） |
| 组间距 | 16(:275...) | **24** |

### 3.4 图文关系

| 项 | 现值 | 改为 | 说明 |
|---|---|---|---|
| 图标视觉 | 22(:2322) | **18** | 硬性「图标略小于文字」：文字 15，图标 18 |
| 图标底板 | 44×44(:2306-2307) | **36×36** | 底板是视觉容器不是热区；36:18 = 2:1 |
| 图文间距 | ListTile 默认 | **12 显式** | 不依赖默认值 |

> 若 PD 觉得太轻，**整组按比例退**：图标 20 / 底板 40。**禁止只缩图标不缩底板**。

### 3.5 点击热区（硬性达标表）

| 项 | 现值 | 判定 | 改为 |
|---|---|---|---|
| 单行高度 | 64 | ✅ ≥48 | 64（保持） |
| 单行宽度 | 全宽 | ✅ | 整行 + 左右各 8 透明内边距 |
| 图标热区 | 视觉 44 | ⚠️ | 视觉 36 + **热区 44**（外包 `SizedBox(44)`） |
| 相邻死区 | 0 | ❌ | **≥8dp**（行高 64 内含 8dp 上下留白） |
| 手势隔离 | 无 | ❌ | **20dp** 边缘不响应侧滑 |
| **FAB 圆形衰减** | 72×72 circle | ❌ **四角 21.5% 不可点** | 改 `behavior: opaque` 或外包方形透明热区 |
| **底部导航格死区** | 24% | ❌ | `Center` 去掉，InkWell 撑满 slot + 让位 **72→88** |

### 3.6 动效手感

| 项 | 改为 |
|---|---|
| 条目按下态 | 底板 alpha 0.25→0.4，**80ms easeOut** |
| 条目入场 | 250ms `Cubic(0.16,1,0.3,1)`，stagger 40ms/项 |
| 触觉 | 点击 `lightImpact`；长按 `mediumImpact`（区分） |

---

## 4. 参数建议（可直接抄）

### 4.1 尺寸

```dart
// 侧栏（分组菜单）
const sectionTitleSize = 17.0;  // w700
const itemTitleSize    = 15.0;  // w600
const itemSubtitleSize = 12.0;  // w400
const itemNoteSize     = 11.0;  // w400

const panelRadius      = 16.0;  // 组容器（同级统一）
const iconPlateRadius  = 10.0;  // 必须 < panelRadius
const iconPlateSize    = 36.0;  // 视觉
const iconVisualSize   = 18.0;
const iconTouchSize    = 44.0;  // 44-48 拇指接触面
const rowMinHeight     = 64.0;
const rowWithSubMin    = 72.0;
const groupGap         = 24.0;  // 组间
const blockPadding     = 24.0;
const dividerIndentL   = 72.0;  // 20 + 44 + 8
const dividerIndentR   = 16.0;
const deadZoneGap      = 8.0;
const gestureIsolation = 20.0;  // dp
```

```dart
// 底部导航
const navIconSize      = 20.0;  // 26 → 20（2.36x → 1.67x）
const navLabelSize     = 12.0;  // 11 → 12
const navGap           = 4.0;
// ❌ 删除 AnimatedScale(1.15) —— 非整数缩放必抖动
// ✅ 选中态：颜色 150ms easeOut + 底板 alpha 200ms
const navSlotGap       = 88.0;  // 让位区 72 → 88（与撑满 slot 必须同时改）
```

### 4.2 动效（统一 6 档，补上缺失的 200）

```dart
const micro   = Duration(milliseconds: 100);  // 按压
const quick   = Duration(milliseconds: 200);  // ★新增：21 处裸 200ms 的归宿
const fast    = Duration(milliseconds: 150);  // 状态切换
const normal  = Duration(milliseconds: 300);  // 标准过渡
const slow    = Duration(milliseconds: 500);
const elaborate = Duration(milliseconds: 800);

// 曲线（语义化，禁裸写 Curves.easeOut）
const enter     = Cubic(0.16, 1, 0.3, 1);   // 入场，过冲 0
const exit      = Curves.easeIn;            // 退场，末段加速
const press     = Curves.easeOut;           // 按压
const switchC   = Cubic(0.2, 0, 0, 1);      // 状态切换
const lively    = Cubic(0.22, 1.2, 0.36, 1);// 需弹跳时（过冲仅 +1.25%）
// ❌ spring(0.34,1.56,0.64,1)：过冲 +9.78% 且持续 63% 时长
//    仅限 FAB/抽卡；二值状态/缩放归零场景一律禁用
```

### 4.3 面板统一参数

```dart
// 40 处 sheet 统一（当前 0 处合格）
const sheetShape  = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),  // 顶部圆角
);
const sheetAnimation = AnimationStyle(
  duration: Duration(milliseconds: 250),
  reverseDuration: Duration(milliseconds: 160),  // 退场 = 入场 × 0.64
  curve: Cubic(0.16, 1, 0.3, 1),
  reverseCurve: Curves.easeIn,
);
const sheetBarrier = Colors.black54;  // 统一遮罩，勿多种 alpha 混用
// isScrollControlled: true + viewInsets.bottom 处理（键盘）
```

### 4.4 手势

```dart
// ① 滚动过滤（修 G2 真 bug，depth 值经实测确认）
if (notification.depth != 1) return false;              // tab 主滚动实测为 1
if (notification.metrics.axis != Axis.vertical) return false;  // axis 是主判据

// ② 对称阈值 + hysteresis（修 G3/G4 闪烁）
const hideThreshold = 12.0;   // 累计向下
const showThreshold = -12.0;  // 累计向上
const hysteresisBand = 16.0;  // 带内不动作

// ③ 长按标准化（修 G1/G5）
// ❌ onTapDown + Timer(2s)
// ✅ GestureDetector(onLongPress: ...)  → 系统 500ms，有 onLongPressUp
```

---

## 5. 验收方法（回放 / 慢动作 / 曲线对比）

| 手段 | 做法 | 判据 |
|---|---|---|
| **回放** | 录屏 → `ffmpeg -vf fps=30` 导出逐帧 | 入场前 30% 应完成 ≥60% 位移（easeOutExpo 实测 87.7%，偏快） |
| **慢动作** | 0.25× 播放 | ①退场末 20% 无一帧消失 ②导航栏 slide/opacity 不错帧 ③无像素抖动 |
| **曲线对比** | 同屏并排方块跑 `enter` vs `spring` | spring 可见过冲回弹 → 仅 FAB/抽卡可用 |
| **横向滑动测试** | 在时间线左右滑图片条 | **导航栏不得显隐**（验 G2 修复） |
| **F 类黑洞测试** | 在日历日期格上按住 2 秒 | 只应弹 1 个结果，不应「弹速记后松手又打开日记」 |
| **热区测试** | 手指偏移 8px 按下 | 仍命中目标；偏移 20dp 不触发相邻 |
| **死区测试** | 点底部导航每格左右边缘 7dp 区域 | 修复前无响应，修复后应有 ripple |

---

## 6. 最终修改提示词（可直接交给 AI）

```
对 lib/screens/profile_screen.dart、lib/widgets/custom_bottom_nav.dart、
lib/screens/main_screen.dart 做样式与手势修正。不改内容/配色/交互逻辑。

【一、先修 7 个真 bug（优先级最高）】
1. main_screen.dart:449-489 `_onScrollNotification` 开头加：
   `if (notification.depth != 1) return false;`
   `if (notification.metrics.axis != Axis.vertical) return false;`
   —— 当前左右滑图片条会误触发导航栏显隐。
   ⚠️ depth 必须写 1（实测：tab 主滚动 depth=1、嵌套横向条 depth=2）；
      写成 0 会把所有竖向滚动丢掉、导航栏显隐功能失效。
2. main_screen.dart:634-648 删除 `onTapDown + Timer(2s)` 假长按，
   改为 GestureDetector(onLongPress: ...) 标准 500ms；
   若必须保留全屏长按，改为仅空白区（用 IgnorePointer 隔离可点区域）。
3. diary_interactions.dart:397-400 `AnimatedScale(scale: 0.0, curve: spring)`
   → 改 `Curves.easeIn`，spring 过冲会产生负缩放导致图形镜像翻转。
4. goal_progress_card.dart:671-677 initState 里 forward().then + 2s delayed
   全程无 mounted 检查 → 每步前加 `if (!mounted) return;`，防 dispose 后崩溃。
5. timeline_screen.dart:620 与 stats_screen.dart:1103 空态按钮 `onPressed: () {}`
   → 接上真实动作；当前点了有震动有音效却无反应。
6. animated_feedback.dart:68 `_addRipple` 末尾 `widget.onTap!()`，而它由
   `onTapDown` 调用 → 保存类按钮「按下即触发、滑走不能取消」。
   改为：onTapDown 只做涟漪视觉，业务动作移到 `onTap`。
7. custom_sticker_overlay.dart position 按 MediaQuery 屏高算却挂在 80dp 容器
   → 贴图被 clip 裁掉。改用 LayoutBuilder 按父容器尺寸算坐标。

   → 改 `Curves.easeIn`，spring 过冲会产生负缩放导致图形镜像翻转。
4. goal_progress_card.dart:671-677 initState 里 forward().then + 2s delayed
   全程无 mounted 检查 → 每步前加 `if (!mounted) return;`，防 dispose 后崩溃。
5. timeline_screen.dart:620 空态「开始写日记」按钮 `onPressed: () {}`
   → 接上真实的打开写日记页动作；当前点了有震动有声音但无反应。

【二、分组菜单样式】
- 区块标题 20 → 17(w700)；条目 16 → 15(w600)；副标题 13 → 12(w400)。
- 图标底板圆角 radius12 → 10；图标 22 → 18；底板 44×44 → 36×36（外包 44×44 透明热区）。
- 行 contentPadding vertical 6 → 10（行高稳定 64）；带副标题 minHeight 72。
- Divider indent 76 → 72、endIndent 20 → 16。
- 组间距 SizedBox(16) → 24；组内间距保持 0。
- 加按下态：底板 alpha 0.25→0.4，80ms easeOut。

【三、底部导航】
- 图标 26 → 20；文字 11 → 12；间距 4 保持。
- 删除 AnimatedScale(1.15)（非整数缩放必抖动），选中态改
  颜色 150ms easeOut + 底板 alpha 200ms Cubic(0.2,0,0,1)。
- 把 Material/InkWell 从 Center 内部挪到外部，让热区撑满每格 slot
  （当前每格 24% 宽度点了没反应）；**同时**把让位 SizedBox 72 → 88，
  否则 FAB 会与相邻 tab 热区相切重叠。
- FAB（72×72 shape: circle）加 `behavior: HitTestBehavior.opaque`，
  消除圆形衰减（当前四角 21.5% 不可点）；并补按下态。

【四、动效统一】
- 新建/复用统一令牌，补 `quick = 200ms`（当前 21 处裸写 200ms 无令牌）。
- 导航栏显隐：AnimatedSlide 250ms easeOutCubic 与 AnimatedOpacity 200ms linear
  不一致 → 统一为 250ms + Cubic(0.16,1,0.3,1)，消除「位移先到、淡出后完成」错帧。
- 所有 `Future.delayed` 驱动的延迟恢复改 Timer 变量 + cancel。
- 40 处 showModalBottomSheet 统一 sheetAnimationStyle：
  入 250ms Cubic(0.16,1,0.3,1) / 出 160ms Curves.easeIn；统一 shape 顶部圆角 24；
  19 处未开 isScrollControlled 的改为 true + 处理 viewInsets.bottom。
- 删除 6 个零引用令牌，11 处重复曲线定义收敛到 design_tokens 一处。

【五、验收】
dart analyze lib 0 error；按方案 §5 做录屏逐帧 + 横向滑动 + F 类黑洞三项实测。
```

---

## 附：优先修复顺序（按「影响人数 × 危害」）

| 序 | 项 | 理由 |
|---|---|---|
| 1 | **G2 横向滚动污染导航栏** | 真 bug，每次左右滑图片都触发，用户高频遇到 |
| 2 | **G1 假长按黑洞** | 一次操作两个动作，日历/统计页高频 |
| 3 | **B3 空态按钮无反应** | 首屏引导按钮点了没反应，新用户必经 |
| 4 | **B2 dispose 后崩溃** | 唯一会崩 App 的项 |
| 5 | **底部导航 24% 死区 + FAB 21.5% 圆形衰减** | 每天点几十次 |
| 6 | **B1 负缩放镜面翻转** | 删除动画时可见异常 |
| 7 | 组间距 16→24 / 行高稳定 / 字号梯度 | 「挤、乱」的观感来源 |
| 8 | 40 处 sheet 统一（尤其 19 处键盘遮挡） | 键盘弹出被遮是明确痛点 |
| 9 | 令牌去重 + 补 200ms 档 | 制根治，改动量大，放最后 |
