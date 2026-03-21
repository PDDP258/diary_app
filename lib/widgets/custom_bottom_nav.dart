import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback onAddTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    // 获取底部安全区域高度（适配有虚拟导航栏的设备）
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isGestureNavigation = bottomPadding <= 16; // 手势导航底部padding较小
    
    // 基础高度 + 系统导航栏高度（如果不是手势导航）
    final navBarHeight = 80.0 + (isGestureNavigation ? 0.0 : bottomPadding);

    return Container(
      height: navBarHeight,
      margin: EdgeInsets.fromLTRB(16, 8, 16, isGestureNavigation ? 8 : 0),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        boxShadow: [
          BoxShadow(
            color: scheme.textDarkColor.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: scheme.primaryColor.withOpacity(0.08),
            blurRadius: 40,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 底部导航项
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              _buildNavItem(Icons.auto_stories_rounded, '日记', 0, scheme),
              _buildNavItem(Icons.calendar_month_rounded, '日历', 1, scheme),
              const SizedBox(width: 72), // 中间留出空间给FAB
              _buildNavItem(Icons.insights_rounded, '统计', 2, scheme),
              _buildNavItem(Icons.person_rounded, '我的', 3, scheme),
            ],
          ),
          // 中间大加号按钮 - 带动画效果
          Positioned(
            top: -20,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: onAddTap,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 300),
                  tween: Tween(begin: 1.0, end: 1.0),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
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
                              color: scheme.primaryColor.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                              spreadRadius: 0,
                            ),
                            BoxShadow(
                              color: scheme.primaryColor.withOpacity(0.2),
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
                    );
                  },
                ),
              ),
            ),
          ),
          ],
        ),
      ),
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
            splashColor: scheme.primaryColor.withOpacity(0.1),
            highlightColor: scheme.primaryColor.withOpacity(0.05),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: AppTheme.spring,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? scheme.primaryColor.withOpacity(0.1) : Colors.transparent,
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
                      color: isSelected ? scheme.primaryColor : scheme.textLightColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      color: isSelected ? scheme.primaryColor : scheme.textLightColor,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
                widget.backgroundColor.withOpacity(0.8),
                widget.backgroundColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.backgroundColor.withOpacity(0.4),
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
