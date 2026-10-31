import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// 图片缓存服务 - 优化版本
/// 
/// 优化策略：
/// 1. 生成缩略图缓存，避免加载大图
/// 2. 使用 Flutter 自带 ImageCache 缓存解码后的图片
/// 3. 异步预加载，不阻塞主线程
/// 4. LRU 内存管理
/// 5. 支持多级别清晰度缓存（小图/中图/大图/原图）
class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  /// 缩略图缓存格式版本。
  ///
  /// ⚠️ **每次改变缩略图生成逻辑都必须 +1**，否则旧版本生成的（可能有问题的）
  /// 缩略图会继续被命中，用户更新后看不到任何变化。
  ///
  /// v2（2026-10-28）：修复 rawRgba→JPEG 的 offset 错误。v1 生成的缩略图
  /// 可能是花屏/无效的，必须整体作废重生成。
  static const int _thumbCacheVersion = 2;

  /// 有效缩略图的最小字节数。
  ///
  /// 一张正常 JPEG 缩略图至少几百字节；低于此值几乎可以断定是
  /// 编码失败留下的空文件或残片。用于自愈坏缓存。
  static const int _minValidThumbBytes = 256;

  // 缩略图缓存目录
  String? _thumbCacheDir;

  // 是否已初始化
  bool _initialized = false;

  // 正在生成的缩略图任务（避免重复生成）
  final Map<String, Future<String?>> _pendingThumbs = {};

  // 预加载队列（限制并发，避免与滚动抢帧）
  final List<String> _preloadQueue = [];
  bool _isPreloading = false;

  /// 预加载队列上限。超过后丢弃最早的请求，避免用户快速滚动时无限堆积。
  static const int _maxPreloadQueue = 24;

  // 缓存尺寸级别定义
  static const int thumbnailSmall = 300;   // 小缩略图（列表用）
  static const int thumbnailMedium = 400;  // 中等缩略图（日历用）
  static const int thumbnailLarge = 800;   // 大缩略图（详情页用）
  static const int thumbnailXLarge = 1200; // 超大缩略图（全屏预览用）

  /// 初始化缓存服务
  Future<void> initialize() async {
    if (_initialized) return;

    if (!kIsWeb) {
      final tempDir = await getTemporaryDirectory();
      // 目录名带版本号：版本升级 = 换新目录 = 旧缓存自动失效。
      // 这比「删旧文件」更安全（不碰用户其它数据），也天然幂等。
      _thumbCacheDir = path.join(
          tempDir.path, 'image_thumb_cache_v$_thumbCacheVersion');

      // 确保缩略图目录存在
      final dir = Directory(_thumbCacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 顺手清掉旧版本目录，避免占空间
      try {
        final legacy = Directory(path.join(tempDir.path, 'image_thumb_cache'));
        if (await legacy.exists()) {
          await legacy.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('清理旧缩略图目录失败: $e');
      }

      // 清理过期缓存（超过7天的缩略图）
      _cleanOldCache(dir, days: 7);
    }

    _initialized = true;
  }

  /// 获取缩略图路径（如果不存在则生成）
  /// 
  /// [width] 和 [height] 指定缩略图尺寸，默认为 300x300
  /// 支持的预设尺寸：
  /// - thumbnailSmall (300): 小缩略图，用于列表
  /// - thumbnailMedium (400): 中等缩略图，用于日历单元格
  /// - thumbnailLarge (800): 大缩略图，用于详情页
  /// - thumbnailXLarge (1200): 超大缩略图，用于全屏预览
  Future<String?> getThumbnailPath(String originalPath, {int width = 300, int height = 300}) async {
    if (kIsWeb) return originalPath;
    
    await initialize();
    
    final file = File(originalPath);
    if (!await file.exists()) return null;

    // 生成缩略图缓存键（使用标准化尺寸，避免重复生成相近尺寸）
    final normalizedSize = _normalizeSize(width);
    final thumbKey = '${originalPath}_${normalizedSize}x$normalizedSize';
    final cacheKey = '${thumbKey.hashCode}.jpg';
    final thumbPath = path.join(_thumbCacheDir!, cacheKey);
    
    // 检查缩略图是否已存在。
    //
    // ⚠️ 2026-10-28：不仅检查「存在」，还检查「大小合理」。
    // 曾经的 bug 会生成无效/极小的坏 JPEG 并被缓存，之后只要文件存在
    // 就一直返回它 → 图片永远不显示。这里加一道廉价的大小校验：
    // 正常的缩略图不可能小于 [_minValidThumbBytes]。
    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      final len = await thumbFile.length();
      if (len >= _minValidThumbBytes) {
        return thumbPath;
      }
      // 太小 → 视为坏缓存，删掉重新生成
      debugPrint('发现无效缩略图缓存（$len B），删除重建: $cacheKey');
      try {
        await thumbFile.delete();
      } catch (_) {}
    }

    // 避免重复生成同一个缩略图
    if (_pendingThumbs.containsKey(thumbKey)) {
      return _pendingThumbs[thumbKey];
    }

    // 创建缩略图生成任务
    final future = _generateThumbnail(originalPath, thumbPath, normalizedSize, normalizedSize);
    _pendingThumbs[thumbKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingThumbs.remove(thumbKey);
    }
  }

  /// 标准化尺寸到预设级别，减少缓存碎片
  int _normalizeSize(int size) {
    if (size <= thumbnailSmall) return thumbnailSmall;
    if (size <= thumbnailMedium) return thumbnailMedium;
    if (size <= thumbnailLarge) return thumbnailLarge;
    if (size <= thumbnailXLarge) return thumbnailXLarge;
    return size;
  }

  /// 获取中等清晰度缩略图（日历用，400x400）
  Future<String?> getMediumThumbnailPath(String originalPath) {
    return getThumbnailPath(originalPath, width: thumbnailMedium, height: thumbnailMedium);
  }

  /// 获取高清缩略图（详情页用，800x800）
  Future<String?> getLargeThumbnailPath(String originalPath) {
    return getThumbnailPath(originalPath, width: thumbnailLarge, height: thumbnailLarge);
  }

  /// 获取超高清晰缩略图（全屏预览用，1200x1200）
  Future<String?> getXLargeThumbnailPath(String originalPath) {
    return getThumbnailPath(originalPath, width: thumbnailXLarge, height: thumbnailXLarge);
  }

  /// 生成缩略图。
  ///
  /// ⚠️ 2026-10-28 优化（图片加载卡顿）：
  ///
  /// 原路径是 `readAsBytes(原图几 MB)` → `compute` → `img.decodeImage`
  /// 全量解码到 RGB 位图 → `copyResize` → `encodeJpg`。
  ///
  /// 对一张 4000×3000 的手机原图，中间那张**全尺寸位图约 36 MB**，
  /// 即使放在 isolate 里也要真实分配；滚动列表时连续触发几张，
  /// 内存与 GC 压力直接表现为卡顿。
  ///
  /// 改进：优先用 Flutter 引擎的 `instantiateImageCodec`
  /// （**原生解码器支持 targetWidth，直接在解码阶段降采样**，
  /// 不会产生全尺寸中间位图），失败再回退到 `image` 包路径。
  Future<String?> _generateThumbnail(String sourcePath, String targetPath, int width, int height) async {
    try {
      Uint8List? thumbBytes;

      // 路径 A（首选）：引擎原生降采样解码 —— 不产生全尺寸位图
      try {
        thumbBytes = await _decodeScaledBytes(sourcePath, width);
      } catch (e) {
        debugPrint('引擎降采样失败，回退 image 包: $e');
      }

      // 路径 B（兜底）：老的 isolate + image 包
      thumbBytes ??= await _generateThumbnailWithImagePackage(
          sourcePath, width, height);

      if (thumbBytes == null) return null;

      // 保存缩略图
      final thumbFile = File(targetPath);
      await thumbFile.writeAsBytes(thumbBytes);

      return targetPath;
    } catch (e) {
      debugPrint('生成缩略图失败: $sourcePath, 错误: $e');
      return null;
    }
  }

  /// 用引擎的 `instantiateImageCodec` 按目标宽度解码，再编码成 JPEG。
  ///
  /// 关键优势：`getTargetSize` 让**解码器直接输出小图**，
  /// 内存峰值只有目标尺寸那么大（300px ≈ 0.36 MB），
  /// 而不是原图全尺寸位图（4000×3000 ≈ 36 MB）。
  ///
  /// ⚠️ 2026-10-28 修复（「图片变得不爱显示了」）：
  /// 这里曾经把 `byteData.buffer` 直接传给 isolate，**丢掉了 offsetInBytes**。
  /// `toByteData` 返回的 ByteData 是底层 buffer 的一个**视图**，
  /// offset 通常不为 0；只传 `buffer` 会让 isolate 从错误位置开始读，
  /// 编码出**错位/花屏/无效的 JPEG**，而这个坏文件会被写入缩略图缓存，
  /// 之后永远命中坏缓存 → 图片再也不显示。
  ///
  /// 现在显式用 `asUint8List(offset, length)` 取出正确切片。
  Future<Uint8List?> _decodeScaledBytes(String sourcePath, int targetWidth) async {
    final bytes = await File(sourcePath).readAsBytes();

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    late final ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
          if (intrinsicWidth <= targetWidth) {
            // 本来就比目标小，不放大
            return ui.TargetImageSize(
                width: intrinsicWidth, height: intrinsicHeight);
          }
          final scale = targetWidth / intrinsicWidth;
          return ui.TargetImageSize(
            width: targetWidth,
            height: (intrinsicHeight * scale).round(),
          );
        },
      );
    } finally {
      // buffer 交给 codec 后仍需在 codec 释放后释放；这里仅确保异常时释放
    }

    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      // ✅ 关键：按 offset/length 取**正确的切片**，不能只传 buffer
      final rgba = Uint8List.sublistView(byteData);

      // 此时位图已经是降采样后的小图，编码成本低
      return compute<_EncodeJpegParams, Uint8List?>(
        _encodeRawRgbaToJpeg,
        _EncodeJpegParams(
          rgba: rgba,
          width: image.width,
          height: image.height,
        ),
      );
    } finally {
      image.dispose();
      codec.dispose();
      buffer.dispose();
    }
  }

  /// 回退路径：isolate + image 包做解码/缩放/编码。
  Future<Uint8List?> _generateThumbnailWithImagePackage(
      String sourcePath, int width, int height) async {
    final bytes = await File(sourcePath).readAsBytes();
    return compute<_ThumbnailParams, Uint8List?>(
      _createThumbnail,
      _ThumbnailParams(bytes: bytes, width: width, height: height),
    );
  }

  /// 清理过期缓存
  void _cleanOldCache(Directory dir, {required int days}) async {
    try {
      final now = DateTime.now();
      final cutoff = now.subtract(Duration(days: days));
      
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
            }
          } catch (e) {
            // 忽略单个文件清理错误
          }
        }
      }
    } catch (e) {
      debugPrint('清理缓存失败: $e');
    }
  }

  /// 预加载图片（异步队列，不阻塞）
  /// 
  /// [quality] 指定预加载的清晰度级别：
  /// - 'small': 300x300
  /// - 'medium': 400x400
  /// - 'large': 800x800
  /// - 'xlarge': 1200x1200
  void preloadImages(List<String> paths, {String quality = 'small'}) {
    if (kIsWeb) return;
    
    // 根据质量级别确定尺寸
    int size;
    switch (quality) {
      case 'medium':
        size = thumbnailMedium;
        break;
      case 'large':
        size = thumbnailLarge;
        break;
      case 'xlarge':
        size = thumbnailXLarge;
        break;
      case 'small':
      default:
        size = thumbnailSmall;
        break;
    }
    
    // 添加到队列（用 Set 语义去重：List.contains 在队列较长时是 O(n)）
    final existing = _preloadQueue.toSet();
    for (final path in paths) {
      if (!existing.contains(path) && !_preloadQueue.contains(path)) {
        _preloadQueue.add(path);
      }
    }

    // 限制队列大小：超限时丢弃**最早**的请求（用户大概率已经滚过去了）
    if (_preloadQueue.length > _maxPreloadQueue) {
      _preloadQueue.removeRange(0, _preloadQueue.length - _maxPreloadQueue);
    }

    // 启动预加载
    if (!_isPreloading) {
      _processPreloadQueue(size);
    }
  }

  /// 处理预加载队列
  ///
  /// ⚠️ 2026-10-28 修复（图片加载卡顿）：
  ///
  /// 原实现每批并发 3 个，批间只 `delay(16ms)`。
  /// 问题在于每个 `getThumbnailPath` 内部都要
  /// `readAsBytes` 原图（几 MB）+ `compute` 起 isolate 解码重编码 ——
  /// 一批 3 个并列，加上仅 16ms 的间隔，等于**持续不断地**在后台
  /// 抢 CPU 与 IO，用户滚动列表时直接表现为掉帧。
  ///
  /// 现在：
  ///  1. 每次只处理**一个**任务，避免多张原图同时在内存里解码；
  ///  2. 每张之间拉长间隔到 [preloadBatchDelayMs]，给 UI 线程留出喘息；
  ///  3. 队列长度有上限（见 [preloadImages]），不会无限堆积。
  static const int preloadBatchDelayMs = 120;

  Future<void> _processPreloadQueue(int size) async {
    if (_isPreloading) return;
    _isPreloading = true;

    try {
      while (_preloadQueue.isNotEmpty) {
        final path = _preloadQueue.removeAt(0);

        try {
          await getThumbnailPath(path, width: size, height: size);
        } catch (e) {
          // 单张失败不影响后续
          debugPrint('预加载缩略图失败: $path, $e');
        }

        // 每处理一张就主动让出，避免与滚动渲染抢帧
        await Future.delayed(const Duration(milliseconds: preloadBatchDelayMs));
      }
    } finally {
      _isPreloading = false;
    }
  }

  /// 清除所有缩略图缓存
  Future<void> clearThumbnailCache() async {
    if (_thumbCacheDir == null) return;
    
    try {
      final dir = Directory(_thumbCacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('清除缓存失败: $e');
    }
  }

  /// 获取缓存状态
  Future<Map<String, dynamic>> getCacheStatus() async {
    int fileCount = 0;
    int totalSize = 0;

    if (_thumbCacheDir != null) {
      try {
        final dir = Directory(_thumbCacheDir!);
        if (await dir.exists()) {
          await for (final entity in dir.list()) {
            if (entity is File) {
              fileCount++;
              totalSize += await entity.length();
            }
          }
        }
      } catch (e) {
        // 忽略错误
      }
    }

    return {
      'thumbnailCount': fileCount,
      'cacheSizeMB': (totalSize / 1024 / 1024).toStringAsFixed(2),
      'pendingThumbs': _pendingThumbs.length,
      'preloadQueue': _preloadQueue.length,
    };
  }
}

