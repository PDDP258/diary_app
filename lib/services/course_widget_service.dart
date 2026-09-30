import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/course.dart';
import '../providers/theme_provider.dart';
import 'course_reminder_service.dart';
import 'course_widget_plan.dart';
import 'database_service.dart';

/// 今日课程桌面小组件（PRD 决策 D6）
///
/// **职责分工**：Dart 侧算数据，原生侧渲染与刷新。
///
/// Dart 侧把未来两周的课表算成一份 [CourseWidgetPlan] 推给原生
/// （`android/app/src/main/kotlin/com/example/diary_app/CourseWidget*`），
/// 原生侧存进自己的 SharedPreferences 并立即重绘小组件。
///
/// **为什么不让原生侧算**：读 SQLite、判教学周、查节次时间表都得靠 Dart，
/// 而小组件刷新发生在开机 / 系统定时唤醒这些 App 进程不存在的时刻 ——
/// 那时拉起完整 Flutter 引擎代价太大且不可靠。预计算把「算」和「画」解耦。
///
/// 之前用 glance_widget 的 Calendar 模板时，跨天刷新依赖 App 打开
/// （`updatePeriodMillis=0`，系统根本不会唤醒小组件），所以出现过
/// 「重新开机后还显示昨天」的问题。现在原生侧自带开机 / 每日定时刷新。
class CourseWidgetService {
  static const _channel = MethodChannel('com.diary_app/course_widget');

  /// 主题色缓存：主题切换时由 [updateTheme] 覆盖，避免每次同步都读一遍 prefs
  static CourseWidgetTheme? _cachedTheme;

  /// 上一份计划：切主题时只换配色重推，不必重算两周课表
  static CourseWidgetPlan? _lastPlan;

  // ==================== 生命周期 ====================

  /// App 启动时调用一次：
  /// 1. 让主题缓存就绪；
  /// 2. 把后台入口点的句柄交给原生侧 —— 原生侧在开机 / 每日定时
  ///    会用它起一个**无界面的 Flutter 引擎**跑 [courseWidgetBackgroundEntry]，
  ///    续排课前提醒窗口并刷新小组件；同时让原生侧确认每日任务在排。
  static Future<void> initialize() async {
    await _ensureTheme();
    try {
      final handle = PluginUtilities.getCallbackHandle(
        courseWidgetBackgroundEntry,
      );
      if (handle == null) return;
      await _channel.invokeMethod<void>('registerBackground', {
        'handle': handle.toRawHandle(),
      });
    } catch (e) {
      // 非 Android 平台 / 通道未注册：小组件不同步不影响 App 使用
      debugPrint('CourseWidgetService: 后台入口注册失败（通常不影响使用）: $e');
    }
  }

  /// 主题变更后调用：让小组件跟着 App 换肤
  ///
  /// 计划里内嵌了配色，所以换主题必须把计划重推一次；只调 refresh
  /// 原生侧手里还是旧配色。
  static Future<void> updateTheme(ThemeScheme scheme) async {
    _cachedTheme = _themeFrom(scheme);
    final last = _lastPlan;
    if (last == null) return;
    try {
      await _push(last.withTheme(_cachedTheme!));
    } catch (_) {
      // 桌面没加小组件 / 通道不可用：静默，下次同步自然会带上新配色
    }
  }

  // ==================== 同步 ====================

  /// 同步今日课程到桌面小组件（非支持平台静默跳过）
  ///
  /// 失败只在调试模式输出日志 —— 常见原因是桌面尚未添加小组件实例，
  /// 原生侧会静默忽略（下次同步照样写计划，用户添加实例后立即生效）。
  static Future<void> syncTodayCourses({
    required List<Course> courses,
    required SemesterConfig? semester,
    ThemeScheme? scheme,
  }) async {
    try {
      final theme = scheme != null
          ? (_cachedTheme = _themeFrom(scheme))
          : await _ensureTheme();
      final plan = CourseWidgetPlan.build(
        courses: courses,
        semester: semester,
        theme: theme,
      );
      _lastPlan = plan;
      await _push(plan);
    } catch (e) {
      debugPrint('CourseWidgetService: 小组件同步失败（通常不影响使用）: $e');
    }
  }

  /// 推送一份计划并让原生侧立即重绘
  static Future<void> _push(CourseWidgetPlan plan) async {
    await _channel.invokeMethod<void>('updatePlan', {
      'plan': jsonEncode(plan.toJson()),
    });
  }

  /// 清空计划（退出学期 / 删除全部课程时用），小组件回到引导文案
  static Future<void> clear() async {
    _lastPlan = null;
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (e) {
      debugPrint('CourseWidgetService: 清空小组件失败: $e');
    }
  }

  /// 告诉原生侧「后台 Dart 干完了，可以销毁引擎」
  ///
  /// 原生侧在等这个信号（有超时兜底）—— 不等的话引擎会在 Dart 还没跑完
  /// 时被销毁，提醒窗口就续排不上。
  static Future<void> notifyBackgroundDone() async {
    try {
      await _channel.invokeMethod<void>('backgroundDone');
    } catch (_) {
      // 主引擎里调用 / 通道不可用：无所谓
    }
  }

  // ==================== 主题 ====================

  static Future<CourseWidgetTheme> _ensureTheme() async {
    final cached = _cachedTheme;
    if (cached != null) return cached;
    try {
      final provider = ThemeProvider();
      await provider.loadSettings();
      return _cachedTheme = _themeFrom(provider.currentScheme);
    } catch (_) {
      return CourseWidgetTheme.fallback;
    }
  }

  static CourseWidgetTheme _themeFrom(ThemeScheme s) => CourseWidgetTheme(
        background: s.backgroundColor.toARGB32(),
        foreground: s.textDarkColor.toARGB32(),
        secondary: s.textMediumColor.toARGB32(),
        accent: s.primaryColor.toARGB32(),
        divider: s.lightColor.toARGB32(),
      );
}

/// **后台入口点**（开机 / 每日定时由原生侧拉起）
///
/// 原生侧在 `CourseWidgetBackgroundRunner` 里起一个无界面 FlutterEngine
/// 执行这个函数。它做两件 App 不在前台也必须做的事：
///
/// 1. 续排课前提醒的滚动窗口 —— 窗口只有 [CourseReminderService.windowDays] 天，
///    长期不开 App 就会排空；
/// 2. 重新生成小组件计划 —— 否则两周后小组件只能显示「课表待刷新」。
///
/// 这个函数必须**永不抛异常**：它跑在没有 UI 的后台进程里，
/// 崩了不会有任何提示，还会让系统认为 App 不稳定。整段包 try/catch。
@pragma('vm:entry-point')
Future<void> courseWidgetBackgroundEntry() async {
  DartPluginRegistrant.ensureInitialized();
  try {
    WidgetsFlutterBinding.ensureInitialized();

    final courses = await DatabaseService.getAllCourses();
    final semester = await DatabaseService.getSemesterConfig();

    await CourseReminderService.reschedule(
      courses: courses,
      semester: semester,
    );
    await CourseWidgetService.syncTodayCourses(
      courses: courses,
      semester: semester,
    );
  } catch (e) {
    debugPrint('CourseWidgetService: 后台刷新失败: $e');
  } finally {
    // 无论成败都要回话，否则原生侧会一直等到超时（25s）才销毁引擎
    await CourseWidgetService.notifyBackgroundDone();
  }
}
