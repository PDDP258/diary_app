import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback onAddTap;
  final VoidCallback? onAddLongPress;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onAddTap,
    this.onAddLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    // 使用 Stack 让中间按钮可以超出父容器边界
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // 底部导航栏背景
        Container(
          height: 80,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.xlRadius),
            boxShadow: [
              BoxShadow(
                color: scheme.textDarkColor.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.xlRadius),
            // 2026-11-02 修正记录：
            //
            // 上一轮我基于 **debug 版**的观感把 sigma 从 20 降到 12，
            // 那是错误前提 —— debug 版帧率本来就不代表真实性能
            // （JIT、无 AOT、大量断言检查），release 版是好的。
            // 所以**盲降模糊半径没有必要**：用户没要求降级视觉，
            // 而这是全 App 的气质组件。已恢复 sigma = 20。
            //
            // 只保留 `RepaintBoundary`：它把导航栏独立成一个图层，
            // 页面内容滚动时不必连带重绘导航栏。这一项**没有任何视觉代价**，
            // 属于「顺手就能拿到」的收益，与 blur 半径无关。
            child: RepaintBoundary(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.cardColor.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(AppTheme.xlRadius),
                    border: Border.all(
                      color: scheme.lightColor.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildNavItem(Icons.auto_stories_rounded, '日记', 0, scheme),
                      _buildNavItem(Icons.calendar_month_rounded, '日历', 1, scheme),
                      const SizedBox(width: 72), // 中间留出空间给FAB
                      _buildNavItem(Icons.insights_rounded, '统计', 2, scheme),
                      _buildNavItem(Icons.person_rounded, '我的', 3, scheme),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // 中间大加号按钮 - 放在 Stack 顶层，可以超出边界
        Positioned(
          bottom: 12, // 导航栏高度80/2 + margin 8 - 按钮高度72/2 = 40 + 8 - 36 = 12
          child: GestureDetector(
            onTap: onAddTap,
            onLongPress: onAddLongPress,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.darkColor,
                    scheme.primaryColor,
                    scheme.lightColor,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.0, 0.5, 1.0],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: scheme.primaryColor.withValues(alpha: 0.2),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                    spreadRadius: -5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem(
      IconData icon, String label, int index, ThemeScheme scheme) {
    final isSelected = currentIndex == index;

    return Expanded(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(index),
            borderRadius: BorderRadius.circular(16),
            splashColor: scheme.primaryColor.withValues(alpha: 0.1),
            highlightColor: scheme.primaryColor.withValues(alpha: 0.05),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: AppTheme.spring,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? scheme.primaryColor.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: isSelected ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: AppTheme.spring,
                    child: Icon(
                      icon,
                      color: isSelected
                          ? scheme.primaryColor
                          : scheme.textLightColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      color: isSelected
                          ? scheme.primaryColor
                          : scheme.textLightColor,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: isSelected ? 0.5 : 0,
                      height: 1.0,
                    ),
                    child: Text(label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 悬浮操作按钮动画包装器
class AnimatedFAB extends StatefulWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color backgroundColor;

  const AnimatedFAB({
    super.key,
    required this.onTap,
    required this.icon,
    required this.backgroundColor,
  });

  @override
  State<AnimatedFAB> createState() => _AnimatedFABState();
}

class _AnimatedFABState extends State<AnimatedFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.backgroundColor.withValues(alpha: 0.8),
                widget.backgroundColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.backgroundColor.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            color: Colors.white,
            size: 36,
          ),
        ),
      ),
    );
  }
}
