import 'dart:convert';
import 'dart:io';

import 'package:charset_converter/charset_converter.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/course.dart';
import '../../utils/day_of_week.dart';
import '../../utils/week_parser.dart';
import 'course_import_source.dart';

/// Excel/CSV 模板导入（动态表头识别）
///
/// 第一行固定为表头，列位置随意，按表头名字动态识别列含义。
/// 每个字段支持多个关键词（如「课程名称/课程名/课程/科目/name」）。
/// 必填：课程名称、星期、节次（开始节+结束节，或合并的「节次」列）。
/// 选填：教师、周次（缺省按全部周）、地点、颜色。
///
/// 示例（列顺序任意）：
///   地点,课程名称,星期,节次,周次,教师
///   教一101,高等数学,周一,1-2,1-16,张老师
///
/// 兼容旧的固定列顺序模板（表头识别失败时回退）。
class TemplateImportSource extends CourseImportSource {
  @override
  String get name => 'Excel/CSV 模板';

  /// 模板文本（供复制）
  static const templateCsv = '课程名称,教师,星期,节次,周次,地点\n'
      '高等数学,张老师,1,1-2,1-16,教一101\n'
      '大学英语,李老师,周三,3-4,1-15单周,外语楼302\n';

  /// 字段关键词表（匹配前会归一化：去空白/冒号/下划线、转小写）
  static const _aliases = <String, List<String>>{
    'name': ['课程名称', '课程名', '课程', '课名', '名称', '科目', 'coursename', 'course', 'name', 'title', 'subject'],
    'teacher': ['任课教师', '授课教师', '任课老师', '教师', '老师', '主讲', 'teacher', 'instructor', 'lecturer'],
    'weekday': ['星期几', '上课星期', '星期', '周几', '上课日', 'weekday', 'dayofweek', 'day'],
    'start': ['开始节次', '起始节次', '开始节', '起始节', '起节', 'startsection', 'sectionstart', 'start'],
    'end': ['结束节次', '结束节', '止节', '末节', 'endsection', 'sectionend', 'end'],
    'sections': ['上课节次', '上课节数', '节次', '节数', 'sections', 'section'],
    'weeks': ['上课周次', '上课周', '周次', '周数', 'weeks', 'week'],
    'location': ['上课地点', '地点', '教室', '位置', '场所', 'location', 'classroom', 'room', 'place'],
    'color': ['颜色', 'color', 'colour'],
  };

  /// 匹配优先级（靠前的先认领列，避免「周几」被「周」抢走）
  static const _fieldPriority = [
    'name', 'teacher', 'weekday', 'start', 'end', 'sections', 'weeks', 'location', 'color',
  ];

