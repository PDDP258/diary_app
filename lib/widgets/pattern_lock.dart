import 'package:flutter/material.dart';

/// 九宫格手势密码组件
///
/// 使用说明：
/// ```dart
/// PatternLock(
///   onPatternCompleted: (pattern) {
///     // pattern 是 [0-8] 的整数列表
///     print('输入的密码: $pattern');
///   },
/// )
/// ```
class PatternLock extends StatefulWidget {
  /// 密码输入完成回调
  final void Function(List<int> pattern)? onPatternCompleted;

  /// 密码输入中回调（手指移动时）
  final void Function(List<int> pattern)? onPatternUpdate;

  /// 是否显示错误状态
  final bool showError;

  /// 正确/错误提示文字
  final String? message;

  /// 主题色
  final Color? primaryColor;

  /// 错误颜色
  final Color? errorColor;

  /// 背景颜色
  final Color? backgroundColor;

  /// 圆点数量（默认 3x3）
  final int gridSize;

  /// 是否震动反馈
  final bool hapticFeedback;

  /// 自动重置时间（毫秒），0 表示不自动重置
  final int autoResetDelay;

  /// 重置回调
  final VoidCallback? onReset;

  /// 控制器
  final PatternLockController? controller;

  const PatternLock({
    super.key,
    this.onPatternCompleted,
    this.onPatternUpdate,
    this.showError = false,
    this.message,
    this.primaryColor,
    this.errorColor,
    this.backgroundColor,
    this.gridSize = 3,
    this.hapticFeedback = true,
    this.autoResetDelay = 1000,
    this.onReset,
    this.controller,
  });

  @override
  State<PatternLock> createState() => _PatternLockState();
}

