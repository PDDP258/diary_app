import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'gacha_service.dart';

/// 目标类型
enum GoalType {
  diaryCount,    // 日记篇数
  wordCount,     // 总字数
  streakDays,    // 连续天数
  photoCount,    // 照片数量
}

extension GoalTypeExtension on GoalType {
  String get displayName {
    switch (this) {
      case GoalType.diaryCount:
        return '日记篇数';
      case GoalType.wordCount:
        return '总字数';
      case GoalType.streakDays:
        return '连续记录';
      case GoalType.photoCount:
        return '照片数量';
    }
  }
  
  String get unit {
    switch (this) {
      case GoalType.diaryCount:
        return '篇';
      case GoalType.wordCount:
        return '字';
      case GoalType.streakDays:
        return '天';
      case GoalType.photoCount:
        return '张';
    }
  }
  
  IconData get icon {
    switch (this) {
      case GoalType.diaryCount:
        return Icons.edit_note;
      case GoalType.wordCount:
        return Icons.text_fields;
      case GoalType.streakDays:
        return Icons.local_fire_department;
      case GoalType.photoCount:
        return Icons.photo_camera;
    }
  }
}

/// 月度目标
class MonthlyGoal {
  final int year;
  final int month;
  final int targetCount;
  final GoalType type;
  int completedCount;
  int currentStreak;
  int longestStreak;
  bool isCompleted;
  DateTime? completedAt;
  DateTime createdAt;
  
