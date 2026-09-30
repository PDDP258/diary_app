import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/course.dart';
import '../providers/course_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/week_parser.dart';

/// 课程编辑/创建页（T3：手动添加）
///
/// 课程基本信息 + 多个上课安排（星期几/节次/周次/地点）。
class CourseEditScreen extends StatefulWidget {
  final Course? course; // null = 新建

  const CourseEditScreen({super.key, this.course});

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  final _nameController = TextEditingController();
  final _teacherController = TextEditingController();
  late int _color;
  late List<CourseSession> _sessions;

  static const _presetColors = Course.presetColors;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _nameController.text = c?.name ?? '';
    _teacherController.text = c?.teacher ?? '';
    _color = c?.color ?? _presetColors[0];
    _sessions = List.of(c?.sessions ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final isEdit = widget.course != null;

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        title: Text(isEdit ? '编辑课程' : '添加课程',
            style: TextStyle(color: scheme.textDarkColor)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
        actions: [
          if (isEdit)
            IconButton(
              icon: Icon(Icons.delete_outline, color: scheme.errorColor),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _save,
            child: Text('保存',
                style: TextStyle(
                    color: scheme.primaryColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(scheme, [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '课程名称',
                prefixIcon:
                    Icon(Icons.book_outlined, color: scheme.textMediumColor),
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 24),
            TextField(
              controller: _teacherController,
              decoration: InputDecoration(
                labelText: '教师（可选）',
                prefixIcon:
                    Icon(Icons.person_outline, color: scheme.textMediumColor),
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 24),
            _colorPicker(scheme),
          ]),
          const SizedBox(height: 16),
          _card(scheme, [
            Row(
              children: [
                Icon(Icons.event_note_outlined,
                    size: 18, color: scheme.textMediumColor),
                const SizedBox(width: 8),
                Text('上课安排',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _editSession(null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加'),
                  style:
                      TextButton.styleFrom(foregroundColor: scheme.primaryColor),
                ),
              ],
            ),
            if (_sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('还没有安排，点「添加」设置上课时间',
                    style: TextStyle(
                        fontSize: 13, color: scheme.textLightColor)),
              )
            else
              for (var i = 0; i < _sessions.length; i++)
                _sessionTile(scheme, i),
          ]),
        ],
      ),
    );
  }

  Widget _card(ThemeScheme scheme, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: scheme.shadowColor,
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _colorPicker(ThemeScheme scheme) {
    return Row(
      children: [
        Icon(Icons.palette_outlined, size: 18, color: scheme.textMediumColor),
        const SizedBox(width: 8),
        ..._presetColors.map((c) => GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: _color == c
                      ? Border.all(color: scheme.textDarkColor, width: 2)
                      : null,
                ),
              ),
            )),
      ],
    );
  }

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  Widget _sessionTile(ThemeScheme scheme, int index) {
    final s = _sessions[index];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '周${_weekdayNames[s.dayOfWeek - 1]} 第${s.startSection}-${s.endSection}节',
        style: TextStyle(fontSize: 14, color: scheme.textDarkColor),
      ),
      subtitle: Text(
        '第 ${WeekParser.formatWeeks(s.weeks)} 周'
        '${s.location != null && s.location!.isNotEmpty ? ' · ${s.location}' : ''}',
        style: TextStyle(fontSize: 12, color: scheme.textMediumColor),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.textLightColor),
      onTap: () => _editSession(index),
    );
  }

  Future<void> _editSession(int? index) async {
    final maxSection = context.read<CourseProvider>().semester?.sections.length ?? 8;
    final result = await showModalBottomSheet<CourseSession>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SessionEditorSheet(
        session: index == null ? null : _sessions[index],
        maxSection: maxSection,
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _sessions.add(result);
      } else {
        _sessions[index] = result;
      }
    });
  }

  Future<void> _delete() async {
    final scheme = AppTheme.schemeOf(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除「${widget.course!.name}」及其全部安排吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('删除', style: TextStyle(color: scheme.errorColor))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<CourseProvider>().deleteCourse(widget.course!.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    final scheme = AppTheme.schemeOf(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写课程名称')));
      return;
    }
    if (_sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请至少添加一个上课安排')));
      return;
    }
    final provider = context.read<CourseProvider>();
    final existing = widget.course;
    if (existing == null) {
      await provider.addCourse(
        Course(
            name: name,
            teacher: _teacherController.text.trim(),
            color: _color),
        _sessions,
      );
    } else {
      await provider.updateCourse(
        existing.copyWith(
            name: name,
            teacher: _teacherController.text.trim(),
            color: _color),
        _sessions,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已保存', style: TextStyle(color: scheme.cardColor))));
      Navigator.pop(context);
    }
  }
}

/// 上课安排编辑弹层
class _SessionEditorSheet extends StatefulWidget {
  final CourseSession? session;
  final int maxSection;

  const _SessionEditorSheet({this.session, required this.maxSection});

  @override
  State<_SessionEditorSheet> createState() => _SessionEditorSheetState();
}

class _SessionEditorSheetState extends State<_SessionEditorSheet> {
  late int _dayOfWeek;
  late int _startSection;
  late int _endSection;
  final _weeksController = TextEditingController();
  final _locationController = TextEditingController();
  String? _weeksError;

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _dayOfWeek = s?.dayOfWeek ?? DateTime.now().weekday;
    _startSection = s?.startSection ?? 1;
    _endSection = s?.endSection ?? 2;
    _weeksController.text =
        s == null ? '1-16' : WeekParser.formatWeeks(s.weeks);
    _locationController.text = s?.location ?? '';
  }

  @override
  void dispose() {
    _weeksController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('上课安排',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: scheme.textDarkColor)),
              const SizedBox(height: 16),

              // 星期选择
              Text('星期', style: TextStyle(color: scheme.textMediumColor)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var d = 1; d <= 7; d++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _dayOfWeek = d),
                        child: Container(
                          height: 36,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _dayOfWeek == d
                                ? scheme.primaryColor
                                : scheme.backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_weekdayNames[d - 1],
                              style: TextStyle(
                                  fontSize: 13,
                                  color: _dayOfWeek == d
                                      ? Colors.white
                                      : scheme.textDarkColor)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 节次区间
              Row(
                children: [
                  Expanded(
                    child: _sectionDropdown(scheme, '开始节', _startSection,
                        (v) => setState(() {
                              _startSection = v;
                              if (_endSection < v) _endSection = v;
                            })),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _sectionDropdown(scheme, '结束节', _endSection,
                        (v) => setState(() => _endSection = v)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 周次
              TextField(
                controller: _weeksController,
                decoration: InputDecoration(
                  labelText: '周次（如 1-16 或 1-15单周）',
                  errorText: _weeksError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _weeksError = null),
              ),
              const SizedBox(height: 16),

              // 地点
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: '地点（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: scheme.primaryColor),
                  onPressed: _confirm,
                  child: const Text('确定',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionDropdown(ThemeScheme scheme, String label, int value,
      ValueChanged<int> onChanged) {
    return InputDecorator(
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          items: [
            for (var s = 1; s <= widget.maxSection; s++)
              DropdownMenuItem(value: s, child: Text('第 $s 节')),
          ],
          onChanged: (v) => onChanged(v!),
        ),
      ),
    );
  }

  void _confirm() {
    List<int> weeks;
    try {
      weeks = WeekParser.parseWeeks(_weeksController.text);
    } on FormatException {
      setState(() => _weeksError = '周次格式不正确，如 1-16 或 1-15单周');
      return;
    }
    Navigator.pop(
      context,
      CourseSession(
        id: widget.session?.id,
        courseId: widget.session?.courseId ?? 0,
        dayOfWeek: _dayOfWeek,
        startSection: _startSection,
        sectionCount: _endSection - _startSection + 1,
        weeks: weeks,
        location: _locationController.text.trim(),
      ),
    );
  }
}
