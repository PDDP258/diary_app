import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'floating_settings_service.dart';

/// 浮窗生命周期管理服务
///
/// 封装 flutter_overlay_window 包，提供统一的浮窗控制接口
class FloatingWindowService {
  static bool _isShowingBar = false;

  /// 检查浮窗是否正在显示
  static Future<bool> isActive() async {
    return await FlutterOverlayWindow.isActive();
  }

  /// 显示小浮窗按钮
  static Future<void> showFloatingButton() async {
    final settings = await FloatingSettingsService.load();
    final windowSize = FloatingSettingsService.getWindowSizePixels(settings.windowSize);

    if (await isActive()) {
      await closeFloatingWindow();
    }

    await FlutterOverlayWindow.showOverlay(
      height: windowSize.toInt(),
      width: windowSize.toInt(),
      alignment: OverlayAlignment.topRight,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: '小记速记',
      overlayContent: '双击打开速记',
      enableDrag: true,
      positionGravity: PositionGravity.none,
    );

    _isShowingBar = false;
  }

  /// 显示速记条（在浮窗内切换到速记条模式）
  ///
  /// 通过 OverlayWindow 的数据通道通知浮窗切换 UI
  static Future<void> showQuickNoteBar() async {
    final settings = await FloatingSettingsService.load();

    if (!await isActive()) {
      // 如果浮窗未显示，先显示再切换
      await FlutterOverlayWindow.showOverlay(
        height: settings.barHeight.toInt(),
        width: settings.barWidth.toInt(),
        alignment: OverlayAlignment.center,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: '小记速记',
        overlayContent: '速记条',
        enableDrag: true,
        positionGravity: PositionGravity.none,
      );
    } else {
      // 已显示，调整大小为速记条尺寸
      await FlutterOverlayWindow.resizeOverlay(
        settings.barWidth.toInt(),
        settings.barHeight.toInt(),
        true,
      );
    }

    // 发送消息通知浮窗切换到速记条模式
    await FlutterOverlayWindow.shareData(jsonEncode({
      'action': 'show_bar',
      'width': settings.barWidth,
      'height': settings.barHeight,
    }));

    _isShowingBar = true;
    HapticFeedback.mediumImpact();
  }

  /// 关闭速记条，回到小浮窗
  static Future<void> hideQuickNoteBar() async {
    if (!await isActive()) return;

    final settings = await FloatingSettingsService.load();
    final windowSize = FloatingSettingsService.getWindowSizePixels(settings.windowSize);

    // 调整回小浮窗大小
    await FlutterOverlayWindow.resizeOverlay(
      windowSize.toInt(),
      windowSize.toInt(),
      true,
    );

    // 发送消息通知浮窗切换回按钮模式
    await FlutterOverlayWindow.shareData(jsonEncode({
      'action': 'show_button',
    }));

    _isShowingBar = false;
  }

  /// 完全关闭浮窗
  static Future<void> closeFloatingWindow() async {
    if (await isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
    _isShowingBar = false;
  }

  /// 切换浮窗显示/隐藏
  static Future<void> toggle() async {
    if (await isActive()) {
      await closeFloatingWindow();
    } else {
      await showFloatingButton();
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
      return const Offset(-1, -1); // 表示未设置
    }
    return Offset(settings.posX, settings.posY);
  }

  /// 当前是否显示速记条
  static bool get isShowingBar => _isShowingBar;
}
