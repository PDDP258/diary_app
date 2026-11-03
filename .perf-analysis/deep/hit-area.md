# 深挖 1：点击热区体系全量审计（小记日记 / Flutter 3.x）

> 只读审计，未改 `lib/` 任何源码，未跑 flutter/dart 工具链。SDK 结论已核对
> `C:\flutter\flutter\packages\flutter\lib\src` 真实行号。基准 = **最小触控目标 48×48 dp**。
> 两处 `ThemeData`（`app_theme.dart:380`、`theme_provider.dart:318`）均 `useMaterial3: true`，
> **未设置** `materialTapTargetSize`/`visualDensity` ⇒ 全 App = `padded` + `VisualDensity.standard`。

**全量计数**：`GestureDetector(` **146**（显式 `behavior:` 仅 3 处、全 `translucent`；含 tap/long 回调 133 处，
其中 **129 处无 `onTapDown` ⇒ 零按下态**）；`InkWell` 21；`ListTile` 52；`IconButton` **66 次构造调用**
（grep 的 73 行 = 66 调用 + 4 自有封装/转发 + 3 import/export）；`onTapDown` 11；`onLongPress` 27；
`HapticFeedback.*` 76（light 32 / medium 28 / heavy 8 / selection 8，散在 23 文件）；`playClick()` 16 / 7 文件。

## §0 三条根基事实

1. **`IconButton` 的 48dp 由 `_InputPadding` 补出，不是 `constraints`。** M3 分支
   `icon_button.dart:720` → `button_style_button.dart:578-596`：`tapTargetSize == padded` 时
   `minSize = kMinInteractiveDimension(48) + densityAdjustment`；其 `hitTest`（`:736-749`）在点到
   48×48 边缘但不在 40×40 视觉区时 forceToPoint 到 child 中心再测 ⇒ **48×48 全域可点**。
   ⇒ 不动 `visualDensity`/`tapTargetSize` 时，`IconButton` 恒为「视觉 40 / 热区 48」。**仅 2 处例外（§③）。**
2. **`InkWell` 热区 ≡ 父级给它的尺寸。** `ink_well.dart:1406-1418` 内部是 `GestureDetector(behavior: opaque)`
   ⇒ 整个 render box 归它、无需子元素命中；但它自身多大取决于外层是 `Expanded` 还是 `Center`。
3. **`GestureDetector` 默认 `deferToChild`（143/146 处）**：子元素须命中才响应。子若是
   `Container(decoration:)`，`RenderDecoratedBox.hitTestSelf`（`proxy_box.dart:2468`）走
   `BoxDecoration.hitTest`（`box_decoration.dart:375-390`）：矩形/圆角 ⇒ 整框命中；
   **`shape: circle` ⇒ 只有内切圆命中，四角死 —— 固定失效 1−π/4 = 21.5%，与直径无关。**

## §① 热区尺寸总表

### A 类：< 48dp —— 不合格（15 处）

| # | 元素 | file:line | 视觉 | 实际热区 | 成因 |
|---|---|---|---|---|---|
| A1 | **速记悬浮按钮（全局入口）** | `main_screen.dart:681` | 44×44 | **44×44** | GD `deferToChild` + `Container(44,44)` |
| A2 | 标签 Chip | `write_diary_screen.dart:1729-1746` | 高 ~24 | **高 24~28** | `materialTapTargetSize: shrinkWrap` + `padding: zero` + `visualDensity: compact` 三重叠加 |
| A3 | 预设色板 | `course_edit_screen.dart:159` | 28 圆 | **28**（实得 616dp²） | GD + `Container(28,28)` + circle |
| A4 | 颜色圆点 ×2 | `tag_management_screen_v3.dart:341`、`:439` | 36 圆 | **36** | 同上 |
| A5 | AI 发送 | `ai_chat_screen.dart:536` | 38 圆 | **38** | 同上（主操作） |
| A6 | 语音播放 | `voice_recorder_button_v2.dart:346` | 40 圆 | **40** | 同上 |
| A7 | 关于页调试入口 | `profile_screen.dart:2569` | 40 圆 | **40** | 同上（有意隐蔽，低危） |
| A8 | 应用锁/生物识别开关 ×2 | `profile_screen.dart:1421`、`:1499` | 48×28 | **48×28** | GD + `Container(48,28)`，高度不足 |
| A9 | 详情左右翻页条 ×2 | `diary_detail_screen.dart:597`、`:646` | 44×全高 | **44×全高** | GD + `Container(width:44)`，宽差 4 |
| A10 | 「恢复预设」 | `semester_settings_screen.dart:159-167` | 高 ~28 | **高 ~28** | `minimumSize: Size.zero` + `tapTargetSize: shrinkWrap` + `padding h12 v6` |
| A11 | 节次自定义/删除 IconButton ×2 | `semester_settings_screen.dart:343`、`:361` | 16 / 18 | **40×40** | `visualDensity: VisualDensity.compact`（48−8，见 §③） |
| A12 | 「开始写日记」 | `timeline_screen.dart:619-648` | 高 ~42 | 全宽×**42** | `InteractiveButton(padding: zero)`，组件无最小高 |
| A13 | 心情占比卡 | `stats_screen.dart:1102-1104` | 高 ~43 | 全宽×**43** | 同上 + `onPressed: () {}` 空回调 |
| A14 | 星期选择 | `course_edit_screen.dart:353` | 高 36 | **高 36** | GD + `Container(height:36)` |
| A15 | 「更换教务系统」 | `course_schedule_screen.dart:166` | — | ~40~48 | `dense: true`；SDK `list_tile.dart:312` 明示 dense 把 leading/trailing 压到 32 且与无障碍冲突，M3 下不建议 |

