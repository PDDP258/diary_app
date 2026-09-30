/// 周次解析与学期周计算
///
/// 周次字符串解析只发生在导入边界（手动输入/模板/教务/OCR），
/// 内部统一使用 List<int>。支持国内教务常见写法：
///   "1-16周" "1,3,5-15周" "1-15周(单)" "2-16双周" "1-8,10-16周"
///   "1~16" "1—16" "1到16周" "第3-5周" "单周1-15" "全周" 全角字符等
library;

class WeekParser {
  /// 区间连接符：- ~ ～ — – － 到 至
  static final _rangePattern = RegExp(r'[-~～—–－到至]');

  /// 片段分隔符：中英文逗号、顿号、分号、竖线、斜杠、空白
  static final _splitPattern = RegExp(r'[,，、;；|/\s]+');

  /// 解析周次字符串为排序去重后的 List<int>。
  /// [totalWeeks] 仅在出现「全周/全部」等写法时用作上限，默认 20。
  /// 无法解析任何片段时抛出 [FormatException]。
  static List<int> parseWeeks(String input, {int totalWeeks = 20}) {
    var s = input.trim();
    if (s.isEmpty) throw const FormatException('周次为空');

    // 全周写法
    if (RegExp(r'^(全周|全部|所有周?|every\s*week|all)$', caseSensitive: false)
        .hasMatch(s)) {
      return List.generate(totalWeeks, (i) => i + 1);
    }

    // 全角转半角、去「第」「周」「周次」与空白
    s = s
        .replaceAll('，', ',')
        .replaceAll('－', '-')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('～', '~')
        .replaceAll('第', '')
        .replaceAll('周次', '')
        .replaceAll('周', '')
        .replaceAll(' ', '');

    // 单双周标记（前缀/后缀、括号有无均可，兼容奇偶写法）
    var onlyOdd = false;
    var onlyEven = false;
    final oddMark =
        RegExp(r'[\(（\[\{]?(单周?|单数|奇数周?|odd)[\)）\]\}]?', caseSensitive: false);
    final evenMark =
        RegExp(r'[\(（\[\{]?(双周?|双数|偶数周?|even)[\)）\]\}]?', caseSensitive: false);
    if (oddMark.hasMatch(s)) {
      onlyOdd = true;
      s = s.replaceAll(oddMark, '');
    } else if (evenMark.hasMatch(s)) {
      onlyEven = true;
      s = s.replaceAll(evenMark, '');
    }

    final weeks = <int>{};
    for (final part in s.split(_splitPattern)) {
      if (part.isEmpty) continue;
      final bounds = part.split(_rangePattern).where((e) => e.isNotEmpty).toList();
      if (bounds.length == 2) {
        final start = _parseInt(bounds[0]);
        final end = _parseInt(bounds[1]);
        if (start == null || end == null || start > end || start < 1) {
          throw FormatException('无效区间: $part');
        }
        if (end - start > 60) throw FormatException('区间过大: $part');
        for (var w = start; w <= end; w++) {
          weeks.add(w);
        }
      } else if (bounds.length == 1) {
        final w = _parseInt(bounds[0]);
        if (w == null || w < 1) throw FormatException('无效周次: $part');
        weeks.add(w);
      } else {
        throw FormatException('无效区间: $part');
      }
    }
    if (weeks.isEmpty) throw const FormatException('未解析出任何周次');

    var list = weeks.toList()..sort();
    if (onlyOdd) list = list.where((w) => w.isOdd).toList();
    if (onlyEven) list = list.where((w) => w.isEven).toList();
    if (list.isEmpty) throw const FormatException('单双周过滤后无剩余周次');
    return list;
  }

  /// 容忍 Excel 数字被 toString 成 "3.0" 的情况
  static int? _parseInt(String s) {
    final direct = int.tryParse(s);
    if (direct != null) return direct;
    final d = double.tryParse(s);
    if (d != null && d == d.roundToDouble()) return d.toInt();
    return null;
  }

  /// List<int> 回格式化为紧凑字符串，如 [1,2,3,5,7,9] -> "1-3,5,7,9"
  static String formatWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '';
    final sorted = weeks.toSet().toList()..sort();
    final parts = <String>[];
    var start = sorted.first;
    var prev = start;
    for (var i = 1; i <= sorted.length; i++) {
      final cur = i < sorted.length ? sorted[i] : null;
      if (cur != null && cur == prev + 1) {
        prev = cur;
        continue;
      }
      parts.add(start == prev ? '$start' : '$start-$prev');
      if (cur != null) {
        start = cur;
        prev = cur;
      }
    }
    return parts.join(',');
  }

  /// 计算指定日期是第几个教学周（基于开学日，开学日为第 1 周周一）。
  /// 返回 null 表示在学期范围外（开学前或超过总周数）。
  static int? currentWeek({
    required DateTime semesterStart,
    required int totalWeeks,
    DateTime? date,
  }) {
    final d = date ?? DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final start = DateTime(
        semesterStart.year, semesterStart.month, semesterStart.day);
    final diffDays = day.difference(start).inDays;
    if (diffDays < 0) return null;
    final week = diffDays ~/ 7 + 1;
    return week > totalWeeks ? null : week;
  }
}
