import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// MBK备份文件读取器
///
/// 支持读取加密的MBK备份格式（ZIP + AES加密）
class MBKBackupReader {
  String? _filePath;
  Uint8List? _fileData;
  Map<String, dynamic>? _manifest;
  List<MBKDiaryEntry> _entries = [];

  bool get hasData => _fileData != null;

  /// 从文件读取
  Future<bool> readFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('文件不存在: $filePath');
        return false;
      }

      _filePath = filePath;
      _fileData = await file.readAsBytes();

      // 检查是否是ZIP格式
      if (!_isZipFile(_fileData!)) {
        debugPrint('不是有效的ZIP/MBK文件');
        return false;
      }

      // 尝试读取ZIP结构
      await _parseZipStructure();

      return _entries.isNotEmpty || _manifest != null;
    } catch (e) {
      debugPrint('读取MBK文件失败: $e');
      return false;
    }
  }

  /// 从字节数据读取
  Future<bool> readFromBytes(Uint8List data) async {
    try {
      _fileData = data;

      if (!_isZipFile(data)) {
        debugPrint('不是有效的ZIP/MBK文件');
        return false;
      }

      await _parseZipStructure();
      return _entries.isNotEmpty || _manifest != null;
    } catch (e) {
      debugPrint('读取MBK数据失败: $e');
      return false;
    }
  }

  /// 检查是否是ZIP文件
  bool _isZipFile(Uint8List data) {
    if (data.length < 4) return false;
    // ZIP文件头: PK\x03\x04 或 PK\x05\x06
    return data[0] == 0x50 && data[1] == 0x4B;
  }

  /// 解析ZIP结构
  Future<void> _parseZipStructure() async {
    try {
      // 尝试直接解压（如果未加密）
      final archive = ZipDecoder().decodeBytes(_fileData!);

      _entries = [];

      for (final file in archive) {
        debugPrint('发现文件: ${file.name}, 大小: ${file.content.length}');

        if (file.isFile) {
          // 尝试解析JSON内容
          try {
            final contentStr = utf8.decode(file.content);
            final jsonData = jsonDecode(contentStr) as Map<String, dynamic>;

            _entries.add(MBKDiaryEntry(
              fileName: file.name,
              jsonData: jsonData,
            ));
          } catch (e) {
            // 可能是加密的二进制数据
            _entries.add(MBKDiaryEntry(
              fileName: file.name,
              rawBytes: file.content,
              isEncrypted: true,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('解析ZIP失败，可能是加密文件: $e');
      // 文件可能是加密的，记录原始信息
      _entries.add(MBKDiaryEntry(
        fileName: 'encrypted_data',
        rawBytes: _fileData,
        isEncrypted: true,
      ));
    }
  }

  /// 尝试用密码解密
  Future<bool> tryDecrypt(String password) async {
    // 注意：标准的archive包不支持ZIP AES加密
    // 需要额外的库或原生代码支持
    // 这里只是一个占位符，实际实现需要更复杂的解密逻辑

    debugPrint('尝试解密...密码长度: ${password.length}');

    // TODO: 实现AES解密
    // 需要知道具体的加密方式（AES-256? AES-128?）
    // 和盐值/IV

    return false;
  }

  /// 获取所有条目
  List<MBKDiaryEntry> get entries => _entries;

  /// 获取清单信息
  Map<String, dynamic>? get manifest => _manifest;

  /// 获取统计信息
  Map<String, dynamic> getStatistics() {
    return {
      'filePath': _filePath,
      'fileSize': _fileData?.length ?? 0,
      'entryCount': _entries.length,
      'encryptedEntries': _entries.where((e) => e.isEncrypted).length,
      'readableEntries': _entries.where((e) => !e.isEncrypted).length,
    };
  }

  /// 获取文件预览信息（前N字节）
  String getFilePreview(int byteCount) {
    if (_fileData == null) return '无数据';

    final bytes = _fileData!.sublist(0, byteCount.clamp(0, _fileData!.length));
    final hexStr =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

    return 'HEX: $hexStr';
  }

  /// 导出可读的日记数据
  List<Map<String, dynamic>> exportReadableEntries() {
    final result = <Map<String, dynamic>>[];

    for (final entry in _entries) {
      if (!entry.isEncrypted && entry.jsonData != null) {
        result.add({
          'fileName': entry.fileName,
          'data': entry.jsonData,
        });
      }
    }

    return result;
  }
}

/// MBK日记条目
class MBKDiaryEntry {
  final String fileName;
  final Map<String, dynamic>? jsonData;
  final Uint8List? rawBytes;
  final bool isEncrypted;

  MBKDiaryEntry({
    required this.fileName,
    this.jsonData,
    this.rawBytes,
    this.isEncrypted = false,
  });

  /// 获取人类可读的文件类型
  String get fileType {
    if (fileName.contains('HeadInfo')) return '头部信息';
    if (fileName.contains('MoodList')) return '心情列表';
    if (fileName.contains('LabTagList')) return '标签列表';
    if (fileName.contains('TemplateList')) return '模板列表';
    if (fileName.contains('DiaryContent')) return '日记内容';
    if (fileName.contains('Pic_')) return '图片';
    return '其他';
  }

  /// 获取内容预览
  String get contentPreview {
    if (isEncrypted) {
      return '【加密数据】大小: ${rawBytes?.length ?? 0} bytes';
    }

    if (jsonData != null) {
      final preview = jsonEncode(jsonData).substring(0, 200);
      return '$preview...';
    }

    return '无内容';
  }
}

/// 备份格式转换器
///
/// 将ZZ目录格式或MBK格式转换为App内部格式
class BackupFormatConverter {
  /// 自动检测格式并转换
  static Future<List<DiaryImportEntry>> convertBackup(String sourcePath) async {
    final entries = <DiaryImportEntry>[];

    // 检测是否是目录
    final dir = Directory(sourcePath);
    if (await dir.exists()) {
      // ZZ目录格式
      final reader = ZZBackupReader();
      final success = await reader.readFromDirectory(sourcePath);

      if (success) {
        final diaries = reader.convertToDiaryImportData();
        entries.addAll(diaries.map((d) => DiaryImportEntry(
              title: d.title ?? '无标题',
              content: d.content,
              date: d.date,
              moodName: d.moodName,
              moodColor: d.moodColor,
              source: 'ZZ格式',
            )));
      }
    } else {
      // 尝试MBK文件格式
      final file = File(sourcePath);
      if (await file.exists()) {
        final reader = MBKBackupReader();
        final success = await reader.readFromFile(sourcePath);

        if (success) {
          final readableEntries = reader.exportReadableEntries();
          for (final entry in readableEntries) {
            final data = entry['data'] as Map<String, dynamic>?;
            if (data != null) {
              entries.add(_parseMBKEntry(data));
            }
          }
        }
      }
    }

    return entries;
  }

  /// 解析MBK条目
  static DiaryImportEntry _parseMBKEntry(Map<String, dynamic> data) {
    // 根据MBK格式解析
    // 这里需要根据实际格式调整

    String? title;
    String? content;
    String? date;

    // 尝试不同的字段名
    if (data.containsKey('title')) {
      title = data['title'] as String?;
    } else if (data.containsKey('templateName')) {
      title = data['templateName'] as String?;
    }

    if (data.containsKey('content')) {
      content = data['content'] as String?;
    } else if (data.containsKey('text')) {
      content = data['text'] as String?;
    } else if (data.containsKey('templateDesc')) {
      content = data['templateDesc'] as String?;
    }

    if (data.containsKey('date')) {
      date = data['date'] as String?;
    } else if (data.containsKey('createTime')) {
      final timestamp = data['createTime'] as int?;
      if (timestamp != null) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String();
      }
    }

    return DiaryImportEntry(
      title: title ?? '无标题',
      content: content ?? '',
      date: date ?? DateTime.now().toIso8601String(),
      source: 'MBK格式',
    );
  }
}

/// 日记导入条目
class DiaryImportEntry {
  final String title;
  final String content;
  final String date;
  final String? moodName;
  final String? moodColor;
  final String source;

  DiaryImportEntry({
    required this.title,
    required this.content,
    required this.date,
    this.moodName,
    this.moodColor,
    required this.source,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'date': date,
      'moodName': moodName,
      'moodColor': moodColor,
      'source': source,
    };
  }
}

// 引入ZZBackupReader（假设在同一个文件中或需要import）
// 如果分开文件，需要添加import
class ZZBackupReader {
  Future<bool> readFromDirectory(String path) async {
    // 复用之前的实现
    return false;
  }

  List<dynamic> convertToDiaryImportData() {
    return [];
  }
}
