import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/time_capsule.dart';
import '../services/time_capsule_service.dart';
import '../providers/theme_provider.dart';
import 'time_capsule_write_screen.dart';
import 'time_capsule_detail_screen.dart';

/// 时间胶囊列表页面 - 重新设计版
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
    final pending = await TimeCapsuleService.getPendingUnlockCapsules();
    
    if (mounted) {
      setState(() {
        _lockedCapsules = locked;
        _unlockedCapsules = unlocked;
        _isLoading = false;
      });
    }

    if (pending.isNotEmpty && mounted) {
      _showUnlockNotification(pending.length);
    }
  }

  void _showUnlockNotification(int count) {
    final scheme = AppTheme.schemeOf(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.mark_email_unread, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text('有 $count 封信件可以开启啦！'),
            ),
          ],
        ),
        backgroundColor: scheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: '查看',
          textColor: Colors.white,
          onPressed: () => _tabController.animateTo(1),
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
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // 顶部应用栏
          SliverAppBar(
            pinned: true,
            floating: true,
            elevation: 0,
            backgroundColor: scheme.backgroundColor,
            title: Text(
              '时间胶囊',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor,
              ),
            ),
            centerTitle: true,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: scheme.primaryColor,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: scheme.primaryColor,
              unselectedLabelColor: scheme.textLightColor,
              labelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
              tabs: [
                Tab(text: '等待中'),
                Tab(text: '已开启'),
              ],
            ),
          ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildLockedList(),
                  _buildUnlockedList(),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TimeCapsuleWriteScreen(),
            ),
          );
          if (result == true) _loadCapsules();
        },
        backgroundColor: scheme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          '写信给未来',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        elevation: 4,
      ),
    );
  }

  Widget _buildLockedList() {
    if (_lockedCapsules.isEmpty) {
      return _buildEmptyState(
        icon: Icons.lock_outline,
        title: '还没有时间胶囊',
        subtitle: '写一封信给未来的自己吧',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCapsules,
      color: AppTheme.primaryMint,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _lockedCapsules.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _LockedCapsuleCard(
            capsule: _lockedCapsules[index],
            onTap: () => _showCapsulePreview(_lockedCapsules[index]),
          );
        },
      ),
    );
  }

  Widget _buildUnlockedList() {
    if (_unlockedCapsules.isEmpty) {
      return _buildEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: '还没有开启的信件',
        subtitle: '时间胶囊到期后会在这里显示',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCapsules,
      color: AppTheme.primaryMint,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _unlockedCapsules.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _UnlockedCapsuleCard(
            capsule: _unlockedCapsules[index],
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TimeCapsuleDetailScreen(
                    capsule: _unlockedCapsules[index],
                  ),
                ),
              );
              if (result == true) _loadCapsules();
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final scheme = AppTheme.schemeOf(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: scheme.primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.textLightColor,
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
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.lightColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Icon(Icons.lock_outline, size: 48, color: scheme.primaryColor),
              const SizedBox(height: 16),
              Text(
                '这封信还在封存中',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '还有 ${capsule.waitingTimeDesc} 才能开启',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('我知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 锁定状态的胶囊卡片
class _LockedCapsuleCard extends StatelessWidget {
  final TimeCapsule capsule;
  final VoidCallback onTap;

  const _LockedCapsuleCard({
    required this.capsule,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final remainingDays = capsule.remainingDays;
    
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.lightColor.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 左侧图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lock,
                  color: scheme.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // 中间内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capsule.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '创建于 ${capsule.createdTimeDesc}',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textLightColor,
                      ),
                    ),
                  ],
                ),
              ),
              // 右侧倒计时
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: remainingDays <= 7
                      ? AppTheme.warmPink.withValues(alpha: 0.1)
                      : scheme.lightColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  remainingDays > 0 ? '还有$remainingDays天' : '今天',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: remainingDays <= 7
                        ? AppTheme.warmPink
                        : scheme.textMediumColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 已解锁的胶囊卡片
class _UnlockedCapsuleCard extends StatelessWidget {
  final TimeCapsule capsule;
  final VoidCallback onTap;

  const _UnlockedCapsuleCard({
    required this.capsule,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final isUnread = !capsule.isRead;
    
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isUnread 
              ? scheme.primaryColor.withValues(alpha: 0.3)
              : scheme.lightColor.withValues(alpha: 0.5),
          width: isUnread ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 左侧图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isUnread
                      ? scheme.primaryColor.withValues(alpha: 0.1)
                      : scheme.lightColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isUnread ? Icons.mark_email_unread : Icons.mark_email_read,
                  color: isUnread ? scheme.primaryColor : scheme.textLightColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // 中间内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capsule.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '来自 ${capsule.createdTimeDesc} 的你',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textLightColor,
                      ),
                    ),
                  ],
                ),
              ),
              // 右侧未读标记
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
      ),
    );
  }
}
