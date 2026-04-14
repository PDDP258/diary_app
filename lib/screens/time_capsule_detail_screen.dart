import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/time_capsule.dart';
import '../services/time_capsule_service.dart';
import '../widgets/interactive_button.dart';
import '../providers/theme_provider.dart';

/// 时间胶囊详情页面（包含解锁动画）
class TimeCapsuleDetailScreen extends StatefulWidget {
  final TimeCapsule capsule;

  const TimeCapsuleDetailScreen({
    super.key,
    required this.capsule,
  });

  @override
  State<TimeCapsuleDetailScreen> createState() =>
      _TimeCapsuleDetailScreenState();
}

class _TimeCapsuleDetailScreenState extends State<TimeCapsuleDetailScreen>
    with TickerProviderStateMixin {
  late TimeCapsule _capsule;
  bool _isUnlocking = false;
  bool _showContent = false;
  
  // 动画控制器
  late AnimationController _unlockAnimationController;
  late AnimationController _fadeController;
  late Animation<double> _lockScaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _shakeAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _capsule = widget.capsule;
    _showContent = _capsule.isUnlocked;
    
    // 解锁动画控制器
    _unlockAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    
    // 淡入控制器
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // 锁缩放动画
    _lockScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.9)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.9, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInBack)),
        weight: 50,
      ),
    ]).animate(_unlockAnimationController);

    // 发光动画
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(
          CurvedAnimation(
            parent: _unlockAnimationController,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
          ),
        );

    // 震动动画
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(
          CurvedAnimation(
            parent: _unlockAnimationController,
            curve: const Interval(0.2, 0.5, curve: Curves.easeInOut),
          ),
        );

    // 淡入动画
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: AppTheme.gentleCurve))
        .animate(_fadeController);

    // 如果已经解锁，直接显示内容
    if (_showContent) {
      _fadeController.forward();
      _markAsRead();
    }
  }

  @override
  void dispose() {
    _unlockAnimationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _performUnlock() async {
    if (_isUnlocking) return;
    
    setState(() => _isUnlocking = true);
    HapticFeedback.heavyImpact();
    
    // 播放解锁动画
    await _unlockAnimationController.forward();
    
    // 解锁胶囊
    final unlocked = await TimeCapsuleService.unlockCapsule(_capsule.id!);
    
    if (unlocked != null && mounted) {
      setState(() {
        _capsule = unlocked;
        _showContent = true;
      });
      
      // 显示内容
      await _fadeController.forward();
      
      // 标记为已读
      await _markAsRead();
    }
    
    setState(() => _isUnlocking = false);
  }

  Future<void> _markAsRead() async {
    if (_capsule.id != null && !_capsule.isRead) {
      final updated = await TimeCapsuleService.markAsRead(_capsule.id!);
      if (updated != null) {
        setState(() {
          _capsule = updated;
        });
      }
    }
  }

  Future<void> _deleteCapsule() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        ),
        title: const Text('删除时间胶囊'),
        content: const Text('确定要删除这个时间胶囊吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && _capsule.id != null) {
      final success = await TimeCapsuleService.deleteCapsule(_capsule.id!);
      if (success && mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: SafeArea(
        child: _showContent
            ? _buildContentView(scheme)
            : _buildUnlockView(scheme),
      ),
    );
  }

  Widget _buildUnlockView(ThemeScheme scheme) {
    return AnimatedBuilder(
      animation: _unlockAnimationController,
      builder: (context, child) {
        // 计算震动偏移
        double shakeOffset = 0;
        if (_shakeAnimation.value > 0 && _shakeAnimation.value < 1) {
          final shakeIntensity = math.sin(_shakeAnimation.value * math.pi * 8);
          shakeOffset = shakeIntensity * 8 * (1 - _shakeAnimation.value);
        }

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 发光背景
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      scheme.primaryColor
                          .withValues(alpha: 0.3 * _glowAnimation.value),
                      scheme.primaryColor
                          .withValues(alpha: 0.1 * _glowAnimation.value),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // 锁图标
              Transform.translate(
                offset: Offset(shakeOffset, 0),
                child: Transform.scale(
                  scale: _lockScaleAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primaryColor,
                          scheme.darkColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primaryColor
                              .withValues(alpha: 0.4 * _glowAnimation.value),
                          blurRadius: 40,
                          spreadRadius: 10 * _glowAnimation.value,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 48),
              
              // 提示文字
              Text(
                _isUnlocking ? '开启中...' : '一封信件正在等待开启',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
              
              const SizedBox(height: 12),
              
              Text(
                _isUnlocking
                    ? '正在解锁你的时间胶囊'
                    : '来自 ${_formatDate(_capsule.createdAt)} 的你',
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.textMediumColor,
                ),
              ),
              
              const SizedBox(height: 48),
              
              // 解锁按钮
              if (!_isUnlocking)
                InteractiveButton(
                  onPressed: _capsule.canUnlock ? _performUnlock : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      gradient: _capsule.canUnlock
                          ? LinearGradient(
                              colors: [scheme.darkColor, scheme.primaryColor],
                            )
                          : LinearGradient(
                              colors: [
                                Colors.grey.shade300,
                                Colors.grey.shade400,
                              ],
                            ),
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                      boxShadow: _capsule.canUnlock ? AppTheme.floatingShadow : null,
                    ),
                    child: Text(
                      _capsule.canUnlock ? '开启信件' : '还未到开启时间',
                      style: TextStyle(
                        color: _capsule.canUnlock ? Colors.white : Colors.grey.shade600,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              
              if (!_capsule.canUnlock) ...[
                const SizedBox(height: 16),
                Text(
                  '还有 ${_capsule.waitingTimeDesc}',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.textLightColor,
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // 返回按钮
              InteractiveButton(
                onPressed: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.cardColor,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    border: Border.all(color: scheme.lightColor),
                  ),
                  child: Text(
                    '稍后再看',
                    style: TextStyle(
                      color: scheme.textMediumColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContentView(ThemeScheme scheme) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: CustomScrollView(
        slivers: [
          // 顶部导航栏
          SliverAppBar(
            floating: true,
            backgroundColor: scheme.backgroundColor,
            elevation: 0,
            leading: InteractiveButton(
              onPressed: () => Navigator.pop(context, true),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.cardColor,
                  borderRadius: BorderRadius.circular(AppTheme.smallRadius),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: scheme.textDarkColor,
                ),
              ),
            ),
            actions: [
              InteractiveButton(
                onPressed: _deleteCapsule,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.cardColor,
                    borderRadius: BorderRadius.circular(AppTheme.smallRadius),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppTheme.error.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
          
          // 内容区
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 信封装饰头部
                  _buildEnvelopeHeader(scheme),
                  
                  const SizedBox(height: AppTheme.spacingLg),
                  
                  // 标题
                  Container(
                    width: double.infinity,
                    padding: AppTheme.cardPadding,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.cardColor,
                          scheme.cardColor.withValues(alpha: 0.95),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.largeRadius),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Text(
                      _capsule.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: scheme.textDarkColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: AppTheme.spacingLg),
                  
                  // 内容
                  Container(
                    width: double.infinity,
                    padding: AppTheme.cardPadding,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.cardColor,
                          scheme.cardColor.withValues(alpha: 0.95),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.largeRadius),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Text(
                      _capsule.content,
                      style: TextStyle(
                        fontSize: 16,
                        color: scheme.textDarkColor,
                        height: 1.8,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: AppTheme.spacingLg),
                  
                  // 图片
                  if (_capsule.imageList.isNotEmpty)
                    _buildImageGallery(scheme),
                  
                  // 底部信息
                  _buildFooterInfo(scheme),
                  
                  const SizedBox(height: AppTheme.spacingXxl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvelopeHeader(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryColor.withValues(alpha: 0.15),
            scheme.lightColor.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        border: Border.all(
          color: scheme.primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // 信封图标
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primaryColor, scheme.darkColor],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: scheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.mark_email_read,
              size: 36,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: AppTheme.spacingMd),
          
          Text(
            '来自过去的信',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: scheme.textDarkColor,
            ),
          ),
          
          const SizedBox(height: 4),
          
          Text(
            '${_formatDate(_capsule.createdAt)} → ${_formatDate(_capsule.unlockDate)}',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textMediumColor,
            ),
          ),
          
          if (_capsule.moodEmoji != null) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: scheme.cardColor,
                borderRadius: BorderRadius.circular(AppTheme.chipRadius),
              ),
              child: Text(
                '当时的心情: ${_capsule.moodEmoji}',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.textMediumColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageGallery(ThemeScheme scheme) {
    return Container(
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '随信附上的照片',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _capsule.imageList.map((path) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
                child: Image.file(
                  File(path),
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterInfo(ThemeScheme scheme) {
    final waitingTime = _calculateWaitingTime();
    
    return Container(
      margin: const EdgeInsets.only(top: AppTheme.spacingLg),
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.lightColor.withValues(alpha: 0.3),
            scheme.lightColor.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: scheme.textLightColor,
              ),
              const SizedBox(width: 8),
              Text(
                '这封信历经 $waitingTime 终于抵达',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.textMediumColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Text(
            '"时间胶囊封存了此刻的你，\n愿未来的你依然热爱生活。"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: scheme.textLightColor,
              fontStyle: FontStyle.italic,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  String _calculateWaitingTime() {
    final difference = _capsule.unlockDate.difference(_capsule.createdAt);
    final days = difference.inDays;
    
    if (days > 365) {
      final years = days ~/ 365;
      final months = (days % 365) ~/ 30;
      if (months > 0) {
        return '$years年$months个月';
      }
      return '$years年';
    } else if (days > 30) {
      final months = days ~/ 30;
      return '$months个月';
    } else {
      return '$days天';
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }
}
