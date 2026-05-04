import 'package:flutter/material.dart';
import 'screens/floating_window_screen.dart';

/// 浮窗专用 Flutter 入口
///
/// 当系统悬浮窗启动时，调用此入口而不是 main.dart
/// 浮窗内是一个精简的 Flutter 应用，只包含速记相关 UI
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FloatingWindowApp());
}

/// 兼容入口（部分flutter_overlay_window版本使用main）
@pragma('vm:entry-point')
void main() {
  overlayMain();
}

class FloatingWindowApp extends StatelessWidget {
  const FloatingWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSerifCJKsc',
      ),
      home: const FloatingWindowScreen(),
    );
  }
}
