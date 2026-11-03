# 全局帧率与页面切换卡顿：根因与修复

> 用户反馈：「页面切换时出现了很严重的卡顿」「很多画面帧率明显不足，应该说大部分吧」

排查结论：**不是某一个页面慢，而是若干「全局性」问题叠加**，每一个都作用在所有页面上。

---

## 〇、性能排查的前提：先确认运行模式

**debug 版的帧率数据不具参考价值**，用它诊断性能问题会得出大量假阳性结论。

| 差异 | 影响 |
|---|---|
| **JIT 解释执行**（无 AOT 预编译） | 同样的 Dart 代码慢数倍 |
| **全部断言开启**（`assert`） | 每次 build / layout / 手势判定都额外校验 |
| **无 tree-shaking / R8** | 代码与资源未优化 |
| **调试钩子常驻**（堆快照、服务扩展、帧回调统计） | 每帧额外开销 |
| **Impeller/Skia 的调试路径** | 光栅化更慢 |

同一份代码，release 打好包后完全是另一个量级。

本项目 release 确实做了优化（证据：`build/app/outputs/mapping/release/mapping.txt` 34.1 MB，
说明 R8 混淆+收缩真实生效 —— Flutter Gradle 插件自动开启，无需手写 `isMinifyEnabled`）。

**排查原则**：任何帧率/卡顿报告，第一步问「debug 还是 release」，或用 `--profile` 复现。
debug 下能复现的「卡顿」只能作为「值得用 profile 复核」的线索，不能直接当作代码缺陷。
性能改动必须配 `--profile` 实测，不接受纯静态推算。

---

## 一、根因（按影响面排序）

### 根因 1（最大）：四个 tab 全部没有 keep-alive

`main_screen.dart` 用 `PageView(children: _screens)` 承载四个页面，但四个页面
**一个都没有** `AutomaticKeepAliveClientMixin`。

后果：`PageView` 切换时离屏页会被 dispose，切回来重新 `initState`：

| 页面 | `initState` 里做的事 | 切回一次的代价 |
|---|---|---|
| **统计** | `_loadStats()` → 全量遍历日记做聚合（天数/字数/连续打卡/心情分布/天气/标签分布） | **几百毫秒级** |
| **日历** | `_resetToToday()` + `_loadAnniversaries()` + `_loadGoal()` | 3 次 DB/IO + **选中日期被重置**（体验问题） |
| **时间线** | 重建整个列表 + 重播入场动画 + **滚动位置归零** | 整页重建 |
| **我的** | 4 个并发服务调用（徽章/应用锁/生物识别/浮窗），各自 setState | 100KB+ 大页面重建 |

**这是「页面切换卡顿」的直接原因**：每次切 tab 都等于重新进入一次页面。

### 根因 2：`cacheExtent` 被误设成 600

`timeline_screen.dart` 当时的写法是：

```dart
// 注释写着「收紧到一屏以内」
cacheExtent: 600,
```

但 Flutter 默认值是 **250**（`RenderAbstractViewport.defaultCacheExtent`）。
把默认值**扩大了 2.4 倍**，屏幕外预构建区域翻倍，更多带图片的 item 同时构建
→ 帧率反而更差。注释写的是意图，代码做的是反的。

### 根因 3：`ScrollReveal` 稳态残留 `Opacity`

时间线**每一个**列表项都包着 `ScrollReveal`，它内部：

```dart
Opacity(opacity: _opacity.value, ...)
```

即使动画早已播完（value == 1.0），这个 `Opacity` 仍然留在树里。
非 0/1 的 `Opacity` 会走 **saveLayer（离屏合成）**，列表里几十个图层叠加，
滚动时每一帧都要合成这些层。

### 根因 4：底部导航 `BackdropFilter` 全宽常驻实时模糊

`custom_bottom_nav.dart` 用 `ImageFilter.blur(sigmaX: 20, sigmaY: 20)`
做**全宽常驻**的实时高斯模糊。它必须在每帧把背后内容拷进离屏缓冲再模糊，
成本与模糊半径和区域面积成正比，且页面滚动时背后内容一直在变，**每帧重算**。

这一项**没有降级视觉**（sigma 保持 20）：底部导航是全 App 的气质组件，
不在没有实测数据支撑、也未经确认的情况下牺牲视觉效果。
这里只做零成本的优化 —— 用 `RepaintBoundary` 把导航栏独立成图层，
页面滚动时不必连带重绘导航栏。

### 根因 5：`ThemeProvider.theme` 每次访问新建整个 ThemeData

```dart
ThemeData get theme {          // ← 纯计算 getter
  return ThemeData(...);       // ← 每次调用都新建一整套（ColorScheme + TextTheme + 各组件主题）
}
```

而 `main.dart` 里 `Consumer<ThemeProvider>` 包着**整个 `MaterialApp`** ——
任何一次 notifyListeners（主题、字号、`loadSettings` 完成）都会重算 ThemeData
并让**整棵树**重建。

### 根因 6：平台通道调用放在 `build()` 里

```dart
Widget build(...) {
  SystemChrome.setSystemUIOverlayStyle(...);   // ← 每次重建都跨平台往返一次
}
```

MainScreen 的任何 `setState`（导航栏显隐、tab 切换、滚动）都会触发。

