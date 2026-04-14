import 'package:flutter/material.dart';
import '../config/design_tokens.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../widgets/animated_feedback.dart';
import '../widgets/immersive_experience.dart';
import '../widgets/diary_interactions.dart';
import '../widgets/smart_notifications.dart';

/// ============================================================================
/// 设计系统扩展方法
/// ============================================================================
///
/// 提供便捷的扩展方法，简化设计系统的使用

/// BuildContext 扩展
extension DesignContextExtension on BuildContext {
  /// 获取当前主题方案
  ThemeScheme get scheme => AppTheme.schemeOf(this);

  /// 获取语义化颜色
  SemanticColors get colors => SemanticColors(this, scheme);

  /// 屏幕宽度
  double get screenWidth => MediaQuery.of(this).size.width;

  /// 屏幕高度
  double get screenHeight => MediaQuery.of(this).size.height;

  /// 安全区顶部内边距
  double get safeTop => MediaQuery.of(this).padding.top;

  /// 安全区底部内边距
  double get safeBottom => MediaQuery.of(this).padding.bottom;

  /// 显示 Toast
  void showToast(
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    ToastManager().show(this, message: message, type: type, duration: duration);
  }

  /// 显示成功 Toast
  void showSuccess(String message) {
    showToast(message, type: ToastType.success);
  }

  /// 显示错误 Toast
  void showError(String message) {
    showToast(message, type: ToastType.error);
  }

  /// 显示警告 Toast
  void showWarning(String message) {
    showToast(message, type: ToastType.warning);
  }
}

/// Widget 扩展
extension DesignWidgetExtension on Widget {
  /// 添加弹性动画
  Widget withBounce({
    VoidCallback? onTap,
    double scaleFactor = 0.96,
  }) {
    return BouncyCard(
      onTap: onTap,
      scaleFactor: scaleFactor,
      child: this,
    );
  }

  /// 添加滑动入场动画
  Widget withSlideIn({
    int index = 0,
    AxisDirection direction = AxisDirection.up,
  }) {
    return SlideInAnimation(
      index: index,
      direction: direction,
      child: this,
    );
  }

  /// 添加 3D 倾斜效果
  Widget withTilt({
    VoidCallback? onTap,
    double maxTilt = 0.1,
  }) {
    return TiltCard(
      onTap: onTap,
      maxTilt: maxTilt,
      child: this,
    );
  }

  /// 添加玻璃态效果
  Widget withGlassmorphism({
    Color? color,
    double blur = 20,
    double opacity = 0.2,
  }) {
    return GlassmorphicContainer(
      color: color,
      blur: blur,
      opacity: opacity,
      child: this,
    );
  }

  /// 添加渐变边框
  Widget withGradientBorder({
    List<Color> colors = const [
      Color(0xFFFF6B6B),
      Color(0xFF4ECDC4),
      Color(0xFF45B7D1),
    ],
    double borderWidth = 2,
  }) {
    return GradientBorderContainer(
      gradientColors: colors,
      borderWidth: borderWidth,
      child: this,
    );
  }

  /// 添加呼吸动画
  Widget withBreathing({
    Duration duration = const Duration(milliseconds: 2000),
  }) {
    return BreathingAnimation(
      duration: duration,
      child: this,
    );
  }

  /// 添加震动效果
  Widget withShake({
    required bool shouldShake,
    VoidCallback? onComplete,
  }) {
    return ShakeAnimation(
      shouldShake: shouldShake,
      onShakeComplete: onComplete,
      child: this,
    );
  }

  /// 添加内边距
  Widget padding(EdgeInsets padding) {
    return Padding(padding: padding, child: this);
  }

  /// 添加对称水平内边距
  Widget paddingH(double value) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: value),
      child: this,
    );
  }

  /// 添加对称垂直内边距
  Widget paddingV(double value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: value),
      child: this,
    );
  }

  /// 添加所有方向内边距
  Widget paddingAll(double value) {
    return Padding(padding: EdgeInsets.all(value), child: this);
  }

  /// 添加圆角
  Widget withBorderRadius(double radius) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: this,
    );
  }

  /// 添加卡片样式
  Widget asCard({
    Color? backgroundColor,
    double radius = PrimitiveRadius.xl,
    List<BoxShadow> shadows = PrimitiveShadows.md,
  }) {
    return Builder(
      builder: (context) {
        final scheme = context.scheme;
        return Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? scheme.cardColor,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: shadows,
          ),
          child: this,
        );
      },
    );
  }
}

/// Text 扩展
extension DesignTextExtension on Text {
  /// 应用魔法文字效果
  Widget withMagicEffect({
    List<Color> colors = const [
      Color(0xFFFF6B6B),
      Color(0xFF4ECDC4),
      Color(0xFF45B7D1),
      Color(0xFF96CEB4),
    ],
  }) {
    return MagicText(
      text: data ?? '',
      style: style,
      colors: colors,
    );
  }

  /// 应用霓虹发光效果
  Widget withNeonGlow({
    Color color = const Color(0xFF00F0FF),
  }) {
    return NeonText(
      text: data ?? '',
      style: style,
      glowColor: color,
    );
  }