/// 缩略图生成参数
class _ThumbnailParams {
  final Uint8List bytes;
  final int width;
  final int height;

  _ThumbnailParams({required this.bytes, required this.width, required this.height});
}

/// rawRgba 编码参数
class _EncodeJpegParams {
  final Uint8List rgba;
  final int width;
  final int height;

  _EncodeJpegParams({
    required this.rgba,
    required this.width,
    required this.height,
  });
}

/// 把 rawRgba 位图编码成 JPEG（在 isolate 中执行，避免阻塞 UI）。
Uint8List? _encodeRawRgbaToJpeg(_EncodeJpegParams p) {
  try {
    // ⚠️ 2026-10-28 关键修复（「图片变得不爱显示了」的真正原因）：
    //
    // `p.rgba` 是 `toByteData()` 返回 ByteData 的**视图**，
    // 它的 `offsetInBytes` 通常不为 0（指向底层 buffer 中段的某个位置）。
    // 而 `Image.fromBytes(bytes: ...)` 接收的是**整个 ByteBuffer**，
    // 若只传 `p.rgba.buffer` 而不传 `bytesOffset`，image 包会从
    // buffer 的第 0 字节开始读 —— 读到的是错位的数据，
    // 编码结果是花屏 / 纯色 / 无效 JPEG。
    //
    // 更糟的是这个坏文件会被写进缩略图磁盘缓存，此后
    // `getThumbnailPath` 一看到文件存在就直接返回 → **图片永久不显示**。
    //
    // 修复：显式把 offset 传给 image 包。
    final image = img.Image.fromBytes(
      width: p.width,
      height: p.height,
      bytes: p.rgba.buffer,
      bytesOffset: p.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(image, quality: 88));
  } catch (e) {
    debugPrint('rawRgba → JPEG 编码失败: $e');
    return null;
  }
}

