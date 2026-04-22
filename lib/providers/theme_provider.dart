import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题配色方案
class ThemeScheme {
  final Color primaryColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color lightColor;
  final Color darkColor;
  final Color textDarkColor;
  final Color textMediumColor;
  final Color textLightColor;
  final String name;
  final Color? iconColor; // 可选的独立图标颜色

  const ThemeScheme({
    required this.primaryColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.lightColor,
    required this.darkColor,
    required this.textDarkColor,
    required this.textMediumColor,
    required this.textLightColor,
    required this.name,
    this.iconColor,
  });

  /// 错误色 - 默认红色
  Color get errorColor => const Color(0xFFE53935);

  /// 成功色
  Color get successColor => const Color(0xFF81C995);

  /// 警告色
  Color get warningColor => const Color(0xFFFFB74D);

  /// 次色 - 用于 Alter Ego 等辅助身份标识（默认紫色）
  Color get secondaryColor => const Color(0xFF9C27B0);

  /// 表面色 - 用于底部弹窗、对话框等 elevated 表面
  Color get surfaceColor {
    if (isBackgroundLight) {
      return const Color(0xFFFFFFFF);
    }
    return Color.lerp(cardColor, lightColor, 0.15) ?? cardColor;
  }

  /// 分割线颜色
  Color get dividerColor => lightColor.withValues(alpha: 0.35);

  /// 阴影颜色
  Color get shadowColor => isBackgroundLight
      ? const Color(0x1A5C4B51)
      : const Color(0x66000000);

  /// 判断背景色是浅色还是深色
  /// 基于 luminance（亮度值），范围 0-1，0.5 为中间值
  bool get isBackgroundLight {
    // 计算背景色的亮度值
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5;
  }

  /// 获取箭头按钮的背景色
  /// 根据背景色深浅动态调整，确保有足够对比度
  Color getArrowButtonBackground({double opacity = 0.15}) {
    if (isBackgroundLight) {
      // 背景是浅色，使用深色版本的 lightColor，增加对比度
      return lightColor.withValues(alpha: opacity + 0.25);
    } else {
      // 背景是深色，使用更浅的版本
      return cardColor.withValues(alpha: opacity + 0.35);
    }
  }

  /// 获取箭头按钮的图标色
  Color getArrowButtonIconColor({double opacity = 0.8}) {
    if (isBackgroundLight) {
      // 背景是浅色，使用更深的颜色
      return textMediumColor.withValues(alpha: opacity + 0.1);
    } else {
      // 背景是深色，使用更浅的颜色
      return textLightColor.withValues(alpha: opacity);
    }
  }

  // 温馨米（默认）- 温暖舒适的米色调
  static const ThemeScheme warmBeige = ThemeScheme(
    primaryColor: Color(0xFFE8B4B8),      // 温暖玫瑰粉
    backgroundColor: Color(0xFFFDF8F3),  // 温暖米白
    cardColor: Colors.white,
    lightColor: Color(0xFFF5E6D3),       // 浅米色
    darkColor: Color(0xFFD4A5A5),        // 深玫瑰
    textDarkColor: Color(0xFF5C4B51),    // 温暖深棕
    textMediumColor: Color(0xFF8B7B7B),  // 中灰棕
    textLightColor: Color(0xFFB8A8A8),   // 浅灰棕
    name: '温馨米',
  );

  // 薄荷绿
  static const ThemeScheme mint = ThemeScheme(
    primaryColor: Color(0xFF7DD3C0),
    backgroundColor: Color(0xFFA8D8E6),
    cardColor: Colors.white,
    lightColor: Color(0xFFB8E6D9),
    darkColor: Color(0xFF5BC0A8),
    textDarkColor: Color(0xFF2C3E50),
    textMediumColor: Color(0xFF5D6D7E),
    textLightColor: Color(0xFF95A5A6),
    name: '薄荷绿',
  );

  // 樱花粉
  static const ThemeScheme pink = ThemeScheme(
    primaryColor: Color(0xFFF8BBD0),
    backgroundColor: Color(0xFFFCE4EC),
    cardColor: Colors.white,
    lightColor: Color(0xFFFCE4EC),
    darkColor: Color(0xFFF48FB1),
    textDarkColor: Color(0xFF4A148C),
    textMediumColor: Color(0xFF7B1FA2),
    textLightColor: Color(0xFF9C27B0),
    name: '樱花粉',
  );

