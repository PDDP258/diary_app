/// 教务系统导入源（jwapp / 金智 ehall）
///
/// 与另外两条导入路径的区别：取数前需要用户**在 WebView 里登录**。
/// 为了不把 UI 依赖倒灌进 services 层，这里把「打开登录页」这件事
/// 通过 [openLogin] 注入 —— 本类只负责「原始响应 → ImportDraft」的解析，
/// 以及把解析出的学期建议、调课提示回传给调用方。
library;

import 'course_import_source.dart';
import 'jwapp/jwapp_client.dart';
import 'jwapp/jwapp_course_parser.dart';
import 'jwapp/jwapp_endpoints.dart';
import 'jwapp/jwapp_models.dart';
import 'jwapp/jwapp_semester_parser.dart';

class JwappImportSource extends CourseImportSource {
  /// 接入点（学校）
  final JwappEndpoints endpoints;

  /// 打开登录页取数；用户取消返回 null
  final Future<JwappImportData?> Function() openLogin;

  JwappImportSource({required this.endpoints, required this.openLogin});

  /// [collect] 后可用：本学期建议（开学日 / 总周数）
  JwappSemester? semesterSuggestion;

  /// [collect] 后可用：非致命提示（调课汇总等）
  List<String> notices = const [];

  /// [collect] 后可用：课表里出现的最大节次（用于撑开学期节次表）
  int maxSection = 0;

  /// [collect] 后可用：数据所属学期编码（`2026-2027-1`）
  String? semesterCode;

  @override
  String get name => '教务系统';

  @override
  Future<ImportDraft?> collect() async {
    final data = await openLogin();
    if (data == null) return null;

    final result = JwappCourseParser.parse(
      data.courseBody,
      tableKey: endpoints.courseTableKey,
      sourceName: name,
    );

    notices = result.notices;
    maxSection = result.maxSection;
    semesterCode = result.semesterCode;

    try {
      final semesters = JwappSemesterParser.parseAll(
        data.semesterBody,
        tableKey: endpoints.semesterTableKey,
      );
      semesterSuggestion = JwappSemesterParser.findByCode(
            semesters,
            result.semesterCode ?? '',
          ) ??
          JwappSemesterParser.pickCurrent(semesters);
    } catch (_) {
      // 学期配置解析失败不影响课程导入
      semesterSuggestion = null;
    }

    return result.draft;
  }
}
