import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clipboard/clipboard.dart';
import '../config/app_theme.dart';
import '../models/course.dart';
import '../providers/course_provider.dart';
import '../providers/theme_provider.dart';
import '../services/course_import/template_import_source.dart';
import '../services/course_import/ics_import_source.dart';
import '../services/course_import/course_import_source.dart';
import '../services/course_import/jwapp_import_source.dart';
import '../services/course_import/jwapp/jwapp_client.dart';
import '../services/course_import/jwapp/jwapp_config.dart';
import '../services/course_import/jwapp/jwapp_endpoints.dart';
import '../services/course_reminder_service.dart';
import '../utils/week_parser.dart';
import 'course_import_preview_screen.dart';
import 'jwapp_endpoints_dialog.dart';
import 'jwapp_login_screen.dart';
import 'semester_settings_screen.dart';
import 'course_edit_screen.dart';

/// 课表主页：周网格视图
///
/// 布局：顶部周切换条 + 7 列（周一~周日）× N 节次网格。
/// 课程块跨节次显示，点击进入编辑。
class CourseScheduleScreen extends StatefulWidget {
  const CourseScheduleScreen({super.key});

  @override
  State<CourseScheduleScreen> createState() => _CourseScheduleScreenState();
}

class _CourseScheduleScreenState extends State<CourseScheduleScreen> {
  int? _viewingWeek; // null 时跟随当前周

