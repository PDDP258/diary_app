import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/design_tokens.dart';
import '../config/app_theme.dart';
import '../models/mood.dart';

/// ============================================================================
/// 日记应用专属交互组件
/// ============================================================================
///
/// 为日记应用定制的精美交互组件：
/// - 心情选择器动画
/// - 图片预览画廊
/// - 标签云
/// - 日记卡片 3D 倾斜效果

/// 心情选择器 - 带弹性动画
class MoodSelector extends StatefulWidget {
  final Mood? selectedMood;
  final Function(Mood) onMoodSelected;
  final List<Mood> moods;

  const MoodSelector({
    super.key,
    this.selectedMood,
    required this.onMoodSelected,
    required this.moods,
  });

  @override
  State<MoodSelector> createState() => _MoodSelectorState();
}

class _MoodSelectorState extends State<MoodSelector>
    with SingleTickerProviderStateMixin {
  int? _hoveredIndex;

  Color _parseColor(String colorStr) {
    return Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(widget.moods.length, (index) {
        final mood = widget.moods[index];
        final isSelected = widget.selectedMood?.id == mood.id;
        final isHovered = _hoveredIndex == index;
        final moodColor = _parseColor(mood.color);

        return GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            widget.onMoodSelected(mood);
          },
          onTapDown: (_) => setState(() => _hoveredIndex = index),
          onTapUp: (_) => setState(() => _hoveredIndex = null),
          onTapCancel: () => setState(() => _hoveredIndex = null),
          child: AnimatedContainer(
            duration: PrimitiveAnimation.fast,
            curve: PrimitiveAnimation.spring,
            transform: Matrix4.identity()
              ..scale(isSelected ? 1.2 : (isHovered ? 1.1 : 1.0)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 心情图标
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? moodColor.withValues(alpha: 0.2)
                        : scheme.cardColor,
                    border: Border.all(
                      color: isSelected ? moodColor : scheme.lightColor,
                      width: isSelected ? 3 : 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: moodColor.withValues(alpha: 0.4),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      mood.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 心情文字
                AnimatedDefaultTextStyle(
                  duration: PrimitiveAnimation.fast,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? moodColor : scheme.textMediumColor,
                  ),
                  child: Text(mood.name),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// 3D 倾斜卡片 - 跟随手指/鼠标倾斜
class TiltCard extends StatefulWidget {
  final Widget child;
  final double maxTilt;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TiltCard({
    super.key,
    required this.child,
    this.maxTilt = 0.1,
    this.duration = PrimitiveAnimation.fast,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> {
  double _tiltX = 0;
  double _tiltY = 0;
  bool _isPressed = false;

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    setState(() {
      _tiltY = (details.localPosition.dx / size.width - 0.5) * 2 * widget.maxTilt;
      _tiltX = -(details.localPosition.dy / size.height - 0.5) *
          2 *
          widget.maxTilt;
    });
  }

  void _onPanEnd([DragEndDetails? _]) {
    setState(() {
      _tiltX = 0;
      _tiltY = 0;
    });
  }

  void _onTapDown(_) {
    setState(() => _isPressed = true);
    HapticFeedback.lightImpact();
  }

  void _onTapUp(_) {
    setState(() => _isPressed = false);
    widget.onTap?.call();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanUpdate: (details) => _onPanUpdate(details, constraints.biggest),
          onPanEnd: _onPanEnd,
          onPanCancel: _onPanEnd,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onLongPress: widget.onLongPress,
          child: AnimatedContainer(
            duration: widget.duration,
            curve: PrimitiveAnimation.spring,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // 透视
              ..rotateX(_tiltX)
              ..rotateY(_tiltY)
              ..scale(_isPressed ? 0.98 : 1.0),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// 标签云 - 可交互的标签集合
class TagCloud extends StatelessWidget {
  final List<String> tags;
  final List<String>? selectedTags;
  final Function(String)? onTagTap;
  final Function(String)? onTagLongPress;
  final Color? tagColor;

  const TagCloud({
    super.key,
    required this.tags,
    this.selectedTags,
    this.onTagTap,
    this.onTagLongPress,
    this.tagColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Wrap(
      spacing: PrimitiveSpacing.sm,
      runSpacing: PrimitiveSpacing.sm,
      children: tags.map((tag) {
        final isSelected = selectedTags?.contains(tag) ?? false;

        return _AnimatedTag(
          label: tag,
          isSelected: isSelected,
          color: tagColor ?? scheme.primaryColor,
          onTap: () => onTagTap?.call(tag),
          onLongPress: () => onTagLongPress?.call(tag),
        );
      }).toList(),
    );
  }
}

class _AnimatedTag extends StatefulWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _AnimatedTag({
    required this.label,
    required this.isSelected,
    required this.color,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_AnimatedTag> createState() => _AnimatedTagState();
}

class _AnimatedTagState extends State<_AnimatedTag>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: PrimitiveAnimation.micro,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: PrimitiveAnimation.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: PrimitiveSpacing.lg,
            vertical: PrimitiveSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.color.withValues(alpha: 0.2)
                : scheme.cardColor,
            borderRadius: BorderRadius.circular(PrimitiveRadius.xl),
            border: Border.all(
              color: widget.isSelected ? widget.color : scheme.lightColor,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.2),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
              color: widget.isSelected ? widget.color : scheme.textMediumColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// 图片预览网格 - 带删除动画
class ImagePreviewGrid extends StatefulWidget {
  final List<String> images;
  final Function(int)? onDelete;
  final Function(int)? onTap;
  final double spacing;

  const ImagePreviewGrid({
    super.key,
    required this.images,
    this.onDelete,
    this.onTap,
    this.spacing = 8,
  });

  @override
  State<ImagePreviewGrid> createState() => _ImagePreviewGridState();
}

class _ImagePreviewGridState extends State<ImagePreviewGrid> {
  final Set<int> _deletingIndices = {};

  void _handleDelete(int index) {
    setState(() => _deletingIndices.add(index));
    Future.delayed(const Duration(milliseconds: 300), () {
      widget.onDelete?.call(index);
      setState(() => _deletingIndices.remove(index));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: widget.images.length,
      itemBuilder: (context, index) {
        final isDeleting = _deletingIndices.contains(index);

        return GestureDetector(
          onTap: () => widget.onTap?.call(index),
          child: AnimatedScale(
            scale: isDeleting ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: PrimitiveAnimation.spring,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 图片
                ClipRRect(
                  borderRadius: BorderRadius.circular(PrimitiveRadius.lg),
                  child: Image.network(
                    widget.images[index],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: scheme.lightColor,
                      child: Icon(Icons.image_not_supported,
                          color: scheme.textLightColor),
                    ),
                  ),
                ),
                // 删除按钮
                if (widget.onDelete != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _handleDelete(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 进度指示器 - 环形带动画
class AnimatedProgressRing extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final double size;
  final double strokeWidth;
  final Color? progressColor;
  final Color? backgroundColor;
  final Widget? center;

  const AnimatedProgressRing({
    super.key,
    required this.progress,
    this.size = 80,
    this.strokeWidth = 8,
    this.progressColor,
    this.backgroundColor,
    this.center,
  });

  @override
  State<AnimatedProgressRing> createState() => _AnimatedProgressRingState();
}

class _AnimatedProgressRingState extends State<AnimatedProgressRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: widget.progress).animate(
      CurvedAnimation(
        parent: _controller,
        curve: PrimitiveAnimation.easeOut,
      ),
    );

    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) {
      _animation = Tween<double>(
        begin: oldWidget.progress,
        end: widget.progress,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: PrimitiveAnimation.easeOut,
        ),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _ProgressRingPainter(
            progress: _animation.value,
            strokeWidth: widget.strokeWidth,
            progressColor: widget.progressColor ?? scheme.primaryColor,
            backgroundColor:
                widget.backgroundColor ?? scheme.lightColor.withValues(alpha: 0.3),
          ),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(child: widget.center),
          ),
        );
      },
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color progressColor;
  final Color backgroundColor;

  _ProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 背景圆环
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // 进度圆环
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          progressColor,
          progressColor.withValues(alpha: 0.5),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 字数统计指示器
class WordCountIndicator extends StatelessWidget {
  final int count;
  final int? goal;
  final bool showAnimation;

  const WordCountIndicator({
    super.key,
    required this.count,
    this.goal,
    this.showAnimation = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final progress = goal != null ? (count / goal!).clamp(0.0, 1.0) : 0.0;
    final isGoalReached = goal != null && count >= goal!;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PrimitiveSpacing.lg,
        vertical: PrimitiveSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isGoalReached
            ? PrimitiveColors.mint500.withValues(alpha: 0.1)
            : scheme.cardColor,
        borderRadius: BorderRadius.circular(PrimitiveRadius.xl),
        border: Border.all(
          color: isGoalReached ? PrimitiveColors.mint500 : scheme.lightColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGoalReached ? Icons.check_circle : Icons.edit_note,
            size: 18,
            color: isGoalReached ? PrimitiveColors.mint500 : scheme.textLightColor,
          ),
          const SizedBox(width: PrimitiveSpacing.sm),
          Text(
            '$count 字',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: scheme.textMediumColor,
            ),
          ),
          if (goal != null) ...[
            Text(
              ' / $goal',
              style: TextStyle(
                fontSize: 13,
                color: scheme.textLightColor,
              ),
            ),
            const SizedBox(width: PrimitiveSpacing.sm),
            SizedBox(
              width: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: scheme.lightColor,
                  valueColor: AlwaysStoppedAnimation(
                    isGoalReached ? PrimitiveColors.mint500 : scheme.primaryColor,
                  ),
                  minHeight: 4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
