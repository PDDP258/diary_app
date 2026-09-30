/// jwapp 学期配置解析（`cxjcs.do`）
///
/// 这个接口**一次返回全部学期**，每条给出开学日与总周数：
///
/// ```json
/// { "XN": "2026-2027", "XQ": "1", "XQKSRQ": "2026-09-07 00:00:00",
///   "ZZC": 20, "PX": 9921, "SFSY": 1 }
/// ```
///
/// 这正好能自动填本地 [SemesterConfig]，省掉用户手填开学日这一步。
///
/// ⚠️ **别用 `PX` 判定当前学期** —— 实测存在 `PX` 为 null 的行，详见 [pickCurrent]。
library;

import 'jwapp_models.dart';
import 'jwapp_response.dart';

class JwappSemesterParser {
  /// 学期配置表名实测值
  static const defaultTableKey = 'cxjcs';

  /// 解析全部学期（按 `code` 去重，保留首条）
  static List<JwappSemester> parseAll(
    String body, {
    String? tableKey = defaultTableKey,
  }) {
    final rows = JwappResponse.unwrapRows(body, key: tableKey);
    final seen = <String>{};
    final out = <JwappSemester>[];

    for (final row in rows) {
      final sem = _parse(row);
      if (sem == null) continue;
      if (seen.add(sem.code)) out.add(sem);
    }
    return out;
  }

  /// 当前学期
  ///
  /// **不能用 `PX` 单独判定**。实测 `cxjcs.do` 里存在 `PX` 为 null 的学期
  /// （2025-2026-3，暑假小学期，`SFSY` 同样是 1「在用」）。把 null 当作 0
  /// 参与排序会让它排到最前面、被误判成当前学期，后果是：
  /// 课表按 `XNXQDM=2025-2026-3` 查询 → **一门课都查不到**，
  /// 学期配置还会被写成那条的开学日与总周数（两个症状同一个根因）。
  ///
  /// 改为按数据本身判定 —— 开学日与总周数就在行里，比任何排序字段都直接：
  ///
  /// 1. 今天落在 `[开学日, 开学日 + 总周数×7)` 内的学期，取开学日最晚的；
  /// 2. 否则取已开学且开学日最晚的（学期之间的假期也能选对刚结束那学期）；
  /// 3. 否则取最早开学的（开学前就已录入新学期的情况）；
  /// 4. 日期都不可用时才退回 `PX` 排序（null 视为最旧，排最后）。
  ///
  /// [now] 供测试注入，默认取系统当天。
  static JwappSemester? pickCurrent(List<JwappSemester> all, {DateTime? now}) {
    if (all.isEmpty) return null;
    final today = _dayOnly(now ?? DateTime.now());

    final dated = <JwappSemester>[];
    final starts = <DateTime>[];
    for (final s in all) {
      final d = _parseDate(s.startDate);
      if (d == null) continue;
      dated.add(s);
      starts.add(d);
    }

    if (dated.isNotEmpty) {
      // 1. 落在学期区间内 —— 取开学日最晚的一个
      var best = -1;
      for (var i = 0; i < dated.length; i++) {
        final start = starts[i];
        final end = start.add(Duration(days: dated[i].totalWeeks * 7));
        if (!today.isBefore(start) && today.isBefore(end)) {
          if (best < 0 || start.isAfter(starts[best])) best = i;
        }
      }
      if (best >= 0) return dated[best];

      // 2. 已开学 —— 取最近开学的
      best = -1;
      for (var i = 0; i < dated.length; i++) {
        if (!starts[i].isAfter(today)) {
          if (best < 0 || starts[i].isAfter(starts[best])) best = i;
        }
      }
      if (best >= 0) return dated[best];

      // 3. 全都还没开学 —— 取最早开学的
      best = 0;
      for (var i = 1; i < dated.length; i++) {
        if (starts[i].isBefore(starts[best])) best = i;
      }
      return dated[best];
    }

    // 4. 兜底：按 PX 排序，越小越新，null 排最后
    final pool = List<JwappSemester>.from(all);
    pool.sort((a, b) => _order(a).compareTo(_order(b)));
    return pool.first;
  }

  /// 按学期编码（`2026-2027-1`，即 `XNXQDM`）查找
  static JwappSemester? findByCode(List<JwappSemester> all, String code) {
    if (code.isEmpty) return null;
    for (final s in all) {
      if (s.code == code) return s;
    }
    return null;
  }

  static JwappSemester? _parse(Map<String, dynamic> raw) {
    final year = _str(raw['XN']);
    final term = _str(raw['XQ']);
    final start = _dateOnly(_str(raw['XQKSRQ']));
    if (year.isEmpty || term.isEmpty || start.isEmpty) return null;

    final totalWeeks = _int(raw['ZZC']);
    if (totalWeeks == null || totalWeeks < 1) return null;

    return JwappSemester(
      academicYear: year,
      term: term,
      startDate: start,
      totalWeeks: totalWeeks,
      sortOrder: _int(raw['PX']),
      inUse: (_int(raw['SFSY']) ?? 0) != 0,
    );
  }

  /// `"2026-09-07 00:00:00"` → `"2026-09-07"`
  static String _dateOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final space = s.indexOf(' ');
    final head = space > 0 ? s.substring(0, space) : s;
    // 只接受 yyyy-MM-dd 形态，避免把异常值写进学期配置
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(head) ? head : '';
  }

  static DateTime? _parseDate(String ymd) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  static DateTime _dayOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  /// PX 排序键：越小越新；null 视为最旧（排最后）
  static int _order(JwappSemester s) => s.sortOrder ?? 0x7fffffff;

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
