import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「笔迹·成长」图标主题服务
/// 
/// 功能：支持动态切换 Android 应用桌面图标颜色主题
/// 设计哲学：图标是应用的门面，跟随用户喜好变化
/// 
/// 支持的图标主题（4种）：
/// - coral: 珊瑚红（默认）
/// - mint: 青绿色（清新）
/// - pink: 樱花粉（甜美）
/// - starry: 星空主题（商店购买解锁）
class IconThemeService {
  static const MethodChannel _channel =
      MethodChannel('com.diaryapp/icon_theme');

  /// 获取支持的图标主题列表
  static Future<List<String>> getAvailableThemes() async {
    if (!Platform.isAndroid) {
      return [];
    }

    try {
      final List<dynamic> themes = await _channel.invokeMethod('getAvailableThemes');
      return themes.cast<String>();
    } catch (e) {
      print('获取图标主题列表失败: $e');
      return ['coral', 'mint', 'pink', 'starry'];
    }
  }

  /// 获取当前启用的图标主题
  static Future<String> getCurrentTheme() async {
    if (!Platform.isAndroid) {
      return 'coral';
    }

    try {
      final String theme = await _channel.invokeMethod('getCurrentTheme');
      return theme;
    } catch (e) {
      print('获取当前图标主题失败: $e');
      return 'coral';
    }
  }

  /// 设置图标主题
  static Future<bool> setIconTheme(String themeName) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final bool success = await _channel.invokeMethod('setIconTheme', {
        'theme': themeName,
      });
      return success;
    } catch (e) {
      print('设置图标主题失败: $e');
      return false;
    }
  }

  /// 检查星空主题是否已解锁（扭蛋商店购买）
  static Future<bool> isStarryThemeUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final unlockedThemes = prefs.getStringList('unlocked_themes') ?? [];
    return unlockedThemes.contains('theme_starry');
  }

  /// 检查樱花粉主题是否已解锁（扭蛋商店购买樱花主题）
  static Future<bool> isPinkThemeUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final unlockedThemes = prefs.getStringList('unlocked_themes') ?? [];
    return unlockedThemes.contains('theme_sakura');
  }

  /// 检查青绿色主题是否已解锁（扭蛋商店购买极光主题）
  static Future<bool> isMintThemeUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final unlockedThemes = prefs.getStringList('unlocked_themes') ?? [];
    return unlockedThemes.contains('theme_aurora');
  }

  /// 主题颜色映射（用于 UI 展示）
  static final Map<String, Map<String, dynamic>> themeMap = {
    'coral': {
      'name': '珊瑚红',
      'color': 0xFFFF6B6B,
      'description': '温暖热情，默认主题',
      'emoji': '🔴',
      'locked': false,
    },
    'mint': {
      'name': '青绿色',
      'color': 0xFF4ECDC4,
      'description': '清新自然（扭蛋商店解锁）',
      'emoji': '🟢',
      'locked': true, // 需要解锁
      'themeId': 'theme_aurora', // 对应商店极光主题ID
    },
    'pink': {
      'name': '樱花粉',
      'color': 0xFFFF8FB8,
      'description': '甜美浪漫（扭蛋商店解锁）',
      'emoji': '🩷',
      'locked': true, // 需要解锁
      'themeId': 'theme_sakura', // 对应商店樱花主题ID
    },
    'starry': {
      'name': '星空主题',
      'color': 0xFF1A1A2E,
      'description': '深邃梦幻（扭蛋商店解锁）',
      'emoji': '🌌',
      'locked': true, // 需要解锁
      'themeId': 'theme_starry', // 对应商店主题ID
    },
  };

  /// 获取主题显示名称
  static String getThemeName(String themeKey) {
    return themeMap[themeKey]?['name'] ?? '珊瑚红';
  }

  /// 获取主题颜色
  static int getThemeColor(String themeKey) {
    return themeMap[themeKey]?['color'] ?? 0xFFFF6B6B;
  }

  /// 检查是否支持图标主题切换
  static bool get isSupported => Platform.isAndroid;
}
