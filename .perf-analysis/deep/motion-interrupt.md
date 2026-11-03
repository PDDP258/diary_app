# 深挖 3：动效可打断性与曲线体系

审计对象 `E:\main\work\diary_app`（Flutter 3.x「小记日记」）｜2026-11-03｜只读，未改任何源码

**基线（全 lib 递归 grep 实测）**：`AnimationController(` **58**、`.repeat()` **18**、`Future.delayed` **53**（含 1 处注释 → 可执行 **52**）、`addListener` **13** + `addStatusListener` **3**、`milliseconds: N` **144**（21 种取值）、`ScrollReveal` 实际使用仅 **1** 处（`timeline_screen.dart:276`）、曲线常量重复定义 **11** 处。任务书给的 53/58/18/13 已复核一致；13 处 `addListener` 中真正驱动动画的仅 3 处（`real_page_turn.dart:178`、`immersive_experience.dart:41`、`motion_photo_widget.dart:293`），其余是 ScrollController/FocusNode/Provider 监听。

## ① 曲线语义映射表

### 1.1 令牌层：11 处重复定义、4 套并存入口

| 数值 | design_tokens（L1） | app_theme（两段） | page_transitions | swipeable_list_item |
|---|---|---|---|---|
| `(0.16,1,0.3,1)` | `easeOutExpo` :272 | `smoothDecel` :125 ＋ `easeOutExpo` :375 | — | 裸写 :205 / :305 |
| `(0.65,0,0.35,1)` | `easeInOutCubic` :273 | `smoothCurve` :137 ＋ `easeInOutCubic` :376 | — | — |
| `(0.34,1.56,0.64,1)` | `spring` :274 | `bouncyCurve` :128 ＋ `spring` :377 | `springCurve` :223 | — |
| `(0.23,1,0.32,1)` | `gentle` :275 | `gentleCurve` :134 | — | — |
| `(0.4,0,0.2,1)` | — | `slowCurve` :131 | — | — |

**「两边 spring 是否完全相同」→ 数值完全相同**（`design_tokens:274` 与 `app_theme:377` 都是 `Cubic(0.34,1.56,0.64,1)`）；`easeOutExpo≡smoothDecel`、`easeInOutCubic≡smoothCurve` 亦数值相同。**问题是命名重复而非数值漂移** —— 同一曲线有 2~4 个可互换名字，调用方按「写码人记得的名字」挑，这是手感不一致的制度性根源。第三套入口在 `utils/design_extensions.dart:407-430`（`Durations`/`AppCurves` 全量转发），「改一个令牌改全局」在事实层面已不成立。

### 1.2 六类语义 × 实际曲线（⚠️ = 同类语义不同曲线）

| 语义 | 位置 | 时长 | 曲线 | 判定 |
|---|---|---|---|---|
| **入场** | `scroll_reveal.dart:49-50`（默认）/ `timeline_screen.dart:276`（唯一用例） | 300ms | `easeOutExpo` | 基准 |
| | `timeline_screen.dart:48-50`+`:257-263` | 800ms | `Curves.easeOut` Interval 0.05/项 | ⚠️ 未用令牌 |
| | `page_transitions.dart:68` | 父驱动 | `easeOutExpo` Interval 0.1/项 | 一致 |
| | `animated_feedback.dart:519-566` `SlideInAnimation` | 300ms | 位移 `spring` / 透明度 `easeOut` | ⚠️ 组件内双曲线 |
| | `stats_screen.dart:66-82`／`splash_screen.dart:350-368`／`diary_cinema_screen.dart:54-60` | 600/500/500ms | `easeOutExpo`+`Interval`／`easeOut`+`easeOutBack`／无显式 linear | ⚠️ 双曲线，含第三套弹跳 |
| **退场** | `smart_notifications.dart:93-120` Toast | 400ms | 进 `spring` / 出 `reverse()` 同曲线 | ⚠️ 弹跳退场 |
| | `swipeable_list_item.dart:114-116` | 200ms | `Curves.easeOut` | — |
| | `random_sticker_overlay.dart:276-283` | 出 300/入 400ms | 入 `easeOut`+`elasticOut`，出 `easeIn` | ⚠️ 出入差异极大 |
| **状态切换** | `custom_bottom_nav.dart:145-185` 选中三件套 | 200ms | `AppTheme.spring` ×2 ＋ **默认 linear**(`:172`) | ⚠️ 同格三通道节奏不同 |
| | `profile_screen.dart:1433/1511`／`calendar_screen.dart:733-734` | 200ms | **默认 linear** | ⚠️ 二值状态用 linear |
| | `self_talk_screen.dart:389/662/791/832` | 200ms | 前两处 linear，`:792` `easeOut` | ⚠️ **同页 4 处分裂** |
| | `calendar_screen.dart:828-830`／`smart_recall_screen_v2.dart:285-290`／`swipeable_list_item.dart:198-213` | 300/250/300ms | `easeInOut`／`easeOut`／高度 `Cubic(0.16,1,0.3,1)`+旋转 `easeInOut` | ⚠️ 同组件双曲线 |
| | `bento_card.dart:85-87` hover | 200ms | `AppTheme.smoothDecel` | **唯一全规范** |
| **按压** | `interactive_button.dart:55-69`／`:196-205` | 150ms | `spring` ／ `easeOutExpo` | ⚠️ **同文件两个曲线** |
| | `animated_feedback.dart:196-209`／`diary_interactions.dart:63/:189` | 150ms | `spring` | 规范 |
| | `animated_feedback.dart:271-281`／`custom_bottom_nav.dart:221-227`／`diary_interactions.dart:271` | 100~150ms | `easeOut`／`easeInOut`／`easeOut` | ⚠️ 第三、四套 |
| | `diary_interactions.dart:397-400` 图片删除 | 300ms | `spring` → 0.0（**过冲为负**） | ⚠️ 见 §2.4 |
| **循环背景** | `theme_backgrounds.dart:54-57`Sakura／`:1290-1293`Aurora／`:1559-1562`Golden／`:2009-2012`Starry／`:654-669`Ocean **×3** | 10/5/6/4/4·8·3s | **无曲线**（直读 `_controller.value`） | 线性相位（正确做法） |
| | `skeleton_loading.dart:36-46`／`animated_feedback.dart:380-395`／`immersive_experience.dart:308-318`／`voice_recorder_button.dart:40-52` | 1500/2000/1500/1000ms | `Curves.easeInOut` + `repeat(reverse)` | ⚠️ 双向曲线致「喘息感」 |
| | `gacha_screen.dart:40-90` | 600ms | `TweenSequence` 无曲线 | 线性晃动 |
| **过渡/路由** | `main_screen.dart:429-433` `animateToPage` | 300ms | `Curves.easeInOut` | — |
| | `main_screen.dart:715-718` `AnimatedSlide`／`:719-721` `AnimatedOpacity` | **250ms / 200ms** | `Curves.easeOutCubic` / **默认 linear** | ⚠️ **同一次显隐 250/200 + 两曲线** |
| | `app_theme.dart:596-603`／`:577-590`／`page_transitions.dart:254-257`／`skeleton_loading.dart:333-336` | 400/300/300ms | `easeOutExpo`／无曲线／出 `easeIn` 入 `easeOut` | ⚠️ fadeRoute 无曲线 |

