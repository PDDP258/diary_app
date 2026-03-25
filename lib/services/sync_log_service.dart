import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// 云同步日志服务
/// 将同步日志记录到 Markdown 文件中
class SyncLogService {
  static const String _logFileName = 'cloud_sync_log.md';
  static String? _logFilePath;

  /// 初始化并创建日志文件
  static Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFilePath = '${directory.path}/$_logFileName';

      // 如果文件不存在，创建并写入头部
      final file = File(_logFilePath!);
      if (!await file.exists()) {
        const header = '''# 云同步日志

> 本文件记录所有云端同步操作的详细日志，便于排查问题。

---

''';
        await file.writeAsString(header);
      }
    } catch (e) {
      print('[SyncLog] 初始化日志服务失败: $e');
    }
  }

  /// 写入日志
  static Future<void> log(String message, {String level = 'INFO'}) async {
    try {
      if (_logFilePath == null) {
        await initialize();
      }

      final timestamp =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final logEntry = '**[$timestamp]** **[$level]** $message\n\n';

      final file = File(_logFilePath!);
      await file.writeAsString(logEntry, mode: FileMode.append);

      // 同时输出到控制台
      print('[CloudSync] $message');
    } catch (e) {
      print('[SyncLog] 写入日志失败: $e');
    }
  }

  /// 写入分隔线
  static Future<void> logSeparator() async {
    try {
      if (_logFilePath == null) {
        await initialize();
      }

      final file = File(_logFilePath!);
      await file.writeAsString('---\n\n', mode: FileMode.append);
    } catch (e) {
      print('[SyncLog] 写入分隔线失败: $e');
    }
  }

  /// 获取日志文件路径
  static String? get logFilePath => _logFilePath;

  /// 读取所有日志内容
  static Future<String> readAllLogs() async {
    try {
      if (_logFilePath == null) {
        await initialize();
      }

      final file = File(_logFilePath!);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return '# 云同步日志\n\n暂无日志记录。';
    } catch (e) {
      return '# 错误\n\n读取日志失败: $e';
    }
  }

  /// 清空日志
  static Future<void> clearLogs() async {
    try {
      if (_logFilePath == null) {
        await initialize();
      }

      final file = File(_logFilePath!);
      final header = '''# 云同步日志

> 本文件记录所有云端同步操作的详细日志，便于排查问题。

---

**[${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}]** **[INFO]** 日志已清空

''';
      await file.writeAsString(header);
    } catch (e) {
      print('[SyncLog] 清空日志失败: $e');
    }
  }
}
