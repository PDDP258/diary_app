/// jwapp 课表接口 → [Course] 解析
///
/// 输入是 `cxxszhxqkb.do`（学生周课表）返回的 `datas.<表名>.rows`。
/// 每条记录 = 一段「上课安排」，字段已高度结构化，无需任何网格还原。
///
/// 实测（西北农林科技大学，2026-2027-1）字段：
///
/// | 字段 | 含义 | 去向 |
/// |---|---|---|
/// | `KCM` | 课程名 | `Course.name` |
/// | `SKJS` | 教师（可能重复，如「张刚,张刚」） | `Course.teacher` |
/// | `SKXQ` / `SKXQ_DISPLAY` | 星期几（数字 / 「星期三」） | `session.dayOfWeek` |
/// | `KSJC` / `JSJC` | 起始/结束节次 | `session.startSection` / `sectionCount` |
/// | `SKZC` | 周次位图 | `session.weeks` |
/// | `JASMC` / `XXXQMC` | 教室 / 校区 | `session.location` |
/// | `BZ` | 调课备注 | 汇总为提示，不注入课程数据 |
///
/// 三个必须小心的坑（都有测试锁定）：
/// 1. **`SKZC` 位图长度不固定** —— 同一次响应里出现 20 位与 18 位混用，
///    长度取决于该条记录排课时的总周数。按实际长度解析，不要按学期总周数截断。
/// 2. **调课会把同一时段拆成多条** —— 例如「周3 第1-4节」出现 `[1,2,3]` 与
///    `[4]` 两条（第 5 周整体调至第 4 周）。必须按「课程+周几+节次+地点」
///    合并 weeks 并集，否则课表上会画出重叠的格子。
/// 3. **课程标识不能用 `KCH`+`KXH`** —— 同一门课可能有多个课序号
///    （实测 `01S01` 与 `01` 并存）。按「课程名 + 归一化教师」合并。
library;

import '../../../models/course.dart';
import '../../../utils/day_of_week.dart';
import '../course_import_source.dart';
import 'jwapp_models.dart';
import 'jwapp_response.dart';

class JwappCourseParser {
  /// 课表表名实测值；传 null 时由 [JwappResponse.unwrapTable] 自动发现
  static const defaultTableKey = 'cxxszhxqkb';

  /// 解析课表接口响应体
  static JwappParseResult parse(
    String body, {
    String? tableKey = defaultTableKey,
    String sourceName = '教务系统导入',
  }) {
    final rows = JwappResponse.unwrapRows(body, key: tableKey);
    return parseRows(rows, sourceName: sourceName);
  }

  /// 直接解析 rows（便于测试与复用）
  static JwappParseResult parseRows(
    List<Map<String, dynamic>> rows, {
    String sourceName = '教务系统导入',
  }) {
    final issues = <String>[];
    final notices = <String>[];
    final byCourse = <String, _CourseAcc>{};

    var maxSection = 0;
    var rescheduled = 0;
    String? semesterCode;

    for (var i = 0; i < rows.length; i++) {
      final raw = rows[i];

      if (semesterCode == null) {
        final code = _str(raw['XNXQDM']);
        if (code.isNotEmpty) semesterCode = code;
      }

      final row = _parseRow(raw, i, issues, notices);
      if (row == null) continue;

      final endSection = row.startSection + row.sectionCount - 1;
      if (endSection > maxSection) maxSection = endSection;

      final note = _str(raw['BZ']);
      if (note.contains('调至') || note.contains('调课')) rescheduled++;

      final key = '${row.name}|${row.teacher ?? ''}';
      byCourse
          .putIfAbsent(key, () => _CourseAcc(row.name, row.teacher))
          .merge(row);
    }

    if (rescheduled > 0) {
      notices.add('检测到 $rescheduled 处调课，已按教务系统调整后的时间导入');
    }

    final courses = <Course>[];
    for (final acc in byCourse.values) {
      courses.add(acc.toCourse(colorIndex: courses.length));
    }

    return JwappParseResult(
      draft: ImportDraft(
        courses: courses,
        issues: issues,
        sourceName: sourceName,
      ),
      notices: notices,
      semesterCode: semesterCode,
      rawCount: rows.length,
      maxSection: maxSection,
    );
  }

  // ===================== 单条记录 =====================

