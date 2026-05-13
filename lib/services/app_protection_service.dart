import 'dart:io';
import 'package:flutter/foundation.dart';

/// 应用保护服务
///
/// 保护作者劳动成果，防止软件被非法修改和盗用
///
/// 保护范围：
/// 1. 防止APK被重新打包（包名校验）
/// 2. 防止代码被调试分析（调试检测）
/// 3. 防止资源被提取盗用（完整性检查）
///
/// 不限制：
/// - 用户自用（允许Root、模拟器）
/// - 免费使用（无时间限制）
/// - 数据备份导出
///
/// 版权所有 © 2024-2026 PDDP
/// 保留所有权利
class AppProtectionService {
  // 原始包名（发布前填入实际包名）
  static const String _originalPackageName = 'com.example.diary_app';

  // 是否启用严格模式（发布时设为true）
  static const bool _strictMode = false; // 暂时关闭严格模式，避免误判

  /// 执行作品保护检查
  ///
  /// 重点检测：
  /// - 包名是否被修改（防止重打包）
  /// - 是否被调试（防止逆向分析）
  ///
  /// 不检测：
  /// - Root设备（用户有权利控制自己的设备）
  /// - 模拟器（方便用户测试）
  static Future<ProtectionResult> checkAppIntegrity() async {
    final results = <String, bool>{};

    // 1. 检查包名（防止重打包）- 暂时放宽检查
    results['package'] = await _checkPackageNameReliable();

    // 2. 检查是否被调试（防止逆向分析）
    results['debug'] = !_isBeingDebugged();

    // 3. 检查文件完整性（可选，防止资源被篡改）
    results['files'] = await _checkFileIntegrity();

    // 计算总体结果
    // 在严格模式下才阻止运行，目前先只记录不阻止
    final allPassed = true; // 暂时允许所有情况通过
    final failedChecks =
        results.entries.where((e) => !e.value).map((e) => e.key).toList();

    return ProtectionResult(
      isValid: allPassed,
      failedChecks: failedChecks,
      details: results,
    );
  }

  /// 可靠的包名检查
  static Future<bool> _checkPackageNameReliable() async {
    try {
      // 方法1：检查应用数据目录
final appDir = await _getAppDataDirectory();
      if (appDir != null && appDir.contains(_originalPackageName)) {
        return true;
      }

      // 方法2：检查进程信息
      final processPackage = await _getPackageFromProcess();
      if (processPackage != null && processPackage == _originalPackageName) {
        return true;
      }
    
      // 方法3：检查文件系统路径
      if (_checkPackageFromFileSystem()) {
        return true;
      }
      
      // 如果都检查失败，在非严格模式下允许通过
      return !_strictMode;
    } catch (e) {
  // 检查出错时，在非严格模式下允许通过
      return !_strictMode;
    }
  }
  
  /// 获取应用数据目录
  static Future<String?> _getAppDataDirectory() async {
    try {
    // 获取应用私有目录
      final appDir = Directory('/data/data/$_originalPackageName');
      if (await appDir.exists()) {
        return appDir.path;
      }
      
      // 尝试获取当前目录
  final currentDir = Directory.current.path;
      if (currentDir.contains(_originalPackageName)) {
        return currentDir;
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// 从进程信息获取包名
  static Future<String?> _getPackageFromProcess() async {
    try {
      // 读取进程命令行
      final cmdlineFile = File('/proc/self/cmdline');
      if (await cmdlineFile.exists()) {
        final content = await cmdlineFile.readAsString();
    // cmdline 格式通常是: 包名\0...\0
        final packageName = content.split('\x00').first;
        if (packageName.isNotEmpty) {
        return packageName;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// 从文件系统检查包名
  static bool _checkPackageFromFileSystem() {
  try {
      // 检查常见的应用路径
      final paths = [
        '/data/data/$_originalPackageName',
        '/data/app/$_originalPackageName-1',
        '/data/app/$_originalPackageName-2',
      ];
    
      for (final path in paths) {
        if (Directory(path).existsSync()) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      return false;
  }
  }
  
  /// 检查是否被调试（防止逆向分析）
  static bool _isBeingDebugged() {
    // 检查是否以调试模式编译
    if (kDebugMode) {
      return true;
    }
    
    // 检查是否有调试器附加（Android）
    if (Platform.isAndroid) {
      try {
        final file = File('/proc/self/status');
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          if (content.contains('TracerPid:')) {
            final tracerPid = _extractTracerPid(content);
            if (tracerPid != null && tracerPid != '0') {
            return true;
            }
          }
        }
      } catch (e) {
        // 无法读取文件
    }
    }
    
    return false;
  }
  
  /// 提取 TracerPid
  static String? _extractTracerPid(String content) {
    final lines = content.split('\n');
  for (final line in lines) {
      if (line.startsWith('TracerPid:')) {
        return line.split(':').last.trim();
      }
}
    return null;
  }
  
  /// 检查文件完整性（防止资源被篡改）
  static Future<bool> _checkFileIntegrity() async {
    // 目前不检查具体文件，留作扩展
    // 可以在这里添加关键资源文件的哈希校验
    return true;
  }
  
  /// 获取保护状态信息（用于调试）
  static Future<Map<String, dynamic>> getProtectionStatus() async {
    return {
      'package_name': await _getPackageFromProcess(),
      'app_directory': await _getAppDataDirectory(),
      'filesystem_check': _checkPackageFromFileSystem(),
      'is_debugged': _isBeingDebugged(),
      'strict_mode': _strictMode,
    'build_mode': kDebugMode ? 'debug' : 'release',
    };
  }
  
  /// 获取版权信息
  static Map<String, String> getCopyrightInfo() {
    return {
      'app_name': '小记日记',
      'version': '1.3.0',
      'author': 'PDDP',
      'copyright': '© 2024-2026 PDDP',
      'license': '个人作品，免费使用，禁止修改',
      'rights': '保留所有权利',
    };
  }
}
  

/// 保护检查结果
class ProtectionResult {
  final bool isValid;
  final List<String> failedChecks;
  final Map<String, bool> details;
  
  const ProtectionResult({
    required this.isValid,
    required this.failedChecks,
    required this.details,
  });
  
  @override
  String toString() {
    if (isValid) {
      return '作品完整性检查通过';
    } else {
      return '作品完整性检查失败: ${failedChecks.join(', ')}';
    }
  }
  
  /// 获取用户友好的错误信息
  String getUserFriendlyMessage() {
    if (isValid) return '';
    
    final messages = <String>[];
    for (final check in failedChecks) {
      switch (check) {
        case 'package':
          messages.add('应用包名异常，可能已被修改');
          break;
        case 'debug':
          messages.add('检测到调试模式');
          break;
        case 'files':
          messages.add('应用文件不完整');
          break;
        default:
          messages.add('检查失败: $check');
      }
    }
    return messages.join('\n');
  }
  
  /// 获取版权保护说明
  String getCopyrightNotice() {
    return '''
小记日记 - 个人作品保护

本软件为作者个人作品，供用户免费使用。

禁止行为：
• 修改软件代码或资源
• 重新打包分发
• 去除版权信息
• 商业使用

尊重劳动成果，从你我做起。
''';
  }
}
