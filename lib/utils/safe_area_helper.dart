import 'package:flutter/material.dart';
import 'dart:io';

/// 底部安全区域帮助类
/// 用于处理非全面屏设备的底部导航栏适配
class SafeAreaHelper {
  /// 获取底部安全区域高度（包括系统导航栏）
  static double getBottomPadding(BuildContext context) {
    // 使用 viewPadding 获取系统 UI 占用的空间（包括导航栏）
    return MediaQuery.of(context).viewPadding.bottom;
  }

  /// 获取底部导航栏高度（包括安全区域）
  /// 对于非全面屏设备，确保至少有 48dp 的底部空间（标准导航栏高度）
  static double getBottomNavHeight(BuildContext context) {
    final bottomPadding = getBottomPadding(context);
    // 如果系统没有提供底部 padding（非全面屏设备），使用默认值 48
    final safePadding = bottomPadding > 0 ? bottomPadding : 48.0;
    // 标准底部导航栏高度 + 安全区域
    return 80 + safePadding;
  }

  /// 获取内容底部间距（用于列表等可滚动内容）
  static double getContentBottomPadding(BuildContext context) {
    // 导航栏高度 + 额外间距
    return getBottomNavHeight(context) + 16;
  }

  /// 创建底部间距 Widget
  static Widget bottomSpacing(BuildContext context, {double extraHeight = 0}) {
    return SizedBox(height: getBottomNavHeight(context) + extraHeight);
  }

  /// 创建内容底部内边距
  static EdgeInsets contentPadding(BuildContext context) {
    return EdgeInsets.only(bottom: getContentBottomPadding(context));
  }

  /// 获取系统导航栏高度（仅系统部分，不包括应用导航栏）
  static double getSystemNavBarHeight(BuildContext context) {
    final bottomPadding = getBottomPadding(context);
    // 如果系统没有提供底部 padding，使用默认值 48（标准 Android 导航栏高度）
    return bottomPadding > 0 ? bottomPadding : 48.0;
  }
}

/// 底部安全区域包装器
/// 用于包裹需要底部安全区域适配的页面内容
class BottomSafeArea extends StatelessWidget {
  final Widget child;
  final bool addSpacing;
  final double extraHeight;

  const BottomSafeArea({
    super.key,
    required this.child,
    this.addSpacing = true,
    this.extraHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!addSpacing) {
      return child;
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: SafeAreaHelper.getBottomNavHeight(context) + extraHeight,
      ),
      child: child,
    );
  }
}

/// 底部间距 Widget
/// 用于在列表底部添加足够的空间，避免内容被导航栏遮挡
class BottomSpacing extends StatelessWidget {
  final double extraHeight;

  const BottomSpacing({super.key, this.extraHeight = 0});

  @override
  Widget build(BuildContext context) {
    return SafeAreaHelper.bottomSpacing(context, extraHeight: extraHeight);
  }
}

/// 系统导航栏安全区域
/// 用于确保内容不会被系统导航栏遮挡
class SystemNavBarSafeArea extends StatelessWidget {
  final Widget child;
  final Color? color;

  const SystemNavBarSafeArea({
    super.key,
    required this.child,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = SafeAreaHelper.getSystemNavBarHeight(context);
    
    return Container(
      color: color,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: child,
    );
  }
}
