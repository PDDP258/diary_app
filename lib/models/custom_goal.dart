/// 自定义目标
///
/// 完全由用户定义的目标，与日记系统无关
/// 例如：每天喝水8杯、每周运动3次、每月读书2本等
class CustomGoal {
  final String id;
  String name; // 目标名称（用户自定义）
  String? icon; // 图标emoji（可选）
  int targetCount; // 目标数量
  int currentCount; // 当前完成数量
  GoalPeriod period; // 目标周期
  bool isActive; // 是否激活
  DateTime createdAt;
  DateTime? completedAt; // 完成时间
  List<DailyRecord> records; // 每日记录
  String unit; // 单位ID（如 'times', 'minutes', 'pages'）
  String? lastResetDate; // 上次重置日期 yyyy-MM-dd，用于防止同周期重复重置

  CustomGoal({
    required this.id,
    required this.name,
    this.icon,
    required this.targetCount,
    this.currentCount = 0,
    this.period = GoalPeriod.daily,
    this.isActive = true,
    DateTime? createdAt,
    this.completedAt,
    List<DailyRecord>? records,
    this.unit = 'times',
    this.lastResetDate,
  })  : createdAt = createdAt ?? DateTime.now(),
        records = records ?? [];

  /// 完成进度（0.0 - 1.0）
  double get progress =>
      targetCount > 0 ? (currentCount / targetCount).clamp(0.0, 1.0) : 0.0;

  /// 是否已完成
  bool get isCompleted => currentCount >= targetCount;

  /// 剩余数量
  int get remaining => (targetCount - currentCount).clamp(0, targetCount);

  /// 周期显示名称
  String get periodDisplay => period.displayName;

  /// 单位显示名称
  String get unitDisplay => GoalUnit.getNameById(unit);

  /// 快捷增量值列表
  List<int> get incrementSteps => GoalUnit.getStepsById(unit);

  /// 完整描述（例如：每天 8 杯）
  String get fullDescription => '$periodDisplay $targetCount$unitDisplay';

  /// 获取今日记录
  DailyRecord? getTodayRecord() {
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    try {
      return records.firstWhere((r) => r.date == todayStr);
    } catch (e) {
      return null;
    }
  }

  /// 获取今日完成数
  int getTodayCount() {
    return getTodayRecord()?.count ?? 0;
  }

  /// 增加完成次数（按指定值）
  void incrementBy(int value) {
    if (value <= 0) return;

    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final existingRecord = getTodayRecord();
    if (existingRecord != null) {
      existingRecord.count += value;
    } else {
      records.add(DailyRecord(date: todayStr, count: value));
    }

    currentCount += value;

    if (isCompleted && completedAt == null) {
      completedAt = DateTime.now();
    }
  }

  /// 减少完成次数（按指定值）
  void decrementBy(int value) {
    if (value <= 0) return;

    final decrementValue = value > currentCount ? currentCount : value;
    if (currentCount > 0) {
      currentCount -= decrementValue;
    }

    final todayRecord = getTodayRecord();
    if (todayRecord != null && todayRecord.count > 0) {
      todayRecord.count -= decrementValue;
      if (todayRecord.count < 0) todayRecord.count = 0;
    }

    if (!isCompleted) {
      completedAt = null;
    }
  }

  /// 增加完成次数（默认+1，兼容旧逻辑）
  void increment() => incrementBy(1);

  /// 减少完成次数（默认-1，兼容旧逻辑）
  void decrement() => decrementBy(1);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'targetCount': targetCount,
        'currentCount': currentCount,
        'period': period.index,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'records': records.map((r) => r.toJson()).toList(),
        'unit': unit,
        'lastResetDate': lastResetDate,
      };

  factory CustomGoal.fromJson(Map<String, dynamic> json) {
    return CustomGoal(
      id: json['id'],
      name: json['name'],
      icon: json['icon'],
      targetCount: json['targetCount'],
      currentCount: json['currentCount'] ?? 0,
      period: GoalPeriod.values[json['period'] ?? 0],
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.parse(json['createdAt']),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
      records: (json['records'] as List?)
              ?.map((r) => DailyRecord.fromJson(r))
              .toList() ??
          [],
      unit: json['unit'] ?? 'times',
      lastResetDate: json['lastResetDate'],
    );
  }

  /// 创建副本
  CustomGoal copyWith({
    String? id,
    String? name,
    String? icon,
    int? targetCount,
    int? currentCount,
    GoalPeriod? period,
    bool? isActive,
    DateTime? createdAt,
    DateTime? completedAt,
    List<DailyRecord>? records,
    String? unit,
    String? lastResetDate,
  }) {
    return CustomGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      targetCount: targetCount ?? this.targetCount,
      currentCount: currentCount ?? this.currentCount,
      period: period ?? this.period,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      records: records ?? List.from(this.records),
      unit: unit ?? this.unit,
      lastResetDate: lastResetDate ?? this.lastResetDate,
    );
  }
}

