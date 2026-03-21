import 'package:flutter/material.dart';
import '../models/custom_goal.dart';
import '../services/custom_goal_service.dart';

/// 自定义目标 Provider
class CustomGoalProvider extends ChangeNotifier {
  List<CustomGoal> _goals = [];
  CustomGoal? _activeGoal;
  bool _isLoading = false;
  String? _error;
  
  // Getters
  List<CustomGoal> get goals => _goals;
  CustomGoal? get activeGoal => _activeGoal;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasGoals => _goals.isNotEmpty;
  bool get hasActiveGoal => _activeGoal != null;
  
  /// 加载所有目标
  Future<void> loadGoals() async {
    _setLoading(true);
    try {
      _goals = await CustomGoalService.getAllGoals();
      _activeGoal = await CustomGoalService.getActiveGoal();
      _error = null;
    } catch (e) {
      _error = '加载目标失败: $e';
    } finally {
      _setLoading(false);
    }
  }
  
  /// 加载当前激活的目标
  Future<void> loadActiveGoal() async {
    try {
      _activeGoal = await CustomGoalService.getActiveGoal();
      notifyListeners();
    } catch (e) {
      debugPrint('加载激活目标失败: $e');
    }
  }
  
  /// 添加新目标
  Future<void> addGoal(CustomGoal goal) async {
    _setLoading(true);
    try {
      await CustomGoalService.addGoal(goal);
      await loadGoals();
      _error = null;
    } catch (e) {
      _error = '添加目标失败: $e';
      _setLoading(false);
    }
  }
  
  /// 更新目标
  Future<void> updateGoal(CustomGoal goal) async {
    try {
      await CustomGoalService.updateGoal(goal);
      await loadGoals();
    } catch (e) {
      _error = '更新目标失败: $e';
      notifyListeners();
    }
  }
  
  /// 删除目标
  Future<void> deleteGoal(String goalId) async {
    try {
      await CustomGoalService.deleteGoal(goalId);
      await loadGoals();
    } catch (e) {
      _error = '删除目标失败: $e';
      notifyListeners();
    }
  }
  
  /// 设置激活的目标
  Future<void> setActiveGoal(String goalId) async {
    try {
      await CustomGoalService.setActiveGoal(goalId);
      _activeGoal = await CustomGoalService.getGoalById(goalId);
      notifyListeners();
    } catch (e) {
      _error = '设置激活目标失败: $e';
      notifyListeners();
    }
  }
  
  /// 增加目标完成次数
  Future<void> incrementGoal(String goalId) async {
    try {
      await CustomGoalService.incrementGoal(goalId);
      
      // 更新本地状态
      final goal = _goals.firstWhere((g) => g.id == goalId);
      goal.increment();
      
      if (_activeGoal?.id == goalId) {
        _activeGoal = goal;
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('增加目标进度失败: $e');
    }
  }
  
  /// 减少目标完成次数
  Future<void> decrementGoal(String goalId) async {
    try {
      await CustomGoalService.decrementGoal(goalId);
      
      // 更新本地状态
      final goal = _goals.firstWhere((g) => g.id == goalId);
      goal.decrement();
      
      if (_activeGoal?.id == goalId) {
        _activeGoal = goal;
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('减少目标进度失败: $e');
    }
  }
  
  /// 从模板创建目标
  Future<void> createFromTemplate(GoalTemplate template) async {
    final goal = CustomGoal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: template.name,
      icon: template.icon,
      targetCount: template.targetCount,
      period: template.period,
    );
    
    await addGoal(goal);
  }
  
  /// 重置每日进度
  Future<void> resetDailyProgress() async {
    await CustomGoalService.resetDailyProgress();
    await loadGoals();
  }
  
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
