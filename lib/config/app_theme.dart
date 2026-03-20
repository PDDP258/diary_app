import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// 应用主题配置 - 温馨风格版
/// 采用温暖柔和的色彩，营造舒适的日记记录氛围
class AppTheme {
  AppTheme._();

  // ===== 温馨主色调 =====
  // 暖薄荷 - 温暖清新的主色
  static const Color primaryMint = Color(0xFF7DD3C0);
  static const Color lightMint = Color(0xFFB8E6D9);
  static const Color darkMint = Color(0xFF5BC0A8);
  static const Color deepMint = Color(0xFF4A9B88);
  
  // 暖粉色系 - 温馨甜美
  static const Color warmPink = Color(0xFFF4A6A6);
  static const Color lightPink = Color(0xFFFCE4E4);
  static const Color softPink = Color(0xFFFAD4D4);
  
  // 暖黄色系 - 阳光温暖
  static const Color warmYellow = Color(0xFFF5D491);
  static const Color lightYellow = Color(0xFFFDF6E3);
  static const Color cream = Color(0xFFFDF8F0);
  
  // 暖紫色系 - 柔和优雅
  static const Color warmPurple = Color(0xFFD4A5D9);
  static const Color lightPurple = Color(0xFFF3E5F5);
  
  // ===== 背景色 - 温暖米色调 =====
  static const Color background = Color(0xFFFDF8F3); // 温暖米白
  static const Color cardBackground = Colors.white;
  static const Color scaffoldBackground = Color(0xFFFDF8F3);
  static const Color warmBackground = Color(0xFFFAF5F0); // 更暖的米色
  
  // ===== 文字色 - 柔和深色调 =====
  static const Color textDark = Color(0xFF3D3D3D);      // 柔和深灰
  static const Color textMedium = Color(0xFF6B6B6B);    // 中灰
  static const Color textLight = Color(0xFF9E9E9E);     // 浅灰
  static const Color textWarm = Color(0xFF5C4B51);      // 暖深棕
  
  // ===== 功能色 - 温暖调 =====
  static const Color accentGreen = Color(0xFF81C995);   // 温暖绿
  static const Color selectedGreen = Color(0xFF6DD5C0);
  
  // ===== 情感色 - 柔和版 =====
  static const Color success = Color(0xFF81C995);       // 柔和绿
  static const Color warning = Color(0xFFFFB74D);       // 温暖橙
  static const Color error = Color(0xFFE57373);         // 柔和红
  static const Color info = Color(0xFF64B5F6);          // 柔和蓝
  
  // ===== 温馨装饰色 =====
  static const Color warmAccent = Color(0xFFF4A6A6);    // 暖粉点缀
  static const Color shadowBase = Color(0x1A5C4B51);    // 暖色阴影基础色

  // ========== 圆角系统 - 更圆润温馨 ==========
  static const double smallRadius = 12.0;    // 小圆角 - 按钮、标签
  static const double mediumRadius = 20.0;   // 中圆角 - 输入框、小卡片
  static const double largeRadius = 28.0;    // 大圆角 - 卡片
  static const double xlRadius = 36.0;       // 超大圆角 - 大卡片
  static const double xxlRadius = 48.0;      // 最大圆角 - 弹窗、底部 sheet
  static const double buttonRadius = 24.0;   // 按钮专用圆角
  static const double chipRadius = 20.0;     // 标签芯片圆角
  static const double avatarRadius = 16.0;   // 头像圆角
  
  // ========== 间距系统 - 更舒适 ==========
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacingXxl = 48.0;
  