### B 类：48~56 dp —— 刚好合格

| 元素 | file:line | 热区 | 备注 |
|---|---|---|---|
| **底部导航 4 格** | `custom_bottom_nav.dart:132-193` | **50×57** | 宽仅 +2dp，且**格内 45~55% 死区**（§②） |
| IconButton 默认 64 处 | 全 lib | **48×48** | 视觉 40×40 由 `_InputPadding` 补足；AppBar 相邻两个视觉隔 8、热区 0 |
| 分类/标签色块 ×4 | `tag_management_screen_v3.dart:494/561/626/694` | 50×50 | |
| 头像/徽章触发 | `profile_screen.dart:620`（Tooltip 包 52） | 52×52 | |
| 等级/词云块 ×2 | `profile_screen.dart:1238`、`:1275` | 48×48 | |
| 自言自语发送 | `self_talk_screen.dart:830` | 48×48 | |
| 录音按钮 ×2 | `voice_recorder_button.dart:484`、`voice_recorder_button_v2.dart:229` | 48×48 | 圆形 ⇒ 实得 78.5% |
| 去年今日「查看」 | `stats_screen.dart:1411` | 全宽×52 | |
| 手势锁键盘区 | `pattern_lock.dart:450` | 全宽×50 | |
| `InteractiveIconButton` | `interactive_button.dart:242-254` | **48×48** | InkWell + `padding all(12)` + icon 24 ⇒ 手写出的正解，可作范式 |
| `AccessibleIconButton` | `accessibility_components.dart:148-150` | `minSize`(默认 48) | 项目已有正确组件，**全仓仅 2 处使用** |

### C 类：≥ 56 dp —— 富余

`ListTile` 52 处（M3 默认 56 单行 / **72 双行**，`_buildMenuGroup` 属此）· FAB 72 `custom_bottom_nav.dart:87` ·
`AnimatedFAB` 72 `:238` · `profile_screen.dart:620/740/841`（52/56/80）· `stats_detail_screen.dart:1329` 80 ·
`data_management_screen.dart:1513` 240 · `tag_management_screen_v3.dart:298/401` 60 / `:494/561/626/694` 50 ·
`voice_recorder_button.dart:262/327` 56 · `motion_photo_widget.dart:403` 80 · `diary_cinema_screen.dart:756` 64 ·
`write_diary_screen.dart:2048` 100 · `profile_screen_min.dart:115` 72（**死文件，全仓无引用**）。

### D 类：假合格 —— 尺寸够但命中被形状/层级吃掉

| 元素 | file:line | 名义 | 实际可点 | 损失 |
|---|---|---|---|---|
| **中间 FAB** | `custom_bottom_nav.dart:87-126` | 72×72 | 直径 72 内切圆 | 四角 1113dp² = **21.5%** |
| AnimatedFAB | `custom_bottom_nav.dart:238-275` | 72×72 | 同上 | 21.5% |
| 其余 12 个 circle+GD 站点 | `tag_management:341/439`(36)、`ai_chat:536`(38)、`voice_recorder_v2:229/244/346`、`profile:2569`(40)、`motion_photo:403`(80)、`diary_cinema:756`(64)、`profile_screen_min:115`(72) | — | 内切圆 | 恒 **21.5%** |
| 全屏手势层 | `main_screen.dart:632-658` | 整页 | `translucent` ⇒ 自身+子都命中 | 不抢子按钮，但**抢长按语义**（§④.4） |