  // 天空蓝
  static const ThemeScheme blue = ThemeScheme(
    primaryColor: Color(0xFF90CAF9),
    backgroundColor: Color(0xFFE3F2FD),
    cardColor: Colors.white,
    lightColor: Color(0xFFBBDEFB),
    darkColor: Color(0xFF64B5F6),
    textDarkColor: Color(0xFF0D47A1),
    textMediumColor: Color(0xFF1976D2),
    textLightColor: Color(0xFF42A5F5),
    name: '天空蓝',
  );

  // 活力橙
  static const ThemeScheme orange = ThemeScheme(
    primaryColor: Color(0xFFFFCC80),
    backgroundColor: Color(0xFFFFF3E0),
    cardColor: Colors.white,
    lightColor: Color(0xFFFFE0B2),
    darkColor: Color(0xFFFFB74D),
    textDarkColor: Color(0xFFE65100),
    textMediumColor: Color(0xFFEF6C00),
    textLightColor: Color(0xFFF57C00),
    name: '活力橙',
  );

  // 薰衣草紫
  static const ThemeScheme purple = ThemeScheme(
    primaryColor: Color(0xFFCE93D8),
    backgroundColor: Color(0xFFF3E5F5),
    cardColor: Colors.white,
    lightColor: Color(0xFFE1BEE7),
    darkColor: Color(0xFFBA68C8),
    textDarkColor: Color(0xFF4A148C),
    textMediumColor: Color(0xFF6A1B9A),
    textLightColor: Color(0xFF8E24AA),
    name: '薰衣草紫',
  );

  // 珊瑚红
  static const ThemeScheme coral = ThemeScheme(
    primaryColor: Color(0xFFFFAB91),
    backgroundColor: Color(0xFFFBE9E7),
    cardColor: Colors.white,
    lightColor: Color(0xFFFFCCBC),
    darkColor: Color(0xFFFF8A65),
    textDarkColor: Color(0xFFBF360C),
    textMediumColor: Color(0xFFD84315),
    textLightColor: Color(0xFFEF6C00),
    name: '珊瑚红',
  );

  // 森林绿
  static const ThemeScheme green = ThemeScheme(
    primaryColor: Color(0xFFA5D6A7),
    backgroundColor: Color(0xFFE8F5E9),
    cardColor: Colors.white,
    lightColor: Color(0xFFC8E6C9),
    darkColor: Color(0xFF81C784),
    textDarkColor: Color(0xFF1B5E20),
    textMediumColor: Color(0xFF2E7D32),
    textLightColor: Color(0xFF388E3C),
    name: '森林绿',
  );

  // 玫瑰红
  static const ThemeScheme rose = ThemeScheme(
    primaryColor: Color(0xFFEF9A9A),
    backgroundColor: Color(0xFFFFEBEE),
    cardColor: Colors.white,
    lightColor: Color(0xFFFFCDD2),
    darkColor: Color(0xFFE57373),
    textDarkColor: Color(0xFFB71C1C),
    textMediumColor: Color(0xFFC62828),
    textLightColor: Color(0xFFE53935),
    name: '玫瑰红',
  );

  // 🌌 星空主题 - 深邃梦幻的星空氛围
  static const ThemeScheme starry = ThemeScheme(
    primaryColor: Color(0xFF7C4DFF),      // 梦幻紫
    backgroundColor: Color(0xFF0D0D1F),   // 深蓝黑背景
    cardColor: Colors.white,              // 白色卡片（参考自定义颜色）
    lightColor: Color(0xFF2D1B4E),        // 紫罗兰高光
    darkColor: Color(0xFF5B7CFF),         // 星空蓝
    textDarkColor: Color(0xFF2D2D4A),     // 主要文字：深紫黑（在白色卡片上可见）
    textMediumColor: Color(0xFF4A4A6A),   // 次要文字：中紫灰
    textLightColor: Color(0xFF7A7A9A),    // 辅助文字：浅紫灰
    iconColor: Color(0xFF7C4DFF),         // 图标：梦幻紫（主题色）
    name: '星空主题',
  );

  // 🌸 樱花主题 - 浪漫飘落的樱花
  static const ThemeScheme sakura = ThemeScheme(
    primaryColor: Color(0xFFF48FB1),      // 樱花粉
    backgroundColor: Color(0xFFFFF5F7),   // 极浅粉背景
    cardColor: Color(0xFFFFFFFF),         // 白色卡片（与gacha_service一致）
    lightColor: Color(0xFFFCE4EC),        // 淡粉高光
    darkColor: Color(0xFFF8BBD0),         // 深粉
    textDarkColor: Color(0xFF880E4F),     // 深玫红文字
    textMediumColor: Color(0xFFC2185B),   // 中玫红
    textLightColor: Color(0xFFF06292),    // 浅玫红
    name: '樱花主题',
  );

