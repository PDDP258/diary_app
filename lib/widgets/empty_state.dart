import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';

/// 空状态类型
enum EmptyStateType {
  diary,      // 日记为空
  search,     // 搜索无结果
  tag,        // 标签为空
  photo,      // 照片为空
  mood,       // 心情为空
  anniversary,// 纪念日为空
  backup,     // 备份为空
  network,    // 网络错误
  error,      // 通用错误
}

/// 统一的空状态组件
/// 
/// 功能：
/// 1. 提供多种预设空状态类型
/// 2. 支持自定义图标、标题、描述
/// 3. 支持操作按钮
/// 4. 统一的视觉风格
class EmptyState extends StatelessWidget {
  final EmptyStateType type;
  final String? title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? customIcon;

  const EmptyState({
    super.key,
    this.type = EmptyStateType.diary,
    this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.customIcon,
  });

  /// 获取预设配置
  _EmptyStateConfig _getConfig(ThemeScheme scheme) {
    switch (type) {
      case EmptyStateType.diary:
        return _EmptyStateConfig(
          icon: Icons.book_outlined,
          title: '还没有日记',
          description: '开始记录你的第一篇日记吧',
          actionLabel: '写日记',
          iconColor: scheme.primaryColor,
        );
      case EmptyStateType.search:
        return _EmptyStateConfig(
          icon: Icons.search_off,
          title: '没有找到结果',
          description: '尝试调整搜索条件',
          iconColor: scheme.textMediumColor,
        );
      case EmptyStateType.tag:
        return _EmptyStateConfig(
          icon: Icons.label_outline,
          title: '还没有标签',
          description: '为日记添加标签，方便分类管理',
          actionLabel: '添加标签',
          iconColor: scheme.primaryColor,
        );
      case EmptyStateType.photo:
        return _EmptyStateConfig(
          icon: Icons.photo_library_outlined,
          title: '还没有照片',
          description: '在日记中添加照片，记录美好瞬间',
          iconColor: scheme.primaryColor,
        );
      case EmptyStateType.mood:
        return _EmptyStateConfig(
          icon: Icons.sentiment_satisfied_outlined,
          title: '还没有心情记录',
          description: '记录每天的心情变化',
          iconColor: Colors.orange,
        );
      case EmptyStateType.anniversary:
        return _EmptyStateConfig(
          icon: Icons.favorite_outline,
          title: '还没有纪念日',
          description: '添加重要的纪念日，不再错过特殊日子',
          actionLabel: '添加纪念日',
          iconColor: Colors.red,
        );
      case EmptyStateType.backup:
        return _EmptyStateConfig(
          icon: Icons.cloud_off_outlined,
          title: '还没有备份',
          description: '定期备份数据，防止意外丢失',
          actionLabel: '立即备份',
          iconColor: scheme.primaryColor,
        );
      case EmptyStateType.network:
        return _EmptyStateConfig(
          icon: Icons.wifi_off_outlined,
          title: '网络连接失败',
          description: '请检查网络设置后重试',
          actionLabel: '重试',
          iconColor: scheme.errorColor,
        );
      case EmptyStateType.error:
        return _EmptyStateConfig(
          icon: Icons.error_outline,
          title: '出错了',
          description: '请稍后重试',
          actionLabel: '重试',
          iconColor: scheme.errorColor,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final config = _getConfig(scheme);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: (config.iconColor ?? scheme.primaryColor).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: customIcon ?? Icon(
                  config.icon,
                  size: 56,
                  color: config.iconColor ?? scheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 标题
            Text(
              title ?? config.title ?? '',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: scheme.textDarkColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // 描述
            Text(
              description ?? config.description ?? '',
              style: TextStyle(
                fontSize: 14,
                color: scheme.textMediumColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 操作按钮
            if ((actionLabel ?? config.actionLabel) != null && onAction != null)
              ElevatedButton.icon(
                onPressed: onAction,
                icon: Icon(_getActionIcon(config)),
                label: Text(actionLabel ?? config.actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: config.iconColor ?? scheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getActionIcon(_EmptyStateConfig config) {
    switch (type) {
      case EmptyStateType.diary:
        return Icons.edit;
      case EmptyStateType.search:
        return Icons.refresh;
      case EmptyStateType.tag:
        return Icons.add;
      case EmptyStateType.photo:
        return Icons.add_photo_alternate;
      case EmptyStateType.mood:
        return Icons.sentiment_satisfied;
      case EmptyStateType.anniversary:
        return Icons.favorite;
      case EmptyStateType.backup:
        return Icons.backup;
      case EmptyStateType.network:
      case EmptyStateType.error:
        return Icons.refresh;
    }
  }
}

/// 空状态配置
class _EmptyStateConfig {
  final IconData? icon;
  final String? title;
  final String? description;
  final String? actionLabel;
  final Color? iconColor;

  _EmptyStateConfig({
    this.icon,
    this.title,
    this.description,
    this.actionLabel,
    this.iconColor,
  });
}

/// 简化的空状态组件
class SimpleEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;

  const SimpleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: scheme.lightColor,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              style: TextStyle(
                fontSize: 14,
                color: scheme.textLightColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
