import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// 浮窗系统权限管理服务
///
/// 统一管理以下权限：
/// - 外部存储（读写备份文件）
/// - 悬浮窗（SYSTEM_ALERT_WINDOW，需跳转系统设置）
/// - 通知（POST_NOTIFICATIONS，Android 13+）
/// - 电池优化白名单（保持后台运行）
class FloatingPermissionService {
  /// 顺序请求所有必要权限
  /// 返回每个权限的请求结果 Map
  static Future<Map<String, bool>> requestAllPermissions(BuildContext context) async {
    final results = <String, bool>{};

    // 1. 外部存储权限
    results['storage'] = await requestStoragePermission();
    HapticFeedback.lightImpact();

    // 2. 通知权限（Android 13+）
    results['notification'] = await requestNotificationPermission();
    HapticFeedback.lightImpact();

    // 3. 悬浮窗权限（必须跳转系统设置）
    results['overlay'] = await requestOverlayPermission();
    HapticFeedback.lightImpact();

    // 4. 电池优化白名单
    results['battery'] = await requestBatteryOptimizationWhitelist();

    return results;
  }

  /// 请求外部存储权限
  /// Android 11+ 使用 MANAGE_EXTERNAL_STORAGE，低版本使用 READ/WRITE
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 30) {
        // Android 11+：请求所有文件访问权限
        final status = await Permission.manageExternalStorage.request();
        return status.isGranted;
      } else {
        // Android 10 及以下：传统存储权限
        final writeStatus = await Permission.storage.request();
        return writeStatus.isGranted;
      }
    }
    return true; // iOS/Web 默认通过
  }

  /// 检查外部存储权限
  static Future<bool> checkStoragePermission() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 30) {
        return await Permission.manageExternalStorage.isGranted;
      } else {
        return await Permission.storage.isGranted;
      }
    }
    return true;
  }

  /// 请求通知权限（Android 13+ 需要显式请求）
  static Future<bool> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 33) {
        final status = await Permission.notification.request();
        return status.isGranted;
      }
    }
    return true; // Android 12 及以下默认允许
  }

  /// 检查通知权限
  static Future<bool> checkNotificationPermission() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 33) {
        return await Permission.notification.isGranted;
      }
    }
    return true;
  }

  /// 请求悬浮窗权限
  /// SYSTEM_ALERT_WINDOW 必须跳转到系统设置页面
  static Future<bool> requestOverlayPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.systemAlertWindow.request();
      return status.isGranted;
    }
    return false; // iOS 不支持系统悬浮窗
  }

  /// 检查悬浮窗权限
  static Future<bool> checkOverlayPermission() async {
    if (Platform.isAndroid) {
      return await Permission.systemAlertWindow.isGranted;
    }
    return false;
  }

  /// 请求电池优化白名单
  /// 防止系统杀死后台进程，保持浮窗存活
  static Future<bool> requestBatteryOptimizationWhitelist() async {
    if (Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    }
    return true;
  }

  /// 检查电池优化白名单
  static Future<bool> checkBatteryOptimizationWhitelist() async {
    if (Platform.isAndroid) {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    }
    return true;
  }

  /// 获取 Android SDK 版本号
  static Future<int> _getAndroidSdkInt() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    }
    return 0;
  }

  /// 打开悬浮窗权限设置页面
  static Future<void> openOverlaySettings() async {
    await Permission.systemAlertWindow.request();
  }

  /// 打开电池优化设置页面
  static Future<void> openBatterySettings() async {
    await Permission.ignoreBatteryOptimizations.request();
  }
}
