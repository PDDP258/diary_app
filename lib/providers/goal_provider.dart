import 'package:flutter/material.dart';
import '../services/goal_service.dart';

/// 目标状态 Provider
class GoalProvider extends ChangeNotifier {
  MonthlyGoal? _currentGoal;
  bool _isLoading = false;
  String? _error;
  
  // Getters
  MonthlyGoal? get currentGoal => _currentGoal;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // 快捷访问
  bool get hasGoal => _currentGoal != null;
  double get progress => _currentGoal?.progress ?? 0.0;
  bool get isCompleted => _currentGoal?.isCompleted ?? false;
  bool get isAlmostComplete => _currentGoal?.isAlmostComplete ?? false;
  int get remaining => _currentGoal?.remaining ?? 0;
  int get currentStreak => _currentGoal?.currentStreak ?? 0;
  
  /// 加载当前月目标
  Future<void> loadCurrentGoal() async {
    _setLoading(true);
    try {
      _currentGoal = await GoalService.getCurrentGoal();
      _error = null;
    } catch (e) {
      _error = '加载目标失败: $e';
    } finally {
      _setLoading(false);
    }
  }
  
  /// 设置新目标
  Future<void> setGoal({
    required int targetCount,
    GoalType type = GoalType.diaryCount,
  }) async {
    _setLoading(true);
    try {
      final now = DateTime.now();
      final goal = MonthlyGoal(
        year: now.year,
        month: now.month,
        targetCount: targetCount,
        type: type,
      );
      
      // 更新进度
      await GoalService.setGoal(goal);
      _currentGoal = goal;
      
      // 立即刷新进度
      await refreshProgress();
      
      _error = null;
    } catch (e) {
      _error = '设置目标失败: $e';
    } finally {
      _setLoading(false);
    }
  }
  
  /// 刷新目标进度
  Future<void> refreshProgress() async {
    if (_currentGoal == null) return;
    
    try {
      // 重新获取以更新进度
      _currentGoal = await GoalService.getCurrentGoal();
      notifyListeners();
    } catch (e) {
      debugPrint('刷新进度失败: $e');
    }
  }
  
  /// 检查是否达成目标（写新日记后调用）
  Future<bool> checkGoalCompletion() async {
    await refreshProgress();
    
    if (_currentGoal?.isCompleted == true && _currentGoal?.completedAt != null) {
      // 刚刚完成（1分钟内）
      final completedAt = _currentGoal!.completedAt!;
      final diff = DateTime.now().difference(completedAt).inMinutes;
      if (diff < 1) {
        return true; // 刚完成，需要显示庆祝
      }
    }
    
    return false;
  }
  
  /// 获取目标历史
  Future<List<MonthlyGoal>> getGoalHistory() async {
    return await GoalService.getGoalHistory();
  }
  
  /// 获取统计数据
  Future<Map<String, dynamic>> getStats() async {
    return await GoalService.getGoalStats();
  }
  
  /// 设置 loading 状态
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
  
  /// 清除错误
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
