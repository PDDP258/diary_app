import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../providers/diary_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/platform_helpers.dart';
import '../widgets/widgets.dart';
import '../services/database_service.dart';
import 'diary_detail_screen.dart';
import 'write_diary_screen.dart';
import 'gacha_screen.dart';
import 'smart_recall_screen_v2.dart';
import 'self_talk_screen.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final provider = context.read<DiaryProvider>();
      if (!provider.isLoadingMore && provider.hasMoreData) {
        provider.loadMoreDiaries();
      }
    }
  }

  /// 长按日记卡片：显示编辑/删除菜单
  void _onDiaryLongPress(Diary diary) {
    HapticFeedback.mediumImpact();
    final scheme = AppTheme.schemeOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: scheme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: scheme.primaryColor),
                title: Text('编辑日记', style: TextStyle(color: scheme.textDarkColor)),
                onTap: () {
                  Navigator.pop(context);
                  _editDiary(diary);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.errorColor),
                title: Text('删除日记', style: TextStyle(color: scheme.errorColor)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteDiary(diary);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 编辑日记
  void _editDiary(Diary diary) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriteDiaryScreen(
          diary: diary,
          selectedDate: DateFormat('yyyy-MM-dd').parse(diary.date),
        ),
      ),
    );
    if (result == true && mounted) {
      context.read<DiaryProvider>().loadDiaries();
    }
  }

  /// 确认删除日记
  void _confirmDeleteDiary(Diary diary) async {
    final scheme = AppTheme.schemeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('删除日记？', style: TextStyle(color: scheme.textDarkColor)),
        content: Text(
          '此操作不可恢复，确定要删除 ${DateFormat('M月d日', 'zh_CN').format(DateFormat('yyyy-MM-dd').parse(diary.date))} 的日记吗？',
          style: TextStyle(color: scheme.textMediumColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: scheme.textLightColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除', style: TextStyle(color: scheme.errorColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await DatabaseService.deleteDiary(diary.id!);
        if (mounted) {
          context.read<DiaryProvider>().loadDiaries();
          ToastManager().show(context, message: '日记已删除', type: ToastType.success);
        }
      } catch (e) {
        if (mounted) {
          ToastManager().show(context, message: '删除失败：$e', type: ToastType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Consumer<DiaryProvider>(
      builder: (context, provider, child) {
        final diaries = provider.diaries;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            // 底部不处理，让 MainScreen 的 SafeArea 统一处理
            bottom: false,
            child: Column(
              children: [
                // 顶部标题栏 - 玻璃态效果
                _buildHeader(scheme, diaries.length),

                // 智能回忆卡片已整合到顶部header中

                // 日记列表
                Expanded(
                  child: diaries.isEmpty
                      ? _buildEmptyState(scheme)
                      : RefreshIndicator(
                          onRefresh: () => provider.loadDiaries(),
                          color: scheme.primaryColor,
                          backgroundColor: scheme.cardColor,
                          strokeWidth: 3,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, top: 8, bottom: 16),
                            itemCount:
                                diaries.length + (provider.hasMoreData ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= diaries.length) {
                                return _buildLoadMoreIndicator(scheme);
                              }

                              final diary = diaries[index];
                              final prevDiary =
                                  index > 0 ? diaries[index - 1] : null;

                              // 只对前10个日记应用入场动画
                              if (index < 10 &&
                                  _animationController.status ==
                                      AnimationStatus.forward) {
                                return AnimatedBuilder(
                                  animation: _animationController,
                                  builder: (context, child) {
                                    final delay = index * 0.05;
                                    final value =
                                        (_animationController.value - delay)
                                            .clamp(0.0, 1.0);
                                    return FadeTransition(
                                      opacity: AlwaysStoppedAnimation(
                                          value.clamp(0.0, 1.0)),
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.2),
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: _animationController,
                                            curve: Interval(
                                              delay.clamp(0.0, 0.8),
                                              (delay + 0.2).clamp(0.0, 1.0),
                                              curve: Curves.easeOut,
                                            ),
                                          ),
                                        ),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child:
                                      _buildDiaryItem(diary, prevDiary, scheme),
                                );
                              }

                              // 其他日记直接显示，不应用动画
                              return _buildDiaryItem(diary, prevDiary, scheme);
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeScheme scheme, int diaryCount) {
    // 获取用户设置
    final settings = context.watch<SettingsProvider>();
    final userName = settings.userName;
    final userSignature = settings.userSignature;
    final customAvatarPath = settings.customAvatarPath;
    final userEmoji = settings.userEmoji;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        // 增强毛玻璃效果
        color: scheme.cardColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        border: Border.all(
          color: scheme.lightColor.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：头像信息 + 篇数
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：头像 + 昵称/签名
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 头像（优先使用自定义头像，否则使用emoji）
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: scheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.primaryColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: customAvatarPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(customAvatarPath),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Text(
                                    userEmoji,
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                );
                              },
                            ),
                          )
                        : Center(
                            child: Text(
                              userEmoji,
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                    ),
                    const SizedBox(width: 14),
                    // 昵称和签名（上下关系）
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 昵称
                          Text(
                            '$userName的日记',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: scheme.textDarkColor,
                              letterSpacing: -0.5,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // 签名
                          Text(
                            userSignature,
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.textMediumColor,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 右上：已移到底部入口区域
            ],
          ),
          const SizedBox(height: 12),
          // 第二行：四个等宽入口整齐排列
          Row(
            children: [
              // 1. 自言自语
              Expanded(
                child: _buildHeaderActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: '自言自语',
                  scheme: scheme,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SelfTalkScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 2. 扭蛋
              Expanded(
                child: _buildHeaderActionButton(
                  icon: Icons.casino_outlined,
                  label: '扭蛋',
                  scheme: scheme,
                  isPrimary: true,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GachaScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 3. 珍贵的回忆
              Expanded(
                child: _buildHeaderActionButton(
                  icon: Icons.auto_awesome,
                  label: '回忆',
                  scheme: scheme,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SmartRecallScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 4. 篇数
              Expanded(
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$diaryCount 篇',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionButton({
    required IconData icon,
    required String label,
    required ThemeScheme scheme,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isPrimary
                ? scheme.primaryColor.withValues(alpha: 0.15)
                : scheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPrimary
                  ? scheme.primaryColor.withValues(alpha: 0.4)
                  : scheme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: isPrimary ? scheme.primaryColor : scheme.textMediumColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isPrimary ? scheme.primaryColor : scheme.textDarkColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primaryColor),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '加载更多...',
            style: TextStyle(
              fontSize: 12,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BouncyCard(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.lightColor.withValues(alpha: 0.5),
                    scheme.primaryColor.withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppTheme.xlRadius),
              ),
              child: Icon(
                Icons.menu_book_outlined,
                size: 64,
                color: scheme.primaryColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '还没有日记',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: scheme.textDarkColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方 + 开始记录美好时光',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 24),
          InteractiveButton(
            onPressed: () {},
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    size: 20,
                    color: scheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '开始写日记',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiaryItem(Diary diary, Diary? prevDiary, ThemeScheme scheme) {
    final date = DateFormat('yyyy-MM-dd').parse(diary.date);
    final day = DateFormat('dd').format(date);
    final weekday = DateFormat('E', 'zh_CN').format(date);
    final month = DateFormat('yyyy年M月', 'zh_CN').format(date);

    bool showMonthDivider = false;
    if (prevDiary != null) {
      final prevDate = DateFormat('yyyy-MM-dd').parse(prevDiary.date);
      final prevMonth = DateFormat('yyyy年M月', 'zh_CN').format(prevDate);
      if (month != prevMonth) {
        showMonthDivider = true;
      }
    }

    return Column(
      children: [
        // 月份分隔
        if (showMonthDivider || prevDiary == null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primaryColor, scheme.lightColor],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  month,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: scheme.textDarkColor,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),

        // 日记卡片 - 3D倾斜 + 玻璃态效果
        TiltCard(
          maxTilt: 0.04,
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DiaryDetailScreen(diary: diary),
              ),
            );
            if (result == true) {
              context.read<DiaryProvider>().loadDiaries();
            }
          },
          onLongPress: () => _onDiaryLongPress(diary),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: scheme.cardColor,
              borderRadius: BorderRadius.circular(AppTheme.xlRadius),
              border: Border.all(
                color: scheme.primaryColor.withValues(alpha: 0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadowColor.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 日期行 + 心情
                  Row(
                    children: [
                      // 日期显示
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.lightColor.withValues(alpha: 0.5),
                              scheme.lightColor.withValues(alpha: 0.2),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(
                              AppTheme.mediumRadius),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              day,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: scheme.primaryColor,
                              ),
                            ),
                            Text(
                              weekday,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.textLightColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 标题
                                  if (diary.title != null &&
                                      diary.title!.isNotEmpty)
                                    Text(
                                      diary.title!,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.textDarkColor,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  else
                                    Text(
                                      '无标题',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: scheme.textLightColor,
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  // 心情表情
                                  if (diary.moodEmoji != null)
                                    Row(
                                      children: [
                                        Text(
                                          diary.moodEmoji!,
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                        if (diary.moodName != null) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            diary.moodName!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.textMediumColor,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            // 收藏标记
                            if (diary.isFavorite)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.favorite_rounded,
                                  color: Colors.red,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),

                        // 内容
                        if (diary.content != null && diary.content!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              diary.content!,
                              style: TextStyle(
                                fontSize: 15,
                                color: scheme.textMediumColor,
                                height: 1.6,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        // 图片预览
                        if (diary.images != null && diary.images!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: diary.imageList.length.clamp(0, 4),
                                itemBuilder: (context, index) {
                                  final imagePath = diary.imageList[index];
                                  return Container(
                                    margin: const EdgeInsets.only(right: 12),
                                    width: 100,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                          AppTheme.mediumRadius),
                                      color: scheme.lightColor.withValues(alpha: 0.3),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          AppTheme.mediumRadius),
                                      child: imagePath.startsWith('assets/')
                                          ? Image.asset(
                                              imagePath,
                                              fit: BoxFit.cover,
                                              cacheWidth: 200,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  Icon(Icons.image,
                                                      color:
                                                          scheme.primaryColor),
                                            )
                                          : PlatformImage(
                                              path: imagePath,
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                              cacheWidth: 200,
                                              cacheHeight: 200,
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                        // 底部信息
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            children: [
                              if (diary.images != null &&
                                  diary.images!.isNotEmpty)
                                _buildInfoChip(
                                  Icons.image_outlined,
                                  '${diary.imageList.length}张',
                                  scheme,
                                ),
                              if (diary.weather != null) ...[
                                if (diary.images != null &&
                                    diary.images!.isNotEmpty)
                                  const SizedBox(width: 8),
                                _buildInfoChip(
                                  Icons.wb_sunny_outlined,
                                  diary.weather!,
                                  scheme,
                                ),
                              ],
                              const Spacer(),
                              Text(
                                '${diary.wordCount} 字',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.textLightColor.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text, ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.lightColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: scheme.primaryColor,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: scheme.textMediumColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
