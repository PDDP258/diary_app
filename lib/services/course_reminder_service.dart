import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import '../utils/week_parser.dart';

/// 课前提醒服务（PRD 决策 D5）
///
/// 滚动窗口调度：只排未来 [windowDays] 天的上课提醒，
/// 在 App 启动、课表变更、提醒设置变更时续排。
///
/// 为什么不用系统级每周重复（dayOfWeekAndTime）：
/// 1. 无法表达单双周/周次集合；
/// 2. iOS 待触发通知上限 64 条、部分 Android（三星）闹钟上限 500 条，
///    一学期排满会爆；14 天窗口 × 每天几节课远低于上限。
///
/// 精度策略：inexactAllowWhileIdle（不强制申请 Android 14 精确闹钟权限，
/// 最多延迟几分钟，课前提醒场景可接受，且国产 ROM 上更可靠）。
class CourseReminderService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _tzInitialized = false;

  static const _channelId = 'course_reminder_channel';
  static const _enabledKey = 'course_reminder_enabled';
  static const _minutesKey = 'course_remind_minutes';

  /// 通知 id 命名空间前缀，避免与其他功能冲突
  static const _idBase = 0x03000000;

  /// 滚动窗口天数
  static const windowDays = 14;

  static Future<void> _ensureInit() async {
    if (!_tzInitialized) {
      tz_data.initializeTimeZones();
      _tzInitialized = true;
    }
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin
        .initialize(const InitializationSettings(android: androidSettings));
    _initialized = true;
  }

  // ==================== 设置 ====================

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<int> remindMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_minutesKey) ?? 15;
  }

  /// 更新设置并重排
  static Future<void> saveSettings({
    required bool enabled,
    required int minutes,
    List<Course>? courses,
    SemesterConfig? semester,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setInt(_minutesKey, minutes);
    if (courses != null) {
      await reschedule(courses: courses, semester: semester);
    }
  }

  // ==================== 调度 ====================

  /// 重排滚动窗口内的全部课前提醒
  static Future<void> reschedule({
    required List<Course> courses,
    required SemesterConfig? semester,
  }) async {
    await _ensureInit();
    await cancelAll();

    if (!await isEnabled() || semester == null) return;
    final minutes = await remindMinutes();
    final semesterStart = DateTime.parse(semester.startDate);

    // 节次序号 → 开始时间
    final sectionTimes = {
      for (final s in semester.sections) s.section: s.startTime,
    };

    final now = DateTime.now();
    var scheduled = 0;

    for (var offset = 0; offset < windowDays; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      final week = WeekParser.currentWeek(
          semesterStart: semesterStart,
          totalWeeks: semester.totalWeeks,
          date: day);
      if (week == null) continue;

      for (final course in courses) {
        for (final session in course.sessions) {
          if (!session.occursOn(week, day.weekday)) continue;
          final timeText = sectionTimes[session.startSection];
          if (timeText == null) continue;
          final parts = timeText.split(':');
          final classTime = DateTime(day.year, day.month, day.day,
              int.parse(parts[0]), int.parse(parts[1]));
          final remindAt = classTime.subtract(Duration(minutes: minutes));
          if (remindAt.isBefore(now)) continue; // 已过期的不排

          await _scheduleOne(
            id: _notificationId(day, session),
            title: '上课提醒 · ${course.name}',
            body: '${_two(classTime.hour)}:${_two(classTime.minute)} '
                '${session.location ?? ''} 第${session.startSection}节开始'
                .trim(),
            at: remindAt,
          );
          scheduled++;
        }
      }
    }
  }

  static Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      '上课提醒',
      channelDescription: '课程开始前的提醒通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// 取消全部课前提醒（只清我们的 id 命名空间）
  static Future<void> cancelAll() async {
    await _ensureInit();
    final pending = await _plugin.pendingNotificationRequests();
    for (final req in pending) {
      if (req.id >= _idBase && req.id < _idBase + 0x1000000) {
        await _plugin.cancel(req.id);
      }
    }
  }

  /// 通知 id：日期 + session 的稳定散列，落在命名空间内
  static int _notificationId(DateTime day, CourseSession session) {
    final key = '${day.year}${day.month}${day.day}'
        '_${session.courseId}_${session.dayOfWeek}_${session.startSection}';
    return _idBase + (key.hashCode & 0xFFFFFF);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
