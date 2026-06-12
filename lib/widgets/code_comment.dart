import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// 代码注释式区块标题组件
/// 参考 pddp258.github.io/PROJECT_INTRO // Section Header 风格
///
/// 用代码注释语法作为区块引导文本，营造 Dev-Aesthetic 氛围
///
/// 字体使用系统等宽字体（Android: Droid Sans Mono），无需联网加载。
///
/// 用法:
/// ```dart
/// CodeComment(text: '// 今日记录')
/// CodeComment(text: '> 随笔回忆', prefix: '>')
/// CodeComment(text: '# 日记影院', prefix: '#')
/// ```
class CodeComment extends StatelessWidget {
  /// 注释文本（不含前缀）
  final String text;

  /// 前缀符号（默认 //）
  final String prefix;

  /// 字号
  final double fontSize;

  /// 颜色
  final Color? color;

  /// 字间距
  final double letterSpacing;

  /// 外间距
  final EdgeInsetsGeometry? margin;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 字体族名（设为 null 使用系统默认等宽字体）
  final String? fontFamily;

  const CodeComment({
    super.key,
    required this.text,
    this.prefix = '//',
    this.fontSize = 13.0,
    this.color,
    this.letterSpacing = 0.5,
    this.margin,
    this.padding,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Padding(
        padding: padding ?? const EdgeInsets.only(bottom: 8.0),
        child: Text(
          '$prefix $text',
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: color ?? AppTheme.codeComment,
            letterSpacing: letterSpacing,
          ),
        ),
      ),
    );
  }
}