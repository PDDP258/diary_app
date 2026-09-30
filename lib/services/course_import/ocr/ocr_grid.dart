/// 课表网格还原：把 OCR 的「带合并信息的单元格集合」还原成二维网格，
/// 再定位星期表头行与节次列，输出每个课程格对应的 (星期几, 节次区间)。
///
/// 为什么必须做这一步：腾讯云只给「单元格矩形 + 文本」，一门课占 2-3 节
/// 是靠 rowSpan 表达的，必须展开成网格才能知道它落在哪几节；而「星期几」
/// 只能从表头行的列位置推出来。
library;

import '../../../utils/day_of_week.dart';
import 'ocr_models.dart';

/// 展开后的二维网格。合并区域覆盖到的每个位置都填同一文本。
class OcrGrid {
  final int rows;
  final int cols;

  /// [text[r][c]，空为 null
  final List<List<String?>> text;

  /// 坐标已平移到 0 起的原始单元格
  final List<OcrCell> cells;

  final int rowOffset;
  final int colOffset;

  const OcrGrid({
    required this.rows,
    required this.cols,
    required this.text,
    required this.cells,
    required this.rowOffset,
    required this.colOffset,
  });

  bool get isEmpty => rows == 0 || cols == 0;

  String? at(int r, int c) {
    if (r < 0 || r >= rows || c < 0 || c >= cols) return null;
    return text[r][c];
  }

  /// 由一张表构建网格。坐标统一平移到 0 起（兼容 0 基与 1 基返回）。
  factory OcrGrid.fromTable(OcrTable table) {
    if (table.cells.isEmpty) {
      return const OcrGrid(
          rows: 0, cols: 0, text: [], cells: [], rowOffset: 0, colOffset: 0);
    }

    var minRow = table.cells.first.row;
    var minCol = table.cells.first.col;
    var maxRowEnd = 0;
    var maxColEnd = 0;
    for (final c in table.cells) {
      if (c.row < minRow) minRow = c.row;
      if (c.col < minCol) minCol = c.col;
      if (c.rowEnd > maxRowEnd) maxRowEnd = c.rowEnd;
      if (c.colEnd > maxColEnd) maxColEnd = c.colEnd;
    }

    final rows = maxRowEnd - minRow;
    final cols = maxColEnd - minCol;
    final text = List.generate(rows, (_) => List<String?>.filled(cols, null));

    final shifted = <OcrCell>[];
    for (final c in table.cells) {
      final r = c.row - minRow;
      final col = c.col - minCol;
      shifted.add(OcrCell(
        row: r,
        col: col,
        rowSpan: c.rowSpan,
        colSpan: c.colSpan,
        text: c.text,
        confidence: c.confidence,
      ));
      for (var i = r; i < r + c.rowSpan && i < rows; i++) {
        for (var j = col; j < col + c.colSpan && j < cols; j++) {
          // 合并区域的每个覆盖位置都可见同一文本（后面的单元格不覆盖已有的）
          text[i][j] ??= c.text;
        }
      }
    }

    return OcrGrid(
      rows: rows,
      cols: cols,
      text: text,
      cells: shifted,
      rowOffset: minRow,
      colOffset: minCol,
    );
  }
}

/// 网格行对应的节次区间
class SectionSlot {
  final int start;
  final int end;
  const SectionSlot(this.start, this.end);

  @override
  String toString() => start == end ? '$start' : '$start-$end';
}

/// 表头与节次结构
class ScheduleHeader {
  /// 星期表头所在的网格行，-1 表示没找到
  final int dayHeaderRow;

  /// 网格列 -> 星期几（1..7）
  final Map<int, int> dayOfColumn;

  /// 节次列，-1 表示没找到（回退为第 0 列）
  final int sectionColumn;

  /// 每个网格行的节次区间（长度 = 网格行数，仅课程区有意义）
  final List<SectionSlot?> rowSlots;

  /// 课程区起始行
  final int bodyTopRow;

  const ScheduleHeader({
    required this.dayHeaderRow,
    required this.dayOfColumn,
    required this.sectionColumn,
    required this.rowSlots,
    required this.bodyTopRow,
  });

  bool get dayDetected => dayHeaderRow >= 0 && dayOfColumn.isNotEmpty;
}

/// 从网格中抽取出的一个课程格
class CourseGridCell {
  final String text;

  /// 星期几，1..7
  final int dayOfWeek;

  final int startSection;
  final int endSection;

  /// 该格覆盖的网格行数（用于判断是否连堂）
  final int rowCount;

  /// 该格覆盖的网格列数（>1 说明横向跨了多天，通常是识别噪声）
  final int colCount;

  const CourseGridCell({
    required this.text,
    required this.dayOfWeek,
    required this.startSection,
    required this.endSection,
    this.rowCount = 1,
    this.colCount = 1,
  });
}

