import 'dart:math';
import 'package:flutter/material.dart';

/// 简化版翻页效果组件 - 用于开场动画
/// 采用简单的向左滑行 + 透视效果，更自然
class SplashPageTurn extends StatefulWidget {
  final List<Widget> pages;
  final int initialPage;
  final VoidCallback? onComplete;
  final Duration delayBeforeStart;
  final Duration flipDuration;

  const SplashPageTurn({
    super.key,
    required this.pages,
    this.initialPage = 0,
    this.onComplete,
    this.delayBeforeStart = const Duration(seconds: 2),
    this.flipDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<SplashPageTurn> createState() => _SplashPageTurnState();
}

class _SplashPageTurnState extends State<SplashPageTurn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.flipDuration,
    );

    // 透明度动画
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    ));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });

    // 延迟开始翻页
    _startFlipAfterDelay();
  }

  void _startFlipAfterDelay() async {
    await Future.delayed(widget.delayBeforeStart);
    if (mounted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 背景页（下一页内容）
            if (progress > 0.1)
              widget.pages.length > 1
                  ? widget.pages[1]
                  : Container(color: const Color(0xFFF5F0E6)),

            // 当前页 - 向左滑行 + 透视
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001) // 透视
                ..translate(
                  -progress * MediaQuery.of(context).size.width * 0.8,
                  progress * 20,
                )
                ..rotateY(progress * 0.05), // 轻微旋转
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: widget.pages.isNotEmpty
                    ? widget.pages[0]
                    : Container(color: const Color(0xFFF5F0E6)),
              ),
            ),

            // 阴影遮罩 - 模拟页面移动时的阴影
            if (progress > 0 && progress < 1)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.black.withValues(alpha: progress * 0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 真实书本翻页组件 - 支持拖拽右下角触发翻页
class RealPageTurn extends StatefulWidget {
  final List<Widget> pages;
  final int initialPage;
  final Function(int)? onPageChanged;
  final bool allowForward;
  final bool allowBackward;
  final double threshold;
  final Duration duration;
  final double sizeRatio;
  final bool centered;

  const RealPageTurn({
    super.key,
    required this.pages,
    this.initialPage = 0,
    this.onPageChanged,
    this.allowForward = true,
    this.allowBackward = true,
    this.threshold = 0.3,
    this.duration = const Duration(milliseconds: 800),
    this.sizeRatio = 0.8,
    this.centered = true,
  });

  @override
  State<RealPageTurn> createState() => _RealPageTurnState();
}

class _RealPageTurnState extends State<RealPageTurn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late int _currentPage;
  double _dragStartX = 0;
  double _dragStartY = 0;
  double _dragProgress = 0;
  bool _isDragging = false;
  bool _isForward = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.addListener(() {
      setState(() {
        _dragProgress = _controller.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (_controller.isAnimating) return;

    final touchX = details.localPosition.dx;
    final touchY = details.localPosition.dy;
    final size = MediaQuery.of(context).size;
    final componentWidth = size.width * widget.sizeRatio;
    final componentHeight = size.height * widget.sizeRatio;

    final leftOffset = widget.centered ? (size.width - componentWidth) / 2 : 0;
    final topOffset = widget.centered ? (size.height - componentHeight) / 2 : 0;

    final rightEdge = leftOffset + componentWidth;
    final bottomEdge = topOffset + componentHeight;
    final cornerSize = componentWidth * 0.25;

    final inRightCorner =
        touchX > rightEdge - cornerSize && touchY > bottomEdge - cornerSize;
    final inLeftCorner =
        touchX < leftOffset + cornerSize && touchY > bottomEdge - cornerSize;

    if (inRightCorner) {
      if (widget.allowForward && _currentPage < widget.pages.length - 1) {
        _isForward = true;
        _isDragging = true;
        _dragStartX = touchX;
        _dragStartY = touchY;
      }
    } else if (inLeftCorner) {
      if (widget.allowBackward && _currentPage > 0) {
        _isForward = false;
        _isDragging = true;
        _dragStartX = touchX;
        _dragStartY = touchY;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final componentSize = MediaQuery.of(context).size.width * widget.sizeRatio;
    final deltaX = _dragStartX - details.localPosition.dx;
    final deltaY = _dragStartY - details.localPosition.dy;

    final progress =
        ((deltaX + deltaY) / (componentSize * 1.5)).clamp(0.0, 1.0);

    setState(() {
      _dragProgress = progress;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;

    if (_dragProgress > widget.threshold) {
      _animateToPage(1.0);
    } else {
      _animateToPage(0.0);
    }
  }

  void _animateToPage(double target) {
    final startProgress = _dragProgress;
    _controller.reset();

    final animation = Tween<double>(
      begin: startProgress,
      end: target,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    animation.addListener(() {
      setState(() {
        _dragProgress = animation.value;
      });
    });

    _controller.forward().then((_) {
      if (target > 0.5 && _dragProgress > widget.threshold) {
        if (_isForward) {
          _currentPage++;
        } else {
          _currentPage--;
        }
        widget.onPageChanged?.call(_currentPage);
      }
      setState(() {
        _dragProgress = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final componentWidth = size.width * widget.sizeRatio;
    final componentHeight = size.height * widget.sizeRatio;

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              children: [
                if (_dragProgress > 0)
                  _buildPage(_isForward ? _currentPage + 1 : _currentPage - 1),
                _buildCurrentPageWithEffect(),
                if (_dragProgress == 0 &&
                    _currentPage < widget.pages.length - 1)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Icon(
                      Icons.chevron_left,
                      color: Colors.black.withValues(alpha: 0.2),
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (widget.centered) {
      return Center(
        child: SizedBox(
          width: componentWidth,
          height: componentHeight,
          child: content,
        ),
      );
    }

    return SizedBox(
      width: componentWidth,
      height: componentHeight,
      child: content,
    );
  }

  Widget _buildPage(int index) {
    if (index < 0 || index >= widget.pages.length) {
      return const SizedBox.shrink();
    }
    return widget.pages[index];
  }

  Widget _buildCurrentPageWithEffect() {
    if (_dragProgress == 0) {
      return widget.pages[_currentPage];
    }

    return _buildPageTurnEffect(
      child: widget.pages[_currentPage],
      progress: _dragProgress,
      isForward: _isForward,
    );
  }

  Widget _buildPageTurnEffect({
    required Widget child,
    required double progress,
    required bool isForward,
  }) {
    final screenHeight = MediaQuery.of(context).size.height * widget.sizeRatio;

    final angle = progress * pi / 2;

    return Stack(
      children: [
        Transform(
          alignment: Alignment.bottomRight,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..translate(0.0, -progress * screenHeight * 0.3)
            ..rotateX(isForward ? angle * 0.3 : -angle * 0.3)
            ..rotateY(isForward ? angle : -angle),
          child: Opacity(
            opacity: 1 - progress * 0.3,
            child: child,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Colors.black.withValues(alpha: progress * 0.5),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.5 + progress * 0.5],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