class _PatternLockState extends State<PatternLock>
    with SingleTickerProviderStateMixin {
  // 当前选中的点
  final List<int> _selectedIndices = [];

  // 当前手指位置
  Offset? _currentPosition;

  // 每个点的位置缓存
  final List<Offset> _dotPositions = List.filled(9, Offset.zero);

  // 动画控制器（用于错误抖动）
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: 0), weight: 1),
    ]).animate(_shakeController);

    // 附加控制器
    widget.controller?.attach(this);
  }

  @override
  void didUpdateWidget(PatternLock oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当外部设置 showError 时，播放抖动动画
    if (widget.showError && !oldWidget.showError) {
      _shakeController.forward(from: 0);
    }

    // 处理控制器变更
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _shakeController.dispose();
    super.dispose();
  }

  /// 重置密码
  void reset() {
    setState(() {
      _selectedIndices.clear();
      _currentPosition = null;
    });
    widget.onReset?.call();
  }

  /// 获取当前密码
  List<int> get pattern => List.unmodifiable(_selectedIndices);

  @override
  Widget build(BuildContext context) {
    final primaryColor =
        widget.primaryColor ?? Theme.of(context).colorScheme.primary;
    final errorColor = widget.errorColor ?? Colors.red;
    final bgColor = widget.backgroundColor ?? Colors.transparent;

    final isError = widget.showError;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 提示文字
            if (widget.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  widget.message!,
                  style: TextStyle(
                    fontSize: 16,
                    color: isError ? errorColor : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // 九宫格
            AspectRatio(
              aspectRatio: 1,
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: Container(
                  color: Colors.transparent,
                  child: CustomPaint(
                    painter: _PatternPainter(
                      selectedIndices: _selectedIndices,
                      currentPosition: _currentPosition,
                      dotPositions: _dotPositions,
                      primaryColor: primaryColor,
                      errorColor: errorColor,
                      isError: isError,
                      gridSize: widget.gridSize,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 计算每个点的位置
                        _calculateDotPositions(constraints.biggest);
                        return const SizedBox.expand();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 计算每个点的位置
  void _calculateDotPositions(Size size) {
    final cellWidth = size.width / widget.gridSize;
    final cellHeight = size.height / widget.gridSize;

    for (int i = 0; i < 9; i++) {
      final row = i ~/ widget.gridSize;
      final col = i % widget.gridSize;
      _dotPositions[i] = Offset(
        col * cellWidth + cellWidth / 2,
        row * cellHeight + cellHeight / 2,
      );
    }
  }

  /// 获取触摸位置对应的点索引
  int? _getTouchedIndex(Offset position) {
    const touchRadius = 40.0; // 触摸检测半径

    for (int i = 0; i < 9; i++) {
      final distance = (position - _dotPositions[i]).distance;
      if (distance < touchRadius) {
        return i;
      }
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    final localPosition = details.localPosition;
    final index = _getTouchedIndex(localPosition);

    if (index != null) {
      setState(() {
        _selectedIndices.clear();
        _selectedIndices.add(index);
        _currentPosition = localPosition;
      });

      _triggerHaptic();
      widget.onPatternUpdate?.call(List.unmodifiable(_selectedIndices));
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_selectedIndices.isEmpty) return;

    final localPosition = details.localPosition;
    final index = _getTouchedIndex(localPosition);

    setState(() {
      _currentPosition = localPosition;

      // 如果触摸到新的点且未选中，添加到列表
      if (index != null && !_selectedIndices.contains(index)) {
        _selectedIndices.add(index);
        _triggerHaptic();
        widget.onPatternUpdate?.call(List.unmodifiable(_selectedIndices));
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_selectedIndices.length >= 4) {
      // 密码完成
      widget.onPatternCompleted?.call(List.unmodifiable(_selectedIndices));

      // 自动重置
      if (widget.autoResetDelay > 0 && !widget.showError) {
        Future.delayed(Duration(milliseconds: widget.autoResetDelay), () {
          if (mounted) {
            reset();
          }
        });
      }
    } else if (_selectedIndices.isNotEmpty) {
      // 密码太短，重置
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          reset();
        }
      });
    }

    setState(() {
      _currentPosition = null;
    });
  }

  void _triggerHaptic() {
    if (widget.hapticFeedback) {
      // 使用震动反馈
      Feedback.forTap(context);
    }
  }
}

/// 九宫格绘制器
class _PatternPainter extends CustomPainter {
  final List<int> selectedIndices;
  final Offset? currentPosition;
  final List<Offset> dotPositions;
  final Color primaryColor;
  final Color errorColor;
  final bool isError;
  final int gridSize;

  _PatternPainter({
    required this.selectedIndices,
    required this.currentPosition,
    required this.dotPositions,
    required this.primaryColor,
    required this.errorColor,
    required this.isError,
    required this.gridSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final activeColor = isError ? errorColor : primaryColor;

    // 绘制连接线
    if (selectedIndices.length >= 2) {
      final linePaint = Paint()
        ..color = activeColor.withValues(alpha: 0.5)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      for (int i = 0; i < selectedIndices.length - 1; i++) {
        final from = dotPositions[selectedIndices[i]];
        final to = dotPositions[selectedIndices[i + 1]];

        if (i == 0) {
          path.moveTo(from.dx, from.dy);
        }
        path.lineTo(to.dx, to.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // 绘制从最后一个点到手指位置的线
    if (currentPosition != null && selectedIndices.isNotEmpty) {
      final lastDot = dotPositions[selectedIndices.last];
      final linePaint = Paint()
        ..color = activeColor.withValues(alpha: 0.3)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(lastDot, currentPosition!, linePaint);
    }

    // 绘制圆点
    final normalPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final selectedPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final selectedRingPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.3)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;

    final dotRadius = size.width / (gridSize * 6);

    for (int i = 0; i < 9; i++) {
      final center = dotPositions[i];

      if (selectedIndices.contains(i)) {
        // 选中的点 - 绘制外圈
        canvas.drawCircle(center, dotRadius + 8, selectedRingPaint);
        canvas.drawCircle(center, dotRadius, selectedPaint);
      } else {
        // 未选中的点
        canvas.drawCircle(center, dotRadius, normalPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.selectedIndices != selectedIndices ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.isError != isError;
  }
}

/// 九宫格密码控制器
class PatternLockController {
  _PatternLockState? _state;

  /// 附加状态
  void attach(_PatternLockState state) {
    _state = state;
  }

  /// 分离状态
  void detach() {
    _state = null;
  }

  /// 重置密码
  void reset() {
    _state?.reset();
  }

  /// 获取当前密码
  List<int> get pattern {
    return _state?._selectedIndices ?? [];
  }
}

/// 简化的解锁按钮
class PatternLockButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isEnabled;
  final String text;
  final Color? color;

  const PatternLockButton({
    super.key,
    this.onTap,
    this.isEnabled = true,
    this.text = '确认',
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: isEnabled ? themeColor : themeColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: isEnabled ? Colors.white : Colors.white.withValues(alpha: 0.5),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