/// 网格解析结果
class ScheduleGridResult {
  final List<CourseGridCell> courses;
  final ScheduleHeader header;
  final List<String> issues;

  const ScheduleGridResult({
    required this.courses,
    required this.header,
    required this.issues,
  });
}

/// 网格 → 课程格
class ScheduleGridParser {
  /// 表头行里至少要有这么多个星期标签才算识别成功
  static const minDayLabels = 3;

  static ScheduleGridResult parse(OcrGrid grid) {
    final issues = <String>[];
    final header = detectHeader(grid);

    if (!header.dayDetected) {
      throw const OcrException(
        '没在图片里找到「星期」表头行。请把课表截得更完整（保留顶部星期行）后重试',
        code: 'NO_DAY_HEADER',
      );
    }
    if (header.dayHeaderRow + 1 >= grid.rows) {
      throw const OcrException('图片里只有表头，没有课程内容', code: 'EMPTY_BODY');
    }
    if (header.sectionColumn < 0) {
      issues.add('没识别到节次列，已按行顺序推断节次');
    }

    final courses = <CourseGridCell>[];
    final sectionCol = header.sectionColumn < 0 ? 0 : header.sectionColumn;

    for (final cell in grid.cells) {
      if (cell.row < header.bodyTopRow) continue;
      if (cell.col == sectionCol) continue;
      if (cell.text.trim().isEmpty) continue;

      // 定位星期：取该格覆盖到列中最靠左的已知星期列
      int? day;
      var spanCols = 0;
      for (var c = cell.col; c < cell.colEnd; c++) {
        final d = header.dayOfColumn[c];
        if (d != null) {
          day ??= d;
          spanCols++;
        }
      }
      if (day == null) continue; // 落在星期区之外（如备注列）

      final rows = _boxRows(header, cell);
      if (rows.isEmpty) continue;

      var start = rows.first.start;
      var end = rows.first.end;
      for (final s in rows) {
        if (s.start < start) start = s.start;
        if (s.end > end) end = s.end;
      }
      // 只占一行的课程格就是单节：即使节次标签是「1-2节」的合并格也按单节处理
      if (rows.length == 1) end = start;

      courses.add(CourseGridCell(
        text: cell.text,
        dayOfWeek: day,
        startSection: start,
        endSection: end,
        rowCount: rows.length,
        colCount: spanCols,
      ));
    }

    if (courses.isEmpty) {
      throw const OcrException(
        '表头认出来了，但课程格里没有可用文本。请换一张分辨率更高、文字更清晰的课表图',
        code: 'NO_COURSE_CELL',
      );
    }

    final wide =
        courses.where((c) => c.colCount > 1).toList();
    if (wide.isNotEmpty) {
      issues.add('有 ${wide.length} 个课程格横跨了多天，已按最左边那天归属，请在预览页核对');
    }

    return ScheduleGridResult(
      courses: courses,
      header: header,
      issues: issues,
    );
  }

  static List<SectionSlot> _boxRows(ScheduleHeader header, OcrCell cell) {
    final out = <SectionSlot>[];
    for (var r = cell.row; r < cell.rowEnd; r++) {
      if (r < 0 || r >= header.rowSlots.length) continue;
      final slot = header.rowSlots[r];
      if (slot != null) out.add(slot);
    }
    return out;
  }

