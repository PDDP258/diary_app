import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'floating_settings_service.dart';
import 'native_floating_service.dart';

/// 浮窗生命周期管理服务
///
/// 对外提供统一的浮窗控制接口，内部委托给 NativeFloatingService（原生 Kotlin 实现）。
/// 此层保持接口稳定，调用方（如 profile_screen.dart）无需修改。
class FloatingWindowService {
  static bool _isShowingBar = false;
  static bool _isInitialized = false;

  /// 初始化回调（应在应用启动时调用）
  static void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    NativeFloatingService.registerCallbacks();
    developer.log('FloatingWindowService initialized', name: 'FloatingWindow');
  }

  /// 检查浮窗是否正在显示
  static Future<bool> isActive() async {
    try {
      return await NativeFloatingService.isServiceRunning();
    } catch (e) {
      developer.log('isActive error: $e', name: 'FloatingWindow');
      return false;
    }
  }

  /// 显示小浮窗按钮
  static Future<bool> showFloatingButton() async {
    try {
      // 如果已经显示，先关闭再重新显示
      if (await isActive()) {
        await closeFloatingWindow();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      developer.log('Showing floating button via native service', name: 'FloatingWindow');
      final success = await NativeFloatingService.showFloatingButton();

      _isShowingBar = false;
      return success;
    } catch (e, stack) {
      developer.log('showFloatingButton error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 显示速记条（在浮窗内切换到速记条模式）
  static Future<bool> showQuickNoteBar() async {
    try {
      if (!await isActive()) {
        // 如果浮窗未显示，先显示按钮
        await showFloatingButton();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final success = await NativeFloatingService.showQuickNotePanel();
      _isShowingBar = true;
      return success;
    } catch (e, stack) {
      developer.log('showQuickNoteBar error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 关闭速记条，回到小浮窗
  static Future<bool> hideQuickNoteBar() async {
    try {
      if (!await isActive()) return false;
      final success = await NativeFloatingService.hideQuickNotePanel();
      _isShowingBar = false;
      return success;
    } catch (e, stack) {
      developer.log('hideQuickNoteBar error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 完全关闭浮窗
  static Future<bool> closeFloatingWindow() async {
    try {
      final success = await NativeFloatingService.hideFloatingWindow();
      _isShowingBar = false;
      return success;
    } catch (e, stack) {
      developer.log('closeFloatingWindow error: $e\n$stack', name: 'FloatingWindow');
      return false;
    }
  }

  /// 切换浮窗显示/隐藏
  static Future<bool> toggle() async {
    if (await isActive()) {
      return await closeFloatingWindow();
    } else {
      return await showFloatingButton();
    }
  }

  /// 保存浮窗位置
  static Future<void> savePosition(double x, double y) async {
    await FloatingSettingsService.savePosition(x, y);
  }

  /// 获取保存的浮窗位置
  static Future<Offset> getSavedPosition() async {
    final settings = await FloatingSettingsService.load();
    if (settings.posX < 0 || settings.posY < 0) {
      return const Offset(-1, -1);
    }
    return Offset(settings.posX, settings.posY);
  }

  /// 当前是否显示速记条
  static bool get isShowingBar => _isShowingBar;
}
