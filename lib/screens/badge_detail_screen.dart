import 'package:flutter/material.dart';
import '../config/app_theme.dart' show AppTheme;
import '../providers/theme_provider.dart' show ThemeScheme;
import '../services/badge_service.dart' as badge_service;

/// 徽章详情页面
/// 显示单个徽章的详细信息和获取条件
class BadgeDetailScreen extends StatelessWidget {
  final badge_service.Badge badge;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const BadgeDetailScreen({
    super.key,
    required this.badge,
    required this.isUnlocked,
    this.unlockedAt,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: CustomScrollView(
        slivers: [
          // 顶部应用栏
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: scheme.backgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: scheme.textDarkColor),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      badge.color.withValues(alpha: 0.3),
                      scheme.backgroundColor,
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),
                      // 徽章大图标
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isUnlocked
                                ? [
                                    badge.color.withValues(alpha: 0.9),
                                    badge.color.withValues(alpha: 0.5),
                                  ]
                                : [
                                    scheme.lightColor.withValues(alpha: 0.5),
                                    scheme.lightColor.withValues(alpha: 0.2),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: isUnlocked
                              ? [
                                  BoxShadow(
                                    color: badge.color.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                    spreadRadius: -5,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            isUnlocked ? badge.emoji : '🔒',
                            style: const TextStyle(fontSize: 60),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 徽章名称
                      Text(
                        isUnlocked ? badge.name : '???',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: scheme.textDarkColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 内容区域
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 状态卡片
                  _buildStatusCard(scheme),
                  const SizedBox(height: 24),

                  // 徽章信息
                  _buildInfoSection(scheme),
                  const SizedBox(height: 24),

                  // 获取条件
                  _buildConditionSection(scheme),
                  const SizedBox(height: 24),

                  // 提示信息
                  if (!isUnlocked) _buildHintSection(scheme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建状态卡片
  Widget _buildStatusCard(ThemeScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isUnlocked
              ? [
                  badge.color.withValues(alpha: 0.15),
                  badge.color.withValues(alpha: 0.05),
                ]
              : [
                  scheme.lightColor.withValues(alpha: 0.3),
                  scheme.lightColor.withValues(alpha: 0.1),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUnlocked
              ? badge.color.withValues(alpha: 0.3)
              : scheme.lightColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isUnlocked ? Icons.verified : Icons.lock_outline,
                color: isUnlocked ? badge.color : scheme.textLightColor,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                isUnlocked ? '已获得' : '未解锁',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isUnlocked ? badge.color : scheme.textLightColor,
                ),
              ),
            ],
          ),
          if (isUnlocked && unlockedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              '解锁时间：${_formatDate(unlockedAt!)}',
              style: TextStyle(
                fontSize: 14,
                color: scheme.textMediumColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建信息区域
  Widget _buildInfoSection(ThemeScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '徽章信息',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: scheme.textDarkColor,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildInfoRow('稀有度', _getRarityText(badge.rarity), badge.color, scheme),
              const Divider(height: 24),
              _buildInfoRow('分类', _getCategoryText(badge.type), scheme.primaryColor, scheme),
              const Divider(height: 24),
              _buildInfoRow('徽章ID', badge.id, scheme.textLightColor, scheme),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(String label, String value, Color valueColor, ThemeScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: scheme.textMediumColor,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  /// 构建条件区域
  Widget _buildConditionSection(ThemeScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '获取条件',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: scheme.textDarkColor,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                badge.description,
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.textDarkColor,
                  height: 1.6,
                ),
              ),
              if (isUnlocked) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '已完成',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 构建提示区域
  Widget _buildHintSection(ThemeScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '继续写日记来完成这个徽章的解锁条件吧！',
              style: TextStyle(
                fontSize: 14,
                color: Colors.orange[700],
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getRarityText(badge_service.BadgeRarity rarity) {
    switch (rarity) {
      case badge_service.BadgeRarity.common:
        return '普通';
      case badge_service.BadgeRarity.uncommon:
        return '罕见';
      case badge_service.BadgeRarity.rare:
        return '稀有';
      case badge_service.BadgeRarity.epic:
        return '史诗';
      case badge_service.BadgeRarity.legendary:
        return '传说';
    }
  }

  String _getCategoryText(badge_service.BadgeType type) {
    switch (type) {
      case badge_service.BadgeType.milestone:
        return '里程碑';
      case badge_service.BadgeType.streak:
        return '连续记录';
      case badge_service.BadgeType.content:
        return '内容创作';
      case badge_service.BadgeType.time:
        return '时间类';
      case badge_service.BadgeType.photo:
        return '照片类';
      case badge_service.BadgeType.emotion:
        return '情感类';
      case badge_service.BadgeType.hidden:
        return '隐藏徽章';
      case badge_service.BadgeType.special:
        return '特殊成就';
      case badge_service.BadgeType.totalCount:
        return '累计成就';
      default:
        return '其他';
    }
  }
}
