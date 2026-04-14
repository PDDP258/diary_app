import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

/// ============================================================================
/// 设计令牌系统 (Design Tokens)
/// ============================================================================
/// 
/// 基于 Design System Patterns Skill 的三层架构：
/// Layer 1: Primitive Tokens (原始值)
/// Layer 2: Semantic Tokens (语义化)
/// Layer 3: Component Tokens (组件级)
///
/// 结合 Visual Design Foundations Skill：
/// - 8-point 网格系统
/// - 模块化排版比例
/// - 语义化色彩系统

// =============================================================================
// LAYER 1: PRIMITIVE TOKENS (原始值)
// =============================================================================

/// 颜色原始值 - 基于 HSL 色彩空间
class PrimitiveColors {
  PrimitiveColors._();

  // 玫瑰色系
  static const Color rose50 = Color(0xFFFFF1F2);
  static const Color rose100 = Color(0xFFFFE4E6);
  static const Color rose200 = Color(0xFFFECDD3);
  static const Color rose300 = Color(0xFFFDA4AF);
  static const Color rose400 = Color(0xFFFB7185);
  static const Color rose500 = Color(0xFFF43F5E);
  static const Color rose600 = Color(0xFFE11D48);
  static const Color rose700 = Color(0xFFBE123C);
  static const Color rose800 = Color(0xFF9F1239);
  static const Color rose900 = Color(0xFF881337);

  // 薄荷色系
  static const Color mint50 = Color(0xFFF0FDF9);
  static const Color mint100 = Color(0xFFCCFBEF);
  static const Color mint200 = Color(0xFF99F6E0);
  static const Color mint300 = Color(0xFF5EEAD4);
  static const Color mint400 = Color(0xFF2DD4BF);
  static const Color mint500 = Color(0xFF14B8A6);
  static const Color mint600 = Color(0xFF0D9488);
  static const Color mint700 = Color(0xFF0F766E);
  static const Color mint800 = Color(0xFF115E59);
  static const Color mint900 = Color(0xFF134E4A);

  // 天空色系
  static const Color sky50 = Color(0xFFF0F9FF);
  static const Color sky100 = Color(0xFFE0F2FE);
  static const Color sky200 = Color(0xFFBAE6FD);
  static const Color sky300 = Color(0xFF7DD3FC);
  static const Color sky400 = Color(0xFF38BDF8);
  static const Color sky500 = Color(0xFF0EA5E9);
  static const Color sky600 = Color(0xFF0284C7);
  static const Color sky700 = Color(0xFF0369A1);
  static const Color sky800 = Color(0xFF075985);
  static const Color sky900 = Color(0xFF0C4A6E);

  // 琥珀色系
  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber100 = Color(0xFFFEF3C7);
  static const Color amber200 = Color(0xFFFDE68A);
  static const Color amber300 = Color(0xFFFCD34D);
  static const Color amber400 = Color(0xFFFBBF24);
  static const Color amber500 = Color(0xFFF59E0B);
  static const Color amber600 = Color(0xFFD97706);
  static const Color amber700 = Color(0xFFB45309);
  static const Color amber800 = Color(0xFF92400E);
  static const Color amber900 = Color(0xFF78350F);

  // 紫罗兰色系
  static const Color violet50 = Color(0xFFF5F3FF);
  static const Color violet100 = Color(0xFFEDE9FE);
  static const Color violet200 = Color(0xFFDDD6FE);
  static const Color violet300 = Color(0xFFC4B5FD);
  static const Color violet400 = Color(0xFFA78BFA);
  static const Color violet500 = Color(0xFF8B5CF6);
  static const Color violet600 = Color(0xFF7C3AED);
  static const Color violet700 = Color(0xFF6D28D9);
  static const Color violet800 = Color(0xFF5B21B6);
  static const Color violet900 = Color(0xFF4C1D95);

  // 中性灰色系
  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray300 = Color(0xFFD1D5DB);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = Color(0xFF4B5563);
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = Color(0xFF1F2937);
  static const Color gray900 = Color(0xFF111827);

  // 暖灰米色
  static const Color warm50 = Color(0xFFFAFAF9);
  static const Color warm100 = Color(0xFFF5F5F4);
  static const Color warm200 = Color(0xFFE7E5E4);
  static const Color warm300 = Color(0xFFD6D3D1);
  static const Color warm400 = Color(0xFFA8A29E);
  static const Color warm500 = Color(0xFF78716C);
  static const Color warm600 = Color(0xFF57534E);
  static const Color warm700 = Color(0xFF44403C);
  static const Color warm800 = Color(0xFF292524);
  static const Color warm900 = Color(0xFF1C1917);
}

/// 间距原始值 - 8pt 网格系统
class PrimitiveSpacing {
  PrimitiveSpacing._();

  static const double unit = 4.0;  // 基础单位

  // 基础间距 (8pt 网格)
  static const double xs = 4.0;    // 1 unit
  static const double sm = 8.0;    // 2 units
  static const double md = 12.0;   // 3 units
  static const double lg = 16.0;   // 4 units
  static const double xl = 20.0;   // 5 units
  static const double xxl = 24.0;  // 6 units
  static const double xxxl = 32.0; // 8 units

