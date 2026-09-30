/// 桌面小组件的「预计算计划」
///
/// **为什么要把课表提前算成一张日期表**：Android 桌面小组件由系统广播唤醒
/// （开机、`updatePeriodMillis` 定时、用户添加/缩放），这些时机 App 进程
/// 往往根本不存在 —— 那时读不了 SQLite，也算不出「今天第几教学周」。
///
/// 所以 Dart 侧一次性把未来 [CourseWidgetPlan.defaultHorizonDays] 天里
/// 「每天上什么课、几点几分开始结束」算好交给原生侧存着；原生侧刷新时
/// 只需要按 `yyyy-MM-dd` 查表渲染，不需要任何业务逻辑，也不需要拉起 Flutter。
///
/// 这也是修掉「开机后小组件还显示昨天」的关键：原生侧不再依赖 App 是否前台。
library;

import '../models/course.dart';
import '../utils/week_parser.dart';

/// 一天里的一节课（已经把节次换算成钟点与分钟数）
class CourseWidgetItem {
  /// 展示用的开始时间，如 `"10:10"`；节次无对应时间时退化为 `"第3节"`
  final String time;

  /// 开始 / 结束时刻距零点的分钟数；节次时间表里没有该节次时为 null。
  /// 原生侧靠它判断「已上完 / 正在上」，不需要自己解析时钟。
  final int? startMinutes;
  final int? endMinutes;

  /// 起始节次
  final int section;

  final String name;

  /// 地点，可为空串
  final String location;

  /// 课程颜色（ARGB）
  final int color;