  /// 教务系统接入点（学校）。未配置时首次导入会引导选择。
  JwappEndpoints? _jwappEndpoints;

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    JwappConfig.load().then((ep) {
      if (mounted && ep != null) setState(() => _jwappEndpoints = ep);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        title: Text('课程表', style: TextStyle(color: scheme.textDarkColor)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: '上课提醒',
            onPressed: _showReminderSettings,
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '导入课表',
            onPressed: _showImportMenu,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '学期设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SemesterSettingsScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<CourseProvider>(
        builder: (context, provider, _) {
          if (!provider.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final semester = provider.semester;
          if (semester == null) {
            return _buildEmptySemester(scheme);
          }
          final currentWeek = provider.currentWeek;
          final week = _viewingWeek ?? currentWeek ?? 1;
          return Column(
            children: [
              _buildWeekSwitcher(scheme, semester, week, currentWeek),
              Expanded(child: _buildGrid(scheme, provider, semester, week)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: scheme.primaryColor,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CourseEditScreen()),
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  /// 导入入口菜单：模板 / ICS / 教务系统
  void _showImportMenu() {
    final scheme = AppTheme.schemeOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.table_chart_outlined,
                  color: scheme.primaryColor),
              title: const Text('Excel / CSV 模板导入'),
              subtitle: const Text('下载模板格式，批量导入课程'),
              onTap: () {
                Navigator.pop(ctx);
                _runImport(TemplateImportSource(), showTemplateHelp: true);
              },
            ),
            ListTile(
              leading: Icon(Icons.calendar_month_outlined,
                  color: scheme.primaryColor),
              title: const Text('ICS 日历文件导入'),
              subtitle: const Text('导入学校导出的 .ics 课表文件'),
              onTap: () {
                Navigator.pop(ctx);
                _runImport(IcsImportSource());
              },
            ),
            ListTile(
              leading: Icon(Icons.account_balance_outlined,
                  color: scheme.primaryColor),
              title: const Text('教务系统导入'),
              subtitle: Text(_jwappEndpoints == null
                  ? '应用内登录学校教务，直接读取课表'
                  : '当前：${_jwappEndpoints!.name}'),
              onTap: () {
                Navigator.pop(ctx);
                _startJwappImport();
              },
            ),
            // 图片识别导入（OCR）暂缓，不出现在入口。
            // 实现保留在 services/course_import/ocr/ + ocr_import_source.dart +
            // ocr_service_settings_dialog.dart + cloud/ocr-proxy/，未接线。
            // 恢复入口需要：(1) 本菜单加 ListTile 指向 OcrImportSource
            // (2) 课表页 import ocr_import_source.dart / ocr_service_settings_dialog.dart
            // (3) _runImport 补进度弹窗与 OcrException 分支（见 .rollback/ocr-20260929/）。
            if (_jwappEndpoints != null) ...[
              Divider(
                  height: 1,
                  color: scheme.textLightColor.withValues(alpha: 0.15)),
              ListTile(
                dense: true,
                leading: Icon(Icons.swap_horiz_outlined,
                    size: 18, color: scheme.textLightColor),
                title: Text('更换教务系统',
                    style:
                        TextStyle(fontSize: 13, color: scheme.textLightColor)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picked = await showJwappEndpointsDialog(context,
                      current: _jwappEndpoints);
                  if (picked == null) return;
                  await JwappConfig.save(picked);
                  if (!mounted) return;
                  setState(() => _jwappEndpoints = picked);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runImport(CourseImportSource source,
      {bool showTemplateHelp = false,
      Future<void> Function()? beforePreview}) async {
    final scheme = AppTheme.schemeOf(context);

    if (showTemplateHelp) {
      // 先展示模板说明，可一键复制模板
      final goOn = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('模板格式'),
          content: const SingleChildScrollView(
            child: Text('表格第一行为表头，之后每行一个上课安排：\n\n'
                '课程名称,教师,星期,开始节,结束节,周次,地点\n\n'
                '示例：\n高等数学,张老师,1,1,2,1-16,教一101\n\n'
                '· 星期填 1-7 或 周一~周日\n'
                '· 周次支持 1-16、1,3,5、1-15单周\n'
                '· 保存为 .csv 或 .xlsx 均可导入'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FlutterClipboard.copy(TemplateImportSource.templateCsv);
                ScaffoldMessenger.of(dctx).showSnackBar(
                    const SnackBar(content: Text('模板已复制到剪贴板')));
              },
              child: const Text('复制模板'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: scheme.primaryColor),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('选择文件',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (goOn != true || !mounted) return;
    }

    try {
      final draft = await source.collect();
      if (draft == null || !mounted) return; // 用户取消
      // 部分导入源（教务）需要先把元数据落地再进预览
      if (beforePreview != null) await beforePreview();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CourseImportPreviewScreen(draft: draft)),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败：${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  /// 教务系统导入：首次引导选学校，之后直接进登录页
  Future<void> _startJwappImport() async {
    var endpoints = _jwappEndpoints;
    if (endpoints == null) {
      endpoints = await showJwappEndpointsDialog(context);
      if (endpoints == null || !mounted) return;
      await JwappConfig.save(endpoints);
      if (!mounted) return;
      setState(() => _jwappEndpoints = endpoints);
    }

    final ep = endpoints;
    final source = JwappImportSource(
      endpoints: ep,
      openLogin: () async {
        if (!mounted) return null;
        return Navigator.of(context).push<JwappImportData>(
          MaterialPageRoute(builder: (_) => JwappLoginScreen(endpoints: ep)),
        );
      },
    );

    await _runImport(
      source,
      beforePreview: () => _applyJwappResult(source),
    );
  }

  /// 教务数据落地：写学期配置（保留用户改过的作息时间）+ 展示调课提示
  Future<void> _applyJwappResult(JwappImportSource source) async {
    final provider = context.read<CourseProvider>();
    final semester = source.semesterSuggestion;

    if (semester != null) {
      final existing = provider.semester;
      final config = semester.toSemesterConfig(
        minSections: source.maxSection,
        mergeWith: existing,
      );
      final unchanged = existing != null &&
          existing.startDate == config.startDate &&
          existing.totalWeeks == config.totalWeeks;

      if (existing == null) {
        await provider.saveSemester(config);
        _toast('已按教务数据设置学期：${config.startDate} 起，共 ${config.totalWeeks} 周');
      } else if (!unchanged) {
        if (!mounted) return;
        final scheme = AppTheme.schemeOf(context);
        final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('更新学期设置'),
            content: Text('教务系统显示本学期 ${config.startDate} 开学、共 ${config.totalWeeks} 周。\n\n'
                '当前设置：${existing.startDate} 开学、共 ${existing.totalWeeks} 周。\n\n'
                '更新只覆盖开学日与总周数，节次上课时间保持你现在的设置。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('保持现状'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: scheme.primaryColor),
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('更新', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (ok == true) {
          await provider.saveSemester(config);
          _toast('已更新学期设置');
        }
      }
    }

    for (final notice in source.notices) {
      _toast(notice);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 上课提醒设置弹层
  Future<void> _showReminderSettings() async {
    final scheme = AppTheme.schemeOf(context);
    var enabled = await CourseReminderService.isEnabled();
    var minutes = await CourseReminderService.remindMinutes();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: scheme.cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('上课提醒',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: scheme.textDarkColor)),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('开启课前提醒',
                      style: TextStyle(color: scheme.textDarkColor)),
                  subtitle: Text('未来两周的课程将自动安排提醒',
                      style: TextStyle(
                          fontSize: 12, color: scheme.textLightColor)),
                  value: enabled,
                  activeTrackColor: scheme.primaryColor,
                  onChanged: (v) => setSheetState(() => enabled = v),
                ),
                if (enabled) ...[
                  Text('提前量',
                      style: TextStyle(color: scheme.textMediumColor)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in [5, 10, 15, 30, 60])
                        ChoiceChip(
                          label: Text(m >= 60 ? '1 小时' : '$m 分钟'),
                          selected: minutes == m,
                          selectedColor:
                              scheme.primaryColor.withValues(alpha: 0.2),
                          onSelected: (_) =>
                              setSheetState(() => minutes = m),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: scheme.primaryColor),
                    onPressed: () async {
                      final provider = context.read<CourseProvider>();
                      await CourseReminderService.saveSettings(
                        enabled: enabled,
                        minutes: minutes,
                        courses: provider.courses,
                        semester: provider.semester,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content:
                                Text(enabled ? '上课提醒已开启' : '上课提醒已关闭')));
                      }
                    },
                    child:
                        const Text('保存', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 未配置学期时的引导页
  Widget _buildEmptySemester(ThemeScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 64, color: scheme.textLightColor),
            const SizedBox(height: 16),
            Text('先设置学期信息',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor)),
            const SizedBox(height: 8),
            Text('设置开学日期和节次时间后\n就可以添加课程了',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.textMediumColor, height: 1.5)),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: scheme.primaryColor),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SemesterSettingsScreen()),
              ),
              icon: const Icon(Icons.settings, color: Colors.white),
              label: const Text('去设置', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekSwitcher(
      ThemeScheme scheme, SemesterConfig semester, int week, int? currentWeek) {
    final isCurrentWeek = week == currentWeek;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: scheme.backgroundColor,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: week > 1
                ? () => setState(() => _viewingWeek = week - 1)
                : null,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _viewingWeek = null),
              child: Column(
                children: [
                  Text('第 $week 周',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.textDarkColor)),
                  Text(
                    isCurrentWeek
                        ? '本周 · 点击回到本周'
                        : (currentWeek != null
                            ? '今天是第 $currentWeek 周'
                            : '学期外'),
                    style: TextStyle(fontSize: 11, color: scheme.textLightColor),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: week < semester.totalWeeks
                ? () => setState(() => _viewingWeek = week + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(ThemeScheme scheme, CourseProvider provider,
      SemesterConfig semester, int week) {
    final sections = semester.sections;
    final today = DateTime.now();
    final isViewingCurrentWeek = week == provider.currentWeek;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 100),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 节次时间列
          Column(
            children: [
              _headerCell(scheme, ''),
              for (final s in sections)
                _timeCell(scheme, s),
            ],
          ),
          // 周一~周日 7 列
          for (var day = 1; day <= 7; day++)
            Expanded(
              child: Column(
                children: [
                  _headerCell(
                    scheme,
                    _weekdayNames[day - 1],
                    highlight: isViewingCurrentWeek && today.weekday == day,
                  ),
                  ..._buildDayCells(scheme, provider, week, day),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 一天的单元格：课程块跨行 + 空格
  List<Widget> _buildDayCells(
      ThemeScheme scheme, CourseProvider provider, int week, int day) {
    final providerSections = provider.semester?.sections.length ?? 8;
    final cells = <Widget>[];
    var section = 1;
    while (section <= providerSections) {
      final hit = provider.courseAt(week, day, section);
      if (hit != null && hit.session.startSection == section) {
        cells.add(_courseCell(
            scheme, hit.course, hit.session, provider.semester));
        section = hit.session.endSection + 1;
      } else if (hit != null) {
        // 已被跨行课程块覆盖，跳过
        section++;
      } else {
        cells.add(_emptyCell(scheme));
        section++;
      }
    }
    return cells;
  }

  static const double _cellHeight = 56;

  Widget _headerCell(ThemeScheme scheme, String text,
      {bool highlight = false}) {
    return Container(
      height: 32,
      width: 44,
      alignment: Alignment.center,
      decoration: highlight
          ? BoxDecoration(
              color: scheme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color:
                  highlight ? scheme.primaryColor : scheme.textMediumColor)),
    );
  }

  Widget _timeCell(ThemeScheme scheme, SectionTime s) {
    return Container(
      height: _cellHeight,
      width: 44,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${s.section}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor)),
          Text(s.startTime,
              style:
                  TextStyle(fontSize: 9, color: scheme.textLightColor)),
        ],
      ),
    );
  }

  Widget _emptyCell(ThemeScheme scheme) {
    return Container(
      height: _cellHeight,
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: scheme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _courseCell(ThemeScheme scheme, Course course, CourseSession session,
      SemesterConfig? semester) {
    final color = Color(course.color);
    final compact = session.sectionCount == 1;

    // 起止时间：第一节上课 ~ 最后一节下课
    String? timeRange;
    if (semester != null) {
      final start = semester.sections
          .where((s) => s.section == session.startSection)
          .firstOrNull;
      final end = semester.sections
          .where((s) => s.section == session.endSection)
          .firstOrNull;
      if (start != null && end != null) {
        timeRange = '${start.startTime}-${end.endTime}';
      }
    }

    final hasLocation =
        session.location != null && session.location!.isNotEmpty;
    final hasTeacher = course.teacher != null && course.teacher!.isNotEmpty;

    return GestureDetector(
      onTap: () => _showCourseDetail(scheme, course, session),
      child: Container(
        height: _cellHeight * session.sectionCount,
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 上课地点：大号粗体，最醒目
            if (hasLocation)
              Text(
                session.location!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.textDarkColor,
                    height: 1.15),
              ),
            // 课程全名
            Text(
              course.name,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                  height: 1.2),
            ),
            // 任课教师
            if (hasTeacher && !compact)
              Text(
                course.teacher!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 9, color: scheme.textMediumColor),
              ),
            const Spacer(),
            // 起止时间
            if (timeRange != null)
              Text(
                timeRange,
                maxLines: 1,
                style:
                    TextStyle(fontSize: 9, color: scheme.textLightColor),
              ),
          ],
        ),
      ),
    );
  }

  void _showCourseDetail(
      ThemeScheme scheme, Course course, CourseSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Color(course.color),
                          shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(course.name,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: scheme.textDarkColor)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (course.teacher != null && course.teacher!.isNotEmpty)
                _detailRow(scheme, Icons.person_outline, course.teacher!),
              _detailRow(scheme, Icons.schedule,
                  '周${_weekdayNames[session.dayOfWeek - 1]} 第${session.startSection}-${session.endSection}节'),
              _detailRow(scheme, Icons.date_range,
                  '第 ${WeekParser.formatWeeks(session.weeks)} 周'),
              if (session.location != null && session.location!.isNotEmpty)
                _detailRow(
                    scheme, Icons.location_on_outlined, session.location!),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CourseEditScreen(course: course)),
                      );
                    },
                    child:
                        Text('编辑', style: TextStyle(color: scheme.primaryColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(ThemeScheme scheme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.textMediumColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    TextStyle(fontSize: 14, color: scheme.textDarkColor)),
          ),
        ],
      ),
    );
  }
}
