import 'dart:convert';

/// 自定义目标
/// 
/// 完全由用户定义的目标，与日记系统无关
/// 例如：每天喝水8杯、每周运动3次、每月读书2本等
class CustomGoal {
  final String id;
  String name;                    // 目标名称（用户自定义）
  String? icon;                   // 图标emoji（可选）
  int targetCount;                // 目标数量
  int currentCount;               // 当前完成数量
  GoalPeriod period;              // 目标周期
  bool isActive;                  // 是否激活
  DateTime createdAt;
  DateTime? completedAt;          // 完成时间
  List<DailyRecord> records;      // 每日记录
  
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
  }) : createdAt = createdAt ?? DateTime.now(),
       records = records ?? [];
  
  /// 完成进度（0.0 - 1.0）
  double get progress => targetCount > 0 
      ? (currentCount / targetCount).clamp(0.0, 1.0) 
      : 0.0;
  
  /// 是否已完成
  bool get isCompleted => currentCount >= targetCount;
  
  /// 剩余数量
  int get remaining => (targetCount - currentCount).clamp(0, targetCount);
  
  /// 周期显示名称
  String get periodDisplay => period.displayName;
  
  /// 完整描述（例如：每天 8 杯）
  String get fullDescription => '${periodDisplay} ${targetCount}${unit}';
  
  /// 获取单位（根据目标名称智能判断或默认"次"）
  String get unit {
    if (name.contains('杯') || name.contains('水')) return '杯';
    if (name.contains('次') || name.contains('回')) return '次';
    if (name.contains('分钟') || name.contains('分')) return '分钟';
    if (name.contains('小时') || name.contains('时')) return '小时';
    if (name.contains('本') || name.contains('书')) return '本';
    if (name.contains('公里') || name.contains('km')) return '公里';
    if (name.contains('步')) return '步';
    if (name.contains('天')) return '天';
    return '次';
  }
  
  /// 获取今日记录
  DailyRecord? getTodayRecord() {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
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
  
  /// 增加完成次数
  void increment() {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    final existingRecord = getTodayRecord();
    if (existingRecord != null) {
      existingRecord.count++;
    } else {
      records.add(DailyRecord(date: todayStr, count: 1));
    }
    
    currentCount++;
    
    if (isCompleted && completedAt == null) {
      completedAt = DateTime.now();
    }
  }
  
  /// 减少完成次数
  void decrement() {
    if (currentCount > 0) {
      currentCount--;
    }
    
    final todayRecord = getTodayRecord();
    if (todayRecord != null && todayRecord.count > 0) {
      todayRecord.count--;
    }
    
    if (!isCompleted) {
      completedAt = null;
    }
  }
  
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
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
      records: (json['records'] as List?)
          ?.map((r) => DailyRecord.fromJson(r))
          .toList() ?? [],
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
    );
  }
}

/// 目标周期
enum GoalPeriod {
  daily,    // 每日
  weekly,   // 每周
  monthly,  // 每月
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

/// 每日记录
class DailyRecord {
  String date;      // 日期字符串（yyyy-MM-dd）
  int count;        // 完成次数
  String? note;     // 备注（可选）
  
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
  
  const GoalTemplate({
    required this.name,
    required this.icon,
    required this.targetCount,
    required this.period,
  });
  
  static const List<GoalTemplate> presets = [
    GoalTemplate(name: '喝水', icon: '💧', targetCount: 8, period: GoalPeriod.daily),
    GoalTemplate(name: '运动', icon: '🏃', targetCount: 30, period: GoalPeriod.daily),
    GoalTemplate(name: '阅读', icon: '📚', targetCount: 30, period: GoalPeriod.daily),
    GoalTemplate(name: '冥想', icon: '🧘', targetCount: 1, period: GoalPeriod.daily),
    GoalTemplate(name: '背单词', icon: '📝', targetCount: 20, period: GoalPeriod.daily),
    GoalTemplate(name: '吃水果', icon: '🍎', targetCount: 1, period: GoalPeriod.daily),
    GoalTemplate(name: '早睡早起', icon: '😴', targetCount: 1, period: GoalPeriod.daily),
    GoalTemplate(name: '跑步', icon: '🏃', targetCount: 3, period: GoalPeriod.weekly),
    GoalTemplate(name: '健身', icon: '💪', targetCount: 3, period: GoalPeriod.weekly),
    GoalTemplate(name: '读书', icon: '📖', targetCount: 2, period: GoalPeriod.monthly),
  ];
}
