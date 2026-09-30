/// jwapp（金智教育 ehall 教务系统）导入的公共模型
///
/// 教务系统是商业标准产品（jwapp / ehall），课表接口返回结构化 JSON，
/// 因此这条路径**不需要 DOM 适配器**，也不需要网格还原：
/// 直接 `fetch` 接口 → 拆包 → 映射到 [Course] / [CourseSession]。
///
/// 已实测：西北农林科技大学（`/jwapp/sys/wdkbby/`），2026-2027-1 学期。
/// 接口路径跨校应基本一致，但设计上保留可覆盖（见各 parser 的默认参数）。
library;

import '../../../models/course.dart';
import '../course_import_source.dart';

/// jwapp 导入过程中抛出的错误
class JwappException implements Exception {
  final String message;
  final JwappErrorKind kind;

  const JwappException(this.message, {this.kind = JwappErrorKind.unknown});

  @override
  String toString() => message;
}

enum JwappErrorKind {
  /// 响应不是 JSON —— 最常见的原因是 CAS 登录态失效（服务端回 HTML 错误页）
  notJson,

  /// 业务码非 0（`{code, msg}`）
  businessCode,

  /// JSON 结构符合语法但不符合预期
  malformed,

  unknown,
}

/// 一个学期（来自 `cxjcs.do` / `datas.cxjcs.rows`）
class JwappSemester {
  /// 学年，如 `2026-2027`
  final String academicYear;

  /// 学期号：`1` 秋 / `2` 春 / `3` 夏（暑期小学期）
  final String term;

  /// 第 1 周周一，`yyyy-MM-dd`
  final String startDate;

  /// 总周数（`ZZC`）
  final int totalWeeks;

  /// 排序权重（`PX`），越小越新。
  ///
  /// **实测存在为 null 的行**（如 2025-2026-3 暑假小学期），所以这里可空：
  /// 把 null 当成 0 会让它排到最前面，被误判成「最新学期」。
  final int? sortOrder;

  /// 是否在用（`SFSY`）
  final bool inUse;

  const JwappSemester({
    required this.academicYear,
    required this.term,
    required this.startDate,
    required this.totalWeeks,
    required this.sortOrder,
    required this.inUse,
  });

  /// 教务系统的学期编码，也是课表接口的 `XNXQDM` 参数
  String get code => '$academicYear-$term';

  /// 人类可读名称，如「2026-2027学年 秋」
  String get displayName {
    const termNames = {'1': '秋', '2': '春', '3': '夏'};
    final t = termNames[term] ?? term;
    return '$academicYear学年 $t';
  }

  /// 转成本地 [SemesterConfig]
  ///
  /// [minSections] 用于把节次表撑到足够长（课表里出现过的最大节次）。
  /// [mergeWith] 传入已有学期配置时会**保留用户自己改过的节次时间**——
  /// 教务数据只覆盖开学日与总周数，作息时间不能被打回默认值。
  SemesterConfig toSemesterConfig({
    int minSections = 10,
    SemesterConfig? mergeWith,
  }) {
    final need = minSections < 10 ? 10 : minSections;
    final kept = mergeWith?.sections;
    final sections =
        (kept != null && kept.length >= need) ? kept : _buildSections(need, kept);

    return SemesterConfig(
      id: mergeWith?.id,
      name: displayName,
      startDate: startDate,
      totalWeeks: totalWeeks,
      sections: sections,
      isActive: true,
      fixedDurationMode: mergeWith?.fixedDurationMode ?? true,
      classMinutes: mergeWith?.classMinutes ?? 45,
    );
  }

  /// 生成 [minSections] 节：优先沿用 [kept]，不足处补默认值，再不足按 50 分钟递推
  static List<SectionTime> _buildSections(
    int minSections, [
    List<SectionTime>? kept,
  ]) {
    final out = <SectionTime>[];
    for (var i = 1; i <= minSections; i++) {
      if (kept != null && kept.length >= i) {
        out.add(kept[i - 1]);
        continue;
      }
      if (i <= SemesterConfig.defaultSections.length) {
        out.add(SemesterConfig.defaultSections[i - 1]);
        continue;
      }
      // 兜底递推：每节 45 分钟，间隔 10 分钟
      final prev = out.last;
      out.add(SectionTime(
        section: i,
        startTime: _plusMinutes(prev.endTime, 10),
        endTime: _plusMinutes(prev.endTime, 55),
      ));
    }
    return out;
  }

  static String _plusMinutes(String hhmm, int minutes) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return hhmm;
    final total = (h * 60 + m + minutes) % (24 * 60);
    final hh = (total ~/ 60).toString().padLeft(2, '0');
    final mm = (total % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

/// 课表接口的解析结果
class JwappParseResult {
  /// 归一化后的课程草稿，直接可进公共预览确认页
  final ImportDraft draft;

  /// 非致命提示（调课、节次异常等），预览页可单独展示
  final List<String> notices;

  /// 数据来自哪个学期（课表行的 `XNXQDM`），用于与学期配置对齐
  final String? semesterCode;

  /// 参与解析的原始记录条数（含被跳过的）
  final int rawCount;

  /// 课表里出现的最大节次 —— 用于把学期节次表撑到够长
  final int maxSection;

  const JwappParseResult({
    required this.draft,
    required this.notices,
    required this.semesterCode,
    required this.rawCount,
    required this.maxSection,
  });
}