  // 大间距
  static const double huge = 48.0;   // 12 units
  static const double giant = 64.0;  // 16 units
  static const double massive = 96.0; // 24 units
}

/// 排版原始值 - 模块化比例 (1.125 比例)
class PrimitiveTypography {
  PrimitiveTypography._();

  // 基础字号
  static const double base = 16.0;

  // 字号比例 (1.125 比例系统)
  static const double xs = 12.0;     // base / 1.333
  static const double sm = 14.0;     // base / 1.143
  static const double lg = 18.0;     // base * 1.125
  static const double xl = 20.0;     // base * 1.25
  static const double xxl = 24.0;    // base * 1.5
  static const double xxxl = 30.0;   // base * 1.875
  static const double display = 36.0; // base * 2.25

  // 字重
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  // 行高倍数
  static const double tight = 1.2;    // 标题
  static const double normal = 1.5;   // 正文
  static const double relaxed = 1.7;  // 阅读文本
}

/// 圆角原始值
class PrimitiveRadius {
  PrimitiveRadius._();

  static const double none = 0.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double full = 9999.0; // 完全圆形
}

/// 阴影原始值
class PrimitiveShadows {
  PrimitiveShadows._();

  static const List<BoxShadow> none = [];

  static const List<BoxShadow> xs = [
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];
}

/// 动画原始值
class PrimitiveAnimation {
  PrimitiveAnimation._();

  // 时长 (基于 Interaction Design Skill)
  static const Duration micro = Duration(milliseconds: 100);      // 微交互
  static const Duration fast = Duration(milliseconds: 150);       // 快速反馈
  static const Duration normal = Duration(milliseconds: 300);     // 标准过渡
  static const Duration slow = Duration(milliseconds: 500);       // 页面切换
  static const Duration elaborate = Duration(milliseconds: 800);  // 复杂动画

  // 缓动曲线 (基于 Interaction Design Skill)
  static const Curve linear = Curves.linear;
  static const Curve ease = Curves.ease;
  static const Curve easeIn = Curves.easeIn;
  static const Curve easeOut = Curves.easeOut;
  static const Curve easeInOut = Curves.easeInOut;
  
  // 特殊曲线
  static const Cubic easeOutExpo = Cubic(0.16, 1, 0.3, 1);        // 减速进入
  static const Cubic easeInOutCubic = Cubic(0.65, 0, 0.35, 1);    // 平滑过渡
  static const Cubic spring = Cubic(0.34, 1.56, 0.64, 1);         // 弹性效果
  static const Cubic gentle = Cubic(0.23, 1.0, 0.32, 1.0);        // 柔和
}

// =============================================================================
// LAYER 2: SEMANTIC TOKENS (语义化令牌)
// =============================================================================

/// 语义化颜色 - 按用途命名
class SemanticColors {
  final BuildContext context;
  final ThemeScheme scheme;

  SemanticColors(this.context, this.scheme);

  // 品牌色
  Color get brandPrimary => scheme.primaryColor;
  Color get brandLight => scheme.lightColor;
  Color get brandDark => scheme.darkColor;

  // 背景色
  Color get backgroundDefault => scheme.backgroundColor;
  Color get backgroundElevated => scheme.cardColor;
  Color get backgroundOverlay => scheme.textDarkColor.withValues(alpha: 0.5);

  // 文字色
  Color get textPrimary => scheme.textDarkColor;
  Color get textSecondary => scheme.textMediumColor;
  Color get textTertiary => scheme.textLightColor;
  Color get textInverse => Colors.white;

  // 边框色
  Color get borderDefault => scheme.lightColor.withValues(alpha: 0.3);
  Color get borderFocus => scheme.primaryColor;
  Color get borderError => PrimitiveColors.rose500;

  // 状态色
  Color get stateSuccess => PrimitiveColors.mint500;
  Color get stateWarning => PrimitiveColors.amber500;
  Color get stateError => PrimitiveColors.rose500;
  Color get stateInfo => PrimitiveColors.sky500;

  // 交互状态
  Color get interactiveDefault => scheme.primaryColor;
  Color get interactiveHover => scheme.darkColor;
  Color get interactivePressed => scheme.darkColor.withValues(alpha: 0.8);
  Color get interactiveDisabled => scheme.textLightColor.withValues(alpha: 0.3);
}

/// 语义化间距 - 按场景命名
class SemanticSpacing {
  SemanticSpacing._();

  // 组件内部
  static const double componentXs = PrimitiveSpacing.xs;   // 4px - 紧密间距
  static const double componentSm = PrimitiveSpacing.sm;   // 8px - 标准间距
  static const double componentMd = PrimitiveSpacing.md;   // 12px - 宽松间距

  // 组件之间
  static const double elementSm = PrimitiveSpacing.lg;     // 16px
  static const double elementMd = PrimitiveSpacing.xxl;    // 24px
  static const double elementLg = PrimitiveSpacing.xxxl;   // 32px

