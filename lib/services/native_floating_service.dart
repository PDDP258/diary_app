import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/self_talk_message.dart';
import 'floating_settings_service.dart';
import 'quick_note_service.dart';
import 'floating_notification_service.dart';
import 'self_talk_service.dart';

/// 原生浮窗 MethodChannel 服务
///
/// 通过 MethodChannel 与 Kotlin 侧的 FloatingWindowPlugin/FloatingWindowService 通信。
/// 这是替代 flutter_overlay_window 的原生实现方案。
class NativeFloatingService {
  static const MethodChannel _channel =
      MethodChannel('com.diary_app/floating_window');

  static bool _callbacksRegistered = false;

  /// 注册回调监听（应在应用启动时调用一次）
  static void registerCallbacks() {
    if (_callbacksRegistered) return;
    _callbacksRegistered = true;

    _channel.setMethodCallHandler(_handleMethodCall);
    developer.log('NativeFloatingService callbacks registered', name: 'FloatingWindow');
  }

  /// 显示浮窗按钮
  static Future<bool> showFloatingButton() async {
    try {
      final settings = await FloatingSettingsService.load();
      // 获取自定义标签列表（如果用户没有自定义标签，使用预设标签）
      final tags = await _getCustomTags();
      // 将 windowSize 枚举映射为 dp 值（与 Kotlin 侧保持一致：48/60/72）
      final sizeDp = settings.windowSize == FloatingWindowSize.small ? 48 :
                     settings.windowSize == FloatingWindowSize.large ? 72 : 60;
      final result = await _channel.invokeMethod('showFloatingButton', {
        'color': _colorToHex(settings.iconColor),
        'opacity': settings.iconOpacity,
        'posX': settings.posX >= 0 ? settings.posX.toInt() : -1,
        'posY': settings.posY >= 0 ? settings.posY.toInt() : -1,
        'tags': tags,
        'autoHideToEdge': settings.autoHideToEdge,
        'doubleTapSensitivityMs': settings.doubleTapSensitivityMs,
        'iconEmoji': settings.iconEmoji,
        'windowSize': sizeDp,
      });
      return result == true;
    } catch (e, stack) {
      developer.log('showFloatingButton error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 隐藏浮窗
  static Future<bool> hideFloatingWindow() async {
    try {
      final result = await _channel.invokeMethod('hideFloatingWindow');
      return result == true;
    } catch (e, stack) {
      developer.log('hideFloatingWindow error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 显示速记面板
  static Future<bool> showQuickNotePanel() async {
    try {
      final settings = await FloatingSettingsService.load();
      final result = await _channel.invokeMethod('showQuickNotePanel', {
        'barWidth': settings.barWidth.toInt(),
        'barHeight': settings.barHeight.toInt(),
        'fontSize': settings.fontSize.toInt(),
      });
      return result == true;
    } catch (e, stack) {
      developer.log('showQuickNotePanel error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 隐藏速记面板
  static Future<bool> hideQuickNotePanel() async {
    try {
      final result = await _channel.invokeMethod('hideQuickNotePanel');
      return result == true;
    } catch (e, stack) {
      developer.log('hideQuickNotePanel error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 更新浮窗设置
  static Future<bool> updateSettings({
    Color? color,
    double? opacity,
  }) async {
    try {
      final result = await _channel.invokeMethod('updateSettings', {
        'color': color != null ? _colorToHex(color) : null,
        'opacity': opacity,
      });
      return result == true;
    } catch (e, stack) {
      developer.log('updateSettings error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 检查服务是否运行
  static Future<bool> isServiceRunning() async {
    try {
      final result = await _channel.invokeMethod('isServiceRunning');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// 处理来自 Kotlin 侧的回调
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    developer.log('Native callback: ${call.method}', name: 'FloatingWindow');

    switch (call.method) {
      case 'onSaveQuickNote':
        final content = call.arguments['content'] as String? ?? '';
        final tag = call.arguments['tag'] as String? ?? '';
        await _saveQuickNote(content, tag);
        return true;

      case 'onPanelShown':
        // 面板已展开，Dart 侧可更新状态
        return true;

      case 'onPanelHidden':
        // 面板已收起
        return true;

      case 'onPositionChanged':
        final x = call.arguments['x'] as int? ?? -1;
        final y = call.arguments['y'] as int? ?? -1;
        await FloatingSettingsService.savePosition(x.toDouble(), y.toDouble());
        return true;

      case 'onOpenMainApp':
        // 长按打开主应用，已在 Kotlin 侧处理
        return true;

      case 'onSettingsChanged':
        // 浮窗设置变更（用户在浮窗设置面板中修改了颜色/透明度/大小/图标）
        final colorHex = call.arguments['color'] as String?;
        final opacity = call.arguments['opacity'] as double?;
        final sizeDp = call.arguments['sizeDp'] as int?;
        final iconEmoji = call.arguments['iconEmoji'] as String?;
        await _updateFloatingSettings(colorHex: colorHex, opacity: opacity, sizeDp: sizeDp, iconEmoji: iconEmoji);
        return true;

      case 'onFunctionSettingsChanged':
        // 功能设置变更（同步开关、字数统计、自动隐藏、双击灵敏度、字体大小、标签）
        final syncToNotification = call.arguments['syncToNotification'] as bool?;
        final syncToSelfTalk = call.arguments['syncToSelfTalk'] as bool?;
        final showWordCount = call.arguments['showWordCount'] as bool?;
        final autoHideToEdge = call.arguments['autoHideToEdge'] as bool?;
        final doubleTapSensitivityMs = call.arguments['doubleTapSensitivityMs'] as int?;
        final fontSize = call.arguments['fontSize'] as int?;
        final useTags = call.arguments['useTags'] as bool?;
        await FloatingSettingsService.update(
          syncToNotification: syncToNotification,
          syncToSelfTalk: syncToSelfTalk,
          showWordCount: showWordCount,
          autoHideToEdge: autoHideToEdge,
          doubleTapSensitivityMs: doubleTapSensitivityMs,
          fontSize: fontSize?.toDouble(),
          useTags: useTags,
        );
        developer.log('Function settings updated from native: syncNotif=$syncToNotification, syncSelfTalk=$syncToSelfTalk, showWordCount=$showWordCount, autoHideEdge=$autoHideToEdge, doubleTap=$doubleTapSensitivityMs, fontSize=$fontSize, useTags=$useTags', name: 'FloatingWindow');
        return true;

      case 'onPanelSizeChanged':
        // 面板大小变更（用户拖动调节）
        final width = call.arguments['width'] as int?;
        final height = call.arguments['height'] as int?;
        if (width != null && height != null) {
          await FloatingSettingsService.saveBarSize(width.toDouble(), height.toDouble());
          developer.log('Panel size saved: ${width}x$height', name: 'FloatingWindow');
        }
        return true;

      default:
        developer.log('Unknown callback: ${call.method}', name: 'FloatingWindow');
        return null;
    }
  }

  /// 将 Color 转为 #RRGGBB 字符串
  static String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  /// 保存速记
  ///
  /// 数据流：
  /// 1. 保存到 QuickNote 数据库
  /// 2. 如果 syncToNotification 开启 → 显示持久通知
  /// 3. 如果 syncToSelfTalk 开启 → 同步到当天自言自语
  static Future<void> _saveQuickNote(String content, String tag) async {
    try {
      final settings = await FloatingSettingsService.load();

      // 1. 保存速记
      await QuickNoteService.insert(content, tag: tag.isEmpty ? null : tag);
      developer.log('Quick note saved from floating window', name: 'FloatingWindow');

      // 2. 同步到通知（如果开启）
      if (settings.syncToNotification) {
        await FloatingNotificationService.showQuickNoteNotification(content);
        developer.log('Quick note synced to notification', name: 'FloatingWindow');
      }

      // 3. 同步到自言自语（如果开启）
      if (settings.syncToSelfTalk) {
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        await SelfTalkService.sendMessage(
          content,
          today,
          senderType: SelfTalkSenderType.me,
        );
        developer.log('Quick note synced to self talk', name: 'FloatingWindow');
      }
    } catch (e, stack) {
      developer.log('Failed to save quick note: $e\n$stack', name: 'FloatingWindow');
    }
  }

  /// 获取自定义标签列表
  static Future<List<String>> _getCustomTags() async {
    try {
      final allTags = await QuickNoteService.getAllTags();
      if (allTags.isNotEmpty) {
        return allTags;
      }
    } catch (e) {
      developer.log('Failed to get custom tags: $e', name: 'FloatingWindow');
    }
    // 默认标签
    return ['灵感', '待办', '备忘', '读书', '想法'];
  }

  /// 更新浮窗设置（来自原生设置面板的变更）
  static Future<void> _updateFloatingSettings({
    String? colorHex,
    double? opacity,
    int? sizeDp,
    String? iconEmoji,
  }) async {
    try {
      Color? color;
      if (colorHex != null) {
        color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
      }
      // sizeDp 映射到 FloatingWindowSize
      FloatingWindowSize? windowSize;
      if (sizeDp != null) {
        if (sizeDp <= 48) {
          windowSize = FloatingWindowSize.small;
        } else if (sizeDp >= 72) {
          windowSize = FloatingWindowSize.large;
        } else {
          windowSize = FloatingWindowSize.medium;
        }
      }
      await FloatingSettingsService.update(
        iconColor: color,
        iconOpacity: opacity,
        windowSize: windowSize,
        iconEmoji: iconEmoji,
      );
      developer.log('Floating settings updated from native: color=$colorHex, opacity=$opacity, size=$sizeDp, iconEmoji=$iconEmoji', name: 'FloatingWindow');
    } catch (e, stack) {
      developer.log('Failed to update floating settings: $e\n$stack', name: 'FloatingWindow');
    }
  }
}
