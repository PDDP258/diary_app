import 'dart:io';

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

  // 缩略图缓存目录
  String? _thumbCacheDir;
  
  // 是否已初始化
  bool _initialized = false;

  // 正在生成的缩略图任务（避免重复生成）
  final Map<String, Future<String?>> _pendingThumbs = {};

  // 预加载队列（限制并发数）
  final List<String> _preloadQueue = [];
  bool _isPreloading = false;
  static const int _maxConcurrentPreloads = 3;

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
      _thumbCacheDir = path.join(tempDir.path, 'image_thumb_cache');
      
      // 确保缩略图目录存在
      final dir = Directory(_thumbCacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
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
    
    // 检查缩略图是否已存在
    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      return thumbPath;
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

  /// 生成缩略图
  Future<String?> _generateThumbnail(String sourcePath, String targetPath, int width, int height) async {
    try {
      final sourceFile = File(sourcePath);
      final bytes = await sourceFile.readAsBytes();
      
      // 在 isolate 中解码和缩放图片
      final thumbBytes = await compute<_ThumbnailParams, Uint8List?>(
        _createThumbnail,
        _ThumbnailParams(bytes: bytes, width: width, height: height),
      );

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
    
    // 添加到队列
    for (final path in paths) {
      if (!_preloadQueue.contains(path)) {
        _preloadQueue.add(path);
      }
    }

    // 限制队列大小
    if (_preloadQueue.length > 100) {
      _preloadQueue.removeRange(0, _preloadQueue.length - 100);
    }

    // 启动预加载
    if (!_isPreloading) {
      _processPreloadQueue(size);
    }
  }

  /// 处理预加载队列
  Future<void> _processPreloadQueue(int size) async {
    if (_isPreloading) return;
    _isPreloading = true;

    while (_preloadQueue.isNotEmpty) {
      // 分批处理，每批最多 _maxConcurrentPreloads 个
      final batch = <String>[];
      for (var i = 0; i < _maxConcurrentPreloads && _preloadQueue.isNotEmpty; i++) {
        batch.add(_preloadQueue.removeAt(0));
      }

      // 并发处理一批
      await Future.wait(
        batch.map((path) => getThumbnailPath(path, width: size, height: size)),
      );

      // 短暂休眠，避免占用过多资源
      await Future.delayed(const Duration(milliseconds: 16));
    }

    _isPreloading = false;
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

  const OptimizedCachedImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.quality = CacheQuality.small,
  });

  @override
  State<OptimizedCachedImage> createState() => _OptimizedCachedImageState();
}

class _OptimizedCachedImageState extends State<OptimizedCachedImage> {
  String? _thumbPath;
  bool _isLoading = true;

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

  Future<void> _loadThumbnail() async {
    if (kIsWeb) {
      setState(() => _isLoading = false);
      return;
    }

    // 首先检查原文件是否存在
    final originalFile = File(widget.path);
    if (!await originalFile.exists()) {
      if (mounted) {
        setState(() {
          _thumbPath = null; // 文件不存在，将显示占位图
          _isLoading = false;
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
          widget.path,
          width: ImageCacheService.thumbnailSmall,
          height: ImageCacheService.thumbnailSmall,
        );
        break;
      case CacheQuality.medium:
        thumbPath = await cacheService.getMediumThumbnailPath(widget.path);
        break;
      case CacheQuality.large:
        thumbPath = await cacheService.getLargeThumbnailPath(widget.path);
        break;
      case CacheQuality.xlarge:
        thumbPath = await cacheService.getXLargeThumbnailPath(widget.path);
        break;
      case CacheQuality.original:
        thumbPath = widget.path;
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
        _thumbPath = thumbPath ?? widget.path;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _thumbPath == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[200],
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // 使用 Image.file 配合 cacheWidth/cacheHeight 让 Flutter 自动管理缓存
    return Image.file(
      File(_thumbPath!),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
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

/// 大图预览 Widget - 直接使用原图
class OriginalImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  const OriginalImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
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