### 1.3 同类语义不同曲线的 8 个可量化缺陷

| # | 语义 | A | B | 后果 |
|---|---|---|---|---|
| D1 | 按压缩放 150ms | `interactive_button.dart:67` spring | 同行 `:203` easeOutExpo | 两按钮「一回弹一干脆」 |
| D2 | 按压缩放 | `animated_feedback.dart:207` spring | `custom_bottom_nav.dart:226` easeInOut | 卡片与 FAB 手感不同 |
| D3 | 按压缩放 | `diary_interactions.dart:279` easeOut | `:191` spring | 同文件两套 |
| D4 | 导航栏显隐 | slide 250ms easeOutCubic | opacity 200ms linear | 实测 t=100ms 位移已完成 **79.5%**、透明度才 **50%** → **半透明滑到位** |
| D5 | 列表入场 | `scroll_reveal` 300ms | `timeline_screen:48` 800ms | 两套入场体系并存 |
| D6 | 状态切换 | `self_talk:389` linear | `:791` easeOut | 同页开关分裂 |
| D7 | 弹跳 | 令牌 `spring`(+9.78%) | `easeOutBack`（≈+8.69%，3 处） | 三套弹跳并存 |
| D8 | 删除退场 | `swipeable:115` easeOut 滑出 | `diary_interactions:399` spring 缩没 | 一处平滑一处弹性 |

### 1.4 9 个曲线令牌只有 5 个在用，6 个是死代码

| 令牌 | 定义 | 引用数 | 状态 |
|---|---|---|---|
| `bouncyCurve`/`slowCurve`/`smoothCurve`/`easeInOutCubic`(app_theme) ＋ `gentle`/`easeInOutCubic`(design_tokens) | app_theme:128/131/137/376、design_tokens:275/273 | **全 0** | ☠️ 6 个死令牌 |
| `smoothDecel`／`easeOutExpo`／`gentleCurve` | :125/:375/:134 | 1／1／3 | 低频 |
| `AppTheme.spring`／`PrimitiveAnimation.spring`／`easeOutExpo` | :377／:274／:272 | 5／8／5 | 在用 |

**6/9 令牌是死代码，同时 40+ 处直接散用 `Curves.easeOut/easeInOut/elasticOut`（未进令牌）。** 不是「没建令牌」，是「建了没人用」。

## ② 过冲 / 缓出数学表（含推导）

### 2.1 参数方程与过冲判据

`Cubic(x1,y1,x2,y2)` 为 CSS `cubic-bezier` 语义，两端锚定 (0,0)、(1,1)：

```
x(t)=3(1-t)²t·x1 + 3(1-t)t²·x2 + t³    y(t)=3(1-t)²t·y1 + 3(1-t)t²·y2 + t³    t∈[0,1]
```

**过冲充要条件：`y1>1` 或 `y2>1`。** 本项目 6 曲线中只有 spring 满足（y1=1.56）；`(0.16,1,0.3,1)`、`(0.23,1,0.32,1)`、`(0.65,0,0.35,1)`、`(0.4,0,0.2,1)`、`easeOutCubic(0.215,0.61,0.355,1)` 的 `maxY≡1.0000`（精确）。

### 2.2 spring 精确最大 y（解析求导，非采样估算）

```
dy/dt = 3[ y1(1-4t+3t²) + y2(2t-3t²) + t² ]
代入 y1=1.56, y2=1:  1.56-6.24t+4.68t² + 2t-3t² + t² = 0
→ 2.68t² - 4.24t + 1.56 = 0
→ t = [4.24 ± √(4.24²-4·2.68·1.56)]/(2·2.68) = [4.24 ± √1.2544]/5.36 = [4.24 ± 1.12]/5.36
→ t₁=1.0000（终点）  t₂=0.5820896 ← 极大值点
y(0.5820896) = 3(0.4179104)²(0.5820896)(1.56) + 3(0.4179104)(0.5820896)²(1.00) + (0.5820896)³ = 1.097804
x(0.5820896) = 0.572795   ← 峰值出现在 57.28% 时长处
```

