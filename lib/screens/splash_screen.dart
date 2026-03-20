import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../services/app_lock_service.dart';
import '../widgets/real_page_turn.dart';
import 'app_lock_screen.dart';
import 'main_screen.dart';

/// 存储上次显示完整开屏动画的日期
const String _lastFullSplashKey = 'last_full_splash_date';

/// 封面轮廓绘制 - 使用主题色绘制简化版封面
/// 作为背景层，与原图叠加创造透明效果
class _CoverOutlinePainter extends CustomPainter {
  final Color color;

  _CoverOutlinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 绘制简化的书籍封面轮廓
    final bookWidth = size.width * 0.85;
    final bookHeight = size.height * 0.75;
    final left = (size.width - bookWidth) / 2;
    final top = (size.height - bookHeight) / 2;

    // 主体书本形状（圆角矩形）
    final bookRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, bookWidth, bookHeight),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(bookRect, paint);

    // 绘制书脊/装饰条（左侧）
    final spineWidth = bookWidth * 0.08;
    final spineRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + spineWidth * 0.5, top + bookHeight * 0.05, spineWidth, bookHeight * 0.9),
      Radius.circular(size.width * 0.01),
    );
    canvas.drawRRect(spineRect, paint..color = color.withOpacity(0.7));

    // 绘制顶部装饰区域（模拟图片区域）
    final headerHeight = bookHeight * 0.35;
    final headerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + spineWidth * 2, top + bookHeight * 0.08, bookWidth - spineWidth * 3, headerHeight),
      Radius.circular(size.width * 0.02),
    );
    canvas.drawRRect(headerRect, paint..color = color.withOpacity(0.6));

    // 绘制中部装饰线条
    final lineY = top + headerHeight + bookHeight * 0.15;
    canvas.drawRect(
      Rect.fromLTWH(left + spineWidth * 2, lineY, bookWidth * 0.3, bookHeight * 0.015),
      paint..color = color.withOpacity(0.5),
    );

    // 绘制底部装饰条（模拟作者信息区域）
    final footerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + bookWidth * 0.15, top + bookHeight * 0.65, bookWidth * 0.7, bookHeight * 0.25),
      Radius.circular(size.width * 0.015),
    );
    canvas.drawRRect(footerRect, paint..color = color.withOpacity(0.4));

    // 绘制右下角装饰点
    final decorationSize = bookWidth * 0.12;
    canvas.drawCircle(
      Offset(left + bookWidth - decorationSize, top + bookHeight - decorationSize),
      decorationSize * 0.5,
      paint..color = color.withOpacity(0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _CoverOutlinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// 封面图片的原始分辨率
const double _originalImageWidth = 1080;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isCheckingLock = false;
  bool _showFullAnimation = true; // 是否显示完整动画

  @override
  void initState() {
    super.initState();
    // 初始化应用锁服务
    AppLockService.initialize();
    // 检查是否需要显示完整动画
    _checkAnimationType();
  }

  /// 检查是否需要显示完整动画（每两天一次）
  Future<void> _checkAnimationType() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDateStr = prefs.getString(_lastFullSplashKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // 去掉时间部分

    bool shouldShowFull = true;
    if (lastDateStr != null) {
      final lastDate = DateTime.parse(lastDateStr);
      final difference = today.difference(lastDate).inDays;
      // 每两天显示一次完整动画
      shouldShowFull = difference >= 2;
    }

    setState(() {
      _showFullAnimation = shouldShowFull;
    });

    // 如果显示完整动画，记录当前日期
    if (_showFullAnimation) {
      await prefs.setString(_lastFullSplashKey, today.toIso8601String());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final screenSize = MediaQuery.of(context).size;
    final scheme = themeProvider.currentScheme;

    // 根据动画类型显示不同开屏
    if (_showFullAnimation) {
      // 完整动画：3D翻书效果（每月一次）
      final pages = [
        _buildCoverPage(settings, screenSize, scheme),
        _buildHomeBackground(scheme),
      ];

      return Scaffold(
        backgroundColor: Colors.white,
        body: SplashPageTurn(
          pages: pages,
          initialPage: 0,
          delayBeforeStart: const Duration(milliseconds: 1200),
          flipDuration: const Duration(milliseconds: 800),
          onComplete: _onSplashComplete,
        ),
      );
    } else {
      // 简单动画：淡入淡出（日常）
      return _SimpleSplashAnimation(
        scheme: scheme,
        settings: settings,
        onComplete: _onSplashComplete,
      );
    }
  }

  /// 开场动画完成后的处理
  void _onSplashComplete() {
    if (_isCheckingLock) return;
    _isCheckingLock = true;

    // 检查是否启用了应用锁
    if (AppLockService.isEnabled) {
      // 显示解锁界面
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppLockScreen()),
      );
    } else {
      // 直接进入主界面
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  /// 构建封面页面 - 带自适应坐标的文字叠加
  /// 图片效果：背景轮廓(50%透明深色) + 原图(50%透明)
  Widget _buildCoverPage(SettingsProvider settings, Size screenSize, ThemeScheme scheme) {
    // 计算缩放比例 - 基于原始设计尺寸
    final scale = screenSize.width / _originalImageWidth;
    
    // 字体大小 - 根据屏幕适配（再放大5）
    final nameFontSize = 42 * scale + 5;   // 用户名字体
    final signatureFontSize = 28 * scale + 5;  // 签名字体
    
    // 计算位置 - 垂直位置上移（原位的1/3）
    final authorLabelTop = screenSize.height * 0.573;
    
    // 使用主题的主色调作为文字颜色，保持美观
    final textColor = scheme.primaryColor;
    
    // 使用纯白色背景，轮廓颜色为浅灰色
    final backgroundColor = Colors.white;
    final outlineColor = Colors.grey.shade200; // 更浅的灰色
    
    return Container(
      width: screenSize.width,
      height: screenSize.height,
      color: backgroundColor, // 纯白色背景
      child: Stack(
        children: [
          // 第一层：绘制的封面轮廓（更淡：50%透明度）
          Opacity(
            opacity: 0.5,
            child: CustomPaint(
              size: Size(screenSize.width, screenSize.height),
              painter: _CoverOutlinePainter(outlineColor),
            ),
          ),
          // 第二层：原始封面图片（30%透明度）
          Opacity(
            opacity: 0.3,
            child: Center(
              child: Image.asset(
                'assets/images/splash_cover.png',
                fit: BoxFit.contain,
                width: screenSize.width,
                height: screenSize.height,
              ),
            ),
          ),
          // 作者信息区域 - 水平居中
          Positioned(
            top: authorLabelTop,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 用户名
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: screenSize.width * 0.8),
                  child: Text(
                    settings.userName.isNotEmpty ? settings.userName : '小记用户',
                    style: TextStyle(
                      fontSize: nameFontSize,
                      color: textColor,  // 使用主题主色
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                // 签名
                if (settings.userSignature.isNotEmpty && settings.userSignature != 'PD inc') ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: screenSize.width * 0.8),
                    child: Text(
                      settings.userSignature,
                      style: TextStyle(
                        fontSize: signatureFontSize,
                        color: textColor.withOpacity(0.85),
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeBackground(ThemeScheme scheme) {
    return Container(
      color: scheme.backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories,
              size: 80,
              color: scheme.primaryColor.withOpacity(0.5),
            ),
            const SizedBox(height: 20),
            Text(
              '小记日记',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: scheme.primaryColor.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '记录生活，珍藏回忆',
              style: TextStyle(
                fontSize: 16,
                color: scheme.textMediumColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// 简单开屏动画 - 日常快速进入
class _SimpleSplashAnimation extends StatefulWidget {
  final ThemeScheme scheme;
  final SettingsProvider settings;
  final VoidCallback onComplete;

  const _SimpleSplashAnimation({
    required this.scheme,
    required this.settings,
    required this.onComplete,
  });

  @override
  State<_SimpleSplashAnimation> createState() => _SimpleSplashAnimationState();
}

class _SimpleSplashAnimationState extends State<_SimpleSplashAnimation>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // 淡入动画控制器
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 缩放动画控制器
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
    );

    // 延迟一点开始动画
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _fadeController.forward();
        _scaleController.forward();
      }
    });

    // 短暂显示后自动跳转
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: widget.scheme.backgroundColor,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(_scaleAnimation),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 图标
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: widget.scheme.primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.auto_stories,
                    size: 40,
                    color: widget.scheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 20),
                // 应用名
                Text(
                  '小记日记',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: widget.scheme.textDarkColor,
                  ),
                ),
                const SizedBox(height: 8),
                // 用户名（如果有）
                if (widget.settings.userName.isNotEmpty)
                  Text(
                    widget.settings.userName,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.scheme.textMediumColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