  @override
  Future<ImportDraft?> collect() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    List<List<String>> rows;
    if (file.extension == 'xlsx') {
      rows = _parseXlsx(file);
    } else {
      rows = await _parseCsv(file);
    }
    return parseRows(rows);
  }

  /// 解析行数据为 ImportDraft（独立成方法便于测试）
  static ImportDraft parseRows(List<List<String>> rows) {
    final issues = <String>[];
    final courses = <Course>[];
    if (rows.isEmpty) {
      return ImportDraft(courses: const [], issues: const ['文件为空'], sourceName: 'Excel/CSV 模板');
    }

    // 1) 尝试动态表头识别
    final columnMap = _mapHeaders(rows.first);
    final hasSections = columnMap.containsKey('sections') ||
        (columnMap.containsKey('start') && columnMap.containsKey('end'));
    final headerOk =
        columnMap.containsKey('name') && columnMap.containsKey('weekday') && hasSections;

    // 2) 识别失败则回退旧固定列顺序：课程名称,教师,星期,开始节,结束节,周次,地点
    late final List<List<String>> dataRows;
    late final Map<String, int> effectiveMap;
    if (headerOk) {
      dataRows = rows.sublist(1);
      effectiveMap = columnMap;
    } else {
      effectiveMap = const {
        'name': 0, 'teacher': 1, 'weekday': 2, 'start': 3, 'end': 4, 'weeks': 5, 'location': 6,
      };
      // 首行像表头（必填列含非数据文字）则跳过，否则当作数据行
      final first = rows.first;
      final looksLikeHeader = first.length > 2 && tryParseDayOfWeek(first[2]) == null;
      dataRows = looksLikeHeader ? rows.sublist(1) : rows;
      if (first.isNotEmpty && !looksLikeHeader) {
        issues.add('未识别到表头，已按固定列顺序（课程名称,教师,星期,开始节,结束节,周次,地点）解析');
      }
    }

    for (var i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      final lineNo = i + (identical(dataRows, rows) ? 1 : 2);
      if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;
      try {
        courses.add(_parseRow(row, effectiveMap));
      } on FormatException catch (e) {
        issues.add('第 $lineNo 行：${e.message}');
      }
    }

    return ImportDraft(
      courses: mergeCoursesByName(courses),
      issues: issues,
      sourceName: 'Excel/CSV 模板',
    );
  }

  /// 表头归一化：去空白/冒号/下划线/连字符/括号内容，转小写
  static String _normalize(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-:：]'), '')
      .replaceAll(RegExp(r'[\(（\[【].*?[\)）\]】]'), '');

  /// 把表头行映射为 字段 -> 列号。先精确匹配，再包含匹配，每列只认领一次。
  static Map<String, int> _mapHeaders(List<String> headerRow) {
    final normalized = headerRow.map(_normalize).toList();
    final result = <String, int>{};
    final claimed = <int>{};

    // 第一遍：精确匹配
    for (final field in _fieldPriority) {
      for (var col = 0; col < normalized.length; col++) {
        if (claimed.contains(col) || normalized[col].isEmpty) continue;
        if (_aliases[field]!.any((a) => normalized[col] == _normalize(a))) {
          result[field] = col;
          claimed.add(col);
          break;
        }
      }
    }
    // 第二遍：包含匹配（表头含关键词或关键词含表头，关键词至少 2 字防误伤）
    for (final field in _fieldPriority) {
      if (result.containsKey(field)) continue;
      for (var col = 0; col < normalized.length; col++) {
        if (claimed.contains(col) || normalized[col].isEmpty) continue;
        final hit = _aliases[field]!.any((a) {
          final na = _normalize(a);
          if (na.length < 2) return normalized[col] == na;
          return normalized[col].contains(na) || na.contains(normalized[col]);
        });
        if (hit) {
          result[field] = col;
          claimed.add(col);
          break;
        }
      }
    }
    return result;
  }

  static Course _parseRow(List<String> row, Map<String, int> map) {
    String cell(String field) {
      final idx = map[field];
      if (idx == null || idx >= row.length) return '';
      return row[idx].trim();
    }

    final name = cell('name');
    if (name.isEmpty) throw const FormatException('课程名称为空');
    final dayOfWeek = parseDayOfWeek(cell('weekday'));

    // 节次：优先合并列「节次」（如 1-2 / 第3-4节），否则开始节+结束节
    int startSection;
    int endSection;
    final combined = cell('sections');
    if (combined.isNotEmpty) {
      final pair = _parseSectionRange(combined);
      startSection = pair.$1;
      endSection = pair.$2;
    } else {
      final s = _parseIntLoose(cell('start'));
      final e = _parseIntLoose(cell('end'));
      if (s == null || s < 1) throw const FormatException('开始节无效');
      if (e == null || e < s) throw const FormatException('结束节无效');
      startSection = s;
      endSection = e;
    }
    if (endSection - startSection > 12) {
      throw const FormatException('节次跨度异常（超过 12 节）');
    }

    final weeksText = cell('weeks');
    final weeks = weeksText.isEmpty
        ? List.generate(20, (i) => i + 1) // 周次缺省按 1-20 周，预览页可改
        : WeekParser.parseWeeks(weeksText);

    final teacher = cell('teacher');
    final location = cell('location');
    final color = _parseColor(cell('color'));

    return Course(
      name: name,
      teacher: teacher.isEmpty ? null : teacher,
      color: color ?? 0xFFC4956A, // 未指定颜色时默认品牌暖木棕
      sessions: [
        CourseSession(
          courseId: 0,
          dayOfWeek: dayOfWeek,
          startSection: startSection,
          sectionCount: endSection - startSection + 1,
          weeks: weeks,
          location: location.isEmpty ? null : location,
        ),
      ],
    );
  }

  /// 「第3-4节」「1~2」「3」→ (起, 止)
  static (int, int) _parseSectionRange(String s) {
    final cleaned = s.replaceAll('第', '').replaceAll('节', '').trim();
    final parts = cleaned
        .split(RegExp(r'[-~～—–－到至]'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (parts.length == 1) {
      final v = _parseIntLoose(parts[0]);
      if (v != null && v >= 1) return (v, v);
    } else if (parts.length == 2) {
      final a = _parseIntLoose(parts[0]);
      final b = _parseIntLoose(parts[1]);
      if (a != null && b != null && a >= 1 && b >= a) return (a, b);
    }
    throw FormatException('节次无效: $s');
  }

  /// 容忍 Excel 数字被 toString 成 "3.0"、带「第/节」的情况
  static int? _parseIntLoose(String s) {
    final cleaned = s.replaceAll('第', '').replaceAll('节', '').trim();
    final direct = int.tryParse(cleaned);
    if (direct != null) return direct;
    final d = double.tryParse(cleaned);
    if (d != null && d == d.roundToDouble()) return d.toInt();
    return null;
  }

  /// 颜色列：#C4956A / 0xFFC4956A / 十进制 int，非法则忽略
  static int? _parseColor(String s) {
    if (s.isEmpty) return null;
    var cleaned = s.trim().replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
    final hex = int.tryParse(cleaned, radix: 16);
    if (hex != null) {
      return hex > 0xFFFFFF ? hex : (0xFF000000 | hex);
    }
    return int.tryParse(s.trim());
  }

  static Future<List<List<String>>> _parseCsv(PlatformFile file) async {
    final bytes = file.bytes ??
        (file.path != null ? File(file.path!).readAsBytesSync() : null);
    if (bytes == null) throw const FormatException('无法读取文件');
    // 兼容 UTF-8（含 BOM）与 GBK（Excel 中文导出常是 GBK）
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = await CharsetConverter.decode('gbk', bytes);
    }
    if (content.startsWith('﻿')) content = content.substring(1);
    return content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.split(','))
        .toList();
  }

  static List<List<String>> _parseXlsx(PlatformFile file) {
    final bytes = file.bytes ??
        (file.path != null ? File(file.path!).readAsBytesSync() : null);
    if (bytes == null) throw const FormatException('无法读取文件');
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.firstOrNull;
    if (sheet == null) return [];
    return sheet.rows
        .map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList())
        .toList();
  }
}