**`1.56` 只是控制点纵坐标，不是过冲量。实际峰值 1.097804 = travel 的 +9.78%（而非 +56%）。**

| 度量 | 值 | 度量 | 值 |
|---|---|---|---|
| 实际最大 y | **1.097804** | 开始过冲（y>1） | x=0.3691（36.91%） |
| 过冲百分比 | **+9.78%** | 过冲持续窗口 | **63.1% 时长**（300ms 占 189ms） |
| 峰值时刻 | x=0.5728（57.28%） | 终点斜率 dy/dx | −0.0029（极轻「回贴」） |

按位移换算峰值像素（判断可见性）：按压缩放 0.04 → **0.039px（不可见）**；导航选中 0.15 → 0.015px；`ScaleFadeTransition` 0.8→1.0 → 0.0196（12px 图标 ≈0.24px）。**唯一出问题的是 `diary_interactions.dart:397` 把 spring 用在 `scale: 1.0→0.0`**：`1-1.0978 = -0.0978` **缩放为负 → Transform.scale 镜面翻转**，应改 `easeIn`。

### 2.3 前 30% 时长完成多少位移 —— 缓出手感判据

反解 `x(t)=0.30` 求 `y`（二分求根）：

| 曲线 | y(0.10) | **y(0.30)** | y(0.50) | y(0.70) | 达 90% | 达 95% | 达 99% | 终点斜率 |
|---|---|---|---|---|---|---|---|---|
| `easeOutExpo (0.16,1,0.3,1)` | 0.4944 | **0.8772** | 0.9718 | 0.9957 | 32.9% | 42.5% | 62.0% | 0.0000 |
| `gentle (0.23,1,0.32,1)` | 0.3981 | **0.8430** | 0.9660 | 0.9950 | 36.1% | 45.2% | 63.5% | 0.0000 |
| `spring (0.34,1.56,0.64,1)` | 0.4039 | **0.9074** | 1.0874(峰) | 1.0758 | 29.5% | 32.8% | 36.0% | −0.0029 |
| `easeOutCubic (Curves)` | 0.2757 | **0.6778** | 0.8751 | 0.9638 | — | — | — | 0.0006 |
| `smoothCurve (0.65,0,0.35,1)` | 0.0089 | **0.1124** | 0.5000 | 0.8876 | — | — | — | 0.0016 |
| `slowCurve (0.4,0,0.2,1)` | 0.0259 | **0.3673** | 0.7756 | 0.9382 | — | — | — | 0.0010 |

> *与 Lead 独立计算交叉验证：spring maxY=1.0978(+9.78%)@t=0.582 ✓；smoothDecel x=0.30→0.877、x=0.50→0.972 ✓；gentle x=0.30→0.843 ✓；smoothCurve x=0.30→0.112、x=0.50→0.500 ✓。*

**这解释「写了 300ms 为什么点完就结束」**：`ScrollReveal` 默认 300ms+easeOutExpo，**第 90ms（约第 6 帧）位移已完成 87.7%**，剩下 12% 斜率仅 0.225 → 人眼几乎无感，**实际感知时长约 100~120ms**。三个副作用：① 按 300ms 排的 stagger（`DiaryListItemTransition` 每项 Interval 0.1 = 30ms）被压到 10ms 级，**stagger 基本消失**；② 为「看清」调到 500/800ms → 前 30% 更早走完，观感仍是「一顿即完 + 长时间空等」；③ 想「慢而稳」只能用 `smoothCurve`(11.24%) 或 `slowCurve`(36.73%) —— **这两个令牌全 lib 零使用**。

### 2.4 8 个 spring 使用点逐个裁定

| # | 位置 | 语义 | 裁定 |
|---|---|---|---|
| 1 | `interactive_button.dart:67` | 按压 1.0→0.96 | ✅ 该用（物理按压） |
| 2 | `animated_feedback.dart:207` `BouncyCard` | 按压 | ✅ 该用（名字就是 Bouncy） |
| 3 | `gacha_screen.dart:664` | **抽卡奖励 0.85→1.0** | ✅ **最该用，也是唯一名副其实的奖励场景** |
| 4 | `animated_feedback.dart:563` `SlideInAnimation` 位移 | **入场滑入** | ❌ 滑到位后「往回顶一下」=噪声，应 `easeOutExpo` |
| 5 | `smart_notifications.dart:100` Toast 滑入 | 入场 | ❌ 从 −100 滑入会越过顶部再弹回，小屏顶出安全区 |
| 6 | `custom_bottom_nav.dart:147/:162` 导航选中 | **二值状态** | ❌ 离散状态来回抖，配 200ms 更拖沓 |
| 7 | `stats_screen.dart:92/:681/:687` | 入场/计数 | ⚠️ 计数器可留（生动），卡片应换 |
| 8 | `smart_notifications.dart:548` Tooltip 0.8→1.0 | 入场缩放 | ⚠️ 0.0196 过冲，几乎不可见 |

**8 处里只有 3 处名副其实（#1 #2 #3）；抽卡这种正当场景只用 1 次，导航选中这种最不该弹的地方用了 2 次 —— 弹跳资源完全错配。** 且 spring 的 y(0.30)=90.74% 仅比 easeOutExpo 快 3 个点，却换来 63% 时长处于过冲 —— **入场用 spring 是净亏**。

## ③ 不可打断清单

