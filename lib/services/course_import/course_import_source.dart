import '../../models/course.dart';

// 课程导入源抽象（PRD 决策 D2）
//
// 三条路径统一实现此接口；collect() 之后进入公共管线：
// 解析 → 归一化 → ImportPreview 页 → 入库。
//
// 实现：
// - [TemplateImportSource]  Excel/CSV 模板文件
// - [IcsImportSource]       .ics 日历文件
// - [OcrImportSource]       图片识别（暂缓，实现已完成但不接入 UI）
// - 教务系统 WebView 适配器（T11，后续实现）

/// 一次导入的原始产出：归一化后的课程（含安排）+ 逐行问题
class ImportDraft {
  /// 归一化后的课程列表（同名课程已合并，sessions 已挂上）
  final List<Course> courses;

  /// 解析过程中的问题（如第 N 行格式错误），供预览页展示
  final List<String> issues;

  /// 来源描述（如「Excel 模板」「ics 文件」）
  final String sourceName;

  const ImportDraft({
    required this.courses,
    required this.issues,
    required this.sourceName,
  });

  int get sessionCount =>
      courses.fold(0, (sum, c) => sum + c.sessions.length);
}

/// 导入源接口：collect() 完成「选文件/拍照/开 WebView」等各自特有的采集动作，
/// 返回归一化后的草稿；用户取消时返回 null。
abstract class CourseImportSource {
  String get name;

  Future<ImportDraft?> collect();
}

/// 按课程名合并课程（各导入源共用）
List<Course> mergeCoursesByName(List<Course> courses) {
  final map = <String, Course>{};
  for (final c in courses) {
    final key = '${c.name}|${c.teacher ?? ''}';
    final existing = map[key];
    if (existing == null) {
      map[key] = c;
    } else {
      map[key] = existing.copyWith(
          sessions: [...existing.sessions, ...c.sessions]);
    }
  }
  return map.values.toList();
}
