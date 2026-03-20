import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 里程碑成就服务
/// 管理日记记录天数里程碑和彩蛋触发
class MilestoneService {
  static const String _milestonePrefix = 'milestone_';
  
  /// 里程碑配置
  static final Map<int, MilestoneConfig> _milestones = {
    1: MilestoneConfig(
      days: 1,
      title: '初识日记',
      message: '写下第一篇日记，开启记录之旅',
      badge: '🌱',
      color: Color(0xFF98D4BB),
      animationType: MilestoneAnimation.growth,
    ),
    7: MilestoneConfig(
      days: 7,
      title: '一周坚持',
      message: '连续记录一周，好习惯正在养成',
      badge: '🌿',
      color: Color(0xFF9ACD32),
      animationType: MilestoneAnimation.celebration,
    ),
    30: MilestoneConfig(
      days: 30,
      title: '月度达人',
      message: '一个月的陪伴，记录了那么多故事',
      badge: '🌸',
      color: Color(0xFFFFB6C1),
      animationType: MilestoneAnimation.fireworks,
    ),
    50: MilestoneConfig(
      days: 50,
      title: '半百之旅',
      message: '五十天的坚持，你已是日记行家',
      badge: '🌺',
      color: Color(0xFFFF69B4),
      animationType: MilestoneAnimation.fireworks,
    ),
    100: MilestoneConfig(
      days: 100,
      title: '百日纪念',
      message: '一百天的时光，一百篇的故事',
      badge: '💯',
      color: Color(0xFFFFD700),
      animationType: MilestoneAnimation.confetti,
    ),
    200: MilestoneConfig(
      days: 200,
      title: '双百辉煌',
      message: '二百天的记录，见证你的成长',
      badge: '🏆',
      color: Color(0xFFFFA500),
      animationType: MilestoneAnimation.confetti,
    ),
    365: MilestoneConfig(
      days: 365,
      title: '周年盛典',
      message: '一整年的陪伴，感谢有你',
      badge: '🌟',
      color: Color(0xFF9B7BB8),
      animationType: MilestoneAnimation.anniversary,
    ),
    500: MilestoneConfig(
      days: 500,
      title: '五百传奇',
      message: '五百天的坚持，你是日记大师',
      badge: '👑',
      color: Color(0xFF667eea),
      animationType: MilestoneAnimation.legendary,
    ),
    1000: MilestoneConfig(
      days: 1000,
      title: '千日神话',
      message: '一千天的记录，永恒的回忆',
      badge: '🏛️',
      color: Color(0xFFFF6B9D),
      animationType: MilestoneAnimation.legendary,
    ),
  };
  
  /// 检查并触发里程碑
  /// 返回需要显示的里程碑，如果没有则返回null
  static Future<MilestoneConfig?> checkMilestone(int uniqueDays) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 找到最近的已达成但未展示的里程碑
    for (final entry in _milestones.entries) {
      final days = entry.key;
      final config = entry.value;
      
      if (uniqueDays >= days) {
        final shownKey = '$_milestonePrefix$days';
        final hasShown = prefs.getBool(shownKey) ?? false;
        
        if (!hasShown) {
          // 标记为已展示
          await prefs.setBool(shownKey, true);
          return config;
        }
      }
    }
    
    return null;
  }
  
  /// 获取下一个里程碑信息
  static MilestoneInfo? getNextMilestone(int currentDays) {
    for (final entry in _milestones.entries) {
      if (entry.key > currentDays) {
        return MilestoneInfo(
          days: entry.key,
          title: entry.value.title,
          badge: entry.value.badge,
          remainingDays: entry.key - currentDays,
        );
      }
    }
    return null;
  }
  
  /// 获取已解锁的里程碑列表
  static List<MilestoneConfig> getUnlockedMilestones(int uniqueDays) {
    return _milestones.entries
        .where((e) => uniqueDays >= e.key)
        .map((e) => e.value)
        .toList();
  }
  
  /// 重置所有里程碑（用于测试）
  static Future<void> resetAllMilestones() async {
    final prefs = await SharedPreferences.getInstance();
    for (final days in _milestones.keys) {
      await prefs.remove('$_milestonePrefix$days');
    }
  }
}

/// 里程碑配置
class MilestoneConfig {
  final int days;
  final String title;
  final String message;
  final String badge;
  final Color color;
  final MilestoneAnimation animationType;
  
