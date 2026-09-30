/// jwapp 接口响应拆包
///
/// 教务系统（金智 jwapp / ehall）所有数据接口的统一信封：
///
/// ```json
/// { "code": "0", "datas": { "<表名>": { "totalSize": 14, "rows": [ ... ] } } }
/// ```
///
/// 失败形态有两种，都必须在拆包层识别出来，否则上层会拿到空表却以为
/// 「这学期没课」：
/// - **登录态失效**：返回 HTML（`<title>系统异常</title>` / `403`），不是 JSON
/// - **业务错误**：JSON 正常但 `code != "0"`
library;

import 'dart:convert';

import 'jwapp_models.dart';

class JwappResponse {
  /// 拆出 `datas.<key>` 这张表；[key] 为 null 时自动取第一张含 `rows` 的表。
  ///
  /// 自动发现是为了跨校容错：课表表名实测为 `cxxszhxqkb`，
  /// 但不同版本 jwapp 可能不同，没必要硬编码。
  static Map<String, dynamic> unwrapTable(String body, {String? key}) {
    final datas = _unwrapDatas(body);

    if (key != null) {
      final table = datas[key];
      if (table is! Map) {
        throw JwappException(
          '响应中缺少 datas.$key（实际含：${datas.keys.join(', ')}）',
          kind: JwappErrorKind.malformed,
        );
      }
      return Map<String, dynamic>.from(table);
    }

    for (final entry in datas.entries) {
      final value = entry.value;
      if (value is Map && value['rows'] is List) {
        return Map<String, dynamic>.from(value);
      }
    }
    throw const JwappException(
      '响应中没有找到含 rows 的数据表',
      kind: JwappErrorKind.malformed,
    );
  }

  /// 取出 `datas.<key>.rows`；缺 rows 时返回空列表
  static List<Map<String, dynamic>> unwrapRows(String body, {String? key}) {
    final table = unwrapTable(body, key: key);
    return readRows(table);
  }

  /// 从已拆出的表里读 rows
  static List<Map<String, dynamic>> readRows(Map<String, dynamic> table) {
    final rows = table['rows'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  /// 拆到 `datas` 层，处理「非 JSON」与「业务码非 0」两种失败
  static Map<String, dynamic> _unwrapDatas(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      throw const JwappException('教务系统返回了空响应',
          kind: JwappErrorKind.notJson);
    }

    // HTML 错误页 —— CAS 会话过期时最常见
    if (trimmed.startsWith('<')) {
      throw const JwappException(
        '登录状态已失效，请重新登录教务系统后再试',
        kind: JwappErrorKind.notJson,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      throw const JwappException(
        '教务系统返回的内容不是 JSON，可能登录已过期',
        kind: JwappErrorKind.notJson,
      );
    }

    if (decoded is! Map) {
      throw const JwappException(
        '教务系统返回的 JSON 顶层不是对象',
        kind: JwappErrorKind.malformed,
      );
    }

    final code = decoded['code'];
    if (code != null && code.toString() != '0') {
      final msg = (decoded['msg'] ?? decoded['message'] ?? '').toString().trim();
      throw JwappException(
        '教务系统返回错误（code=$code${msg.isEmpty ? '' : ' $msg'}）',
        kind: JwappErrorKind.businessCode,
      );
    }

    final datas = decoded['datas'];
    if (datas is! Map) {
      throw const JwappException(
        '响应中缺少 datas 字段',
        kind: JwappErrorKind.malformed,
      );
    }
    return Map<String, dynamic>.from(datas);
  }
}
