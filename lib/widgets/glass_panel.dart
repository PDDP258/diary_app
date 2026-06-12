import 'dart:ui';
import 'package:flutter/material.dart';

/// 毛玻璃面板组件
/// 参考 pddp258.github.io/PROJECT_INTRO GlassRefraction 设计
///
/// 使用 ImageFiltered + 半透明背景 + 细边框 实现毛玻璃效果
///
/// 用法:
/// ```dart
/// GlassPanel(
///   blur: 15.0,
///   borderRadius: 20.0,
///   child: YourContent(),
/// )
/// ```
class GlassPanel extends StatelessWidget {
  /// 子组件
  final Widget child;

  /// 模糊强度（默认 15px）
  final double blur;

  /// 圆角
  final double borderRadius;

  /// 背景透明度 (0.0 - 1.0)
  final double opacity;

  /// 边框透明度 (0.0 - 1.0)
  final double borderOpacity;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 外间距
  final EdgeInsetsGeometry? margin;

  /// 宽度
  final double? width;

  /// 高度
  final double? height;

  /// 阴影
  final List<BoxShadow>? shadows;

  /// 是否为深色玻璃
  final bool dark;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 15.0,
    this.borderRadius = 20.0,
    this.opacity = 0.15,
    this.borderOpacity = 0.2,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.shadows,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = dark
        ? Colors.black.withValues(alpha: opacity * 4)
        : Colors.white.withValues(alpha: opacity);
    final borderColor = dark
        ? Colors.white.withValues(alpha: borderOpacity * 0.3)
        : Colors.white.withValues(alpha: borderOpacity);

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 0.5),
        boxShadow: shadows ??
            [
              BoxShadow(
                color: (dark ? Colors.black : Colors.black).withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: child,
        ),
      ),
    );
  }
}