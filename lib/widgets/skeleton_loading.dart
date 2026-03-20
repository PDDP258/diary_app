import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// 骨架屏加载组件
/// 
/// 基于 Interaction Design Skill：
/// - 保留布局结构，减少认知负担
/// - 脉动动画暗示加载中
/// - 200-300ms 过渡时长

/// 骨架屏基础 shimmer 效果
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const ShimmerEffect({
    super.key,
    required this.child,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: -1, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: GradientRotation(_animation.value * 0.5),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 骨架屏容器
class SkeletonContainer extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final Color? color;

  const SkeletonContainer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final baseColor = scheme.textLightColor.withOpacity(0.2);
    final highlightColor = scheme.textLightColor.withOpacity(0.1);

    return ShimmerEffect(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.mediumRadius),
        ),
      ),
    );
  }
}

/// 日记卡片骨架屏
class DiaryCardSkeleton extends StatelessWidget {
  const DiaryCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: [
          BoxShadow(
            color: scheme.textDarkColor.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期行
          Row(
            children: [
              const SkeletonContainer(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(12))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonContainer(width: 80, height: 16),
                    const SizedBox(height: 6),
                    const SkeletonContainer(width: 120, height: 12),
                  ],
                ),
              ),
              const SkeletonContainer(width: 60, height: 24, borderRadius: BorderRadius.all(Radius.circular(12))),
            ],
          ),
          const SizedBox(height: 16),
          // 标题
          const SkeletonContainer(width: double.infinity, height: 20),
          const SizedBox(height: 12),
          // 内容行
          const SkeletonContainer(width: double.infinity, height: 14),
          const SizedBox(height: 8),
          const SkeletonContainer(width: double.infinity, height: 14),
          const SizedBox(height: 8),
          const SkeletonContainer(width: 200, height: 14),
          const SizedBox(height: 16),
          // 图片区域（如果有）
          const SkeletonContainer(
            width: double.infinity,
            height: 150,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          const SizedBox(height: 12),
          // 标签行
          Row(
            children: [
              const SkeletonContainer(width: 60, height: 24, borderRadius: BorderRadius.all(Radius.circular(8))),
              const SizedBox(width: 8),
              const SkeletonContainer(width: 80, height: 24, borderRadius: BorderRadius.all(Radius.circular(8))),
              const Spacer(),
              const SkeletonContainer(width: 24, height: 24, borderRadius: BorderRadius.all(Radius.circular(12))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 列表骨架屏
class DiaryListSkeleton extends StatelessWidget {
  final int itemCount;

  const DiaryListSkeleton({
    super.key,
    this.itemCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return AnimatedOpacity(
          opacity: 1.0,
          duration: Duration(milliseconds: 200 + (index * 100)),
          child: const DiaryCardSkeleton(),
        );
      },
    );
  }
}

/// 统计页面骨架屏
class StatsSkeleton extends StatelessWidget {
  const StatsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部统计卡片
          const SkeletonContainer(
            width: double.infinity,
            height: 200,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          const SizedBox(height: 24),
          // 标题
          const SkeletonContainer(width: 120, height: 24),
          const SizedBox(height: 16),
          // 统计项
          Row(
            children: [
              Expanded(child: _buildStatItemSkeleton()),
              const SizedBox(width: 12),
              Expanded(child: _buildStatItemSkeleton()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatItemSkeleton()),
              const SizedBox(width: 12),
              Expanded(child: _buildStatItemSkeleton()),
            ],
          ),
          const SizedBox(height: 24),
          // 图表区域
          const SkeletonContainer(width: double.infinity, height: 24),
          const SizedBox(height: 16),
          const SkeletonContainer(
            width: double.infinity,
            height: 200,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItemSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const SkeletonContainer(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(8))),
          const SizedBox(height: 8),
          const SkeletonContainer(width: 60, height: 20),
          const SizedBox(height: 4),
          const SkeletonContainer(width: 80, height: 14),
        ],
      ),
    );
  }
}

/// 通用加载占位符
class LoadingPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const LoadingPlaceholder({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonContainer(
      width: width ?? double.infinity,
      height: height ?? 100,
      borderRadius: borderRadius,
    );
  }
}

/// 带淡入过渡的内容加载器
class ContentLoader extends StatelessWidget {
  final bool isLoading;
  final Widget skeleton;
  final Widget content;
  final Duration transitionDuration;

  const ContentLoader({
    super.key,
    required this.isLoading,
    required this.skeleton,
    required this.content,
    this.transitionDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: transitionDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: isLoading ? skeleton : content,
    );
  }
}