  // 🌊 海洋主题 - 流动舒缓的波浪
  static const ThemeScheme ocean = ThemeScheme(
    primaryColor: Color(0xFF42A5F5),      // 海洋蓝
    backgroundColor: Color(0xFFE3F2FD),   // 浅天蓝背景
    cardColor: Color(0xFFFFFFFF),         // 白色卡片（与gacha_service一致）
    lightColor: Color(0xFFBBDEFB),        // 天蓝高光（与gacha_service一致）
    darkColor: Color(0xFF90CAF9),         // 深天蓝（与gacha_service一致）
    textDarkColor: Color(0xFF0D47A1),     // 深蓝文字
    textMediumColor: Color(0xFF1565C0),   // 中蓝
    textLightColor: Color(0xFF42A5F5),    // 浅蓝
    name: '海洋主题',
  );

  // 🌌 极光主题 - 翠绿色极光（与星空主题区分开）
  static const ThemeScheme aurora = ThemeScheme(
    primaryColor: Color(0xFF00C060),      // 青绿主色（稍微偏绿）
    backgroundColor: Color(0xFF001810),   // 深绿黑背景
    cardColor: Color(0xFF003328),         // 深青绿卡片
    lightColor: Color(0xFF009060),        // 深青绿（稍微偏绿）
    darkColor: Color(0xFF00FFC0),         // 亮青绿（稍微偏绿）
    textDarkColor: Color(0xFFE0F7FA),     // 浅青白文字
    textMediumColor: Color(0xFF80DEEA),   // 中青
    textLightColor: Color(0xFF4DD0E1),    // 浅青
    name: '极光主题',
  );

  // ✨ 黄金主题 - 华丽的金色粒子
  static const ThemeScheme golden = ThemeScheme(
    primaryColor: Color(0xFFFFD700),      // 黄金色
    backgroundColor: Color(0xFFFFF8E1),   // 极浅金背景
    cardColor: Color(0xFFFFECB3),         // 浅金卡片
    lightColor: Color(0xFFFFE082),        // 中金黄
    darkColor: Color(0xFFFFB300),         // 深金黄
    textDarkColor: Color(0xFF5D4037),     // 深棕文字
    textMediumColor: Color(0xFF795548),   // 中棕
    textLightColor: Color(0xFFA1887F),    // 浅棕
    name: '黄金主题',
  );
}

/// 主题设置 Provider
class ThemeProvider extends ChangeNotifier {
  static const String _themeColorKey = 'theme_color';
  static const String _themeNameKey = 'theme_name'; // 保存主题名称，用于识别特殊主题
  static const String _isDarkModeKey = 'is_dark_mode';
  static const String _fontSizeKey = 'font_size';

  ThemeScheme _currentScheme = ThemeScheme.warmBeige;
  bool _isDarkMode = false;
  double _fontSize = 1.0;
  bool _isLoaded = false;

  // Getters
  ThemeScheme get currentScheme => _currentScheme;
  bool get isDarkMode => _isDarkMode;
  double get fontSize => _fontSize;
  bool get isLoaded => _isLoaded;
  Color get primaryColor => _currentScheme.primaryColor;

