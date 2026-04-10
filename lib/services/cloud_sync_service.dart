import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import 'encryption_service.dart';
import 'database_service.dart';
import 'sync_log_service.dart';
import 'dart:math' as math;

/// 云同步服务抽象类
abstract class CloudSyncService {
  static const String _lastSyncTimeKey = 'last_sync_time';
  static const String _autoSyncKey = 'auto_sync_enabled';

  bool _isLoggedIn = false;
  String? _accessToken;
  DateTime? _lastSyncTime;
  bool _autoSyncEnabled = false;

  // 安全存储实例 - 改为protected以便子类访问
  static FlutterSecureStorage get secureStorage => FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );

  // Getters
  bool get isLoggedIn => _isLoggedIn;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get autoSyncEnabled => _autoSyncEnabled;
  String get serviceName;
  String get serviceIcon;

  /// 初始化
  Future<void> initialize() async {
    await _loadSettings();
  }

  /// 加载设置（使用安全的存储方式）
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSyncEnabled = prefs.getBool(_autoSyncKey) ?? false;
    final lastSyncStr = prefs.getString(_lastSyncTimeKey);
    if (lastSyncStr != null) {
      _lastSyncTime = DateTime.tryParse(lastSyncStr);
    }
    await _loadAuthInfo();
  }

  /// 加载授权信息（子类实现）
  Future<void> _loadAuthInfo();

  /// 保存同步时间
  Future<void> _saveSyncTime() async {
    _lastSyncTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncTimeKey, _lastSyncTime!.toIso8601String());
  }

  /// 设置自动同步
  Future<void> setAutoSync(bool enabled) async {
    _autoSyncEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, enabled);
  }

  /// 辅助方法：生成数据哈希用于完整性校验
  String _generateDataHash(Map<String, dynamic> data) {
    final jsonStr = jsonEncode(data);
    final bytes = utf8.encode(jsonStr);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 验证数据完整性
  bool _verifyDataIntegrity(Map<String, dynamic> data) {
    if (!data.containsKey('_hash')) return true; // 旧版本数据不做校验
    final storedHash = data['_hash'] as String;
    final dataCopy = Map<String, dynamic>.from(data)..remove('_hash');
    final computedHash = _generateDataHash(dataCopy);
    return storedHash == computedHash;
  }

  /// 登录授权（子类实现）
  Future<bool> login(BuildContext context);

  /// 退出登录
  Future<void> logout();

  /// 上传备份
  Future<bool> uploadBackup(Map<String, dynamic> backupData);

  /// 下载备份
  Future<Map<String, dynamic>?> downloadBackup({String? cloudKey});

  /// 上传加密图片包
  Future<bool> uploadImageArchive(List<int> encryptedBytes, String fileName);

  /// 下载加密图片包
  Future<List<int>?> downloadImageArchive(String fileName);

  /// 同步数据（上传本地数据）
  Future<SyncResult> syncToCloud({
    required List<Diary> diaries,
    required List<Mood> moods,
    required List<Tag> tags,
    required List<Map<String, dynamic>> diaryTags,
    bool syncImages = true, // 默认包含图片
  });

  /// 从云端恢复
  Future<SyncResult> syncFromCloud({String? cloudKey});

  // ==================== 多备份管理（v1.1.5新增）====================

  /// 扫描所有备份文件夹
  /// 返回备份列表，每个备份包含文件夹名和时间戳
  Future<List<CloudBackupInfo>> scanAllBackups();

  /// 从指定备份文件夹下载备份
  Future<Map<String, dynamic>?> downloadBackupFromFolder(
    String folderName, {
    required String decryptionKey,
  });

  /// 从指定文件夹下载原始加密备份数据（不解密）
  Future<Map<String, dynamic>?> downloadBackupFromFolderRaw(String folderName);

  /// 解密备份数据
  Future<Map<String, dynamic>?> decryptBackupData(
    Map<String, dynamic> encryptedData,
    String decryptionKey,
  );

  /// 合并备份数据到本地（不覆盖，只添加）
  /// [folderName] 可选，指定云端备份文件夹名，用于恢复图片
  Future<SyncResult> mergeBackupToLocal(Map<String, dynamic> backupData, {String? folderName});
}

/// 云端备份信息
class CloudBackupInfo {
  final String folderName;
  final String? timestamp;
  final int? diaryCount;
  final bool isCurrentDevice;

  CloudBackupInfo({
    required this.folderName,
    this.timestamp,
    this.diaryCount,
    this.isCurrentDevice = false,
  });
}

/// 同步结果
class SyncResult {
  final bool success;
  final String message;
  final int uploadedCount;
  final int downloadedCount;
  final DateTime? timestamp;

  SyncResult({
    required this.success,
    required this.message,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.timestamp,
  });

  factory SyncResult.success({
    String message = '同步成功',
    int uploaded = 0,
    int downloaded = 0,
  }) {
    return SyncResult(
      success: true,
      message: message,
      uploadedCount: uploaded,
      downloadedCount: downloaded,
      timestamp: DateTime.now(),
    );
  }

  factory SyncResult.failure(String message) {
    return SyncResult(
      success: false,
      message: message,
      timestamp: DateTime.now(),
    );
  }
}

/// Isolate消息 - 图片批次处理
class _ImageBatchMessage {
  final List<String> imagePaths;
  final SendPort sendPort;

  _ImageBatchMessage({
    required this.imagePaths,
    required this.sendPort,
  });
}

/// Isolate消息 - 加密处理
class _EncryptMessage {
  final Archive archive;
  final SendPort sendPort;

  _EncryptMessage({
    required this.archive,
    required this.sendPort,
  });
}

/// WebDAV 同步服务实现
class WebDAVSyncService extends CloudSyncService {
  static const String _serverUrlKey = 'webdav_server_url';
  static const String _usernameKey = 'webdav_username';
  static const String _passwordKey = 'webdav_password';

  String? _serverUrl;
  String? _username;
  String? _password;

  @override
  String get serviceName => 'WebDAV';

  @override
  String get serviceIcon => '☁️';

  @override
  Future<void> _loadAuthInfo() async {
    // 使用安全存储替代SharedPreferences - 通过父类调用静态成员
    _serverUrl = await CloudSyncService.secureStorage.read(key: _serverUrlKey);
    _username = await CloudSyncService.secureStorage.read(key: _usernameKey);
    _password = await CloudSyncService.secureStorage.read(key: _passwordKey);

    // 规范化URL（确保以/结尾）
    if (_serverUrl != null) {
      _serverUrl = _serverUrl!.trim();
      if (!_serverUrl!.endsWith('/')) {
        _serverUrl = '$_serverUrl/';
      }
      // 确保URL以http://或https://开头
      if (!_serverUrl!.startsWith('http://') &&
          !_serverUrl!.startsWith('https://')) {
        _serverUrl = 'https://$_serverUrl';
      }
    }

    _isLoggedIn = _serverUrl != null && _username != null && _password != null;
  }

