/// 课表单元格文本 → 课程语义
///
/// OCR 拿到的单元格文本长这样（真实课表里五花八门）：
///   "高等数学\n张老师\n教一101\n1-16周"
///   "大学英语(张老师) 语302 1-16周(单)"
///   "线性代数 1-8周\n大学物理 9-16周"      ← 一格两门课
///   "概率论与数理统计 李四 A座203"
///
/// 本模块只做「把一个格的文本拆成 课程名 + 教师 + 地点 + 周次」这件事，
/// 星期几与节次由 [ScheduleGridParser] 从网格位置推出来。
///
/// 立场：启发式不可能 100% 对，所以预览确认页是产品必需品——
/// 这里的目标是「常见写法都能拆对」，拆不动的宁可不拆（保留在课程名里），
/// 也不要错拆成两门课。
library;

import '../../../utils/week_parser.dart';

/// 一个课程格拆出的一门课
class ParsedCellCourse {
  /// 课程名（一定非空，兜底为「未识别课程」）
  final String name;

  final String? teacher;
  final String? location;

  /// 周次；null 表示格子里没写周次，调用方按学期总周数兜底
  final List<int>? weeks;

  /// 原始文本，供预览页「查看原文」
  final String sourceText;

  const ParsedCellCourse({
    required this.name,
    this.teacher,
    this.location,
    this.weeks,
    required this.sourceText,
  });

  @override
  String toString() =>
      'ParsedCellCourse($name / ${teacher ?? '-'} / ${location ?? '-'} / '
      '${weeks?.length ?? 0}周)';
}

class CourseCellParser {
  /// 未识别出课程名时的兜底名
  static const fallbackName = '未识别课程';

  /// 把一个单元格文本拆成一门或多门课
  static List<ParsedCellCourse> parse(String rawText, {int totalWeeks = 20}) {
    final text = _normalize(rawText);
    if (text.isEmpty) return const [];

    // 1) 先摘出括号里的「周次 / 教师 / 地点」，剩下的括号内容留作课程名的一部分
    final extracted = _extractBrackets(text, totalWeeks);

    // 2) 按行 -> 词 切分，边切边做块分组（一格多课在这里分开）
    final blocks = _splitIntoBlocks(extracted.cleaned, extracted.weeks, totalWeeks);

    // 3) 每个块内部分类出行
    final out = <ParsedCellCourse>[];
    for (final b in blocks) {
      final course = _buildCourse(
        b,
        fallbackTeacher: extracted.teacher,
        fallbackLocation: extracted.location,
        fallbackWeeks: extracted.weeks,
        sourceText: rawText.trim(),
        totalWeeks: totalWeeks,
      );
      if (course != null) out.add(course);
    }
    return out;
  }

  // ==================== 归一化 ====================

  /// 全角 → 半角，统一换行，去零宽字符
  static String _normalize(String s) {
    final buf = StringBuffer();
    for (final r in s.runes) {
      if (r == 0x3000) {
        buf.write(' ');
      } else if (r >= 0xFF01 && r <= 0xFF5E) {
        buf.writeCharCode(r - 0xFEE0);
      } else if (r == 0x200B || r == 0xFEFF || r == 0x00A0) {
        // 零宽/不换行空格：丢掉
      } else {
        buf.writeCharCode(r);
      }
    }
    return buf
        .toString()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }

  /// 括号内容摘取结果
  static _BracketExtract _extractBrackets(String text, int totalWeeks) {
    final weeks = <int>[];
    String? teacher;
    String? location;

    final cleaned = text.replaceAllMapped(
      RegExp(r'[\(\[【]([^\)\]】]{1,20})[\)\]】]'),
      (m) {
        final inner = m.group(1)!.trim();
        if (_isWeekish(inner)) {
          final w = _tryParseWeeks(inner, totalWeeks);
          if (w != null) {
            weeks.addAll(w);
            return ' ';
          }
        }
        if (teacher == null && _isExplicitTeacher(inner)) {
          teacher = inner;
          return ' ';
        }
        if (location == null && _isLocation(inner)) {
          location = inner;
          return ' ';
        }
        return m.group(0)!; // 不是结构化信息，原样保留（如「高等数学(上)」）
      },
    );

    return _BracketExtract(
      cleaned: cleaned,
      weeks: weeks.isEmpty ? null : _dedup(weeks),
      teacher: teacher,
      location: location,
    );
  }