  MonthlyGoal({
    required this.year,
    required this.month,
    this.targetCount = 12,
    this.type = GoalType.diaryCount,
    this.completedCount = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.isCompleted = false,
    this.completedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  /// 完成百分比
  double get progress => targetCount > 0 
      ? (completedCount / targetCount).clamp(0.0, 1.0) 
      : 0.0;
  
  /// 剩余数量
  int get remaining => (targetCount - completedCount).clamp(0, targetCount);
  
  /// 是否即将完成（还差1-2个）
  bool get isAlmostComplete => remaining > 0 && remaining <= 2;
  
  Map<String, dynamic> toJson() => {
    'year': year,
    'month': month,
    'targetCount': targetCount,
    'type': type.index,
    'completedCount': completedCount,
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
    'isCompleted': isCompleted,
    'completedAt': completedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory MonthlyGoal.fromJson(Map<String, dynamic> json) => MonthlyGoal(
    year: json['year'],
    month: json['month'],
    targetCount: json['targetCount'],
    type: GoalType.values[json['type']],
    completedCount: json['completedCount'] ?? 0,
    currentStreak: json['currentStreak'] ?? 0,
    longestStreak: json['longestStreak'] ?? 0,
    isCompleted: json['isCompleted'] ?? false,
    completedAt: json['completedAt'] != null 
        ? DateTime.parse(json['completedAt'])
        : null,
    createdAt: DateTime.parse(json['createdAt']),
  );
}

/// 目标服务
class GoalService {
  static const String _goalKey = 'monthly_goal';
  static const String _goalHistoryKey = 'goal_history';
  
  /// 获取当前月目标
  static Future<MonthlyGoal> getCurrentGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = '$_goalKey${now.year}_${now.month}';
    
    final jsonStr = prefs.getString(key);
    if (jsonStr != null) {
      final goal = MonthlyGoal.fromJson(jsonDecode(jsonStr));
      // 更新完成进度
      await _updateProgress(goal);
      return goal;
    }
    
    // 创建默认目标
    final defaultGoal = MonthlyGoal(
      year: now.year,
      month: now.month,
      targetCount: 12,
      type: GoalType.diaryCount,
    );
    await _updateProgress(defaultGoal);
    return defaultGoal;
  }
  
  /// 获取指定月份目标
  static Future<MonthlyGoal> getGoal(int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_goalKey${year}_$month';
    
    final jsonStr = prefs.getString(key);
    if (jsonStr != null) {
      return MonthlyGoal.fromJson(jsonDecode(jsonStr));
    }
    
    return MonthlyGoal(
      year: year,
      month: month,
      targetCount: 12,
    );
  }
  
  /// 设置目标
  static Future<void> setGoal(MonthlyGoal goal) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_goalKey${goal.year}_${goal.month}';
    await prefs.setString(key, jsonEncode(goal.toJson()));
  }
  
  /// 更新目标进度
  static Future<void> _updateProgress(MonthlyGoal goal) async {
    final now = DateTime.now();
    // 只更新当前月或过去月的进度
    if (goal.year > now.year || (goal.year == now.year && goal.month > now.month)) {
      return;
    }
    
    final diaries = await DatabaseService.getDiariesByMonth(goal.year, goal.month);
    
    switch (goal.type) {
      case GoalType.diaryCount:
        goal.completedCount = diaries.length;
        break;
      case GoalType.wordCount:
        goal.completedCount = diaries.fold(0, (sum, d) => sum + (d.wordCount));
        break;
      case GoalType.photoCount:
        goal.completedCount = diaries.fold(0, (sum, d) => sum + (d.images?.length ?? 0));
        break;
      case GoalType.streakDays:
        goal.completedCount = await _calculateStreakDays();
        break;
    }
    
    // 检查是否完成
    if (goal.completedCount >= goal.targetCount && !goal.isCompleted) {
      goal.isCompleted = true;
      goal.completedAt = DateTime.now();
    }
    
    // 计算连续天数
    goal.currentStreak = await _calculateCurrentStreak();
    if (goal.currentStreak > goal.longestStreak) {
      goal.longestStreak = goal.currentStreak;
    }
    
    await setGoal(goal);
  }
  
  /// 计算连续记录天数
  static Future<int> _calculateStreakDays() async {
    // 获取所有日记日期
    final diaries = await DatabaseService.getAllDiaries();
    final dates = diaries.map((d) => d.date).toSet()..toList();
    
    if (dates.isEmpty) return 0;
    
    // 按日期排序
    final sortedDates = dates.map((d) {
      final parts = d.split('-');
      return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    }).toList()..sort();
    
    int maxStreak = 1;
    int currentStreak = 1;
    
    for (int i = 1; i < sortedDates.length; i++) {
      final diff = sortedDates[i].difference(sortedDates[i - 1]).inDays;
      if (diff == 1) {
        currentStreak++;
        if (currentStreak > maxStreak) {
          maxStreak = currentStreak;
        }
      } else if (diff > 1) {
        currentStreak = 1;
      }
    }
    
    return maxStreak;
  }
  
  /// 计算当前连续天数（从今天倒推）
  static Future<int> _calculateCurrentStreak() async {
    final now = DateTime.now();
    int streak = 0;
    
    for (int i = 0; i < 365; i++) {
      final date = now.subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final diaries = await DatabaseService.getDiariesByDate(dateStr);
      
      if (diaries.isNotEmpty) {
        streak++;
      } else if (i > 0) {
        // 今天没写不算断，但昨天没写就断了
        break;
      }
    }
    
    return streak;
  }
  
  /// 获取历史目标（最近12个月）
  static Future<List<MonthlyGoal>> getGoalHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final goals = <MonthlyGoal>[];
    
    for (int i = 0; i < 12; i++) {
      final month = now.month - i;
      final year = now.year + (month <= 0 ? -1 : 0);
      final actualMonth = month <= 0 ? month + 12 : month;
      
      final goal = await getGoal(year, actualMonth);
      goals.add(goal);
    }
    
    return goals;
  }
  
  /// 获取目标达成率统计
  static Future<Map<String, dynamic>> getGoalStats() async {
    final history = await getGoalHistory();
    final completed = history.where((g) => g.isCompleted).length;
    final total = history.length;
    
    return {
      'total': total,
      'completed': completed,
      'rate': total > 0 ? (completed / total * 100).round() : 0,
      'averageProgress': history.isNotEmpty
          ? history.map((g) => g.progress).reduce((a, b) => a + b) / history.length
          : 0.0,
    };
  }
  
