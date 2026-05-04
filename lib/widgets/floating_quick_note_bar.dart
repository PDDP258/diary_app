import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/floating_notification_service.dart';
import '../services/floating_settings_service.dart';
import '../services/quick_note_service.dart';
import '../services/self_talk_service.dart';
import '../models/self_talk_message.dart';
import 'floating_settings_panel.dart';

/// 速记条横条
///
/// 特性：
/// - 设置按钮、粘贴按钮、输入框、存储按钮、关闭按钮
/// - 右下角拖动横杠调节大小
/// - 双击拖动横杠还原默认大小
/// - 字数统计（可选显示）
class FloatingQuickNoteBar extends StatefulWidget {
  final FloatingSettings settings;
  final VoidCallback onClose;

  const FloatingQuickNoteBar({
    super.key,
    required this.settings,
    required this.onClose,
  });

  @override
  State<FloatingQuickNoteBar> createState() => _FloatingQuickNoteBarState();
}

class _FloatingQuickNoteBarState extends State<FloatingQuickNoteBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  double _width = 320;
  double _height = 120;
  bool _isDragging = false;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _width = widget.settings.barWidth;
    _height = widget.settings.barHeight;
    _focusNode.requestFocus();
    _startAutoHideTimer();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _startAutoHideTimer() {
    if (!widget.settings.autoHideBar) return;
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(
      Duration(seconds: widget.settings.autoHideDelaySeconds),
      () {
        if (mounted && _controller.text.isEmpty) {
          widget.onClose();
        }
      },
    );
  }

  void _resetAutoHideTimer() {
    _startAutoHideTimer();
  }

  Future<void> _onPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      final text = data!.text!;
      final selection = _controller.selection;
      final newText = _controller.text.replaceRange(
        selection.start,
        selection.end,
        text,
      );
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + text.length),
      );
      HapticFeedback.lightImpact();
      _resetAutoHideTimer();
    }
  }

  Future<void> _onSave() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.heavyImpact();

    // 1. 保存到速记数据库
    await QuickNoteService.insert(text, tag: widget.settings.useTags ? '速记' : null);

    // 2. 同步到通知
    if (widget.settings.syncToNotification) {
      await FloatingNotificationService.showQuickNoteNotification(
        text,
        wordCount: text.length,
      );
    }

    // 3. 同步到自言自语
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await SelfTalkService.sendMessage(
      text,
      dateStr,
      senderType: SelfTalkSenderType.me,
    );

    // 4. 清空输入框
    _controller.clear();

    // 5. 可选自动隐藏
    if (widget.settings.autoHideBar) {
      widget.onClose();
    }
  }

  void _onResizeStart(DragStartDetails details) {
    setState(() => _isDragging = true);
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    setState(() {
      _width = (_width + details.delta.dx).clamp(200.0, 600.0);
      _height = (_height + details.delta.dy).clamp(80.0, 400.0);
    });
  }

  void _onResizeEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
    FloatingSettingsService.saveBarSize(_width, _height);
  }

  void _onResizeDoubleTap() {
    HapticFeedback.mediumImpact();
    FloatingSettingsService.resetBarSize().then((settings) {
      if (mounted) {
        setState(() {
          _width = settings.barWidth;
          _height = settings.barHeight;
        });
      }
    });
  }

  void _onShowSettings() {
    showDialog(
      context: context,
      builder: (context) => FloatingSettingsPanel(
        initialSettings: widget.settings,
        onSettingsChanged: (newSettings) {
          // 设置变更通过 FloatingSettingsService 持久化
          // 浮窗通过 overlayListener 接收更新通知
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColor = scheme.surface.withValues(
      alpha: widget.settings.inputOpacity,
    );
    final borderColor = scheme.outline.withValues(alpha: 0.3);

    return SizedBox(
      width: _width,
      height: _height,
      child: Stack(
        children: [
          // 主容器
          Container(
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部工具栏
                _buildToolbar(),
                // 输入区域
                Expanded(child: _buildInputArea()),
                // 底部字数统计
                if (widget.settings.showWordCount) _buildWordCount(),
              ],
            ),
          ),

          // 右下角拖动横杠
          Positioned(
            right: 4,
            bottom: 4,
            child: GestureDetector(
              onPanStart: _onResizeStart,
              onPanUpdate: _onResizeUpdate,
              onPanEnd: _onResizeEnd,
              onDoubleTap: _onResizeDoubleTap,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? scheme.primary.withValues(alpha: 0.5)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: CustomPaint(
                    size: const Size(20, 20),
                    painter: _ResizeHandlePainter(
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = scheme.onSurface.withValues(alpha: 0.7);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Row(
        children: [
          // 设置按钮
          _ToolButton(
            icon: Icons.settings_outlined,
            size: 18,
            color: iconColor,
            onTap: _onShowSettings,
          ),
          const SizedBox(width: 6),
          // 粘贴按钮
          _ToolButton(
            icon: Icons.content_paste_outlined,
            size: 18,
            color: iconColor,
            onTap: _onPaste,
          ),
          const Spacer(),
          // 存储按钮
          _ToolButton(
            icon: Icons.save_outlined,
            size: 20,
            color: scheme.primary,
            onTap: _onSave,
          ),
          const SizedBox(width: 6),
          // 关闭按钮
          _ToolButton(
            icon: Icons.close,
            size: 18,
            color: iconColor,
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontSize: widget.settings.fontSize,
          height: 1.4,
        ),
        decoration: InputDecoration(
          hintText: '快速记录...',
          hintStyle: TextStyle(
            fontSize: widget.settings.fontSize,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => _resetAutoHideTimer(),
        onSubmitted: (_) => _onSave(),
      ),
    );
  }

  Widget _buildWordCount() {
    final count = _controller.text.length;
    return Padding(
      padding: const EdgeInsets.only(right: 28, bottom: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$count 字',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

/// 工具栏小按钮
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

/// 右下角 resize 手柄绘制器
class _ResizeHandlePainter extends CustomPainter {
  final Color color;

  _ResizeHandlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // 画两条斜线形成 L 形
    canvas.drawLine(
      Offset(size.width - 2, size.height - 8),
      Offset(size.width - 2, size.height - 2),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 8, size.height - 2),
      Offset(size.width - 2, size.height - 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