  // ==================== 分块（一格多课） ====================

  static List<_Block> _splitIntoBlocks(
      String cleaned, List<int>? bracketWeeks, int totalWeeks) {
    final blocks = <_Block>[];
    var current = _Block();

    /// 自上一个周次标记以来累积的词。遇到「同一块里的第二个周次」时，
    /// 这批词属于下一门课——这正是「高等数学 1-8周\n大学物理 9-16周」的切分点。
    final pending = <String>[];

    void commitPending() {
      current.lines.addAll(pending);
      pending.clear();
    }

    for (final rawLine in cleaned.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      for (final token in line.split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;

        if (_isWeekish(token)) {
          final w = _tryParseWeeks(token, totalWeeks);
          if (w != null) {
            if (current.weeks != null && (current.hasName || pending.isNotEmpty)) {
              // 第二门课：当前块收尾，pending 里的词归新块
              if (current.hasContent) blocks.add(current);
              current = _Block()..lines.addAll(pending);
            } else {
              commitPending();
            }
            pending.clear();
            current.weeks = w;
            current.hasContent = true;
            continue;
          }
        }

        if (_isSectionish(token)) continue; // 节次由网格位置给出，文本里丢弃
        pending.add(token);
        current.hasContent = true;
      }
    }

    commitPending();
    if (current.hasContent) blocks.add(current);

    // 兜底：整格只有括号里的周次、没有课名
    if (blocks.isEmpty && bracketWeeks != null) {
      blocks.add(_Block()..hasContent = true);
    }

    // 后处理：没有课名的块并回上一个块（「1-8周\n10-16周」是同门课的两个区间）
    final merged = <_Block>[];
    for (final b in blocks) {
      if (!b.hasName && merged.isNotEmpty) {
        final prev = merged.last;
        if (b.weeks != null) {
          prev.weeks = _dedup([...?prev.weeks, ...b.weeks!]);
        }
        prev.lines.addAll(b.lines);
        continue;
      }
      merged.add(b);
    }
    return merged;
  }

  // ==================== 块 → 课程 ====================

  static ParsedCellCourse? _buildCourse(
    _Block block, {
    String? fallbackTeacher,
    String? fallbackLocation,
    List<int>? fallbackWeeks,
    required String sourceText,
    required int totalWeeks,
  }) {
    final tokens = block.lines;

    // 1) 地点：显式关键词优先
    String? location = fallbackLocation;
    final rest = <String>[];
    for (final t in tokens) {
      if (location == null && _isLocation(t)) {
        location = t;
        continue;
      }
      rest.add(t);
    }

    // 2) 教师：带后缀的（张老师/李教授）优先，否则取「课名之后剩下的纯中文短词」
    String? teacher = fallbackTeacher;
    if (teacher == null) {
      final explicit = rest.indexWhere(_isExplicitTeacher);
      if (explicit >= 0) {
        teacher = rest.removeAt(explicit);
      } else if (rest.length >= 2) {
        final last = rest.last;
        if (_isLikelyName(last) && rest.first.length >= 2) {
          teacher = rest.removeLast();
        }
      }
    }

    // 3) 剩下的就是课程名
    var name = rest.join(' ').trim();
    if (name.isEmpty) {
      // 名字与地点/教师都分不开时，用原文去掉周次后的内容兜底
      name = _stripWeekText(block.lines.join(' ')).trim();
    }
    if (name.isEmpty) return null;
    if (name.length > 40) name = name.substring(0, 40);

    final weeks = block.weeks ?? fallbackWeeks;
    return ParsedCellCourse(
      name: name,
      teacher: teacher,
      location: location,
      weeks: weeks == null
          ? null
          : (weeks.isEmpty ? null : _dedup(weeks)),
      sourceText: sourceText,
    );
  }

  // ==================== 判定谓词 ====================

