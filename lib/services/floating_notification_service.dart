import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 浮窗系统通知服务
///
/// 用于显示/更新持久通知，将最新速记内容同步到通知栏
class FloatingNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// 初始化通知插件
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _initialized = true;
  }

  /// 显示/更新速记持久通知
  ///
  /// [content] 速记内容
  /// [wordCount] 字数
  static Future<void> showQuickNoteNotification(String content, {int? wordCount}) async {
    await init();

    final displayContent = content.length > 30 ? '${content.substring(0, 30)}...' : content;
    final wordCountText = wordCount != null ? '（$wordCount字）' : '';

    const androidDetails = AndroidNotificationDetails(
      'quick_note_floating_channel',
      '速记提醒',
      channelDescription: '显示最新速记内容，随时查看',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      onlyAlertOnce: true,
      // 使用 inbox 样式显示多条信息
      styleInformation: InboxStyleInformation(
        [],
        contentTitle: '📌 最新速记',
        summaryText: '双击浮窗快速记录',
      ),
      channelShowBadge: false,
    );

    await _notificationsPlugin.show(
      0x0101, // 固定通知 ID
      '📌 最新速记',
      '$displayContent$wordCountText',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// 取消速记通知
  static Future<void> cancelNotification() async {
    await _notificationsPlugin.cancel(0x0101);
  }

  /// 通知点击回调
  static void _onNotificationTap(NotificationResponse response) {
    // 点击通知时打开主应用
    // 具体实现由调用方处理（通过 Navigator 或 Intent）
  }

  /// 检查通知权限是否已授予
  static Future<bool> checkPermission() async {
    final status = await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    return status ?? false;
  }
}
