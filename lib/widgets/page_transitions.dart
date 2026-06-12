import 'package:flutter/material.dart';
import '../config/design_tokens.dart';

/// 页面过渡动画集合
///
/// 基于 Interaction Design Skill：
/// - 300-500ms 中等过渡时长
/// - Ease-out 进入，Ease-in 退出
/// - 保持上下文连续性

/// 淡入上浮过渡 - 通用页面切换
class FadeSlideTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final Offset beginOffset;

  const FadeSlideTransition({
    super.key,
    required this.child,
    required this.animation,
    this.beginOffset = const Offset(0, 0.05),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(
              beginOffset.dx * (1 - animation.value) * 100,
              beginOffset.dy * (1 - animation.value) * 50,
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 日记列表项入场动画
class DiaryListItemTransition extends StatelessWidget {
  final Widget child;
  final int index;
  final Animation<double> animation;

  const DiaryListItemTransition({
    super.key,
    required this.child,
    required this.index,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    // 错峰动画，每项延迟 50ms
    final delay = index * 0.1;
    final adjustedAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: Interval(
          delay.clamp(0.0, 0.6),
          1.0,
          curve: PrimitiveAnimation.easeOutExpo,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: adjustedAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: adjustedAnimation.value,
          child: Transform.translate(
            offset: Offset(
              0,
              (1 - adjustedAnimation.value) * 30,
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 卡片展开过渡 - 用于日记详情
class CardExpandTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final Rect? sourceRect;

  const CardExpandTransition({
    super.key,
    required this.child,
    required this.animation,
    this.sourceRect,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final easeOut = PrimitiveAnimation.easeOutExpo.transform(animation.value);

        return ClipRect(
          child: Opacity(
            opacity: animation.value,
            child: Transform.scale(
              scale: 0.95 + (easeOut * 0.05),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Hero 动画包装器 - 共享元素过渡
class SharedElementTransition extends StatelessWidget {
  final String tag;
  final Widget child;

  const SharedElementTransition({
    super.key,
    required this.tag,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      // 自定义 Hero 动画曲线
      flightShuttleBuilder: (
        BuildContext flightContext,
        Animation<double> animation,
        HeroFlightDirection flightDirection,
        BuildContext fromHeroContext,
        BuildContext toHeroContext,
      ) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            // 使用 ease-in-out 曲线
            final easeValue = Curves.easeInOut.transform(animation.value);
            return Opacity(
              opacity: easeValue,
              child: child,
            );
          },
          child: flightDirection == HeroFlightDirection.push
              ? toHeroContext.widget
              : fromHeroContext.widget,
        );
      },
      child: child,
    );
  }
}

/// 底部弹窗滑入过渡
class BottomSheetTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;

  const BottomSheetTransition({
    super.key,
    required this.child,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // Ease-out 进入
        final easeOut = PrimitiveAnimation.easeOutExpo.transform(animation.value);

        return Transform.translate(
          offset: Offset(0, (1 - easeOut) * 100),
          child: Opacity(
            opacity: animation.value,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 缩放淡入组合 - 用于 FAB 或重要按钮
class ScaleFadeTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final double beginScale;

  const ScaleFadeTransition({
    super.key,
    required this.child,
    required this.animation,
    this.beginScale = 0.8,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // Spring 弹性效果
        const springCurve = Cubic(0.34, 1.56, 0.64, 1);
        final springValue = springCurve.transform(animation.value);

        return Opacity(
          opacity: animation.value,
          child: Transform.scale(
            scale: beginScale + (springValue * (1 - beginScale)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 列表加载骨架屏动画
class SkeletonLoadingTransition extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final Widget skeleton;

  const SkeletonLoadingTransition({
    super.key,
    required this.isLoading,
    required this.child,
    required this.skeleton,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: PrimitiveAnimation.normal,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: isLoading ? skeleton : child,
    );
  }
}

/// 震动反馈动画 - 用于错误提示
class ShakeTransition extends StatefulWidget {
  final Widget child;
  final bool shouldShake;
  final VoidCallback? onShakeComplete;

  const ShakeTransition({
    super.key,
    required this.child,
    this.shouldShake = false,
    this.onShakeComplete,
  });

  @override
  State<ShakeTransition> createState() => _ShakeTransitionState();
}

class _ShakeTransitionState extends State<ShakeTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onShakeComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ShakeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldShake && !oldWidget.shouldShake) {
      _controller.forward(from: 0);
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
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_animation.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