  /// 是否「周次」表达：必须出现 周/单/双/全周 之类标记，
  /// 且去掉标记后只剩数字与分隔符——这样 "A302"、"教一101" 不会被误判。
  static bool _isWeekish(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (RegExp(r'^(全周|全部|所有周|每周|everyweek|all)$', caseSensitive: false)
        .hasMatch(t.replaceAll(' ', ''))) {
      return true;
    }
    final hasMarker =
        t.contains('周') || t.contains('单') || t.contains('双');
    if (!hasMarker) return false;
    final core = t
        .replaceAll(RegExp(r'[周次单双第]'), '')
        .replaceAll(RegExp(r'[\(\)\[\]（）【】\s]'), '');
    if (core.isEmpty) return false;
    return RegExp(r'^[0-9,，、\-~～—–－到至]+$').hasMatch(core);
  }

  /// "第1-2节" / "1,2节" 这类：位置信息已由网格给出，文本里可丢弃
  static bool _isSectionish(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (!t.contains('节')) return false;
    final core = t.replaceAll(RegExp(r'[第节小课次\s]'), '');
    if (core.isEmpty) return false;
    return RegExp(r'^[0-9,，、\-~～—–－到至]+$').hasMatch(core);
  }

  static bool _isExplicitTeacher(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t.length > 12) return false;
    return RegExp(r'(老师|教师|教授|讲师|助教|导师|博士|先生)$').hasMatch(t);
  }

  /// 2-4 个纯汉字，且不像地点/周次——当作人名
  static bool _isLikelyName(String raw) {
    final t = raw.trim();
    if (!RegExp(r'^[\u4e00-\u9fa5]{2,4}$').hasMatch(t)) return false;
    if (_isLocation(t) || _isWeekish(t)) return false;
    // 姓名里不该出现这些字
    return !RegExp(r'[楼室馆区栋阶楼院系课专业学期班]').hasMatch(t);
  }

  static bool _isLocation(String raw) {
    var t = raw.trim();
    if (t.isEmpty || t.length > 20) return false;
    t = t.replaceAll(RegExp(r'\s+'), '');

    // 显式地点关键词
    if (RegExp(r'(楼|教室|机房|实验室|实验楼|报告厅|礼堂|体育馆|操场|场地|'
            r'校区|阶梯|多媒体|机房|中心|广场|游泳馆|球馆|苑|座|号)')
        .hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^[教实]?\d').hasMatch(t) && RegExp(r'\d').hasMatch(t)) {
      // 「教101」「实302」
      if (RegExp(r'^[教实]?[A-Za-z]?\d{2,4}$').hasMatch(t)) return true;
    }
    // 「A101」「B2-305」「语302」「东A-201」
    if (RegExp(r'^[A-Za-z\u4e00-\u9fa5]{0,2}[A-Za-z]?[-]?\d{2,4}([-]\d{1,4})?[A-Za-z]?$')
        .hasMatch(t)) {
      // 纯数字（如「1」）在这里也会命中，但长度 >= 2 的数字串更像房间号
      return t.replaceAll(RegExp(r'[^0-9]'), '').length >= 2;
    }
    return false;
  }

  // ==================== 周次解析 ====================

  static List<int>? _tryParseWeeks(String s, int totalWeeks) {
    try {
      final w = WeekParser.parseWeeks(s, totalWeeks: totalWeeks);
      return w.isEmpty ? null : w;
    } catch (_) {
      return null;
    }
  }

  static String _stripWeekText(String s) =>
      s.replaceAll(RegExp(r'[0-9][0-9,，、\-~～—–－到至]*\s*[单双]?\s*周次?'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ');

  static List<int> _dedup(Iterable<int> xs) {
    final set = xs.where((w) => w >= 1).toSet().toList()..sort();
    return set;
  }
}

/// 一个课程块（整格课程里的一门）
class _Block {
  final List<String> lines = [];
  List<int>? weeks;
  bool hasContent = false;

  /// 是否已经有「课名」性质的内容（非周次行）
  bool get hasName => lines.any((l) => RegExp(r'[\u4e00-\u9fa5A-Za-z]').hasMatch(l));
}

class _BracketExtract {
  final String cleaned;
  final List<int>? weeks;
  final String? teacher;
  final String? location;

  const _BracketExtract({
    required this.cleaned,
    this.weeks,
    this.teacher,
    this.location,
  });
}
