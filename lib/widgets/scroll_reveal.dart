import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../config/design_tokens.dart';

/// 滚动揭示动画组件
///
/// 基于 Interaction Design Skill 与 Visual Design Foundations：
/// - 进入视口时触发 reveal 动画
/// - 使用统一设计令牌：时长、缓动、距离
/// - 支持多方向 reveal 与 stagger 延迟
///
/// 用法:
/// ```dart
/// ScrollReveal(
///   delay: PrimitiveAnimation.normal,
///   direction: AxisDirection.up,
///   child: MyWidget(),
/// )
/// ```
class ScrollReveal extends StatefulWidget {
  final Widget child;

  /// 延迟触发时间
  final Duration delay;

  /// 初始偏移距离（默认 28 逻辑像素）
  final double offset;

  /// 动画时长
  final Duration duration;

  /// 动画曲线
  final Curve curve;

  /// 动画方向：up/down/left/right
  final AxisDirection direction;

  /// 可视阈值 (0.0 - 1.0)
  final double visibleFraction;

  /// 是否只播放一次
  final bool once;

  const ScrollReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 28.0,
    this.duration = PrimitiveAnimation.normal,
    this.curve = PrimitiveAnimation.easeOutExpo,
    this.direction = AxisDirection.up,
    this.visibleFraction = 0.12,
    this.once = true,
  });

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _translate;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _translate = Tween<Offset>(
      begin: _getInitialOffset(widget.direction, widget.offset),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    // ⚠️ 2026-10-31 安全兜底（重要）：
    //
    // 原来触发揭示动画**只依赖** `_onVisibilityChanged`。一旦
    // VisibilityDetector 因为任何原因没有回调（布局时机、父级裁剪、
    // 测试环境、极端滚动状态），`_controller` 就永远停在 0.0，
    // 而 `Opacity(0.0)` 会让内容**完全不可见且永远不出现**。
    //
    // 这属于「宁可不动画，也绝不能看不见」的底线问题 ——
    // 和信息流里「图片不爱显示」是同一类风险。
    //
    // 兜底策略：首帧结束后如果还没被触发，就无条件播一遍。
    // 列表项本来就该可见，动画只是锦上添花。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_triggered) {
        _triggered = true;
        _controller.forward();
      }
    });
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
          // ⚠️ 2026-10-31 帧率优化。
          //
          // 原实现无条件包 `Opacity(opacity: _opacity.value)`：
          // 即使动画已经播完（value == 1.0），它仍然留在树里，
          // 且列表里**每一个** item 都有一个。非 0/1 的 Opacity 会走
          // saveLayer（离屏合成），列表滚动时几十个图层叠加，
          // 这是全局帧率偏低的一个重要来源。
          //
          // 现在：动画完成后**直接返回 child**，把 Opacity/Transform
          // 从树里摘掉 —— 稳态下零额外开销。
          final value = _opacity.value;
          if (value >= 1.0) {
            return child ?? const SizedBox.shrink();
          }
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: _translate.value,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

Offset _getInitialOffset(AxisDirection direction, double distance) {
  switch (direction) {
    case AxisDirection.up:
      return Offset(0, distance);
    case AxisDirection.down:
      return Offset(0, -distance);
    case AxisDirection.right:
      return Offset(-distance, 0);
    case AxisDirection.left:
      return Offset(distance, 0);
  }
}
