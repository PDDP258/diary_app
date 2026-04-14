import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/design_tokens.dart';

/// ============================================================================
/// 沉浸式体验组件
/// ============================================================================
/// 
/// 创造令人难忘的交互体验：
/// - 视差滚动效果
/// - 3D 卡片翻转
/// - 魔法文字效果
/// - 粒子背景

/// 视差滚动容器
/// 
/// 背景元素以不同速度移动，创造深度感
class ParallaxContainer extends StatefulWidget {
  final Widget child;
  final List<ParallaxLayer> layers;
  final double height;

  const ParallaxContainer({
    super.key,
    required this.child,
    required this.layers,
    this.height = 300,
  });

  @override
  State<ParallaxContainer> createState() => _ParallaxContainerState();
}

class _ParallaxContainerState extends State<ParallaxContainer> {
  double _scrollOffset = 0;
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _controller.offset;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 视差层
        ...widget.layers.map((layer) {
          final speed = layer.speed;
          final offset = _scrollOffset * speed;

          return Positioned(
            top: layer.initialTop != null ? layer.initialTop! - offset : null,
            left: layer.initialLeft,
            right: layer.initialRight,
            bottom: layer.initialBottom != null
                ? layer.initialBottom! + offset
                : null,
            child: Transform.scale(
              scale: layer.scale,
              child: Opacity(
                opacity: layer.opacity,
                child: layer.child,
              ),
            ),
          );
        }),

        // 可滚动内容
        SingleChildScrollView(
          controller: _controller,
          child: SizedBox(
            height: widget.height,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class ParallaxLayer {
  final Widget child;
  final double speed;
  final double? initialTop;
  final double? initialLeft;
  final double? initialRight;
  final double? initialBottom;
  final double scale;
  final double opacity;

  ParallaxLayer({
    required this.child,
    required this.speed,
    this.initialTop,
    this.initialLeft,
    this.initialRight,
    this.initialBottom,
    this.scale = 1.0,
    this.opacity = 1.0,
  });
}

/// 3D 翻转卡片
/// 
/// 支持水平和垂直翻转，带有透视效果
class FlipCard extends StatefulWidget {
  final Widget front;
  final Widget back;
  final Duration duration;
  final FlipDirection direction;
  final VoidCallback? onFlip;

  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    this.duration = PrimitiveAnimation.slow,
    this.direction = FlipDirection.horizontal,
    this.onFlip,
  });

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isFront = true;

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
        curve: PrimitiveAnimation.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flip() {
    if (_isFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    setState(() => _isFront = !_isFront);
    widget.onFlip?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * math.pi;
          final isUnder = angle > math.pi / 2;

          Matrix4 transform = Matrix4.identity();
          transform.setEntry(3, 2, 0.001); // 透视

          if (widget.direction == FlipDirection.horizontal) {
            transform.rotateY(angle);
          } else {
            transform.rotateX(angle);
          }

          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: isUnder ? widget.back : widget.front,
          );
        },
      ),
    );
  }
}

enum FlipDirection { horizontal, vertical }

/// 魔法文字 - 渐变流光效果
class MagicText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final List<Color> colors;
  final Duration duration;

  const MagicText({
    super.key,
    required this.text,
    this.style,
    this.colors = const [
      Color(0xFFFF6B6B),
      Color(0xFF4ECDC4),
      Color(0xFF45B7D1),
      Color(0xFF96CEB4),
      Color(0xFFFF6B6B),
    ],
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<MagicText> createState() => _MagicTextState();
}

class _MagicTextState extends State<MagicText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
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
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: widget.colors,
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: GradientRotation(_controller.value * 2 * math.pi),
            ).createShader(bounds);
          },
          child: Text(
            widget.text,
            style: (widget.style ?? const TextStyle(fontSize: 24))
                .copyWith(color: Colors.white),
          ),
        );
      },
    );
  }
}

/// 霓虹发光文字
class NeonText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color glowColor;
  final double glowIntensity;

  const NeonText({
    super.key,
    required this.text,
    this.style,
    this.glowColor = const Color(0xFF00F0FF),
    this.glowIntensity = 20.0,
  });

  @override
  State<NeonText> createState() => _NeonTextState();
}