/// 在 isolate 中生成缩略图
Uint8List? _createThumbnail(_ThumbnailParams params) {
  try {
    // 解码图片
    final original = img.decodeImage(params.bytes);
    if (original == null) return null;

    // 计算保持宽高比的缩略图尺寸
    final aspectRatio = original.width / original.height;
    int targetWidth = params.width;
    int targetHeight = params.height;

    if (aspectRatio > 1) {
      targetHeight = (targetWidth / aspectRatio).round();
    } else {
      targetWidth = (targetHeight * aspectRatio).round();
    }

    // 如果图片已经很小，直接返回原图
    if (original.width <= targetWidth && original.height <= targetHeight) {
      return params.bytes;
    }

    // 根据目标尺寸选择插值算法
    // 小图使用 cubic 获得更好质量，大图使用 linear 平衡速度
    final interpolation = params.width <= 400 
        ? img.Interpolation.cubic 
        : img.Interpolation.linear;

    // 缩放图片
    final resized = img.copyResize(
      original,
      width: targetWidth,
      height: targetHeight,
      interpolation: interpolation,
    );

    // 根据尺寸调整 JPEG 质量
    // 小图使用更高质量，大图使用标准质量以控制文件大小
    final quality = params.width <= 400 ? 90 : 85;
    
    // 编码为 JPEG
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (e) {
    return null;
  }
}

/// 缓存质量级别
enum CacheQuality {
  /// 小缩略图 (300x300) - 用于列表
  small,
  /// 中等缩略图 (400x400) - 用于日历
  medium,
  /// 大缩略图 (800x800) - 用于详情页
  large,
  /// 超大缩略图 (1200x1200) - 用于全屏预览
  xlarge,
  /// 原图 - 用于原图查看
  original,
}

/// 优化的缓存图片 Widget - 使用缩略图
class OptimizedCachedImage extends StatefulWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final CacheQuality quality;

  /// 解码目标宽度（物理像素）。
  ///
  /// ⚠️ 2026-10-28 修复（图片加载卡顿）：这两个参数以前**不存在**，
  /// 于是调用方传进来的 `cacheWidth: 200` 无处可去（在
  /// `PlatformImage` 里被静默丢弃），最终 `Image.file` 按缩略图实际
  /// 像素解码。虽然缩略图本身已是 300px，但列表里显示尺寸只有 100×100，
  /// 300px 解码 + GPU 上传依然比需要的多 9 倍像素。
  ///
  /// 传了就按它降采样解码；不传则使用 [width] × dpr 自动推算。
  final int? cacheWidth;
  final int? cacheHeight;

  const OptimizedCachedImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.quality = CacheQuality.small,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  State<OptimizedCachedImage> createState() => _OptimizedCachedImageState();
}