  // 获取当前主题
  ThemeData get theme {
    final scheme = _currentScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: scheme.backgroundColor,
      colorScheme: ColorScheme.light(
        primary: scheme.primaryColor,
        secondary: scheme.darkColor,
        surface: scheme.surfaceColor,
        surfaceContainerHighest: scheme.cardColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: scheme.textDarkColor,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.textDarkColor,
        titleTextStyle: TextStyle(
          color: scheme.textDarkColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: scheme.iconColor ?? scheme.textDarkColor),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: scheme.cardColor,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide:
              BorderSide(color: scheme.lightColor.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primaryColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconTheme: IconThemeData(
        color: scheme.iconColor ?? scheme.textMediumColor,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.dividerColor,
        thickness: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.cardColor,
        selectedItemColor: scheme.primaryColor,
        unselectedItemColor: scheme.textLightColor,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      textTheme: _getTextTheme(),
    );
  }

  TextTheme _getTextTheme() {
    final scheme = _currentScheme;
    return TextTheme(
      bodyLarge:
          TextStyle(fontSize: 16 * _fontSize, color: scheme.textDarkColor),
      bodyMedium:
          TextStyle(fontSize: 14 * _fontSize, color: scheme.textMediumColor),
      bodySmall:
          TextStyle(fontSize: 12 * _fontSize, color: scheme.textLightColor),
      titleLarge: TextStyle(
          fontSize: 22 * _fontSize,
          fontWeight: FontWeight.bold,
          color: scheme.textDarkColor),
      titleMedium: TextStyle(
          fontSize: 16 * _fontSize,
          fontWeight: FontWeight.w600,
          color: scheme.textDarkColor),
      titleSmall: TextStyle(
          fontSize: 14 * _fontSize,
          fontWeight: FontWeight.w500,
          color: scheme.textMediumColor),
      headlineLarge: TextStyle(
          fontSize: 32 * _fontSize,
          fontWeight: FontWeight.bold,
          color: scheme.textDarkColor),
      headlineMedium: TextStyle(
          fontSize: 24 * _fontSize,
          fontWeight: FontWeight.bold,
          color: scheme.textDarkColor),
      headlineSmall: TextStyle(
          fontSize: 20 * _fontSize,
          fontWeight: FontWeight.w600,
          color: scheme.textDarkColor),
    );
  }

  // 加载设置
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 首先尝试通过主题名称加载（更可靠，用于识别特殊主题）
      final savedName = prefs.getString(_themeNameKey);
      if (savedName != null) {
        final schemeByName = _findSchemeByName(savedName);
        if (schemeByName != null) {
          _currentScheme = schemeByName;
        } else {
          // 如果通过名称找不到，回退到颜色匹配
          await _loadByColor(prefs);
        }
      } else {
        // 兼容旧版本：通过颜色加载
        await _loadByColor(prefs);
      }

      // 加载暗黑模式
      _isDarkMode = prefs.getBool(_isDarkModeKey) ?? false;

      // 加载字体大小
      _fontSize = prefs.getDouble(_fontSizeKey) ?? 1.0;

      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('加载设置失败: $e');
      _isLoaded = true;
    }
  }

  // 通过颜色加载主题（兼容旧版本）
  Future<void> _loadByColor(SharedPreferences prefs) async {
    final colorValue = prefs.getInt(_themeColorKey);
    if (colorValue != null) {
      final savedColor = Color(colorValue);
      final scheme = _findSchemeByColor(savedColor);
      // 如果是预设颜色，使用预设方案；否则创建自定义方案
      if (scheme.primaryColor.value == savedColor.value) {
        _currentScheme = scheme;
      } else {
        _currentScheme = _createSchemeFromColor(savedColor);
      }
    }
  }

  // 根据名称查找配色方案
  ThemeScheme? _findSchemeByName(String name) {
    // 先检查预设主题
    for (final scheme in presetSchemes) {
      if (scheme.name == name) {
        return scheme;
      }
    }
    // 再检查特殊主题
    for (final scheme in specialThemes) {
      if (scheme.name == name) {
        return scheme;
      }
    }
    return null;
  }

  // 根据颜色查找配色方案（包括特殊主题）
  ThemeScheme _findSchemeByColor(Color color) {
    // 先检查预设主题
    for (final scheme in presetSchemes) {
      if (scheme.primaryColor.value == color.value) {
        return scheme;
      }
    }
    // 再检查特殊主题
    for (final scheme in specialThemes) {
      if (scheme.primaryColor.value == color.value) {
        return scheme;
      }
    }
    // 返回一个标记，表示未找到（使用 mint 但可以通过比较判断）
    return ThemeScheme.mint;
  }

  // 检查是否为预设颜色（包括特殊主题）
  bool _isPresetColor(Color color) {
    for (final scheme in presetSchemes) {
      if (scheme.primaryColor.value == color.value) {
        return true;
      }
    }
    for (final scheme in specialThemes) {
      if (scheme.primaryColor.value == color.value) {
        return true;
      }
    }
    return false;
  }