  @override
  Future<bool> login(BuildContext context) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const WebDAVLoginDialog(),
    );

    if (result == null) return false;

    _serverUrl = result['url'];
    _username = result['username'];
    _password = result['password'];

    // 测试连接（必须成功才保存）
    final connected = await _testConnection();
    if (!connected) {
      // 连接失败，不保存配置
      _debugPrint('连接测试失败', level: 'ERROR');
      return false;
    }

    // 连接成功，保存凭证
    await CloudSyncService.secureStorage
        .write(key: _serverUrlKey, value: _serverUrl);
    await CloudSyncService.secureStorage
        .write(key: _usernameKey, value: _username);
    await CloudSyncService.secureStorage
        .write(key: _passwordKey, value: _password);

    _isLoggedIn = true;
    return true;
  }

  @override
  Future<void> logout() async {
    // 安全删除存储的凭证
    await CloudSyncService.secureStorage.delete(key: _serverUrlKey);
    await CloudSyncService.secureStorage.delete(key: _usernameKey);
    await CloudSyncService.secureStorage.delete(key: _passwordKey);
    _serverUrl = null;
    _username = null;
    _password = null;
    _isLoggedIn = false;
  }

  Future<bool> _testConnection() async {
    try {
      // 规范化服务器URL
      var baseUrl = _serverUrl!.trim();
      if (!baseUrl.endsWith('/')) {
        baseUrl = '$baseUrl/';
      }

      // 确保URL以http://或https://开头
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      // 保存规范化后的URL
      _serverUrl = baseUrl;

      _debugPrint('测试连接: $baseUrl');

      // 直接使用PROPFIND方法测试（坚果云等WebDAV服务器需要）
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) {
          _debugPrint('SSL证书验证: $host:$port - 接受自签名证书');
          return true;
        };

      try {
        final request =
            await httpClient.openUrl('PROPFIND', Uri.parse(baseUrl));

        // 添加认证头
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Depth', '0');
        request.headers.set('Content-Type', 'application/xml');
        request.headers.set('Connection', 'close');
        request.write(
            '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop></d:prop></d:propfind>');

        final response =
            await request.close().timeout(const Duration(seconds: 30));
        await response.drain();

        _debugPrint('PROPFIND 响应码: ${response.statusCode}');
        httpClient.close();

        // 分析响应码
        if (response.statusCode == 401) {
          _debugPrint('认证失败：用户名或密码错误', level: 'ERROR');
          return false;
        }

        // 207 Multi-Status 是WebDAV成功的标志
        if (response.statusCode == 207) {
          _debugPrint('WebDAV连接成功');
          return true;
        }

        // 200/404 也表示服务器可达
        if (response.statusCode == 200 || response.statusCode == 404) {
          _debugPrint('服务器可达');
          return true;
        }

        _debugPrint('服务器响应: ${response.statusCode}');
        return response.statusCode >= 200 && response.statusCode < 300;
      } catch (e) {
        _debugPrint('PROPFIND请求失败: $e', level: 'ERROR');
        httpClient.close();

        // 备用：尝试GET请求
        return await _testConnectionWithHttp();
      }
    } catch (e) {
      _debugPrint('WebDAV连接测试异常: $e', level: 'ERROR');
      return false;
    }
  }

  /// 使用http包测试连接
  Future<bool> _testConnectionWithHttp() async {
    try {
      _debugPrint('使用http包测试连接...');

      var baseUrl = _serverUrl!.trim();
      if (!baseUrl.endsWith('/')) {
        baseUrl = '$baseUrl/';
      }
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      final auth = base64Encode(utf8.encode('$_username:$_password'));

      try {
        final response = await http.get(
          Uri.parse(baseUrl),
          headers: {
            'Authorization': 'Basic $auth',
            'Accept': '*/*',
          },
        ).timeout(const Duration(seconds: 20));

        _debugPrint('http响应码: ${response.statusCode}');

        if (response.statusCode == 401) {
          return false;
        }

        return response.statusCode >= 200 && response.statusCode < 400;
      } catch (e) {
        // 可能是证书问题，尝试忽略证书
        _debugPrint('http请求异常: $e', level: 'ERROR');
        return false;
      }
    } catch (e) {
      _debugPrint('http测试异常: $e', level: 'ERROR');
      return false;
    }
  }

  Map<String, String> _getAuthHeaders() {
    final auth = base64Encode(utf8.encode('$_username:$_password'));
    return {
      'Authorization': 'Basic $auth',
      'Content-Type': 'application/json',
    };
  }

  /// 获取当前设备的备份文件夹名
  Future<String> _getCurrentBackupFolderName() async {
    final key = await EncryptionService.getCloudBackupKey();
    if (key == null || key.isEmpty) {
      return 'backup_unknown';
    }
    final keyHash = sha256.convert(utf8.encode(key)).toString();
    return 'backup_${keyHash.substring(0, 8)}';
  }

  @override
  Future<bool> uploadBackup(Map<String, dynamic> backupData) async {
    try {
      // 1. 获取当前设备的备份文件夹名
      final folderName = await _getCurrentBackupFolderName();
      _debugPrint('备份到文件夹: $folderName');

      // 2. 确保备份目录存在
      final dirCreated = await _ensureDirectoryExists('diary_backups/$folderName');
      if (!dirCreated) {
        _debugPrint('创建备份目录失败', level: 'ERROR');
        return false;
      }

      // 3. 添加数据哈希用于完整性校验
      final dataWithHash = Map<String, dynamic>.from(backupData);
      dataWithHash['_hash'] = _generateDataHash(backupData);
      dataWithHash['_encrypted'] = true;

      final jsonStr = jsonEncode(dataWithHash);

      // 4. 使用云端备份专用密钥加密数据
      final encryptedJson = await EncryptionService.encryptWithCloudKey(jsonStr);
      if (encryptedJson == null) {
        _debugPrint('加密备份数据失败', level: 'ERROR');
        return false;
      }

      // 添加加密标识
      final encryptedData = {
        '_encrypted': true,
        '_version': 2,
        'data': encryptedJson,
      };

      final encryptedJsonStr = jsonEncode(encryptedData);
      final bytes = utf8.encode(encryptedJsonStr);

      // 5. 上传到新架构的备份路径（按密钥分文件夹）
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        var baseUrl = _serverUrl!;
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        // 新路径：diary_backups/<folder>/backup.mbk
        final newPathUri = Uri.parse('${baseUrl}diary_backups/$folderName/backup.mbk');
        _debugPrint('上传备份到新路径: $newPathUri');

        final newPathRequest = await httpClient.putUrl(newPathUri);
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        newPathRequest.headers.set('Authorization', 'Basic $auth');
        newPathRequest.headers.set('Content-Type', 'application/octet-stream');
        newPathRequest.headers.set('Content-Length', '${bytes.length}');
        newPathRequest.headers.set('Connection', 'close');
        newPathRequest.add(bytes);

        final newPathResponse = await newPathRequest.close().timeout(const Duration(seconds: 30));
        final newPathStatus = newPathResponse.statusCode;
        await newPathResponse.drain();

        _debugPrint('新路径上传响应码: $newPathStatus');

        // 同时上传到旧路径保持兼容性（如果新路径成功）
        if (newPathStatus == 200 || newPathStatus == 201 || newPathStatus == 204) {
          // 尝试上传到旧路径，失败不影响整体成功
          try {
            final oldPathUri = Uri.parse('${baseUrl}diary/backup_latest.mbk');
            _debugPrint('同时上传到旧路径（兼容）: $oldPathUri');
            
            final oldPathRequest = await httpClient.putUrl(oldPathUri);
            oldPathRequest.headers.set('Authorization', 'Basic $auth');
            oldPathRequest.headers.set('Content-Type', 'application/octet-stream');
            oldPathRequest.headers.set('Content-Length', '${bytes.length}');
            oldPathRequest.headers.set('Connection', 'close');
            oldPathRequest.add(bytes);

            final oldPathResponse = await oldPathRequest.close().timeout(const Duration(seconds: 30));
            await oldPathResponse.drain();
            _debugPrint('旧路径上传响应码: ${oldPathResponse.statusCode}');
          } catch (e) {
            _debugPrint('旧路径上传失败（不影响）: $e');
          }

          httpClient.close();
          await _saveSyncTime();
          _debugPrint('备份上传成功');
          return true;
        }

        httpClient.close();
        _debugPrint('备份上传失败，状态码: $newPathStatus', level: 'ERROR');
        return false;
      } catch (e) {
        httpClient.close();
        rethrow;
      }
    } catch (e) {
      _debugPrint('上传备份失败: $e', level: 'ERROR');
      return false;
    }
  }

  /// 确保目录存在，不存在则创建
  Future<bool> _ensureDirectoryExists(String dirPath) async {
    try {
      var baseUrl = _serverUrl!;
      if (!baseUrl.endsWith('/')) {
        baseUrl = '$baseUrl/';
      }

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        // 逐级创建目录
        final parts = dirPath.split('/');
        String currentPath = '';
        
        for (final part in parts) {
          if (part.isEmpty) continue;
          currentPath += '$part/';
          
          final uri = Uri.parse('$baseUrl$currentPath');
          _debugPrint('检查/创建目录: $uri');

          // 检查目录是否存在
          final propfindRequest = await httpClient.openUrl('PROPFIND', uri);
          final auth = base64Encode(utf8.encode('$_username:$_password'));
          propfindRequest.headers.set('Authorization', 'Basic $auth');
          propfindRequest.headers.set('Depth', '0');
          propfindRequest.headers.set('Connection', 'close');

          final propfindResponse = await propfindRequest.close().timeout(const Duration(seconds: 10));
          final propfindStatus = propfindResponse.statusCode;
          await propfindResponse.drain();

          if (propfindStatus == 207) {
            // 目录已存在
            continue;
          }

          if (propfindStatus == 404) {
            // 目录不存在，创建
            final mkcolRequest = await httpClient.openUrl('MKCOL', uri);
            mkcolRequest.headers.set('Authorization', 'Basic $auth');
            mkcolRequest.headers.set('Connection', 'close');

            final mkcolResponse = await mkcolRequest.close().timeout(const Duration(seconds: 10));
            final mkcolStatus = mkcolResponse.statusCode;
            await mkcolResponse.drain();

            if (mkcolStatus != 201) {
              _debugPrint('创建目录失败: $currentPath, 状态码: $mkcolStatus', level: 'ERROR');
              httpClient.close();
              return false;
            }
          }
        }

        httpClient.close();
        return true;
      } catch (e) {
        httpClient.close();
        _debugPrint('确保目录存在时出错: $e');
        return false;
      }
    } catch (e) {
      _debugPrint('创建目录失败: $e', level: 'ERROR');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> downloadBackup({String? cloudKey}) async {
    // 优先尝试新路径（按密钥分文件夹）
    try {
      final folderName = await _getCurrentBackupFolderName();
      final result = await downloadBackupFromFolder(folderName, decryptionKey: cloudKey ?? '');
      if (result != null) {
        return result;
      }
    } catch (e) {
      _debugPrint('从新路径下载失败，尝试旧路径: $e');
    }

    // 回退到旧路径
    return await _downloadBackupFromOldPath(cloudKey: cloudKey);
  }

  /// 从旧路径下载备份（兼容模式）
  Future<Map<String, dynamic>?> _downloadBackupFromOldPath({String? cloudKey}) async {
    try {
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        var baseUrl = _serverUrl!;
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        final uri = Uri.parse('${baseUrl}diary/backup_latest.mbk');
        _debugPrint('从旧路径下载备份: $uri');

        final request = await httpClient.getUrl(uri);
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Connection', 'close');

        final response = await request.close().timeout(const Duration(seconds: 30));
        final statusCode = response.statusCode;

        if (statusCode == 200) {
          final bytes = await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
          final jsonStr = utf8.decode(bytes);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;

          httpClient.close();
          return await _decryptBackupData(data, cloudKey);
        }

        await response.drain();
        httpClient.close();
        return null;
      } catch (e) {
        httpClient.close();
        rethrow;
      }
    } catch (e) {
      _debugPrint('从旧路径下载备份失败: $e', level: 'ERROR');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> downloadBackupFromFolder(
    String folderName, {
    required String decryptionKey,
  }) async {
    try {
      // 1. 下载原始加密数据
      final rawData = await downloadBackupFromFolderRaw(folderName);
      if (rawData == null) return null;
      
      // 2. 解密
      return await decryptBackupData(rawData, decryptionKey);
    } catch (e) {
      _debugPrint('从文件夹下载备份失败: $e', level: 'ERROR');
      return null;
    }
  }

  /// 从指定文件夹下载原始加密备份数据（不解密）
  @override
  Future<Map<String, dynamic>?> downloadBackupFromFolderRaw(String folderName) async {
    try {
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        var baseUrl = _serverUrl!;
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        final uri = Uri.parse('${baseUrl}diary_backups/$folderName/backup.mbk');
        _debugPrint('从文件夹下载备份: $uri');

        final request = await httpClient.getUrl(uri);
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Connection', 'close');

        final response = await request.close().timeout(const Duration(seconds: 30));
        final statusCode = response.statusCode;

        if (statusCode == 200) {
          final bytes = await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
          final jsonStr = utf8.decode(bytes);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;

          httpClient.close();
          return data;
        }

        await response.drain();
        httpClient.close();
        _debugPrint('备份不存在或无法访问，状态码: $statusCode');
        return null;
      } catch (e) {
        httpClient.close();
        rethrow;
      }
    } catch (e) {
      _debugPrint('从文件夹下载备份失败: $e', level: 'ERROR');
      return null;
    }
  }

  /// 解密备份数据（公开方法供UI使用）
  @override
  Future<Map<String, dynamic>?> decryptBackupData(
    Map<String, dynamic> encryptedData,
    String decryptionKey,
  ) async {
    return await _decryptBackupData(encryptedData, decryptionKey);
  }

  /// 解密备份数据
  Future<Map<String, dynamic>?> _decryptBackupData(
    Map<String, dynamic> data,
    String? cloudKey,
  ) async {
    try {
      if (data['_encrypted'] == true && data['data'] != null) {
        if (cloudKey == null || cloudKey.isEmpty) {
          _debugPrint('需要密钥才能解密备份');
          return null;
        }
        final encryptedContent = data['data'] as String;
        final decryptedJson = await EncryptionService.decryptWithCloudKey(
          encryptedContent,
          cloudKey,
        );
        if (decryptedJson == null) {
          _debugPrint('密钥解密失败', level: 'ERROR');
          return null;
        }
        final decryptedData = jsonDecode(decryptedJson) as Map<String, dynamic>;
        
        if (!_verifyDataIntegrity(decryptedData)) {
          _debugPrint('警告：备份数据可能已被篡改');
          return null;
        }
        return decryptedData;
      } else if (data.containsKey('diaries')) {
        // 旧格式，未加密
        return data;
      }
      _debugPrint('未知的备份格式');
      return null;
    } catch (e) {
      _debugPrint('解密备份数据失败: $e');
      return null;
    }
  }

  @override
  Future<List<CloudBackupInfo>> scanAllBackups() async {
    final backups = <CloudBackupInfo>[];
    
    try {
      var baseUrl = _serverUrl!;
      if (!baseUrl.endsWith('/')) {
        baseUrl = '$baseUrl/';
      }

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        // 1. 列出 diary_backups 目录下的所有子目录
        final uri = Uri.parse('${baseUrl}diary_backups/');
        _debugPrint('扫描备份目录: $uri');

        final request = await httpClient.openUrl('PROPFIND', uri);
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Depth', '1'); // 只列出一级子目录
        request.headers.set('Content-Type', 'application/xml');
        request.headers.set('Connection', 'close');
        request.write(
          '<?xml version="1.0"?>'
          '<d:propfind xmlns:d="DAV:">'
          '<d:prop><d:displayname/><d:resourcetype/><d:getlastmodified/></d:prop>'
          '</d:propfind>'
        );

        final response = await request.close().timeout(const Duration(seconds: 30));
        final statusCode = response.statusCode;

        if (statusCode == 207) {
          final bytes = await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
          final xmlStr = utf8.decode(bytes);
          
          // 解析XML响应，提取文件夹名
          final folderNames = _parseWebDAVListing(xmlStr);
          _debugPrint('发现 ${folderNames.length} 个备份文件夹');

          // 获取当前设备的文件夹名
          final currentFolder = await _getCurrentBackupFolderName();

          for (final folderName in folderNames) {
            if (folderName.startsWith('backup_')) {
              backups.add(CloudBackupInfo(
                folderName: folderName,
                isCurrentDevice: folderName == currentFolder,
              ));
            }
          }
        }

        await response.drain();
        httpClient.close();
      } catch (e) {
        httpClient.close();
        _debugPrint('扫描备份目录失败: $e');
      }
    } catch (e) {
      _debugPrint('扫描所有备份失败: $e', level: 'ERROR');
    }

    return backups;
  }

  /// 解析WebDAV PROPFIND响应，提取文件夹名
  List<String> _parseWebDAVListing(String xmlStr) {
    final names = <String>[];
    
    // 简单的XML解析，提取displayname
    final regExp = RegExp(r'<d:displayname>([^<]+)</d:displayname>');
    final matches = regExp.allMatches(xmlStr);
    
    for (final match in matches) {
      final name = match.group(1);
      if (name != null && name != 'diary_backups') {
        names.add(name);
      }
    }
    
    return names;
  }

  @override
  Future<SyncResult> mergeBackupToLocal(Map<String, dynamic> backupData, {String? folderName}) async {
    _debugPrint('=== 开始合并备份到本地 ===');
    
    try {
      int diaryCount = 0;
      int moodCount = 0;
      int tagCount = 0;

      // 1. 合并日记（根据ID去重，保留最新的）
      final diariesList = backupData['diaries'] as List<dynamic>?;
      if (diariesList != null && diariesList.isNotEmpty) {
        _debugPrint('合并 ${diariesList.length} 篇日记...');
        final diaries = diariesList
            .map((d) => Diary.fromMap(d as Map<String, dynamic>))
            .toList();
        
        for (final diary in diaries) {
          // 检查是否已存在
          if (diary.id == null) continue;
          final existing = await DatabaseService.getDiary(diary.id!);
          if (existing == null) {
            // 不存在，直接插入
            await DatabaseService.insertDiary(diary);
            diaryCount++;
          } else {
            // 存在，保留更新时间较新的
            final diaryUpdatedAt = DateTime.tryParse(diary.updatedAt ?? '');
            final existingUpdatedAt = DateTime.tryParse(existing.updatedAt ?? '');
            if (diaryUpdatedAt != null && existingUpdatedAt != null && 
                diaryUpdatedAt.isAfter(existingUpdatedAt)) {
              await DatabaseService.updateDiary(diary);
              diaryCount++;
            }
          }
        }
        _debugPrint('成功合并 $diaryCount 篇新日记');
      }

      // 2. 合并心情
      final moodsList = backupData['moods'] as List<dynamic>?;
      if (moodsList != null && moodsList.isNotEmpty) {
        _debugPrint('合并 ${moodsList.length} 个心情...');
        final moods = moodsList
            .map((m) => Mood.fromMap(m as Map<String, dynamic>))
            .toList();
        
        for (final mood in moods) {
          if (mood.id == null) continue;
          final existing = await DatabaseService.getMood(mood.id!);
          if (existing == null) {
            await DatabaseService.insertMood(mood);
            moodCount++;
          }
        }
        _debugPrint('成功合并 $moodCount 个新心情');
      }

      // 3. 合并标签
      final tagsList = backupData['tags'] as List<dynamic>?;
      if (tagsList != null && tagsList.isNotEmpty) {
        _debugPrint('合并 ${tagsList.length} 个标签...');
        final tags = tagsList
            .map((t) => Tag.fromMap(t as Map<String, dynamic>))
            .toList();
        
        for (final tag in tags) {
          if (tag.id == null) continue;
          final existing = await DatabaseService.getTag(tag.id!);
          if (existing == null) {
            await DatabaseService.insertTag(tag);
            tagCount++;
          }
        }
        _debugPrint('成功合并 $tagCount 个新标签');
      }

      // 4. 合并日记-标签关联
      final diaryTagsList = backupData['diary_tags'] as List<dynamic>?;
      if (diaryTagsList != null && diaryTagsList.isNotEmpty) {
        _debugPrint('合并 ${diaryTagsList.length} 个日记标签关联...');
        await DatabaseService.mergeDiaryTags(
          diaryTagsList.cast<Map<String, dynamic>>()
        );
      }

      // 5. 恢复图片（如果提供了文件夹名）
      int restoredImages = 0;
      if (folderName != null && folderName.isNotEmpty) {
        _debugPrint('开始从文件夹 $folderName 恢复图片...');
        restoredImages = await _restoreImageArchives(folderName);
        _debugPrint('图片恢复完成，共 $restoredImages 张');
      }

      return SyncResult.success(
        message: '成功导入备份',
        downloaded: diaryCount + moodCount + tagCount,
      );
    } catch (e) {
      _debugPrint('合并备份失败: $e', level: 'ERROR');
      return SyncResult.failure('导入失败: $e');
    }
  }

  @override
  Future<bool> uploadImageArchive(
      List<int> encryptedBytes, String fileName) async {
    try {
      _debugPrint('上传加密图片包: $fileName');

      // 获取当前设备的备份文件夹
      final folderName = await _getCurrentBackupFolderName();

      // 确保目录存在
      final dirCreated = await _ensureDirectoryExists('diary_backups/$folderName/images');
      if (!dirCreated) {
        _debugPrint('创建图片目录失败', level: 'WARN');
      }

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        var baseUrl = _serverUrl!;
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        // 上传到当前设备的备份文件夹
        final uri = Uri.parse('${baseUrl}diary_backups/$folderName/images/$fileName');
        _debugPrint('上传图片包到: $uri');

        final request = await httpClient.putUrl(uri);

        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Content-Type', 'application/octet-stream');
        request.headers.set('Content-Length', '${encryptedBytes.length}');
        request.headers.set('Connection', 'close');

        request.add(encryptedBytes);

        final response =
            await request.close().timeout(const Duration(minutes: 5));
        final statusCode = response.statusCode;
        await response.drain();

        httpClient.close();

        _debugPrint('图片包上传响应码: $statusCode');

        if (statusCode == 200 || statusCode == 201 || statusCode == 204) {
          _debugPrint('图片包上传成功');
          return true;
        }

        _debugPrint('图片包上传失败，状态码: $statusCode', level: 'ERROR');
        return false;
      } catch (e) {
        httpClient.close();
        rethrow;
      }
    } catch (e) {
      _debugPrint('上传图片包失败: $e', level: 'ERROR');
      return false;
    }
  }

  @override
  Future<List<int>?> downloadImageArchive(String fileName) async {
    try {
      _debugPrint('下载加密图片包: $fileName');

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        var baseUrl = _serverUrl!;
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        // 优先从当前设备的备份文件夹下载
        final folderName = await _getCurrentBackupFolderName();
        var uri = Uri.parse('${baseUrl}diary_backups/$folderName/images/$fileName');
        _debugPrint('尝试从设备文件夹下载: $uri');

        var request = await httpClient.getUrl(uri);
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Connection', 'close');

        var response = await request.close().timeout(const Duration(minutes: 5));
        var statusCode = response.statusCode;

        // 如果从设备文件夹下载失败，尝试旧路径
        if (statusCode != 200) {
          await response.drain();
          _debugPrint('从设备文件夹下载失败，尝试旧路径');
          
          uri = Uri.parse('${baseUrl}diary/images/$fileName');
          request = await httpClient.getUrl(uri);
          request.headers.set('Authorization', 'Basic $auth');
          request.headers.set('Connection', 'close');
          
          response = await request.close().timeout(const Duration(minutes: 5));
          statusCode = response.statusCode;
        }

        if (statusCode == 200) {
          final bytes = await response
              .fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
          httpClient.close();
          _debugPrint(
              '图片包下载成功，大小: ${(bytes.length / 1024 / 1024).toStringAsFixed(2)}MB');
          return bytes;
        }

        await response.drain();
        httpClient.close();

        _debugPrint('图片包下载失败，状态码: $statusCode', level: 'ERROR');
        return null;
      } catch (e) {
        httpClient.close();
        rethrow;
      }
    } catch (e) {
      _debugPrint('下载图片包失败: $e', level: 'ERROR');
      return null;
    }
  }

  /// 打包并加密图片（使用Isolate避免主线程卡顿）
  Future<List<int>?> _createEncryptedImageArchive(List<Diary> diaries) async {
    try {
      _debugPrint('开始打包加密图片...');

      // 从日记中提取所有图片路径
      final allImagePaths = <String>{};

      for (final diary in diaries) {
        if (diary.images != null && diary.images!.isNotEmpty) {
          allImagePaths
              .addAll(diary.images!.split(',').where((p) => p.isNotEmpty));
        }
      }

      if (allImagePaths.isEmpty) {
        _debugPrint('没有图片需要同步');
        return null;
      }

      _debugPrint('找到 ${allImagePaths.length} 张图片');

      // 分批处理图片，避免内存溢出
      const batchSize = 50;
      final allPaths = allImagePaths.toList();
      final archive = Archive();
      int successCount = 0;

      for (int i = 0; i < allPaths.length; i += batchSize) {
        final batch = allPaths.skip(i).take(batchSize).toList();
        
        // 在Isolate中处理每一批图片
        final batchResult = await _processImageBatchInIsolate(batch);
        
        for (final fileData in batchResult) {
          archive.addFile(ArchiveFile(
            fileData['name'] as String,
            (fileData['bytes'] as List<int>).length,
            fileData['bytes'] as List<int>,
          ));
          successCount++;
        }
        
        // 让出时间片，避免阻塞UI
        await Future.delayed(const Duration(milliseconds: 10));
      }

      _debugPrint('成功打包 $successCount 张图片');

      if (successCount == 0) {
        _debugPrint('没有图片可以打包', level: 'WARN');
        return null;
      }

      // 在Isolate中编码ZIP
      final zipBytes = await _encodeInIsolate(archive);
      
      if (zipBytes == null) {
        _debugPrint('ZIP编码失败', level: 'ERROR');
        return null;
      }

      // 在主线程加密（因为EncryptionService是异步的）
      final encrypted = await EncryptionService.encryptData(Uint8List.fromList(zipBytes));
      if (encrypted == null) {
        _debugPrint('加密失败', level: 'ERROR');
        return null;
      }

      _debugPrint(
          '图片打包加密完成，大小: ${(encrypted.length / 1024 / 1024).toStringAsFixed(2)}MB');
      return encrypted;
    } catch (e, stackTrace) {
      _debugPrint('打包加密图片失败: $e', level: 'ERROR');
      _debugPrint('堆栈: $stackTrace', level: 'ERROR');
      return null;
    }
  }

  /// 在Isolate中处理图片批次
  Future<List<Map<String, dynamic>>> _processImageBatchInIsolate(List<String> imagePaths) async {
    try {
      final receivePort = ReceivePort();
      
      await Isolate.spawn(
        _processImageBatchIsolate,
        _ImageBatchMessage(
          imagePaths: imagePaths,
          sendPort: receivePort.sendPort,
        ),
      );

      final result = await receivePort.first as List<Map<String, dynamic>>;
      return result;
    } catch (e) {
      _debugPrint('Isolate处理图片批次失败: $e', level: 'ERROR');
      // 降级为在主线程处理
      return _processImageBatch(imagePaths);
    }
  }

  /// Isolate入口函数 - 处理图片批次
  static void _processImageBatchIsolate(_ImageBatchMessage message) {
    final result = _processImageBatch(message.imagePaths);
    message.sendPort.send(result);
  }

  /// 处理图片批次（静态方法，可在Isolate中运行）
  static List<Map<String, dynamic>> _processImageBatch(List<String> imagePaths) {
    final result = <Map<String, dynamic>>[];
    
    for (final imagePath in imagePaths) {
      try {
        final file = File(imagePath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          final fileName = imagePath.split('/').last;
          result.add({
            'name': fileName,
            'bytes': bytes,
          });
        }
      } catch (e) {
        // 单张图片失败不中断整个批次
        debugPrint('读取图片失败: $imagePath - $e');
      }
    }
    
    return result;
  }

  /// 在Isolate中编码ZIP
  Future<List<int>?> _encodeInIsolate(Archive archive) async {
    try {
      final receivePort = ReceivePort();
      
      await Isolate.spawn(
        _encodeIsolate,
        _EncryptMessage(
          archive: archive,
          sendPort: receivePort.sendPort,
        ),
      );

      final result = await receivePort.first as List<int>?;
      return result;
    } catch (e) {
      _debugPrint('Isolate编码失败: $e', level: 'ERROR');
      // 降级为在主线程处理
      return _encodeArchive(archive);
    }
  }

  /// Isolate入口函数 - 编码ZIP
  static void _encodeIsolate(_EncryptMessage message) {
    final result = _encodeArchive(message.archive);
    message.sendPort.send(result);
  }

  /// 编码ZIP（静态方法，可在Isolate中运行）
  static List<int>? _encodeArchive(Archive archive) {
    try {
      // 编码ZIP数据
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        debugPrint('ZIP编码失败');
        return null;
      }
      return zipBytes;
    } catch (e) {
      debugPrint('编码失败: $e');
      return null;
    }
  }

  /// 解密并解压图片
  Future<bool> _restoreEncryptedImageArchive(List<int> encryptedBytes) async {
    try {
      _debugPrint('开始解密恢复图片...');

      // 解密数据
      final decrypted = await EncryptionService.decryptData(
          Uint8List.fromList(encryptedBytes));
      if (decrypted == null) {
        _debugPrint('解密失败', level: 'ERROR');
        return false;
      }

      // 解压ZIP
      final archive = ZipDecoder().decodeBytes(decrypted);

      // 获取图片保存目录
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      // 保存图片
      int successCount = 0;
      for (final file in archive.files) {
        if (file.isFile) {
          final filePath = '${imagesDir.path}/${file.name}';
          final outputFile = File(filePath);
          await outputFile.writeAsBytes(file.content as List<int>);
          successCount++;
        }
      }

      _debugPrint('成功恢复 $successCount 张图片');
      return true;
    } catch (e) {
      _debugPrint('解密恢复图片失败: $e', level: 'ERROR');
      return false;
    }
  }

  @override
  Future<SyncResult> syncToCloud({
    required List<Diary> diaries,
    required List<Mood> moods,
    required List<Tag> tags,
    required List<Map<String, dynamic>> diaryTags,
    bool syncImages = true, // 默认包含图片
  }) async {
    _debugPrint('=== 开始同步到云端 ===');
    
    if (!_isLoggedIn) {
      _debugPrint('错误: 未登录WebDAV', level: 'ERROR');
      return SyncResult.failure('未登录');
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      _debugPrint('准备备份数据:');
      _debugPrint('  - 日记: ${diaries.length} 篇');
      _debugPrint('  - 心情: ${moods.length} 个');
      _debugPrint('  - 标签: ${tags.length} 个');
      _debugPrint('  - 日记标签关联: ${diaryTags.length} 个');

      final backupData = {
        'version': '1.1.5',
        'syncTime': DateTime.now().toIso8601String(),
        'diaries': diaries.map((d) => d.toMap()).toList(),
        'moods': moods.map((m) => m.toMap()).toList(),
        'tags': tags.map((t) => t.toMap()).toList(),
        'diary_tags': diaryTags,
        'unlocked_badges': prefs.getString('unlocked_badges'),
        'gacha_draws': prefs.getInt('gacha_draws'),
        'gacha_collection': prefs.getString('gacha_collection'),
        'gacha_history': prefs.getString('gacha_history'),
        'anniversaries': prefs.getString('anniversaries'),
        'custom_stickers': prefs.getString('custom_stickers'),
      };
      
      _debugPrint('备份数据组装完成，开始上传...');

      final dataSuccess = await uploadBackup(backupData);
      if (!dataSuccess) {
        return SyncResult.failure('数据上传失败');
      }

      if (syncImages) {
        final encryptedImages = await _createEncryptedImageArchive(diaries);
        if (encryptedImages != null) {
          final imageSuccess = await uploadImageArchive(encryptedImages,
              'images_${DateTime.now().millisecondsSinceEpoch}.enc');
          if (!imageSuccess) {
            _debugPrint('图片上传失败，但数据已同步', level: 'WARN');
          }
        }
      } else {
        _debugPrint('跳过图片同步（图片同步请在设置中手动触发）');
      }

      return SyncResult.success(
        message: '同步成功',
        uploaded: diaries.length,
      );
    } catch (e) {
      return SyncResult.failure('同步失败: $e');
    }
  }

  @override
  Future<SyncResult> syncFromCloud({String? cloudKey}) async {
    _debugPrint('=== 开始从云端恢复 ===');
    
    if (!_isLoggedIn) {
      _debugPrint('错误: 未登录WebDAV', level: 'ERROR');
      return SyncResult.failure('未登录');
    }

    try {
      final cloudBackupKey =
          cloudKey ?? await EncryptionService.getCloudBackupKey();

      if (cloudBackupKey == null || cloudBackupKey.isEmpty) {
        _debugPrint('错误: 没有云端备份密钥', level: 'ERROR');
        return SyncResult.failure('没有备份密钥，请先导入密钥');
      }
      
      _debugPrint('正在下载备份...');
      final backupData = await downloadBackup(cloudKey: cloudBackupKey);
      if (backupData == null) {
        _debugPrint('错误: 下载备份失败或解密失败', level: 'ERROR');
        return SyncResult.failure('云端没有备份或解密失败');
      }
      
      _debugPrint('备份下载成功，开始恢复数据...');

      final prefs = await SharedPreferences.getInstance();

      // 1. 恢复日记数据到数据库
      final diariesList = backupData['diaries'] as List<dynamic>?;
      if (diariesList != null && diariesList.isNotEmpty) {
        _debugPrint('恢复 ${diariesList.length} 篇日记...');
        final diaries = diariesList
            .map((d) => Diary.fromMap(d as Map<String, dynamic>))
            .toList();
        await DatabaseService.importDiaries(diaries);
        _debugPrint('日记恢复完成');
      } else {
        _debugPrint('备份中没有日记数据');
      }

      // 2. 恢复心情数据到数据库
      final moodsList = backupData['moods'] as List<dynamic>?;
      if (moodsList != null && moodsList.isNotEmpty) {
        _debugPrint('恢复 ${moodsList.length} 个心情...');
        final moods = moodsList
            .map((m) => Mood.fromMap(m as Map<String, dynamic>))
            .toList();
        await DatabaseService.importMoods(moods);
        _debugPrint('心情恢复完成');
      } else {
        _debugPrint('备份中没有心情数据');
      }

      // 3. 恢复标签数据到数据库
      final tagsList = backupData['tags'] as List<dynamic>?;
      if (tagsList != null && tagsList.isNotEmpty) {
        _debugPrint('恢复 ${tagsList.length} 个标签...');
        final tags = tagsList
            .map((t) => Tag.fromMap(t as Map<String, dynamic>))
            .toList();
        await DatabaseService.importTags(tags);
        _debugPrint('标签恢复完成');
      } else {
        _debugPrint('备份中没有标签数据');
      }

      // 4. 恢复日记-标签关联
      final diaryTagsList = backupData['diary_tags'] as List<dynamic>?;
      if (diaryTagsList != null && diaryTagsList.isNotEmpty) {
        _debugPrint('恢复 ${diaryTagsList.length} 个日记标签关联...');
        await DatabaseService.importDiaryTags(diaryTagsList.cast<Map<String, dynamic>>());
        _debugPrint('日记标签关联恢复完成');
      } else {
        _debugPrint('备份中没有日记标签关联数据');
      }

      // 5. 恢复SharedPreferences数据
      if (backupData['unlocked_badges'] != null) {
        await prefs.setString(
            'unlocked_badges', backupData['unlocked_badges'] as String);
      }
      if (backupData['gacha_draws'] != null) {
        await prefs.setInt('gacha_draws', backupData['gacha_draws'] as int);
      }
      if (backupData['gacha_collection'] != null) {
        await prefs.setString(
            'gacha_collection', backupData['gacha_collection'] as String);
      }
      if (backupData['gacha_history'] != null) {
        await prefs.setString(
            'gacha_history', backupData['gacha_history'] as String);
      }
      if (backupData['anniversaries'] != null) {
        await prefs.setString(
            'anniversaries', backupData['anniversaries'] as String);
      }
      if (backupData['custom_stickers'] != null) {
        await prefs.setString(
            'custom_stickers', backupData['custom_stickers'] as String);
      }

      // 6. 恢复图片
      _debugPrint('开始恢复图片...');
      final folderName = await _getCurrentBackupFolderName();
      final restoredImages = await _restoreImageArchives(folderName);
      _debugPrint('图片恢复完成，共 $restoredImages 张');

      final diariesCount = diariesList?.length ?? 0;

      await _saveSyncTime();

      return SyncResult.success(
        message: '恢复成功',
        downloaded: diariesCount,
      );
    } catch (e) {
      return SyncResult.failure('恢复失败: $e');
    }
  }

  /// 扫描指定备份文件夹中的图片包
  Future<List<String>> _scanImageArchives(String folderName) async {
    final archives = <String>[];
    
    try {
      var baseUrl = _serverUrl!;
      if (!baseUrl.endsWith('/')) {
        baseUrl = '$baseUrl/';
      }

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        final uri = Uri.parse('${baseUrl}diary_backups/$folderName/images/');
        _debugPrint('扫描图片目录: $uri');

        final request = await httpClient.openUrl('PROPFIND', uri);
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Depth', '1');
        request.headers.set('Content-Type', 'application/xml');
        request.headers.set('Connection', 'close');
        request.write(
          '<?xml version="1.0"?>'
          '<d:propfind xmlns:d="DAV:">'
          '<d:prop><d:displayname/><d:getlastmodified/></d:prop>'
          '</d:propfind>'
        );

        final response = await request.close().timeout(const Duration(seconds: 30));
        final statusCode = response.statusCode;

        if (statusCode == 207) {
          final bytes = await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
          final xmlStr = utf8.decode(bytes);
          
          // 解析XML，提取.enc文件名
          final regExp = RegExp(r'<d:displayname>([^<]+)</d:displayname>');
          final matches = regExp.allMatches(xmlStr);
          
          for (final match in matches) {
            final name = match.group(1);
            if (name != null && name.endsWith('.enc')) {
              archives.add(name);
            }
          }
          
          _debugPrint('发现 ${archives.length} 个图片包');
        }

        await response.drain();
        httpClient.close();
      } catch (e) {
        httpClient.close();
        _debugPrint('扫描图片目录失败: $e');
      }
    } catch (e) {
      _debugPrint('扫描图片包失败: $e', level: 'ERROR');
    }
    
    return archives;
  }

  /// 下载并恢复图片包
  Future<int> _restoreImageArchives(String folderName) async {
    int restoredCount = 0;
    
    try {
      // 扫描图片包
      final archives = await _scanImageArchives(folderName);
      if (archives.isEmpty) {
        _debugPrint('没有图片包需要恢复');
        return 0;
      }
      
      // 获取应用文档目录用于保存图片
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/diary_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      
      // 下载并解压每个图片包
      for (final archiveName in archives) {
        try {
          _debugPrint('下载图片包: $archiveName');
          final encryptedBytes = await downloadImageArchive(archiveName);
          if (encryptedBytes == null) {
            _debugPrint('下载图片包失败: $archiveName', level: 'ERROR');
            continue;
          }
          
          // 解密（转换为Uint8List）
          final decryptedBytes = await EncryptionService.decryptData(Uint8List.fromList(encryptedBytes));
          if (decryptedBytes == null) {
            _debugPrint('解密图片包失败: $archiveName', level: 'ERROR');
            continue;
          }
          
          // 解压ZIP
          final archive = ZipDecoder().decodeBytes(decryptedBytes);
          if (archive == null) {
            _debugPrint('解压图片包失败: $archiveName', level: 'ERROR');
            continue;
          }
          
          // 保存图片
          for (final file in archive) {
            if (file.isFile) {
              final fileName = file.name;
              final filePath = '${imagesDir.path}/$fileName';
              final outputFile = File(filePath);
              await outputFile.writeAsBytes(file.content as List<int>);
              restoredCount++;
            }
          }
          
          _debugPrint('图片包 $archiveName 恢复完成，共 ${archive.length} 张图片');
        } catch (e) {
          _debugPrint('恢复图片包 $archiveName 失败: $e', level: 'ERROR');
        }
      }
      
      _debugPrint('图片恢复完成，共 $restoredCount 张');
    } catch (e) {
      _debugPrint('恢复图片包失败: $e', level: 'ERROR');
    }
    
    return restoredCount;
  }

  void _debugPrint(String message, {String level = 'INFO'}) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[$timestamp] [WebDAV-$level] $message');
    
    // 同时记录到同步日志
    SyncLogService.log(message, level: level);
  }
}