class _OptimizedCachedImageState extends State<OptimizedCachedImage> {
  String? _thumbPath;
  bool _isLoading = true;

  /// 记录上一次成功解析的 path，避免重复 IO。
  String? _resolvedForPath;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(OptimizedCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.quality != widget.quality) {
      _loadThumbnail();
    }
  }

  /// 计算解码尺寸。
  ///
  /// 优先用显式 [OptimizedCachedImage.cacheWidth]；否则按显示尺寸 × dpr，
  /// 保证「解码像素 ≈ 显示像素」，不浪费内存与 GPU 带宽。
  int? _resolveDecodeWidth(BuildContext context) {
    final explicit = widget.cacheWidth;
    if (explicit != null && explicit > 0) return explicit;

    final media = MediaQuery.maybeOf(context);
    final dpr = media?.devicePixelRatio ?? 1.0;
    final logical = widget.width;
    if (logical == null || logical <= 0) return null;
    // 略微超采样（1.2×）避免边缘发虚
    return (logical * dpr * 1.2).round().clamp(32, 2048);
  }

  Future<void> _loadThumbnail() async {
    if (kIsWeb) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 同一 path 已解析成功 → 不重复做 IO
    if (_resolvedForPath == widget.path && _thumbPath != null) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    final path = widget.path;

    // 首先检查原文件是否存在
    final originalFile = File(path);
    if (!await originalFile.exists()) {
      if (mounted) {
        setState(() {
          _thumbPath = null; // 文件不存在，将显示占位图
          _isLoading = false;
          _resolvedForPath = path;
        });
      }
      return;
    }

    // 根据质量级别获取对应尺寸的缩略图
    String? thumbPath;
    final cacheService = ImageCacheService();

    switch (widget.quality) {
      case CacheQuality.small:
        thumbPath = await cacheService.getThumbnailPath(
          path,
          width: ImageCacheService.thumbnailSmall,
          height: ImageCacheService.thumbnailSmall,
        );
        break;
      case CacheQuality.medium:
        thumbPath = await cacheService.getMediumThumbnailPath(path);
        break;
      case CacheQuality.large:
        thumbPath = await cacheService.getLargeThumbnailPath(path);
        break;
      case CacheQuality.xlarge:
        thumbPath = await cacheService.getXLargeThumbnailPath(path);
        break;
      case CacheQuality.original:
        thumbPath = path;
        break;
    }

    // 验证缩略图路径是否有效
    if (thumbPath != null) {
      final thumbFile = File(thumbPath);
      if (!await thumbFile.exists()) {
        thumbPath = null;
      }
    }

    if (mounted) {
      setState(() {
        _thumbPath = thumbPath ?? path;
        _isLoading = false;
        _resolvedForPath = path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _thumbPath == null) {
      // ⚠️ 2026-10-28：这里不再显示 CircularProgressIndicator。
      //
      // 列表滚动时每个图片格子都会先经历一帧「loading」——
      // 转圈组件本身有动画 ticker，几十个同时存在既耗性能，
      // 视觉上也是「一闪一闪」的雪花点，比静默占位更难受。
      //
      // 改为中性底色块（与卡片背景同色系），图片就绪后直接替换，
      // 配合 gaplessPlayback 不会出现白闪。
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey.withValues(alpha: 0.12),
      );
    }

    // 关键修复：把 cacheWidth/cacheHeight 真正交给 Image.file，
    // 让解码尺寸贴合实际显示尺寸（列表里 100×100 只需解 ~260px 而非缩略图全尺寸）。
    final decodeWidth = _resolveDecodeWidth(context);

    return Image.file(
      File(_thumbPath!),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: decodeWidth,
      cacheHeight: widget.cacheHeight,
      // gaplessPlayback 保持同一 widget 换图时不闪白
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      },
    );
  }
}

