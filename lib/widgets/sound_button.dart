import 'package:flutter/material.dart';
import '../services/sound_service.dart';

/// 带点击音效的按钮
class SoundButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;

  const SoundButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed == null
          ? null
          : () {
              SoundService.playClick();
              onPressed!();
            },
      style: style,
      child: child,
    );
  }
}

/// 带点击音效的图标按钮
class SoundIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? color;
  final double? iconSize;
  final String? tooltip;

  const SoundIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.color,
    this.iconSize,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed == null
          ? null
          : () {
              SoundService.playClick();
              onPressed!();
            },
      icon: Icon(icon, color: color, size: iconSize),
      tooltip: tooltip,
    );
  }
}

/// 带点击音效的列表项
class SoundListTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SoundListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap == null
          ? null
          : () {
              SoundService.playClick();
              onTap!();
            },
    );
  }
}

/// 带点击音效的手势检测器
class SoundGestureDetector extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const SoundGestureDetector({
    super.key,
    this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              SoundService.playClick();
              onTap!();
            },
      child: child,
    );
  }
}