  /// 识别表头：星期行、节次列、每行节次区间
  static ScheduleHeader detectHeader(OcrGrid grid) {
    if (grid.isEmpty) {
      return const ScheduleHeader(
        dayHeaderRow: -1,
        dayOfColumn: {},
        sectionColumn: -1,
        rowSlots: [],
        bodyTopRow: 0,
      );
    }

    // 1) 找星期行：命中星期标签最多的那一行（要求 >= minDayLabels 且列不重复）
    var bestRow = -1;
    var bestMap = <int, int>{};
    var bestScore = 0;
    for (var r = 0; r < grid.rows; r++) {
      final map = <int, int>{};
      final seen = <int>{};
      for (final cell in grid.cells) {
        if (cell.row != r) continue;
        final day = tryParseDayOfWeek(cell.text);
        if (day == null) continue;
        if (!seen.add(day)) continue;
        for (var c = cell.col; c < cell.colEnd; c++) {
          map.putIfAbsent(c, () => day);
        }
      }
      if (map.length > bestScore) {
        bestScore = map.length;
        bestRow = r;
        bestMap = map;
      }
    }
    if (bestScore < minDayLabels) bestRow = -1;

    // 星期行的下边界（表头可能合并两行，如「星期一」+「上午/下午」）
    var bodyTopRow = bestRow + 1;
    if (bestRow >= 0) {
      for (final cell in grid.cells) {
        if (cell.row != bestRow) continue;
        if (tryParseDayOfWeek(cell.text) == null) continue;
        if (cell.rowEnd > bodyTopRow) bodyTopRow = cell.rowEnd;
      }
    }

    // 2) 找节次列：课程区里能解析出节次最多的那一列
    var sectionCol = -1;
    var sectionHits = 0;
    for (var c = 0; c < grid.cols; c++) {
      if (bestMap.containsKey(c)) continue;
      final seen = <int>{};
      var hits = 0;
      for (final cell in grid.cells) {
        if (cell.col != c) continue;
        if (cell.row < bodyTopRow) continue;
        if (!seen.add(cell.row)) continue;
        if (_parseSectionLabel(cell.text, cell.rowSpan) != null) hits++;
      }
      if (hits > sectionHits) {
        sectionHits = hits;
        sectionCol = c;
      }
    }

    // 3) 逐行算节次区间；无法解析的行按行序兜底
    final slots = List<SectionSlot?>.filled(grid.rows, null);
    if (sectionCol >= 0) {
      for (final cell in grid.cells) {
        if (cell.col != sectionCol) continue;
        final slot = _parseSectionLabel(cell.text, cell.rowSpan);
        if (slot == null) continue;
        for (var r = cell.row; r < cell.rowEnd && r < grid.rows; r++) {
          slots[r] = slot;
        }
      }
    }
    for (var r = bodyTopRow; r < grid.rows; r++) {
      slots[r] ??= SectionSlot(r - bodyTopRow + 1, r - bodyTopRow + 1);
    }

    final header = ScheduleHeader(
      dayHeaderRow: bestRow,
      dayOfColumn: bestMap,
      sectionColumn: sectionCol,
      rowSlots: slots,
      bodyTopRow: bodyTopRow,
    );
    return header;
  }

  /// 节次标签解析：「第1节」「第1节 08:00-08:45」「1-2」「第一节」「上午第三节」…
  ///
  /// 返回 null 表示交给行序兜底。两类必须返回 null 的情况：
  /// 1. 纯时间标签（08:00-08:45）——不含节次序号；
  /// 2. 带「上午/下午」这类块标记的序号——其含义依赖学校作息，硬取会错。
  static SectionSlot? _parseSectionLabel(String raw, int spanRows) {
    var s = _normalize(raw);
    if (s.isEmpty) return null;

    // 先剥掉时间点，否则「08:00-08:45」会被当成节次区间 0-8
    s = s.replaceAll(RegExp(r'\d{1,2}:\d{2}'), '');
    // 剩下的应当是短标签；长文本（一门课的完整描述）不该被当成节次
    if (s.length > 8) return null;

    s = s.replaceAll(RegExp(r'[第节小课次]'), '').trim();
    if (s.isEmpty) return null;

    // 显式区间优先
    final range = RegExp(r'(\d+)\s*[-~～—–－到至]\s*(\d+)').firstMatch(s);
    if (range != null) {
      final a = int.tryParse(range.group(1)!);
      final b = int.tryParse(range.group(2)!);
      if (a != null && b != null && a >= 1 && b >= a && b - a < 12) {
        return SectionSlot(a, b);
      }
    }

    if (RegExp(r'(上午|早上|早晨|中午|下午|傍晚|晚上|夜间|时段)').hasMatch(s)) {
      return null;
    }

    // 单个数字：若该标签纵向合并了 n 行，语义上就是连着的 n 节
    final span = spanRows < 1 ? 1 : spanRows;
    final single = RegExp(r'(\d+)').firstMatch(s);
    if (single != null) {
      final n = int.tryParse(single.group(1)!);
      if (n != null && n >= 1 && n <= 30) return SectionSlot(n, n + span - 1);
    }

    final cn = _chineseNumber(s);
    if (cn != null && cn >= 1 && cn <= 30) return SectionSlot(cn, cn + span - 1);

    return null;
  }

  static String _normalize(String s) {
    final buf = StringBuffer();
    for (final r in s.trim().runes) {
      if (r == 0x3000) {
        buf.write(' ');
      } else if (r >= 0xFF01 && r <= 0xFF5E) {
        buf.writeCharCode(r - 0xFEE0);
      } else {
        buf.writeCharCode(r);
      }
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), '');
  }

  static const _cnDigits = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
  };

  /// 「一」→1 「十二」→12 「二十」→20
  static int? _chineseNumber(String s) {
    final m = RegExp(r'[一二三四五六七八九十]+').firstMatch(s);
    if (m == null) return null;
    final t = m.group(0)!;
    if (t == '十') return 10;
    if (t.length == 1) return _cnDigits[t];
    final idx = t.indexOf('十');
    if (idx < 0) return null;
    if (idx == 0 && t.length == 2) return 10 + (_cnDigits[t[1]] ?? 0);
    if (idx == 1 && t.length == 2) return (_cnDigits[t[0]] ?? 0) * 10;
    return null;
  }
}
