import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../config/design_tokens.dart';
import '../services/sound_service.dart';

/// 交互增强按钮 - 带缩放、涟漪、音效反馈
/// 
/// 遵循 Interaction Design Skill 原则：
/// - 100-150ms 微反馈
/// - Spring 动画替代线性动画
/// - 触觉 + 视觉 + 听觉三重反馈
class InteractiveButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final bool enableHaptic;
  final bool enableSound;
  final double scaleFactor;

  const InteractiveButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.backgroundColor,
    this.foregroundColor,
    this.width,
    this.height,
    this.borderRadius,
    this.padding,
    this.enableHaptic = true,
    this.enableSound = true,
    this.scaleFactor = 0.96,
  });

  @override
  State<InteractiveButton> createState() => _InteractiveButtonState();
}

class _InteractiveButtonState extends State<InteractiveButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    // 150ms 快速反馈 - 符合 Skill 的微交互时间标准
    _controller = AnimationController(
      duration: PrimitiveAnimation.fast,
      vsync: this,
    );

    // 使用 spring 动画 - 符合 Interaction Design Skill 的自然物理原则
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleFactor,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: PrimitiveAnimation.spring,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed == null) return;
    
    setState(() => _isPressed = true);
    _controller.forward();
    
    // 触觉反馈
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onPressed == null) return;
    
    setState(() => _isPressed = false);
    _controller.reverse();
    
    // 音效反馈
    if (widget.enableSound) {
      SoundService.playClick();
    }
    
    widget.onPressed!();
  }

  void _handleTapCancel() {
    if (widget.onPressed == null) return;
    
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              padding: widget.padding ?? 
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: widget.onPressed == null
                    ? (widget.backgroundColor ?? scheme.primaryColor).withValues(alpha: 0.3)
                    : (widget.backgroundColor ?? scheme.primaryColor),
                borderRadius: widget.borderRadius ?? 
                    BorderRadius.circular(AppTheme.largeRadius),
                boxShadow: _isPressed
                    ? [] // 按下时移除阴影（按压效果）
                    : [
                        BoxShadow(
                          color: (widget.backgroundColor ?? scheme.primaryColor)
                              .withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                          spreadRadius: -2,
                        ),
                      ],
              ),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: widget.foregroundColor ?? Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                child: Center(child: widget.child),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 交互增强图标按钮
class InteractiveIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? color;
  final double size;
  final String? tooltip;
  final bool enableHaptic;
  final bool enableSound;

  const InteractiveIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.color,
    this.size = 24,
    this.tooltip,
    this.enableHaptic = true,
    this.enableSound = true,
  });

  @override
  State<InteractiveIconButton> createState() => _InteractiveIconButtonState();
}

class _InteractiveIconButtonState extends State<InteractiveIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: PrimitiveAnimation.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(
        parent: _controller,
        curve: PrimitiveAnimation.easeOutExpo,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onPressed == null) return;
    
    _controller.forward().then((_) => _controller.reverse());
    
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }
    if (widget.enableSound) {
      SoundService.playClick();
    }
    
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    Widget button = AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.hardEdge,
            child: InkWell(
              onTap: widget.onPressed == null ? null : _handleTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  widget.icon,
                  color: widget.onPressed == null
                      ? (widget.color ?? scheme.textLightColor).withValues(alpha: 0.3)
                      : (widget.color ?? scheme.primaryColor),
                  size: widget.size,
                ),
              ),
            ),
          ),
        );
      },
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}


