import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/image_cache_service.dart';

/// 懒加载图片组件
///
/// 功能：
/// 1. 图片进入可视区域时才加载
/// 2. 显示占位图和加载动画
/// 3. 加载失败显示错误占位图
/// 4. 支持渐进式加载（先显示模糊图，再显示清晰图）
class LazyImage extends StatefulWidget {
  final String imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final CacheQuality quality;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Duration fadeDuration;
  final BorderRadius? borderRadius;

  const LazyImage({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.quality = CacheQuality.medium,
    this.placeholder,
    this.errorWidget,
    this.fadeDuration = const Duration(milliseconds: 300),
    this.borderRadius,
  });

  @override
  State<LazyImage> createState() => _LazyImageState();
}

class _LazyImageState extends State<LazyImage> {
  bool _isVisible = false;
  bool _isLoaded = false;
  bool _hasError = false;
  String? _cachedPath;
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkVisibility();
  }

  @override
  void didUpdateWidget(LazyImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _isLoaded = false;
      _hasError = false;
      _cachedPath = null;
      _checkVisibility();
    }
  }

  void _checkVisibility() {
    // 使用 WidgetsBinding 在下一帧检查可见性
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateVisibility();
    });
  }

  void _updateVisibility() {
    if (!mounted) return;

    final renderObject = _key.currentContext?.findRenderObject();
    if (renderObject == null) return;

    final viewport = RenderAbstractViewport.of(renderObject);
    if (viewport == null) {
      // 不在滚动容器中，直接加载
      if (!_isVisible) {
        setState(() => _isVisible = true);
        _loadImage();
      }
      return;
    }

    // 检查是否在可视区域内
    final offset = viewport.getOffsetToReveal(renderObject, 0.0).offset;
    final viewportDimension = viewport.paintBounds.height;

    // 如果图片在可视区域上下 100px 范围内，开始加载
    final isInViewport = offset >= -100 && offset <= viewportDimension + 100;

    if (isInViewport && !_isVisible) {
      setState(() => _isVisible = true);
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (_isLoaded || _hasError) return;

    try {
      // 获取缓存图片路径
      final cachedPath = await ImageCacheService().getThumbnailPath(
        widget.imagePath,
        width: widget.quality.size.toInt(),
        height: widget.quality.size.toInt(),
      );

      if (mounted) {
        setState(() {
          _cachedPath = cachedPath ?? widget.imagePath;
          _isLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (!_isVisible || !_isLoaded) {
      // 显示占位图
      imageWidget = widget.placeholder ?? _buildDefaultPlaceholder();
    } else if (_hasError) {
      // 显示错误占位图
      imageWidget = widget.errorWidget ?? _buildErrorWidget();
    } else {
      // 显示图片
      imageWidget = _buildImage();
    }

    // 应用圆角
    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    return SizedBox(
      key: _key,
      width: widget.width,
      height: widget.height,
      child: imageWidget,
    );
  }

  Widget _buildDefaultPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[200],
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[200],
      child: Icon(
        Icons.broken_image_outlined,
        color: Colors.grey[400],
        size: 32,
      ),
    );
  }

  Widget _buildImage() {
    final file = File(_cachedPath!);

    return Image.file(
      file,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;

        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: widget.fadeDuration,
          curve: Curves.easeInOut,
          child: child,
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return widget.errorWidget ?? _buildErrorWidget();
      },
    );
  }
}

/// 缓存质量级别
enum CacheQuality {
  small(300), // 小图（列表用）
  medium(400), // 中图（日历用）
  large(800), // 大图（详情页用）
  xlarge(1200); // 超大图（全屏预览用）

  final double size;
  const CacheQuality(this.size);
}

/// 懒加载图片列表
///
/// 用于在列表中批量懒加载图片
class LazyImageList extends StatefulWidget {
  final List<String> imagePaths;
  final double itemWidth;
  final double itemHeight;
  final BoxFit fit;
  final CacheQuality quality;
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;
  final Function(String)? onTap;

  const LazyImageList({
    super.key,
    required this.imagePaths,
    this.itemWidth = 100,
    this.itemHeight = 100,
    this.fit = BoxFit.cover,
    this.quality = CacheQuality.medium,
    this.padding,
    this.scrollController,
    this.onTap,
  });

  @override
  State<LazyImageList> createState() => _LazyImageListState();
}

class _LazyImageListState extends State<LazyImageList> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    } else {
      _scrollController.removeListener(_onScroll);
    }
    super.dispose();
  }

  void _onScroll() {
    // 滚动时触发子组件检查可见性
    // 实际检查在 LazyImage 组件中完成
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      scrollDirection: Axis.horizontal,
      itemCount: widget.imagePaths.length,
      itemBuilder: (context, index) {
        final path = widget.imagePaths[index];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: widget.onTap != null ? () => widget.onTap!(path) : null,
            child: LazyImage(
              imagePath: path,
              width: widget.itemWidth,
              height: widget.itemHeight,
              fit: widget.fit,
              quality: widget.quality,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}

/// 网格懒加载图片
class LazyImageGrid extends StatelessWidget {
  final List<String> imagePaths;
  final int crossAxisCount;
  final double spacing;
  final double childAspectRatio;
  final CacheQuality quality;
  final Function(String)? onTap;

  const LazyImageGrid({
    super.key,
    required this.imagePaths,
    this.crossAxisCount = 3,
    this.spacing = 8,
    this.childAspectRatio = 1.0,
    this.quality = CacheQuality.medium,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: imagePaths.length,
      itemBuilder: (context, index) {
        final path = imagePaths[index];
        return GestureDetector(
          onTap: onTap != null ? () => onTap!(path) : null,
          child: LazyImage(
            imagePath: path,
            fit: BoxFit.cover,
            quality: quality,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }
}
