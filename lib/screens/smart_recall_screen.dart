import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../services/smart_recall_service.dart';
import '../widgets/interactive_button.dart';
import '../providers/theme_provider.dart';
import 'diary_detail_screen.dart';

/// 智能回忆页面
class SmartRecallScreen extends StatefulWidget {
  final Diary? currentDiary;
  
  const SmartRecallScreen({
    super.key,
    this.currentDiary,
  });

  @override
  State<SmartRecallScreen> createState() => _SmartRecallScreenState();
}

class _SmartRecallScreenState extends State<SmartRecallScreen> {
  List<RecallItem> _recalls = [];
  bool _isLoading = true;
  bool _showAnimation = false;

  @override
  void initState() {
    super.initState();
    _loadRecalls();
  }

  Future<void> _loadRecalls() async {
    setState(() => _isLoading = true);
    
    final recalls = await SmartRecallService.getSmartRecalls(
      limit: 5,
      currentDiary: widget.currentDiary,
    );
    
    if (mounted) {
      setState(() {
        _recalls = recalls;
        _isLoading = false;
        _showAnimation = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: CustomScrollView(
        slivers: [
          // 顶部标题栏
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            backgroundColor: scheme.backgroundColor,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primaryColor.withOpacity(0.2),
                      scheme.backgroundColor,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.primaryColor,
                              scheme.darkColor,
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primaryColor.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        SmartRecallService.getTodayRecallTitle(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: scheme.textDarkColor,
                        ),
                      ),
                      Text(
                        '发现 ${_recalls.length} 个值得回味的瞬间',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.textMediumColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            leading: InteractiveButton(
              onPressed: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.cardColor,
                  borderRadius: BorderRadius.circular(AppTheme.smallRadius),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: scheme.textDarkColor,
                ),
              ),
            ),
            actions: [
              InteractiveButton(
                onPressed: _loadRecalls,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.cardColor,
                    borderRadius: BorderRadius.circular(AppTheme.smallRadius),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Icon(
                    Icons.refresh,
                    size: 20,
                    color: scheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          
          // 内容区
          SliverPadding(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            sliver: _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _recalls.isEmpty
                    ? SliverFillRemaining(
                        child: _buildEmptyState(scheme),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final recall = _recalls[index];
                            return AnimatedOpacity(
                              opacity: _showAnimation ? 1.0 : 0.0,
                              duration: Duration(milliseconds: 300 + index * 100),
                              curve: AppTheme.gentleCurve,
                              child: AnimatedSlide(
                                offset: _showAnimation 
                                    ? Offset.zero 
                                    : const Offset(0, 0.2),
                                duration: Duration(milliseconds: 400 + index * 100),
                                curve: AppTheme.gentleCurve,
                                child: _buildRecallCard(scheme, recall),
                              ),
                            );
                          },
                          childCount: _recalls.length,
                        ),
                      ),
          ),
          
          // 底部提示
          if (_recalls.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Center(
                  child: Text(
                    '继续写日记，发现更多精彩回忆 ✨',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.textLightColor,
                    ),
                  ),
                ),
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
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: scheme.lightColor.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history,
              size: 60,
              color: scheme.textLightColor.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '还没有足够的日记',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: scheme.textDarkColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '多写几篇日记，我们会为你发现\n值得回味的精彩瞬间',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: scheme.textMediumColor,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          InteractiveButton(
            onPressed: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.darkColor, scheme.primaryColor],
                ),
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                boxShadow: AppTheme.floatingShadow,
              ),
              child: const Text(
                '去写日记',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecallCard(ThemeScheme scheme, RecallItem recall) {
    final color = Color(recall.color);
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      child: InteractiveButton(
        onPressed: () async {
          HapticFeedback.mediumImpact();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DiaryDetailScreen(diary: recall.diary),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.cardColor,
                scheme.cardColor.withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.largeRadius),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部类型标签
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd,
                  vertical: AppTheme.spacingSm,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withOpacity(0.15),
                      color.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.largeRadius),
                    topRight: Radius.circular(AppTheme.largeRadius),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      recall.icon,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      recall.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                      ),
                      child: Text(
                        recall.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: color.withOpacity(0.8),
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
                    if (recall.diary.moodEmoji != null) ...[
                      Row(
                        children: [
                          Text(
                            recall.diary.moodEmoji!,
                            style: const TextStyle(fontSize: 24),
                          ),
                          if (recall.diary.moodName != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              recall.diary.moodName!,
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.textMediumColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingSm),
                    ],
                    
                    if (recall.highlight != null) ...[
                      Text(
                        recall.highlight!,
                        style: TextStyle(
                          fontSize: 16,
                          color: scheme.textDarkColor,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    
                    if (recall.diary.images != null && 
                        recall.diary.images!.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.spacingMd),
                      Row(
                        children: [
                          Icon(
                            Icons.photo_outlined,
                            size: 16,
                            color: scheme.textLightColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${recall.diary.imageList.length}张照片',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.textLightColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页回忆卡片（用于时间轴页面）
class SmartRecallHomeCard extends StatefulWidget {
  const SmartRecallHomeCard({super.key});

  @override
  State<SmartRecallHomeCard> createState() => _SmartRecallHomeCardState();
}

class _SmartRecallHomeCardState extends State<SmartRecallHomeCard> {
  RecallItem? _todayRecall;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTodayRecall();
  }

  Future<void> _loadTodayRecall() async {
    final recalls = await SmartRecallService.getSmartRecalls(limit: 1);
    if (mounted) {
      setState(() {
        _todayRecall = recalls.isNotEmpty ? recalls.first : null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    if (_isLoading) {
      return const SizedBox.shrink();
    }
    
    if (_todayRecall == null) {
      return const SizedBox.shrink();
    }
    
    final color = Color(_todayRecall!.color);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InteractiveButton(
        onPressed: () async {
          HapticFeedback.mediumImpact();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DiaryDetailScreen(diary: _todayRecall!.diary),
            ),
          );
          _loadTodayRecall();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withOpacity(0.15),
                scheme.cardColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppTheme.largeRadius),
            border: Border.all(color: color.withOpacity(0.3)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _todayRecall!.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _todayRecall!.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _todayRecall!.highlight ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textMediumColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
