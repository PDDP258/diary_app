import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/course.dart';
import '../providers/course_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/section_schedule.dart';

/// 学期配置页：开学日期、总周数、节次时间
///
/// 节次时间支持「固定课时模式」：修改某节上课时间自动调整下课时间，
/// 后续节次保持原有课间间隔顺延；每节可勾选「自定义」单独设置。
class SemesterSettingsScreen extends StatefulWidget {
  const SemesterSettingsScreen({super.key});

  @override
  State<SemesterSettingsScreen> createState() => _SemesterSettingsScreenState();
}

class _SemesterSettingsScreenState extends State<SemesterSettingsScreen> {
  final _nameController = TextEditingController();
  DateTime _startDate = DateTime.now();
  int _totalWeeks = 20;
  late List<SectionTime> _sections;
  bool _fixedDurationMode = true;
  int _classMinutes = 45;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _initFrom(SemesterConfig? existing) {
    if (_initialized) return;
    _initialized = true;
    if (existing != null) {
      _nameController.text = existing.name;
      _startDate = DateTime.parse(existing.startDate);
      _totalWeeks = existing.totalWeeks;
      _sections = List.of(existing.sections);
      _fixedDurationMode = existing.fixedDurationMode;
      _classMinutes = existing.classMinutes;
    } else {
      _nameController.text = _defaultSemesterName();
      // 默认对齐到本周一
      final now = DateTime.now();
      _startDate = now.subtract(Duration(days: now.weekday - 1));
      _sections = List.of(SemesterConfig.defaultSections);
    }
  }