> **结论**：「IconButton 塌陷」担心基本不成立（66 处仅 2 处被打到 40）。真正塌的是
> **手搓 `GestureDetector` + 小 `Container`**（A1~A7、A14）与 **把 `shrinkWrap`/`Size.zero`/`compact`
> 套在 Material 按钮上**（A2、A10、A11）。

## §② 底部导航专项推导（`custom_bottom_nav.dart`）

### 2.1 约束流

```
Stack(alignment: bottomCenter)                                  :25-27
├─ Container(height:80, margin: fromLTRB(12,0,12,8))            :30-32
│   └─ decoration: Border.all(width:0.5)  ⇒ 内部再扣 1.0         :64-67
│       └─ ClipRRect→RepaintBoundary→BackdropFilter→Container(radius16)
│           └─ Row(crossAxisAlignment: center)                  :69-70
│               ├─ _buildNavItem ×4 (Expanded)   :72-76 / :132-193
│               └─ SizedBox(width:72) ← 固定,非 Expanded         :74
└─ Positioned(bottom:12) → GD(无 behavior) → Container(72×72, circle)  :85-126

_buildNavItem = Expanded(:136 tight 宽) > Center(:137 **只居中不拉宽**·关键) > Material
              > InkWell(:140 热区=自身尺寸) > AnimatedContainer(h12 v8, 无 w/h ⇒ 只包内容)
              > Column > [Icon 26 | SizedBox 4 | Text(11, height:1.0)]   :159-185
```

### 2.2 每格宽度（**含 0.5dp 边框**，最易算错）

```
W_outer = S − 24                (margin 左右各 12)
W_inner = W_outer − 1 = S − 25  (Border.all 0.5 × 2)
slotW   = (S − 25 − 72) / 4 = (S − 97) / 4
```

| 屏宽 S | slotW | 每侧空余 `(slotW−50)/2` | 4 格合计浪费 |
|---|---|---|---|
| **360** | **65.75** | 7.875 | **63.0 dp** |
| **390** | **73.25** | 11.625 | **93.0 dp** |
| **412** | **78.75** | 14.375 | **115.0 dp** |

### 2.3 每格热区（内容驱动，**与屏宽无关**）

```
内容高 = Icon 26 + SizedBox 4 + Text(11 × height 1.0 = 11) = 41
容器高 = 41 + v8×2                                        = 57
内容宽 = max(Icon 26, 两字×11 = 22)                       = 26
容器宽 = 26 + h12×2                                       = 50
```

`Row` 高 = 80 − 1 = 79；`Center` 给 loose ⇒ **InkWell = 50×57**，内部 `opaque` ⇒ 全域可点。
`AnimatedScale(1.15)` 只改绘制不改布局 ⇒ 选中态热区仍 50×57。

### 2.4 结论

| 屏宽 | 格子 slotW×79 | 真热区 50×57 | 命中率 |
|---|---|---|---|
| 360 | 65.75×79 | 2850 / 5194 | **54.9%** |
| 390 | 73.25×79 | 2850 / 5787 | **49.3%** |
| 412 | 78.75×79 | 2850 / 6221 | **45.8%** |

- **高度合格（57 ≥ 48）**，不存在「塌成小图标」。
- **宽度只靠 `h12` 撑住**：`Icon 26 + 2×12 = 50`。**改成 8 ⇒ 42 < 48** —— 4dp 的悬崖，
  任何「收紧导航栏 padding」的视觉优化会顺手把它打回不合格。
- **垂直还有 22dp 死带**：`Row` 79、pill 57 ⇒ 上下各 11dp 点了无 ripple、也不唤出导航栏。

### 2.5 FAB 与相邻两格：**互不重叠**，但功劳不在「让位 72」

左右 margin 对称 + 4 等分 + 中间固定 72 ⇒ **让位区中心恒等于屏心**，
让位区 = `[S/2−36, S/2+36]`，宽 72 恰等于 FAB 直径 72。净间距 = `(slotW−50)/2`：

