import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/floating_settings_service.dart';

/// 小浮窗按钮
///
/// 特性：
/// - 可自由拖拽
/// - 拖到屏幕边缘自动吸附并缩小为小线
/// - 点击小线展开回圆点
/// - 双击打开速记条
class FloatingButton extends StatefulWidget {
  final FloatingSettings settings;
  final VoidCallback onDoubleTap;

  const FloatingButton({
    super.key,
    required this.settings,
    required this.onDoubleTap,
  });

  @override
  State<FloatingButton> createState() => _FloatingButtonState();
}

class _FloatingButtonState extends State<FloatingButton> {
  bool _isCollapsed = false;
  Offset _position = const Offset(100, 100);
  Size _screenSize = Size.zero;

  static const double _collapsedWidth = 6;
  static const double _collapsedHeight = 60;
  static const double _edgeThreshold = 40;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
  }

  double get _windowSize =>
      FloatingSettingsService.getWindowSizePixels(widget.settings.windowSize);

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _position += details.delta;
      _constrainPosition();
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.settings.autoHideToEdge) return;

    // 判断是否靠近边缘
    final dx = _position.dx;
    final dy = _position.dy;
    final nearLeft = dx < _edgeThreshold;
    final nearRight = dx > _screenSize.width - _windowSize - _edgeThreshold;
    final nearTop = dy < _edgeThreshold;
    final nearBottom = dy > _screenSize.height - _windowSize - _edgeThreshold;

    if (nearLeft || nearRight || nearTop || nearBottom) {
      setState(() {
        _isCollapsed = true;
        if (nearLeft) _position = Offset(0, _position.dy);
        if (nearRight) _position = Offset(_screenSize.width - _collapsedWidth, _position.dy);
        if (nearTop) _position = Offset(_position.dx, 0);
        if (nearBottom) _position = Offset(_position.dx, _screenSize.height - _collapsedHeight);
      });
    }
  }

  void _constrainPosition() {
    final maxX = _screenSize.width - (_isCollapsed ? _collapsedWidth : _windowSize);
    final maxY = _screenSize.height - (_isCollapsed ? _collapsedHeight : _windowSize);
    _position = Offset(
      _position.dx.clamp(0, maxX),
      _position.dy.clamp(0, maxY),
    );
  }

  void _onTap() {
    if (_isCollapsed) {
      setState(() => _isCollapsed = false);
      HapticFeedback.lightImpact();
    }
  }

  void _handleDoubleTap() {
    if (!_isCollapsed) {
      widget.onDoubleTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = _isCollapsed
        ? const Size(_collapsedWidth, _collapsedHeight)
        : Size(_windowSize, _windowSize);

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTap: _onTap,
        onDoubleTap: _handleDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: _isCollapsed
                ? widget.settings.iconColor.withValues(alpha: 0.6)
                : widget.settings.iconColor.withValues(
                    alpha: widget.settings.iconOpacity),
            borderRadius: BorderRadius.circular(_isCollapsed ? 3 : _windowSize / 2),
            boxShadow: _isCollapsed
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: _isCollapsed
              ? null
              : Center(
                  child: Text(
                    widget.settings.iconEmoji,
                    style: TextStyle(fontSize: _windowSize * 0.5),
                  ),
                ),
        ),
      ),
    );
  }
}
