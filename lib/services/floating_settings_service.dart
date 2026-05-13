import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 浮窗设置数据模型
class FloatingSettings {
  // === 功能设置 ===
  final bool useTags;
  final double fontSize;
  final bool syncToNotification;
  final bool syncToSelfTalk;
  final bool showWordCount;
  final bool autoHideBar;
  final int autoHideDelaySeconds;

  // === 浮窗外观设置 ===
  final double inputOpacity;
  final int doubleTapSensitivityMs;
  final bool autoHideToEdge;
  final FloatingWindowSize windowSize;
  final Color iconColor;
  final String iconEmoji;
  final double iconOpacity;

  // === 状态记忆 ===
  final double barWidth;
  final double barHeight;
  final double posX;
  final double posY;

  const FloatingSettings({
    this.useTags = true,
    this.fontSize = 15,
    this.syncToNotification = true,
    this.syncToSelfTalk = true,
    this.showWordCount = true,
    this.autoHideBar = false,
    this.autoHideDelaySeconds = 5,
    this.inputOpacity = 0.95,
    this.doubleTapSensitivityMs = 300,
    this.autoHideToEdge = true,
    this.windowSize = FloatingWindowSize.medium,
    this.iconColor = const Color(0xFF7C4DFF),
    this.iconEmoji = '💡',
    this.iconOpacity = 1.0,
    this.barWidth = 320,
    this.barHeight = 120,
    this.posX = -1, // -1 表示未初始化，使用默认位置
    this.posY = -1,
  });

  Map<String, dynamic> toMap() {
    return {
      'useTags': useTags,
      'fontSize': fontSize,
      'syncToNotification': syncToNotification,
      'syncToSelfTalk': syncToSelfTalk,
      'showWordCount': showWordCount,
      'autoHideBar': autoHideBar,
      'autoHideDelaySeconds': autoHideDelaySeconds,
      'inputOpacity': inputOpacity,
      'doubleTapSensitivityMs': doubleTapSensitivityMs,
      'autoHideToEdge': autoHideToEdge,
      'windowSize': windowSize.index,
      // ignore: deprecated_member_use
      'iconColor': iconColor.toARGB32(),
      'iconEmoji': iconEmoji,
      'iconOpacity': iconOpacity,
      'barWidth': barWidth,
      'barHeight': barHeight,
      'posX': posX,
      'posY': posY,
    };
  }

  factory FloatingSettings.fromMap(Map<String, dynamic> map) {
    return FloatingSettings(
      useTags: map['useTags'] as bool? ?? true,
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 15,
      syncToNotification: map['syncToNotification'] as bool? ?? true,
      syncToSelfTalk: map['syncToSelfTalk'] as bool? ?? true,
      showWordCount: map['showWordCount'] as bool? ?? true,
      autoHideBar: map['autoHideBar'] as bool? ?? false,
      autoHideDelaySeconds: map['autoHideDelaySeconds'] as int? ?? 5,
      inputOpacity: (map['inputOpacity'] as num?)?.toDouble() ?? 0.95,
      doubleTapSensitivityMs: map['doubleTapSensitivityMs'] as int? ?? 300,
      autoHideToEdge: map['autoHideToEdge'] as bool? ?? true,
      windowSize: FloatingWindowSize.values[map['windowSize'] as int? ?? 1],
      iconColor: Color(map['iconColor'] as int? ?? 0xFF7C4DFF),
      iconEmoji: map['iconEmoji'] as String? ?? '💡',
      iconOpacity: (map['iconOpacity'] as num?)?.toDouble() ?? 1.0,
      barWidth: (map['barWidth'] as num?)?.toDouble() ?? 320,
      barHeight: (map['barHeight'] as num?)?.toDouble() ?? 120,
      posX: (map['posX'] as num?)?.toDouble() ?? -1,
      posY: (map['posY'] as num?)?.toDouble() ?? -1,
    );
  }

