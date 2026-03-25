import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 生物识别认证服务
/// 
/// 适配说明：
/// - 红米K60：光学屏下指纹（需要FlutterFragmentActivity）
/// - 超声波指纹：同样使用BiometricPrompt API
/// - 电容指纹：侧边/后置指纹，同一套API
/// 
/// 关键要求：
/// 1. Android必须使用FlutterFragmentActivity
/// 2. 需要USE_BIOMETRIC权限
/// 3. 必须用户交互后才能触发（Android系统要求）
class BiometricAuthService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static const String _biometricEnabledKey = 'biometric_auth_enabled';
  static bool _enabled = false;
  static bool _initialized = false;

  static bool get isEnabled => _enabled;

  /// 初始化服务
  static Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_biometricEnabledKey) ?? false;
    _initialized = true;

    debugPrint('BiometricAuthService initialized: enabled=$_enabled');
  }

  /// 获取设备生物识别详细信息
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final info = <String, dynamic>{};
    
    try {
      info['isDeviceSupported'] = await _localAuth.isDeviceSupported();
      info['canCheckBiometrics'] = await _localAuth.canCheckBiometrics;
      info['availableBiometrics'] = await _localAuth.getAvailableBiometrics();
      info['platform'] = Platform.operatingSystem;
      info['platformVersion'] = Platform.operatingSystemVersion;
    } catch (e) {
      info['error'] = e.toString();
    }
    
    return info;
  }

  /// 检查设备是否支持生物识别（基础检查）
  static Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      debugPrint('Error checking device support: $e');
      return false;
    }
  }

  /// 检查是否有可用的生物识别类型
  static Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      debugPrint('Error checking biometrics capability: $e');
      return false;
    }
  }

  /// 获取可用的生物识别类型
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      final types = await _localAuth.getAvailableBiometrics();
      debugPrint('Available biometrics: $types');
      return types;
    } catch (e) {
      debugPrint('Error getting available biometrics: $e');
      return [];
    }
  }

  /// 检查是否有可用的生物识别（完整检查）
  /// 
  /// 对于光学/超声波屏下指纹，需要：
  /// - 设备支持（isDeviceSupported）
  /// - 可以检查生物识别（canCheckBiometrics）
  /// - 有可用的生物识别类型（非空列表）
  static Future<bool> hasAvailableBiometrics() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      if (!isSupported) {
        debugPrint('[Biometric] 设备不支持生物识别');
        return false;
      }

      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) {
        debugPrint('[Biometric] 无法检查生物识别状态');
        return false;
      }

      final available = await _localAuth.getAvailableBiometrics();
      debugPrint('[Biometric] 可用类型: $available');
      
      // 检查是否有任何生物识别类型可用
      if (available.isEmpty) {
        debugPrint('[Biometric] 没有可用的生物识别类型');
        return false;
      }

      // 对于Android，只要有指纹或强生物识别就可用
      final hasFingerprint = available.contains(BiometricType.fingerprint);
      final hasStrong = available.contains(BiometricType.strong);
      
      debugPrint('[Biometric] 有指纹: $hasFingerprint, 有强生物识别: $hasStrong');
      
      return hasFingerprint || hasStrong;
    } catch (e) {
      debugPrint('[Biometric] 检查可用性异常: $e');
      return false;
    }
  }

  /// 执行生物识别认证
  /// 
  /// 【关键】此方法必须在用户交互（如点击按钮）后调用！
  /// Android BiometricPrompt不允许在没有用户交互的情况下自动弹出。
  /// 
  /// 对于红米K60等屏下指纹设备：
  /// - 系统会自动显示指纹图标在屏幕上
  /// - 用户需要触摸屏幕指纹区域
  /// - 无需额外的UI，系统会处理
  static Future<bool> authenticate() async {
    debugPrint('[Biometric] 开始认证流程...');

    if (!_initialized) {
      debugPrint('[Biometric] 服务未初始化，正在初始化...');
      await initialize();
    }

    if (!_enabled) {
      debugPrint('[Biometric] 生物识别未启用');
      return false;
    }

    try {
      // 前置检查
      final available = await hasAvailableBiometrics();
      if (!available) {
        debugPrint('[Biometric] 设备不可用，跳过认证');
        return false;
      }

      debugPrint('[Biometric] 调用系统认证...');

      // 调用系统生物识别
      // local_auth v3.x API - 简化参数
      final result = await _localAuth.authenticate(
        localizedReason: '验证身份以解锁',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: '指纹验证',
            cancelButton: '取消',
            signInHint: '请触摸指纹传感器',
          ),
        ],
      );

      debugPrint('[Biometric] 认证结果: $result');
      return result;
    } on PlatformException catch (e) {
      debugPrint('[Biometric] 平台异常: ${e.code} - ${e.message}');
      
      // 处理特定错误
      switch (e.code) {
        case 'UserCancel':
          debugPrint('[Biometric] 用户取消');
          break;
        case 'NotAvailable':
          debugPrint('[Biometric] 生物识别不可用');
          break;
        case 'NotEnrolled':
          debugPrint('[Biometric] 未录入指纹/面容');
          break;
        case 'PasscodeNotSet':
          debugPrint('[Biometric] 未设置锁屏密码');
          break;
        default:
          debugPrint('[Biometric] 其他错误: ${e.code}');
      }
      return false;
    } catch (e) {
      debugPrint('[Biometric] 认证异常: $e');
      return false;
    }
  }

  /// 启用生物识别认证
  /// 
  /// 会先尝试认证一次以确认设备可用
  static Future<bool> enable() async {
    debugPrint('[Biometric] 尝试启用...');

    // 检查设备支持
    final available = await hasAvailableBiometrics();
    if (!available) {
      debugPrint('[Biometric] 设备不可用，无法启用');
      return false;
    }

    // 尝试认证以确认可用
    try {
      // 临时启用进行测试
      _enabled = true;
      final success = await authenticate();
      
      if (!success) {
        debugPrint('[Biometric] 认证测试失败');
        _enabled = false;
        return false;
      }

      // 保存设置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, true);
      _enabled = true;

      debugPrint('[Biometric] 已启用');
      return true;
    } catch (e) {
      debugPrint('[Biometric] 启用异常: $e');
      _enabled = false;
      return false;
    }
  }

  /// 禁用生物识别认证
  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, false);
    _enabled = false;
    debugPrint('[Biometric] 已禁用');
  }

  /// 切换生物识别启用状态
  static Future<bool> toggle() async {
    if (_enabled) {
      await disable();
      return false;
    } else {
      return await enable();
    }
  }

  /// 获取生物识别类型描述（用于UI显示）
  static String getBiometricTypeDescription(List<BiometricType> types) {
    if (types.isEmpty) return '无';

    final descriptions = <String>[];
    for (final type in types) {
      switch (type) {
        case BiometricType.face:
          descriptions.add('面容识别');
          break;
        case BiometricType.fingerprint:
          descriptions.add('指纹识别');
          break;
        case BiometricType.iris:
          descriptions.add('虹膜识别');
          break;
        case BiometricType.strong:
          descriptions.add('强生物识别');
          break;
        case BiometricType.weak:
          descriptions.add('弱生物识别');
          break;
        default:
          descriptions.add('生物识别');
      }
    }
    return descriptions.join('、');
  }

  /// 获取指纹传感器类型描述（基于设备信息推测）
  static String getSensorTypeDescription() {
    final device = Platform.operatingSystemVersion.toLowerCase();
    
    // 常见设备指纹类型映射
    final ultrasonicDevices = [
      'samsung', 'galaxy s21', 'galaxy s22', 'galaxy s23', 'galaxy s24',
      'pixel 7', 'pixel 8', 'vivo', 'iqoo', '魅族18',
    ];
    
    final opticalDevices = [
      'redmi', 'xiaomi', 'oppo', 'realme', 'oneplus', 'huawei', 'honor',
    ];
    
    final deviceLower = device.toLowerCase();
    
    for (final d in ultrasonicDevices) {
      if (deviceLower.contains(d)) return '超声波屏下指纹';
    }
    
    for (final d in opticalDevices) {
      if (deviceLower.contains(d)) return '光学屏下指纹';
    }
    
    return '指纹识别';
  }
}
