/// 课表领域模型
///
/// 词汇定义见 /CONTEXT.md：
/// - Course：一门课（名称/教师/颜色）
/// - CourseSession：一次上课安排（星期几 + 节次区间 + 周次集合 + 地点）
/// - SemesterConfig：学期配置（开学日、总周数、节次时间表）
library;

/// 一节课的时间定义
class SectionTime {
  final int section; // 节次序号，从 1 开始
  final String startTime; // "08:00"
  final String endTime; // "08:45"
  final bool isCustom; // 固定课时模式下勾选「自定义」后单独设置时间，不参与联动

  const SectionTime({
    required this.section,
    required this.startTime,
    required this.endTime,
    this.isCustom = false,
  });

  Map<String, dynamic> toMap() => {
        'section': section,
        'start_time': startTime,
        'end_time': endTime,
        'is_custom': isCustom ? 1 : 0,
      };

  factory SectionTime.fromMap(Map<String, dynamic> map) => SectionTime(
        section: map['section'] as int,
        startTime: map['start_time'] as String,
        endTime: map['end_time'] as String,
        isCustom: (map['is_custom'] as int? ?? 0) == 1,
      );
}

/// 课程
class Course {
  /// 课程色板：新增/导入课程按序取色，用户可再改
  static const presetColors = [
    0xFFC4956A, // 暖木棕（品牌）
    0xFFE57373, // 红
    0xFF64B5F6, // 蓝
    0xFF81C784, // 绿
    0xFFBA68C8, // 紫
    0xFFFFB74D, // 橙
    0xFF4DB6AC, // 青
    0xFF90A4AE, // 灰蓝
  ];

  final int? id;
  final String name; // 课程名，必填
  final String? teacher;
  final int color; // ARGB 颜色值
  final String? note;
  final String createdAt; // ISO8601

  /// 非持久化字段：该课程的所有上课安排（查询时组装）
  final List<CourseSession> sessions;

  Course({
    this.id,
    required this.name,
    this.teacher,
    this.color = 0xFFC4956A, // 默认品牌暖木棕
    this.note,
    String? createdAt,
    this.sessions = const [],
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'color': color,
        'note': note,
        'created_at': createdAt,
      };

  factory Course.fromMap(Map<String, dynamic> map) => Course(
        id: map['id'] as int?,
        name: map['name'] as String,
        teacher: map['teacher'] as String?,
        color: (map['color'] as int?) ?? 0xFFC4956A,
        note: map['note'] as String?,
        createdAt: map['created_at'] as String?,
      );

  Course copyWith({
    int? id,
    String? name,
    String? teacher,
    int? color,
    String? note,
    List<CourseSession>? sessions,
  }) =>
      Course(
        id: id ?? this.id,
        name: name ?? this.name,
        teacher: teacher ?? this.teacher,
        color: color ?? this.color,
        note: note ?? this.note,
        createdAt: createdAt,
        sessions: sessions ?? this.sessions,
      );
}

/// 上课安排
class CourseSession {
  final int? id;
  final int courseId;
  final int dayOfWeek; // 1=周一 ... 7=周日
  final int startSection; // 起始节次
  final int sectionCount; // 连上节数
  final List<int> weeks; // 周次集合，已解析为 List<int>
  final String? location;

  CourseSession({
    this.id,
    required this.courseId,
    required this.dayOfWeek,
    required this.startSection,
    this.sectionCount = 1,
    required this.weeks,
    this.location,
  });

  int get endSection => startSection + sectionCount - 1;

  /// 指定教学周、星期几是否有这次课
  bool occursOn(int week, int day) =>
      dayOfWeek == day && weeks.contains(week);

  Map<String, dynamic> toMap() => {
        'id': id,
        'course_id': courseId,
        'day_of_week': dayOfWeek,
        'start_section': startSection,
        'section_count': sectionCount,
        'weeks': weeks.join(','),
        'location': location,
      };

  factory CourseSession.fromMap(Map<String, dynamic> map) => CourseSession(
        id: map['id'] as int?,
        courseId: map['course_id'] as int,
        dayOfWeek: map['day_of_week'] as int,
        startSection: map['start_section'] as int,
        sectionCount: (map['section_count'] as int?) ?? 1,
        weeks: (map['weeks'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .map(int.parse)
            .toList(),
        location: map['location'] as String?,
      );

  CourseSession copyWith({
    int? id,
    int? courseId,
    int? dayOfWeek,
    int? startSection,
    int? sectionCount,
    List<int>? weeks,
    String? location,
  }) =>
      CourseSession(
        id: id ?? this.id,
        courseId: courseId ?? this.courseId,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startSection: startSection ?? this.startSection,
        sectionCount: sectionCount ?? this.sectionCount,
        weeks: weeks ?? this.weeks,
        location: location ?? this.location,
      );
}

/// 学期配置（同一时间只有一个 isActive）
class SemesterConfig {
  final int? id;
  final String name; // 如 "2026 秋季学期"
  final String startDate; // 第 1 周周一，ISO8601 日期 "yyyy-MM-dd"
  final int totalWeeks;
  final List<SectionTime> sections;
  final bool isActive;
  final bool fixedDurationMode; // 固定课时模式：改上课时间自动联动下课与后续节次
  final int classMinutes; // 固定课时时长（分钟）

  SemesterConfig({
    this.id,
    required this.name,
    required this.startDate,
    this.totalWeeks = 20,
    this.sections = defaultSections,
    this.isActive = true,
    this.fixedDurationMode = true,
    this.classMinutes = 45,
  });

  /// 默认节次时间（夏季作息：上午 8:00-11:50、下午 14:30-18:10、晚上 19:30-21:05）
  static const defaultSections = [
    SectionTime(section: 1, startTime: '08:00', endTime: '08:45'),
    SectionTime(section: 2, startTime: '08:55', endTime: '09:40'),
    SectionTime(section: 3, startTime: '10:10', endTime: '10:55'),
    SectionTime(section: 4, startTime: '11:05', endTime: '11:50'),
    SectionTime(section: 5, startTime: '14:30', endTime: '15:15'),
    SectionTime(section: 6, startTime: '15:25', endTime: '16:10'),
    SectionTime(section: 7, startTime: '16:30', endTime: '17:15'),
    SectionTime(section: 8, startTime: '17:25', endTime: '18:10'),
    SectionTime(section: 9, startTime: '19:30', endTime: '20:15'),
    SectionTime(section: 10, startTime: '20:20', endTime: '21:05'),
  ];

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start_date': startDate,
        'total_weeks': totalWeeks,
        'sections': sections.map((s) => s.toMap()).toList(),
        'is_active': isActive ? 1 : 0,
        'fixed_duration_mode': fixedDurationMode ? 1 : 0,
        'class_minutes': classMinutes,
      };

  factory SemesterConfig.fromMap(Map<String, dynamic> map) => SemesterConfig(
        id: map['id'] as int?,
        name: map['name'] as String,
        startDate: map['start_date'] as String,
        totalWeeks: (map['total_weeks'] as int?) ?? 20,
        sections: ((map['sections'] as List?) ?? [])
            .map((e) => SectionTime.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        isActive: (map['is_active'] as int? ?? 1) == 1,
        fixedDurationMode: (map['fixed_duration_mode'] as int? ?? 1) == 1,
        classMinutes: (map['class_minutes'] as int?) ?? 45,
      );
}
