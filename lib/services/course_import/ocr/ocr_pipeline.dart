/// OCR 识别结果 → ImportDraft（公共管线的一部分）
///
/// 管线：表格结构 → 网格还原 → 表头定位 → 单元格语义 → 课程模型。
/// 产出的 [ImportDraft] 与模板/ICS 导入完全同构，直接进同一个预览确认页。
library;

import '../../../models/course.dart';
import '../course_import_source.dart';
import 'course_cell_parser.dart';
import 'ocr_grid.dart';
import 'ocr_models.dart';

class OcrImportPipeline {
  /// 把一次识别结果转成导入草稿。
  ///
  /// [totalWeeks] 用于「格子里没写周次」时兜底（取学期总周数）。
  /// 多张表时取「能成功解析出课表的那张」（单元格最多者优先）。
  static ImportDraft buildDraft(
    OcrResult result, {
    int totalWeeks = 20,
    String sourceName = '图片识别',
  }) {
    if (result.tables.isEmpty) {
      throw const OcrException(
        '没在图片里找到表格。请用教务系统/课表 App 的截图，尽量别拍歪、别裁掉边框',
        code: 'NO_TABLE',
      );
    }

    final issues = <String>[];
    if (result.angle.abs() > 3) {
      issues.add('图片倾斜约 ${result.angle.toStringAsFixed(1)}°，识别可能有偏差，请核对');
    }

    final sorted = [...result.tables]
      ..sort((a, b) => b.cellCount.compareTo(a.cellCount));

    ScheduleGridResult? parsed;
    final failures = <String>[];
    for (final table in sorted) {
      try {
        parsed = ScheduleGridParser.parse(OcrGrid.fromTable(table));
        break;
      } on OcrException catch (e) {
        failures.add(e.message);
      }
    }
    if (parsed == null) {
      // 报最有信息量的那条（通常是第一张表的失败原因）
      throw OcrException(
        failures.isEmpty ? '没能解析出课表' : failures.first,
        code: 'PARSE_FAILED',
      );
    }

    issues.addAll(parsed.issues);

    final courses = <Course>[];
    var unnamedCells = 0;

    for (final cell in parsed.courses) {
      final slots = CourseCellParser.parse(cell.text, totalWeeks: totalWeeks);
      if (slots.isEmpty) {
        unnamedCells++;
        continue;
      }
      for (final slot in slots) {
        courses.add(Course(
          name: slot.name,
          teacher: slot.teacher,
          sessions: [
            CourseSession(
              courseId: 0,
              dayOfWeek: cell.dayOfWeek,
              startSection: cell.startSection,
              sectionCount: cell.endSection - cell.startSection + 1,
              weeks: slot.weeks ?? List.generate(totalWeeks, (i) => i + 1),
              location: slot.location,
            ),
          ],
        ));
      }
    }

    if (courses.isEmpty) {
      throw const OcrException(
        '看懂了表格结构，但格子里没读出课程名。请换更清晰的截图重试',
        code: 'NO_COURSE_NAME',
      );
    }
    if (unnamedCells > 0) {
      issues.add('有 $unnamedCells 个格子只能读出周次、读不出课程名，已跳过');
    }

    final merged = mergeCoursesByName(courses);
    final withColor = <Course>[];
    for (var i = 0; i < merged.length; i++) {
      withColor.add(merged[i].copyWith(
        color: Course.presetColors[i % Course.presetColors.length],
      ));
    }

    issues.add('星期与节次由表格位置推断，若图片表头有偏移请在预览页逐格核对');

    return ImportDraft(
      courses: withColor,
      issues: issues,
      sourceName: sourceName,
    );
  }
}