| 屏宽 | 第2格右缘 | FAB 左缘 | 净距 | FAB 右缘 | 第3格左缘 | 净距 |
|---|---|---|---|---|---|---|
| 360 | **136.125** | 144 | **7.875** ⚠️<8 | 216 | **223.875** | **7.875** ⚠️ |
| 390 | **147.375** | 159 | **11.625** ✅ | 231 | **242.625** | **11.625** ✅ |
| 412 | **155.625** | 170 | **14.375** ✅ | 242 | **256.375** | **14.375** ✅ |

⇒ 只有 **360dp 档（≈ 主流 5.0"~5.5" 小屏）双侧破 8dp**；390/412 安全。
**关键反直觉点**：现在不重叠靠的不是 `SizedBox(width:72)`，而是 `Center` 把 InkWell 缩到 50。
一旦撑满 slot，让位区边界与相邻格热区就**相切（0dp）** ⇒ **撑满 + 让位 72→88 必须同时改**（§⑥ F-1/F-2）。

### 2.6 FAB 自身

`Positioned(bottom:12)`、72×72、`BoxShape.circle` + GD 无 behavior ⇒ 仅内切圆可点（21.5% 失效）；
`boxShadow(blur 20/40)` 让**看起来比 72 大** ⇒ 点阴影必无反应。尺寸 72 远超 48，问题在形状与**零按下态**。

## §③ IconButton 陷阱清单

**先纠正一个误判**：全 lib `constraints:` 出现点**没有一处属于 `IconButton`**，逐个核对 owner 为：
`ai_chat_screen.dart:425` / `self_talk_screen.dart:483`（`Container` maxWidth 聊天气泡）、
`calendar_screen.dart:1855` / `badge_service.dart:2628`（`Container` maxHeight 弹窗）、
`custom_sticker_overlay.dart:128` / `random_sticker_overlay.dart:287`（`Container` maxW/maxH 贴图）、
`accessibility_components.dart:88`（`ConstrainedBox(minWidth/Height: 48)`，**正确**用法）。⇒ **对 IconButton 热区零影响。**

**别混淆**：`stats_screen.dart:797/877/965/1104`、`timeline_screen.dart:621` 的 `padding: EdgeInsets.zero`
是 **`InteractiveButton`**；`write_diary_screen.dart:1744` 是 **`Chip`**；
`profile_screen.dart:1955` 的 `contentPadding: EdgeInsets.zero` 是 **`ListTile`**。

### 66 处 `IconButton` 的 arg-block 逐个解析

| 参数 | 覆盖处数 | 结论 |
|---|---|---|
| `padding:` | **0** | 48 补足机制完好 |
| `constraints:` | **0** | 同上 |
| `iconSize:` | **0**（`Icon(size:)` 12 处只影响字形、不影响热区） | 无影响 |
| `visualDensity:` | **2** | 这 2 处塌到 40×40 ↓ |
| 其余 64 处 | — | **48×48 / 视觉 40×40，合格** |

### 真正会塌的只有 2 处（同文件、同一 Row）

```dart
// semester_settings_screen.dart:343 和 :361
IconButton(
  icon: Icon(Icons.tune, size: 16, ...),   // 视觉仅 16px
  visualDensity: VisualDensity.compact,     // ← 致命
  onPressed: ...,
)
```
`compact = (−2,−2)` → `baseSizeAdjustment = (−8,−8)`（`theme_data.dart:3225/3307`，interval 4.0）
⇒ `_InputPadding.minSize = 48 − 8 = **40×40**`。且这俩在 `Row` 里**紧挨（`:359`↔`:360` 无 SizedBox）**，
左侧直接贴 `Expanded(InkWell)` 时间块。右侧那个是「删除本节」——**误触即删**。
另需警惕：`IconButton` 若被塞进高度受限父级，`_RenderInputPadding` 会 `constraints.constrain()`
把 48 压回去（`button_style_button.dart:699-701`）。

## §④ 相邻热区死区（< 8dp）

### 4.1 底部导航

| 关系 | 360 | 390 | 412 | 判定 |
|---|---|---|---|---|
| 格内左右死区（每侧） | 7.875 | 11.625 | 14.375 | 屏越宽死区越大 |
| FAB ↔ 相邻格 | **7.875** ⚠️ | 11.625 | 14.375 | 仅 360 破 8dp |
| 格 ↔ 格（InkWell 边缘距） | 15.75 | 23.25 | 28.75 | 相邻 tab 不会互触 ✅ |
| 格内上下死带 | 各 11 | 同 | 同 | **22dp 无反馈** ❌ |