/// 目标周期
enum GoalPeriod {
  daily, // 每日
  weekly, // 每周
  monthly, // 每月
}

extension GoalPeriodExtension on GoalPeriod {
  String get displayName {
    switch (this) {
      case GoalPeriod.daily:
        return '每天';
      case GoalPeriod.weekly:
        return '每周';
      case GoalPeriod.monthly:
        return '每月';
    }
  }

  String get shortName {
    switch (this) {
      case GoalPeriod.daily:
        return '日';
      case GoalPeriod.weekly:
        return '周';
      case GoalPeriod.monthly:
        return '月';
    }
  }
}

/// 预设单位
class GoalUnit {
  final String id;
  final String name;
  final List<int> steps;

  const GoalUnit({
    required this.id,
    required this.name,
    required this.steps,
  });

  static const List<GoalUnit> presets = [
    GoalUnit(id: 'times', name: '次', steps: [1, 5, 10]),
    GoalUnit(id: 'minutes', name: '分钟', steps: [5, 15, 30, 60]),
    GoalUnit(id: 'hours', name: '小时', steps: [1, 2, 3]),
    GoalUnit(id: 'pages', name: '页', steps: [5, 10, 20, 50]),
    GoalUnit(id: 'cups', name: '杯', steps: [1, 2]),
    GoalUnit(id: 'km', name: '公里', steps: [1, 3, 5]),
    GoalUnit(id: 'steps', name: '步', steps: [500, 1000, 3000]),
  ];

  static GoalUnit? getById(String id) {
    try {
      return presets.firstWhere((u) => u.id == id);
    } catch (e) {
      return null;
    }
  }

  static String getNameById(String id) {
    return getById(id)?.name ?? '次';
  }

  static List<int> getStepsById(String id) {
    return getById(id)?.steps ?? [1];
  }
}

/// 每日记录
class DailyRecord {
  String date; // 日期字符串（yyyy-MM-dd）
  int count; // 完成次数
  String? note; // 备注（可选）

  DailyRecord({
    required this.date,
    this.count = 0,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'count': count,
        'note': note,
      };

  factory DailyRecord.fromJson(Map<String, dynamic> json) {
    return DailyRecord(
      date: json['date'],
      count: json['count'] ?? 0,
      note: json['note'],
    );
  }
}

/// 预设目标模板
class GoalTemplate {
  final String name;
  final String icon;
  final int targetCount;
  final GoalPeriod period;
  final String unit;

  const GoalTemplate({
    required this.name,
    required this.icon,
    required this.targetCount,
    required this.period,
    this.unit = 'times',
  });

  static const List<GoalTemplate> presets = [
    GoalTemplate(
        name: '喝水', icon: '💧', targetCount: 8, period: GoalPeriod.daily, unit: 'cups'),
    GoalTemplate(
        name: '运动', icon: '🏃', targetCount: 30, period: GoalPeriod.daily, unit: 'minutes'),
    GoalTemplate(
        name: '阅读', icon: '📚', targetCount: 30, period: GoalPeriod.daily, unit: 'pages'),
    GoalTemplate(
        name: '冥想', icon: '🧘', targetCount: 1, period: GoalPeriod.daily, unit: 'times'),
    GoalTemplate(
        name: '背单词', icon: '📝', targetCount: 20, period: GoalPeriod.daily, unit: 'times'),
    GoalTemplate(
        name: '吃水果', icon: '🍎', targetCount: 1, period: GoalPeriod.daily, unit: 'times'),
    GoalTemplate(
        name: '早睡早起', icon: '😴', targetCount: 1, period: GoalPeriod.daily, unit: 'times'),
    GoalTemplate(
        name: '跑步', icon: '🏃', targetCount: 3, period: GoalPeriod.weekly, unit: 'times'),
    GoalTemplate(
        name: '健身', icon: '💪', targetCount: 3, period: GoalPeriod.weekly, unit: 'times'),
    GoalTemplate(
        name: '读书', icon: '📖', targetCount: 2, period: GoalPeriod.monthly, unit: 'times'),
  ];
}
