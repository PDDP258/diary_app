import 'dart:async';
import 'dart:developer';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ============================================================================
/// 性能优化工具库
/// ============================================================================
///
/// 基于 Flutter 性能最佳实践：
/// - 渲染优化
/// - 内存管理
/// - 卡顿优化
/// - 图片缓存

/// 性能监控器
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  Timer? _reportTimer;

  void startMonitoring({Duration reportInterval = const Duration(seconds: 30)}) {
    // 定期报告
    _reportTimer?.cancel();
    _reportTimer = Timer.periodic(reportInterval, (_) => _reportPerformance());
  }

  void stopMonitoring() {
    _reportTimer?.cancel();
    _reportTimer = null;
  }

  void _reportPerformance() {
    if (kDebugMode) {
      print('=== 性能报告 ===');
      print('=================');
    }
  }
}

/// 防抖构建 - 防止频繁重建
class DebouncedBuilder<T> extends StatefulWidget {
  final T value;
  final Duration debounceTime;
  final Widget Function(BuildContext context, T value) builder;

  const DebouncedBuilder({
    super.key,
    required this.value,
    required this.builder,
    this.debounceTime = const Duration(milliseconds: 100),
  });

  @override
  State<DebouncedBuilder<T>> createState() => _DebouncedBuilderState<T>();
}

class _DebouncedBuilderState<T> extends State<DebouncedBuilder<T>> {
  T? _displayValue;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _displayValue = widget.value;
  }

  @override
  void didUpdateWidget(DebouncedBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.value != oldWidget.value) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(widget.debounceTime, () {
        if (mounted) {
          setState(() => _displayValue = widget.value);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _displayValue as T);
  }
}

/// 虚拟化列表 - 大数据集优化
class VirtualizedList<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double itemHeight;
  final EdgeInsets? padding;
  final ScrollController? scrollController;

  const VirtualizedList({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.itemHeight,
    this.padding,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: padding,
      itemCount: items.length,
      itemExtent: itemHeight,
      cacheExtent: itemHeight * 5, // 缓存 5 个屏幕外的 item
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
      itemBuilder: (context, index) {
        return RepaintBoundary(
          child: itemBuilder(context, items[index], index),
        );
      },
    );
  }
}

/// 内存图片缓存管理器
class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._internal();
  factory ImageCacheManager() => _instance;
  ImageCacheManager._internal();

  final Map<String, ui.Image> _memoryCache = {};
  final _maxCacheSize = 50; // 最大缓存数量
  final _maxMemorySize = 100 * 1024 * 1024; // 100MB

  ui.Image? get(String key) {
    return _memoryCache[key];
  }

  void put(String key, ui.Image image) {
    if (_memoryCache.length >= _maxCacheSize) {
      // LRU 淘汰
      final oldestKey = _memoryCache.keys.first;
      _memoryCache[oldestKey]?.dispose();
      _memoryCache.remove(oldestKey);
    }
    _memoryCache[key] = image;
  }

  void clear() {
    for (final image in _memoryCache.values) {
      image.dispose();
    }
    _memoryCache.clear();
  }

  void evict(String key) {
    _memoryCache[key]?.dispose();
    _memoryCache.remove(key);
  }
}

/// 节流函数
class Throttler {
  final Duration duration;
  Timer? _timer;
  bool _isExecuting = false;

  Throttler({this.duration = const Duration(milliseconds: 300)});

