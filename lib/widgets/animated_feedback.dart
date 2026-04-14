import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/design_tokens.dart';

/// ============================================================================
/// 动画反馈组件集合
/// ============================================================================
/// 
/// 基于 Interaction Design Skill 实现：
/// - 触觉 + 视觉 + 听觉三重反馈
/// - 微交互动画 (100-150ms)
/// - Spring 物理动画效果

/// 涟漪效果按钮
/// 
/// 点击时产生水波纹扩散效果，提供清晰的交互反馈
class RippleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? rippleColor;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  final Duration duration;

  const RippleButton({
    super.key,
    required this.child,
    this.onTap,
    this.backgroundColor,
    this.rippleColor,
    this.padding,
    this.borderRadius,
    this.duration = PrimitiveAnimation.fast,
  });

  @override
  State<RippleButton> createState() => _RippleButtonState();
}

class _RippleButtonState extends State<RippleButton>
    with SingleTickerProviderStateMixin {
  final List<_Ripple> _ripples = [];
  int _rippleId = 0;

  void _addRipple(Offset position) {
    if (widget.onTap == null) return;

    setState(() {
      _ripples.add(_Ripple(
        id: _rippleId++,
        position: position,
      ));
    });

    // 触觉反馈
    HapticFeedback.lightImpact();

    // 延迟移除涟漪
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _ripples.removeWhere((r) => r.id == _rippleId - 1);
        });
      }
    });

    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? Colors.transparent;
    final rpColor = widget.rippleColor ?? Colors.white.withValues(alpha: 0.3);

    return GestureDetector(
      onTapDown: (details) => _addRipple(details.localPosition),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Container(
            padding: widget.padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
            ),
            child: widget.child,
          ),
          // 涟漪层
          ..._ripples.map((ripple) => _RippleWidget(
            ripple: ripple,
            color: rpColor,
          )),
        ],
      ),
    );
  }
}

class _Ripple {
  final int id;
  final Offset position;

  _Ripple({required this.id, required this.position});
}

class _RippleWidget extends StatefulWidget {
  final _Ripple ripple;
  final Color color;

  const _RippleWidget({
    required this.ripple,
    required this.color,
  });

  @override
  State<_RippleWidget> createState() => _RippleWidgetState();
}

class _RippleWidgetState extends State<_RippleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.forward();
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
        return Positioned(
          left: widget.ripple.position.dx - 50 * _animation.value,
          top: widget.ripple.position.dy - 50 * _animation.value,
          child: Container(
            width: 100 * _animation.value,
            height: 100 * _animation.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.3 * (1 - _animation.value)),
            ),
          ),
        );
      },
    );
  }
}

/// 弹跳卡片 - 按压时产生弹跳效果
class BouncyCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;

  const BouncyCard({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 0.96,
  });

  @override
  State<BouncyCard> createState() => _BouncyCardState();
}

class _BouncyCardState extends State<BouncyCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: PrimitiveAnimation.fast,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleFactor,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: PrimitiveAnimation.spring,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap == null) return;
    _controller.forward();
    HapticFeedback.lightImpact();
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap == null) return;
    _controller.reverse();
    widget.onTap!();
  }

  void _handleTapCancel() {
    if (widget.onTap == null) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// 震动动画 - 用于错误提示
class ShakeAnimation extends StatefulWidget {
  final Widget child;
  final bool shouldShake;
  final VoidCallback? onShakeComplete;
  final int shakeCount;

  const ShakeAnimation({
    super.key,
    required this.child,
    this.shouldShake = false,
    this.onShakeComplete,
    this.shakeCount = 3,
  });

  @override
  State<ShakeAnimation> createState() => _ShakeAnimationState();
}

class _ShakeAnimationState extends State<ShakeAnimation>
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

    _buildAnimation();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onShakeComplete?.call();
      }
    });
  }

  void _buildAnimation() {
    final items = <TweenSequenceItem<double>>[];
    
    for (int i = 0; i < widget.shakeCount; i++) {
      items.add(TweenSequenceItem(
        tween: Tween(begin: 0, end: -8),
        weight: 1,
      ));
      items.add(TweenSequenceItem(
        tween: Tween(begin: -8, end: 8),
        weight: 2,
      ));
    }
    
    items.add(TweenSequenceItem(
      tween: Tween(begin: 8, end: 0),
      weight: 1,
    ));

    _animation = TweenSequence<double>(items).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ShakeAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldShake && !oldWidget.shouldShake) {
      _controller.forward(from: 0);
      HapticFeedback.heavyImpact();
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

/// 呼吸动画 - 用于吸引注意力
class BreathingAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minScale;
  final double maxScale;

  const BreathingAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 2000),
    this.minScale = 0.98,
    this.maxScale = 1.02,
  });

  @override
  State<BreathingAnimation> createState() => _BreathingAnimationState();
}

class _BreathingAnimationState extends State<BreathingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _animation = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _controller.repeat(reverse: true);
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
        return Transform.scale(
          scale: _animation.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 脉冲动画 - 用于新消息/通知提示
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Color? pulseColor;

  const PulseAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.pulseColor,
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 脉冲环
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              width: 20 + (_animation.value * 20),
              height: 20 + (_animation.value * 20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (widget.pulseColor ?? Colors.red)
                    .withValues(alpha: 0.3 * (1 - _animation.value)),
              ),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

/// 滑动显示动画 - 列表项入场
class SlideInAnimation extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final AxisDirection direction;

  const SlideInAnimation({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = const Duration(milliseconds: 50),
    this.direction = AxisDirection.up,
  });

  @override
  State<SlideInAnimation> createState() => _SlideInAnimationState();
}

class _SlideInAnimationState extends State<SlideInAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: PrimitiveAnimation.normal,
      vsync: this,
    );

    final delay = widget.index * widget.delay.inMilliseconds / 1000;
    final adjustedDelay = delay.clamp(0.0, 0.6);

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          adjustedDelay,
          1.0,
          curve: PrimitiveAnimation.easeOut,
        ),
      ),
    );

    Offset beginOffset;
    switch (widget.direction) {
      case AxisDirection.up:
        beginOffset = const Offset(0, 0.3);
        break;
      case AxisDirection.down:
        beginOffset = const Offset(0, -0.3);
        break;
      case AxisDirection.left:
        beginOffset = const Offset(0.3, 0);
        break;
      case AxisDirection.right:
        beginOffset = const Offset(-0.3, 0);
        break;
    }

    _slideAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          adjustedDelay,
          1.0,
          curve: PrimitiveAnimation.spring,
        ),
      ),
    );

    // 延迟启动
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) _controller.forward();
    });
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
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 计数动画 - 数字变化时的平滑过渡
class CountAnimation extends StatefulWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;

  const CountAnimation({
    super.key,
    required this.value,
    this.style,
    this.duration = PrimitiveAnimation.normal,
  });

  @override
  State<CountAnimation> createState() => _CountAnimationState();
}

class _CountAnimationState extends State<CountAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _animation;
  int _oldValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _oldValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant CountAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _oldValue = oldWidget.value;
      _animation = IntTween(
        begin: _oldValue,
        end: widget.value,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: PrimitiveAnimation.easeOut,
        ),
      );
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
      animation: _controller,
      builder: (context, child) {
        return Text(
          '${_animation.value}',
          style: widget.style,
        );
      },
    );
  }
}
