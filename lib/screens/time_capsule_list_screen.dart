import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/time_capsule.dart';
import '../services/time_capsule_service.dart';
import '../widgets/interactive_button.dart';
import '../providers/theme_provider.dart';
import 'time_capsule_detail_screen.dart';
import 'time_capsule_write_screen.dart';

/// 时间胶囊列表页面
class TimeCapsuleListScreen extends StatefulWidget {
  const TimeCapsuleListScreen({super.key});

  @override
  State<TimeCapsuleListScreen> createState() => _TimeCapsuleListScreenState();
}

class _TimeCapsuleListScreenState extends State<TimeCapsuleListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TimeCapsule> _lockedCapsules = [];
  List<TimeCapsule> _unlockedCapsules = [];
  bool _isLoading = true;
  Map<String, int> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCapsules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCapsules() async {
    setState(() => _isLoading = true);
    
    final locked = await TimeCapsuleService.getLockedCapsules();
    final unlocked = await TimeCapsuleService.getUnlockedCapsules();
    final stats = await TimeCapsuleService.getCapsuleStats();
    
    // 检查待解锁的胶囊
    final pending = await TimeCapsuleService.getPendingUnlockCapsules();
    
    if (mounted) {
      setState(() {
        _lockedCapsules = locked;
        _unlockedCapsules = unlocked;
        _stats = stats;
        _isLoading = false;
      });
    }

    // 如果有待解锁的，提示用户
    if (pending.isNotEmpty && mounted) {
      _showUnlockNotification(pending.length);
    }
  }

  void _showUnlockNotification(int count) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.mark_email_unread, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '有 $count 封信件可以开启啦！',
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryMint,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        ),
        action: SnackBarAction(
          label: '查看',
          textColor: Colors.white,
          onPressed: () {
            _tabController.animateTo(1);
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '时间胶囊',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: scheme.primaryColor,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: scheme.primaryColor,
          unselectedLabelColor: scheme.textMediumColor,
          labelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 6),
                  Text('等待中 (${_lockedCapsules.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_open_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text('已开启 (${_unlockedCapsules.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLockedList(),
                _buildUnlockedList(),
              ],
            ),
      floatingActionButton: InteractiveButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TimeCapsuleWriteScreen(),
            ),
          );
          if (result == true) {
            _loadCapsules();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.darkColor, scheme.primaryColor],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            boxShadow: AppTheme.floatingShadow,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                '写给未来的自己',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockedList() {
    if (_lockedCapsules.isEmpty) {
      return _buildEmptyState(
        icon: Icons.lock_outline,
        title: '还没有时间胶囊',
        subtitle: '写一封信给未来的自己吧\n到期后会自动提醒你开启',
        buttonText: '创建时间胶囊',
        onButtonTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TimeCapsuleWriteScreen(),
            ),
          );
          if (result == true) {
            _loadCapsules();
          }
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCapsules,
      color: AppTheme.primaryMint,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        itemCount: _lockedCapsules.length,
        itemBuilder: (context, index) {
          final capsule = _lockedCapsules[index];
          return _buildLockedCapsuleCard(capsule);
        },
      ),
    );
  }

  Widget _buildUnlockedList() {
    if (_unlockedCapsules.isEmpty) {
      return _buildEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: '还没有开启的信件',
        subtitle: '时间胶囊到期后会在这里显示\n耐心等待那一天的到来吧',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCapsules,
      color: AppTheme.primaryMint,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        itemCount: _unlockedCapsules.length,
        itemBuilder: (context, index) {
          final capsule = _unlockedCapsules[index];
          return _buildUnlockedCapsuleCard(capsule);
        },
      ),
    );
  }

  Widget _buildLockedCapsuleCard(TimeCapsule capsule) {
    final scheme = AppTheme.schemeOf(context);
    final remainingDays = capsule.remainingDays;
    
    return InteractiveButton(
      onPressed: () {
        HapticFeedback.lightImpact();
        _showCapsulePreview(capsule);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.cardColor,
              scheme.cardColor.withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.largeRadius),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部锁定状态条
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryColor.withValues(alpha: 0.1),
                    scheme.lightColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.largeRadius),
                  topRight: Radius.circular(AppTheme.largeRadius),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock,
                    size: 16,
                    color: scheme.primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '封存中',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primaryColor,
                    ),
                  ),
                  const Spacer(),
                  if (capsule.moodEmoji != null) ...[
                    Text(
                      capsule.moodEmoji!,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: remainingDays <= 7
                          ? AppTheme.warmPink.withValues(alpha: 0.2)
                          : scheme.lightColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                    ),
                    child: Text(
                      remainingDays > 0 
                          ? '还有${capsule.waitingTimeDesc}'
                          : '今天可开启',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: remainingDays <= 7
                            ? AppTheme.warmPink
                            : scheme.darkColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 内容区
            Padding(
              padding: AppTheme.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    capsule.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  Text(
                    '创建于 ${capsule.createdTimeDesc}',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: scheme.textLightColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '解锁日期: ${_formatDate(capsule.unlockDate)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textLightColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockedCapsuleCard(TimeCapsule capsule) {
    final scheme = AppTheme.schemeOf(context);
    final isUnread = !capsule.isRead;
    
    return InteractiveButton(
      onPressed: () async {
        HapticFeedback.mediumImpact();
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TimeCapsuleDetailScreen(capsule: capsule),
          ),
        );
        if (result == true) {
          _loadCapsules();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.cardColor,
              scheme.cardColor.withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.largeRadius),
          boxShadow: AppTheme.cardShadow,
          border: isUnread
              ? Border.all(
                  color: scheme.primaryColor.withValues(alpha: 0.3),
                  width: 1.5,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部状态条
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    isUnread
                        ? scheme.primaryColor.withValues(alpha: 0.15)
                        : AppTheme.success.withValues(alpha: 0.1),
                    scheme.lightColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.largeRadius),
                  topRight: Radius.circular(AppTheme.largeRadius),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isUnread ? Icons.mark_email_unread : Icons.mark_email_read,
                    size: 16,
                    color: isUnread ? scheme.primaryColor : AppTheme.success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isUnread ? '新信件' : '已阅读',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isUnread ? scheme.primaryColor : AppTheme.success,
                    ),
                  ),
                  const Spacer(),
                  if (capsule.moodEmoji != null) ...[
                    Text(
                      capsule.moodEmoji!,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (isUnread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
            // 内容区
            Padding(
              padding: AppTheme.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    capsule.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  Text(
                    '来自 ${capsule.createdTimeDesc} 的你',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: scheme.textLightColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '等待了 ${_calculateWaitingTime(capsule.createdAt, capsule.unlockDate)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textLightColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCapsulePreview(TimeCapsule capsule) {
    final scheme = AppTheme.schemeOf(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        decoration: BoxDecoration(
          color: scheme.backgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.xxlRadius),
            topRight: Radius.circular(AppTheme.xxlRadius),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.textLightColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppTheme.spacingLg),
              Icon(
                Icons.lock_outline,
                size: 64,
                color: scheme.primaryColor.withValues(alpha: 0.5),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              Text(
                '这封信还在封存中',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                '还有 ${capsule.waitingTimeDesc} 才能开启',
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                '解锁日期: ${_formatDate(capsule.unlockDate)}',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.textLightColor,
                ),
              ),
              const SizedBox(height: AppTheme.spacingXl),
              InteractiveButton(
                onPressed: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.darkColor, scheme.primaryColor],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: const Text(
                    '我知道了',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? buttonText,
    VoidCallback? onButtonTap,
  }) {
    final scheme = AppTheme.schemeOf(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.lightColor.withValues(alpha: 0.5),
                    scheme.lightColor.withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 56,
                color: scheme.primaryColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: scheme.textMediumColor,
                height: 1.5,
              ),
            ),
            if (buttonText != null && onButtonTap != null) ...[
              const SizedBox(height: AppTheme.spacingXl),
              InteractiveButton(
                onPressed: onButtonTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.darkColor, scheme.primaryColor],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    boxShadow: AppTheme.floatingShadow,
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  String _calculateWaitingTime(DateTime created, DateTime unlock) {
    final difference = unlock.difference(created);
    final days = difference.inDays;
    
    if (days > 365) {
      final years = days ~/ 365;
      final remainingDays = days % 365;
      if (remainingDays > 30) {
        final months = remainingDays ~/ 30;
        return '$years年$months个月';
      }
      return '$years年';
    } else if (days > 30) {
      final months = days ~/ 30;
      return '$months个月';
    } else {
      return '$days天';
    }
  }
}
