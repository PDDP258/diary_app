# 图片加载卡顿：根因与修复（2026-10-28）

> 用户反馈：「修好了，但是加载图片还是会卡卡的」

---

## 一、根因：三个叠加的结构性缺陷

排查后确认不是单一问题，而是三处互相放大的缺陷。

### 缺陷 1（最致命）：`cacheWidth` 是**死参数**

`PlatformImage` 声明了 `cacheWidth` / `cacheHeight`：

```dart
class PlatformImage extends StatelessWidget {
  final int? cacheWidth;
  final int? cacheHeight;
  ...
}
```

但 `build()` 里构造 `OptimizedCachedImage` 时**根本没传**：

```dart
return OptimizedCachedImage(
  path: path,
  width: width,
  height: height,
  fit: fit,
  quality: CacheQuality.small,
  // ← cacheWidth / cacheHeight 在这里被静默丢弃
);
```

更严重的是 `OptimizedCachedImage` 的构造函数**根本没有这两个参数**，它的
`Image.file` 也不设置 `cacheWidth`：

```dart
return Image.file(
  File(_thumbPath!),
  width: widget.width,
  height: widget.height,
  fit: widget.fit,
  gaplessPlayback: true,
  // ← 无 cacheWidth
);
```

**后果**：时间线里 14 处 `PlatformImage` 调用方都老老实实传了
`cacheWidth: 200`，全部无效。列表里显示 100×100 的图，实际按缩略图的
**完整像素**（300×300）解码，多解 9 倍像素；GPU 上传与纹理占用同样放大 9 倍。

> 这是典型的「参数在，但链路断了」——`dart analyze` 不会报错，
> 因为参数确实被声明了，只是没人用。

### 缺陷 2：`File.exists()` 每次 build 都发一次磁盘 IO

```dart
return FutureBuilder<bool>(
  future: File(path).exists(),      // ← 建在 build 里
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return _buildLoadingWidget();  // ← 回到 loading 态
    }
    ...
```

两个问题：
1. **每次 rebuild 都重新发一次磁盘 IO**（列表里有几十个图，滚动时 rebuild 很频繁）；
2. 每次都会先回到 `waiting` 态 → 显示转圈 → 再出图，视觉上是**闪白块**。

而这层检查是**多余的** —— `Image.file` 自带 `errorBuilder`，文件不存在它会自己走错误分支。

### 缺陷 3：缩略图生成会产生全尺寸中间位图

原缩略图生成路径：

```
readAsBytes(原图 3~8 MB)
  → compute isolate
    → img.decodeImage()      ← 解码成 4000×3000 的全尺寸位图 ≈ 36 MB
    → img.copyResize()       ← 再缩放
    → img.encodeJpg()
```

对一张手机原图，**中间那张全尺寸位图约 36 MB**。即使放在 isolate 里，
这也是真实的内存分配。列表滚动时连续触发几张，内存与 GC 压力直接表现为卡顿。

### 缺陷 4：预加载队列与滚动抢 CPU

```dart
// 每批并发 3 个
await Future.wait(batch.map(...));
// 批间只隔 16ms
await Future.delayed(const Duration(milliseconds: 16));
```

每个任务都要读几 MB 原图 + 起 isolate 解码，一批 3 个并列、间隔仅 16ms，
等于**持续不断地**在后台抢 CPU 和 IO。

### 缺陷 5：列表 `cacheExtent` 过大

`ListView.builder` 没设 `cacheExtent`，默认 250px 会预构建屏幕外的 item。
每个 item 都带图片 → 快速滚动时大量图片**同时**进入解码队列。

---

## 二、修复内容

### 2.1 打通 `cacheWidth` 链路（核心）

`OptimizedCachedImage` 新增 `cacheWidth` / `cacheHeight`，并真正传给 `Image.file`：

```dart
final decodeWidth = _resolveDecodeWidth(context);

return Image.file(
  File(_thumbPath!),
  cacheWidth: decodeWidth,      // ← 现在真的生效
  cacheHeight: widget.cacheHeight,
  gaplessPlayback: true,
  ...
);
```

`_resolveDecodeWidth` 策略：优先用显式 `cacheWidth`；否则按
`显示逻辑宽度 × dpr × 1.2` 推算（略微超采样避免边缘发虚），夹紧到 `[32, 2048]`。

`PlatformImage` 把收到的参数透传下去。

**收益**：列表里的图片解码像素从 300×300 降到约 260×260（100dp@2x），
对更小的格子收益更大；GPU 纹理占用同比下降。

### 2.2 去掉 build 期 IO

```dart
// 改前：FutureBuilder + File.exists()
// 改后：直接渲染，交给 errorBuilder
return OptimizedCachedImage(..., cacheWidth: cacheWidth, ...);
```

消除了每次 rebuild 的磁盘 IO，也消除「闪白块」。

### 2.3 引擎原生降采样（关键优化）

新增首选路径：用 Flutter 引擎的 `instantiateImageCodecWithSize` **在解码阶段降采样**：

```dart
final codec = await ui.instantiateImageCodecWithSize(
  buffer,
  getTargetSize: (intrinsicWidth, intrinsicHeight) {
    // 直接让解码器输出小图，不产生全尺寸中间位图
    ...
  },
);
```

**内存峰值从 36 MB 降到 0.36 MB**（300px 位图）。
取 `rawRgba` 后在 isolate 里编码 JPEG（此时位图已经很小，编码很便宜）。

原 `image` 包路径保留为**兜底**，引擎降采样失败时自动回退。

### 2.4 预加载队流控