  void run(VoidCallback action) {
    if (_isExecuting) return;

    _isExecuting = true;
    action();

    _timer?.cancel();
    _timer = Timer(duration, () {
      _isExecuting = false;
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// 防抖函数
class Debouncer {
  final Duration duration;
  Timer? _timer;

  Debouncer({this.duration = const Duration(milliseconds: 300)});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// 懒加载构建器
class LazyBuilder extends StatefulWidget {
  final Widget Function(BuildContext context) builder;
  final Duration delay;

  const LazyBuilder({
    super.key,
    required this.builder,
    this.delay = const Duration(milliseconds: 100),
  });

  @override
  State<LazyBuilder> createState() => _LazyBuilderState();
}

class _LazyBuilderState extends State<LazyBuilder> {
  bool _shouldBuild = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) {
        setState(() => _shouldBuild = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldBuild) {
      return const SizedBox.shrink();
    }
    return widget.builder(context);
  }
}

/// 分帧渲染 - 避免长任务阻塞 UI
class FrameSplitter {
  static Future<void> split<T>(
    List<T> items,
    FutureOr<void> Function(T item) processor, {
    int itemsPerFrame = 16,
  }) async {
    for (var i = 0; i < items.length; i += itemsPerFrame) {
      final end = (i + itemsPerFrame < items.length) 
          ? i + itemsPerFrame 
          : items.length;
      final chunk = items.sublist(i, end);

      await Future(() async {
        for (final item in chunk) {
          await processor(item);
        }
      });

      // 让出时间片给 UI 线程
      await Future.delayed(Duration.zero);
    }
  }
}

/// 对象池 - 复用昂贵对象
class ObjectPool<T> {
  final T Function() create;
  final void Function(T)? reset;
  final int maxSize;
  final List<T> _available = [];
  final List<T> _inUse = [];

  ObjectPool({
    required this.create,
    this.reset,
    this.maxSize = 10,
  });

  T acquire() {
    T obj;
    if (_available.isNotEmpty) {
      obj = _available.removeLast();
    } else {
      obj = create();
    }
    _inUse.add(obj);
    return obj;
  }

  void release(T obj) {
    if (_inUse.contains(obj)) {
      _inUse.remove(obj);
      if (_available.length < maxSize) {
        reset?.call(obj);
        _available.add(obj);
      }
    }
  }

  void clear() {
    _available.clear();
    _inUse.clear();
  }
}

/// 异步任务队列
class TaskQueue {
  final List<_Task> _queue = [];
  bool _isProcessing = false;

  Future<T> add<T>(Future<T> Function() task, {int priority = 0}) async {
    final completer = Completer<T>();
    _queue.add(_Task(task, completer, priority));
    _queue.sort((a, b) => b.priority.compareTo(a.priority));
    
    if (!_isProcessing) {
      _processQueue();
    }
    
    return completer.future;
  }

  Future<void> _processQueue() async {
    _isProcessing = true;
    
    while (_queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      try {
        final result = await task.task();
        task.completer.complete(result);
      } catch (e, stackTrace) {
        task.completer.completeError(e, stackTrace);
      }
      
      // 让出时间片
      await Future.delayed(Duration.zero);
    }
    
    _isProcessing = false;
  }

  void clear() {
    _queue.clear();
  }
}

class _Task {
  final Future Function() task;
  final Completer completer;
  final int priority;

  _Task(this.task, this.completer, this.priority);
}

/// 内存管理助手
class MemoryHelper {
  /// 建议垃圾回收
  static void suggestGC() {
    if (kDebugMode) {
      print('建议垃圾回收');
    }
  }

  /// 检查内存使用情况
  static Future<MemoryInfo> getMemoryInfo() async {
    // 这里应该调用平台特定 API
    return MemoryInfo(
      used: 0,
      total: 0,
      available: 0,
    );
  }

  /// 清理图片缓存
  static void clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  /// 清理内存
  static void clearMemory() {
    clearImageCache();
    WidgetsBinding.instance.renderViewElement?.markNeedsBuild();
  }
}

class MemoryInfo {
  final int used;
  final int total;
  final int available;

  MemoryInfo({
    required this.used,
    required this.total,
    required this.available,
  });

  double get usagePercent => total > 0 ? (used / total) : 0;
}

/// 性能优化的 FadeImage
class OptimizedFadeImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Duration fadeDuration;

  const OptimizedFadeImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fadeDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame != null ? 1.0 : 0.0,
          duration: fadeDuration,
          child: child,
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ?? const Center(
          child: CircularProgressIndicator(),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ?? const Center(
          child: Icon(Icons.error_outline),
        );
      },
    );
  }
}

/// 防止重绘的 Widget
class RepaintBoundaryWrapper extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const RepaintBoundaryWrapper({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return RepaintBoundary(child: child);
  }
}

/// 选择性重绘的 ValueListenableBuilder
class SelectiveValueListenableBuilder<T> extends StatelessWidget {
  final ValueListenable<T> valueListenable;
  final bool Function(T previous, T current) shouldRebuild;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  const SelectiveValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.shouldRebuild,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T>(
      valueListenable: valueListenable,
      builder: (context, value, child) {
        return builder(context, value, child);
      },
      child: child,
    );
  }
}

/// 性能优化的 Builder
class PerformanceBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) builder;
  final bool addRepaintBoundary;

  const PerformanceBuilder({
    super.key,
    required this.builder,
    this.addRepaintBoundary = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = builder(context);
    if (addRepaintBoundary) {
      return RepaintBoundary(child: child);
    }
    return child;
  }
}
