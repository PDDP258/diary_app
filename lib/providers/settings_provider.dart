import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户设置 Provider - 管理用户信息和应用设置
class SettingsProvider extends ChangeNotifier {
  static const String _userNameKey = 'user_name';
  static const String _userGoalKey = 'user_goal';
  static const String _userEmojiKey = 'user_emoji';
  static const String _userSignatureKey = 'user_signature';
  static const String _userAvatarKey = 'user_avatar_path';
  static const String _calendarYearKey = 'calendar_year';
  static const String _calendarMonthKey = 'calendar_month';

  String _userName = '日记记录者';
  String _userGoal = '记录生活，珍藏回忆';
  String _userEmoji = '👋';
  String _userSignature = 'PD inc'; // 默认签名
  String? _customAvatarPath; // 自定义头像路径
  int _calendarYear = DateTime.now().year;
  int _calendarMonth = DateTime.now().month;

  // Getters
  String get userName => _userName;
  String get userGoal => _userGoal;
  String get userEmoji => _userEmoji;
  String get userSignature => _userSignature;
  String? get customAvatarPath => _customAvatarPath;
  int get calendarYear => _calendarYear;
  int get calendarMonth => _calendarMonth;

  // 加载设置
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _userName = prefs.getString(_userNameKey) ?? '日记记录者';
      _userGoal = prefs.getString(_userGoalKey) ?? '记录生活，珍藏回忆';
      _userEmoji = prefs.getString(_userEmojiKey) ?? '👋';
      _userSignature = prefs.getString(_userSignatureKey) ?? 'PD inc';
      _customAvatarPath = prefs.getString(_userAvatarKey);
      _calendarYear = prefs.getInt(_calendarYearKey) ?? DateTime.now().year;
      _calendarMonth = prefs.getInt(_calendarMonthKey) ?? DateTime.now().month;
      
      notifyListeners();
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
  }

  // 设置用户信息
  Future<void> setUserInfo({String? name, String? goal, String? emoji, String? signature}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (name != null) {
        _userName = name;
        await prefs.setString(_userNameKey, name);
      }
      if (goal != null) {
        _userGoal = goal;
        await prefs.setString(_userGoalKey, goal);
      }
      if (emoji != null) {
        _userEmoji = emoji;
        await prefs.setString(_userEmojiKey, emoji);
      }
      if (signature != null) {
        _userSignature = signature;
        await prefs.setString(_userSignatureKey, signature);
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('保存用户信息失败: $e');
    }
  }

  // 设置自定义头像
  Future<void> setCustomAvatar(String path) async {
    try {
      _customAvatarPath = path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userAvatarKey, path);
      notifyListeners();
    } catch (e) {
      debugPrint('保存自定义头像失败: $e');
    }
  }

  // 清除自定义头像
  Future<void> clearCustomAvatar() async {
    try {
      _customAvatarPath = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userAvatarKey);
      notifyListeners();
    } catch (e) {
      debugPrint('清除自定义头像失败: $e');
    }
  }

  // 设置日历状态
  Future<void> setCalendarState(int year, int month) async {
    try {
      _calendarYear = year;
      _calendarMonth = month;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_calendarYearKey, year);
      await prefs.setInt(_calendarMonthKey, month);
      
      notifyListeners();
    } catch (e) {
      debugPrint('保存日历状态失败: $e');
    }
  }
}