- 每批并发 3 个 → **每次只处理 1 个**（避免多张原图同时解码）
- 批间 16ms → **120ms**（给 UI 线程留出喘息）
- 队列上限 100 → **24**（超限丢弃最早的请求，用户大概率已滚过去）
- 单张失败不影响后续

### 2.5 列表 `cacheExtent` 收紧

时间线 `ListView.builder` 显式设 `cacheExtent: 600`，让图片解码与滚动解耦。

### 2.6 loading 态改为静默占位

```dart
// 改前：CircularProgressIndicator（有动画 ticker，几十个同时存在耗性能，视觉上闪雪花点）
// 改后：中性底色块
return Container(color: Colors.grey.withValues(alpha: 0.12));
```

配合 `gaplessPlayback`，图片就绪后直接替换，不白闪。

### 2.7 顺带修掉

时间线里 62px 的头像 `Image.file` 没有 `cacheWidth` → 用户选的高分辨率头像
会被按原图解码。已加 `cacheWidth: 160`。

---

## 三、验证

| 项目 | 结果 |
|---|---|
| `dart analyze` | **0 error，warning 114（与改动前完全一致，无新增）** |
| 全量单测 | **185 passed**（新增 5 条图片相关） |
| APK | 构建成功 |

新增回归测试 `test/image_loading_test.dart`：
- `OptimizedCachedImage` **必须接受** `cacheWidth/cacheHeight`（编译期锁定，防止再变死参数）
- `PlatformImage` 持有并透传这两个参数
- 文件不存在时**首帧不出现转圈**（防止退回「先 loading 再出图」的闪烁）
- 预加载入口对超量输入健壮

---

## 四、仍需真机验证的点

以下收益是静态推算，需要你在真机上确认（DevTools / Memory 面板）：

| 指标 | 改前（推算） | 改后（预期） | 验证方法 |
|---|---|---|---|
| 列表图片单张解码 | 300×300 ≈ 0.36 MB | ≈ 0.27 MB（更小格子差距更大） | DevTools Memory：ImageCache `currentSizeBytes` |
| 缩略图生成峰值 | ≈ 36 MB/张（全尺寸位图） | **≈ 0.36 MB/张** | Memory 面板观察生成瞬间 |
| 滚动掉帧 | 明显 | 应显著改善 | Performance 面板 jank 率 |

**如果滚动仍有轻微卡顿**，下一步可以做的：
1. 把 `cacheExtent` 进一步降到 400 或 0（只留屏幕内）
2. 列表项包 `RepaintBoundary`（避免单个图片刷新带动整项重绘）
3. 首屏只解码前 3~5 张，其余滚动到再加载

---

## 四·补、回归：图片「不爱显示」的原因与修复（2026-10-28 追加）

上一版优化引入了一个**不抛异常**的严重 bug，用户反馈「图片变得不爱显示了」。

### 根因：`bytesOffset` 丢失

```dart
// 我引入的错误写法
final image = img.Image.fromBytes(
  width: p.width,
  height: p.height,
  bytes: p.rgba.buffer,        // ← 整个底层 ByteBuffer
  // bytesOffset 缺省 = 0      // ← bug
  numChannels: 4,
  order: img.ChannelOrder.rgba,
);
```

`image.toByteData()` 返回的 **ByteData 是底层 buffer 的一个视图**，
`offsetInBytes` 通常不为 0。只传 `.buffer` 会让 image 包**从第 0 字节开始读**，
读到错位数据，编码出花屏 / 纯色 / 无效的 JPEG。

**为什么这个 bug 特别恶劣**：

1. **不抛异常** —— 编码「成功」返回了字节，只是内容错；
2. **写进了磁盘缓存** —— `getThumbnailPath` 一看文件存在就直接返回，
   之后**永远命中这张坏图** → 图片再也不显示；
3. 用户看到的是「图片有时能显示、有时完全不显示」，很难归因。

### 修复 1：显式传 offset

```dart
final image = img.Image.fromBytes(
  ...
  bytesOffset: p.rgba.offsetInBytes,   // ← 关键
  ...
);
```

### 修复 2：作废历史坏缓存（**不改这条等于没修**）

```dart
// 缓存目录名带版本号：版本升级 = 换新目录 = 旧缓存自动失效
static const int _thumbCacheVersion = 2;
_thumbCacheDir = path.join(tempDir.path, 'image_thumb_cache_v$_thumbCacheVersion');
// 顺手清掉旧版本目录
```

### 修复 3：坏缓存自愈

读缓存时不再只判断「文件存在」，还校验**大小合理**（< 256 B 视为损坏），
命中坏文件就删掉重建。这样即使将来还有别的编码路径出错，也不会永久卡死。

### 验证方式：用真实像素比对锁死正确性

`test/image_encode_test.dart` 做了三件事：

1. 构造「左半红、右半蓝」的已知位图，套上非零 offset 的视图，
   按**修复后的写法**编码 → 解码 → **逐像素校验左右颜色正确**；
2. 用**错误写法**（缺 `bytesOffset`）跑同样流程，断言**左半区不再纯红**
   —— 这一条**证明了这个 bug 真实存在**，而不是我臆测；
3. 校验正常缩略图大小 > 256 B，确保自愈阈值不会误杀有效缓存。

---

## 五、这次为什么没被 `dart analyze` 抓到

`cacheWidth` 声明了却没用、`_buildLoadingWidget` 这类私有方法没被引用 ——
前者** analyzer 看不出**（参数是合法的公共 API，只是没人消费），
后者只在事后变成 `unused_element` 警告。

**教训**：参数化组件要配「参数真的被消费」的测试。
本次新增的 `image_loading_test.dart` 就是为此 —— 它会在编译期
强制 `OptimizedCachedImage` 保留这两个字段，防止未来被悄悄删掉。
