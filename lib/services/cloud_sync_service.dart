import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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
    bool syncImages = false,
  });

  /// 从云端恢复
  Future<SyncResult> syncFromCloud({String? cloudKey});
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

  @override
  Future<bool> uploadBackup(Map<String, dynamic> backupData) async {
    try {
      // 1. 先确保目录存在
      final dirCreated = await _ensureDirectoryExists('diary');
      if (!dirCreated) {
        _debugPrint('创建目录失败，尝试直接上传...', level: 'WARN');
      }

      // 2. 添加数据哈希用于完整性校验
      final dataWithHash = Map<String, dynamic>.from(backupData);
      dataWithHash['_hash'] = _generateDataHash(backupData);
      dataWithHash['_encrypted'] = true;

      final jsonStr = jsonEncode(dataWithHash);

      // 3. 使用云端备份专用密钥加密数据
      final encryptedJson =
          await EncryptionService.encryptWithCloudKey(jsonStr);
      if (encryptedJson == null) {
        _debugPrint('加密备份数据失败', level: 'ERROR');
        return false;
      }

      // 添加加密标识
      final encryptedData = {
        '_encrypted': true,
        '_version': 1,
        'data': encryptedJson,
      };

      final encryptedJsonStr = jsonEncode(encryptedData);
      final bytes = utf8.encode(encryptedJsonStr);

      // 3. 使用HttpClient进行PUT请求（更好的WebDAV支持）
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        // 规范化服务器URL
        var baseUrl = _serverUrl!;
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        final uri = Uri.parse('${baseUrl}diary/backup_latest.mbk');
        _debugPrint('上传备份到: $uri');

        final request = await httpClient.putUrl(uri);

        // 添加认证头
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Content-Type', 'application/octet-stream');
        request.headers.set('Content-Length', '${bytes.length}');
        request.headers.set('Connection', 'close');

        request.add(bytes);

        final response =
            await request.close().timeout(const Duration(seconds: 30));
        final statusCode = response.statusCode;
        await response.drain();

        httpClient.close();

        _debugPrint('上传响应码: $statusCode');

        // WebDAV PUT 成功状态码: 200 OK, 201 Created, 204 No Content
        if (statusCode == 200 || statusCode == 201 || statusCode == 204) {
          await _saveSyncTime();
          _debugPrint('上传成功');
          return true;
        }

        _debugPrint('上传失败，状态码: $statusCode', level: 'ERROR');
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
  Future<bool> _ensureDirectoryExists(String dirName) async {
    try {
      // 规范化服务器URL
      var baseUrl = _serverUrl!;
      if (!baseUrl.endsWith('/')) {
        baseUrl = '$baseUrl/';
      }

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        // 1. 先检查目录是否存在（PROPFIND）
        final uri = Uri.parse('$baseUrl$dirName/');
        _debugPrint('检查目录: $uri');

        final propfindRequest = await httpClient.openUrl('PROPFIND', uri);
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        propfindRequest.headers.set('Authorization', 'Basic $auth');
        propfindRequest.headers.set('Depth', '0');
        propfindRequest.headers.set('Connection', 'close');

        final propfindResponse =
            await propfindRequest.close().timeout(const Duration(seconds: 10));
        final propfindStatus = propfindResponse.statusCode;
        await propfindResponse.drain();

        // 207 = 目录存在
        if (propfindStatus == 207) {
          _debugPrint('目录已存在');
          httpClient.close();
          return true;
        }

        // 404 = 目录不存在，需要创建
        if (propfindStatus == 404) {
          _debugPrint('目录不存在，创建中...');

          final mkcolRequest = await httpClient.openUrl('MKCOL', uri);
          mkcolRequest.headers.set('Authorization', 'Basic $auth');
          mkcolRequest.headers.set('Connection', 'close');

          final mkcolResponse =
              await mkcolRequest.close().timeout(const Duration(seconds: 10));
          final mkcolStatus = mkcolResponse.statusCode;
          await mkcolResponse.drain();

          httpClient.close();

          // 201 = 创建成功
          if (mkcolStatus == 201) {
            _debugPrint('目录创建成功');
            return true;
          } else {
            _debugPrint('目录创建失败，状态码: $mkcolStatus', level: 'ERROR');
            return false;
          }
        }

        httpClient.close();
        return false;
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
    try {
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        // 规范化服务器URL
        var baseUrl = _serverUrl!;
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        final uri = Uri.parse('${baseUrl}diary/backup_latest.mbk');
        _debugPrint('下载备份: $uri');

        final request = await httpClient.getUrl(uri);

        // 添加认证头
        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Connection', 'close');

        final response =
            await request.close().timeout(const Duration(seconds: 30));
        final statusCode = response.statusCode;

        if (statusCode == 200) {
          final bytes = await response
              .fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
          final jsonStr = utf8.decode(bytes);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;

          httpClient.close();

          Map<String, dynamic>? decryptedData;

          if (data['_encrypted'] == true && data['data'] != null) {
            if (cloudKey == null || cloudKey.isEmpty) {
              _debugPrint('需要云端备份密钥才能解密');
              return null;
            }
            final encryptedContent = data['data'] as String;
            final decryptedJson = await EncryptionService.decryptWithCloudKey(
                encryptedContent, cloudKey);
            if (decryptedJson == null) {
              _debugPrint('云端密钥解密失败', level: 'ERROR');
              return null;
            }
            decryptedData = jsonDecode(decryptedJson) as Map<String, dynamic>;
          } else if (data.containsKey('diaries')) {
            decryptedData = data;
          } else {
            _debugPrint('未知的备份格式');
            return null;
          }

          if (!_verifyDataIntegrity(decryptedData)) {
            _debugPrint('警告：下载的备份数据可能已被篡改');
            return null;
          }

          _debugPrint('下载成功');
          return decryptedData;
        }

        await response.drain();
        httpClient.close();

        _debugPrint('下载失败，状态码: $statusCode', level: 'ERROR');
        return null;
      } catch (e) {
        httpClient.close();
        rethrow;
      }
    } catch (e) {
      _debugPrint('下载备份失败: $e', level: 'ERROR');
      return null;
    }
  }

  @override
  Future<bool> uploadImageArchive(
      List<int> encryptedBytes, String fileName) async {
    try {
      _debugPrint('上传加密图片包: $fileName');

      // 1. 先确保目录存在
      final dirCreated = await _ensureDirectoryExists('diary/images');
      if (!dirCreated) {
        _debugPrint('创建图片目录失败，尝试直接上传...', level: 'WARN');
      }

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      try {
        var baseUrl = _serverUrl!;
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        final uri = Uri.parse('${baseUrl}diary/images/$fileName');
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

        final uri = Uri.parse('${baseUrl}diary/images/$fileName');
        _debugPrint('下载图片包: $uri');

        final request = await httpClient.getUrl(uri);

        final auth = base64Encode(utf8.encode('$_username:$_password'));
        request.headers.set('Authorization', 'Basic $auth');
        request.headers.set('Connection', 'close');

        final response =
            await request.close().timeout(const Duration(minutes: 5));
        final statusCode = response.statusCode;

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

  /// 打包并加密图片
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

      // 创建ZIP归档
      final archive = Archive();
      int successCount = 0;

      for (final imagePath in allImagePaths) {
        final file = File(imagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final fileName = imagePath.split('/').last;
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
          successCount++;
        }
      }

      _debugPrint('成功打包 $successCount 张图片');

      // 编码ZIP数据
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        _debugPrint('ZIP编码失败', level: 'ERROR');
        return null;
      }

      // 加密ZIP数据
      final encrypted =
          await EncryptionService.encryptData(Uint8List.fromList(zipBytes));
      if (encrypted == null) {
        _debugPrint('加密失败', level: 'ERROR');
        return null;
      }

      _debugPrint(
          '图片打包加密完成，大小: ${(encrypted.length / 1024 / 1024).toStringAsFixed(2)}MB');
      return encrypted;
    } catch (e) {
      _debugPrint('打包加密图片失败: $e', level: 'ERROR');
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
    bool syncImages = false,
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
        'version': '1.1.0',
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

      _debugPrint('从云端恢复完成，图片将在访问日记时按需加载');

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
          _showError(result.errorMessage ?? '连接失败，请检查配置');
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// 云同步服务工厂
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

// 使用日志服务记录（同时输出到控制台和 Markdown 文件）
void _debugPrint(String message, {String level = 'INFO'}) {
  // 异步记录到日志文件
  SyncLogService.log(message, level: level);
}

/// 连接测试结果
class ConnectionResult {
  final bool success;
  final String? url;
  final String? errorMessage;

  ConnectionResult({
    required this.success,
    this.url,
    this.errorMessage,
  });
}

/// WebDAV连接测试器 - 用于登录对话框中测试连接
class _WebDAVConnectionTester {
  final String serverUrl;
  final String username;
  final String password;

  _WebDAVConnectionTester({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  /// 带详细错误信息的测试
  Future<ConnectionResult> testConnectionWithDetails() async {
    try {
      // 规范化服务器URL
      var baseUrl = serverUrl.trim();
      if (!baseUrl.endsWith('/')) {
        baseUrl = '$baseUrl/';
      }

      // 确保URL以http://或https://开头
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      _debugPrint('测试连接: $baseUrl');

      // 创建HttpClient - 直接使用PROPFIND测试
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      // 直接尝试PROPFIND请求（坚果云等WebDAV服务器需要）
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
        await response.drain();

        _debugPrint('PROPFIND响应码: ${response.statusCode}');

        httpClient.close();

        if (response.statusCode == 401) {
          return ConnectionResult(
            success: false,
            errorMessage: '用户名或密码错误',
          );
        }

        // 207 Multi-Status 是WebDAV成功的标志
        if (response.statusCode == 207) {
          return ConnectionResult(success: true, url: baseUrl);
        }

        // 200/404 也表示服务器可达
        if (response.statusCode == 200 || response.statusCode == 404) {
          return ConnectionResult(success: true, url: baseUrl);
        }

        return ConnectionResult(
          success: false,
          errorMessage: '服务器返回错误: ${response.statusCode}',
        );
      } catch (e) {
        _debugPrint('PROPFIND请求失败: $e', level: 'ERROR');
        httpClient.close();

        // 备用：尝试GET请求
        final httpClient2 = HttpClient()
          ..badCertificateCallback = (cert, host, port) => true;

        try {
          final request = await httpClient2.getUrl(Uri.parse(baseUrl));
          final auth = base64Encode(utf8.encode('$username:$password'));
          request.headers.set('Authorization', 'Basic $auth');
          request.headers.set('Connection', 'close');

          final response =
              await request.close().timeout(const Duration(seconds: 20));
          await response.drain();

          _debugPrint('GET响应码: ${response.statusCode}');

          httpClient2.close();

          if (response.statusCode == 401) {
            return ConnectionResult(
              success: false,
              errorMessage: '用户名或密码错误',
            );
          }

          if (response.statusCode >= 200 && response.statusCode < 300 ||
              response.statusCode == 404) {
            return ConnectionResult(success: true, url: baseUrl);
          }

          return ConnectionResult(
            success: false,
            errorMessage: '服务器返回错误: ${response.statusCode}',
          );
        } catch (e2) {
          _debugPrint('GET请求也失败: $e2');
          httpClient2.close();
          return ConnectionResult(
            success: false,
            errorMessage: '无法连接到服务器，请检查网络或服务器地址',
          );
        }
      }
    } catch (e) {
      _debugPrint('WebDAV连接测试异常: $e', level: 'ERROR');
      return ConnectionResult(
        success: false,
        errorMessage: '连接异常: ${e.toString()}',
      );
    }
  }
}
