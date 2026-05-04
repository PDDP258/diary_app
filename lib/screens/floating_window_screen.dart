import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../services/floating_settings_service.dart';
import '../widgets/floating_button.dart';
import '../widgets/floating_quick_note_bar.dart';

/// 浮窗根容器
///
/// 管理浮窗的两种模式：
/// 1. 小浮窗按钮（ FloatingButton ）
/// 2. 速记条横条（ FloatingQuickNoteBar ）
///
/// 通过 overlayListener 接收主应用发送的切换指令
class FloatingWindowScreen extends StatefulWidget {
  const FloatingWindowScreen({super.key});

  @override
  State<FloatingWindowScreen> createState() => _FloatingWindowScreenState();
}

class _FloatingWindowScreenState extends State<FloatingWindowScreen> {
  bool _showBar = false;
  FloatingSettings _settings = const FloatingSettings();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _listenToOverlayMessages();
  }

  Future<void> _loadSettings() async {
    final settings = await FloatingSettingsService.load();
    if (mounted) {
      setState(() => _settings = settings);
    }
  }

  /// 监听主应用通过 OverlayWindow 发送的消息
  void _listenToOverlayMessages() {
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event == null) return;
      try {
        final data = jsonDecode(event.toString()) as Map<String, dynamic>;
        final action = data['action'] as String?;

        switch (action) {
          case 'show_bar':
            setState(() => _showBar = true);
            break;
          case 'show_button':
            setState(() => _showBar = false);
            break;
          case 'update_settings':
            _loadSettings();
            break;
        }
      } catch (_) {
        // 忽略解析错误
      }
    });
  }

  void _onShowBar() {
    HapticFeedback.mediumImpact();
    setState(() => _showBar = true);
  }

  void _onHideBar() {
    HapticFeedback.lightImpact();
    setState(() => _showBar = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _showBar
            ? FloatingQuickNoteBar(
                key: const ValueKey('bar'),
                settings: _settings,
                onClose: _onHideBar,
              )
            : FloatingButton(
                key: const ValueKey('button'),
                settings: _settings,
                onDoubleTap: _onShowBar,
              ),
      ),
    );
  }
}
