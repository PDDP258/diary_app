import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import 'database_service.dart';

/// 自动备份服务
/// 
/// 功能：
/// 1. 定期自动备份（每天/每周）
/// 2. 保留最近 N 次备份
/// 3. 支持手动触发备份
/// 4. 备份历史管理
/// 
/// 备份策略：
/// - 每天首次启动时检查是否需要备份
/// - 保留最近 7 次备份
/// - 备份文件存储在应用私有目录
class AutoBackupService {
  static const String _backupDirName = 'auto_backups';
  static const String _backupInfoKey = 'auto_backup_info';
  static const int _maxBackupCount = 7; // 保留最近7次备份
  static const int _backupIntervalHours = 24; // 每天备份一次

  /// 检查并执行自动备份
  /// 
  /// 返回：是否执行了备份
  static Future<bool> checkAndBackup() async {
    try {
      // 检查是否需要备份
      if (!await _shouldBackup()) {
        return false;
      }

      // 执行备份
      await performBackup();
      return true;
    } catch (e) {
      print('自动备份失败: $e');
      return false;
    }
  }

  /// 检查是否需要备份
  static Future<bool> _shouldBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackupTime = prefs.getInt('last_auto_backup_time');

    if (lastBackupTime == null) {
      return true; // 从未备份过
    }

    final lastBackup = DateTime.fromMillisecondsSinceEpoch(lastBackupTime);
    final now = DateTime.now();
    final diff = now.difference(lastBackup);

    return diff.inHours >= _backupIntervalHours;
  }

  /// 执行备份
  static Future<String> performBackup() async {
    try {
      // 1. 获取应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/$_backupDirName');

      // 2. 确保备份目录存在
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // 3. 获取数据
      final diaries = await DatabaseService.getAllDiaries();
      final moods = await DatabaseService.getAllMoods();
      final tags = await DatabaseService.getAllTags();

      // 4. 构建备份数据
      final backupData = {
        'version': '1.1.0',
        'backupTime': DateTime.now().toIso8601String(),
        'diaries': diaries.map((d) => d.toMap()).toList(),
        'moods': moods.map((m) => m.toMap()).toList(),
        'tags': tags.map((t) => t.toMap()).toList(),
      };

      // 5. 生成备份文件名（带时间戳）
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'backup_$timestamp.json';
      final filePath = '${backupDir.path}/$fileName';

      // 6. 写入文件
      final file = File(filePath);
      await file.writeAsString(jsonEncode(backupData));

      // 7. 更新备份信息
      await _updateBackupInfo(filePath, backupData);

      // 8. 清理旧备份
      await _cleanupOldBackups();

      // 9. 记录备份时间
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_auto_backup_time', DateTime.now().millisecondsSinceEpoch);

      print('自动备份完成: $filePath');
      return filePath;
    } catch (e) {
      print('备份失败: $e');
      rethrow;
    }
  }

  /// 更新备份信息列表
  static Future<void> _updateBackupInfo(String filePath, Map<String, dynamic> backupData) async {
    final prefs = await SharedPreferences.getInstance();
    final infoJson = prefs.getString(_backupInfoKey);
    
    List<Map<String, dynamic>> backupList = [];
    if (infoJson != null) {
      backupList = List<Map<String, dynamic>>.from(jsonDecode(infoJson));
    }

    // 添加新备份信息
    backupList.insert(0, {
      'filePath': filePath,
      'backupTime': backupData['backupTime'],
      'diaryCount': (backupData['diaries'] as List).length,
      'size': await File(filePath).length(),
    });

    // 保存更新后的列表
    await prefs.setString(_backupInfoKey, jsonEncode(backupList));
  }

  /// 清理旧备份
  static Future<void> _cleanupOldBackups() async {
    final backupList = await getBackupList();
    
    if (backupList.length <= _maxBackupCount) {
      return;
    }

    // 删除超出保留数量的旧备份
    final toDelete = backupList.sublist(_maxBackupCount);
    for (final backup in toDelete) {
      try {
        final file = File(backup['filePath']);
        if (await file.exists()) {
          await file.delete();
          print('删除旧备份: ${backup['filePath']}');
        }
      } catch (e) {
        print('删除旧备份失败: $e');
      }
    }

    // 更新备份信息列表
    final prefs = await SharedPreferences.getInstance();
    final updatedList = backupList.sublist(0, _maxBackupCount);
    await prefs.setString(_backupInfoKey, jsonEncode(updatedList));
  }

  /// 获取备份列表
  static Future<List<Map<String, dynamic>>> getBackupList() async {
    final prefs = await SharedPreferences.getInstance();
    final infoJson = prefs.getString(_backupInfoKey);
    
    if (infoJson == null) {
      return [];
    }

    final List<dynamic> list = jsonDecode(infoJson);
    
    // 过滤掉已不存在的文件
    final validBackups = <Map<String, dynamic>>[];
    for (final backup in list) {
      final file = File(backup['filePath']);
      if (await file.exists()) {
        validBackups.add(Map<String, dynamic>.from(backup));
      }
    }

    return validBackups;
  }

  /// 从备份恢复
  static Future<bool> restoreFromBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('备份文件不存在');
      }

      final jsonStr = await file.readAsString();
      final backupData = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 验证备份数据
      if (!backupData.containsKey('diaries') ||
          !backupData.containsKey('moods') ||
          !backupData.containsKey('tags')) {
        throw Exception('备份文件格式不正确');
      }

      // 恢复日记
      final diariesList = backupData['diaries'] as List;
      final diaries = diariesList.map((e) => Diary.fromMap(e)).toList();
      await DatabaseService.restoreDiaries(diaries);

      // 恢复心情
      final moodsList = backupData['moods'] as List;
      final moods = moodsList.map((e) => Mood.fromMap(e)).toList();
      await DatabaseService.restoreMoods(moods);

      // 恢复标签
      final tagsList = backupData['tags'] as List;
      final tags = tagsList.map((e) => Tag.fromMap(e)).toList();
      await DatabaseService.restoreTags(tags);

      print('从备份恢复成功: $filePath');
      return true;
    } catch (e) {
      print('恢复备份失败: $e');
      rethrow;
    }
  }

  /// 删除指定备份
  static Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // 从备份列表中移除
      final prefs = await SharedPreferences.getInstance();
      final infoJson = prefs.getString(_backupInfoKey);
      if (infoJson != null) {
        final List<dynamic> list = jsonDecode(infoJson);
        list.removeWhere((b) => b['filePath'] == filePath);
        await prefs.setString(_backupInfoKey, jsonEncode(list));
      }

      return true;
    } catch (e) {
      print('删除备份失败: $e');
      return false;
    }
  }

  /// 获取备份存储大小
  static Future<int> getTotalBackupSize() async {
    final backupList = await getBackupList();
    int totalSize = 0;
    for (final backup in backupList) {
      totalSize += (backup['size'] as int? ?? 0);
    }
    return totalSize;
  }

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
