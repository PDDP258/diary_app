import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 主题背景组件工厂
/// 
/// 为主题商店中的特殊主题提供高级背景效果
class ThemeBackgroundFactory {
  static Widget wrap({
    required Widget child,
    required String themeName,
  }) {
    switch (themeName) {
      case '星空主题':
        return StarryBackground(child: child);
      case '樱花主题':
        return SakuraBackground(child: child);
      case '海洋主题':
        return OceanBackground(child: child);
      case '极光主题':
        return AuroraBackground(child: child);
      case '黄金主题':
        return GoldenBackground(child: child);
      default:
        return child;
    }
  }
}

// ==================== 🌸 樱花主题（优雅飘落版）====================
class SakuraBackground extends StatefulWidget {
  final Widget child;
  const SakuraBackground({super.key, required this.child});

  @override
  State<SakuraBackground> createState() => _SakuraBackgroundState();
}

class _SakuraBackgroundState extends State<SakuraBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<SakuraPetal> petals = [];
  final List<SakuraPetal> landedPetals = []; // 已落地的花瓣
  final List<SakuraFlower> flowers = []; // 完整花朵
  final Random random = Random();
  int _chaosTimer = 0; // 混乱时间计时器
  bool _isChaos = false; // 是否处于混乱状态
  int _flowerSpawnCounter = 0; // 花朵生成计时器

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // 初始化花瓣 - 更深的颜色
    final colors = [
      const Color(0xFFFFB7C5), // 深粉
      const Color(0xFFFF9EAA), // 珊瑚粉
      const Color(0xFFFFC1CC), // 柔粉
      const Color(0xFFFF8FAB), // 玫瑰粉
    ];

    for (int i = 0; i < 25; i++) {
      petals.add(SakuraPetal(
        x: random.nextDouble(),
        y: random.nextDouble() * 1.2 - 0.2,
        size: random.nextDouble() * 8 + 6,
        speed: (random.nextDouble() * 0.3 + 0.2) * 0.8, // 速度减缓至80%
        rotation: random.nextDouble() * pi * 2,
        rotationSpeed: random.nextDouble() * 0.02 - 0.01,
        opacity: random.nextDouble() * 0.4 + 0.4,
        color: colors[random.nextInt(colors.length)],
        vx: 0,
        vy: 0,
      ));
    }
    
    // 首次立即生成一朵大樱花（1秒后）
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _spawnFlower();
    });
  }
  
  /// 生成完整花朵 - 唯美樱花，更深颜色
  void _spawnFlower() {
    if (flowers.length >= 2) return; // 最多2朵
    
    // 更深的樱花粉色
    final flowerColors = [
      const Color(0xFFFF6B8A), // 深珊瑚粉
      const Color(0xFFFF5C8D), // 玫瑰粉
      const Color(0xFFFF85A1), // 樱粉
    ];
    
    flowers.add(SakuraFlower(
      x: random.nextDouble() * 0.8 + 0.1,
      y: -0.15,
      size: random.nextDouble() * 4 + 12, // 12-16大小（稍小更精致）
      speed: random.nextDouble() * 0.12 + 0.10,
      rotation: random.nextDouble() * pi * 2,
      rotationSpeed: random.nextDouble() * 0.008 - 0.004,
      opacity: 1.0,
      color: flowerColors[random.nextInt(flowerColors.length)],
      vx: 0,
      vy: 0,
      life: 1.0,
      isLanded: false,
      chaosTimer: 0,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _chaosIntensity = 0.0; // 混乱强度，用于过渡动画
  
  void _triggerChaos() {
    if (!_isChaos && random.nextDouble() < 0.00088) { // 频率提高10%
      _isChaos = true;
      _chaosTimer = 120; // 延长到2秒（带过渡）
      
      // 给所有花瓣随机速度 - 上左右向下右左的来向（力度减轻20%）
      for (var petal in petals) {
        // 方向：上(0,-1), 左(-1,0), 右(1,0), 下右(0.7,0.7), 左(-0.7,0.7)
        final direction = random.nextInt(5);
        switch (direction) {
          case 0: // 上
            petal.vx = (random.nextDouble() - 0.5) * 0.0032; // ±0.0016
            petal.vy = -0.0048 - random.nextDouble() * 0.0032; // -0.0048 ~ -0.008
            break;
          case 1: // 左
            petal.vx = -0.0048 - random.nextDouble() * 0.0032; // -0.0048 ~ -0.008
            petal.vy = (random.nextDouble() - 0.5) * 0.0032;
            break;
          case 2: // 右
            petal.vx = 0.0048 + random.nextDouble() * 0.0032; // 0.0048 ~ 0.008
            petal.vy = (random.nextDouble() - 0.5) * 0.0032;
            break;
          case 3: // 下右
            petal.vx = 0.0032 + random.nextDouble() * 0.0024; // 0.0032 ~ 0.0056
            petal.vy = 0.0032 + random.nextDouble() * 0.0024;
            break;
          case 4: // 下左
            petal.vx = -0.0032 - random.nextDouble() * 0.0024; // -0.0032 ~ -0.0056
            petal.vy = 0.0032 + random.nextDouble() * 0.0024;
            break;
        }
      }
    }
  }
  
  /// 检测坐标是否在地面区域（花瓣可堆积的区域）- 使用相对坐标
  bool _isOnGroundRelative(double x, double y) {
    // 地面位置更低一点（从0.93降至0.95）
    const groundTopRel = 0.95;
    const navBarBottomRel = 0.995;
    
    // 检查是否在导航栏区域内（水平边距16px）
    const horizontalMargin = 16.0 / 375.0;
    if (y >= groundTopRel && y <= navBarBottomRel && 
        x >= horizontalMargin && x <= (1.0 - horizontalMargin)) {
      return true;
    }
    
    return false;
  }
  
  /// 获取地面的Y坐标范围（轻飘飘的随机堆积，不精确吸附）
  double _getGroundYRelative(double x) {
    // 基础地面位置（更低）
    const baseGround = 0.95;
    // 添加随机偏移，模拟轻飘飘的自然堆积（0-15px的随机高度）
    final randomOffset = random.nextDouble() * 0.018; 
    return baseGround + randomOffset;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF5F7),
            Color(0xFFFFE4E8),
            Color(0xFFFCE4EC),
            Color(0xFFF8BBD0),
          ],
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          _triggerChaos();
          
          // 生成花朵检查（2秒一次，提高概率）
          _flowerSpawnCounter++;
          if (_flowerSpawnCounter > 120) { // 2秒检查一次（从3秒加快）
            _flowerSpawnCounter = 0;
            if (random.nextDouble() < 0.60) { // 60%概率生成（从45%提高）
              _spawnFlower();
            }
          }
          
          // 更新花朵位置（添加碰撞和消散逻辑）
          for (var flower in flowers) {
            if (flower.isLanded) {
              // 已落地：渐隐消散
              flower.life -= 0.003; // 约5秒消散
              // 渐隐：从1.0到0.0线性减少
              flower.opacity = flower.life.clamp(0.0, 1.0);
              continue;
            }
            
            if (_isChaos && flower.chaosTimer > 0) {
              // 混乱状态：随机运动 + 碰撞
              flower.x += flower.vx;
              flower.y += flower.vy;
              flower.rotation += flower.rotationSpeed * 2;
              flower.chaosTimer--;
              
              // 边界反弹
              if (flower.x < 0 || flower.x > 1) flower.vx *= -0.8;
              if (flower.y < 0 || flower.y > 1) flower.vy *= -0.8;
              
              // 混乱结束恢复
              if (flower.chaosTimer <= 0) {
                flower.vx = 0;
                flower.vy = 0;
              }
            } else if (_isChaos && flower.chaosTimer == 0) {
              // 进入混乱状态 - 上左右向下右左的来向（力度减轻20%）
              final direction = random.nextInt(5);
              switch (direction) {
                case 0: // 上
                  flower.vx = (random.nextDouble() - 0.5) * 0.006;
                  flower.vy = -0.0096 - random.nextDouble() * 0.0064;
                  break;
                case 1: // 左
                  flower.vx = -0.0096 - random.nextDouble() * 0.0064;
                  flower.vy = (random.nextDouble() - 0.5) * 0.006;
                  break;
                case 2: // 右
                  flower.vx = 0.0096 + random.nextDouble() * 0.0064;
                  flower.vy = (random.nextDouble() - 0.5) * 0.006;
                  break;
                case 3: // 下右
                  flower.vx = 0.0064 + random.nextDouble() * 0.0048;
                  flower.vy = 0.0064 + random.nextDouble() * 0.0048;
                  break;
                case 4: // 下左
                  flower.vx = -0.0064 - random.nextDouble() * 0.0048;
                  flower.vy = 0.0064 + random.nextDouble() * 0.0048;
                  break;
              }
              flower.chaosTimer = _chaosTimer.toDouble();
            } else if (!flower.isLanded) {
              // 正常飘落（未落地时）
              flower.y += flower.speed * 0.008;
              flower.rotation += flower.rotationSpeed;
            } else {
              // 已落地：轻飘飘滑动，不再下落
              flower.vx *= 0.95;
              flower.vy = 0; // 停止垂直运动
              flower.speed *= 0.9;
              // 水平方向轻微滑动
              flower.x += flower.vx;
              flower.rotation += flower.rotationSpeed * 0.3;
              // 限制y在地面区域
              final groundY = _getGroundYRelative(flower.x);
              if (flower.y > groundY) {
                flower.y = groundY + (random.nextDouble() - 0.5) * 0.01;
              }
            }
            
            // 检测是否落到地面
            if (!flower.isLanded && _isOnGroundRelative(flower.x, flower.y)) {
              flower.isLanded = true;
              flower.life = 1.0;
              // 落地时轻微反弹效果（可选）
              flower.vx = (random.nextDouble() - 0.5) * 0.005;
              flower.vy = 0;
            }
            
            // 超出屏幕循环
            if (flower.y > 1.15 && !flower.isLanded) {
              flower.y = -0.2;
              flower.x = random.nextDouble() * 0.8 + 0.1;
              flower.isLanded = false;
              flower.life = 1.0;
              flower.opacity = random.nextDouble() * 0.15 + 0.85;
            }
          }
          
          // 移除已消散的花朵
          flowers.removeWhere((f) => f.isLanded && f.life <= 0);
          
          // 更新混乱状态 - 带过渡效果
          if (_isChaos) {
            _chaosTimer--;
            // 强度过渡：前40帧渐入（延长），中间40帧保持，后40帧渐出（延长）
            if (_chaosTimer > 80) {
              _chaosIntensity = (120 - _chaosTimer) / 40; // 0 -> 1 (40帧渐入)
            } else if (_chaosTimer < 40) {
              _chaosIntensity = _chaosTimer / 40; // 1 -> 0 (40帧渐出)
            } else {
              _chaosIntensity = 1.0; // 40帧保持
            }
            
            if (_chaosTimer <= 0) {
              _isChaos = false;
              _chaosIntensity = 0.0;
            }
          } else {
            _chaosIntensity = 0.0;
          }
          
          // 更新飘落花瓣
          for (var petal in petals) {
            if (_isChaos || _chaosIntensity > 0) {
              // 混乱状态：随机运动（带强度过渡）
              petal.x += petal.vx * _chaosIntensity;
              petal.y += petal.vy * _chaosIntensity;
              petal.rotation += petal.rotationSpeed * 3 * _chaosIntensity;
              
              // 边界反弹
              if (petal.x < 0 || petal.x > 1) petal.vx *= -0.8;
              if (petal.y < 0 || petal.y > 1) petal.vy *= -0.8;
              
              // 混乱结束时逐渐减速
              if (!_isChaos) {
                petal.vx *= 0.95;
                petal.vy *= 0.95;
              }
            } else {
              // 正常飘落
              petal.y += petal.speed * 0.008;
              petal.rotation += petal.rotationSpeed;
            }
            
            // 检测是否落到地面 - 轻飘飘堆积
            if (!petal.life.isNaN && _isOnGroundRelative(petal.x, petal.y)) {
              // 轻飘飘地转移到落地花瓣，不瞬移
              landedPetals.add(SakuraPetal(
                x: petal.x + (random.nextDouble() - 0.5) * 0.01, // 轻微随机偏移
                y: petal.y, // 保持当前y位置，不瞬移
                size: petal.size,
                speed: 0, // 落地后停止下落
                rotation: petal.rotation,
                rotationSpeed: petal.rotationSpeed * 0.1, // 缓慢旋转
                opacity: petal.opacity,
                color: petal.color,
                vx: (random.nextDouble() - 0.5) * 0.001, // 极轻微水平滑动
                vy: 0, // 停止垂直运动，不反弹
                life: 1.0,
              ));
              // 重置飘落花瓣
              petal.y = -0.1;
              petal.x = random.nextDouble();
            }
            
            // 循环
            if (petal.y > 1.15) {
              petal.y = -0.1;
              petal.x = random.nextDouble();
            }
          }
          
          // 更新落地花瓣 - 轻飘飘滑动效果
          for (var petal in landedPetals) {
            petal.life -= 0.004; // 4秒消失
            // 渐隐
            if (petal.life < 0.5) {
              petal.opacity = petal.life * 2;
            }
            // 轻微滑动，模拟轻飘飘堆积
            petal.x += petal.vx;
            petal.y += petal.vy;
            // 减速
            petal.vx *= 0.98;
            petal.vy *= 0.98;
            // 轻微旋转
            petal.rotation += petal.rotationSpeed;
            petal.rotationSpeed *= 0.95;
          }
          landedPetals.removeWhere((p) => p.life <= 0);
          
          return CustomPaint(
            painter: SakuraPainter(
              petals: petals,
              landedPetals: landedPetals,
              flowers: flowers,
              progress: _controller.value,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

class SakuraPetal {
  double x, y, rotation, opacity, vx, vy, life;
  final double size, speed;
  double rotationSpeed; // 改为非 final，支持减速
  final Color color;

  SakuraPetal({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.opacity,
    required this.color,
    required this.vx,
    required this.vy,
    this.life = 1.0,
  });
}

/// 完整樱花花朵 - 比花瓣大，低频率出现
class SakuraFlower {
  double x, y, rotation, opacity, vx, vy, life;
  final double size;
  double speed; // 改为非 final，支持减速
  double rotationSpeed; // 改为非 final
  final Color color;
  bool isLanded; // 是否已落地
  double chaosTimer; // 混乱状态计时

  SakuraFlower({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.opacity,
    required this.color,
    this.vx = 0,
    this.vy = 0,
    this.life = 1.0,
    this.isLanded = false,
    this.chaosTimer = 0,
  });
}

class SakuraPainter extends CustomPainter {
  final List<SakuraPetal> petals;
  final List<SakuraPetal> landedPetals;
  final List<SakuraFlower> flowers;
  final double progress;

  SakuraPainter({
    required this.petals,
    required this.landedPetals,
    required this.flowers,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制完整花朵（在花瓣下方，更大更淡雅）
    for (var flower in flowers) {
      _drawFlower(canvas, size, flower);
    }
    
    // 绘制落地花瓣（在底部）
    for (var petal in landedPetals) {
      _drawPetal(canvas, size, petal, true);
    }
    
    // 绘制飘落花瓣
    for (var petal in petals) {
      _drawPetal(canvas, size, petal, false);
    }
  }

  void _drawPetal(Canvas canvas, Size size, SakuraPetal petal, bool isLanded) {
    final center = Offset(petal.x * size.width, petal.y * size.height);
    
    final paint = Paint()
      ..color = petal.color.withValues(alpha: petal.opacity.clamp(0, 1))
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(petal.rotation);

    // 简化的樱花花瓣形状
    final path = Path();
    path.moveTo(0, -petal.size);
    path.quadraticBezierTo(petal.size * 0.5, -petal.size * 0.3, 0, petal.size * 0.8);
    path.quadraticBezierTo(-petal.size * 0.5, -petal.size * 0.3, 0, -petal.size);
    canvas.drawPath(path, paint);

    canvas.restore();
  }
  
  /// 绘制完整樱花花朵 - 唯美樱花形状，心形花瓣
  void _drawFlower(Canvas canvas, Size size, SakuraFlower flower) {
    final center = Offset(flower.x * size.width, flower.y * size.height);
    final petalCount = 5;
    final pSize = flower.size;
    
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(flower.rotation);
    
    // 应用花朵整体透明度（用于渐隐效果）
    final flowerOpacity = flower.opacity.clamp(0.0, 1.0);
    
    // 花瓣渐变色 - 从中心浅到边缘深（应用整体透明度）
    for (int i = 0; i < petalCount; i++) {
      final angle = (i / petalCount) * pi * 2;
      
      canvas.save();
      canvas.rotate(angle);
      
      // 唯美心形花瓣路径
      final path = Path();
      // 从心形底部开始
      path.moveTo(0, pSize * 0.2);
      // 左侧心形曲线（两个弧形形成心形凹陷）
      path.cubicTo(
        -pSize * 0.7, -pSize * 0.3,  // 控制点1：左侧外扩
        -pSize * 0.5, -pSize * 1.0,  // 控制点2：向上收窄
        0, -pSize * 1.2              // 顶点：心形尖端
      );
      // 右侧心形曲线
      path.cubicTo(
        pSize * 0.5, -pSize * 1.0,   // 控制点1
        pSize * 0.7, -pSize * 0.3,   // 控制点2
        0, pSize * 0.2               // 回到底部
      );
      path.close();
      
      // 花瓣渐变填充（应用整体透明度）
      final gradient = RadialGradient(
        center: const Alignment(0, 0.3),
        radius: 0.8,
        colors: [
          flower.color.withValues(alpha: 0.9 * flowerOpacity),           // 中心较深
          flower.color.withValues(alpha: 0.7 * flowerOpacity),           // 中间
          flower.color.withValues(alpha: 0.4 * flowerOpacity),           // 边缘渐淡
        ],
      );
      
      final petalPaint = Paint()
        ..shader = gradient.createShader(
          Rect.fromCenter(center: Offset.zero, width: pSize * 2.4, height: pSize * 2.8),
        )
        ..style = PaintingStyle.fill;
      
      canvas.drawPath(path, petalPaint);
      
      // 柔和的边缘线（应用整体透明度）
      final edgePaint = Paint()
        ..color = flower.color.withValues(alpha: 0.6 * flowerOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawPath(path, edgePaint);
      
      canvas.restore();
    }
    
    // 绘制花心（柔和渐变，应用整体透明度）
    final centerGradient = RadialGradient(
      colors: [
        const Color(0xFFFFFACD).withValues(alpha: 0.9 * flowerOpacity), // 浅黄色中心
        const Color(0xFFFFE4B5).withValues(alpha: 0.6 * flowerOpacity), // 过渡
        Colors.transparent,
      ],
    );
    
    canvas.drawCircle(
      Offset.zero,
      pSize * 0.35,
      Paint()
        ..shader = centerGradient.createShader(
          Rect.fromCenter(center: Offset.zero, width: pSize * 0.7, height: pSize * 0.7),
        )
        ..style = PaintingStyle.fill,
    );
    
    // 花蕊细节（更精致，应用整体透明度）
    for (int i = 0; i < 5; i++) {
      final dotAngle = i * pi * 2 / 5;
      final dotX = cos(dotAngle) * pSize * 0.15;
      final dotY = sin(dotAngle) * pSize * 0.15;
      // 花蕊渐变点（应用整体透明度）
      final stamenGradient = RadialGradient(
        colors: [
          const Color(0xFFFFD700).withValues(alpha: flowerOpacity), // 金黄中心
          const Color(0xFFFFA500).withValues(alpha: flowerOpacity), // 橙色边缘
        ],
      );
      canvas.drawCircle(
        Offset(dotX, dotY),
        pSize * 0.08,
        Paint()
          ..shader = stamenGradient.createShader(
            Rect.fromCenter(center: Offset(dotX, dotY), width: pSize * 0.16, height: pSize * 0.16),
          )
          ..style = PaintingStyle.fill,
      );
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==================== 🌊 海洋主题（完美循环+海洋生物版）====================
class OceanBackground extends StatefulWidget {
  final Widget child;
  const OceanBackground({super.key, required this.child});

  @override
  State<OceanBackground> createState() => _OceanBackgroundState();
}

class _OceanBackgroundState extends State<OceanBackground>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _bubbleController;
  
  // 海洋生物系统
  late AnimationController _creatureController;
  final List<SeaCreature> creatures = [];
  Timer? _creatureSpawnTimer;
  
  final List<Bubble> bubbles = [];
  final Random random = Random();

  @override
  void initState() {
    super.initState();
    
    // 波浪动画 - 完美循环（4秒整数周期）
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    
    // 气泡动画
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // 海洋生物动画
    _creatureController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // 初始化气泡
    for (int i = 0; i < 15; i++) {
      bubbles.add(Bubble(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: random.nextDouble() * 5 + 2,
        speed: random.nextDouble() * 0.3 + 0.1,
        opacity: random.nextDouble() * 0.4 + 0.2,
        wobble: random.nextDouble() * pi * 2,
      ));
    }
    
    // 启动海洋生物生成循环
    _startCreatureSpawner();
    
    // 立即生成第一个生物，让用户立即看到效果
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _spawnCreature();
    });
  }
  
  void _startCreatureSpawner() {
    // 低频率生成：6-15秒间隔（缩短间隔）
    void scheduleNext() {
      final delay = 6 + random.nextInt(10); // 6-15秒
      _creatureSpawnTimer = Timer(Duration(seconds: delay), () {
        if (!mounted) return;
        _spawnCreature();
        scheduleNext();
      });
    }
    scheduleNext();
  }
  
  void _spawnCreature() {
    // 最多同时3个生物
    if (creatures.length >= 3) return;
    
    // 70%概率生成鱼，20%概率生成海龟，10%概率生成虾
    final roll = random.nextDouble();
    final type = roll < 0.7 
        ? CreatureType.fish 
        : roll < 0.9 
            ? CreatureType.turtle 
            : CreatureType.shrimp;
    
    // 随机方向：从左到右或从右到左
    final fromLeft = random.nextBool();
    
    // 增大生物尺寸，使其更明显可见
    creatures.add(SeaCreature(
      type: type,
      x: fromLeft ? -0.15 : 1.15, // 起始位置更远，有进入动画感
      y: 0.35 + random.nextDouble() * 0.4, // 在中下层水域
      size: type == CreatureType.turtle 
          ? random.nextDouble() * 20 + 35  // 海龟：35-55（明显增大）
          : type == CreatureType.fish 
              ? random.nextDouble() * 18 + 22  // 鱼：22-40（明显增大）
              : random.nextDouble() * 15 + 18, // 虾：18-33（明显增大）
      speed: type == CreatureType.turtle 
          ? random.nextDouble() * 0.15 + 0.08  // 海龟慢
          : type == CreatureType.fish 
              ? random.nextDouble() * 0.35 + 0.25  // 鱼中等
              : random.nextDouble() * 0.45 + 0.35, // 虾较快
      fromLeft: fromLeft,
      wigglePhase: random.nextDouble() * pi * 2,
      color: _getCreatureColor(type),
    ));
  }
  
  Color _getCreatureColor(CreatureType type) {
    switch (type) {
      case CreatureType.fish:
        final colors = [
          const Color(0xFFFFB74D), // 橙色
          const Color(0xFF4FC3F7), // 蓝色
          const Color(0xFFFFF176), // 黄色
          const Color(0xFFFF8A65), // 珊瑚色
          const Color(0xFFBA68C8), // 紫色
        ];
        return colors[random.nextInt(colors.length)];
      case CreatureType.turtle:
        return const Color(0xFF66BB6A); // 绿色
      case CreatureType.shrimp:
        return const Color(0xFFFF8A80); // 粉红色
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _bubbleController.dispose();
    _creatureController.dispose();
    _creatureSpawnTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE3F2FD), // 浅天蓝
            Color(0xFFBBDEFB), // 天蓝
            Color(0xFF90CAF9), // 中蓝
            Color(0xFF64B5F6), // 深天蓝
          ],
        ),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _waveController, 
          _bubbleController,
          _creatureController,
        ]),
        builder: (context, _) {
          // 更新气泡位置
          for (var bubble in bubbles) {
            bubble.y -= bubble.speed * 0.008;
            bubble.wobble += 0.015;
            if (bubble.y < -0.1) {
              bubble.y = 1.1;
              bubble.x = random.nextDouble();
            }
          }
          
          // 更新海洋生物位置
          for (var creature in creatures) {
            creature.x += creature.fromLeft ? creature.speed * 0.01 : -creature.speed * 0.01;
            creature.wigglePhase += creature.type == CreatureType.shrimp ? 0.3 : 0.08;
          }
          // 移除已游出屏幕的生物
          creatures.removeWhere((c) => 
            c.fromLeft ? c.x > 1.2 : c.x < -0.2
          );
          
          return CustomPaint(
            painter: OceanPainter(
              progress: _waveController.value,
              bubbles: bubbles,
              creatures: creatures,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

// 海洋生物类型
enum CreatureType { fish, turtle, shrimp }

// 海洋生物数据
class SeaCreature {
  final CreatureType type;
  double x, y;
  final double size;
  final double speed;
  final bool fromLeft;
  double wigglePhase;
  final Color color;

  SeaCreature({
    required this.type,
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.fromLeft,
    required this.wigglePhase,
    required this.color,
  });
}

class Bubble {
  double x, y, wobble;
  final double size, speed, opacity;

  Bubble({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
    required this.wobble,
  });
}

class OceanPainter extends CustomPainter {
  final double progress;
  final List<Bubble> bubbles;
  final List<SeaCreature> creatures;

  OceanPainter({
    required this.progress, 
    required this.bubbles,
    required this.creatures,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制后两层波浪（背景）
    _drawWave(canvas, size, 0.78, const Color(0xFF90CAF9), 1.0, 20, 0.25);
    _drawWave(canvas, size, 0.84, const Color(0xFFBBDEFB), 1.5, 16, 0.20);
    
    // 绘制海洋生物（在中间层，在前两层波浪之后，后两层之前）
    for (var creature in creatures) {
      _drawCreature(canvas, size, creature);
    }
    
    // 绘制前两波浪（前景，半透明，让生物可见）
    _drawWave(canvas, size, 0.65, const Color(0xFF42A5F5), 0.0, 28, 0.20);
    _drawWave(canvas, size, 0.72, const Color(0xFF64B5F6), 0.5, 24, 0.25);
    
    // 绘制波光（在波浪上的闪烁点）
    _drawSparkles(canvas, size);
    
    // 绘制气泡（最前景）
    for (var bubble in bubbles) {
      _drawBubble(canvas, size, bubble);
    }
  }

  void _drawWave(Canvas canvas, Size size, double yOffset, Color color,
      double phaseOffset, double amplitude, double opacity) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height);

    // 完美循环：所有波形使用整数倍频率，确保4秒周期无缝循环
    final t = progress * 2 * pi;
    
    for (double x = 0; x <= size.width; x += 2) {
      final nx = x / size.width * 2 * pi;
      
      // 关键：所有t的系数必须是整数，才能在4秒后回到原点
      // sin(nx + t) 周期 = 2π
      // sin(nx * 2 - t * 2) 周期 = π，4秒后循环2次，位置相同
      // sin(nx * 3 + t * 3) 周期 = 2π/3，4秒后循环6次，位置相同
      final y = size.height * yOffset +
          sin(nx + t + phaseOffset) * amplitude * 0.6 +
          sin(nx * 2 - t * 2 + phaseOffset) * amplitude * 0.3 +  // 改为t*2
          sin(nx * 3 + t * 3) * amplitude * 0.1;                   // 改为t*3
          
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }
  
  void _drawCreature(Canvas canvas, Size size, SeaCreature creature) {
    final centerX = creature.x * size.width;
    final centerY = creature.y * size.height;
    final wiggle = sin(creature.wigglePhase) * 3; // 摆动幅度
    
    switch (creature.type) {
      case CreatureType.fish:
        _drawFish(canvas, centerX, centerY + wiggle, creature);
        break;
      case CreatureType.turtle:
        _drawTurtle(canvas, centerX, centerY + wiggle * 0.5, creature);
        break;
      case CreatureType.shrimp:
        _drawShrimp(canvas, centerX, centerY + wiggle, creature);
        break;
    }
  }
  
  void _drawFish(Canvas canvas, double x, double y, SeaCreature fish) {
    final size = fish.size;
    final direction = fish.fromLeft ? 1 : -1;
    
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(direction.toDouble(), 1);
    
    // 添加白色轮廓/阴影，使其在蓝色背景下更明显
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // 鱼身（椭圆）
    final bodyPaint = Paint()
      ..color = fish.color
      ..style = PaintingStyle.fill;
    
    final bodyRect = Rect.fromCenter(center: Offset.zero, width: size * 1.8, height: size);
    canvas.drawOval(bodyRect, bodyPaint);
    canvas.drawOval(bodyRect, outlinePaint); // 轮廓
    
    // 鱼尾（三角形）
    final tailPath = Path()
      ..moveTo(-size * 0.8, 0)
      ..lineTo(-size * 1.4, -size * 0.5)
      ..lineTo(-size * 1.4, size * 0.5)
      ..close();
    canvas.drawPath(tailPath, bodyPaint);
    canvas.drawPath(tailPath, outlinePaint); // 轮廓
    
    // 背鳍
    final dorsalPath = Path()
      ..moveTo(0, -size * 0.4)
      ..lineTo(-size * 0.3, -size * 0.8)
      ..lineTo(size * 0.3, -size * 0.5)
      ..close();
    canvas.drawPath(dorsalPath, bodyPaint);
    canvas.drawPath(dorsalPath, outlinePaint); // 轮廓
    
    // 眼睛（加大）
    canvas.drawCircle(
      Offset(size * 0.5, -size * 0.15),
      size * 0.2,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size * 0.55, -size * 0.15),
      size * 0.12,
      Paint()..color = Colors.black,
    );
    // 眼睛高光
    canvas.drawCircle(
      Offset(size * 0.58, -size * 0.18),
      size * 0.04,
      Paint()..color = Colors.white,
    );
    
    canvas.restore();
  }
  
  void _drawTurtle(Canvas canvas, double x, double y, SeaCreature turtle) {
    final size = turtle.size;
    
    canvas.save();
    canvas.translate(x, y);
    
    // 白色轮廓画笔
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // 四肢（简单线条）
    final limbPaint = Paint()
      ..color = const Color(0xFF81C784) // 更亮的绿色
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.18
      ..strokeCap = StrokeCap.round;
    
    // 四肢（带轮廓）
    final limbOffsets = [
      [Offset(-size * 0.3, -size * 0.2), Offset(-size * 0.7, -size * 0.5)],
      [Offset(size * 0.3, -size * 0.2), Offset(size * 0.7, -size * 0.5)],
      [Offset(-size * 0.3, size * 0.2), Offset(-size * 0.7, size * 0.5)],
      [Offset(size * 0.3, size * 0.2), Offset(size * 0.7, size * 0.5)],
    ];
    for (final offsets in limbOffsets) {
      canvas.drawLine(offsets[0], offsets[1], limbPaint);
      canvas.drawLine(offsets[0], offsets[1], outlinePaint);
    }
    
    // 龟壳（圆形，带轮廓）
    final shellPaint = Paint()
      ..color = const Color(0xFF43A047) // 更亮的绿色
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, size * 0.6, shellPaint);
    canvas.drawCircle(Offset.zero, size * 0.6, outlinePaint);
    
    // 龟壳花纹（六边形）
    final hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3;
      final px = cos(angle) * size * 0.35;
      final py = sin(angle) * size * 0.35;
      if (i == 0) {
        hexPath.moveTo(px, py);
      } else {
        hexPath.lineTo(px, py);
      }
    }
    hexPath.close();
    final hexPaint = Paint()
      ..color = const Color(0xFF66BB6A)
      ..style = PaintingStyle.fill;
    canvas.drawPath(hexPath, hexPaint);
    canvas.drawPath(hexPath, outlinePaint);
    
    // 头部（带轮廓）
    final headPaint = Paint()
      ..color = const Color(0xFF81C784)
      ..style = PaintingStyle.fill;
    final headCenter = Offset(0, -size * 0.8);
    canvas.drawCircle(headCenter, size * 0.35, headPaint);
    canvas.drawCircle(headCenter, size * 0.35, outlinePaint);
    
    // 眼睛（加大）
    canvas.drawCircle(
      Offset(-size * 0.15, -size * 0.85),
      size * 0.1,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(-size * 0.15, -size * 0.85),
      size * 0.05,
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(
      Offset(size * 0.15, -size * 0.85),
      size * 0.1,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size * 0.15, -size * 0.85),
      size * 0.05,
      Paint()..color = Colors.black,
    );
    
    canvas.restore();
  }
  
  void _drawShrimp(Canvas canvas, double x, double y, SeaCreature shrimp) {
    final size = shrimp.size;
    final direction = shrimp.fromLeft ? 1 : -1;
    
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(direction.toDouble(), 1);
    
    // 白色轮廓画笔
    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    // 更亮的身体颜色
    final bodyPaint = Paint()
      ..color = const Color(0xFFFFAB91) // 更亮的珊瑚色
      ..style = PaintingStyle.fill;
    
    // 虾身（分段）
    final segments = 5;
    for (int i = 0; i < segments; i++) {
      final segmentX = -size * 0.3 * i;
      final segmentSize = size * (1 - i * 0.12);
      canvas.drawCircle(
        Offset(segmentX, 0),
        segmentSize * 0.4,
        bodyPaint,
      );
      canvas.drawCircle(
        Offset(segmentX, 0),
        segmentSize * 0.4,
        outlinePaint,
      );
    }
    
    // 虾尾（扇形）
    final tailPath = Path()
      ..moveTo(-size * 1.5, 0)
      ..lineTo(-size * 2.0, -size * 0.4)
      ..lineTo(-size * 2.2, 0)
      ..lineTo(-size * 2.0, size * 0.4)
      ..close();
    canvas.drawPath(tailPath, bodyPaint);
    canvas.drawPath(tailPath, outlinePaint);
    
    // 虾头
    final headRect = Rect.fromCenter(center: Offset(size * 0.3, 0), width: size * 0.8, height: size * 0.6);
    canvas.drawOval(headRect, bodyPaint);
    canvas.drawOval(headRect, outlinePaint);
    
    // 眼睛（明显）
    canvas.drawCircle(
      Offset(size * 0.5, -size * 0.1),
      size * 0.15,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size * 0.5, -size * 0.1),
      size * 0.08,
      Paint()..color = Colors.black,
    );
    
    // 长触须（白色）
    final antennaPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    final antennaPath = Path()
      ..moveTo(size * 0.5, -size * 0.15)
      ..quadraticBezierTo(size * 1.5, -size * 0.9, size * 2.0, -size * 0.4);
    canvas.drawPath(antennaPath, antennaPaint);
    
    final antennaPath2 = Path()
      ..moveTo(size * 0.5, size * 0.15)
      ..quadraticBezierTo(size * 1.5, size * 0.9, size * 2.0, size * 0.4);
    canvas.drawPath(antennaPath2, antennaPaint);
    
    canvas.restore();
  }
  
  void _drawSparkles(Canvas canvas, Size size) {
    // 在波浪上绘制闪烁的光点 - 完美循环
    final t = progress * 2 * pi;
    
    for (int i = 0; i < 20; i++) {
      final x = (i * 47) % 100 / 100;
      final phase = (i * 0.3) % (pi * 2);
      
      // 整数倍频率确保循环
      final sparkleOpacity = 0.3 + 0.5 * sin(t * 2 + phase);
      
      if (sparkleOpacity > 0.5) {
        final center = Offset(
          x * size.width,
          size.height * 0.75 + sin(t + x * 10) * 15,
        );
        
        canvas.drawCircle(
          center,
          2,
          Paint()
            ..color = Colors.white.withValues(alpha: sparkleOpacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      }
    }
  }
  
  void _drawBubble(Canvas canvas, Size size, Bubble bubble) {
    final x = bubble.x + sin(bubble.wobble) * 0.015;
    final center = Offset(x * size.width, bubble.y * size.height);
    
    // 气泡主体
    canvas.drawCircle(
      center,
      bubble.size,
      Paint()
        ..color = Colors.white.withValues(alpha: bubble.opacity * 0.5)
        ..style = PaintingStyle.fill,
    );
    
    // 气泡高光
    canvas.drawCircle(
      Offset(center.dx - bubble.size * 0.3, center.dy - bubble.size * 0.3),
      bubble.size * 0.3,
      Paint()
        ..color = Colors.white.withValues(alpha: bubble.opacity * 0.9)
        ..style = PaintingStyle.fill,
    );
    
    // 气泡边缘
    canvas.drawCircle(
      center,
      bubble.size,
      Paint()
        ..color = Colors.white.withValues(alpha: bubble.opacity * 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==================== 🌌 极光主题（纯绿色系+完美循环）====================
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

/// 极光星星数据 - 位置固定，但随机生成
class AuroraStar {
  final double x, y, size, phase, speed;
  
  AuroraStar({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.speed,
  });
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late final List<AuroraStar> _stars;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    
    // 生成8颗随机位置的星星 - 只在init时生成一次，生命周期内不变
    _stars = List.generate(8, (index) {
      return AuroraStar(
        x: _random.nextDouble() * 0.9 + 0.05, // 5%-95%范围
        y: _random.nextDouble() * 0.6 + 0.1,  // 10%-70%范围（避免底部波浪区域）
        size: _random.nextDouble() * 1.5 + 0.8, // 0.8-2.3大小
        phase: _random.nextDouble() * pi * 2,
        speed: _random.nextDouble() * 1.5 + 0.5,
      );
    });
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // 减缓至80% (4/0.8=5)
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF020C10), // 极深青黑（夜间背景）
            Color(0xFF061915), // 深青绿黑
            Color(0xFF082820), // 青绿黑（稍微带绿）
            Color(0xFF020C10),
          ],
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: PureGreenAuroraPainter(
              progress: _controller.value,
              stars: _stars,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

class PureGreenAuroraPainter extends CustomPainter {
  final double progress;
  final List<AuroraStar> stars;

  PureGreenAuroraPainter({
    required this.progress,
    required this.stars,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 先绘制星星（在最底层）
    _drawStars(canvas, size);
    
    // 三层翠绿色极光 - 亮度132%(120%*110%)，宽度110%，距离110%，速度80%
    _drawLayer(canvas, size, [
      const Color(0xFF39FF14), // 霓虹绿
      const Color(0xFF00E676), // 亮翠绿
      const Color(0xFF00C853), // 翠绿
    ], 0.22, 0.0, 0.075 * 1.1, 0, brightnessMul: 1.32);  // 亮度132%(120%*110%)
    
    _drawLayer(canvas, size, [
      const Color(0xFF76FF03), // 酸橙绿
      const Color(0xFF69F0AE), // 薄荷绿
      const Color(0xFF00E676), // 亮翠绿
    ], 0.38, 0.33, 0.065 * 1.1, 1, brightnessMul: 1.32);
    
    _drawLayer(canvas, size, [
      const Color(0xFF00E5FF), // 青色
      const Color(0xFF00BFA5), // 青绿
      const Color(0xFF00B248), // 深翠绿
    ], 0.54, 0.67, 0.055 * 1.1, 2, brightnessMul: 1.32);
  }
  
  /// 绘制闪烁星星 - 使用整数倍频率确保循环
  void _drawStars(Canvas canvas, Size size) {
    final time = progress * 2 * pi;
    
    for (var star in stars) {
      // 闪烁效果 - 使用整数倍速度确保同步循环
      final twinkle = sin(time * star.speed.toInt() + star.phase);
      final opacity = 0.5 + 0.5 * twinkle; // 0.5-1.0之间闪烁
      
      final center = Offset(star.x * size.width, star.y * size.height);
      
      // 绘制星星光晕
      canvas.drawCircle(
        center,
        star.size * 2,
        Paint()
          ..color = Colors.white.withValues(alpha: opacity * 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      
      // 绘制星星核心（黄白色）
      canvas.drawCircle(
        center,
        star.size,
        Paint()
          ..color = Color.fromRGBO(
            255,
            255,
            220 + (twinkle * 35).toInt(), // 220-255变化
            opacity,
          )
          ..style = PaintingStyle.fill,
      );
    }
  }

  /// 绘制单层极光 - 完美循环版：整数倍频率确保无缝循环
  void _drawLayer(Canvas canvas, Size size, List<Color> colors, 
      double yCenter, double phaseOffset, double amplitude, int layerIndex,
      {double brightnessMul = 1.0}) {
    
    final centerY = size.height * yCenter;
    final amp = size.height * amplitude;
    final t = progress * 2 * pi;
    
    // 每层独特的参数配置 - 使用整数倍频率确保完美循环
    final layerConfigs = [
      // 第一层：最亮最宽，基础频率 1x
      _AuroraLayerConfig(
        speedMul: 1, amplitudeMul: 1.2, yOffsetMul: 0.0,
        waveFreq1: 1, waveFreq2: 2, waveFreq3: 0,
        blur: 18, opacityMul: 1.0,
      ),
      // 第二层：中等，2倍速流动 2x
      _AuroraLayerConfig(
        speedMul: 2, amplitudeMul: 0.9, yOffsetMul: 0.02,
        waveFreq1: 1, waveFreq2: 2, waveFreq3: 4,
        blur: 25, opacityMul: 0.8,
      ),
      // 第三层：最宽，4倍速 4x
      _AuroraLayerConfig(
        speedMul: 4, amplitudeMul: 0.7, yOffsetMul: -0.015,
        waveFreq1: 2, waveFreq2: 4, waveFreq3: 0,
        blur: 35, opacityMul: 0.6,
      ),
    ];
    
    final config = layerConfigs[layerIndex % 3];
    final path = Path();
    // 使用整数相位偏移，确保循环一致性
    final layerPhase = layerIndex * pi; // 0, π, 2π - 整数倍
    // 使用整数倍速确保循环同步：t * 1, t * 2, t * 4 在 2π 周期后同时回到起点
    final layerT = t * config.speedMul;
    
    // 大步长减少计算点（5像素步长）
    path.moveTo(0, size.height);
    
    for (double x = 0; x <= size.width; x += 5) {
      final nx = x / size.width * 2 * pi;
      
      // 每层使用不同的波形组合 - 所有频率都是整数，确保完美循环
      double y = centerY + config.yOffsetMul * size.height;
      
      // 主波 - 整数频率，同向流动
      if (config.waveFreq1 > 0) {
        y += sin(nx * config.waveFreq1 + layerT + layerPhase) * amp * config.amplitudeMul * 0.55;
      }
      // 次波 - 整数频率，反向流动制造动感（用 -layerT）
      if (config.waveFreq2 > 0) {
        y += sin(nx * config.waveFreq2 - layerT + layerPhase) * amp * config.amplitudeMul * 0.30;
      }
      // 细节波 - 整数频率，同向但更快
      if (config.waveFreq3 > 0) {
        y += sin(nx * config.waveFreq3 + layerT + layerPhase) * amp * config.amplitudeMul * 0.15;
      }
      
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    // 增强的呼吸效果 - 使用与速度同步的整数倍周期，应用亮度倍数
    final breath = (0.45 + 0.25 * sin(layerT)) * brightnessMul;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colors[0].withValues(alpha: breath * config.opacityMul),
          colors[1].withValues(alpha: breath * 0.5 * config.opacityMul),
          colors[2].withValues(alpha: breath * 0.2 * config.opacityMul),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, centerY - amp, size.width, amp * 3))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, config.blur.toDouble());

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 极光层配置
class _AuroraLayerConfig {
  final int speedMul;        // 速度倍数（整数倍确保循环同步：1, 2, 4）
  final double amplitudeMul; // 振幅倍数
  final double yOffsetMul;   // 垂直偏移（相对屏幕高度）
  final int waveFreq1;       // 主波频率
  final int waveFreq2;       // 次波频率
  final int waveFreq3;       // 细节波频率
  final double blur;         // 模糊半径
  final double opacityMul;   // 不透明度倍数
  
  _AuroraLayerConfig({
    required this.speedMul,
    required this.amplitudeMul,
    required this.yOffsetMul,
    required this.waveFreq1,
    required this.waveFreq2,
    required this.waveFreq3,
    required this.blur,
    required this.opacityMul,
  });
}

// ==================== ✨ 黄金主题（性能优化版）====================
/// 
/// 优化策略：
/// 1. 单动画控制器减少开销
/// 2. 减少粒子数量（沙粒 50→15）
/// 3. 减少晶体数量（8→4）
/// 4. 减少金箔数量（30→10）
/// 5. 液态流体简化（5层→2层，步长 10→25）
/// 6. 简化噪声计算
/// 7. 使用缓存路径
class GoldenBackground extends StatefulWidget {
  final Widget child;
  const GoldenBackground({super.key, required this.child});

  @override
  State<GoldenBackground> createState() => _GoldenBackgroundState();
}

class _GoldenBackgroundState extends State<GoldenBackground>
    with TickerProviderStateMixin {
  // 使用单个动画控制器
  late AnimationController _controller;
  
  final List<Crystal> crystals = [];
  final List<SandParticle> sandParticles = [];
  final List<RuneSymbol> runes = [];
  final Random random = Random();
  
  // 缓存的固定金箔位置
  late final List<GoldFoil> _foils;
  
  // 简化的噪声偏移
  double noiseOffset = 0;
  
  @override
  void initState() {
    super.initState();
    
    // 单一动画控制器（6秒循环）
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    
    // 初始化晶体（减少为4个）
    _initCrystals();
    
    // 初始化沙粒（减少为15个）
    _initSandParticles();
    
    // 预生成金箔位置（减少为10个）
    _foils = List.generate(10, (i) {
      final fixedRandom = Random(42 + i);
      return GoldFoil(
        x: fixedRandom.nextDouble(),
        y: fixedRandom.nextDouble(),
        width: fixedRandom.nextDouble() * 80 + 40,
        height: fixedRandom.nextDouble() * 50 + 25,
      );
    });
  }
  
  void _initCrystals() {
    // 减少为4个晶体，分布在四角
    for (int i = 0; i < 4; i++) {
      crystals.add(Crystal(
        edge: i, // 0=上, 1=右, 2=下, 3=左
        position: 0.3 + random.nextDouble() * 0.4,
        size: random.nextDouble() * 40 + 35,
        growthSpeed: random.nextDouble() * 0.3 + 0.2,
        phase: random.nextDouble() * pi * 2,
        sides: 6, // 固定六边形，减少计算
      ));
    }
  }
  
  void _initSandParticles() {
    // 减少为15个沙粒
    for (int i = 0; i < 15; i++) {
      sandParticles.add(SandParticle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: random.nextDouble() * 1.5 + 0.8,
        speedY: random.nextDouble() * 0.2 + 0.08,
        driftX: (random.nextDouble() - 0.5) * 0.08,
        opacity: random.nextDouble() * 0.5 + 0.25,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1208), // 深褐金
            Color(0xFF2D1F0F), // 古铜
            Color(0xFF3D2817), // 暖金
            Color(0xFF2D1F0F), // 古铜
            Color(0xFF1A1208), // 深褐金
          ],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;
          noiseOffset += 0.003; // 降低噪声变化速度
          
          // 更新沙粒位置（每3帧更新一次，减少计算）
          if ((progress * 100).toInt() % 3 == 0) {
            for (var particle in sandParticles) {
              particle.y += particle.speedY * 0.008;
              particle.x += particle.driftX * 0.015;
              
              if (particle.y > 1.0) {
                particle.y = 0;
                particle.x = random.nextDouble();
              }
              if (particle.x < 0) particle.x = 1;
              if (particle.x > 1) particle.x = 0;
            }
          }
          
          // 低频率生成铭文（1%概率）
          if (random.nextDouble() < 0.008 && runes.length < 3) {
            runes.add(RuneSymbol(
              x: random.nextDouble() * 0.8 + 0.1,
              y: random.nextDouble() * 0.8 + 0.1,
              symbol: _getRandomRune(),
              size: random.nextDouble() * 16 + 14,
              opacity: 0,
              life: 0,
              maxLife: random.nextDouble() * 2 + 2,
            ));
          }
          
          // 更新铭文
          for (var rune in runes) {
            rune.life += 0.016;
            if (rune.life < 0.5) {
              rune.opacity = rune.life * 2;
            } else if (rune.life > rune.maxLife - 0.5) {
              rune.opacity = (rune.maxLife - rune.life) * 2;
            } else {
              rune.opacity = 1.0;
            }
          }
          runes.removeWhere((r) => r.life >= r.maxLife);
          
          return CustomPaint(
            painter: OptimizedTimeVaultPainter(
              progress: progress,
              noiseOffset: noiseOffset,
              crystals: crystals,
              sandParticles: sandParticles,
              runes: runes,
              foils: _foils,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
  
  String _getRandomRune() {
    final runes = ['✦', '✧', '✪', '✫', '✬', '✭'];
    return runes[random.nextInt(runes.length)];
  }
}

// 预计算的金箔数据
class GoldFoil {
  final double x, y, width, height;
  GoldFoil({required this.x, required this.y, required this.width, required this.height});
}

// ==================== 数据类 ====================

class Crystal {
  int edge;
  double position;
  double size;
  double growthSpeed;
  double phase;
  int sides;
  
  Crystal({
    required this.edge,
    required this.position,
    required this.size,
    required this.growthSpeed,
    required this.phase,
    required this.sides,
  });
}

class SandParticle {
  double x, y;
  double size;
  double speedY;
  double driftX;
  double opacity;
  
  SandParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedY,
    required this.driftX,
    required this.opacity,
  });
}

class RuneSymbol {
  double x, y;
  String symbol;
  double size;
  double opacity;
  double life;
  double maxLife;
  
  RuneSymbol({
    required this.x,
    required this.y,
    required this.symbol,
    required this.size,
    required this.opacity,
    required this.life,
    required this.maxLife,
  });
}

// ==================== 优化后的画家类 ====================

class OptimizedTimeVaultPainter extends CustomPainter {
  final double progress;
  final double noiseOffset;
  final List<Crystal> crystals;
  final List<SandParticle> sandParticles;
  final List<RuneSymbol> runes;
  final List<GoldFoil> foils;
  
  // 预计算的颜色
  static final List<Color> _sandColors = [
    const Color(0xFFFFD700),
    const Color(0xFFFFB300),
    const Color(0xFFFFC107),
    const Color(0xFFFFE082),
  ];
  
  OptimizedTimeVaultPainter({
    required this.progress,
    required this.noiseOffset,
    required this.crystals,
    required this.sandParticles,
    required this.runes,
    required this.foils,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 简化液态黄金（2层，大步长）
    _drawSimplifiedLiquidGold(canvas, size);
    
    // 2. 预计算位置的金箔（10个）
    _drawOptimizedGoldFoil(canvas, size);
    
    // 3. 简化晶体（4个，固定六边形）
    _drawOptimizedCrystals(canvas, size);
    
    // 4. 简化沙粒（15个，无随机颜色计算）
    _drawOptimizedSand(canvas, size);
    
    // 5. 铭文（最多3个）
    _drawGoldenRunes(canvas, size);
    
    // 6. 简化时光之眼
    _drawSimplifiedTimeEye(canvas, size);
  }
  
  /// 简化液态黄金 - 2层，大步长25
  void _drawSimplifiedLiquidGold(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    
    // 只绘制2层
    for (int i = 0; i < 2; i++) {
      final path = Path();
      final baseY = size.height * (0.3 + i * 0.25);
      
      path.moveTo(0, baseY);
      
      // 大步长25，减少点数
      for (double x = 0; x <= size.width; x += 25) {
        final noise = _fastNoise(x * 0.002 + noiseOffset, i);
        final y = baseY + noise * 50;
        path.lineTo(x, y);
      }
      
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      
      canvas.drawPath(path, paint);
    }
  }
  
  /// 超简化的噪声函数
  double _fastNoise(double x, int seed) {
    return sin(x + seed) * 0.5 + sin(x * 2) * 0.25;
  }
  
  /// 优化金箔 - 预计算位置，减少模糊
  void _drawOptimizedGoldFoil(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFF8E1).withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    
    for (var foil in foils) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(foil.x * size.width, foil.y * size.height),
          width: foil.width,
          height: foil.height,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
    }
  }
  
  /// 优化晶体 - 简化绘制
  void _drawOptimizedCrystals(Canvas canvas, Size size) {
    for (var crystal in crystals) {
      _drawSingleOptimizedCrystal(canvas, size, crystal);
    }
  }
  
  void _drawSingleOptimizedCrystal(Canvas canvas, Size size, Crystal crystal) {
    // 简化生长计算
    final growth = ((progress * 2 + crystal.phase / pi) % 2) / 2;
    final currentSize = crystal.size * (growth < 0.5 ? growth * 2 : (1 - growth) * 2);
    
    if (currentSize < 2) return;
    
    // 确定位置
    Offset center;
    switch (crystal.edge) {
      case 0: center = Offset(size.width * crystal.position, -currentSize * 0.2); break;
      case 1: center = Offset(size.width + currentSize * 0.2, size.height * crystal.position); break;
      case 2: center = Offset(size.width * crystal.position, size.height + currentSize * 0.2); break;
      default: center = Offset(-currentSize * 0.2, size.height * crystal.position);
    }
    
    // 简化六边形绘制
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3 - pi / 2;
      final x = center.dx + cos(angle) * currentSize;
      final y = center.dy + sin(angle) * currentSize;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    
    // 单一颜色填充
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill);
    
    // 简化边框
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFFFF8E1).withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke);
  }
  
  /// 优化沙粒 - 使用预定义颜色，单次绘制
  void _drawOptimizedSand(Canvas canvas, Size size) {
    for (int i = 0; i < sandParticles.length; i++) {
      final p = sandParticles[i];
      final center = Offset(p.x * size.width, p.y * size.height);
      
      // 使用预定义颜色，避免随机计算
      final color = _sandColors[i % _sandColors.length];
      
      // 单次绘制（主体+高光合并为圆形）
      canvas.drawCircle(center, p.size, Paint()
        ..color = color.withValues(alpha: p.opacity)
        ..style = PaintingStyle.fill);
    }
  }
  
  /// 铭文绘制
  void _drawGoldenRunes(Canvas canvas, Size size) {
    for (var rune in runes) {
      final textSpan = TextSpan(
        text: rune.symbol,
        style: TextStyle(
          fontSize: rune.size,
          color: const Color(0xFFFFD700).withValues(alpha: rune.opacity * 0.7),
          fontWeight: FontWeight.w300,
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      textPainter.paint(
        canvas, 
        Offset(
          rune.x * size.width - textPainter.width / 2,
          rune.y * size.height - textPainter.height / 2,
        ),
      );
    }
  }
  
  /// 简化时光之眼 - 位于底部导航栏加号按钮位置
  void _drawSimplifiedTimeEye(Canvas canvas, Size size) {
    // 将时光之眼移到中间加号按钮位置（水平居中，垂直在底部导航栏）
    final center = Offset(size.width * 0.5, size.height * 0.91);
    final pulse = 0.92 + 0.08 * sin(progress * pi * 2);
    
    // 外圈8个点（减少从12个）
    final dotPaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4 + progress * pi * 0.3;
      final radius = 70 * pulse;
      final x = center.dx + cos(angle) * radius;
      final y = center.dy + sin(angle) * radius;
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
    
    // 内圈光晕
    canvas.drawCircle(center, 45 * pulse, Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill);
    
    // 瞳孔
    canvas.drawCircle(center, 18 * pulse, Paint()
      ..color = const Color(0xFFFFF8E1).withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==================== 🌌 星空主题（算法优化版）====================
class StarryBackground extends StatefulWidget {
  final Widget child;
  const StarryBackground({super.key, required this.child});

  @override
  State<StarryBackground> createState() => _StarryBackgroundState();
}

class _StarryBackgroundState extends State<StarryBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  
  // 预计算的星星数据 - 使用Float64List减少内存开销
  late Float64List _starX, _starY, _starSize, _starOpacity, _starPhase, _starSpeed;
  
  // 流星对象池
  late List<MeteorParticle> _meteorPool;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // 初始化80颗星星 - 使用Typed List提高性能
    const starCount = 80;
    _starX = Float64List(starCount);
    _starY = Float64List(starCount);
    _starSize = Float64List(starCount);
    _starOpacity = Float64List(starCount);
    _starPhase = Float64List(starCount);
    _starSpeed = Float64List(starCount);
    
    for (int i = 0; i < starCount; i++) {
      _starX[i] = _random.nextDouble();
      _starY[i] = _random.nextDouble();
      // 分层：60%小星, 30%中星, 10%大星
      _starSize[i] = i < 48 ? 0.8 : (i < 72 ? 1.8 : 3.0);
      _starOpacity[i] = _random.nextDouble() * 0.4 + 0.3;
      _starPhase[i] = _random.nextDouble() * pi * 2;
      _starSpeed[i] = _random.nextDouble() * 0.5 + 0.5;
    }

    // 初始化流星对象池
    _meteorPool = List.generate(4, (_) => MeteorParticle());
  }

  void _spawnMeteor() {
    for (var meteor in _meteorPool) {
      if (!meteor.active) {
        final colors = [
          const Color(0xFF81D4FA), const Color(0xFFB39DDB), const Color(0xFFF48FB1),
          const Color(0xFF80CBC4), const Color(0xFFFFF59D), const Color(0xFFFFAB91),
        ];
        meteor.activate(
          _random.nextDouble() * 0.3 - 0.1,
          _random.nextDouble() * 0.25,
          _random.nextDouble() * 0.005 + 0.003,
          colors[_random.nextInt(colors.length)],
        );
        break;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF030310), // 更深邃的背景
            Color(0xFF080820),
            Color(0xFF0D0D2F),
            Color(0xFF080820),
          ],
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final time = _controller.value * 2 * pi;
          
          // 低概率生成流星
          if (_random.nextDouble() < 0.012) _spawnMeteor();
          
          // 更新流星
          for (var meteor in _meteorPool) {
            if (meteor.active) meteor.update();
          }

          return CustomPaint(
            size: Size.infinite,
            painter: _StarryPainter(
              starX: _starX,
              starY: _starY,
              starSize: _starSize,
              starOpacity: _starOpacity,
              starPhase: _starPhase,
              starSpeed: _starSpeed,
              meteors: _meteorPool,
              time: time,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// 流星粒子 - 带对象池
class MeteorParticle {
  double x = 0, y = 0, life = 0, speed = 0;
  Color color = Colors.white;
  bool active = false;
  final List<_TailPoint> trail = [];

  void activate(double x, double y, double speed, Color color) {
    this.x = x;
    this.y = y;
    this.speed = speed;
    this.color = color;
    life = 1.0;
    active = true;
    trail.clear();
  }

  void update() {
    trail.add(_TailPoint(x, y, life));
    if (trail.length > 10) trail.removeAt(0);
    
    x += speed;
    y += speed * 0.65;
    life -= 0.005;
    
    if (life <= 0 || x > 1.1 || y > 1.1) {
      active = false;
      trail.clear();
    }
  }
}

class _TailPoint {
  final double x, y, life;
  _TailPoint(this.x, this.y, this.life);
}

/// 优化的绘制器
class _StarryPainter extends CustomPainter {
  final Float64List starX, starY, starSize, starOpacity, starPhase, starSpeed;
  final List<MeteorParticle> meteors;
  final double time;
  
  _StarryPainter({
    required this.starX, required this.starY, required this.starSize,
    required this.starOpacity, required this.starPhase, required this.starSpeed,
    required this.meteors, required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 批量绘制星星 - 按大小分组减少Paint切换
    _drawStars(canvas, size, 0, 48, 1.0);   // 小星
    _drawStars(canvas, size, 48, 72, 1.0);  // 中星
    _drawStars(canvas, size, 72, 80, 1.0);  // 大星

    // 绘制流星
    for (var meteor in meteors) {
      if (meteor.active) _drawMeteor(canvas, size, meteor);
    }
  }

  void _drawStars(Canvas canvas, Size size, int start, int end, double scale) {
    final paint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    for (int i = start; i < end; i++) {
      // 快速近似sin计算闪烁
      final twinkle = _approxSin(time * starSpeed[i] + starPhase[i]);
      final opacity = starOpacity[i] * (0.6 + 0.4 * twinkle);
      
      final cx = starX[i] * size.width;
      final cy = starY[i] * size.height;
      final r = starSize[i] * scale;

      // 大星星带光晕
      if (r > 2.5) {
        glowPaint.color = Colors.white.withValues(alpha: opacity * 0.2);
        canvas.drawCircle(Offset(cx, cy), r * 2.5, glowPaint);
      }

      paint.color = Colors.white.withValues(alpha: opacity.clamp(0.1, 0.95));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  void _drawMeteor(Canvas canvas, Size size, MeteorParticle meteor) {
    final headX = meteor.x * size.width;
    final headY = meteor.y * size.height;
    final opacity = meteor.life.clamp(0.0, 1.0);

    // 绘制尾迹路径
    if (meteor.trail.length >= 2) {
      final path = Path();
      final first = meteor.trail.first;
      path.moveTo(first.x * size.width, first.y * size.height);
      
      for (var point in meteor.trail.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      path.lineTo(headX, headY);

      canvas.drawPath(
        path,
        Paint()
          ..color = meteor.color.withValues(alpha: opacity * 0.6)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // 流星头部 - 三层发光
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    
    glowPaint.color = meteor.color.withValues(alpha: opacity * 0.3);
    canvas.drawCircle(Offset(headX, headY), 12, glowPaint);
    
    glowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    glowPaint.color = meteor.color.withValues(alpha: opacity * 0.8);
    canvas.drawCircle(Offset(headX, headY), 5, glowPaint);
    
    glowPaint.maskFilter = null;
    glowPaint.color = Colors.white.withValues(alpha: opacity);
    canvas.drawCircle(Offset(headX, headY), 2.5, glowPaint);
  }

  /// 快速近似sin - Bhaskara I公式
  double _approxSin(double x) {
    x = x % (2 * pi);
    if (x < 0) x += 2 * pi;
    if (x > pi) x = 2 * pi - x;
    return (16 * x * (pi - x)) / (5 * pi * pi - 4 * x * (pi - x));
  }

  @override
  bool shouldRepaint(covariant _StarryPainter old) => true;
}