---

## 二、修复

| # | 修复 | 位置 |
|---|---|---|
| 1 | 四个 tab 全部加 `AutomaticKeepAliveClientMixin`（**并确保 `build` 里调 `super.build`**，否则不生效） | timeline / calendar / stats / profile |
| 2 | `cacheExtent: 600` → **250**（恢复默认） | `timeline_screen.dart` |
| 3 | `ScrollReveal` 动画完成后**直接返回 child**，把 `Opacity`/`Transform` 从树里摘掉 | `scroll_reveal.dart` |
| 4 | 底部导航外包 `RepaintBoundary` 独立成层（**sigma 保持 20，不降级视觉**） | `custom_bottom_nav.dart` |
| 5 | `ThemeProvider.theme` 按「方案 + 字号」**缓存**，同输入返回同一实例 | `theme_provider.dart` |
| 6 | `SystemChrome.setSystemUIOverlayStyle` 移出 `build`，仅在背景色变化时调用 | `main_screen.dart` |

### 额外修复：一个同类的「内容看不见」隐患

写回归测试时发现 `ScrollReveal` 有个**危险设计**：

```dart
// 触发动画只依赖 VisibilityDetector 回调
void _onVisibilityChanged(...) { if (visible) _controller.forward(); }
```

一旦 VisibilityDetector 因任何原因没回调（布局时机、父级裁剪、极端滚动状态），
`_controller` 永远停在 0.0，而 `Opacity(0.0)` 意味着**内容完全不可见且永不出现**。

这与之前「图片不爱显示」是同一类风险：**功能依赖一个可能不触发的回调**。

修复：`initState` 里加帧末兜底 —— 首帧后若还没被触发，就无条件播放一遍。
原则：**宁可不动画，也绝不能看不见。**

---

## 三、验证

| 项目 | 结果 |
|---|---|
| `dart analyze` | **0 error，warning 114（与改动前一致，无新增）** |
| 全量单测 | **224 passed**（新增 4 条） |
| keepAlive 落点 | 4 个页面均有 `wantKeepAlive => true` + `super.build(context)` |
| APK | 构建成功 |

新增 `test/frame_rate_test.dart`：

- `theme` 重复访问必须返回**同一实例**（防退回「每次新建 ThemeData」）
- 换主题后必须产生**新实例**且背景色不同（防缓存永久失效）
- `ScrollReveal` 动画播完后 **不应再有 `Opacity`**（防离屏合成层残留）
- 动画进行中**仍应有过渡**（防为了性能把动画彻底删掉）

---

## 四、需要真机确认的收益

以下是静态推算，需实测确认：

| 指标 | 预期 |
|---|---|
| 切 tab 耗时 | 统计页从「几百毫秒重算」→ **接近瞬时**（复用已构建子树） |
| 列表滚动 jank | 显著下降（少了 cacheExtent 翻倍 + Opacity 层） |
| 底部导航区域 GPU 成本 | 下降（独立图层，不再连带重绘） |
| 主题切换/字号调整 | 不再整树重建（缓存命中） |

**测量方法**：DevTools Performance 面板录制「切 tab → 滚列表」，看
`build`/`raster` 占比与 jank 帧数。可用 `flutter run --profile`。

如果仍有明显卡顿，下一步排查方向：
1. 特殊主题（星空/樱花/海洋/极光/黄金）的**全屏每帧重绘**背景 ——
   这几套主题下 `CustomPaint` 包整棵树 + `shouldRepaint => true`，
   是**默认主题之外**叠加的额外开销。你当前用的是「温馨米」默认主题的话不受影响。
2. 列表项包 `RepaintBoundary`。
3. 图片解码改由 `SchedulerBinding` 分帧调度（避免集中解码）。

---

## 五、仍需在 release 包上实测的问题

这些不是「帧率」问题，而是「特定操作的耗时/体验」问题，
应该在 **release 包**上用 DevTools 逐个测：

1. **统计页切回全量重算**（keepAlive 已缓解，但首次进入仍是全量）
2. **日历切回重置到今天**（keepAlive 已修）
3. **特殊主题（星空/樱花/海洋/极光/黄金）的全屏每帧重绘** ——
   需要单独确认：如果不用这些主题，它不影响你；如果用，它可能是真实开销。
4. `_updateMetadata` 仍是 O(N)（每次写入全量算字数）

---

## 六、两条硬规矩

**其一：改动靠推理，不靠测量；注释写的是意图，代码做的可能是反的。**
具体到 `cacheExtent`：注释写着「收紧到一屏以内」，数值却从 250 改到 600 ——
注释和代码方向相反。所以必须加 `test/frame_rate_test.dart`：
把「预期行为」写成断言，而不是依赖注释承诺。性能类改动尤其需要这种反向验证
（不只是「链路通」，还要验证「没有变得更差」）。

**其二：不因性能推断而牺牲视觉**，除非有实测数据支撑且经确认。
`sigma 20 → 12` 就是反例 —— 用户没有要求降低视觉效果，
而底部导航是全 App 的气质组件。**在错误的测量前提下牺牲视觉，是不可接受的。**
保留的只有 `RepaintBoundary`：它把导航栏独立成图层，
**没有任何视觉代价**，与 blur 半径无关，属于纯收益。