  // 内边距
  static const EdgeInsets cardPadding = EdgeInsets.all(20);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 14);
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  
  // ========== 动画系统 - 更柔和 ==========
  /// 超柔和曲线 - 用于温馨过渡
  static const Curve gentleCurve = Cubic(0.23, 1.0, 0.32, 1.0);
  /// 弹性曲线 - 用于活泼元素
  static const Curve bouncyCurve = Cubic(0.34, 1.56, 0.64, 1);
  /// 缓慢曲线 - 用于背景、装饰
  static const Curve slowCurve = Cubic(0.4, 0.0, 0.2, 1);
  
  // 动画时长
  static const Duration quickDuration = Duration(milliseconds: 200);
  static const Duration normalDuration = Duration(milliseconds: 300);
  static const Duration slowDuration = Duration(milliseconds: 500);
  static const Duration verySlowDuration = Duration(milliseconds: 800);

  // 获取动态主题颜色（用于 StatelessWidget）
  static ThemeScheme schemeOf(BuildContext context) {
    return context.watch<ThemeProvider>().currentScheme;
  }

  static Color primaryOf(BuildContext context) => schemeOf(context).primaryColor;
  static Color backgroundOf(BuildContext context) => schemeOf(context).backgroundColor;
  static Color cardOf(BuildContext context) => schemeOf(context).cardColor;
  static Color lightOf(BuildContext context) => schemeOf(context).lightColor;
  static Color darkOf(BuildContext context) => schemeOf(context).darkColor;
  static Color textDarkOf(BuildContext context) => schemeOf(context).textDarkColor;
  static Color textMediumOf(BuildContext context) => schemeOf(context).textMediumColor;
  static Color textLightOf(BuildContext context) => schemeOf(context).textLightColor;

  // ========== 温馨阴影系统 ==========
  
  /// 卡片阴影 - 柔和温暖的多层效果
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0x1A5C4B51), // 暖色阴影
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: const Color(0x0D5C4B51),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
  
  /// 柔和阴影 - 更温馨
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: const Color(0x145C4B51),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
  
  /// 温馨 glow 效果
  static List<BoxShadow> get warmGlow => [
    BoxShadow(
      color: warmPink.withOpacity(0.2),
      blurRadius: 20,
      offset: const Offset(0, 4),
      spreadRadius: -5,
    ),
  ];
  
  /// 悬浮阴影 - 用于可交互元素
  static List<BoxShadow> get floatingShadow => [
    BoxShadow(
      color: const Color(0x1A5C4B51),
      blurRadius: 16,
      offset: const Offset(0, 8),
      spreadRadius: -4,
    ),
  ];
  
  /// 发光阴影 - 用于高亮元素
  static List<BoxShadow> glowShadow(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.4),
      blurRadius: 20,
      offset: const Offset(0, 4),
      spreadRadius: -4,
    ),
  ];

  // ========== 边框系统 - 柔和 ==========
  static BorderSide softBorder(Color color) => BorderSide(
    color: color.withOpacity(0.2),
    width: 1,
  );
  
  static BorderSide mediumBorder(Color color) => BorderSide(
    color: color.withOpacity(0.3),
    width: 1.5,
  );
  
  static BorderSide focusBorder(Color color) => BorderSide(
    color: color.withOpacity(0.5),
    width: 2,
  );
  
  // 柔和圆角边框
  static BoxDecoration softDecoration(Color color) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(mediumRadius),
    border: Border.all(color: color.withOpacity(0.1)),
  );
  
  // 纸张纹理效果装饰
  static BoxDecoration paperDecoration(Color backgroundColor) => BoxDecoration(
    color: backgroundColor,
    borderRadius: BorderRadius.circular(largeRadius),
    boxShadow: cardShadow,
  );

  // ========== 渐变系统 ==========
  
  /// 主渐变
  static LinearGradient primaryGradient(BuildContext context) {
    final scheme = schemeOf(context);
    return LinearGradient(
      colors: [scheme.lightColor, scheme.primaryColor],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
  
  /// 按钮渐变
  static LinearGradient buttonGradient(BuildContext context) {
    final scheme = schemeOf(context);
    return LinearGradient(
      colors: [scheme.darkColor, scheme.primaryColor],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }
  
  /// 卡片渐变背景
  static LinearGradient cardGradient(BuildContext context) {
    final scheme = schemeOf(context);
    return LinearGradient(
      colors: [
        scheme.cardColor,
        scheme.cardColor.withOpacity(0.95),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
  }
  
  /// 玻璃态渐变
  static LinearGradient glassGradient(Color baseColor) {
    return LinearGradient(
      colors: [
        baseColor.withOpacity(0.7),
        baseColor.withOpacity(0.3),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  // ========== 动画曲线 ==========
  static const Curve easeOutExpo = Cubic(0.16, 1, 0.3, 1);
  static const Curve easeInOutCubic = Cubic(0.65, 0, 0.35, 1);
  static const Curve spring = Cubic(0.34, 1.56, 0.64, 1);

  // 主题数据（基础配置，实际使用 ThemeProvider.theme）
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: primaryMint,
      secondary: accentGreen,
      surface: cardBackground,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textDark,
      error: error,
    ),
    scaffoldBackgroundColor: scaffoldBackground,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      foregroundColor: textDark,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        color: textDark,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(largeRadius),
      ),
      color: cardBackground,
      margin: const EdgeInsets.symmetric(horizontal: spacingMd, vertical: spacingSm),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryMint,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: BorderSide(color: lightMint.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
        borderSide: const BorderSide(color: primaryMint, width: 2),
      ),
      contentPadding: inputPadding,
      hintStyle: TextStyle(
        color: textLight.withOpacity(0.5),
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: primaryMint,
        foregroundColor: Colors.white,
        padding: buttonPadding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        shadowColor: Colors.transparent,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryMint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(smallRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconTheme: const IconThemeData(
      color: textMedium,
      size: 24,
    ),
    dividerTheme: DividerThemeData(
      color: lightMint.withOpacity(0.2),
      thickness: 0.5,
      space: 1,
      indent: spacingMd,
      endIndent: spacingMd,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: primaryMint.withOpacity(0.2),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chipRadius),
      ),
      side: BorderSide(color: lightMint.withOpacity(0.3)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(mediumRadius),
      ),
      contentPadding: listItemPadding,
      minLeadingWidth: 24,
      minVerticalPadding: 12,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: textDark.withOpacity(0.9),
        borderRadius: BorderRadius.circular(smallRadius),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.all(spacingSm),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: primaryMint,
      unselectedItemColor: textLight,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      unselectedLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.normal,
        height: 1.2,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(xlRadius),
      ),
      elevation: 0,
      backgroundColor: cardBackground,
      titleTextStyle: const TextStyle(
        color: textDark,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        color: textMedium,
        fontSize: 15,
        height: 1.5,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(buttonRadius),
      ),
      backgroundColor: textDark.withOpacity(0.95),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      elevation: 4,
    ),
  );
}

/// 动画工具类
class AnimationUtils {
  AnimationUtils._();
  
  /// 页面切换动画
  static PageRouteBuilder<T> fadeRoute<T>({
    required Widget page,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: duration,
    );
  }
  
  /// 滑动进入动画
  static PageRouteBuilder<T> slideUpRoute<T>({
    required Widget page,
    Duration duration = const Duration(milliseconds: 400),
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0);
        const end = Offset.zero;
        const curve = Curves.easeOutExpo;
        
        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );
        
        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
      transitionDuration: duration,
    );
  }
}