  // 容器边距
  static const double containerSm = PrimitiveSpacing.lg;   // 16px
  static const double containerMd = PrimitiveSpacing.xxl;  // 24px
  static const double containerLg = PrimitiveSpacing.huge; // 48px

  // 屏幕边距
  static const double screenPadding = PrimitiveSpacing.lg; // 16px
}

/// 语义化排版 - 按层级命名
class SemanticTypography {
  SemanticTypography._();

  // 展示文字
  static const TextStyle display = TextStyle(
    fontSize: PrimitiveTypography.display,
    fontWeight: PrimitiveTypography.bold,
    height: PrimitiveTypography.tight,
  );

  // 标题层级
  static const TextStyle heading1 = TextStyle(
    fontSize: PrimitiveTypography.xxxl,
    fontWeight: PrimitiveTypography.bold,
    height: PrimitiveTypography.tight,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: PrimitiveTypography.xxl,
    fontWeight: PrimitiveTypography.semibold,
    height: PrimitiveTypography.tight,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: PrimitiveTypography.xl,
    fontWeight: PrimitiveTypography.semibold,
    height: PrimitiveTypography.tight,
  );

  // 正文层级
  static const TextStyle bodyLarge = TextStyle(
    fontSize: PrimitiveTypography.lg,
    fontWeight: PrimitiveTypography.regular,
    height: PrimitiveTypography.relaxed,
  );

  static const TextStyle body = TextStyle(
    fontSize: PrimitiveTypography.base,
    fontWeight: PrimitiveTypography.regular,
    height: PrimitiveTypography.normal,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: PrimitiveTypography.sm,
    fontWeight: PrimitiveTypography.regular,
    height: PrimitiveTypography.normal,
  );

  // UI 文字
  static const TextStyle label = TextStyle(
    fontSize: PrimitiveTypography.sm,
    fontWeight: PrimitiveTypography.medium,
    height: PrimitiveTypography.tight,
  );

  static const TextStyle caption = TextStyle(
    fontSize: PrimitiveTypography.xs,
    fontWeight: PrimitiveTypography.regular,
    height: PrimitiveTypography.tight,
  );

  static const TextStyle button = TextStyle(
    fontSize: PrimitiveTypography.base,
    fontWeight: PrimitiveTypography.semibold,
    height: PrimitiveTypography.tight,
  );
}

// =============================================================================
// LAYER 3: COMPONENT TOKENS (组件级令牌)
// =============================================================================

/// 按钮组件令牌
class ButtonTokens {
  ButtonTokens._();

  // 尺寸
  static const double heightSm = 36.0;
  static const double heightMd = 44.0;
  static const double heightLg = 56.0;

  // 内边距
  static const EdgeInsets paddingSm = EdgeInsets.symmetric(
    horizontal: PrimitiveSpacing.lg,
    vertical: PrimitiveSpacing.xs,
  );
  static const EdgeInsets paddingMd = EdgeInsets.symmetric(
    horizontal: PrimitiveSpacing.xxl,
    vertical: PrimitiveSpacing.sm,
  );
  static const EdgeInsets paddingLg = EdgeInsets.symmetric(
    horizontal: PrimitiveSpacing.xxxl,
    vertical: PrimitiveSpacing.md,
  );

  // 圆角
  static const double radius = PrimitiveRadius.xl;

  // 动画
  static const Duration pressDuration = PrimitiveAnimation.fast;
  static const Curve pressCurve = PrimitiveAnimation.spring;
}

/// 卡片组件令牌
class CardTokens {
  CardTokens._();

  // 内边距
  static const EdgeInsets padding = EdgeInsets.all(PrimitiveSpacing.xxl);
  static const EdgeInsets paddingCompact = EdgeInsets.all(PrimitiveSpacing.lg);

  // 圆角
  static const double radius = PrimitiveRadius.xl;
  static const double radiusLarge = PrimitiveRadius.xxl;

  // 阴影
  static const List<BoxShadow> shadow = PrimitiveShadows.md;
  static const List<BoxShadow> shadowElevated = PrimitiveShadows.lg;
}

/// 输入框组件令牌
class InputTokens {
  InputTokens._();

  // 尺寸
  static const double height = 56.0;

  // 内边距
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: PrimitiveSpacing.xxl,
    vertical: PrimitiveSpacing.md,
  );

  // 圆角
  static const double radius = PrimitiveRadius.xl;

  // 边框
  static const double borderWidth = 1.0;
  static const double borderWidthFocus = 2.0;
}

/// 列表组件令牌
class ListTokens {
  ListTokens._();

  // 间距
  static const double itemSpacing = PrimitiveSpacing.lg;
  static const double sectionSpacing = PrimitiveSpacing.xxxl;

  // 内边距
  static const EdgeInsets itemPadding = EdgeInsets.symmetric(
    horizontal: PrimitiveSpacing.lg,
    vertical: PrimitiveSpacing.md,
  );

  // 分割线
  static const double dividerHeight = 1.0;
  static const double dividerIndent = PrimitiveSpacing.xxl;
}

// ThemeScheme 类定义在 lib/providers/theme_provider.dart 中
// 这里保留注释以避免重复定义