### 4.2 分组菜单（`profile_screen.dart:2283 _buildMenuGroup`）

| 维度 | 实测 | 判定 |
|---|---|---|
| 行高 | 双行 M3 默认 **72**（leading 44、title 16 + subtitle 13 均塞得下，`contentPadding v6` 不改 72） | ✅ |
| **行间隔离** | `Divider(height: 1)` ⇒ **1dp** | ⚠️ <8dp；目标各 72 高、误触率低，但视觉分隔太弱 |
| 组间 | `SizedBox(height: 16)` ⇒ 16 | ✅ |
| 横向留白 | 外层 `fromLTRB(8,…)`（`:232`/`:236`）+ 组内 `contentPadding h20` ⇒ 图标距屏边 28；与多处 `horizontal: 20` 自洽 | ✅ |
| trailing chevron | `padding all(8)` + icon 20 ⇒ 视觉 **36** | ✅ 视觉小、行热区大（正确做法） |

### 4.3 其它 <8dp 并联点

| 位置 | 间距 | 说明 |
|---|---|---|
| `semester_settings_screen.dart:343` ↔ `:361` 两 IconButton | **0** | 40×40 紧贴，右为「删除本节」 |
| `:340` Expanded InkWell ↔ `:343` IconButton | **0** | 时间块与自定义开关紧贴 |
| `course_schedule_screen.dart:166` dense ListTile | 行高被压到 ~40~48 | dense ⇒ leading/trailing 32 |
| `diary_detail_screen.dart:597`/`:646` 翻页条 | 44 宽贴屏边、纵向全高 | 正文上误触翻页风险高，建议下半屏禁用 |
| 导航栏上沿 ↔ 内容区 | **0** | `Positioned(height:88)` 与内容区相接无缓冲 |

### 4.4 全屏手势层（`main_screen.dart:632-658`）

`Positioned.fill > GestureDetector(behavior: translucent)` 包住整个 `PageView`。
**不抢子按钮**（命中最深优先，子 `InkWell` 先进 arena 并胜出），**但抢长按语义**：
`onTapDown`(`:634`) 按下即启动 `Timer(2s)`，2.1s 后 `heavyImpact()` + `_openQuickNoteEditor()`(`:646-650`)
⇒ **在任意按钮/卡片上按住 2.1 秒就弹速记编辑器**，与全 lib **27 处业务 `onLongPress`** 直接冲突。
真正的长按应走 `onLongPress`，而非 `onTapDown` + 定时器模拟。

## §⑤ 按下态与触觉

| 形态 | 覆盖 | 说明 |
|---|---|---|
| `InkWell` 21 处 | splash + highlight + 系统 click | **最好的一档** |
| `IconButton` 66 / `ListTile` 52 | 内部 Material InkWell | 同上 |
| `InteractiveButton` 28 处 | `onTapDown`→scale(0.96)+lightImpact；`onTapUp`→playClick | 三合一，规范 |
| `RippleButton` 6 处 | `onTapDown`→ripple+lightImpact，**无声音** | 半套 |
| `SoundButton/SoundIconButton` 4 处 | 只音效，无触觉无缩放 | 半套 |
| **裸 `GestureDetector` 有 tap/long 133 处** | **129 处无 `onTapDown` ⇒ 完全无按下态**；仅 6 处回调里手写 haptic、2 处有 sound | **主力缺口** |
| `AnimatedFAB` `custom_bottom_nav.dart:238` | `onTapDown`→scale 0.9，无 haptic/sound | 局部 |
| **FAB `:87`** | 零按下态：无 scale、无 haptic、无 sound | ❌ 全 App 最高频按钮 |

**一致性**：同一个「保存」有四种反馈 —— `InteractiveButton`（触觉+声音+缩放）/ `RippleButton`（触觉+涟漪）/
`SoundButton`（只声音）/ 裸 `ElevatedButton`（都没有）。76 处 `HapticFeedback` 散在 23 文件；
项目**已有**统一封装 `AccessibilityHelper.triggerHaptic`（`accessibility_components.dart:549`）但**全仓 0 调用**。

### 已确认的「有反馈但无结果」bug

