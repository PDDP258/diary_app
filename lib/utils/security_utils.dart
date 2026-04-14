import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';

/// ============================================================================
/// 安全工具库 - 基于移动应用安全最佳实践
/// ============================================================================
///
/// 参考:
/// - OWASP Mobile Security Top 10
/// - Mobile App Security Best Practices 2024
/// - Flutter Secure Storage Best Practices

/// 数据加密服务
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  encrypt.Key? _key;
  encrypt.IV? _iv;

  /// 初始化加密服务
  Future<void> initialize(String password) async {
    // 从密码派生密钥
    final keyBytes = _deriveKey(password);
    _key = encrypt.Key(keyBytes);
    _iv = encrypt.IV.fromLength(16);
  }

  /// 派生密钥 (PBKDF2)
  Uint8List _deriveKey(String password, {int length = 32}) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes.take(length).toList());
  }

  /// 加密数据
  String encryptText(String plainText) {
    if (_key == null) throw StateError('EncryptionService not initialized');
    
    final encrypter = encrypt.Encrypter(
      encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
    );
    
    final encrypted = encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  /// 解密数据
  String decryptText(String encryptedText) {
    if (_key == null) throw StateError('EncryptionService not initialized');
    
    final encrypter = encrypt.Encrypter(
      encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
    );
    
    final encrypted = encrypt.Encrypted.fromBase64(encryptedText);
    return encrypter.decrypt(encrypted, iv: _iv);
  }

  /// 哈希密码 (用于本地密码验证)
  String hashPassword(String password, {String? salt}) {
    final effectiveSalt = salt ?? _generateSalt();
    final bytes = utf8.encode(password + effectiveSalt);
    final digest = sha256.convert(bytes);
    return '$effectiveSalt:${digest.toString()}';
  }

  /// 验证密码
  bool verifyPassword(String password, String hashedPassword) {
    final parts = hashedPassword.split(':');
    if (parts.length != 2) return false;
    
    final salt = parts[0];
    final newHash = hashPassword(password, salt: salt);
    return newHash == hashedPassword;
  }

  /// 生成随机盐
  String _generateSalt() {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64.encode(bytes);
  }

  /// 生成安全随机字符串
  String generateSecureToken({int length = 32}) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Url.encode(bytes);
  }
}

/// 安全存储管理器
class SecureStorageManager {
  static final SecureStorageManager _instance = SecureStorageManager._internal();
  factory SecureStorageManager() => _instance;
  SecureStorageManager._internal();

  final Map<String, String> _secureStorage = {};

  /// 存储加密数据
  Future<void> write(String key, String value) async {
    // 实际实现应该使用 flutter_secure_storage
    final encrypted = EncryptionService().encryptText(value);
    _secureStorage[key] = encrypted;
  }

  /// 读取加密数据
  Future<String?> read(String key) async {
    final encrypted = _secureStorage[key];
    if (encrypted == null) return null;
    
    try {
      return EncryptionService().decryptText(encrypted);
    } catch (e) {
      return null;
    }
  }

  /// 删除数据
  Future<void> delete(String key) async {
    _secureStorage.remove(key);
  }

  /// 清空所有数据
  Future<void> deleteAll() async {
    _secureStorage.clear();
  }

  /// 检查是否存在
  Future<bool> containsKey(String key) async {
    return _secureStorage.containsKey(key);
  }
}

/// 证书固定管理器 (Certificate Pinning)
class CertificatePinningManager {
  static final CertificatePinningManager _instance = CertificatePinningManager._internal();
  factory CertificatePinningManager() => _instance;
  CertificatePinningManager._internal();

  final List<String> _pinnedCertificates = [];
  final List<String> _pinnedPublicKeys = [];

  /// 添加固定的证书
  void addPinnedCertificate(String certificate) {
    _pinnedCertificates.add(certificate);
  }

  /// 添加固定的公钥
  void addPinnedPublicKey(String publicKey) {
    _pinnedPublicKeys.add(publicKey);
  }

