import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../models/mood.dart';

/// ZZ备份格式读取器
///
/// 备份目录结构：
/// - HeadInfo-xxx: 头部信息（icon、content、加密的用户信息）
/// - MoodList-xxx: 心情列表
/// - LabTagList-xxx: 标签列表
/// - TemplateList-xxx: 模板列表
/// - D_xxx: 日记内容（ZIP压缩，可能加密）
///
class ZZBackupReader {
  String? _backupPath;
  Map<String, dynamic>? _headInfo;
  Map<String, dynamic>? _moodList;
  Map<String, dynamic>? _tagList;
  Map<String, dynamic>? _templateList;
  final List<Map<String, dynamic>> _diaries = [];

  bool get hasData => _headInfo != null;

  /// 从目录读取备份
  Future<bool> readFromDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        debugPrint('备份目录不存在: $path');
        return false;
      }

      _backupPath = path;
      _diaries.clear();

      final files = await dir.list().toList();

      for (final file in files) {
        if (file is! File) continue;

        final fileName = file.path.split(Platform.pathSeparator).last;

        if (fileName.startsWith('HeadInfo-')) {
          _headInfo = await _readJsonFile(file.path);
          debugPrint('读取HeadInfo成功');
        } else if (fileName.startsWith('MoodList-')) {
          _moodList = await _readJsonFile(file.path);
          debugPrint('读取MoodList成功');
        } else if (fileName.startsWith('LabTagList-')) {
          _tagList = await _readJsonFile(file.path);
          debugPrint('读取LabTagList成功');
        } else if (fileName.startsWith('TemplateList-')) {
          _templateList = await _readJsonFile(file.path);
          debugPrint('读取TemplateList成功');
        } else if (fileName.startsWith('D_')) {
          // 日记文件
          final diaryData = await _readDiaryFile(file.path, fileName);
          if (diaryData != null) {
            _diaries.add(diaryData);
          }
        }
      }

      debugPrint('共读取 ${_diaries.length} 篇日记');
      return _headInfo != null || _diaries.isNotEmpty;
    } catch (e) {
      debugPrint('读取备份失败: $e');
      return false;
    }
  }

  /// 读取JSON文件
  Future<Map<String, dynamic>?> _readJsonFile(String path) async {
    try {
      final file = File(path);
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('读取JSON失败 $path: $e');
      return null;
    }
  }

  /// 读取日记文件（ZIP格式，可能加密）
  Future<Map<String, dynamic>?> _readDiaryFile(
      String path, String fileName) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();

      // 检查是否是ZIP文件
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
        debugPrint('日记文件不是ZIP格式: $fileName');
        return null;
      }

      // 尝试解压ZIP
      try {
        final archive = ZipDecoder().decodeBytes(bytes);

        for (final file in archive) {
          if (file.isFile) {
            debugPrint('ZIP内文件: ${file.name}, 大小: ${file.content.length}');

            // 尝试解析内容
            try {
              // 先尝试UTF-8解码
              final contentStr = utf8.decode(file.content);

              // 尝试JSON解析
              try {
                final jsonData = jsonDecode(contentStr) as Map<String, dynamic>;
                jsonData['_sourceFile'] = fileName;
                return jsonData;
              } catch (_) {
                // 不是JSON，返回原始内容
                return {
                  '_sourceFile': fileName,
                  '_fileName': file.name,
                  'content': contentStr,
                  'isPlainText': true,
                };
              }
            } catch (_) {
              // 不是UTF-8，可能是加密的二进制数据
              return {
                '_sourceFile': fileName,
                '_fileName': file.name,
                'contentBytes': base64Encode(file.content),
                'isEncrypted': true,
              };
            }
          }
        }
      } catch (e) {
        debugPrint('解压ZIP失败 $fileName: $e');
        // ZIP可能加密或损坏
        return {
          '_sourceFile': fileName,
          'rawBytes': base64Encode(bytes),
          'isEncryptedZip': true,
        };
      }

      return null;
    } catch (e) {
      debugPrint('读取日记文件失败 $fileName: $e');
      return null;
    }
  }

  /// 获取头部信息
  Map<String, dynamic>? get headInfo => _headInfo;

  /// 获取心情列表
  List<Map<String, dynamic>> getMoods() {
    if (_moodList == null) return [];
    final list = _moodList!['moodList'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 获取标签列表
  List<Map<String, dynamic>> getTags() {
    if (_tagList == null) return [];
    final list = _tagList!['tagLabList'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 获取模板列表
  List<Map<String, dynamic>> getTemplates() {
    if (_templateList == null) return [];
    final list = _templateList!['itemList'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  /// 获取原始日记数据
  List<Map<String, dynamic>> getRawDiaries() => _diaries;

  /// 转换为App的日记格式
  ///
  /// 注意：由于日记文件可能加密，需要根据实际情况调整映射逻辑
  List<DiaryImportData> convertToDiaryImportData() {
    final result = <DiaryImportData>[];

    for (final rawData in _diaries) {
      try {
        // 根据实际解析的数据结构转换
        // 这里需要根据解密后的实际内容调整

        if (rawData['isEncrypted'] == true ||
            rawData['isEncryptedZip'] == true) {
          // 加密的数据，无法直接读取
          result.add(DiaryImportData(
            title: '【加密日记】',
            content: '此日记文件已加密，需要密码才能查看\\n源文件: ${rawData['_sourceFile']}',
            date: DateTime.now().toIso8601String(),
            isEncrypted: true,
          ));
          continue;
        }

        // 尝试解析不同格式的内容
        String? title;
        String? content;
        String? date;
        String? moodName;
        String? moodColor;

        // 格式1: 如果content字段是纯文本
        if (rawData['isPlainText'] == true) {
          content = rawData['content'] as String?;
          title = '导入的日记';
        }
        // 格式2: 如果有JSON结构
        else {
          // 尝试常见的字段名
          title = rawData['title'] ?? rawData['templateName'] ?? '无标题';
          content = rawData['content'] ??
              rawData['templateDesc'] ??
              rawData['text'] ??
              '';
          date = rawData['date'] ??
              rawData['createTime'] ??
              rawData['lastUpdateTime']?.toString();
          moodName = rawData['mood'] ?? rawData['moodName'];
          moodColor = rawData['moodColor'];
        }

        // 解析日期
        DateTime? parsedDate;
        if (date != null) {
          // 尝试不同格式
          parsedDate = _parseDate(date);
        }
        parsedDate ??= DateTime.now();

        result.add(DiaryImportData(
          title: title,
          content: content ?? '',
          date: parsedDate.toIso8601String(),
          moodName: moodName,
          moodColor: moodColor,
          rawData: rawData, // 保留原始数据以备后用
        ));
      } catch (e) {
        debugPrint('转换日记失败: $e');
      }
    }

    return result;
  }

  /// 解析日期（支持多种格式）
  DateTime? _parseDate(String dateStr) {
    try {
      // 尝试ISO格式
      return DateTime.parse(dateStr);
    } catch (_) {
      try {
        // 尝试时间戳（毫秒）
        final timestamp = int.tryParse(dateStr);
        if (timestamp != null) {
          return DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      } catch (_) {}
    }
    return null;
  }

  /// 获取备份统计信息
  Map<String, dynamic> getStatistics() {
    return {
      'hasHeadInfo': _headInfo != null,
      'hasMoodList': _moodList != null,
      'hasTagList': _tagList != null,
      'hasTemplateList': _templateList != null,
      'diaryCount': _diaries.length,
      'encryptedDiaryCount': _diaries
          .where((d) => d['isEncrypted'] == true || d['isEncryptedZip'] == true)
          .length,
      'minVersion': _headInfo?['minVersion'],
    };
  }
}

/// 日记导入数据结构
class DiaryImportData {
  final String? title;
  final String content;
  final String date;
  final String? moodName;
  final String? moodColor;
  final bool isEncrypted;
  final Map<String, dynamic>? rawData;

  DiaryImportData({
    this.title,
    required this.content,
    required this.date,
    this.moodName,
    this.moodColor,
    this.isEncrypted = false,
    this.rawData,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'date': date,
      'moodName': moodName,
      'moodColor': moodColor,
      'isEncrypted': isEncrypted,
    };
  }
}

/// 心情导入数据结构
class MoodImportData {
  final String uuid;
  final String name;
  final String? translatedName; // 英文转中文
  final int sortNum;
  final double score;
  final String color;

  MoodImportData({
    required this.uuid,
    required this.name,
    this.translatedName,
    required this.sortNum,
    required this.score,
    required this.color,
  });

  static MoodImportData fromMap(Map<String, dynamic> map) {
    // 英文心情名称映射到中文
    final nameTranslations = {
      'Joy': '开心',
      'Satisfied': '满足',
      'Not bad': '不错',
      'So-so': '一般',
      'Depressed': '沮丧',
      'Sad': '难过',
      'Unhappy': '不开心',
      'Angry': '生气',
    };

    final name = map['name'] as String? ?? '';

    return MoodImportData(
      uuid: map['uuid'] as String? ?? '',
      name: name,
      translatedName: nameTranslations[name],
      sortNum: map['sortNum'] as int? ?? 0,
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
      color: map['moodColor'] as String? ?? '#7DD3C0',
    );
  }

  Mood toMoodModel() {
    return Mood(
      name: translatedName ?? name,
      emoji: _getEmojiByScore(score),
      color: color,
      sortOrder: sortNum,
    );
  }

  String _getEmojiByScore(double score) {
    if (score >= 1.0) return '😊';
    if (score >= 0.5) return '🙂';
    if (score >= 0) return '😐';
    if (score >= -0.5) return '😕';
    if (score >= -1.0) return '😢';
    return '😠';
  }
}