| file:line | 代码 | 后果 |
|---|---|---|
| **`timeline_screen.dart:619-620`** | `InteractiveButton(onPressed: () {})` | 点「开始写日记」⇒ **震动+音效+缩放**却**什么也不发生**，用户会反复点 |
| **`stats_screen.dart:1102-1103`** | `InteractiveButton(onPressed: () {})` | 心情占比卡整卡可点、有反馈、无动作 |
| `profile_screen_min.dart:80` | `_MenuItem(onTap: () {})`，而 `_buildMenuGroup` 的 ListTile 会先 haptic+playClick | 同症状；该文件**全仓无引用**，仅备查 |

### 另一处「反馈顺序错」

`RippleButton._addRipple`（`animated_feedback.dart:46-69`）在 **`onTapDown`** 里就
`HapticFeedback.lightImpact()` **并直接 `widget.onTap!()`**（`:68`）—— 业务动作在**手指按下瞬间**触发，
滑动离开无法取消（只注册了 `onTapDown`）。⇒ 「保存/立即购买」类按钮**开始滚动即触发**：
`profile_screen.dart:1372`（保存个人信息）、`write_diary_screen.dart:994`（保存日记）都中招。

## §⑥ 改法代码片段（可直接贴）

### F-1 + F-2 ★ 底部导航：热区撑满格子，同时让位 72→88【**必须一起改**】

```dart
// ① custom_bottom_nav.dart:74 —— 让位区 72 改 88
const SizedBox(width: 88), // 72(FAB) + 2×8(最小隔离带)

// ② custom_bottom_nav.dart:136-193 —— 只换嵌套顺序，视觉零变化
return Expanded(child: Material(color: Colors.transparent,
  child: InkWell(                       // opaque 命中 ⇒ 整格 × 整栏高(79)
    onTap: () => onTap(index),
    borderRadius: BorderRadius.circular(16),
    splashColor: scheme.primaryColor.withValues(alpha: 0.1),
    highlightColor: scheme.primaryColor.withValues(alpha: 0.05),
    child: Center(child: AnimatedContainer(   // ← 原 Center 降为 InkWell 内层
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? scheme.primaryColor.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(16)),
      child: Column(/* 原样不动 */))))));
```
- **为什么必须一起改**：单独撑满 ⇒ 让位区边界与相邻格热区**相切 0dp**（§2.5）；单独改 88 而不撑满 ⇒ 只是让视觉更空。
- 依据：`Align(widthFactor/heightFactor==null)` 在约束有界时铺满父级；`Expanded` 给已知宽、`Row` 给高 79。
- 效果：360dp 屏 **50×57 → 61.75×79**，格内死区 45.1% → **0**；FAB↔格间距恒 **8dp**（所有屏宽）。

### F-3 ★ FAB：去圆形衰减 + 补按下态

```dart
// custom_bottom_nav.dart:85-127（CustomBottomNav 改 Stateful，加 bool _fabPressed）
Positioned(bottom: 12, child: GestureDetector(
  behavior: HitTestBehavior.opaque,     // ← 方形 72×72 全可点，消除 21.5% 四角死区
  onTapDown: (_) => setState(() => _fabPressed = true),
  onTapUp: (_) { setState(() => _fabPressed = false); onAddTap(); },
  onTapCancel: () => setState(() => _fabPressed = false),
  onLongPress: () { HapticFeedback.mediumImpact(); onAddLongPress?.call(); },
  child: AnimatedScale(scale: _fabPressed ? 0.96 : 1.0,
    duration: const Duration(milliseconds: 120),
    child: Container(width: 72, height: 72,
      decoration: BoxDecoration(shape: BoxShape.circle, /* 原样 */),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 40))))))
```
> 不想动 State 时，最低限度加一行 `behavior: HitTestBehavior.opaque`，四角立刻可点。

### F-4 ★ 小图标统一包 48 热区（新增 `lib/widgets/hit_target.dart`，老代码不动）

```dart
class HitTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final double minSize;
  final BorderRadius? borderRadius;
  const HitTarget({super.key, required this.child, this.onTap,
      this.onLongPress, this.minSize = 48, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(12);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
      child: Material(color: Colors.transparent, borderRadius: br,
        child: InkWell(onTap: onTap, onLongPress: onLongPress, borderRadius: br,
          child: Center(child: child))));   // Center 保证视觉尺寸不变
  }
}
```

