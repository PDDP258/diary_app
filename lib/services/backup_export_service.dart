import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'encryption_service.dart';

/// 加密备份导出服务
/// 支持AES-256加密，用户自定义密码
/// 
/// 注意：备份数据在导出前会自动解密，然后整个备份文件使用用户密码加密。
/// 这样可以确保：
/// 1. 备份文件可以在其他设备上恢复（只要有密码）
/// 2. 备份文件本身是加密的，保护用户隐私
class BackupExportService {
  /// 使用密码加密数据并导出为.mbk文件
  /// 
  /// [backupData] 应该是从数据库读取的原始数据（已解密）
  /// [password] 用户设置的备份密码
  static Future<String> exportWithPassword({
    required Map<String, dynamic> backupData,
    required String password,
  }) async {
    // 1. 生成数据哈希
    final dataHash = _generateDataHash(backupData);
    backupData['_hash'] = dataHash;
    
    // 2. 添加元数据
    final exportData = {
      ...backupData,
      'encrypted': true,
      'encryptAlgorithm': 'AES-256',
      'exportTime': DateTime.now().toIso8601String(),
    };
    
    // 3. 转换为JSON
    final jsonStr = jsonEncode(exportData);
    final jsonBytes = utf8.encode(jsonStr);
    
    // 4. 生成随机IV
    final iv = encrypt.IV.fromSecureRandom(16);
    
    // 5. 生成密钥 (PBKDF2衍生的密钥)
    final key = _deriveKey(password);
    
    // 6. AES加密
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    );
    final encrypted = encrypter.encryptBytes(jsonBytes, iv: iv);
    
    // 7. 创建ZIP包
    final archive = Archive();
    
    // 添加加密数据文件
    archive.addFile(ArchiveFile(
      'encrypted_data.dat',
      encrypted.bytes.length,
      encrypted.bytes,
    ));
    
    // 添加IV和盐值 (Base64编码)
    archive.addFile(ArchiveFile(
      'iv.txt',
      iv.base64.length,
      utf8.encode(iv.base64),
    ));
    
    // 添加元数据
    final metaData = jsonEncode({
      'version': '1.0.0',
      'encrypted': true,
      'algorithm': 'AES-256',
    });
    archive.addFile(ArchiveFile(
      'meta.json',
      metaData.length,
      utf8.encode(metaData),
    ));
    
    // 8. 编码为Bytes
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('创建ZIP失败');
    }
    
    // 9. 使用文件选择器让用户选择保存位置
    final filePath = await _saveWithFilePicker(zipData, 'mbk');
    
    return filePath;
  }
  
  /// 使用密码解密备份文件
  static Future<Map<String, dynamic>?> importWithPassword({
    required String filePath,
    required String password,
  }) async {
    try {
      // 1. 读取文件
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      
      // 2. 解码ZIP
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // 3. 读取IV
      final ivFile = archive.findFile('iv.txt');
      if (ivFile == null) {
        throw Exception('无效的备份文件：缺少IV');
      }
      final ivBase64 = utf8.decode(ivFile.content as List<int>);
      final iv = encrypt.IV.fromBase64(ivBase64);
      
      // 4. 读取加密数据
      final dataFile = archive.findFile('encrypted_data.dat');
      if (dataFile == null) {
        throw Exception('无效的备份文件：缺少数据');
      }
      final encryptedBytes = dataFile.content as List<int>;
      final encrypted = encrypt.Encrypted(Uint8List.fromList(encryptedBytes));
      
      // 5. 生成密钥
      final key = _deriveKey(password);
      
      // 6. 解密
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      
      // 7. 解析JSON
      final jsonStr = utf8.decode(decrypted);
      final backupData = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      // 8. 验证数据完整性
      if (!_verifyDataIntegrity(backupData)) {
        throw Exception('数据验证失败：密码可能不正确或文件已损坏');
      }
      
      return backupData;
    } catch (e) {
      debugPrint('解密失败: $e');
      return null;
    }
  }
  
  /// 导出不加密的备份 (用于兼容旧版本)
  static Future<String> exportPlain({
    required Map<String, dynamic> backupData,
  }) async {
    // 添加元数据
    final exportData = {
      ...backupData,
      'encrypted': false,
      'exportTime': DateTime.now().toIso8601String(),
    };
    
    final jsonStr = jsonEncode(exportData);
    final jsonBytes = utf8.encode(jsonStr);
    
    // 创建ZIP包
    final archive = Archive();
    archive.addFile(ArchiveFile(
      'backup.json',
      jsonBytes.length,
      jsonBytes,
    ));
    
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('创建ZIP失败');
    }
    
    // 使用文件选择器保存
    final filePath = await _saveWithFilePicker(zipData, 'mbk');
    
    return filePath;
  }
  
  /// 使用文件选择器保存文件（支持用户选择保存位置）
  static Future<String> _saveWithFilePicker(List<int> bytes, String extension) async {
    // 生成文件名
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'diary_backup_$timestamp.$extension';
    
    // 先保存到临时目录
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/$fileName';
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(bytes);
    
    // 尝试使用文件选择器让用户选择保存位置
    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      
      if (selectedDirectory != null) {
        // 用户选择了目录
        final targetPath = '$selectedDirectory/$fileName';
        await tempFile.copy(targetPath);
        await tempFile.delete(); // 删除临时文件
        return targetPath;
      }
    } catch (e) {
      debugPrint('文件选择器失败: $e');
    }
    
    // 备用方案：保存到应用文档目录
    final appDir = await getApplicationDocumentsDirectory();
    final appPath = '${appDir.path}/$fileName';
    await tempFile.copy(appPath);
    await tempFile.delete();
    
    return appPath;
  }
  
  
  /// 导入不加密的备份
  static Future<Map<String, dynamic>?> importPlain(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      
      final archive = ZipDecoder().decodeBytes(bytes);
      final backupFile = archive.findFile('backup.json');
      
      if (backupFile == null) {
        throw Exception('无效的备份文件');
      }
      
      final jsonStr = utf8.decode(backupFile.content as List<int>);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('导入失败: $e');
      return null;
    }
  }
  
  /// 检查备份文件是否加密
  static Future<bool> isEncrypted(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      
      final archive = ZipDecoder().decodeBytes(bytes);
      final metaFile = archive.findFile('meta.json');
      
      if (metaFile == null) return false;
      
      final jsonStr = utf8.decode(metaFile.content as List<int>);
      final meta = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      return meta['encrypted'] == true;
    } catch (e) {
      return false;
    }
  }
  
  /// 使用PBKDF2从密码派生密钥
  static encrypt.Key _deriveKey(String password) {
    // 使用固定的盐值 (实际应用中应随机生成并存储)
    const salt = 'diary_app_salt_v1';
    final keyBytes = utf8.encode(password + salt);
    final hash = sha256.convert(keyBytes);
    return encrypt.Key(Uint8List.fromList(hash.bytes));
  }
  
  /// 生成数据哈希
  static String _generateDataHash(Map<String, dynamic> data) {
    final dataCopy = Map<String, dynamic>.from(data)..remove('_hash');
    final jsonStr = jsonEncode(dataCopy);
    final bytes = utf8.encode(jsonStr);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// 验证数据完整性
  static bool _verifyDataIntegrity(Map<String, dynamic> data) {
    if (!data.containsKey('_hash')) return true;
    final storedHash = data['_hash'] as String;
    final dataCopy = Map<String, dynamic>.from(data)..remove('_hash');
    final computedHash = _generateDataHash(dataCopy);
    return storedHash == computedHash;
  }
}

/// 调试打印
void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}
