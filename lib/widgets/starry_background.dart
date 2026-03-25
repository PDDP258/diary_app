import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// 星空背景组件
///
/// 营造深邃梦幻的星空氛围：
/// - 深蓝紫渐变背景
/// - 闪烁星星粒子效果
/// - 偶尔划过的流星
/// - 发光星云效果
class StarryBackground extends StatefulWidget {
  final Widget child;
  final int starCount;
  final bool showMeteor;

  const StarryBackground({
    super.key,
    required this.child,
    this.starCount = 100,
    this.showMeteor = true,
  });

  @override
  State<StarryBackground> createState() => _StarryBackgroundState();
}

class _StarryBackgroundState extends State<StarryBackground>
    with TickerProviderStateMixin {
  late List<Star> stars;
  late List<Meteor> meteors;
  late AnimationController _twinkleController;

  // 每个流星有独立的控制器，错开出现
  late List<AnimationController> _meteorControllers;
  late List<Timer?> _meteorTimers;
  final Random random = Random();

  @override
  void initState() {
    super.initState();
    _initStars();
    _initMeteors();

    // 星星闪烁动画
    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    if (widget.showMeteor) {
      _startMeteorLoops();
    }
  }

  void _initStars() {
    stars = List.generate(widget.starCount, (index) {
      return Star(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: random.nextDouble() * 2 + 0.5,
        opacity: random.nextDouble() * 0.7 + 0.3,
        twinkleSpeed: random.nextDouble() * 2 + 1,
        twinkleOffset: random.nextDouble() * pi * 2,
      );
    });
  }

  void _initMeteors() {
    // 四个方向的流星：左上、右上、左下、右下
    // 每种方向有1-2个流星，共4个，降低同时出现的概率
    meteors = [
      // 左上方向（从左上往右下）
      Meteor(
        x: 0.1 + random.nextDouble() * 0.3,
        y: 0.1 + random.nextDouble() * 0.2,
        length: random.nextDouble() * 50 + 30,
        speed: random.nextDouble() * 0.3 + 0.2,
        direction: MeteorDirection.topLeft,
      ),
      // 右上方向（从右上往左下）
      Meteor(
        x: 0.6 + random.nextDouble() * 0.3,
        y: 0.1 + random.nextDouble() * 0.2,
        length: random.nextDouble() * 50 + 30,
        speed: random.nextDouble() * 0.3 + 0.2,
        direction: MeteorDirection.topRight,
      ),
      // 左下方向（从左下往右上）
      Meteor(
        x: 0.1 + random.nextDouble() * 0.3,
        y: 0.5 + random.nextDouble() * 0.3,
        length: random.nextDouble() * 50 + 30,
        speed: random.nextDouble() * 0.3 + 0.2,
        direction: MeteorDirection.bottomLeft,
      ),
      // 右下方向（从右下往左上）
      Meteor(
        x: 0.6 + random.nextDouble() * 0.3,
        y: 0.5 + random.nextDouble() * 0.3,
        length: random.nextDouble() * 50 + 30,
        speed: random.nextDouble() * 0.3 + 0.2,
        direction: MeteorDirection.bottomRight,
      ),
    ];

    // 为每个流星创建独立的控制器
    _meteorControllers = List.generate(4, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 2000 + random.nextInt(1000)), // 2-3秒
      );
    });

    _meteorTimers = List.generate(4, (_) => null);
  }

  void _startMeteorLoops() {
    // 为每个流星设置独立的循环，错开出现时间
    for (int i = 0; i < meteors.length; i++) {
      _scheduleMeteor(i);
    }
  }

  void _scheduleMeteor(int index) {
    // 基础间隔 6-12 秒，保持总体频率与原来相当
    // 但通过错开初始延迟和随机间隔，降低同时出现的概率
    final baseDelay = 6 + random.nextInt(7); // 6-12秒
    // 根据索引添加偏移，让四个流星更分散
    final offsetDelay = index * 2; // 每个流星间隔2秒的偏移
    final totalDelay = baseDelay + offsetDelay;

    _meteorTimers[index] = Timer(Duration(seconds: totalDelay), () {
      if (!mounted) return;

      // 检查是否有其他流星正在显示，避免同时出现
      final othersActive = _meteorControllers.asMap().entries.any(
            (e) => e.key != index && e.value.isAnimating,
          );

      // 如果其他流星正在显示，有70%概率延迟到下次
      if (othersActive && random.nextDouble() < 0.7) {
        _scheduleMeteor(index); // 重新调度
        return;
      }

      _meteorControllers[index].forward(from: 0).then((_) {
        if (mounted) {
          _scheduleMeteor(index);
        }
      });
    });
  }

  @override
  void dispose() {
    _twinkleController.dispose();
    for (var timer in _meteorTimers) {
      timer?.cancel();
    }
    for (var controller in _meteorControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // 深蓝紫渐变背景
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D0D1F), // 深蓝黑
            Color(0xFF1A1A3E), // 深紫蓝
            Color(0xFF2D1B4E), // 紫罗兰
            Color(0xFF1A1A3E), // 深紫蓝
          ],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _twinkleController,
          ..._meteorControllers,
        ]),
        builder: (context, child) {
          return CustomPaint(
            painter: StarryPainter(
              stars: stars,
              meteors: meteors,
              meteorProgresses: _meteorControllers.map((c) => c.value).toList(),
              twinkleProgress: _twinkleController.value,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// 星星数据
class Star {
  final double x;
  final double y;
  final double size;
  final double opacity;
  final double twinkleSpeed;
  final double twinkleOffset;

  Star({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.twinkleSpeed,
    required this.twinkleOffset,
  });
}

/// 流星方向枚举
enum MeteorDirection {
  topLeft, // 从左上往右下
  topRight, // 从右上往左下
  bottomLeft, // 从左下往右上
  bottomRight // 从右下往左上
}

/// 流星数据
class Meteor {
  double x;
  double y;
  final double length;
  final double speed;
  final MeteorDirection direction;

  Meteor({
    required this.x,
    required this.y,
    required this.length,
    required this.speed,
    required this.direction,
  });
}

/// 星空绘制器
class StarryPainter extends CustomPainter {
  final List<Star> stars;
  final List<Meteor> meteors;
  final double twinkleProgress;
  final List<double> meteorProgresses;

  StarryPainter({
    required this.stars,
    required this.meteors,
    required this.twinkleProgress,
    required this.meteorProgresses,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制星星
    for (var star in stars) {
      _drawStar(canvas, size, star);
    }

    // 绘制流星（每个流星有自己的进度）
    for (int i = 0; i < meteors.length; i++) {
      _drawMeteor(canvas, size, meteors[i], meteorProgresses[i]);
    }

    // 绘制星云效果
    _drawNebula(canvas, size);
  }

  void _drawStar(Canvas canvas, Size size, Star star) {
    // 计算闪烁效果
    final twinkle =
        sin(twinkleProgress * pi * 2 * star.twinkleSpeed + star.twinkleOffset);
    final currentOpacity = star.opacity * (0.6 + 0.4 * twinkle);

    final paint = Paint()
      ..color = Colors.white.withOpacity(currentOpacity.clamp(0.1, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);

    final center = Offset(star.x * size.width, star.y * size.height);

    // 绘制星星光晕
    canvas.drawCircle(center, star.size * 2,
        Paint()..color = Colors.white.withOpacity(currentOpacity * 0.3));

    // 绘制星星核心
    canvas.drawCircle(center, star.size, paint);
  }

  void _drawMeteor(Canvas canvas, Size size, Meteor meteor, double progress) {
    if (progress <= 0 || progress >= 1) return;

    double startX, startY, endX, endY;
    final moveDistance = progress * size.width * 0.8; // 移动距离

    // 根据方向计算起始和结束位置
    switch (meteor.direction) {
      case MeteorDirection.topLeft:
        // 从左上往右下
        startX = meteor.x * size.width + moveDistance;
        startY = meteor.y * size.height + moveDistance * 0.5;
        endX = startX - meteor.length * cos(pi / 4);
        endY = startY - meteor.length * sin(pi / 4);
        break;
      case MeteorDirection.topRight:
        // 从右上往左下
        startX = meteor.x * size.width - moveDistance;
        startY = meteor.y * size.height + moveDistance * 0.5;
        endX = startX + meteor.length * cos(pi / 4);
        endY = startY - meteor.length * sin(pi / 4);
        break;
      case MeteorDirection.bottomLeft:
        // 从左下往右上
        startX = meteor.x * size.width + moveDistance;
        startY = meteor.y * size.height - moveDistance * 0.5;
        endX = startX - meteor.length * cos(pi / 4);
        endY = startY + meteor.length * sin(pi / 4);
        break;
      case MeteorDirection.bottomRight:
        // 从右下往左上
        startX = meteor.x * size.width - moveDistance;
        startY = meteor.y * size.height - moveDistance * 0.5;
        endX = startX + meteor.length * cos(pi / 4);
        endY = startY + meteor.length * sin(pi / 4);
        break;
    }

    // 检查是否超出屏幕
    if (startX < -100 ||
        startX > size.width + 100 ||
        startY < -100 ||
        startY > size.height + 100) {
      return;
    }

    // 流星渐变 - 头部亮，尾部渐隐
    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(0.8 * (1 - progress * 0.5)),
        Colors.white.withOpacity(1 - progress * 0.3),
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromPoints(Offset(endX, endY), Offset(startX, startY)),
      )
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

    // 流星头部光点
    canvas.drawCircle(
      Offset(startX, startY),
      3,
      Paint()..color = Colors.white.withOpacity(0.8 * (1 - progress * 0.3)),
    );
  }

  void _drawNebula(Canvas canvas, Size size) {
    // 绘制柔和的星云背景效果
    final nebulaPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.3, 0.3),
        radius: 0.8,
        colors: [
          const Color(0xFF4A148C).withOpacity(0.15), // 紫色星云
          const Color(0xFF1A237E).withOpacity(0.1), // 蓝色星云
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), nebulaPaint);

    // 右下角另一团星云
    final nebulaPaint2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.8, 0.7),
        radius: 0.6,
        colors: [
          const Color(0xFF311B92).withOpacity(0.12),
          const Color(0xFF0D47A1).withOpacity(0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), nebulaPaint2);
  }

  @override
  bool shouldRepaint(covariant StarryPainter oldDelegate) => true;
}

/// 星空主题包装器
///
/// 当用户使用星空主题时，自动应用星空背景
class StarryThemeWrapper extends StatelessWidget {
  final Widget child;
  final bool isStarryTheme;

  const StarryThemeWrapper({
    super.key,
    required this.child,
    required this.isStarryTheme,
  });

  @override
  Widget build(BuildContext context) {
    if (!isStarryTheme) {
      return child;
    }

    return StarryBackground(
      child: child,
    );
  }
}