| 靶点 | 贴法 |
|---|---|
| **A1** `main_screen.dart:681`（44×44 → ≥48） | 把 `GestureDetector` 换成 `HitTarget(onTap: _openQuickNoteEditor, onLongPress: _openQuickNotesList, child: /* 原 44×44 Container */)` |
| **A8** `profile_screen.dart:1421/:1499`（48×28） | `SizedBox(height:48) > GestureDetector(behavior: opaque) > Center > Container(width:48,height:28)` |
| **A2** `write_diary_screen.dart:1729-1746`（Chip 高 24） | 删掉 `materialTapTargetSize: shrinkWrap` / `padding: EdgeInsets.zero` / `visualDensity: compact` 三行 ⇒ 恢复 ~48 |
| **A10** `semester_settings_screen.dart:161-167` | 删 `minimumSize: Size.zero` + `tapTargetSize: shrinkWrap` |
| **A11** `:343/:361`（40×40 且 0 间距） | 删 `visualDensity: compact`；并各补 `const SizedBox(width: 4)` 隔离 |

### F-5 `InteractiveButton` 加最小高（一次修 5 处 `padding: zero` 矮按钮）

```dart
// interactive_button.dart:119-158，在 AnimatedBuilder 外再包一层
return ConstrainedBox(
  constraints: BoxConstraints(minHeight: widget.height ?? 48),
  child: GestureDetector(
    onTapDown: _handleTapDown, onTapUp: _handleTapUp, onTapCancel: _handleTapCancel,
    child: AnimatedBuilder(/* 原样 */)));
```
> 默认 `padding v14` + 16 号字 ≈ 46~47dp，**本来就压在 48 线下**；再加 `padding: zero`
> （`stats_screen.dart:797/877/965/1104`、`timeline_screen.dart:621`）掉到 ~42。改组件比改 28 处调用点划算。

### F-6 `RippleButton`：按下只做视觉，动作放到抬手

```dart
// animated_feedback.dart:76-88
return GestureDetector(
  onTapDown: (d) => _addRippleVisual(d.localPosition),  // 仅涟漪 + haptic
  onTapUp: (d) => widget.onTap?.call(),                 // 动作在抬手
  onTapCancel: () {},
  child: Stack(/* 原样 */));
// 同时删掉 _addRipple 内的 widget.onTap!()（:68）
```

### F-7 去掉「假长按」（`main_screen.dart:632-658`）

```dart
child: GestureDetector(
  behavior: HitTestBehavior.translucent,
  onTapDown: (_) { _showNavBar(); _resetInactivityTimer(); },
  onLongPress: _openQuickNoteEditor,                 // 真长按；子按钮先赢 arena，不会误触
  onLongPressStart: (_) => HapticFeedback.heavyImpact(),
  child: ...),
```
并删除 `_longPressTimer`/`_longPressTriggered` 相关 6 处（`:644-656`、`:204`、`:213`）。

### F-8 统一反馈（可选，根治 76 处散落）

```dart
// lib/widgets/tap_feedback.dart —— 复用已有的 AccessibilityHelper.triggerHaptic（accessibility_components.dart:549，全仓 0 调用）
void playTapFeedback({HapticFeedbackType f = HapticFeedbackType.light, bool sound = true}) {
  AccessibilityHelper.triggerHaptic(f);
  if (sound) SoundService.playClick();
}
```
把 `InteractiveButton`/`RippleButton`/`SoundIconButton`/`AccessibleIconButton` 收敛到
`HitTarget + playTapFeedback`，业务层不再直调 `HapticFeedback`。

## 附：优先修复顺序（影响人数 × 危害）

1. **F-2 + F-1**（底部导航：最高频，45% 死区 + 360dp 档 FAB 间距 7.875）
2. **F-3**（FAB 21.5% 四角死区 + 零按下态）
3. **F-7**（按住任意位置 2.1s 弹速记，与 27 处长按冲突）
4. **A1**（速记入口 44×44，全局唯一常驻 <48 按钮）
5. **A11 + 4.3**（两个 compact IconButton 40×40 且 0 间距，右侧是「删除本节」）
6. **A8**（开关 28 高，设置里误点跳过功能）
7. **A2 / A10**（shrinkWrap 塌陷：标签 Chip 与预设按钮）
8. **⑤ 空回调**（`timeline_screen.dart:620`、`stats_screen.dart:1103`：有震动有声音无动作）
9. **F-6**（RippleButton 按下即触发动作，保存类按钮）
10. **F-5**（`InteractiveButton` 默认高度压在 48 线下 + 5 处 `padding: zero`）