/// WebDAV 登录对话框
class WebDAVLoginDialog extends StatefulWidget {
  const WebDAVLoginDialog({super.key});

  @override
  State<WebDAVLoginDialog> createState() => _WebDAVLoginDialogState();
}

class _WebDAVLoginDialogState extends State<WebDAVLoginDialog> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // 预设配置
  final List<Map<String, String>> _presets = [
    {
      'name': '坚果云',
      'url': 'https://dav.jianguoyun.com/dav/',
      'hint': '使用坚果云应用密码',
    },
    {
      'name': '自定义',
      'url': '',
      'hint': '输入您的WebDAV服务器地址',
    },
  ];

  String? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _selectedPreset = _presets[0]['name'];
    _urlController.text = _presets[0]['url']!;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('连接 WebDAV'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 预设选择
            DropdownButtonFormField<String>(
              initialValue: _selectedPreset,
              decoration: const InputDecoration(
                labelText: '服务商',
                border: OutlineInputBorder(),
              ),
              items: _presets.map((preset) {
                return DropdownMenuItem(
                  value: preset['name'],
                  child: Text(preset['name']!),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPreset = value;
                  final preset = _presets.firstWhere((p) => p['name'] == value);
                  _urlController.text = preset['url']!;
                });
              },
            ),
            const SizedBox(height: 16),

            // 服务器地址
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://dav.example.com/dav/',
                border: OutlineInputBorder(),
              ),
              enabled: _selectedPreset == '自定义',
            ),
            const SizedBox(height: 16),

            // 用户名
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名/邮箱',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 密码
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '密码/应用密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              obscureText: _obscurePassword,
            ),
            const SizedBox(height: 8),

            // 提示文字
            Text(
              _presets.firstWhere((p) => p['name'] == _selectedPreset)['hint']!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('连接'),
        ),
      ],
    );
  }

  Future<void> _login() async {
    // 验证输入
    if (_urlController.text.isEmpty) {
      _showError('请输入服务器地址');
      return;
    }
    if (_usernameController.text.isEmpty) {
      _showError('请输入用户名');
      return;
    }
    if (_passwordController.text.isEmpty) {
      _showError('请输入密码');
      return;
    }

    setState(() => _isLoading = true);

    // 获取输入的值
    final url = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // 创建临时服务来测试连接
    final tempService = _WebDAVConnectionTester(
      serverUrl: url,
      username: username,
      password: password,
    );

    try {
      // 测试连接
      final result = await tempService.testConnectionWithDetails();

      if (mounted) {
        setState(() => _isLoading = false);

        if (result.success) {
          Navigator.pop(context, {
            'url': result.url ?? url,
            'username': username,
            'password': password,
          });
        } else {
          _showError(result.message ?? '连接失败');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('连接异常: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// WebDAV连接测试器
class _WebDAVConnectionTester {
  final String serverUrl;
  final String username;
  final String password;

  _WebDAVConnectionTester({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  Future<ConnectionTestResult> testConnectionWithDetails() async {
    try {
      // 规范化URL
      var baseUrl = serverUrl.trim();
      if (!baseUrl.endsWith('/')) {
        baseUrl = '$baseUrl/';
      }
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        final request =
            await httpClient.openUrl('PROPFIND', Uri.parse(baseUrl));

        final auth = base64Encode(utf8.encode('$username:$password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Depth', '0');
        request.headers.set('Content-Type', 'application/xml');
        request.headers.set('Connection', 'close');
        request.write(
            '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop></d:prop></d:propfind>');

        final response =
            await request.close().timeout(const Duration(seconds: 30));
        final statusCode = response.statusCode;
        await response.drain();

        httpClient.close();

        if (statusCode == 207) {
          return ConnectionTestResult(
            success: true,
            url: baseUrl,
            message: '连接成功',
          );
        } else if (statusCode == 401) {
          return ConnectionTestResult(
            success: false,
            message: '认证失败：用户名或密码错误',
          );
        } else {
          return ConnectionTestResult(
            success: false,
            message: '服务器返回错误: $statusCode',
          );
        }
      } catch (e) {
        httpClient.close();
        return ConnectionTestResult(
          success: false,
          message: '连接失败: $e',
        );
      }
    } catch (e) {
      return ConnectionTestResult(
        success: false,
        message: '异常: $e',
      );
    }
  }
}

/// 连接测试结果
class ConnectionTestResult {
  final bool success;
  final String? url;
  final String? message;

  ConnectionTestResult({
    required this.success,
    this.url,
    this.message,
  });
}

/// 云同步工厂
class CloudSyncFactory {
  static CloudSyncService? _instance;

  static CloudSyncService get instance {
    _instance ??= WebDAVSyncService();
    return _instance!;
  }

  static Future<void> initialize() async {
    await instance.initialize();
  }
}