  static _Row? _parseRow(
    Map<String, dynamic> raw,
    int index,
    List<String> issues,
    List<String> notices,
  ) {
    final label = '第 ${index + 1} 条';

    final name = _str(raw['KCM']);
    if (name.isEmpty) {
      issues.add('$label：缺少课程名（KCM），已跳过');
      return null;
    }

    // 星期：优先数字 SKXQ；**越界**（不只是缺失）时用 SKXQ_DISPLAY（「星期三」）兜底
    var day = _int(raw['SKXQ']);
    if (day == null || day < 1 || day > 7) {
      day = tryParseDayOfWeek(_str(raw['SKXQ_DISPLAY']));
    }
    if (day == null || day < 1 || day > 7) {
      issues.add('$label「$name」：星期无法识别'
          '（SKXQ=${raw['SKXQ']}，显示值="${_str(raw['SKXQ_DISPLAY'])}"），已跳过');
      return null;
    }

    final start = _int(raw['KSJC']);
    if (start == null || start < 1) {
      issues.add('$label「$name」：起始节次无效（KSJC=${raw['KSJC']}），已跳过');
      return null;
    }

    final end = _int(raw['JSJC']);
    var count = 1;
    if (end == null) {
      notices.add('「$name」缺少结束节次，按单节处理');
    } else if (end < start) {
      notices.add('「$name」节次区间异常（$start-$end），按单节处理');
    } else {
      count = end - start + 1;
    }

    final weeks = parseWeekBitmap(_str(raw['SKZC']));
    if (weeks.isEmpty) {
      issues.add(
          '$label「$name」：周次为空（SKZC="${_str(raw['SKZC'])}"），已跳过');
      return null;
    }

    return _Row(
      name: name,
      teacher: normalizeTeacher(raw['SKJS']),
      dayOfWeek: day,
      startSection: start,
      sectionCount: count,
      location: composeLocation(raw),
      weeks: weeks,
    );
  }

  // ===================== 字段级工具（公开以便单测） =====================

  /// 解析 `SKZC` 周次位图：第 i 个字符为 `'1'` 表示第 i+1 周有课。
  ///
  /// 长度按实际内容走 —— 实测同一响应里有 20 位也有 18 位，
  /// 用学期总周数去截断/补齐会得到错的周次。
  static List<int> parseWeekBitmap(String raw) {
    final out = <int>[];
    if (raw.isEmpty) return out;
    for (var i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) == _charOne) out.add(i + 1);
    }
    return out;
  }

  /// 教师串归一化：拆分 → 去空 → 按首次出现去重。
  /// 实测「张刚,张刚」→「张刚」；「王旭辉」→「王旭辉」。
  static String? normalizeTeacher(Object? raw) {
    final s = _str(raw);
    if (s.isEmpty) return null;
    final seen = <String>{};
    final kept = <String>[];
    for (final part in s.split(RegExp(r'[,，、;；/|]+'))) {
      final t = part.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) kept.add(t);
    }
    if (kept.isEmpty) return null;
    return kept.join(',');
  }

  /// 教室 + 校区合成地点，如「南校区 S1608」。
  /// 跨校区走错是最痛的错误，所以校区保留在课前。
  static String? composeLocation(Map<String, dynamic> raw) {
    var room = _str(raw['JASMC']);
    if (room.isEmpty) room = _str(raw['JASDM']);
    var campus = _str(raw['XXXQMC']);
    if (campus.isEmpty) campus = _str(raw['XXXQDM_DISPLAY']);

    if (room.isEmpty && campus.isEmpty) return null;
    if (campus.isEmpty) return room;
    if (room.isEmpty) return campus;
    if (room.contains(campus)) return room;
    return '$campus $room';
  }

  static const _charOne = 0x31; // '1'

  static String _str(Object? value) {
    if (value == null) return '';
    final s = value.toString().trim();
    return s == 'null' ? '' : s;
  }

  static int? _int(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }
}

/// 一条课表记录（已过字段校验）
class _Row {
  final String name;
  final String? teacher;
  final int dayOfWeek;
  final int startSection;
  final int sectionCount;
  final String? location;
  final List<int> weeks;

  const _Row({
    required this.name,
    required this.teacher,
    required this.dayOfWeek,
    required this.startSection,
    required this.sectionCount,
    required this.location,
    required this.weeks,
  });
}

/// 一门课的累积器：同一时段的多条记录合并 weeks
class _CourseAcc {
  final String name;
  final String? teacher;
  final Map<String, _SessionAcc> _sessions = {};

  _CourseAcc(this.name, this.teacher);

  void merge(_Row row) {
    final key = '${row.dayOfWeek}|${row.startSection}|'
        '${row.sectionCount}|${row.location ?? ''}';
    _sessions
        .putIfAbsent(
          key,
          () => _SessionAcc(
            dayOfWeek: row.dayOfWeek,
            startSection: row.startSection,
            sectionCount: row.sectionCount,
            location: row.location,
          ),
        )
        .weeks
        .addAll(row.weeks);
  }

  Course toCourse({required int colorIndex}) => Course(
        name: name,
        teacher: teacher,
        color: Course.presetColors[colorIndex % Course.presetColors.length],
        sessions: _sessions.values.map((s) => s.toSession()).toList(),
      );
}

/// 一个上课时段（周几 + 节次 + 地点）及其周次集合
class _SessionAcc {
  final int dayOfWeek;
  final int startSection;
  final int sectionCount;
  final String? location;
  final Set<int> weeks = {};

  _SessionAcc({
    required this.dayOfWeek,
    required this.startSection,
    required this.sectionCount,
    required this.location,
  });

  CourseSession toSession() => CourseSession(
        courseId: 0,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        sectionCount: sectionCount,
        weeks: weeks.toList()..sort(),
        location: location,
      );
}