  /// 检查今天是否已完成日记（用于连续天数计算）
  static Future<bool> hasWrittenToday() async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final diaries = await DatabaseService.getDiariesByDate(dateStr);
    return diaries.isNotEmpty;
  }
  
  // ==================== 目标提醒功能 ====================
  
  static const String _goalReminderKey = 'goal_reminder_settings';
  static const String _lastReminderKey = 'last_goal_reminder';
  
  /// 获取提醒设置
  static Future<GoalReminderSettings> getReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_goalReminderKey);
    if (jsonStr != null) {
      return GoalReminderSettings.fromJson(jsonDecode(jsonStr));
    }
    return GoalReminderSettings.defaultSettings();
  }
  
  /// 保存提醒设置
  static Future<void> saveReminderSettings(GoalReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_goalReminderKey, jsonEncode(settings.toJson()));
  }
  
  /// 检查是否需要提醒
  static Future<List<GoalReminder>> checkReminders() async {
    final reminders = <GoalReminder>[];
    final settings = await getReminderSettings();
    
    if (!settings.enabled) return reminders;
    
    final goal = await getCurrentGoal();
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final remainingDays = daysInMonth - now.day;
    
    // 1. 目标进度提醒
    if (settings.remindProgress && remainingDays <= 3 && !goal.isCompleted) {
      final dailyNeed = (goal.remaining / remainingDays).ceil();
      if (dailyNeed > 1) {
        reminders.add(GoalReminder(
          type: GoalReminderType.progress,
          title: '目标冲刺',
          message: '本月还剩$remainingDays天，每天需写$dailyNeed篇才能完成目标',
          priority: remainingDays == 1 ? 3 : 2,
        ));
      }
    }
    
    // 2. 即将完成提醒
    if (settings.remindAlmostComplete && goal.isAlmostComplete && !goal.isCompleted) {
      reminders.add(GoalReminder(
        type: GoalReminderType.almostComplete,
        title: '即将达成',
        message: '还差${goal.remaining}篇就完成本月目标了，加油！',
        priority: 2,
      ));
    }
    
    // 3. 连续记录提醒
    if (settings.remindStreak) {
      final hasToday = await hasWrittenToday();
      if (!hasToday && goal.currentStreak > 0) {
        final hour = now.hour;
        String message;
        int priority;
        
        if (hour >= 20) {
          message = '今晚还没写日记哦，连续记录${goal.currentStreak}天即将中断！';
          priority = 3;
        } else if (hour >= 18) {
          message = '记得写日记，保持${goal.currentStreak}天连续记录！';
          priority = 2;
        } else {
          message = '今天别忘了写日记，继续${goal.currentStreak}天的坚持！';
          priority = 1;
        }
        
        reminders.add(GoalReminder(
          type: GoalReminderType.streak,
          title: '连续记录提醒',
          message: message,
          priority: priority,
        ));
      }
    }
    
    // 4. 目标达成庆祝提醒
    if (settings.remindAchievement && goal.isCompleted) {
      final prefs = await SharedPreferences.getInstance();
      final lastKey = '${_lastReminderKey}_achievement_${now.year}_${now.month}';
      final lastReminded = prefs.getBool(lastKey) ?? false;
      
      if (!lastReminded) {
        reminders.add(GoalReminder(
          type: GoalReminderType.achievement,
          title: '🎉 目标达成',
          message: '恭喜你完成本月目标！获得奖励扭蛋1次！',
          priority: 3,
        ));
        await prefs.setBool(lastKey, true);
        // 奖励扭蛋
        await GachaService.addDraws(1);
      }
    }
    
    return reminders..sort((a, b) => b.priority.compareTo(a.priority));
  }
  
  /// 标记提醒已显示
  static Future<void> markReminderShown(GoalReminderType type) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = '${_lastReminderKey}_${type.name}_${now.year}_${now.month}_${now.day}';
    await prefs.setBool(key, true);
  }
  
  /// 检查今日是否已提醒
  static Future<bool> hasRemindedToday(GoalReminderType type) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = '${_lastReminderKey}_${type.name}_${now.year}_${now.month}_${now.day}';
    return prefs.getBool(key) ?? false;
  }
}

/// 目标预设选项
class GoalPreset {
  final int target;
  final String label;
  final String description;
  
  const GoalPreset({
    required this.target,
    required this.label,
    required this.description,
  });
  
  static const List<GoalPreset> diaryCountPresets = [
    GoalPreset(target: 8, label: '轻松', description: '每周2篇'),
    GoalPreset(target: 12, label: '标准', description: '每周3篇'),
    GoalPreset(target: 20, label: '勤奋', description: '每周5篇'),
    GoalPreset(target: 30, label: '日更', description: '每天1篇'),
  ];
  