class _NeonTextState extends State<NeonText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
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
        return Text(
          widget.text,
          style: (widget.style ?? const TextStyle(fontSize: 32))
              .copyWith(
                color: widget.glowColor,
                shadows: [
                  Shadow(
                    color: widget.glowColor
                        .withValues(alpha: 0.8 * _animation.value),
                    blurRadius: widget.glowIntensity * _animation.value,
                  ),
                  Shadow(
                    color: widget.glowColor
                        .withValues(alpha: 0.4 * _animation.value),
                    blurRadius: widget.glowIntensity * 2 * _animation.value,
                  ),
                ],
              ),
        );
      },
    );
  }
}

/// 漂浮粒子背景
class FloatingParticles extends StatefulWidget {
  final int particleCount;
  final List<Color> colors;
  final double minSize;
  final double maxSize;
  final Duration duration;

  const FloatingParticles({
    super.key,
    this.particleCount = 20,
    this.colors = const [
      Colors.white,
      Color(0xFFFFE4E1),
      Color(0xFFE0F7FA),
      Color(0xFFF3E5F5),
    ],
    this.minSize = 4,
    this.maxSize = 12,
    this.duration = const Duration(seconds: 10),
  });

  @override
  State<FloatingParticles> createState() => _FloatingParticlesState();
}

class _FloatingParticlesState extends State<FloatingParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Particle> _particles;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();

    _particles = List.generate(
      widget.particleCount,
      (index) => Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: widget.minSize +
            _random.nextDouble() * (widget.maxSize - widget.minSize),
        color: widget.colors[_random.nextInt(widget.colors.length)],
        speed: 0.2 + _random.nextDouble() * 0.3,
        phase: _random.nextDouble() * 2 * math.pi,
      ),
    );
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
          size: Size.infinite,
          painter: _ParticlesPainter(
            particles: _particles,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class Particle {
  final double x;
  final double y;
  final double size;
  final Color color;
  final double speed;
  final double phase;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    required this.speed,
    required this.phase,
  });
}

class _ParticlesPainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;

  _ParticlesPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // 计算位置 - 向上漂浮 + 左右摇摆
      final y = ((particle.y - progress * particle.speed) % 1.0) * size.height;
      final x = particle.x * size.width +
          math.sin(progress * 2 * math.pi + particle.phase) * 20;

      final paint = Paint()
        ..color = particle.color.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(
        Offset(x, y),
        particle.size / 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 玻璃态容器
class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color? color;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.blur = 20,
    this.opacity = 0.2,
    this.color,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (color ?? Colors.white).withValues(alpha: opacity),
            (color ?? Colors.white).withValues(alpha: opacity * 0.5),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: blur,
            spreadRadius: -5,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 渐变边框容器
class GradientBorderContainer extends StatelessWidget {
  final Widget child;
  final List<Color> gradientColors;
  final double borderWidth;
  final double borderRadius;
  final EdgeInsets? padding;

  const GradientBorderContainer({
    super.key,
    required this.child,
    this.gradientColors = const [
      Color(0xFFFF6B6B),
      Color(0xFF4ECDC4),
      Color(0xFF45B7D1),
      Color(0xFFFF6B6B),
    ],
    this.borderWidth = 2,
    this.borderRadius = 20,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: gradientColors,
        ),
      ),
      child: Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius - borderWidth),
          color: Colors.white,
        ),
        child: child,
      ),
    );
  }
}

/// 打字机效果文字
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration speed;
  final VoidCallback? onComplete;

  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 50),
    this.onComplete,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayText = '';
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    Future.delayed(widget.speed, () {
      if (_currentIndex < widget.text.length && mounted) {
        setState(() {
          _displayText = widget.text.substring(0, _currentIndex + 1);
          _currentIndex++;
        });
        _startTyping();
      } else {
        widget.onComplete?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText,
      style: widget.style,
    );
  }
}
