import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_goal.dart';

/// 自定义目标服务
class CustomGoalService {
  static const String _goalsKey = 'custom_goals_v2';
  static const String _activeGoalIdKey = 'active_custom_goal_id';
  static const int _maxGoals = 5; // 最多5个目标
  
  /// 获取所有目标
  static Future<List<CustomGoal>> getAllGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_goalsKey);
    
    if (jsonStr == null || jsonStr.isEmpty) {
      return [];
    }
    
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((json) => CustomGoal.fromJson(json)).toList();
    } catch (e) {
      print('加载目标失败: $e');
      return [];
    }
  }
  
  /// 获取当前激活的目标（显示在日历页的）
  static Future<CustomGoal?> getActiveGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final goals = await getAllGoals();
    
    if (goals.isEmpty) return null;
    
    final activeId = prefs.getString(_activeGoalIdKey);
    if (activeId != null) {
      try {
        return goals.firstWhere((g) => g.id == activeId && g.isActive);
      } catch (e) {
        // 找不到激活的目标，返回第一个活跃的
        return goals.firstWhere((g) => g.isActive);
      }
    }
    
    // 默认返回第一个活跃的
    return goals.firstWhere((g) => g.isActive);
  }
  
  /// 保存目标列表
  static Future<void> saveGoals(List<CustomGoal> goals) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = goals.map((g) => g.toJson()).toList();
    await prefs.setString(_goalsKey, jsonEncode(jsonList));
  }
  
  /// 添加新目标
  static Future<CustomGoal> addGoal(CustomGoal goal) async {
    final goals = await getAllGoals();
    
    // 检查是否超过最大限制
    if (goals.length >= _maxGoals) {
      throw Exception('最多只能设置$_maxGoals个目标，请先删除其他目标');
    }
    
    goals.add(goal);
    await saveGoals(goals);
    
    // 如果是第一个目标，设为激活
    if (goals.length == 1) {
      await setActiveGoal(goal.id);
    }
    
    return goal;
  }
  
  /// 检查是否还可以添加目标
  static Future<bool> canAddMoreGoals() async {
    final goals = await getAllGoals();
    return goals.length < _maxGoals;
  }
  
  /// 获取最大目标数
  static int get maxGoals => _maxGoals;
  
  /// 更新目标
  static Future<void> updateGoal(CustomGoal updatedGoal) async {
    final goals = await getAllGoals();
    final index = goals.indexWhere((g) => g.id == updatedGoal.id);
    
    if (index != -1) {
      goals[index] = updatedGoal;
      await saveGoals(goals);
    }
  }
  
  /// 删除目标
  static Future<void> deleteGoal(String goalId) async {
    final goals = await getAllGoals();
    goals.removeWhere((g) => g.id == goalId);
    await saveGoals(goals);
    
    // 如果删除的是当前激活的目标，重置激活状态
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_activeGoalIdKey);
    if (activeId == goalId) {
      await prefs.remove(_activeGoalIdKey);
      // 如果有其他目标，激活第一个
      if (goals.isNotEmpty) {
        await setActiveGoal(goals.first.id);
      }
    }
  }
  
  /// 设置激活的目标
  static Future<void> setActiveGoal(String goalId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeGoalIdKey, goalId);
  }
  
  /// 增加目标完成次数（按指定值）
  static Future<void> incrementGoal(String goalId, {int value = 1}) async {
    final goal = await getGoalById(goalId);
    if (goal != null) {
      goal.incrementBy(value);
      await updateGoal(goal);
    }
  }
  
  /// 减少目标完成次数（按指定值）
  static Future<void> decrementGoal(String goalId, {int value = 1}) async {
    final goal = await getGoalById(goalId);
    if (goal != null) {
      goal.decrementBy(value);
      await updateGoal(goal);
    }
  }
  
  /// 根据ID获取目标
  static Future<CustomGoal?> getGoalById(String goalId) async {
    final goals = await getAllGoals();
    try {
      return goals.firstWhere((g) => g.id == goalId);
    } catch (e) {
      return null;
    }
  }
  
  /// 获取活跃目标数量
  static Future<int> getActiveGoalCount() async {
    final goals = await getAllGoals();
    return goals.where((g) => g.isActive).length;
  }
  
  /// 重置每日进度（应用启动或从后台恢复时调用）
  static Future<void> resetDailyProgress() async {
    final goals = await getAllGoals();
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    bool hasChanges = false;

    for (final goal in goals) {
      if (goal.period == GoalPeriod.daily) {
        // 每日目标：如果今天已经重置过，跳过
        if (goal.lastResetDate == todayStr) continue;

        final lastRecord =
            goal.records.isNotEmpty ? goal.records.last : null;
        // 如果最后记录不是今天，说明需要重置
        if (lastRecord == null || lastRecord.date != todayStr) {
          goal.currentCount = 0;
          goal.completedAt = null;
          goal.lastResetDate = todayStr;
          hasChanges = true;
        }
      } else if (goal.period == GoalPeriod.weekly) {
        // 每周目标：检查本周是否已经重置过
        if (_isSameWeek(goal.lastResetDate, todayStr)) continue;

        goal.currentCount = 0;
        goal.completedAt = null;
        goal.lastResetDate = todayStr;
        hasChanges = true;
      } else if (goal.period == GoalPeriod.monthly) {
        // 每月目标：检查本月是否已经重置过
        if (_isSameMonth(goal.lastResetDate, todayStr)) continue;

        goal.currentCount = 0;
        goal.completedAt = null;
        goal.lastResetDate = todayStr;
        hasChanges = true;
      }
    }

    if (hasChanges) {
      await saveGoals(goals);
    }
  }

  /// 检查两个日期字符串是否在同一周（以周一为周起点）
  static bool _isSameWeek(String? dateA, String dateB) {
    if (dateA == null || dateA.isEmpty) return false;
    try {
      final a = DateTime.parse(dateA);
      final b = DateTime.parse(dateB);
      final mondayA = a.subtract(Duration(days: a.weekday - 1));
      final mondayB = b.subtract(Duration(days: b.weekday - 1));
      return DateTime(mondayA.year, mondayA.month, mondayA.day) ==
          DateTime(mondayB.year, mondayB.month, mondayB.day);
    } catch (e) {
      return false;
    }
  }

  /// 检查两个日期字符串是否在同一个月
  static bool _isSameMonth(String? dateA, String dateB) {
    if (dateA == null || dateA.isEmpty) return false;
    try {
      final a = DateTime.parse(dateA);
      final b = DateTime.parse(dateB);
      return a.year == b.year && a.month == b.month;
    } catch (e) {
      return false;
    }
  }
}
