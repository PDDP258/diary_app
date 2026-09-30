/// OCR 表格结构模型
///
/// 数据来源有两条，本模型同时吃得住：
/// 1. **云函数归一化结构**（推荐路径，见 `cloud/ocr-proxy/index.js`）：
///    `{ok:true, angle:0, tables:[{type:1, rows:12, cols:8, cells:[{r,c,rs,cs,text,confidence}]}]}`
/// 2. **腾讯云原始结构**（排查问题时直连用）：
///    `{Response:{TableDetections:[{Cells:[{RowTl,ColTl,RowBr,ColBr,Text,Confidence}]}]}}`
///
/// 索引换算：腾讯云的 `RowBr/ColBr` 是**开区间**（官方示例中跨 9 列的标题格写作
/// `ColTl=0, ColBr=9`），故归一化时 `cs = ColBr - ColTl`。见 `cloud/ocr-proxy/test/`。
library;

/// 识别服务返回的业务错误（区别于网络错误）
class OcrException implements Exception {
  final String message;
  final String? code;

  const OcrException(this.message, {this.code});

  @override
  String toString() => message;
}

/// 一个单元格。坐标为「左上角 + 跨越格数」，与腾讯云返回对齐。
class OcrCell {
  final int row; // 左上角行索引，0 起
  final int col; // 左上角列索引，0 起
  final int rowSpan; // 纵向跨越格数，>=1
  final int colSpan; // 横向跨越格数，>=1
  final String text;
  final double? confidence;

  const OcrCell({
    required this.row,
    required this.col,
    this.rowSpan = 1,
    this.colSpan = 1,
    required this.text,
    this.confidence,
  });

  int get rowEnd => row + rowSpan; // 开区间
  int get colEnd => col + colSpan;

  bool get isMerged => rowSpan > 1 || colSpan > 1;

  @override
  String toString() => 'OcrCell($row,$col ${rowSpan}x$colSpan "$text")';
}

/// 一张表
class OcrTable {
  final List<OcrCell> cells;
  final int type; // 0 非表格文本 / 1 有线表格 / 2 无线表格
  final int declaredRows;
  final int declaredCols;

  const OcrTable({
    required this.cells,
    this.type = 1,
    this.declaredRows = 0,
    this.declaredCols = 0,
  });

  /// 有内容的单元格数（诊断用）
  int get cellCount => cells.length;
}

/// 一次识别的结果
class OcrResult {
  final List<OcrTable> tables;
  final double angle;
  final String? requestId;

  const OcrResult({
    required this.tables,
    this.angle = 0,
    this.requestId,
  });

  bool get isEmpty => tables.isEmpty;

  /// 解析云端响应。`ok=false` 时抛 [OcrException]。
  factory OcrResult.fromJson(Map<String, dynamic> json) {
    // 解包 {Response: {...}}
    var root = json;
    final resp = json['Response'];
    if (resp is Map) root = Map<String, dynamic>.from(resp);

    // 业务失败信号
    final ok = root['ok'];
    if (ok == false) {
      throw OcrException(
        (root['error'] as String?) ?? '识别失败',
        code: root['code'] as String?,
      );
    }

    final rawTables = root['tables'] ?? root['TableDetections'];
    final tables = <OcrTable>[];
    if (rawTables is List) {
      for (final t in rawTables) {
        if (t is! Map) continue;
        final table = _parseTable(Map<String, dynamic>.from(t));
        if (table != null) tables.add(table);
      }
    }

    final angleRaw = root['angle'] ?? root['Angle'];
    return OcrResult(
      tables: tables,
      angle: _asDouble(angleRaw) ?? 0,
      requestId: (root['requestId'] ?? root['RequestId']) as String?,
    );
  }

  static OcrTable? _parseTable(Map<String, dynamic> t) {
    final rawCells = t['cells'] ?? t['Cells'];
    if (rawCells is! List) return null;
    final cells = <OcrCell>[];
    for (final c in rawCells) {
      if (c is! Map) continue;
      final cell = _parseCell(Map<String, dynamic>.from(c));
      if (cell != null) cells.add(cell);
    }
    if (cells.isEmpty) return null;
    return OcrTable(
      cells: cells,
      type: _asInt(t['type'] ?? t['Type']) ?? 1,
      declaredRows: _asInt(t['rows']) ?? 0,
      declaredCols: _asInt(t['cols']) ?? 0,
    );
  }

  static OcrCell? _parseCell(Map<String, dynamic> c) {
    final text = ((c['text'] ?? c['Text']) as String? ?? '').trim();
    if (text.isEmpty) return null;

    final row = _asInt(c['r'] ?? c['row'] ?? c['RowTl']) ?? 0;
    final col = _asInt(c['c'] ?? c['col'] ?? c['ColTl']) ?? 0;

    // 归一化结构直接给 rs/cs；原始结构用 RowBr/ColBr（开区间）相减
    int rowSpan = _asInt(c['rs'] ?? c['rowSpan']) ?? 0;
    int colSpan = _asInt(c['cs'] ?? c['colSpan']) ?? 0;
    if (rowSpan <= 0) {
      final rowBr = _asInt(c['RowBr']);
      rowSpan = rowBr == null ? 1 : rowBr - row;
    }
    if (colSpan <= 0) {
      final colBr = _asInt(c['ColBr']);
      colSpan = colBr == null ? 1 : colBr - col;
    }

    return OcrCell(
      row: row,
      col: col,
      rowSpan: rowSpan < 1 ? 1 : rowSpan,
      colSpan: colSpan < 1 ? 1 : colSpan,
      text: text,
      confidence: _asDouble(c['confidence'] ?? c['Confidence']),
    );
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
