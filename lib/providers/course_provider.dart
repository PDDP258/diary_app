import 'package:flutter/foundation.dart';
import '../models/course.dart';
import '../services/course_reminder_service.dart';
import '../services/course_widget_service.dart';
import '../services/database_service.dart';
import '../utils/week_parser.dart';

/// 课表状态管理
///
/// 所有导入路径（手动/模板/教务适配器/OCR 预留）统一经此 Provider 入库，
/// 通知（T6）与桌面小组件（T7）也从这里取今日课程。
class CourseProvider extends ChangeNotifier {
  List<Course> _courses = [];
  SemesterConfig? _semester;
  bool _loaded = false;

  List<Course> get courses => List.unmodifiable(_courses);
  SemesterConfig? get semester => _semester;
  bool get loaded => _loaded;
  bool get hasSemester => _semester != null;

  /// 当前教学周（学期外返回 null）
  int? get currentWeek {
    final s = _semester;
    if (s == null) return null;
    return WeekParser.currentWeek(
      semesterStart: DateTime.parse(s.startDate),
      totalWeeks: s.totalWeeks,
    );
  }

  Future<void> load() async {
    _courses = await DatabaseService.getAllCourses();
    _semester = await DatabaseService.getSemesterConfig();
    _loaded = true;
    notifyListeners();
    _refreshReminders();
  }

  /// 课表/学期任何变更后续排课前提醒（滚动窗口）+ 同步桌面小组件
  void _refreshReminders() {
    CourseReminderService.reschedule(courses: _courses, semester: _semester)
        .catchError((_) {});
    CourseWidgetService.syncTodayCourses(courses: _courses, semester: _semester)
        .catchError((_) {});
  }

  Future<int> addCourse(Course course, List<CourseSession> sessions) async {
    final id = await DatabaseService.insertCourse(course, sessions);
    await load();
    return id;
  }

  Future<void> updateCourse(Course course, List<CourseSession> sessions) async {
    await DatabaseService.updateCourse(course, sessions);
    await load();
  }

  Future<void> deleteCourse(int id) async {
    await DatabaseService.deleteCourse(id);
    await load();
  }

  Future<void> saveSemester(SemesterConfig config) async {
    await DatabaseService.saveSemesterConfig(config);
    _semester = config;
    notifyListeners();
    _refreshReminders();
  }

  /// 指定教学周、星期几的课程（含对应 session），按起始节次排序
  List<({Course course, CourseSession session})> coursesForDay(
      int week, int dayOfWeek) {
    final result = <({Course course, CourseSession session})>[];
    for (final c in _courses) {
      for (final s in c.sessions) {
        if (s.occursOn(week, dayOfWeek)) {
          result.add((course: c, session: s));
        }
      }
    }
    result.sort((a, b) => a.session.startSection
        .compareTo(b.session.startSection));
    return result;
  }

  /// 今天的课程（学期外或当天无课返回空列表）
  List<({Course course, CourseSession session})> todayCourses() {
    final week = currentWeek;
    if (week == null) return [];
    return coursesForDay(week, DateTime.now().weekday);
  }

  /// 某节次在某天是否有课（供网格视图逐格查询）
  ({Course course, CourseSession session})? courseAt(
      int week, int dayOfWeek, int section) {
    for (final c in _courses) {
      for (final s in c.sessions) {
        if (s.dayOfWeek == dayOfWeek &&
            s.weeks.contains(week) &&
            section >= s.startSection &&
            section <= s.endSection) {
          return (course: c, session: s);
        }
      }
    }
    return null;
  }
}