  FloatingSettings copyWith({
    bool? useTags,
    double? fontSize,
    bool? syncToNotification,
    bool? syncToSelfTalk,
    bool? showWordCount,
    bool? autoHideBar,
    int? autoHideDelaySeconds,
    double? inputOpacity,
    int? doubleTapSensitivityMs,
    bool? autoHideToEdge,
    FloatingWindowSize? windowSize,
    Color? iconColor,
    String? iconEmoji,
    double? iconOpacity,
    double? barWidth,
    double? barHeight,
    double? posX,
    double? posY,
  }) {
    return FloatingSettings(
      useTags: useTags ?? this.useTags,
      fontSize: fontSize ?? this.fontSize,
      syncToNotification: syncToNotification ?? this.syncToNotification,
      syncToSelfTalk: syncToSelfTalk ?? this.syncToSelfTalk,
      showWordCount: showWordCount ?? this.showWordCount,
      autoHideBar: autoHideBar ?? this.autoHideBar,
      autoHideDelaySeconds: autoHideDelaySeconds ?? this.autoHideDelaySeconds,
      inputOpacity: inputOpacity ?? this.inputOpacity,
      doubleTapSensitivityMs: doubleTapSensitivityMs ?? this.doubleTapSensitivityMs,
      autoHideToEdge: autoHideToEdge ?? this.autoHideToEdge,
      windowSize: windowSize ?? this.windowSize,
      iconColor: iconColor ?? this.iconColor,
      iconEmoji: iconEmoji ?? this.iconEmoji,
      iconOpacity: iconOpacity ?? this.iconOpacity,
      barWidth: barWidth ?? this.barWidth,
      barHeight: barHeight ?? this.barHeight,
      posX: posX ?? this.posX,
      posY: posY ?? this.posY,
    );
  }
}

/// 悬浮窗大小选项
enum FloatingWindowSize {
  small,  // 小
  medium, // 中
  large,  // 大
}

/// 浮窗设置持久化服务
class FloatingSettingsService {
  static const String _settingsKey = 'floating_window_settings';
  static const String _enabledKey = 'floating_window_enabled';

  /// 读取设置
  static Future<FloatingSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_settingsKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return const FloatingSettings();
    }
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return FloatingSettings.fromMap(map);
    } catch (_) {
      return const FloatingSettings();
    }
  }

  /// 保存设置
  static Future<void> save(FloatingSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toMap()));
  }

  /// 获取浮窗总开关状态
  static Future<bool> getEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// 设置浮窗总开关
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// 更新部分设置（自动保存）
  static Future<FloatingSettings> update({
    bool? useTags,
    double? fontSize,
    bool? syncToNotification,
    bool? syncToSelfTalk,
    bool? showWordCount,
    bool? autoHideBar,
    int? autoHideDelaySeconds,
    double? inputOpacity,
    int? doubleTapSensitivityMs,
    bool? autoHideToEdge,
    FloatingWindowSize? windowSize,
    Color? iconColor,
    String? iconEmoji,
    double? iconOpacity,
    double? barWidth,
    double? barHeight,
    double? posX,
    double? posY,
  }) async {
    final current = await load();
    final updated = current.copyWith(
      useTags: useTags,
      fontSize: fontSize,
      syncToNotification: syncToNotification,
      syncToSelfTalk: syncToSelfTalk,
      showWordCount: showWordCount,
      autoHideBar: autoHideBar,
      autoHideDelaySeconds: autoHideDelaySeconds,
      inputOpacity: inputOpacity,
      doubleTapSensitivityMs: doubleTapSensitivityMs,
      autoHideToEdge: autoHideToEdge,
      windowSize: windowSize,
      iconColor: iconColor,
      iconEmoji: iconEmoji,
      iconOpacity: iconOpacity,
      barWidth: barWidth,
      barHeight: barHeight,
      posX: posX,
      posY: posY,
    );
    await save(updated);
    return updated;
  }

  /// 保存浮窗位置
  static Future<void> savePosition(double x, double y) async {
    await update(posX: x, posY: y);
  }

  /// 保存速记条大小
  static Future<void> saveBarSize(double width, double height) async {
    await update(barWidth: width, barHeight: height);
  }

  /// 还原速记条默认大小
  static Future<FloatingSettings> resetBarSize() async {
    return await update(barWidth: 320, barHeight: 120);
  }

  /// 获取窗口尺寸（根据设置的大小选项）
  static double getWindowSizePixels(FloatingWindowSize size) {
    switch (size) {
      case FloatingWindowSize.small:
        return 48;
      case FloatingWindowSize.medium:
        return 64;
      case FloatingWindowSize.large:
        return 80;
    }
  }
}
