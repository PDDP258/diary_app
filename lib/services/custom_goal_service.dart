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
  
  /// 增加目标完成次数
  static Future<void> incrementGoal(String goalId) async {
    final goal = await getGoalById(goalId);
    if (goal != null) {
      goal.increment();
      await updateGoal(goal);
    }
  }
  
  /// 减少目标完成次数
  static Future<void> decrementGoal(String goalId) async {
    final goal = await getGoalById(goalId);
    if (goal != null) {
      goal.decrement();
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
  
  /// 重置每日进度（每天调用一次）
  static Future<void> resetDailyProgress() async {
    final goals = await getAllGoals();
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    bool hasChanges = false;
    
    for (final goal in goals) {
      // 检查是否需要重置
      if (goal.period == GoalPeriod.daily) {
        // 每日目标：如果不是今天创建的，且没有今日记录，重置当前计数
        final lastRecord = goal.records.isNotEmpty ? goal.records.last : null;
        if (lastRecord != null && lastRecord.date != todayStr) {
          goal.currentCount = 0;
          goal.completedAt = null;
          hasChanges = true;
        }
      } else if (goal.period == GoalPeriod.weekly) {
        // 每周目标：检查是否跨周
        if (_isNewWeek(goal.createdAt, today)) {
          goal.currentCount = 0;
          goal.completedAt = null;
          hasChanges = true;
        }
      } else if (goal.period == GoalPeriod.monthly) {
        // 每月目标：检查是否跨月
        if (goal.createdAt.month != today.month || goal.createdAt.year != today.year) {
          goal.currentCount = 0;
          goal.completedAt = null;
          hasChanges = true;
        }
      }
    }
    
    if (hasChanges) {
      await saveGoals(goals);
    }
  }
  
  /// 检查是否是新的一周
  static bool _isNewWeek(DateTime created, DateTime today) {
    // 获取本周一
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    
    // 如果创建日期在本周一之前，则需要重置
    return created.isBefore(weekStart);
  }
}