  const CourseWidgetItem({
    required this.time,
    this.startMinutes,
    this.endMinutes,
    required this.section,
    required this.name,
    this.location = '',
    required this.color,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'startMin': startMinutes,
        'endMin': endMinutes,
        'section': section,
        'name': name,
        'location': location,
        'color': color,
      };

  factory CourseWidgetItem.fromJson(Map<String, dynamic> json) =>
      CourseWidgetItem(
        time: (json['time'] as String?) ?? '',
        startMinutes: (json['startMin'] as num?)?.toInt(),
        endMinutes: (json['endMin'] as num?)?.toInt(),
        section: (json['section'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        location: (json['location'] as String?) ?? '',
        color: (json['color'] as num?)?.toInt() ?? 0xFFC4956A,
      );
}

/// 计划里的一天
class CourseWidgetDay {
  /// `yyyy-MM-dd`，原生侧按这个键查今天
  final String date;

  /// 教学周；学期外为 null（假期）
  final int? week;

  /// 1 = 周一 … 7 = 周日
  final int weekday;

  final List<CourseWidgetItem> items;

  const CourseWidgetDay({
    required this.date,
    required this.week,
    required this.weekday,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'week': week,
        'weekday': weekday,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory CourseWidgetDay.fromJson(Map<String, dynamic> json) => CourseWidgetDay(
        date: (json['date'] as String?) ?? '',
        week: (json['week'] as num?)?.toInt(),
        weekday: (json['weekday'] as num?)?.toInt() ?? 1,
        items: ((json['items'] as List?) ?? [])
            .map((e) => CourseWidgetItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// 小组件配色 —— 由 App 当前主题推出来，让小组件跟着 App 换肤
///
/// 不给原生侧写死颜色：主题有 5 套预设 + 自定义，写死必然与 App 不一致。
class CourseWidgetTheme {
  final int background;
  final int foreground;
  final int secondary;
  final int accent;

  /// 分割线 / 浅色板（用主题的 lightColor，暖纸风里是浅米色）
  final int divider;

  const CourseWidgetTheme({
    required this.background,
    required this.foreground,
    required this.secondary,
    required this.accent,
    required this.divider,
  });

  /// 暖纸白 + 暖木棕：跟品牌视觉语言一致的兜底配色
  static const fallback = CourseWidgetTheme(
    background: 0xFFFDF8F0,
    foreground: 0xFF2C241F,
    secondary: 0xFF8A7D6F,
    accent: 0xFFC4956A,
    divider: 0xFFF5E6D3,
  );

  Map<String, dynamic> toJson() => {
        'background': background,
        'foreground': foreground,
        'secondary': secondary,
        'accent': accent,
        'divider': divider,
      };

  factory CourseWidgetTheme.fromJson(Map<String, dynamic> json) =>
      CourseWidgetTheme(
        background: (json['background'] as num?)?.toInt() ??
            fallback.background,
        foreground: (json['foreground'] as num?)?.toInt() ??
            fallback.foreground,
        secondary: (json['secondary'] as num?)?.toInt() ?? fallback.secondary,
        accent: (json['accent'] as num?)?.toInt() ?? fallback.accent,
        divider: (json['divider'] as num?)?.toInt() ?? fallback.divider,
      );
}

/// 交给原生侧存起来、供小组件刷新的完整计划
class CourseWidgetPlan {
  /// 计划格式版本：原生侧据此判断自己认不认这份数据
  ///
  /// 与原生 `CourseWidgetPlan.SCHEMA_VERSION` 必须一致；
  /// 改字段结构时两边一起加一，原生侧就会把不认的版本当「没数据」。
  static const currentSchemaVersion = 1;

  /// 预计算天数。14 天足够覆盖「过年回家两周没开 App」，
  /// 又不会让 JSON 太大（每天最多十来条）。
  static const defaultHorizonDays = 14;

  final int schemaVersion;
  final bool hasSemester;
  final String semesterName;

  /// 生成时刻（ISO8601），原生侧用它判断数据新不新
  final String generatedAt;

  /// 窗口首日 / 末日（`yyyy-MM-dd`），用于判断「今天是否落在计划里」
  final String rangeStart;
  final String rangeEnd;

  final List<CourseWidgetDay> days;
  final CourseWidgetTheme theme;

  const CourseWidgetPlan({
    this.schemaVersion = currentSchemaVersion,
    required this.hasSemester,
    required this.semesterName,
    required this.generatedAt,
    required this.rangeStart,
    required this.rangeEnd,
    required this.days,
    required this.theme,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'hasSemester': hasSemester,
        'semesterName': semesterName,
        'generatedAt': generatedAt,
        'rangeStart': rangeStart,
        'rangeEnd': rangeEnd,
        'days': days.map((e) => e.toJson()).toList(),
        'theme': theme.toJson(),
      };

  factory CourseWidgetPlan.fromJson(Map<String, dynamic> json) =>
      CourseWidgetPlan(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
        hasSemester: json['hasSemester'] == true,
        semesterName: (json['semesterName'] as String?) ?? '',
        generatedAt: (json['generatedAt'] as String?) ?? '',
        rangeStart: (json['rangeStart'] as String?) ?? '',
        rangeEnd: (json['rangeEnd'] as String?) ?? '',
        days: ((json['days'] as List?) ?? [])
            .map((e) => CourseWidgetDay.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        theme: CourseWidgetTheme.fromJson(
          Map<String, dynamic>.from((json['theme'] as Map?) ?? const {}),
        ),
      );

  /// 空计划：没有学期配置、或还没导入课表时推它，让小组件显示引导文案
  /// 而不是停在上一份过期的数据上。
  static CourseWidgetPlan empty({CourseWidgetTheme? theme}) {
    final now = DateTime.now();
    return CourseWidgetPlan(
      hasSemester: false,
      semesterName: '',
      generatedAt: now.toIso8601String(),
      rangeStart: _dateKey(now),
      rangeEnd: _dateKey(now),
      days: const [],
      theme: theme ?? CourseWidgetTheme.fallback,
    );
  }

  /// 生成计划
  ///
  /// [from] 只用于测试注入；默认从「今天」起算。
  static CourseWidgetPlan build({
    required List<Course> courses,
    required SemesterConfig? semester,
    required CourseWidgetTheme theme,
    DateTime? from,
    int horizonDays = defaultHorizonDays,
  }) {
    final now = from ?? DateTime.now();
    if (semester == null) return empty(theme: theme);

    final semesterStart = DateTime.tryParse(semester.startDate);
    if (semesterStart == null) return empty(theme: theme);

    // 节次序号 → 起止时间
    final sectionById = {for (final s in semester.sections) s.section: s};

    final days = <CourseWidgetDay>[];
    for (var offset = 0; offset < horizonDays; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      final week = WeekParser.currentWeek(
        semesterStart: semesterStart,
        totalWeeks: semester.totalWeeks,
        date: day,
      );

      final items = <CourseWidgetItem>[];
      if (week != null) {
        for (final c in courses) {
          for (final s in c.sessions) {
            if (!s.occursOn(week, day.weekday)) continue;
            final st = sectionById[s.startSection];
            items.add(CourseWidgetItem(
              time: st?.startTime ?? '第${s.startSection}节',
              startMinutes: st == null ? null : _minutes(st.startTime),
              endMinutes: st == null ? null : _minutes(st.endTime),
              section: s.startSection,
              name: c.name,
              location: s.location ?? '',
              color: c.color,
            ));
          }
        }
        items.sort((a, b) {
          final bySection = a.section.compareTo(b.section);
          if (bySection != 0) return bySection;
          return a.name.compareTo(b.name);
        });
      }

      days.add(CourseWidgetDay(
        date: _dateKey(day),
        week: week,
        weekday: day.weekday,
        items: items,
      ));
    }

    return CourseWidgetPlan(
      hasSemester: true,
      semesterName: semester.name,
      generatedAt: now.toIso8601String(),
      rangeStart: days.first.date,
      rangeEnd: days.last.date,
      days: days,
      theme: theme,
    );
  }

  /// 取某天（`yyyy-MM-dd`）
  CourseWidgetDay? dayFor(String dateKey) {
    for (final d in days) {
      if (d.date == dateKey) return d;
    }
    return null;
  }

  /// 只换配色、其余原样 —— 用户切主题时不必重新算一遍两周课表
  CourseWidgetPlan withTheme(CourseWidgetTheme newTheme) => CourseWidgetPlan(
        schemaVersion: schemaVersion,
        hasSemester: hasSemester,
        semesterName: semesterName,
        generatedAt: generatedAt,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: days,
        theme: newTheme,
      );

  /// `yyyy-MM-dd`
  static String dateKey(DateTime d) => _dateKey(d);

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// `"10:10"` → 610；格式不对返回 null
  static int? _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}