  String _defaultSemesterName() {
    final now = DateTime.now();
    // 2-7 月视为春季学期，其余为秋季
    final season = (now.month >= 2 && now.month <= 7) ? '春季' : '秋季';
    return '${now.year} $season学期';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final provider = context.watch<CourseProvider>();
    _initFrom(provider.semester);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        title: Text('学期设置', style: TextStyle(color: scheme.textDarkColor)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
        actions: [
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
            _textField(scheme, _nameController, '学期名称', Icons.badge_outlined),
            const Divider(height: 24),
            _dateRow(scheme),
            const Divider(height: 24),
            _weeksRow(scheme),
          ]),
          const SizedBox(height: 16),
          _card(scheme, [
            _presetHeader(scheme),
            const SizedBox(height: 8),
            _fixedDurationRow(scheme),
            if (_fixedDurationMode) ...[
              const Divider(height: 20),
              _classMinutesRow(scheme),
            ],
          ]),
          const SizedBox(height: 16),
          _card(scheme, [
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: scheme.textMediumColor),
                const SizedBox(width: 8),
                Text('节次时间',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addSection,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('加一节'),
                  style: TextButton.styleFrom(
                      foregroundColor: scheme.primaryColor),
                ),
              ],
            ),
            if (_fixedDurationMode)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text('修改上课时间会自动调整下课时间，后续节次按原课间间隔顺延',
                    style: TextStyle(fontSize: 12, color: scheme.textLightColor)),
              )
            else
              const SizedBox(height: 8),
            for (var i = 0; i < _sections.length; i++) _sectionRow(scheme, i),
          ]),
        ],
      ),
    );
  }

  Widget _presetHeader(ThemeScheme scheme) {
    return Row(
      children: [
        Icon(Icons.wb_sunny_outlined, size: 18, color: scheme.textMediumColor),
        const SizedBox(width: 8),
        Text('作息预设',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor)),
        const Spacer(),
        _presetButton(scheme, '夏季作息', SectionSchedule.summer),
        const SizedBox(width: 8),
        _presetButton(scheme, '冬季作息', SectionSchedule.winter),
      ],
    );
  }

  Widget _presetButton(
      ThemeScheme scheme, String label, List<SectionTime> preset) {
    return OutlinedButton(
      onPressed: () => setState(() => _sections = List.of(preset)),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primaryColor,
        side: BorderSide(color: scheme.primaryColor.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _fixedDurationRow(ThemeScheme scheme) {
    return Row(
      children: [
        Icon(Icons.timelapse, size: 18, color: scheme.textMediumColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text('固定课时模式',
              style: TextStyle(fontSize: 15, color: scheme.textDarkColor)),
        ),
        Switch(
          value: _fixedDurationMode,
          activeColor: scheme.primaryColor,
          onChanged: (v) => setState(() => _fixedDurationMode = v),
        ),
      ],
    );
  }

  Widget _classMinutesRow(ThemeScheme scheme) {
    return Row(
      children: [
        Icon(Icons.hourglass_bottom, size: 18, color: scheme.textMediumColor),
        const SizedBox(width: 8),
        Text('每节课时长',
            style: TextStyle(fontSize: 15, color: scheme.textDarkColor)),
        Expanded(
          child: Slider(
            value: _classMinutes.toDouble(),
            min: 30,
            max: 60,
            divisions: 6,
            activeColor: scheme.primaryColor,
            onChanged: (v) => setState(() {
              _classMinutes = (v / 5).round() * 5;
              _sections = SectionSchedule.applyDuration(_sections, _classMinutes);
            }),
          ),
        ),
        Text('$_classMinutes 分钟',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.primaryColor)),
      ],
    );
  }

  Widget _card(ThemeScheme scheme, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: scheme.shadowColor, blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _textField(ThemeScheme scheme, TextEditingController controller,
      String label, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: scheme.textMediumColor),
        border: InputBorder.none,
      ),
    );
  }

  Widget _dateRow(ThemeScheme scheme) {
    final text =
        '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';
    final weekday = '周${['一', '二', '三', '四', '五', '六', '日'][_startDate.weekday - 1]}';
    return InkWell(
      onTap: _pickStartDate,
      child: Row(
        children: [
          Icon(Icons.event, size: 18, color: scheme.textMediumColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('开学日期（第 1 周周一）',
                    style: TextStyle(
                        fontSize: 13, color: scheme.textMediumColor)),
                Text('$text $weekday',
                    style: TextStyle(
                        fontSize: 15,
                        color: scheme.textDarkColor,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.textLightColor),
        ],
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Widget _weeksRow(ThemeScheme scheme) {
    return Row(
      children: [
        Icon(Icons.view_week_outlined, size: 18, color: scheme.textMediumColor),
        const SizedBox(width: 8),
        Text('总周数', style: TextStyle(fontSize: 15, color: scheme.textDarkColor)),
        Expanded(
          child: Slider(
            value: _totalWeeks.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            activeColor: scheme.primaryColor,
            onChanged: (v) => setState(() => _totalWeeks = v.round()),
          ),
        ),
        Text('$_totalWeeks 周',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.primaryColor)),
      ],
    );
  }

  Widget _sectionRow(ThemeScheme scheme, int index) {
    final s = _sections[index];
    // 固定课时模式下，非自定义节次的下课时间自动计算、不可单独编辑
    final endEditable = !_fixedDurationMode || s.isCustom;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text('第 ${s.section} 节',
                style: TextStyle(fontSize: 14, color: scheme.textDarkColor)),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _pickSectionTime(index, true),
              child: _timeChip(scheme, s.startTime, true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('-', style: TextStyle(color: scheme.textLightColor)),
          ),
          Expanded(
            child: InkWell(
              onTap: endEditable ? () => _pickSectionTime(index, false) : null,
              child: _timeChip(scheme, s.endTime, endEditable),
            ),
          ),
          // 自定义开关（不起眼的小图标）：固定课时模式下可单独设置本节时间
          if (_fixedDurationMode)
            IconButton(
              icon: Icon(Icons.tune,
                  size: 16,
                  color: s.isCustom
                      ? scheme.primaryColor
                      : scheme.textLightColor),
              tooltip: s.isCustom ? '恢复联动' : '单独设置此节时间',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _sections[index] = SectionTime(
                  section: s.section,
                  startTime: s.startTime,
                  endTime: s.endTime,
                  isCustom: !s.isCustom,
                );
              }),
            ),
          if (_sections.length > 1)
            IconButton(
              icon: Icon(Icons.remove_circle_outline,
                  size: 18, color: scheme.errorColor),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _sections.removeAt(index)),
            ),
        ],
      ),
    );
  }

  Widget _timeChip(ThemeScheme scheme, String time, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled
            ? scheme.backgroundColor
            : scheme.backgroundColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(time,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: enabled ? scheme.textDarkColor : scheme.textLightColor)),
    );
  }

  Future<void> _pickSectionTime(int index, bool isStart) async {
    final s = _sections[index];
    final current = isStart ? s.startTime : s.endTime;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    final text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (_fixedDurationMode && isStart) {
        // 固定课时：改上课自动联动下课与后续节次
        _sections =
            SectionSchedule.cascadeFrom(_sections, index, text, _classMinutes);
      } else {
        _sections[index] = isStart
            ? SectionTime(
                section: s.section,
                startTime: text,
                endTime: s.endTime,
                isCustom: s.isCustom)
            : SectionTime(
                section: s.section,
                startTime: s.startTime,
                endTime: text,
                isCustom: s.isCustom);
      }
    });
  }

  void _addSection() {
    final last = _sections.last;
    setState(() {
      _sections.add(_fixedDurationMode
          ? SectionSchedule.nextAfter(last, _classMinutes)
          : SectionTime(
              section: last.section + 1,
              startTime: last.endTime,
              endTime: last.endTime));
    });
  }

  Future<void> _save() async {
    final provider = context.read<CourseProvider>();
    final dateText =
        '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';
    await provider.saveSemester(SemesterConfig(
      id: provider.semester?.id,
      name: _nameController.text.trim().isEmpty
          ? _defaultSemesterName()
          : _nameController.text.trim(),
      startDate: dateText,
      totalWeeks: _totalWeeks,
      sections: _sections,
      fixedDurationMode: _fixedDurationMode,
      classMinutes: _classMinutes,
    ));
    if (mounted) Navigator.pop(context);
  }
}
