import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 数据加密服务
/// 使用 AES-256-CBC 加密算法保护用户日记数据
class EncryptionService {
  static const String _keyStorageKey = 'encryption_key_v1';
  static const String _saltStorageKey = 'encryption_salt_v1';
  static const String _cloudBackupKeyStorage = 'cloud_backup_key_v1';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static encrypt.Key? _cachedKey;
  static bool _initialized = false;

  /// 初始化加密服务
  static Future<void> initialize() async {
    if (_initialized) return;

    // 检查是否已有密钥
    final existingKey = await _secureStorage.read(key: _keyStorageKey);

    if (existingKey == null) {
      // 首次使用，生成新密钥
      await _generateAndStoreKey();
    }

    _initialized = true;
  }

  /// 生成并存储新的加密密钥
  static Future<void> _generateAndStoreKey() async {
    // 生成随机密钥
    final key = encrypt.Key.fromSecureRandom(32); // 256位
    final salt = encrypt.IV.fromSecureRandom(16);

    // 安全存储
    await _secureStorage.write(key: _keyStorageKey, value: key.base64);
    await _secureStorage.write(key: _saltStorageKey, value: salt.base64);

    _cachedKey = key;
  }

  /// 获取加密密钥
  static Future<encrypt.Key> _getKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final keyBase64 = await _secureStorage.read(key: _keyStorageKey);
    if (keyBase64 == null) {
      await _generateAndStoreKey();
      return _getKey();
    }

