import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_note.dart';
import '../models/self_talk_message.dart';
import '../models/self_talk_task.dart';
import 'database_service.dart';
import 'quick_note_service.dart';
import 'self_talk_service.dart';

/// 速记与自言自语外部存储备份服务
///
/// 设计原则：
/// - 只备份速记和自言自语（非保密数据）
/// - 日记数据绝不备份到外部存储
/// - 支持自定义备份目录
/// - 备份格式：JSON， human-readable
class QuickNoteBackupService {
  static const String _backupDirKey = 'quick_note_backup_directory';
  static const String _autoBackupKey = 'quick_note_auto_backup_enabled';
  static const String _lastBackupKey = 'quick_note_last_backup_time';

  /// 获取默认备份目录
  /// Documents/小记日记备份/
  static Future<Directory> getDefaultBackupDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${docsDir.parent.path}/Documents/小记日记备份');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// 获取当前备份目录（自定义或默认）
  static Future<Directory> getCurrentBackupDir() async {
    final prefs = await SharedPreferences.getInstance();
    final customDir = prefs.getString(_backupDirKey);
    if (customDir != null && customDir.isNotEmpty) {
      final dir = Directory(customDir);
      if (await dir.exists()) return dir;
    }
    return getDefaultBackupDir();
  }

  /// 设置自定义备份目录
  static Future<void> setCustomBackupDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backupDirKey, path);
  }

  /// 获取自动备份开关状态
  static Future<bool> getAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupKey) ?? false;
  }

  /// 设置自动备份开关
  static Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupKey, enabled);
  }

  /// 获取上次备份时间
  static Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastBackupKey);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 导出速记到外部存储
  ///
  /// [customDir] 可选自定义目录，null 使用当前设置目录
  /// 返回备份文件路径
  static Future<String> exportQuickNotes({String? customDir}) async {
    final dir = customDir != null ? Directory(customDir) : await getCurrentBackupDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final notes = await QuickNoteService.getAll();
    final data = {
      'version': 1,
      'type': 'quick_notes',
      'export_time': DateTime.now().toIso8601String(),
      'count': notes.length,
      'items': notes.map((n) => n.toMap()).toList(),
    };

    final fileName = 'quick_notes_${_formatTimestamp()}.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
    );

    // 同时写入最新备份（覆盖）
    final latestFile = File('${dir.path}/quick_notes_latest.json');
    await latestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
    );

    await _updateLastBackupTime();
    return file.path;
  }

  /// 导出自言自语到外部存储
  ///
  /// [customDir] 可选自定义目录
  /// 返回备份文件路径
  static Future<String> exportSelfTalk({String? customDir}) async {
    final dir = customDir != null ? Directory(customDir) : await getCurrentBackupDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 获取所有日期的消息
    final dates = await SelfTalkService.getRecordedDates();
    final allMessages = <SelfTalkMessage>[];
    final allTasks = <SelfTalkTask>[];

    for (final date in dates) {
      final messages = await SelfTalkService.getMessagesByDate(date);
      final tasks = await SelfTalkService.getTasksByDate(date);
      allMessages.addAll(messages.where((m) => m.id != null));
      allTasks.addAll(tasks.where((t) => t.id != null));
    }

    final data = {
      'version': 1,
      'type': 'self_talk',
      'export_time': DateTime.now().toIso8601String(),
      'message_count': allMessages.length,
      'task_count': allTasks.length,
      'messages': allMessages.map((m) => m.toMap()).toList(),
      'tasks': allTasks.map((t) => t.toMap()).toList(),
    };

    final fileName = 'self_talk_${_formatTimestamp()}.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
    );

    // 同时写入最新备份
    final latestFile = File('${dir.path}/self_talk_latest.json');
    await latestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
    );

    await _updateLastBackupTime();
    return file.path;
  }

  /// 同时导出速记和自言自语
  /// 返回两个备份文件路径
  static Future<Map<String, String>> exportAll({String? customDir}) async {
    final quickNotePath = await exportQuickNotes(customDir: customDir);
    final selfTalkPath = await exportSelfTalk(customDir: customDir);
    return {
      'quick_notes': quickNotePath,
      'self_talk': selfTalkPath,
    };
  }

  /// 从外部存储导入速记
  ///
  /// [filePath] 备份文件路径
  /// [mergeStrategy] 合并策略：'skip_existing'（跳过已有）/'overwrite'（覆盖）/'append'（全部追加）
  /// 返回导入数量
  static Future<int> importQuickNotes(String filePath, {String mergeStrategy = 'skip_existing'}) async {
    final file = File(filePath);
    if (!await file.exists()) return 0;

    final jsonStr = await file.readAsString(encoding: utf8);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final items = data['items'] as List<dynamic>?;
    if (items == null || items.isEmpty) return 0;

    var importedCount = 0;
    final existingNotes = await QuickNoteService.getAll();
    final existingContents = existingNotes.map((n) => '${n.content}_${n.createdAt}').toSet();

    for (final item in items) {
      try {
        final note = QuickNote.fromMap(item as Map<String, dynamic>);
        final key = '${note.content}_${note.createdAt}';

        if (mergeStrategy == 'skip_existing' && existingContents.contains(key)) {
          continue;
        }

        await DatabaseService.insertQuickNote(note);
        importedCount++;
      } catch (_) {
        // 单条失败继续处理下一条
      }
    }

    return importedCount;
  }

  /// 从外部存储导入自言自语
  ///
  /// [filePath] 备份文件路径
  /// 返回导入的消息数量和任务数量
  static Future<Map<String, int>> importSelfTalk(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return {'messages': 0, 'tasks': 0};

    final jsonStr = await file.readAsString(encoding: utf8);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    var messageCount = 0;
    var taskCount = 0;

    // 导入消息
    final messages = data['messages'] as List<dynamic>?;
    if (messages != null) {
      for (final item in messages) {
        try {
          final msg = SelfTalkMessage.fromMap(item as Map<String, dynamic>);
          await DatabaseService.insertSelfTalkMessage(msg);
          messageCount++;
        } catch (_) {}
      }
    }

    // 导入任务
    final tasks = data['tasks'] as List<dynamic>?;
    if (tasks != null) {
      for (final item in tasks) {
        try {
          final task = SelfTalkTask.fromMap(item as Map<String, dynamic>);
          await DatabaseService.insertSelfTalkTask(task);
          taskCount++;
        } catch (_) {}
      }
    }

    return {'messages': messageCount, 'tasks': taskCount};
  }

  /// 获取备份目录下的所有备份文件列表
  static Future<List<File>> listBackupFiles() async {
    final dir = await getCurrentBackupDir();
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith('.json'))
        .cast<File>()
        .toList();

    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// 删除指定备份文件
  static Future<void> deleteBackupFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 格式化时间戳用于文件名
  static String _formatTimestamp() {
    return DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  }

  /// 更新最后备份时间
  static Future<void> _updateLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
  }
}
