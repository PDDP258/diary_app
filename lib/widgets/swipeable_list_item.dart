import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../services/sound_service.dart';

/// 可滑动列表项 - 支持删除操作
/// 
/// 基于 Interaction Design Skill：
/// - 手势交互反馈
/// - 300ms 状态过渡
/// - 触觉 + 视觉反馈
class SwipeableListItem extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;
  final String? confirmDeleteText;
  final bool enableHaptic;

  const SwipeableListItem({
    super.key,
    required this.child,
    this.onDelete,
    this.onEdit,
    this.onTap,
    this.confirmDeleteText,
    this.enableHaptic = true,
  });

  @override
  State<SwipeableListItem> createState() => _SwipeableListItemState();
}

class _SwipeableListItemState extends State<SwipeableListItem>
    with SingleTickerProviderStateMixin {
  double _dragExtent = 0;
  bool _isDeleting = false;
  static const double _threshold = 100;
  static const double _maxDrag = 150;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    // 只允许向左滑动（删除方向）
    if (details.delta.dx < 0 || _dragExtent < 0) {
      setState(() {
        _dragExtent = (_dragExtent + details.delta.dx).clamp(-_maxDrag, 0);
      });
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_dragExtent.abs() > _threshold && widget.onDelete != null) {
      // 超过阈值，触发删除
      _confirmDelete();
    } else {
      // 未超过阈值，回弹
      _resetPosition();
    }
  }

  void _resetPosition() {
    setState(() => _dragExtent = 0);
  }

  void _confirmDelete() {
    if (widget.enableHaptic) {
      HapticFeedback.mediumImpact();
    }
    SoundService.playClick();

    if (widget.confirmDeleteText != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认删除'),
          content: Text(widget.confirmDeleteText!),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resetPosition();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _isDeleting = true);
                Future.delayed(const Duration(milliseconds: 300), () {
                  widget.onDelete?.call();
                });
              },
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      setState(() => _isDeleting = true);
      Future.delayed(const Duration(milliseconds: 300), () {
        widget.onDelete?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final dragProgress = (_dragExtent.abs() / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: widget.onDelete != null ? _onHorizontalDragUpdate : null,
      onHorizontalDragEnd: widget.onDelete != null ? _onHorizontalDragEnd : null,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          _isDeleting ? -MediaQuery.of(context).size.width : _dragExtent,
          0,
          0,
        ),
        child: Stack(
          children: [
            // 背景层 - 删除按钮
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(dragProgress * 0.8),
                  borderRadius: BorderRadius.circular(AppTheme.largeRadius),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: Opacity(
                  opacity: dragProgress,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 24 + (dragProgress * 4),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '删除',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14 + (dragProgress * 2),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
            // 前景层 - 内容
            widget.child,
          ],
        ),
      ),
    );
  }
}

/// 可展开列表项 - 手风琴效果
class ExpandableListItem extends StatefulWidget {
  final Widget header;
  final Widget expandedContent;
  final bool initiallyExpanded;
  final VoidCallback? onExpansionChanged;

  const ExpandableListItem({
    super.key,
    required this.header,
    required this.expandedContent,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  @override
  State<ExpandableListItem> createState() => _ExpandableListItemState();
}

class _ExpandableListItemState extends State<ExpandableListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;
  late Animation<double> _rotation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _heightFactor = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.16, 1, 0.3, 1), // Ease-out
    );

    _rotation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    if (_isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
      widget.onExpansionChanged?.call();
    });
    
    HapticFeedback.lightImpact();
    SoundService.playClick();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.translucent,
          child: Row(
            children: [
              Expanded(child: widget.header),
              AnimatedBuilder(
                animation: _rotation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotation.value * 3.14159 * 2,
                    child: child,
                  );
                },
                child: const Icon(Icons.expand_more, size: 24),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        ClipRect(
          child: AnimatedBuilder(
            animation: _heightFactor,
            builder: (context, child) {
              return Align(
                alignment: Alignment.topCenter,
                heightFactor: _heightFactor.value,
                child: child,
              );
            },
            child: widget.expandedContent,
          ),
        ),
      ],
    );
  }
}

/// 带动画的列表项容器
class AnimatedListItemContainer extends StatelessWidget {
  final Widget child;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AnimatedListItemContainer({
    super.key,
    required this.child,
    required this.index,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: const Cubic(0.16, 1, 0.3, 1), // Ease-out
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 20),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AppTheme.largeRadius),
          splashColor: scheme.primaryColor.withOpacity(0.1),
          highlightColor: scheme.primaryColor.withOpacity(0.05),
          child: child,
        ),
      ),
    );
  }
}


