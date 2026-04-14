import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/design_tokens.dart';
import '../config/app_theme.dart';

/// ============================================================================
/// 智能通知与引导系统
/// ============================================================================
///
/// 优雅的通知和引导组件：
/// - 浮动通知 Toast
/// - 徽章解锁动画
/// - 引导提示 Tooltip
/// - 成就弹窗

/// 浮动通知管理器
class ToastManager {
  static final ToastManager _instance = ToastManager._internal();
  factory ToastManager() => _instance;
  ToastManager._internal();

  OverlayEntry? _currentToast;

  void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onTap,
  }) {
    // 移除当前通知
    _currentToast?.remove();

    final overlay = Overlay.of(context);
    _currentToast = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        child: _ToastWidget(
          message: message,
          type: type,
          duration: duration,
          onDismiss: () {
            _currentToast?.remove();
            _currentToast = null;
          },
          onTap: onTap,
        ),
      ),
    );

    overlay.insert(_currentToast!);
  }

  void hide() {
    _currentToast?.remove();
    _currentToast = null;
  }
}

enum ToastType { success, warning, error, info }

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
    this.onTap,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: -100, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: PrimitiveAnimation.spring,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.forward();

    // 自动消失
    Future.delayed(widget.duration, () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.type) {
      case ToastType.success:
        return Icons.check_circle;
      case ToastType.warning:
        return Icons.warning;
      case ToastType.error:
        return Icons.error;
      case ToastType.info:
        return Icons.info;
    }
  }

  Color get _color {
    switch (widget.type) {
      case ToastType.success:
        return PrimitiveColors.mint500;
      case ToastType.warning:
        return PrimitiveColors.amber500;
      case ToastType.error:
        return PrimitiveColors.rose500;
      case ToastType.info:
        return PrimitiveColors.sky500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: () {
          widget.onTap?.call();
          _dismiss();
        },
        onHorizontalDragEnd: (_) => _dismiss(),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PrimitiveSpacing.lg,
            vertical: PrimitiveSpacing.md,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(PrimitiveRadius.lg),
            boxShadow: PrimitiveShadows.lg,
            border: Border.all(color: _color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: _color, size: 20),
              ),
              const SizedBox(width: PrimitiveSpacing.md),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _dismiss,
                child: Icon(Icons.close,
                    color: Colors.grey.shade400, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 徽章解锁动画
class BadgeUnlockAnimation extends StatefulWidget {
  final String badgeName;
  final String? badgeIcon;
  final Color badgeColor;
  final VoidCallback? onComplete;

  const BadgeUnlockAnimation({
    super.key,
    required this.badgeName,
    this.badgeIcon,
    this.badgeColor = const Color(0xFFFFD700),
    this.onComplete,
  });

  @override
  State<BadgeUnlockAnimation> createState() => _BadgeUnlockAnimationState();
}

class _BadgeUnlockAnimationState extends State<BadgeUnlockAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _shineAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 20),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _rotateAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: -0.5, end: 0.1), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.1, end: -0.05), weight: 30),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0), weight: 30),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _shineAnimation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeInOut),
      ),
    );

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        widget.onComplete?.call();
      });
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
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotateAnimation.value,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 光晕效果
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.badgeColor.withValues(alpha: 0.4),
                        widget.badgeColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                // 徽章主体
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.badgeColor,
                        widget.badgeColor.withValues(alpha: 0.7),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.badgeColor.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.badgeIcon ?? '🏆',
                      style: const TextStyle(fontSize: 40),
                    ),
                  ),
                ),
                // 闪光效果
                Positioned.fill(
                  child: ClipOval(
                    child: CustomPaint(
                      painter: _ShinePainter(
                        progress: _shineAnimation.value,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShinePainter extends CustomPainter {
  final double progress;

  _ShinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final gradient = LinearGradient(
      colors: [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0.5),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: GradientRotation(progress * 3.14),
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 成就弹窗
class AchievementDialog extends StatelessWidget {
  final String title;
  final String description;
  final String? icon;
  final Color? color;
  final VoidCallback? onView;
  final VoidCallback? onDismiss;

  const AchievementDialog({
    super.key,
    required this.title,
    required this.description,
    this.icon,
    this.color,
    this.onView,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(PrimitiveSpacing.xxxl),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(PrimitiveRadius.xxl),
          boxShadow: PrimitiveShadows.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 徽章动画
            BadgeUnlockAnimation(
              badgeName: title,
              badgeIcon: icon,
              badgeColor: color ?? PrimitiveColors.amber500,
            ),
            const SizedBox(height: PrimitiveSpacing.xxl),
            // 标题
            Text(
              '获得成就！',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.textMediumColor,
              ),
            ),
            const SizedBox(height: PrimitiveSpacing.sm),
            // 成就名称
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PrimitiveSpacing.md),
            // 描述
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: scheme.textMediumColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PrimitiveSpacing.xxxl),
            // 按钮
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onDismiss?.call();
                    },
                    child: const Text('知道了'),
                  ),
                ),
                const SizedBox(width: PrimitiveSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onView?.call();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color ?? scheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('查看'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 引导提示组件
class GuidedTooltip extends StatefulWidget {
  final Widget child;
  final String message;
  final TooltipPosition position;
  final bool show;
  final VoidCallback? onDismiss;

  const GuidedTooltip({
    super.key,
    required this.child,
    required this.message,
    this.position = TooltipPosition.bottom,
    this.show = false,
    this.onDismiss,
  });

  @override
  State<GuidedTooltip> createState() => _GuidedTooltipState();
}

enum TooltipPosition { top, bottom, left, right }

class _GuidedTooltipState extends State<GuidedTooltip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: PrimitiveAnimation.spring,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    if (widget.show) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant GuidedTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      _controller.forward();
    } else if (!widget.show && oldWidget.show) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (widget.show)
          Positioned(
            top: widget.position == TooltipPosition.bottom ? null : -50,
            bottom: widget.position == TooltipPosition.top ? null : -50,
            left: widget.position == TooltipPosition.right ? null : 0,
            right: widget.position == TooltipPosition.left ? null : 0,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Opacity(
                    opacity: _fadeAnimation.value,
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: widget.onDismiss,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrimitiveSpacing.md,
                    vertical: PrimitiveSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(PrimitiveRadius.sm),
                  ),
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 五彩纸屑庆祝效果
class ConfettiCelebration extends StatefulWidget {
  final Duration duration;
  final int particleCount;
  final VoidCallback? onComplete;

  const ConfettiCelebration({
    super.key,
    this.duration = const Duration(seconds: 3),
    this.particleCount = 50,
    this.onComplete,
  });

  @override
  State<ConfettiCelebration> createState() => _ConfettiCelebrationState();
}

class _ConfettiCelebrationState extends State<ConfettiCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<ConfettiParticle> _particles;
  final math.Random _random = math.Random();

  final List<Color> _colors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _particles = List.generate(
      widget.particleCount,
      (index) => ConfettiParticle(
        color: _colors[_random.nextInt(_colors.length)],
        x: _random.nextDouble(),
        y: -0.1 - _random.nextDouble() * 0.2,
        size: 5 + _random.nextDouble() * 10,
        speed: 0.5 + _random.nextDouble() * 0.5,
        angle: _random.nextDouble() * 2 * math.pi,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.2,
      ),
    );

    _controller.forward().then((_) => widget.onComplete?.call());
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
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class ConfettiParticle {
  final Color color;
  final double x;
  double y;
  final double size;
  final double speed;
  final double angle;
  final double rotationSpeed;

  ConfettiParticle({
    required this.color,
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.angle,
    required this.rotationSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final y = particle.y + progress * particle.speed;
      final x = particle.x +
          math.sin(progress * 2 * math.pi + particle.angle) * 0.05;
      final rotation = progress * particle.rotationSpeed * 10;

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(rotation);

      final paint = Paint()..color = particle.color;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: particle.size,
          height: particle.size * 0.6,
        ),
        paint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