  static const List<GoalPreset> wordCountPresets = [
    GoalPreset(target: 1000, label: '轻松', description: '每天30字'),
    GoalPreset(target: 3000, label: '标准', description: '每天100字'),
    GoalPreset(target: 6000, label: '勤奋', description: '每天200字'),
    GoalPreset(target: 15000, label: '作家', description: '每天500字'),
  ];
  
  static List<GoalPreset> getPresets(GoalType type) {
    switch (type) {
      case GoalType.diaryCount:
        return diaryCountPresets;
      case GoalType.wordCount:
        return wordCountPresets;
      case GoalType.streakDays:
        return [
          const GoalPreset(target: 7, label: '一周', description: '连续7天'),
          const GoalPreset(target: 14, label: '两周', description: '连续14天'),
          const GoalPreset(target: 21, label: '三周', description: '连续21天'),
          const GoalPreset(target: 30, label: '满月', description: '连续30天'),
        ];
      case GoalType.photoCount:
        return [
          const GoalPreset(target: 10, label: '轻松', description: '每月10张'),
          const GoalPreset(target: 30, label: '标准', description: '每天1张'),
          const GoalPreset(target: 60, label: '勤奋', description: '每天2张'),
          const GoalPreset(target: 100, label: '摄影师', description: '每天3张'),
        ];
    }
  }
}

/// 提醒类型
enum GoalReminderType {
  progress,       // 进度提醒
  almostComplete, // 即将完成
  streak,         // 连续记录
  achievement,    // 目标达成
}

/// 目标提醒
class GoalReminder {
  final GoalReminderType type;
  final String title;
  final String message;
  final int priority; // 1-3，3为最高
  final DateTime createdAt;
  
  GoalReminder({
    required this.type,
    required this.title,
    required this.message,
    this.priority = 1,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  /// 是否高优先级
  bool get isHighPriority => priority >= 3;
  
  /// 是否中优先级
  bool get isMediumPriority => priority == 2;
}

/// 提醒设置
class GoalReminderSettings {
  final bool enabled;
  final bool remindProgress;      // 目标进度提醒
  final bool remindAlmostComplete; // 即将完成提醒
  final bool remindStreak;        // 连续记录提醒
  final bool remindAchievement;   // 目标达成提醒
  final TimeOfDay reminderTime;   // 提醒时间
  
  GoalReminderSettings({
    this.enabled = true,
    this.remindProgress = true,
    this.remindAlmostComplete = true,
    this.remindStreak = true,
    this.remindAchievement = true,
    this.reminderTime = const TimeOfDay(hour: 20, minute: 0),
  });
  
  factory GoalReminderSettings.defaultSettings() => GoalReminderSettings();
  
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'remindProgress': remindProgress,
    'remindAlmostComplete': remindAlmostComplete,
    'remindStreak': remindStreak,
    'remindAchievement': remindAchievement,
    'reminderHour': reminderTime.hour,
    'reminderMinute': reminderTime.minute,
  };
  
  factory GoalReminderSettings.fromJson(Map<String, dynamic> json) => GoalReminderSettings(
    enabled: json['enabled'] ?? true,
    remindProgress: json['remindProgress'] ?? true,
    remindAlmostComplete: json['remindAlmostComplete'] ?? true,
    remindStreak: json['remindStreak'] ?? true,
    remindAchievement: json['remindAchievement'] ?? true,
    reminderTime: TimeOfDay(
      hour: json['reminderHour'] ?? 20,
      minute: json['reminderMinute'] ?? 0,
    ),
  );
  
  GoalReminderSettings copyWith({
    bool? enabled,
    bool? remindProgress,
    bool? remindAlmostComplete,
    bool? remindStreak,
    bool? remindAchievement,
    TimeOfDay? reminderTime,
  }) => GoalReminderSettings(
    enabled: enabled ?? this.enabled,
    remindProgress: remindProgress ?? this.remindProgress,
    remindAlmostComplete: remindAlmostComplete ?? this.remindAlmostComplete,
    remindStreak: remindStreak ?? this.remindStreak,
    remindAchievement: remindAchievement ?? this.remindAchievement,
    reminderTime: reminderTime ?? this.reminderTime,
  );
}
