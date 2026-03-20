import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 音效服务 - 提供系统音效反馈
class SoundService {
  static AudioPlayer? _audioPlayer;
  static bool _initialized = false;
  static bool _soundEnabled = true;
  
  /// 初始化音效服务
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      _audioPlayer = AudioPlayer();
      _initialized = true;
    } catch (e) {
      debugPrint('音效初始化失败: $e');
    }
  }
  
  /// 设置音效开关
  static void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
  }
  
  /// 释放资源
  static Future<void> dispose() async {
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    _initialized = false;
  }
  
  /// 播放系统点击音效（使用点击声音）
  static Future<void> playClick() async {
    // 触感反馈
    await HapticFeedback.lightImpact();
    
    // 音效（使用系统音效）
    if (_soundEnabled && _audioPlayer != null) {
      try {
        // 使用极短的静音来触发系统点击反馈效果
        // 或者使用系统音效
        await SystemSound.play(SystemSoundType.click);
      } catch (e) {
        // 忽略音效错误
      }
    }
  }

  /// 确认音效
  static Future<void> playConfirm() async {
    await HapticFeedback.mediumImpact();
    if (_soundEnabled) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (e) {
        // 忽略错误
      }
    }
  }

  /// 删除/警告音效
  static Future<void> playDelete() async {
    await HapticFeedback.heavyImpact();
  }

  /// 成功音效
  static Future<void> playSuccess() async {
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }

  /// 错误音效
  static Future<void> playError() async {
    await HapticFeedback.heavyImpact();
  }
  
  /// 打字/输入音效 - 轻柔的反馈
  static Future<void> playType() async {
    if (_soundEnabled) {
      try {
        await HapticFeedback.selectionClick();
      } catch (e) {
        // 忽略错误
      }
    }
  }
  
  /// 翻页音效
  static Future<void> playPageTurn() async {
    await HapticFeedback.lightImpact();
  }
  
  /// 徽章解锁音效
  static Future<void> playBadgeUnlock() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.lightImpact();
  }
}