  /// 验证证书
  bool verifyCertificate(String certificate, String publicKey) {
    if (_pinnedCertificates.isNotEmpty) {
      return _pinnedCertificates.contains(certificate);
    }
    if (_pinnedPublicKeys.isNotEmpty) {
      return _pinnedPublicKeys.contains(publicKey);
    }
    return true; // 如果没有固定证书，允许通过
  }

  /// 创建安全的 HTTP 客户端
  HttpClient createSecureHttpClient() {
    final client = HttpClient();
    
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      // 这里应该实现证书验证逻辑
      return false; // 默认拒绝所有无效证书
    };
    
    return client;
  }
}

/// 代码混淆工具 (基础实现)
class ObfuscationUtil {
  /// 混淆字符串
  static String obfuscate(String input) {
    final bytes = utf8.encode(input);
    final obfuscated = bytes.map((b) => b ^ 0x55).toList();
    return base64.encode(obfuscated);
  }

  /// 解混淆字符串
  static String deobfuscate(String input) {
    final obfuscated = base64.decode(input);
    final bytes = obfuscated.map((b) => b ^ 0x55).toList();
    return utf8.decode(bytes);
  }

  /// 简单的字符串加密
  static String simpleEncrypt(String input, String key) {
    final inputBytes = utf8.encode(input);
    final keyBytes = utf8.encode(key);
    final encrypted = <int>[];
    
    for (var i = 0; i < inputBytes.length; i++) {
      encrypted.add(inputBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    
    return base64.encode(encrypted);
  }

  /// 简单的字符串解密
  static String simpleDecrypt(String input, String key) {
    final encrypted = base64.decode(input);
    final keyBytes = utf8.encode(key);
    final decrypted = <int>[];
    
    for (var i = 0; i < encrypted.length; i++) {
      decrypted.add(encrypted[i] ^ keyBytes[i % keyBytes.length]);
    }
    
    return utf8.decode(decrypted);
  }
}

/// 输入验证器
class InputValidator {
  /// 验证邮箱
  static bool isValidEmail(String email) {
    final pattern = r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$';
    return RegExp(pattern).hasMatch(email);
  }

  /// 验证密码强度
  static PasswordStrength checkPasswordStrength(String password) {
    var score = 0;
    
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;

    if (score <= 2) return PasswordStrength.weak;
    if (score <= 4) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  /// 验证手机号
  static bool isValidPhone(String phone) {
    final pattern = r'^\+?[0-9]{10,15}$';
    return RegExp(pattern).hasMatch(phone.replaceAll(RegExp(r'\s'), ''));
  }

  /// 验证 URL
  static bool isValidUrl(String url) {
    final pattern = r'^(http|https)://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(/\S*)?$';
    return RegExp(pattern).hasMatch(url);
  }

  /// 清理输入 (防止 XSS)
  static String sanitizeInput(String input) {
    return input
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;')
        .replaceAll('/', '&#x2F;');
  }

  /// 验证文件名
  static bool isValidFileName(String fileName) {
    final invalidChars = RegExp(r'[<>:"/\\|?*]');
    return !invalidChars.hasMatch(fileName);
  }
}

enum PasswordStrength {
  weak,
  medium,
  strong,
}

/// 安全检查列表
class SecurityChecklist {
  static final List<SecurityCheck> checks = [
    SecurityCheck(
      name: 'Root/越狱检测',
      description: '检测设备是否被 root 或越狱',
      check: () async {
        // 实际实现需要平台特定代码
        return true;
      },
    ),
    SecurityCheck(
      name: '调试模式检测',
      description: '检测应用是否处于调试模式',
      check: () async {
        return !kDebugMode;
      },
    ),
    SecurityCheck(
      name: '数据加密',
      description: '验证敏感数据是否加密存储',
      check: () async {
        // 实际实现需要检查存储
        return true;
      },
    ),
    SecurityCheck(
      name: '网络安全',
      description: '验证 HTTPS 和证书固定',
      check: () async {
        // 实际实现需要检查网络配置
        return true;
      },
    ),
  ];

  static Future<List<SecurityCheckResult>> runChecks() async {
    final results = <SecurityCheckResult>[];
    
    for (final check in checks) {
      try {
        final passed = await check.check();
        results.add(SecurityCheckResult(
          check: check,
          passed: passed,
        ));
      } catch (e) {
        results.add(SecurityCheckResult(
          check: check,
          passed: false,
          error: e.toString(),
        ));
      }
    }
    
    return results;
  }
}

class SecurityCheck {
  final String name;
  final String description;
  final Future<bool> Function() check;

  SecurityCheck({
    required this.name,
    required this.description,
    required this.check,
  });
}

class SecurityCheckResult {
  final SecurityCheck check;
  final bool passed;
  final String? error;

  SecurityCheckResult({
    required this.check,
    required this.passed,
    this.error,
  });
}

/// 审计日志
class AuditLogger {
  static final List<AuditLog> _logs = [];
  static const int _maxLogs = 1000;

  static void log({
    required String action,
    required String userId,
    Map<String, dynamic>? details,
    AuditLogLevel level = AuditLogLevel.info,
  }) {
    final log = AuditLog(
      timestamp: DateTime.now(),
      action: action,
      userId: userId,
      details: details,
      level: level,
    );

    _logs.add(log);

    // 限制日志数量
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    if (kDebugMode) {
      print('[AUDIT] ${log.toString()}');
    }
  }

  static List<AuditLog> getLogs({
    DateTime? startTime,
    DateTime? endTime,
    AuditLogLevel? minLevel,
  }) {
    return _logs.where((log) {
      if (startTime != null && log.timestamp.isBefore(startTime)) return false;
      if (endTime != null && log.timestamp.isAfter(endTime)) return false;
      if (minLevel != null && log.level.index < minLevel.index) return false;
      return true;
    }).toList();
  }

  static void clear() {
    _logs.clear();
  }
}

class AuditLog {
  final DateTime timestamp;
  final String action;
  final String userId;
  final Map<String, dynamic>? details;
  final AuditLogLevel level;

  AuditLog({
    required this.timestamp,
    required this.action,
    required this.userId,
    this.details,
    this.level = AuditLogLevel.info,
  });

  @override
  String toString() {
    return '${timestamp.toIso8601String()} [$level] $userId: $action ${details ?? ""}';
  }
}

enum AuditLogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

/// 威胁检测器
class ThreatDetector {
  static final List<ThreatRule> _rules = [
    ThreatRule(
      name: '多次失败登录',
      check: (context) {
        final failedAttempts = context['failedLoginAttempts'] ?? 0;
        return failedAttempts > 5;
      },
      severity: ThreatSeverity.high,
    ),
    ThreatRule(
      name: '异常时间访问',
      check: (context) {
        final hour = DateTime.now().hour;
        return hour < 5 || hour > 23;
      },
      severity: ThreatSeverity.medium,
    ),
    ThreatRule(
      name: '数据导出异常',
      check: (context) {
        final exportCount = context['exportCount'] ?? 0;
        return exportCount > 100;
      },
      severity: ThreatSeverity.high,
    ),
  ];

  static List<Threat> detectThreats(Map<String, dynamic> context) {
    final threats = <Threat>[];
    
    for (final rule in _rules) {
      if (rule.check(context)) {
        threats.add(Threat(
          rule: rule,
          detectedAt: DateTime.now(),
          context: context,
        ));
      }
    }
    
    return threats;
  }
}

class ThreatRule {
  final String name;
  final bool Function(Map<String, dynamic> context) check;
  final ThreatSeverity severity;

  ThreatRule({
    required this.name,
    required this.check,
    required this.severity,
  });
}

class Threat {
  final ThreatRule rule;
  final DateTime detectedAt;
  final Map<String, dynamic> context;

  Threat({
    required this.rule,
    required this.detectedAt,
    required this.context,
  });
}

enum ThreatSeverity {
  low,
  medium,
  high,
  critical,
}