**52 处可执行 `Future.delayed`：32 处驱动动画/UI 恢复（61.5%），20 处纯业务延迟。共性缺陷 —— 52 处全部不可取消**：没有一处把句柄存进字段，也没有一处改用可 `cancel()` 的 `Timer`。唯一做对的是 `diary_search_screen.dart:33/150`（注释正是记录「从 Future.delayed 改为可取消 Timer」的修复）。

| # | 位置 | 延迟 | 驱动什么 | 连点/提前退出后果 |
|---|---|---|---|---|
| **★1** | `main_screen.dart:168` `_showNavBarImmediately` | **100ms** | 把 `_forceShowNav` 复位（恢复导航栏动画） | **重入竞态**：每次调用排一个新 Future。t=0 排 A、t=90 再排 B；A 在 t=100 把 `_forceShowNav` 置 false，**冲掉 t=90 那次「瞬显」意图** → 本该无动画的导航栏变成 250ms 滑入。该函数 **13 处调用**（`:108 :206 :215 :223 :231 :410 :420 :439 :497 :508 :568 :578 :589`），350ms 切页窗口内连排 4~5 个 → **导航栏在动画与瞬显间反复横跳** |
| **★2** | `goal_progress_card.dart:673` | **2s** | 串 `_scaleController.forward().then` → 延迟 → `_fadeController.forward()` → `onComplete` | **无 mounted 保护**：里程碑弹窗若 2s 内被关（点外部/返回），`_fadeController` 已 dispose，`forward()` 抛 `AnimationController used after dispose` → **release 也崩** |
| **★3** | `animated_feedback.dart:60` `RippleButton` | 600ms | 移除涟漪 | **闭包捕获字段非值**：`removeWhere((r)=>r.id==_rippleId-1)`，`_rippleId` 在回调时才求值。快点 3 次 → 3 个 Future 都删「最新的那个」→ **前 2 个涟漪永久留在树里**（不可见但持续占位/参与 layout） |
| **★4** | `swipeable_list_item.dart:88/:99` | 300ms | 触发 `onDelete` | `_isDeleting` **从不复位**；连点两次 → 两次 `onDelete` → 父级重复删除。若父级未立即移除，该行永停在 `translateX=-屏宽`(`:118`) → **空白行永久残留** |
| **★5** | `diary_interactions.dart:373` | 300ms | `onDelete(index)` + 收尾 setState | 同 index 连点 → 两次 `onDelete`；因删除后**索引前移**，第二次删掉**相邻的另一张图**（错删非重删） |
| **★6/7** | `pattern_lock.dart:284`(`autoResetDelay`) / `:292`(200ms) | 可配/200ms | 手势锁自动重置 | 输完 4 位立刻开始下一笔 → 重置清空新选中点 → **手势中断、点选丢失**；`:292` 紧跟抬手，几乎必然与新一笔重叠 |
| **★8** | `main_screen.dart:640` `_justTapped` 复位 | 300ms | 解除「忽略滚动通知」保护 | 每次 tap 各排一个：t=0 与 t=250 各点一次 → 第一个在 t=300 提前解除，**第 2 次 300ms 保护被截成 50ms** → 点击后微滚动重新触发导航栏显隐（闪烁） |
| **★9** | `main_screen.dart:349`（叠加 `:296` 的 2s） | 500ms | 里程碑弹窗 | 弹窗最早 2.5s 后出现，此时用户已在滚动/进详情 → **弹窗盖到别的页面上**（★2 崩溃的前置条件） |
| **★16/17/18** | `gacha_screen.dart:109`(+500ms)／`:1996`&`:2289`(1200ms)／`:1889`&`:2173`(1500ms) | 500/1200/1500ms | 抽奖等待／自动 `Navigator.pop` | `:94`/`:127` 用状态字段+finally 挡住双击（**逻辑安全**），但 500ms 是 1500ms 动画结束后的**无意义空转**；`:1996/:2289/:1889/:2173` 只判 `Navigator.canPop` → **1200ms 内若上层再 push 路由，会 pop 掉用户的编辑页** |
| **★19** | `milestone_service.dart:273` | **4s** | 里程碑自动 `pop` | 同 ★17 型：`if (mounted && canPop)` pop 栈顶，**不保证是里程碑 dialog** |
| **★12/13/23** | `splash_screen.dart:372`(200ms)+`:380`(1200ms)、`real_page_turn.dart:60`(splash 传 1200ms) | 200/1200ms | 启动 fade+scale／自动跳转／翻页 | **三段串行 2200ms**，而 `_onSplashComplete` 在 1200ms 触发 → **转场动画没播完就切页**；启动期主线程卡顿把 200ms 推到 600ms 时，fade 正好在跳转瞬间完成 → 「一片空白突然跳转」 |
| **★14/15** | `smart_notifications.dart:114`(默认 3s)/`:283`(500ms) | 3s/500ms | Toast 自动消失／BadgeUnlock 完成 | 3s 内再次 show → 旧 toast 已卸载（mounted 兜底）；但新 toast 400ms spring 入场 + 旧 reverse 落空 → **连续弹窗「硬切」**；`:283` 的 `onComplete` 可能在已 pop 页面上触发 |
| **★10/11/20** | `theme_backgrounds.dart:83`(1s)/`:687`(500ms)、`app_lock_screen.dart:87`(500ms) | 1s/500ms | 首朵樱花／首个海洋生物／拉起指纹 | 前两处仅 `mounted` 兜底无句柄；`:87` 的 500ms 内用户已成功输手势 → 两个认证通道短暂并存 |
| **★21/24/25/26/27** | `animated_feedback.dart:569`(index*50ms)、`immersive_experience.dart:608`(50ms/字)、`random_sticker_overlay.dart:78`(3~12s)/`:133`(50ms)/`:207`+`:222`(3~8s) | — | SlideIn 启动／打字机／贴图调度／淡入／淡出移除 | `Interval` 已做错峰，`:569` **再延迟一次=双重错峰**（第 5 项后 clamp 0.6 饱和）；打字机 100 字=100 个 Future 只剩 mounted 拦；贴图自递归链 dispose 后靠 `!mounted` 停链；`:133` 用 50ms 近似「下一帧」，低端机可能同帧合并 → **淡入不触发** |
| **★22/29/31** | `scroll_reveal.dart:118`、`accessibility_components.dart:328`、`performance_optimizations.dart:238` | delay/0/delay | 入场延迟／语义通知／延迟建树 | 均 mounted 兜底；`scroll_reveal:118` 唯一用例未传 delay（=0），属潜在风险 |

