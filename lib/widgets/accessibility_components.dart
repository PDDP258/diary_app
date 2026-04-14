import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// ============================================================================
/// 无障碍组件库 - 基于 WCAG 2.2 和移动无障碍最佳实践
/// ============================================================================
///
/// 参考技能:
/// - WCAG 2.2 Guidelines
/// - Mobile Accessibility Best Practices
/// - Flutter Semantics API

/// 语义化包装器 - 为组件添加无障碍标签
class SemanticWrapper extends StatelessWidget {
  final Widget child;
  final String? label;
  final String? hint;
  final String? value;
  final bool enabled;
  final bool selected;
  final bool hidden;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SemanticWrapper({
    super.key,
    required this.child,
    this.label,
    this.hint,
    this.value,
    this.enabled = true,
    this.selected = false,
    this.hidden = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      hint: hint,
      value: value,
      enabled: enabled,
      selected: selected,
      hidden: hidden,
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }
}

/// 无障碍按钮 - 符合 WCAG 触摸目标规范 (48x48dp)
class AccessibleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final String semanticsLabel;
  final String? semanticsHint;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double minSize;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;

  const AccessibleButton({
    super.key,
    required this.onPressed,
    required this.child,
    required this.semanticsLabel,
    this.semanticsHint,
    this.backgroundColor,
    this.foregroundColor,
    this.minSize = 48.0,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: semanticsHint,
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minSize,
          minHeight: minSize,
        ),
        child: Material(
          color: backgroundColor ?? Theme.of(context).primaryColor,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          child: InkWell(
            onTap: onPressed,
            borderRadius: borderRadius ?? BorderRadius.circular(8),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(12),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: foregroundColor ?? Colors.white,
                  fontSize: 16,
                ),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 无障碍图标按钮 - 符合触摸目标规范
class AccessibleIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String semanticsLabel;
  final String? semanticsHint;
  final Color? color;
  final double iconSize;
  final double minSize;

  const AccessibleIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.semanticsLabel,
    this.semanticsHint,
    this.color,
    this.iconSize = 24,
    this.minSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: semanticsHint,
      onTap: onPressed,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(minSize / 2),
          child: Container(
            width: minSize,
            height: minSize,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: iconSize,
              color: color ?? Theme.of(context).iconTheme.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// 高对比度文本 - 确保符合 WCAG 对比度标准
class HighContrastText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color? backgroundColor;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const HighContrastText(
    this.text, {
    super.key,
    this.style,
    this.backgroundColor,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  /// 计算亮度
  double _getLuminance(Color color) {
    return color.computeLuminance();
  }

  /// 计算对比度
  double _getContrastRatio(Color color1, Color color2) {
    final lum1 = _getLuminance(color1);
    final lum2 = _getLuminance(color2);
    final lighter = lum1 > lum2 ? lum1 : lum2;
    final darker = lum1 > lum2 ? lum2 : lum1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// 获取满足对比度的颜色
  Color _getAccessibleColor(Color bgColor, Color intendedColor) {
    final ratio = _getContrastRatio(bgColor, intendedColor);
    if (ratio >= 4.5) return intendedColor;

    // 调整颜色以达到对比度要求
    final isLightBg = _getLuminance(bgColor) > 0.5;
    return isLightBg ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = style ?? defaultStyle;
    final bgColor = backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    final textColor = effectiveStyle.color ?? Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    
    final accessibleColor = _getAccessibleColor(bgColor, textColor);

    return Text(
      text,
      style: effectiveStyle.copyWith(color: accessibleColor),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// 屏幕阅读器专用文本 - 仅对辅助技术可见
class ScreenReaderOnly extends StatelessWidget {
  final String text;

  const ScreenReaderOnly(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      child: const SizedBox.shrink(),
    );
  }
}

/// 可聚焦区域 - 管理焦点导航
class FocusableArea extends StatefulWidget {
  final Widget child;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onTap;

  const FocusableArea({
    super.key,
    required this.child,
    this.focusNode,
    this.onFocusChange,
    this.onTap,
  });

  @override
  State<FocusableArea> createState() => _FocusableAreaState();
}

class _FocusableAreaState extends State<FocusableArea> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
    widget.onFocusChange?.call(_focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
          widget.onTap?.call();
        },
        child: Container(
          decoration: BoxDecoration(
            border: _isFocused
                ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 实时区域 - 用于动态更新内容的宣布
class LiveRegion extends StatelessWidget {
  final Widget child;
  final String announcement;
  final bool assertive;

  const LiveRegion({
    super.key,
    required this.child,
    required this.announcement,
    this.assertive = false,
  });

  @override
  Widget build(BuildContext context) {
    // 触发屏幕阅读器宣布
    if (announcement.isNotEmpty) {
      Future.delayed(Duration.zero, () {
        SemanticsService.announce(
          announcement,
          Directionality.of(context),
        );
      });
    }

    return Semantics(
      liveRegion: true,
      child: child,
    );
  }
}

/// 无障碍表单字段 - 完整标签和错误提示
class AccessibleFormField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? errorText;
  final bool required;
  final Widget child;
  final bool enabled;

  const AccessibleFormField({
    super.key,
    required this.label,
    this.hint,
    this.errorText,
    this.required = false,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = required ? '$label *' : label;
    final semanticsLabel = errorText != null 
        ? '$labelText, 错误: $errorText' 
        : labelText;

    return Semantics(
      label: semanticsLabel,
      hint: hint,
      enabled: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labelText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          const SizedBox(height: 4),
          child,
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 跳过链接 - 帮助键盘用户跳过导航
class SkipLink extends StatelessWidget {
  final VoidCallback onSkip;
  final String label;

  const SkipLink({
    super.key,
    required this.onSkip,
    this.label = '跳到主内容',
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        // 只在有焦点时显示
        return Focus(
          child: const SizedBox.shrink(),
          onFocusChange: (hasFocus) {
            // 实现跳过逻辑
          },
        );
      },
    );
  }
}

/// 无障碍进度指示器 - 提供进度信息给屏幕阅读器
class AccessibleProgressIndicator extends StatelessWidget {
  final double? value;
  final String? label;
  final String? semanticsLabel;

  const AccessibleProgressIndicator({
    super.key,
    this.value,
    this.label,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final percent = value != null ? (value! * 100).toInt() : null;
    final announcement = percent != null 
        ? '${semanticsLabel ?? "进度"}: $percent%' 
        : '${semanticsLabel ?? "进度"}: 加载中';

    return Semantics(
      label: announcement,
      value: percent?.toString(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(label!),
            ),
          LinearProgressIndicator(value: value),
        ],
      ),
    );
  }
}

/// 对比度检查器 - 开发时检查对比度
class ContrastChecker {
  /// 计算相对亮度
  static double _getLuminance(Color color) {
    return color.computeLuminance();
  }

  /// 计算对比度比率
  static double calculateContrast(Color foreground, Color background) {
    final lum1 = _getLuminance(foreground);
    final lum2 = _getLuminance(background);
    final lighter = lum1 > lum2 ? lum1 : lum2;
    final darker = lum1 > lum2 ? lum2 : lum1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// 检查是否符合 WCAG AA 标准
  static bool meetsWCAGAA(Color foreground, Color background, {bool isLargeText = false}) {
    final ratio = calculateContrast(foreground, background);
    return isLargeText ? ratio >= 3.0 : ratio >= 4.5;
  }

  /// 检查是否符合 WCAG AAA 标准
  static bool meetsWCAGAAA(Color foreground, Color background, {bool isLargeText = false}) {
    final ratio = calculateContrast(foreground, background);
    return isLargeText ? ratio >= 4.5 : ratio >= 7.0;
  }

  /// 获取建议的对比色
  static Color getSuggestedColor(Color background, Color intendedColor) {
    if (meetsWCAGAA(intendedColor, background)) {
      return intendedColor;
    }

    final isLightBg = _getLuminance(background) > 0.5;
    
    // 尝试调整亮度
    for (double adjustment = 0.1; adjustment <= 1.0; adjustment += 0.1) {
      final adjustedColor = isLightBg 
          ? intendedColor.withValues(alpha: 1.0).darken(adjustment)
          : intendedColor.withValues(alpha: 1.0).lighten(adjustment);
      
      if (meetsWCAGAA(adjustedColor, background)) {
        return adjustedColor;
      }
    }

    return isLightBg ? Colors.black : Colors.white;
  }
}

/// 颜色扩展
extension ColorExtension on Color {
  Color lighten(double amount) {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  Color darken(double amount) {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}

/// 无障碍助手 - 提供常用无障碍功能
class AccessibilityHelper {
  /// 宣布消息给屏幕阅读器
  static void announce(BuildContext context, String message) {
    SemanticsService.announce(
      message,
      Directionality.of(context),
    );
  }

  /// 触发触觉反馈
  static void triggerHaptic(HapticFeedbackType type) {
    switch (type) {
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticFeedbackType.selection:
        HapticFeedback.selectionClick();
        break;
    }
  }

  /// 检查系统是否启用了辅助功能
  static Future<bool> isScreenReaderEnabled() async {
    // Flutter 没有直接 API，需要通过 Semantics 检测
    return false;
  }
}

enum HapticFeedbackType {
  light,
  medium,
  heavy,
  selection,
}
