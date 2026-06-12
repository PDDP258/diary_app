import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Bento Box 风格卡片组件
/// 参考 pddp258.github.io/PROJECT_INTRO FeatureGrid + Apple Bento Grid 设计
///
/// 模块化卡片系统，支持不同尺寸比例和 hover 效果
///
/// 用法:
/// ```dart
/// BentoCard(
///   span: BentoCardSpan.medium,
///   onTap: () => ...,
///   child: YourContent(),
/// )
/// ```
class BentoCard extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 卡片尺寸比例
  final BentoCardSpan span;

  /// 点击回调
  final VoidCallback? onTap;

  /// 背景色
  final Color? backgroundColor;

  /// 圆角（默认 20px）
  final double borderRadius;

  /// 是否使用阴影
  final bool elevated;

  /// 是否启用交互效果（hover/tap）
  final bool interactive;

  /// hover 上移距离
  final double hoverLift;

  const BentoCard({
    super.key,
    required this.child,
    this.span = BentoCardSpan.medium,
    this.onTap,
    this.backgroundColor,
    this.borderRadius = 20.0,
    this.elevated = false,
    this.interactive = true,
    this.hoverLift = 4.0,
  });

  @override
  State<BentoCard> createState() => _BentoCardState();
}

class _BentoCardState extends State<BentoCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.interactive && widget.onTap != null
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.interactive && widget.onTap != null
          ? (_) => setState(() {
                _isPressed = false;
                widget.onTap?.call();
              })
          : null,
      onTapCancel: widget.interactive
          ? () => setState(() => _isPressed = false)
          : null,
      child: MouseRegion(
        onEnter: widget.interactive
            ? (_) => setState(() => _isHovered = true)
            : null,
        onExit: widget.interactive
            ? (_) => setState(() => _isHovered = false)
            : null,
        child: AnimatedContainer(
          duration: AppTheme.quickDuration,
          curve: AppTheme.smoothDecel,
          transform: _isHovered
              ? (Matrix4.identity()
                  // ignore: deprecated_member_use
                  ..translate(0.0, -widget.hoverLift, 0.0))
              : (_isPressed
                  ? (Matrix4.identity()
                      // ignore: deprecated_member_use
                      ..scale(0.98))
                  : Matrix4.identity()),
          decoration: AppTheme.bentoDecoration(
            color: widget.backgroundColor,
            borderRadius: widget.borderRadius,
            elevated: widget.elevated || _isHovered,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Bento Box 网格布局
///
/// 用法:
/// ```dart
/// BentoGrid(
///   children: [
///     BentoCard(span: BentoCardSpan.large, child: ...),
///     BentoCard(span: BentoCardSpan.small, child: ...),
///     BentoCard(span: BentoCardSpan.medium, child: ...),
///   ],
/// )
/// ```
class BentoGrid extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final EdgeInsetsGeometry? padding;
  final int columns;

  const BentoGrid({
    super.key,
    required this.children,
    this.gap = 16.0,
    this.padding,
    this.columns = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalGap = gap * (columns - 1);
          final cellWidth = (constraints.maxWidth - totalGap) / columns;
          final cellHeight = cellWidth; // 默认正方形

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: children.map((child) {
              if (child is BentoCard) {
                final span = child.span;
                double width;
                double height;

                switch (span) {
                  case BentoCardSpan.small:
                    width = cellWidth;
                    height = cellHeight;
                  case BentoCardSpan.medium:
                    width = cellWidth * 2 + gap;
                    height = cellHeight;
                  case BentoCardSpan.large:
                    width = cellWidth * 2 + gap;
                    height = cellHeight * 2 + gap;
                  case BentoCardSpan.wide:
                    width = cellWidth * 3 + gap * 2;
                    height = cellHeight;
                  case BentoCardSpan.tall:
                    width = cellWidth;
                    height = cellHeight * 2 + gap;
                  case BentoCardSpan.full:
                    width = constraints.maxWidth;
                    height = cellHeight;
                }

                return SizedBox(
                  width: width,
                  height: height,
                  child: child,
                );
              }
              return SizedBox(
                width: cellWidth,
                height: cellHeight,
                child: child,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

/// Bento 卡片尺寸比例
enum BentoCardSpan {
  /// 1x1 小方块
  small,

  /// 2x1 横条
  medium,

  /// 2x2 大方块
  large,

  /// 3x1 宽条
  wide,

  /// 1x2 竖条
  tall,

  /// 全宽
  full,
}