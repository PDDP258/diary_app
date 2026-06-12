import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// 滚动揭示动画组件
/// 参考 pddp258.github.io/PROJECT_INTRO ScrollReveal 实现
///
/// 使用 IntersectionObserver 理念，当组件进入视口 15% 时触发
/// opacity: 0→1, translateY: 30→0, 过渡 0.3s ease-out（默认无延迟）
///
/// 用法:
/// ```dart
/// ScrollReveal(
///   delay: const Duration(milliseconds: 200),
///   child: MyWidget(),
/// )
/// ```
class ScrollReveal extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 延迟触发时间
  final Duration delay;

  /// 初始 Y 轴偏移（默认 30px）
  final double offsetY;

  /// 动画时长
  final Duration duration;

  /// 动画曲线
  final Curve curve;

  /// 可视阈值 (0.0 - 1.0)
  final double visibleFraction;

  /// 是否只播放一次
  final bool once;

  const ScrollReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 30.0,
    this.duration = const Duration(milliseconds: 300),
    this.curve = const Cubic(0.16, 1, 0.3, 1),
    this.visibleFraction = 0.15,
    this.once = true,
  });

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _translateY;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _translateY = Tween<double>(begin: widget.offsetY, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (widget.once && _triggered) return;

    if (info.visibleFraction >= widget.visibleFraction) {
      _triggered = true;
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    } else if (!widget.once) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: widget.key ?? Key('scroll_reveal_${widget.hashCode}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacity.value,
            child: Transform.translate(
              offset: Offset(0, _translateY.value),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}