  // 设置主题方案
  Future<void> setThemeScheme(ThemeScheme scheme) async {
    _currentScheme = scheme;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeColorKey, scheme.primaryColor.value);
      // 同时保存主题名称，用于识别特殊主题
      await prefs.setString(_themeNameKey, scheme.name);
    } catch (e) {
      debugPrint('保存主题色失败: $e');
    }
  }

  // 设置主题色（兼容旧方法）
  Future<void> setPrimaryColor(Color color) async {
    // 检查是否为预设颜色
    if (_isPresetColor(color)) {
      // 使用预设配色
      final scheme = _findSchemeByColor(color);
      await setThemeScheme(scheme);
    } else {
      // 自定义颜色 - 创建新的配色方案
      final customScheme = _createSchemeFromColor(color);
      _currentScheme = customScheme;
      notifyListeners();

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_themeColorKey, color.value);
        // 清除主题名称，表示这是自定义颜色
        await prefs.remove(_themeNameKey);
      } catch (e) {
        debugPrint('保存自定义主题色失败: $e');
      }
    }
  }

  // 根据主色创建完整配色方案
  ThemeScheme _createSchemeFromColor(Color primaryColor) {
    // 生成相关颜色
    final hsl = HSLColor.fromColor(primaryColor);

    // 如果主色很深，降低饱和度使背景更舒适
    final saturation = hsl.lightness < 0.3
        ? (hsl.saturation * 0.6).clamp(0.0, 1.0)
        : hsl.saturation;
    final adjustedHsl = hsl.withSaturation(saturation);

    // 背景色 - 确保足够亮（最小0.45），这样文字始终用深色即可
    final backgroundLightness = (adjustedHsl.lightness + 0.4).clamp(0.45, 0.95);
    final backgroundColor =
        adjustedHsl.withLightness(backgroundLightness).toColor();

    // 卡片色 - 始终使用白色，与背景形成对比
    const cardColor = Colors.white;

    // 浅色 - 用于渐变等
    final lightLightness = (adjustedHsl.lightness + 0.25).clamp(0.35, 0.9);
    final lightColor = adjustedHsl.withLightness(lightLightness).toColor();

    // 深色 - 用于按钮等
    final darkLightness = (adjustedHsl.lightness - 0.1).clamp(0.25, 0.65);
    final darkColor = adjustedHsl.withLightness(darkLightness).toColor();

    // 文本颜色 - 根据主色色调生成协调的深色文本
    // 保持与主色相同的色调，但降低饱和度和亮度，使其成为深色
    final textHsl = adjustedHsl
        .withSaturation((adjustedHsl.saturation * 0.3).clamp(0.0, 0.4))
        .withLightness(0.25);
    final textDarkColor = textHsl.toColor();

    final textMediumHsl = adjustedHsl
        .withSaturation((adjustedHsl.saturation * 0.25).clamp(0.0, 0.35))
        .withLightness(0.4);
    final textMediumColor = textMediumHsl.toColor();

    final textLightHsl = adjustedHsl
        .withSaturation((adjustedHsl.saturation * 0.2).clamp(0.0, 0.3))
        .withLightness(0.55);
    final textLightColor = textLightHsl.toColor();

    return ThemeScheme(
      primaryColor: primaryColor,
      backgroundColor: backgroundColor,
      cardColor: cardColor,
      lightColor: lightColor,
      darkColor: darkColor,
      textDarkColor: textDarkColor,
      textMediumColor: textMediumColor,
      textLightColor: textLightColor,
      name: '自定义',
    );
  }

  // 切换暗黑模式
  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isDarkModeKey, _isDarkMode);
    } catch (e) {
      debugPrint('保存暗黑模式设置失败: $e');
    }
  }

  // 设置字体大小
  Future<void> setFontSize(double size) async {
    _fontSize = size.clamp(0.8, 1.5);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_fontSizeKey, _fontSize);
    } catch (e) {
      debugPrint('保存字体大小失败: $e');
    }
  }

  // 重置为默认设置
  Future<void> resetToDefault() async {
    _currentScheme = ThemeScheme.mint;
    _isDarkMode = false;
    _fontSize = 1.0;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_themeColorKey);
      await prefs.remove(_isDarkModeKey);
      await prefs.remove(_fontSizeKey);
    } catch (e) {
      debugPrint('重置设置失败: $e');
    }
  }

  // 预设配色方案列表
  static List<ThemeScheme> get presetSchemes => [
        ThemeScheme.warmBeige,  // 温馨米（默认）
        ThemeScheme.mint,
        ThemeScheme.pink,
        ThemeScheme.blue,
        ThemeScheme.orange,
        ThemeScheme.purple,
        ThemeScheme.coral,
        ThemeScheme.green,
        ThemeScheme.rose,
      ];

  // 主题商店特殊主题列表
  static List<ThemeScheme> get specialThemes => [
        ThemeScheme.starry,
        ThemeScheme.sakura,
        ThemeScheme.ocean,
        ThemeScheme.aurora,
        ThemeScheme.golden,
      ];

  // 预设主题色（兼容旧方法）
  static List<Color> get presetColors =>
      presetSchemes.map((s) => s.primaryColor).toList();
}