**纯业务延迟 20 处**（证明分类完整）：`main.dart:86`(2s 浮窗)、`diary_provider.dart:184`(500ms)、`cloud_sync_service.dart:1216/:1457/:1780`、`image_cache_service.dart:394`、`pdf_export_service.dart:335`、`sound_service.dart:72/:100/:102`、`write_diary_screen.dart:621`(3s 云同步)、`voice_diary_service.dart:364`、`floating_window_service.dart:39/:59`、**`main_screen.dart:296`(2s 徽章)**、**`main_screen.dart:303`(3s 预加载)**、`testing_utils.dart:51`、`performance_optimizations.dart:274/:350`。
> `:296`(2s) 与 `:303`(3s) 是启动链路最长两个定时任务（任务书点名）。它们不驱动动画，但 **`:296`→`:349` 的 500ms 二次延迟**意味里程碑弹窗最早在进入主界面 **2.5s** 后弹出 —— 此时用户往往已在滚动列表（见 ★9/★2）。

**改法：句柄 + dispose + 重入先 cancel**

```dart
// 反例（现状，全 lib 52 处）
Future.delayed(const Duration(milliseconds: 100), () {
  if (mounted) setState(() => _forceShowNav = false);
});
// 正例
Timer? _forceShowTimer;
void _showNavBarImmediately() {
  setState(() { _isNavVisible = true; _forceShowNav = true; });
  _forceShowTimer?.cancel();               // ← 关键：冲掉上一次的复位
  _forceShowTimer = Timer(const Duration(milliseconds: 100), () {
    if (mounted) setState(() => _forceShowNav = false);
  });
}
@override
void dispose() { _forceShowTimer?.cancel(); /* ... */ }
```
`RippleButton`(★3) 还须**捕获 id 值**：`final removedId = _rippleId - 1;` 在 add 时定格，回调里 `removeWhere((r) => r.id == removedId)`。

## ④ 动画锁死窗口

| # | 位置 | 窗口 | 解除方式 | 缺陷 |
|---|---|---|---|---|
| L1 | `main_screen.dart:426`→`:451` `_isPageChanging` | **350ms 写死** | `Timer(350ms)`(`:436`) | ⚠️ **与实际动画不等长**：`animateToPage` 只有 **300ms**(`:431`) → 动画结束后 **50ms 死区**仍吞滚动通知；若实际时长偏离则提前/滞后解锁，用户快速上滑被吃掉 |
| L2 | `main_screen.dart:454` `_justTapped` | **300ms** | `Future.delayed(300ms)`(`:640`) | ⚠️ 不可取消且**不重入安全** → 保护窗口被截成 50ms（★8） |
| L3 | `gacha_screen.dart:77/:94` `_isDrawing`/`_isShaking` | 1500+500=**2000ms** | `finally`(`:127`) | ✅ **全 lib 唯一解耦良好**：状态字段+finally，不靠 Timer；但 500ms 无意义等待使锁偏长 |
| L4 | `real_page_turn.dart:192` `if (_controller.isAnimating) return;` | 动画全长 | **`isAnimating` 状态查询** | ✅ **正面样板**：唯一用「动画真实状态」而非猜时长守卫，天然与动画等长 |
| L5/6/7 | `real_page_turn.dart:109/:386`、`milestone_service.dart:469`、`diary_detail_screen.dart:587` `IgnorePointer` | 动画/彩带期间 | 包裹层 | 合理（遮挡层不挡输入） |
| L8 | `self_talk_screen.dart:128` `_isSending`+`:831` | 网络等待 | `finally`(`:185`) | ✅ 正确，但 `:155` 的 `clear()` 在 await 后；若 `sendMessage` 抛异常则 `_isSending` 永真 → **发送按钮永久禁用**（无 try/finally） |
| L9/L10 | `custom_bottom_nav.dart:239-244` AnimatedFAB／`main_screen.dart:646` `_longPressTimer`(2s) | 按压／2s | `onTapUp`/`onTapCancel`；`:653`/`:656` cancel | 合理；L10 是唯一「Timer 但有 cancel」，`_longPressTriggered` 仅 `:213` 手动复位 |

**10 处屏蔽逻辑中：写死 Timer 猜时长 = L1(350ms)、L2(300ms)；用 `isAnimating`=L4；状态字段+finally = L3、L8。**

### 4.1 L1 改法：`whenComplete` 替代 `Timer(350ms)`

