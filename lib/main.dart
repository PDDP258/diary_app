import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'providers/diary_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/custom_goal_provider.dart';
import 'providers/course_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/protection_violation_screen.dart';
import 'screens/main_screen.dart';
import 'services/auto_backup_service.dart';
import 'services/cloud_sync_service.dart';
import 'services/sound_service.dart';
import 'services/debug_log_service.dart';
import 'services/sync_log_service.dart';
import 'services/app_protection_service.dart';
import 'services/floating_window_service.dart';
import 'services/floating_settings_service.dart';
import 'services/floating_permission_service.dart';
import 'services/course_widget_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日期格式（中文）
  await initializeDateFormatting('zh_CN', null);

  // 执行应用保护检查（发布模式下）
  ProtectionResult? protectionResult;
  if (!kDebugMode) {
    protectionResult = await AppProtectionService.checkAppIntegrity();
  }

  // 初始化云同步服务
  await CloudSyncFactory.initialize();

  // 初始化同步日志服务
  await SyncLogService.initialize();

  // 初始化音效服务
  await SoundService.initialize();

  // 初始化浮窗服务（注册 MethodChannel 回调）
  FloatingWindowService.initialize();

  // 预加载主题设置（确保启动时主题已加载）
  final themeProvider = ThemeProvider();
  await themeProvider.loadSettings();

  // 课表桌面小组件：注册后台入口点（开机/每日定时由原生侧拉起 Dart
  // 续排提醒窗口 + 重算计划），并缓存主题配色
  await CourseWidgetService.initialize();

  // 用户切主题 → 桌面小组件跟着换肤（计划里内嵌配色，所以要重推一次）
  themeProvider.addListener(() {
    CourseWidgetService.updateTheme(themeProvider.currentScheme);
  });

  // 检查并执行自动备份（在后台执行，不阻塞启动）
  AutoBackupService.checkAndBackup().then((success) {
    if (success) {
      print('自动备份执行成功');
    }
  }).catchError((e) {
    print('自动备份执行失败: $e');
  });

  // 如果保护检查失败，显示警告页面
  if (protectionResult != null && !protectionResult.isValid) {
    runApp(ProtectionViolationApp(result: protectionResult));
    return;
  }

  runApp(MyApp(preloadedThemeProvider: themeProvider));

  // 延迟自动恢复浮窗（如果之前已开启）
  _autoRestoreFloatingWindow();
}

/// 应用启动后自动恢复浮窗
Future<void> _autoRestoreFloatingWindow() async {
  try {
    // 延迟 2 秒，等应用完全启动后再恢复
    await Future.delayed(const Duration(seconds: 2));
    final isEnabled = await FloatingSettingsService.getEnabled();
    if (isEnabled) {
      final hasOverlay = await FloatingPermissionService.checkOverlayPermission();
      if (hasOverlay) {
        final success = await FloatingWindowService.showFloatingButton();
        print('浮窗自动恢复: $success');
      } else {
        print('浮窗自动恢复跳过: 无悬浮窗权限');
      }
    }
  } catch (e) {
    print('浮窗自动恢复失败: $e');
  }
}

class MyApp extends StatelessWidget {
  final ThemeProvider? preloadedThemeProvider;
  
  const MyApp({super.key, this.preloadedThemeProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        // 使用预加载的 ThemeProvider，如果没有则创建新的
        ChangeNotifierProvider.value(
          value: preloadedThemeProvider ?? (ThemeProvider()..loadSettings()),
        ),
        ChangeNotifierProvider(
            create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => CustomGoalProvider()..loadGoals()),
        ChangeNotifierProvider(create: (_) => CourseProvider()..load()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: '小记日记',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.theme,
            home: const SplashScreen(),
            navigatorObservers: [mainScreenRouteObserver],
            builder: (context, child) {
              return DebugLogOverlay(child: child!);
            },
          );
        },
      ),
    );
  }
}