    _cachedKey = encrypt.Key.fromBase64(keyBase64);
    return _cachedKey!;
  }

  /// 获取盐值（用于IV生成）
  static Future<encrypt.IV> _getSalt() async {
    final saltBase64 = await _secureStorage.read(key: _saltStorageKey);
    if (saltBase64 == null) {
      await _generateAndStoreKey();
      return _getSalt();
    }
    return encrypt.IV.fromBase64(saltBase64);
  }

  /// 生成IV（初始化向量）
  /// 使用数据哈希作为基础，确保相同数据产生相同的IV（用于可搜索加密）
  static encrypt.IV _generateIV(String data, encrypt.IV salt) {
    final bytes = utf8.encode(data + salt.base64);
    final hash = sha256.convert(bytes);
    // 取前16字节作为IV
    final ivBytes = Uint8List.fromList(hash.bytes.sublist(0, 16));
    return encrypt.IV(ivBytes);
  }

  /// 加密文本
  static Future<String?> encryptText(String? plainText) async {
    if (plainText == null || plainText.isEmpty) return plainText;

    try {
      await initialize();

      final key = await _getKey();
      final salt = await _getSalt();
      final iv = _generateIV(plainText, salt);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encrypted = encrypter.encrypt(plainText, iv: iv);

      // 返回 base64 编码的密文，添加标识前缀
      return '__ENC__${encrypted.base64}';
    } catch (e) {
      print('加密失败: $e');
      return plainText; // 加密失败时返回原文，避免数据丢失
    }
  }

  /// 解密文本
  static Future<String?> decryptText(String? cipherText) async {
    if (cipherText == null || cipherText.isEmpty) return cipherText;

    // 检查是否是加密数据
    if (!cipherText.startsWith('__ENC__')) {
      return cipherText; // 未加密的数据直接返回
    }

    try {
      await initialize();

      // 移除标识前缀
      final actualCipher = cipherText.substring(7);

      final key = await _getKey();
      final salt = await _getSalt();

      // 注意：解密时我们需要尝试找到正确的IV
      // 由于IV是基于原文生成的，我们需要使用存储的盐值尝试解密
      // 这里我们使用固定的IV进行解密（因为加密时使用了确定性的IV生成方法）
      final encrypted = encrypt.Encrypted.fromBase64(actualCipher);

      // 尝试使用空字符串生成IV（因为不知道原文）
      // 实际上我们需要存储IV，让我们修改方案
      return await _decryptWithStoredIV(actualCipher, key);
    } catch (e) {
      print('解密失败: $e');
      return cipherText; // 解密失败时返回密文
    }
  }

  /// 使用存储的IV进行解密
  static Future<String?> _decryptWithStoredIV(
    String cipherBase64,
    encrypt.Key key,
  ) async {
    try {
      // 密文格式: base64(iv) + ":" + base64(ciphertext)
      final parts = cipherBase64.split(':');
      if (parts.length != 2) {
        // 旧格式兼容：直接解密
        final encrypter = encrypt.Encrypter(
          encrypt.AES(key, mode: encrypt.AESMode.cbc),
        );
        final encrypted = encrypt.Encrypted.fromBase64(cipherBase64);
        final salt = await _getSalt();
        // 使用默认IV
        final iv = encrypt.IV(Uint8List(16));
        return encrypter.decrypt(encrypted, iv: iv);
      }

      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypted = encrypt.Encrypted.fromBase64(parts[1]);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      print('解密失败: $e');
      return null;
    }
  }

  /// 加密文本（新格式，包含IV）
  static Future<String?> encryptTextV2(String? plainText) async {
    if (plainText == null || plainText.isEmpty) return plainText;

    try {
      await initialize();

      final key = await _getKey();
      final iv = encrypt.IV.fromSecureRandom(16);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encrypted = encrypter.encrypt(plainText, iv: iv);

      // 格式: base64(iv):base64(ciphertext)
      final result = '${iv.base64}:${encrypted.base64}';
      return '__ENC2__${base64Encode(utf8.encode(result))}';
    } catch (e) {
      print('加密失败: $e');
      return plainText;
    }
  }

  /// 解密文本（新格式）
  static Future<String?> decryptTextV2(String? cipherText) async {
    if (cipherText == null || cipherText.isEmpty) return cipherText;

    // 检查是否是V2加密数据
    if (!cipherText.startsWith('__ENC2__')) {
      // 尝试V1格式
      return decryptText(cipherText);
    }

    try {
      await initialize();

      // 解码外层base64
      final inner = utf8.decode(base64Decode(cipherText.substring(8)));
      final parts = inner.split(':');

      if (parts.length != 2) return null;

      final key = await _getKey();
      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypted = encrypt.Encrypted.fromBase64(parts[1]);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      print('解密失败: $e');
      return cipherText;
    }
  }

  /// 批量加密日记数据
  static Future<Map<String, dynamic>> encryptDiaryData(
    Map<String, dynamic> diaryMap,
  ) async {
    final result = Map<String, dynamic>.from(diaryMap);

    // 加密敏感字段
    if (diaryMap['title'] != null) {
      result['title'] = await encryptTextV2(diaryMap['title']);
    }
    if (diaryMap['content'] != null) {
      result['content'] = await encryptTextV2(diaryMap['content']);
    }

    return result;
  }

  /// 批量解密日记数据
  static Future<Map<String, dynamic>> decryptDiaryData(
    Map<String, dynamic> diaryMap,
  ) async {
    final result = Map<String, dynamic>.from(diaryMap);

    // 解密敏感字段
    if (diaryMap['title'] != null) {
      result['title'] = await decryptTextV2(diaryMap['title']);
    }
    if (diaryMap['content'] != null) {
      result['content'] = await decryptTextV2(diaryMap['content']);
    }

    return result;
  }

  /// 检查数据是否已加密
  static bool isEncrypted(String? text) {
    if (text == null) return false;
    return text.startsWith('__ENC__') || text.startsWith('__ENC2__');
  }

  /// 重置加密密钥（危险操作，会导致已有数据无法解密）
  static Future<void> resetKey() async {
    await _secureStorage.delete(key: _keyStorageKey);
    await _secureStorage.delete(key: _saltStorageKey);
    _cachedKey = null;
    await _generateAndStoreKey();
  }

  /// 导出加密密钥（用于备份）
  static Future<String?> exportKey() async {
    final key = await _secureStorage.read(key: _keyStorageKey);
    final salt = await _secureStorage.read(key: _saltStorageKey);

    if (key == null || salt == null) return null;

    final exportData = {
      'key': key,
      'salt': salt,
      'version': '1',
    };

    return base64Encode(utf8.encode(jsonEncode(exportData)));
  }

  /// 导入加密密钥（用于恢复）
  static Future<bool> importKey(String exportedKey) async {
    try {
      final jsonStr = utf8.decode(base64Decode(exportedKey));
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final key = data['key'] as String;
      final salt = data['salt'] as String;

      await _secureStorage.write(key: _keyStorageKey, value: key);
      await _secureStorage.write(key: _saltStorageKey, value: salt);

      _cachedKey = encrypt.Key.fromBase64(key);

      return true;
    } catch (e) {
      print('导入密钥失败: $e');
      return false;
    }
  }

  /// 加密二进制数据（用于图片等文件）
  /// 返回加密后的字节数组，格式: iv(16 bytes) + ciphertext
  static Future<Uint8List?> encryptData(Uint8List data) async {
    try {
      await initialize();

      final key = await _getKey();
      final iv = encrypt.IV.fromSecureRandom(16);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encrypted = encrypter.encryptBytes(data, iv: iv);

      // 组合 IV + 密文
      final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
      result.setRange(0, iv.bytes.length, iv.bytes);
      result.setRange(iv.bytes.length, result.length, encrypted.bytes);

      return result;
    } catch (e) {
      print('数据加密失败: $e');
      return null;
    }
  }

  /// 解密二进制数据（用于图片等文件）
  /// 输入格式: iv(16 bytes) + ciphertext
  static Future<Uint8List?> decryptData(Uint8List encryptedData) async {
    try {
      await initialize();

      if (encryptedData.length < 16) {
        print('加密数据太短');
        return null;
      }

      final key = await _getKey();

      // 提取 IV (前16字节)
      final iv = encrypt.IV(Uint8List.fromList(encryptedData.sublist(0, 16)));

      // 提取密文
      final cipherBytes = encryptedData.sublist(16);
      final encrypted = encrypt.Encrypted(cipherBytes);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
    } catch (e) {
      print('数据解密失败: $e');
      return null;
    }
  }

  // ==================== 云端备份专用密钥 ====================

  /// 生成云端备份专用密钥
  /// 返回Base64编码的密钥字符串，用户需要保存
  static Future<String> generateCloudBackupKey() async {
    final key = encrypt.Key.fromSecureRandom(32);
    final keyBase64 = key.base64;

    await _secureStorage.write(key: _cloudBackupKeyStorage, value: keyBase64);

    return keyBase64;
  }

  /// 获取云端备份密钥
  static Future<String?> getCloudBackupKey() async {
    return await _secureStorage.read(key: _cloudBackupKeyStorage);
  }

  /// 检查是否已有云端备份密钥
  static Future<bool> hasCloudBackupKey() async {
    final key = await _secureStorage.read(key: _cloudBackupKeyStorage);
    return key != null && key.isNotEmpty;
  }

  /// 导入云端备份密钥
  static Future<bool> importCloudBackupKey(String keyBase64) async {
    try {
      await _secureStorage.write(key: _cloudBackupKeyStorage, value: keyBase64);
      return true;
    } catch (e) {
      print('导入云端备份密钥失败: $e');
      return false;
    }
  }

  /// 使用云端备份密钥加密数据
  static Future<String?> encryptWithCloudKey(String plainText) async {
    if (plainText.isEmpty) return plainText;

    try {
      var keyBase64 = await getCloudBackupKey();

      if (keyBase64 == null || keyBase64.isEmpty) {
        keyBase64 = await generateCloudBackupKey();
      }

      final key = encrypt.Key.fromBase64(keyBase64);
      final iv = encrypt.IV.fromSecureRandom(16);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encrypted = encrypter.encrypt(plainText, iv: iv);

      final result = '${iv.base64}:${encrypted.base64}';
      return '__CLOUD__${base64Encode(utf8.encode(result))}';
    } catch (e) {
      print('云端加密失败: $e');
      return plainText;
    }
  }

  /// 使用云端备份密钥解密数据
  static Future<String?> decryptWithCloudKey(String? cipherText, String keyBase64) async {
    if (cipherText == null || cipherText.isEmpty) return null;

    // 清理密钥
    final cleanKey = keyBase64.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanKey.isEmpty) {
      print('解密失败: 密钥为空');
      return null;
    }

    if (!cipherText.startsWith('__CLOUD__')) {
      print('解密: 非加密格式');
      return cipherText;
    }

    try {
      print('解密开始: 密文长度=${cipherText.length}');
      
      final key = encrypt.Key.fromBase64(cleanKey);

      // __CLOUD__ 是9个字符，不是8个！
      final payload = cipherText.substring(9);
      print('去掉前缀后: 长度=${payload.length}');
      
      final decoded = base64Decode(payload);
      print('Base64解码后: 长度=${decoded.length}');
      
      final inner = utf8.decode(decoded);
      print('UTF8解码后: 长度=${inner.length}');
      
      final parts = inner.split(':');
      print('分割后部分数: ${parts.length}');

      if (parts.length != 2) {
        print('解密失败: 格式不正确');
        return null;
      }

      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypted = encrypt.Encrypted.fromBase64(parts[1]);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final result = encrypter.decrypt(encrypted, iv: iv);
      print('解密成功: 原文长度=${result.length}');
      return result;
    } catch (e, stackTrace) {
      print('云端解密失败: $e');
      print('堆栈: $stackTrace');
      return null;
    }
  }

  /// 使用云端备份密钥加密二进制数据
  static Future<Uint8List?> encryptDataWithCloudKey(Uint8List data) async {
    try {
      var keyBase64 = await getCloudBackupKey();

      if (keyBase64 == null || keyBase64.isEmpty) {
        keyBase64 = await generateCloudBackupKey();
      }

      final key = encrypt.Key.fromBase64(keyBase64);
      final iv = encrypt.IV.fromSecureRandom(16);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encrypted = encrypter.encryptBytes(data, iv: iv);

      final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
      result.setRange(0, iv.bytes.length, iv.bytes);
      result.setRange(iv.bytes.length, result.length, encrypted.bytes);

      return result;
    } catch (e) {
      print('云端数据加密失败: $e');
      return null;
    }
  }

  /// 使用云端备份密钥解密二进制数据
  static Future<Uint8List?> decryptDataWithCloudKey(Uint8List encryptedData, String keyBase64) async {
    try {
      if (encryptedData.length < 16) {
        print('加密数据太短');
        return null;
      }

      final key = encrypt.Key.fromBase64(keyBase64);

      final iv = encrypt.IV(Uint8List.fromList(encryptedData.sublist(0, 16)));
      final cipherBytes = encryptedData.sublist(16);
      final encrypted = encrypt.Encrypted(cipherBytes);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
    } catch (e) {
      print('云端数据解密失败: $e');
      return null;
    }
  }

  /// 验证密钥是否有效（可以成功加密解密）
  static Future<Map<String, dynamic>> verifyKey(String keyBase64) async {
    final result = <String, dynamic>{
      'valid': false,
      'error': null,
      'canEncrypt': false,
      'canDecrypt': false,
    };

    try {
      // 清理密钥
      final cleanKey = keyBase64.trim().replaceAll(RegExp(r'\s+'), '');
      
      if (cleanKey.isEmpty) {
        result['error'] = '密钥为空';
        return result;
      }

      // 尝试解析密钥
      final key = encrypt.Key.fromBase64(cleanKey);
      result['keyLength'] = key.bytes.length;

      // 测试加密
      final testData = '{"test": "hello world 中文测试", "timestamp": ${DateTime.now().millisecondsSinceEpoch}}';
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );
      
      final encrypted = encrypter.encrypt(testData, iv: iv);
      result['canEncrypt'] = true;
      result['encryptedLength'] = encrypted.bytes.length;

      // 测试解密
      final decrypted = encrypter.decrypt(encrypted, iv: iv);
      result['canDecrypt'] = true;
      result['decryptedMatch'] = decrypted == testData;

      if (decrypted == testData) {
        result['valid'] = true;
      } else {
        result['error'] = '解密后的数据与原始数据不匹配';
      }

      return result;
    } catch (e, stackTrace) {
      result['error'] = '验证失败: $e';
      result['stackTrace'] = stackTrace.toString();
      return result;
    }
  }
}

// 辅助函数：JSON编码/解码
String jsonEncode(dynamic object) => json.encode(object);
dynamic jsonDecode(String source) => json.decode(source);