/// 大图预览 Widget — 按屏幕尺寸降采样解码
///
/// ⚠️ **不要去掉 cacheWidth**：`Image.file` 不传 cacheWidth 时会按**原始像素**解码。
/// 一张 4000×3000 的手机原图解码后是 12M 像素 × 4 字节 ≈ **48 MB**，而
/// 全屏查看器是 `PageView` + `InteractiveViewer`，相邻页会预加载 →
/// 滑 2~3 张就 >120 MB，低端机直接 OOM（这是「频繁闪退」的一条主要路径）。
///
/// 默认按「屏幕物理宽度 × 1.5」解码：既足够清晰，又给 `InteractiveViewer`
/// 的 4 倍缩放留了余量（1080 宽设备约解码 1800px ≈ 9.7 MB，降幅约 80%）。
class OriginalImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// 解码宽度（物理像素）。不传则按屏幕宽度 × [zoomHeadroom] 自动计算。
  final int? cacheWidth;

  /// 缩放余量：全屏看图允许放大，留一些分辨率；纯展示场景可传 1.0。
  final double zoomHeadroom;

  const OriginalImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.zoomHeadroom = 1.5,
  });

  /// 计算降采样宽度：优先用显式 width，否则用屏幕宽度，再乘 dpr 与缩放余量。
  int _resolveCacheWidth(BuildContext context) {
    final explicit = cacheWidth;
    if (explicit != null && explicit > 0) return explicit;

    final media = MediaQuery.maybeOf(context);
    final dpr = media?.devicePixelRatio ?? 1.0;
    // 显式给了逻辑宽度就用它，否则按屏幕宽度
    final logicalWidth = width ?? media?.size.width;
    if (logicalWidth == null || logicalWidth <= 0) {
      // 拿不到尺寸时保守给一个上限，避免退化成原图解码
      return 1600;
    }
    final physical = (logicalWidth * dpr * zoomHeadroom).round();
    // 夹紧到合理区间：太小会糊，太大就失去降采样的意义
    return physical.clamp(600, 2400);
  }

  @override
  Widget build(BuildContext context) {
    final decodeWidth = _resolveCacheWidth(context);

    if (kIsWeb) {
      return Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image, color: Colors.grey),
          );
        },
      );
    }

    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      cacheWidth: decodeWidth,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      },
    );
  }
}

/// 日历图片组件 - 使用中等清晰度（400x400）
class CalendarImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  const CalendarImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return OptimizedCachedImage(
      path: path,
      width: width,
      height: height,
      fit: fit,
      quality: CacheQuality.medium,
    );
  }
}

/// 详情页图片组件 - 使用高清（800x800）
class DetailImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  const DetailImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return OptimizedCachedImage(
      path: path,
      width: width,
      height: height,
      fit: fit,
      quality: CacheQuality.large,
    );
  }
}

/// 全屏预览图片组件 - 使用超高清（1200x1200）或原图
class PreviewImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool useOriginal;

  const PreviewImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.useOriginal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (useOriginal) {
      return OriginalImage(
        path: path,
        width: width,
        height: height,
        fit: fit,
      );
    }
    
    return OptimizedCachedImage(
      path: path,
      width: width,
      height: height,
      fit: fit,
      quality: CacheQuality.xlarge,
    );
  }
}
