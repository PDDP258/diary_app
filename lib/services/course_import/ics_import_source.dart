import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../models/course.dart';
import '../../utils/week_parser.dart';
import 'course_import_source.dart';

/// ICS（iCalendar）导入（T5）
///
/// 解析学校导出的 .ics 文件：每个 VEVENT = 一次上课安排，
/// RRULE:FREQ=WEEKLY 给出周次重复；UNTIL + 开学日期换算出周次集合。
///
/// 支持的典型形态：
///   BEGIN:VEVENT
///   SUMMARY:高等数学@教一101
///   DTSTART:20260907T080000
///   DTEND:20260907T094000
///   RRULE:FREQ=WEEKLY;UNTIL=20270111T000000
///   LOCATION:教一101
///   DESCRIPTION:张老师
///   END:VEVENT
class IcsImportSource extends CourseImportSource {
  @override
  String get name => 'ICS 日历文件';

  @override
  Future<ImportDraft?> collect() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes ??
        (file.path != null ? File(file.path!).readAsBytesSync() : null);
    if (bytes == null) throw const FormatException('无法读取文件');
    final content = utf8.decode(bytes, allowMalformed: true);
    return parse(content);
  }

  /// 解析 ICS 文本（独立成方法便于测试）
  ///
  /// [semesterStart] 开学日（第 1 周周一）；[sectionOf] 由开始时刻推断节次。
  /// 两者通常来自当前学期配置；缺省时按 DTSTART 星期几 + 固定 8 节推断。
  static ImportDraft parse(
    String content, {
    DateTime? semesterStart,
    int Function(DateTime start, DateTime end)? sectionOf,
    int totalWeeks = 20,
  }) {
    final issues = <String>[];
    final courses = <Course>[];

    // 展开折行（RFC 5545：续行以空格/制表符开头）
    final unfolded = content
        .replaceAll(RegExp(r'\r\n[ \t]'), '')
        .replaceAll(RegExp(r'\n[ \t]'), '');

    final events = RegExp(r'BEGIN:VEVENT(.*?)END:VEVENT', dotAll: true)
        .allMatches(unfolded);

    var index = 0;
    for (final match in events) {
      index++;
      try {
        final course = _parseEvent(
          match.group(1)!,
          semesterStart: semesterStart,
          sectionOf: sectionOf,
          totalWeeks: totalWeeks,
        );
        if (course != null) courses.add(course);
      } on FormatException catch (e) {
        issues.add('第 $index 个事件：${e.message}');
      }
    }

    return ImportDraft(
      courses: mergeCoursesByName(courses),
      issues: issues,
      sourceName: 'ICS 日历文件',
    );
  }

  static Course? _parseEvent(
    String body, {
    DateTime? semesterStart,
    int Function(DateTime start, DateTime end)? sectionOf,
    required int totalWeeks,
  }) {
    final props = <String, String>{};
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).split(';').first.toUpperCase();
      props[key] = line.substring(colon + 1).trim();
    }

    final summary = props['SUMMARY'];
    if (summary == null || summary.isEmpty) {
      throw const FormatException('缺少课程名（SUMMARY）');
    }
    final dtStartText = props['DTSTART'];
    if (dtStartText == null) throw const FormatException('缺少开始时间');
    final dtStart = _parseDateTime(dtStartText);
    final dtEnd = props['DTEND'] != null
        ? _parseDateTime(props['DTEND']!)
        : dtStart.add(const Duration(minutes: 45));

    // 周次：RRULE UNTIL 换算，或 COUNT
    List<int> weeks;
    final rrule = _propWithParams(body, 'RRULE');
    if (rrule != null && rrule.contains('FREQ=WEEKLY')) {
      weeks = _weeksFromRRule(rrule, dtStart,
          semesterStart ?? _mondayOf(dtStart), totalWeeks);
    } else {
      // 无重复规则：只算首周
      weeks = [
        WeekParser.currentWeek(
                semesterStart: semesterStart ?? _mondayOf(dtStart),
                totalWeeks: totalWeeks,
                date: dtStart) ??
            1
      ];
    }

    // 节次推断
    int startSection = 1, sectionCount = 1;
    if (sectionOf != null) {
      startSection = sectionOf(dtStart, dtEnd);
    } else {
      startSection = _guessSection(dtStart);
    }
    final minutes = dtEnd.difference(dtStart).inMinutes;
    if (minutes > 60) sectionCount = 2;
    if (minutes > 120) sectionCount = 3;

    // SUMMARY 常见格式「课程名@地点」
    var name = summary;
    var location = props['LOCATION'];
    if (summary.contains('@')) {
      final parts = summary.split('@');
      name = parts.first.trim();
      location ??= parts.length > 1 ? parts.sublist(1).join('@').trim() : null;
    }

    return Course(
      name: name,
      teacher: props['DESCRIPTION'],
      sessions: [
        CourseSession(
          courseId: 0,
          dayOfWeek: dtStart.weekday,
          startSection: startSection,
          sectionCount: sectionCount,
          weeks: weeks,
          location: location,
        ),
      ],
    );
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  /// 无节次表时的粗略推断：08 点起每 50 分钟一节
  static int _guessSection(DateTime dt) {
    final minutes = dt.hour * 60 + dt.minute;
    if (minutes < 9 * 60) return 1;
    if (minutes < 11 * 60) return 3;
    if (minutes < 14 * 60) return 5;
    if (minutes < 16 * 60) return 6;
    return 7;
  }

  /// 提取带参数的完整属性行值（如 RRULE:FREQ=WEEKLY;UNTIL=...）
  static String? _propWithParams(String body, String name) {
    for (final line in body.split(RegExp(r'\r?\n'))) {
      if (line.toUpperCase().startsWith('$name:') ||
          line.toUpperCase().startsWith('$name;')) {
        final colon = line.indexOf(':');
        return colon > 0 ? line.substring(colon + 1).trim() : null;
      }
    }
    return null;
  }

  static List<int> _weeksFromRRule(
      String rrule, DateTime dtStart, DateTime semesterStart, int totalWeeks) {
    final firstWeek = WeekParser.currentWeek(
            semesterStart: semesterStart, totalWeeks: totalWeeks, date: dtStart) ??
        1;

    final untilMatch = RegExp(r'UNTIL=(\d{8})').firstMatch(rrule);
    final countMatch = RegExp(r'COUNT=(\d+)').firstMatch(rrule);
    final intervalMatch = RegExp(r'INTERVAL=(\d+)').firstMatch(rrule);
    final interval = intervalMatch != null ? int.parse(intervalMatch.group(1)!) : 1;

    int lastWeek;
    if (untilMatch != null) {
      final u = untilMatch.group(1)!;
      final until = DateTime(int.parse(u.substring(0, 4)),
          int.parse(u.substring(4, 6)), int.parse(u.substring(6, 8)));
      lastWeek = WeekParser.currentWeek(
              semesterStart: semesterStart, totalWeeks: totalWeeks, date: until) ??
          totalWeeks;
    } else if (countMatch != null) {
      lastWeek = firstWeek + (int.parse(countMatch.group(1)!) - 1) * interval;
    } else {
      lastWeek = totalWeeks;
    }
    lastWeek = lastWeek.clamp(firstWeek, totalWeeks);

    return [
      for (var w = firstWeek; w <= lastWeek; w += interval) w,
    ];
  }

  static DateTime _parseDateTime(String text) {
    // 支持 20260907T080000 与 20260907T080000Z
    final m = RegExp(r'(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})').firstMatch(text);
    if (m == null) throw FormatException('时间格式无效: $text');
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
  }
}
