import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diary_app/config/app_theme.dart';
import 'package:diary_app/providers/theme_provider.dart';
import 'package:diary_app/screens/ai_chat_screen.dart';

/// 麦麦聊天页的交互回归测试。
///
/// 锁住两件事：
/// 1. 未配置时，右上角设置与「去设置」都能弹出连接设置对话框
///    （曾经两个入口一起失效：整页看着正常，点下去却毫无反应）；
/// 2. 设置弹窗能正常保存并回写配置状态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  // 内存版安全存储，测试里替代真实 keystore
  final Map<String, String> secureStore = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return key == null ? null : secureStore[key];
        case 'write':
          if (key != null) {
            secureStore[key] = (args['value'] as String?) ?? '';
          }
          return null;
        case 'delete':
          if (key != null) secureStore.remove(key);
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'containsKey':
          return key != null && secureStore.containsKey(key);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: const MaterialApp(home: AiChatScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('未配置时点右上角设置，能弹出连接设置', (tester) async {
    await pumpScreen(tester);

    expect(find.text('还没连上麦麦'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('桥地址'), findsOneWidget);
    expect(find.text('访问 token'), findsOneWidget);
  });

  testWidgets('未配置时点「去设置」，能弹出连接设置', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();

    expect(find.text('连接设置'), findsOneWidget);
  });

  testWidgets('填入 token 保存后，页面进入已配置状态', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'test-token');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 对话框关闭，回到对话页
    expect(find.text('连接设置'), findsNothing);
    // 已配置后不再显示「去设置」，空态文案换成可以开聊
    expect(find.text('去设置'), findsNothing);
  });

  // 根因回归：AppTheme.schemeOf 曾经只会 context.watch，
  // 在按钮回调里调用会触发 provider 断言（
  // 'context.owner!.debugBuilding || listen == false'），
  // 整段回调当场中断，表现就是「点了没反应」。
  // 现在它在 build 之外自动回落成 read，这个测试锁住该行为。
  testWidgets('schemeOf 在按钮回调里也能读到主题', (tester) async {
    ThemeScheme? captured;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => captured = AppTheme.schemeOf(context),
                  child: const Text('读主题'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('读主题'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.name, ThemeScheme.warmBeige.name);
  });
}