  /// 应用打字机效果
  Widget withTypewriter({
    Duration speed = const Duration(milliseconds: 50),
    VoidCallback? onComplete,
  }) {
    return TypewriterText(
      text: data ?? '',
      style: style,
      speed: speed,
      onComplete: onComplete,
    );
  }
}

/// Color 扩展
extension DesignColorExtension on Color {
  /// 获取带透明度的颜色
  Color withOpacityValue(double value) {
    return withValues(alpha: value.clamp(0.0, 1.0));
  }

  /// 变亮
  Color lighten([double amount = 0.1]) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// 变暗
  Color darken([double amount = 0.1]) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// 获取对比色（黑或白）
  Color get contrastColor {
    final luminance = computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}

/// Duration 扩展
extension DesignDurationExtension on int {
  /// 转换为毫秒 Duration
  Duration get ms => Duration(milliseconds: this);

  /// 转换为秒 Duration
  Duration get seconds => Duration(seconds: this);
}

/// 动画便捷构建器
class Animated {
  /// 淡入动画
  static Widget fadeIn({
    required Widget child,
    Duration duration = PrimitiveAnimation.normal,
    Curve curve = PrimitiveAnimation.easeOut,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Opacity(opacity: value, child: child);
      },
      child: child,
    );
  }

  /// 缩放动画
  static Widget scale({
    required Widget child,
    double begin = 0.8,
    double end = 1.0,
    Duration duration = PrimitiveAnimation.normal,
    Curve curve = PrimitiveAnimation.spring,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: begin, end: end),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: child,
    );
  }

  /// 滑入动画
  static Widget slideIn({
    required Widget child,
    Offset begin = const Offset(0, 0.5),
    Duration duration = PrimitiveAnimation.normal,
    Curve curve = PrimitiveAnimation.easeOut,
  }) {
    return TweenAnimationBuilder<Offset>(
      tween: Tween(begin: begin, end: Offset.zero),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(value.dx * 100, value.dy * 100),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// 间距便捷类
class Spacing {
  Spacing._();

  static const double xs = PrimitiveSpacing.xs;
  static const double sm = PrimitiveSpacing.sm;
  static const double md = PrimitiveSpacing.md;
  static const double lg = PrimitiveSpacing.lg;
  static const double xl = PrimitiveSpacing.xl;
  static const double xxl = PrimitiveSpacing.xxl;
  static const double xxxl = PrimitiveSpacing.xxxl;

  /// 水平间距
  static Widget h(double value) => SizedBox(width: value);

  /// 垂直间距
  static Widget v(double value) => SizedBox(height: value);

  /// 标准水平间距组件
  static Widget get hSm => h(sm);
  static Widget get hMd => h(md);
  static Widget get hLg => h(lg);
  static Widget get hXl => h(xl);

  /// 标准垂直间距组件
  static Widget get vSm => v(sm);
  static Widget get vMd => v(md);
  static Widget get vLg => v(lg);
  static Widget get vXl => v(xl);
}

/// 圆角便捷类
class AppRadius {
  AppRadius._();

  static const double none = PrimitiveRadius.none;
  static const double xs = PrimitiveRadius.xs;
  static const double sm = PrimitiveRadius.sm;
  static const double md = PrimitiveRadius.md;
  static const double lg = PrimitiveRadius.lg;
  static const double xl = PrimitiveRadius.xl;
  static const double xxl = PrimitiveRadius.xxl;
  static const double full = PrimitiveRadius.full;
}

/// 阴影便捷类
class Shadows {
  Shadows._();

  static const List<BoxShadow> none = PrimitiveShadows.none;
  static const List<BoxShadow> xs = PrimitiveShadows.xs;
  static const List<BoxShadow> sm = PrimitiveShadows.sm;
  static const List<BoxShadow> md = PrimitiveShadows.md;
  static const List<BoxShadow> lg = PrimitiveShadows.lg;
  static const List<BoxShadow> xl = PrimitiveShadows.xl;
}

/// 动画时长便捷类
class Durations {
  Durations._();

  static const Duration micro = PrimitiveAnimation.micro;
  static const Duration fast = PrimitiveAnimation.fast;
  static const Duration normal = PrimitiveAnimation.normal;
  static const Duration slow = PrimitiveAnimation.slow;
  static const Duration elaborate = PrimitiveAnimation.elaborate;
}

/// 曲线便捷类
class AppCurves {
  AppCurves._();

  static const Curve linear = PrimitiveAnimation.linear;
  static const Curve ease = PrimitiveAnimation.ease;
  static const Curve easeIn = PrimitiveAnimation.easeIn;
  static const Curve easeOut = PrimitiveAnimation.easeOut;
  static const Curve easeInOut = PrimitiveAnimation.easeInOut;
  static const Cubic easeOutExpo = PrimitiveAnimation.easeOutExpo;
  static const Cubic easeInOutCubic = PrimitiveAnimation.easeInOutCubic;
  static const Cubic spring = PrimitiveAnimation.spring;
  static const Cubic gentle = PrimitiveAnimation.gentle;
}