```dart
// 现状 main_screen.dart:424-442
_isPageChanging = true;
_pageController.animateToPage(index, duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut);
_pageChangeTimer = Timer(const Duration(milliseconds: 350), () { ... });

// 改法：让动画自己报告结束 + 序号防竞态（同 diary_search_screen.dart:39 的 _searchSeq 手法）
int _pageChangeSeq = 0;
final seq = ++_pageChangeSeq;
_pageController
    .animateToPage(index,
        duration: PrimitiveAnimation.normal,          // 300ms，顺手统一
        curve: PrimitiveAnimation.easeInOutCubic)     // 统一曲线
    .whenComplete(() {
  if (!mounted || seq != _pageChangeSeq) return;       // 已有更新的切换，丢弃本次
  _isPageChanging = false;                            // ← 与动画严格等长，零死区
  _showNavBarImmediately();
  _resetInactivityTimer();
});
```

**收益**：① 锁窗口 350ms→实际 300ms，**消除 50ms 死区**；② 连点只对最后一次生效；③ 去掉一个 `Timer` 字段与 dispose cancel。

> **为何不用 `addStatusListener`**：`PageController.animateToPage` 不暴露 `AnimationController`，硬要 status 得挂 `ScrollPosition.isScrollingNotifier`（脆弱）。`animateToPage` 返回的 Future 在动画结束/被打断时都会 complete，语义正确。真要 `status` 监听需把 PageView 改成 `AnimationController` 驱动 —— 会破坏 `onPageChanged` 既有契约，**不建议**。

**连带修复**：L1 的 350ms Timer 解除时调 `_showNavBarImmediately()`(`:439`)，后者内部再排 100ms(★1) → **一次 tab 切换串 350+100ms 两段定时器**。改法落地后缩为「300ms 完成 → 一次立即显示」，★1 触发次数同步下降。

## ⑤ 统一参数表

### 5.1 21 种时长：200ms 用 21 次，但令牌阶梯里没有它

| 时长 | 次数 | 归属 |
|---|---|---|
| 100ms | 11 | ✅ `micro`/`microDuration` ＋ `main_screen:168` ＋ 3 处音效节流 |
| 150ms | 6 | ✅ `fast` ＋ `custom_bottom_nav:222` |
| **200ms** | **21** | ⚠️ **`quickDuration` 仅在 app_theme，design_tokens 里根本没有** |
| 250ms / 350ms | 3 / 1 | ❌ 无令牌（`main_screen:717`、`self_talk:119`、`smart_recall_v2:286`；`:436` 锁窗口魔数） |
| 300ms | **30** | ✅ `normal`（最多） |
| 400ms / 600ms | 8 / 8 | ❌ 无令牌 |
| 500ms / 800ms | 13 / 8 | ✅ `slow` / `elaborate` |
| 1000~4000ms | 25 | ❌ 场景专用（呼吸/打字机/贴图/彩带），可保留 |

**核心矛盾：200ms 用了 21 次（仅次于 300ms），而 design_tokens 阶梯是 100/150/300/500/800 —— 没有 200。** 想用 200 的人只能写裸数字；他们本想写的是「`fast` 与 `normal` 之间那一档」。这是时长散用最直接的成因。

### 5.2 同一交互跨多时长（4 组实证）

| 交互 | 涉及的动画 | 时长/曲线 | 后果 |
|---|---|---|---|
| **底部导航选中** | `AnimatedContainer:146` ＋ `AnimatedScale:161` ＋ `AnimatedDefaultTextStyle:173` | 全 200ms，前两者 `spring`，第三者 **默认 linear** | ⚠️ 文字线性淡入、图标 spring 弹跳，**同一格三通道节奏不同** |
| **导航栏显隐** | `AnimatedSlide:715` ＋ `AnimatedOpacity:719` | 250ms `easeOutCubic` / 200ms **linear** | ⚠️ t=100ms 位移 79.5%、透明度 50% → **半透明滑到位**（D4） |
| **Tab 页切换** | `animateToPage:429` ＋ `:420` ＋ `:168` ＋ `_isPageChanging:436` | 300/0/100/350ms | ⚠️ **一次点击串 4 个时长，其中 250/350 是魔数** |
| **列表入场** | `DiaryListItemTransition`（前 10 项）＋ `ScrollReveal`（第 11 起，`:239` 分界） | 父驱动 Interval / 300ms | ⚠️ 两套完全不同的入场体系 |

### 5.3 建议阶梯（6 档）+ 可直接抄的常量块（替换 `design_tokens.dart:254-276`）

`80 → 按压极速｜150 → 微交互｜200 → 小过渡（★新增，补断档）｜300 → 标准过渡｜500 → 大过渡｜800 → 叙事动画`
250→200、350→300、400→300、600→500，**预计消除 27 处裸数字**。

