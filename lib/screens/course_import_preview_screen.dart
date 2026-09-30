import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/course.dart';
import '../providers/course_provider.dart';
import '../providers/theme_provider.dart';
import '../services/course_import/course_import_source.dart';
import '../utils/week_parser.dart';

/// 导入预览确认页（所有导入路径共用，PRD 决策 D2 公共管线终点）
///
/// 展示解析出的课程与问题列表，用户确认后批量入库。
class CourseImportPreviewScreen extends StatelessWidget {
  final ImportDraft draft;

  const CourseImportPreviewScreen({super.key, required this.draft});

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        title: Text('导入预览', style: TextStyle(color: scheme.textDarkColor)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
      ),
      body: Column(
        children: [
          _summaryHeader(scheme),
          if (draft.issues.isNotEmpty) _issuesBanner(scheme),
          Expanded(
            child: draft.courses.isEmpty
                ? Center(
                    child: Text('没有可导入的课程',
                        style: TextStyle(color: scheme.textMediumColor)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: draft.courses.length,
                    itemBuilder: (context, i) =>
                        _courseCard(scheme, draft.courses[i]),
                  ),
          ),
          _bottomBar(context, scheme),
        ],
      ),
    );
  }

  Widget _summaryHeader(ThemeScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '来自「${draft.sourceName}」：识别出 ${draft.courses.length} 门课程，'
        '共 ${draft.sessionCount} 个上课安排',
        style: TextStyle(fontSize: 14, color: scheme.textDarkColor),
      ),
    );
  }

  Widget _issuesBanner(ThemeScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.warningColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${draft.issues.length} 行解析失败（已跳过）',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.warningColor)),
          const SizedBox(height: 4),
          for (final issue in draft.issues.take(5))
            Text(issue,
                style:
                    TextStyle(fontSize: 12, color: scheme.textMediumColor)),
          if (draft.issues.length > 5)
            Text('…等共 ${draft.issues.length} 条',
                style:
                    TextStyle(fontSize: 12, color: scheme.textLightColor)),
        ],
      ),
    );
  }

  Widget _courseCard(ThemeScheme scheme, Course course) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: scheme.shadowColor,
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: Color(course.color), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(course.name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor)),
              ),
              if (course.teacher != null && course.teacher!.isNotEmpty)
                Text(course.teacher!,
                    style: TextStyle(
                        fontSize: 12, color: scheme.textMediumColor)),
            ],
          ),
          const SizedBox(height: 8),
          for (final s in course.sessions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '周${_weekdayNames[s.dayOfWeek - 1]} 第${s.startSection}-${s.endSection}节'
                ' · 第 ${WeekParser.formatWeeks(s.weeks)} 周'
                '${s.location != null && s.location!.isNotEmpty ? ' · ${s.location}' : ''}',
                style:
                    TextStyle(fontSize: 12, color: scheme.textMediumColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context, ThemeScheme scheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: scheme.primaryColor),
            onPressed: draft.courses.isEmpty
                ? null
                : () => _confirmImport(context),
            child: Text('确认导入 ${draft.courses.length} 门课程',
                style: const TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmImport(BuildContext context) async {
    final provider = context.read<CourseProvider>();
    for (final course in draft.courses) {
      await provider.addCourse(course, course.sessions);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${draft.courses.length} 门课程')));
      Navigator.pop(context);
    }
  }
}