  MilestoneConfig({
    required this.days,
    required this.title,
    required this.message,
    required this.badge,
    required this.color,
    required this.animationType,
  });
}

/// 里程碑信息
class MilestoneInfo {
  final int days;
  final String title;
  final String badge;
  final int remainingDays;
  
  MilestoneInfo({
    required this.days,
    required this.title,
    required this.badge,
    required this.remainingDays,
  });
}

/// 动画类型
enum MilestoneAnimation {
  growth,      // 生长动画
  celebration, // 庆祝动画
  fireworks,   // 烟花动画
  confetti,    // 彩纸动画
  anniversary, // 周年纪念
  legendary,   // 传奇动画
}

/// 里程碑弹窗组件
class MilestoneDialog extends StatefulWidget {
  final MilestoneConfig config;
  
  const MilestoneDialog({
    super.key,
    required this.config,
  });
  
  static Future<void> show(BuildContext context, MilestoneConfig config) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MilestoneDialog(config: config),
    );
  }

  @override
  State<MilestoneDialog> createState() => _MilestoneDialogState();
}

class _MilestoneDialogState extends State<MilestoneDialog>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _opacityAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0)
            .chain(CurveTween(curve: Curves.linear)),
        weight: 40,
      ),
    ]).animate(_controller);
    
    _rotateAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.5, end: 0.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.1, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 0.0)
            .chain(CurveTween(curve: Curves.linear)),
        weight: 50,
      ),
    ]).animate(_controller);
    
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );
    
    _controller.forward();
    
    // 3秒后自动关闭
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Transform.rotate(
                angle: _rotateAnimation.value,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.config.color.withValues(alpha: 0.95),
                        widget.config.color.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: widget.config.color.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 徽章
                      Text(
                        widget.config.badge,
                        style: const TextStyle(fontSize: 80),
                      ),
                      const SizedBox(height: 16),
                      // 天数
                      Text(
                        '${widget.config.days}',
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '天',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 标题
                      Text(
                        widget.config.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 消息
                      Text(
                        widget.config.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // 装饰线
                      Container(
                        width: 60,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 彩纸庆祝效果（覆盖层）
class ConfettiOverlay extends StatefulWidget {
  final Widget child;
  final bool show;
  
  const ConfettiOverlay({
    super.key,
    required this.child,
    this.show = false,
  });

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<ConfettiParticle> _particles = [];
  final Random _random = Random();
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    
    _generateParticles();
    
    if (widget.show) {
      _controller.forward();
    }
  }
  
  @override
  void didUpdateWidget(ConfettiOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      _controller.forward(from: 0);
    }
  }
  
  void _generateParticles() {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.yellow,
      Colors.purple,
      Colors.orange,
      Colors.pink,
      Colors.teal,
    ];
    
    for (int i = 0; i < 50; i++) {
      _particles.add(ConfettiParticle(
        color: colors[_random.nextInt(colors.length)],
        x: _random.nextDouble(),
        delay: _random.nextDouble() * 0.5,
        duration: 1.5 + _random.nextDouble(),
        size: 5 + _random.nextInt(10).toDouble(),
        rotation: _random.nextDouble() * 6.28,
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
    return Stack(
      children: [
        widget.child,
        if (widget.show)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return IgnorePointer(
                child: Stack(
                  children: _particles.map((particle) {
                    final progress = ((_controller.value - particle.delay) / 
                        (particle.duration / 3)).clamp(0.0, 1.0);
                    
                    if (progress <= 0) return const SizedBox.shrink();
                    
                    final y = progress * 1.5 - 0.2;
                    final x = particle.x + sin(progress * 10 + particle.rotation) * 0.1;
                    final opacity = progress < 0.8 ? 1.0 : 1.0 - (progress - 0.8) * 5;
                    
                    return Positioned(
                      left: x * MediaQuery.of(context).size.width,
                      top: y * MediaQuery.of(context).size.height,
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.rotate(
                          angle: particle.rotation + progress * 10,
                          child: Container(
                            width: particle.size,
                            height: particle.size,
                            decoration: BoxDecoration(
                              color: particle.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
      ],
    );
  }
}

class ConfettiParticle {
  final Color color;
  final double x;
  final double delay;
  final double duration;
  final double size;
  final double rotation;
  
  ConfettiParticle({
    required this.color,
    required this.x,
    required this.delay,
    required this.duration,
    required this.size,
    required this.rotation,
  });
}