```dart
/// 动画原始值 —— 全应用唯一曲线/时长来源。
/// 规则：lib/ 下除本文件外，禁止出现 `Cubic(` 字面量与动画时长裸数字。
class PrimitiveAnimation {
  PrimitiveAnimation._();

  // ---- 时长阶梯（6 档覆盖全部语义） ----
  static const Duration instant = Duration(milliseconds: 80);    // 按压极速
  static const Duration micro   = Duration(milliseconds: 100);   // 兼容既有引用
  static const Duration fast    = Duration(milliseconds: 150);   // 微交互/选中态
  static const Duration quick   = Duration(milliseconds: 200);   // 小过渡（★补断档）
  static const Duration normal  = Duration(milliseconds: 300);   // 标准过渡
  static const Duration slow    = Duration(milliseconds: 500);   // 大过渡
  static const Duration elaborate = Duration(milliseconds: 800); // 叙事动画

  // ---- 曲线（按语义命名，只留 4 条） ----
  /// 入场/缓出主力：x=0.3 走完 87.7%，观感「快而不突兀」
  static const Cubic enter = Cubic(0.16, 1, 0.3, 1);
  /// 双向过渡：x=0.3 只走 11.2%，用于需要「看清过程」的状态切换
  static const Cubic standard = Cubic(0.65, 0, 0.35, 1);
  /// 唯一允许过冲：峰值 1.0978(+9.78%)，仅限物理按压与奖励弹出
  static const Cubic spring = Cubic(0.34, 1.56, 0.64, 1);
  /// 柔和缓出：比 enter 慢 3.4 个点（x=0.3 时 84.3%），用于大面积元素
  static const Cubic gentle = Cubic(0.23, 1, 0.32, 1);

  // ---- 语义别名（转发，避免一次性大改） ----
  static const Cubic easeOutExpo    = enter;
  static const Cubic easeInOutCubic = standard;
  // ⚠️ 已删除（全 lib 零使用，见 §1.4）：slowCurve(0.4,0,0.2,1) / bouncyCurve / smoothCurve
}
```

### 5.4 令牌去重（11 处 → 1 处）

| 步 | 动作 | 文件 |
|---|---|---|
| 1 | **保留** `:254-276` 为唯一来源 | design_tokens |
| 2 | `:125-137` 五个 Curve 改**转发**（`= PrimitiveAnimation.enter` 等），**不改任何调用方** | app_theme |
| 3 | `:375-377` 三个重复曲线同上；`:140-148` 五个时长改 `= PrimitiveAnimation.xxx` | app_theme |
| 4 | `:603` 裸 `Curves.easeOutExpo` → `PrimitiveAnimation.enter` | app_theme |
| 5 | `:223` 局部 `springCurve` 删除；`:205/:305` 两处裸 `Cubic(0.16,1,0.3,1)` → `enter` | page_transitions / swipeable |
| 6 | `:407-430` `Durations`/`AppCurves` 保留（对外 API 稳定，内部已是转发） | design_extensions |
| 7 | **删 6 个死令牌**（§1.4 表） | app_theme + design_tokens |

**收益**：曲线常量 11→4（+3 别名）；「改一处全局生效」重新成立；D1/D2/D3 因只剩 4 条曲线自然收敛；21 处裸 `200` 有了 `quick` 归属。

### 5.5 语义映射表（写码时照抄，不凭记忆）

| 场景 | 时长 | 曲线 |
|---|---|---|
| 按压反馈（按钮/卡片缩放） | `fast` 150ms | `spring` |
| 选中态切换（导航/开关/标签） | `quick` 200ms | `standard`（**不要 spring**，见 §2.4 #6） |
| 入场（列表项/卡片/页面） | `normal` 300ms | `enter`（大面积元素用 `gentle`） |
| 退场（移除/关闭） | `fast` 150ms | `Curves.easeIn`（退场加速离开，不用缓出） |
| 页面路由 | `normal` 300ms | `enter`（进）/ `easeIn`（出） |
| 奖励/抽卡弹出 | `slow` 500ms | `spring`（唯一正当场景） |
| 骨架屏 shimmer | 1500ms | `linear`（循环用双向曲线会「喘」） |

## ⑥ 5 套主题动效降级建议

### 6.1 现状：7 个 repeat 控制器 + 5/5 `shouldRepaint => true`

| 主题 | 控制器 | 周期 | 声明 | shouldRepaint |
|---|---|---|---|---|
| 樱花 | 1 | 10s | `theme_backgrounds.dart:54-57` | `:624` → true |
| 海洋 | **3**（波浪/气泡/生物） | 4/8/3s | `:654-669` | `:1244` → true |
| 极光 | 1 | 5s | `:1290-1293` | `:1494` → true |
| 黄金 | 1 | 6s | `:1559-1562` | `:1983` → true |
| 星空 | 1 | 4s | `:2009-2012` | `:2250` → true |
| **合计** | **7** | — | — | **5/5 全 true** |

`shouldRepaint=>true` 的代价：每个 ticker 帧都全量执行 `paint()`。`OceanPainter` 每帧画 15 气泡 + ≤3 生物 + 4 层渐变，`_StarryPainter` 画 80 星 + 流星池 —— **无脏区裁剪、无分层缓存**；且 `AnimatedBuilder` 每帧在 builder 里 `new` 一个新 painter 实例。

### 6.2 同屏 ticker 上限（特殊主题下 MainScreen 可见）

| 来源 | repeat ticker | 备注 |
|---|---|---|
| 主题背景（海洋最重） | **3**（其它主题 1） | `main_screen.dart:663` `ThemeBackgroundFactory.wrap` 只包一层 |
| `calendar_screen.dart:2675` `BreathingAnimation`（农历高亮） | **1** | `isHighlight` 为真时，2200ms `repeat(reverse)` |
| `profile_screen.dart:806` `BreathingAnimation`（用户卡片） | **1** | 4000ms `repeat(reverse)` |
| **合计（海洋主题且两 tab 都访问过）** | **5 个常驻 repeat ticker** | 四 tab 全开 `AutomaticKeepAliveClientMixin`（`timeline:32`/`calendar:32`/`stats:24`/`profile:50`）→ **切走不销毁** |

**结论：特殊主题下同屏常驻 5 个 `repeat()` ticker**（海洋 3 + 日历 1 + 我的 1）；樱花/极光/黄金/星空降为 3 个。

### 6.3 两个会放大该数字的隐患（未触发但一爆）

| 隐患 | 数字 | 状态 |
|---|---|---|
| **`DiaryCardSkeleton` 内嵌 12 个 `SkeletonContainer`，每个各自 new 一个 `ShimmerEffect`（`skeleton_loading.dart:103`），每个 `ShimmerEffect` 自带 1 个 `repeat()`（`:36-39`）** | 单卡 **12** 个 ticker；`paged_diary_list.dart:282` 渲染 5 卡 = **60** 个 | `PagedDiaryList` 目前仅定义/导出，`lib/screens` 零调用 → **潜伏炸弹**：一旦接线，60 个 `ShaderMask` 每帧重绘 |
| `widgets/starry_background.dart` 独立实现（1 twinkle + **4 流星**，`:46-49`/`:109`） | 5 个 | **死文件**：全 lib/test 无 `import 'starry_background.dart'`（grep 零命中），实际走 `theme_backgrounds.dart:1987` 那份 → 建议删除 |

### 6.4 降级方案（3 档，不改视觉语义）

**档 0 — 零风险，应立即做**

| # | 动作 | 位置 | 收益 |
|---|---|---|---|
| 0-1 | `shouldRepaint` 改**比较实际数据**：只依赖单值 progress 的比 `old.progress != progress`；含 List 的比 `identical(particles, old.particles)` | `:624 :1244 :1494 :1983 :2250` | 父级额外重建时不再白重画整帧 |
| 0-2 | 删除死文件 `widgets/starry_background.dart` | 432 行整文件 | 消除 5 个潜在 ticker + 一份重复实现 |
| 0-3 | 海洋 3 控制器合并为 1（`Listenable.merge` 已在 `:784-788`）：波浪 4s/气泡 8s/生物 3s 由单个 24s 主循环按相位派生（`%1`、`/3`、`/8`） | `:654-669` | ticker 3→1，同屏 5→3 |

**档 1 — 低功耗（主题可见但不交互时）**：① 用 `TickerMode` 包裹背景（`TickerMode(enabled: _isNavVisible || isInteracting, ...)`；**全 lib `TickerMode` 零使用** —— 包一层即可在下滑阅读、导航栏隐藏时**自动停掉所有背景 ticker**）；② `main_screen.dart:141` 已有 `didChangeAppLifecycleState`，`paused` 时 `_controller.stop()`、`resumed` 时 `repeat()`（给背景加 `setActive(bool)` 接口）；③ 降帧率观感：周期拉长（樱花 10→14s、极光 5→7s）摊薄每帧位移，配 `RepaintBoundary` + `CustomPaint(isComplex/willChange)`。

**档 2 — 强降级（低端机/省电/系统「减少动效」）**：① 尊重 `MediaQuery.of(context).disableAnimations`（Flutter 3.x 已提供）—— 为真时背景**只画静态首帧**（`value=0.35` 定住不 repeat）、停所有 `repeat()`、`AnimatedSlide/Opacity` duration 置 0；② 运行时降粒子数（樱花 25→12 花瓣；海洋 15→8 气泡、生物上限 3→1；星空 80→40 星；黄金 15→8 沙粒 —— 数字都在 `initState` 硬编码，抽成 `int count` 参数）；③ 仅前景静止：背景换「静态渐变 + 少量定格装饰」（5 套 `Container` 渐变在 `:770/:1304/:1630/:2065` 本就是好看的静态底），仅首次进入播一次 300ms `enter` 淡入。

**优先级**：先 **0-1 + 0-2 + 0-3**（纯收益、零观感风险、约 1h），再 **1-①（`TickerMode`，单点改动收益最大）**，档 2 作低端机兜底。

### 6.5 五套主题的动效「性格」

现有 5 套背景**全部线性相位**（直读 `_controller.value` 不经 `Curve`）—— 这是**正确**做法：循环动画若上缓动会让周期出现「快慢突变」。要统一的是**前景交互**而非背景：

| 主题 | 背景（循环） | 前景交互建议 |
|---|---|---|
| 樱花 | 线性 10s，25 花瓣 | 卡片入场 `enter` 300ms（可选 `gentle`）；**禁** spring（花瓣已够柔） |
| 海洋 | 线性 4/8/3s | 同上；生物出现 `gentle` 500ms 淡入 |
| 极光 | 线性 5s | 大面积元素用 `gentle`，避免 `enter` 急促 |
| 黄金 | 线性 6s | **唯一可用 `spring`** 的主题（金属质感+弹跳合理），限奖励类元素 |
| 星空 | 线性 4s | 流星已是叙事动画，前景一律 `enter`，**禁** spring |

## 结论摘要（5 条）

1. **曲线体系「4 套入口 / 11 处重复 / 6 个死令牌」**：数值无漂移，但命名与入口重复导致同类语义三套曲线（§1.1/§1.4/§5.4）。
2. **过冲被高估**：`Cubic(0.34,1.56,0.64,1)` 实际峰值 **1.0978（+9.78%）**，非 1.56；8 个使用点里 4 处误用（入场/二值状态），真正弹跳场景（抽卡）只用 1 次（§2.2/§2.4）。
3. **缓出手感被低估**：`easeOutExpo` 在 300ms 的第 90ms 已走完 **87.7%**，实际感知约 100~120ms —— 所有「设计 300ms 却感觉一闪而过」的根源（§2.3）。
4. **52 处 `Future.delayed` 全部不可取消**，32 处驱动动画/UI 恢复；最危险：`RippleButton` 的 id 竞态（涟漪永久残留）、`goal_progress_card` 的 2s 链（dispose 后 forward 崩溃）、`_showNavBarImmediately` 的 100ms 重入（§3）。
5. **锁死窗口仅 1 处用了正确姿势**：`real_page_turn.dart:192` 的 `isAnimating` 守卫是全 lib 唯一「与动画等长」的锁；`main_screen` 的 350ms 与 300ms 两处都是猜时长，应改 `whenComplete`（§4）。
