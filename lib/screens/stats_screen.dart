import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../services/database_service.dart';
import '../services/milestone_service.dart';
import 'diary_detail_screen.dart';
import 'diary_search_screen.dart';
import 'write_diary_screen.dart';
import 'stats_detail_screen.dart';
import 'tags_classification_screen.dart';
import 'emotion_stats_screen_v2.dart';
import 'smart_recall_screen_v2.dart';
import '../widgets/widgets.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with TickerProviderStateMixin {
  int _totalDiaries = 0;
  int _totalChars = 0;
  DateTime? _startDate;
  int _uniqueDays = 0;
  int _currentStreak = 0;
  int _maxStreak = 0;
  Map<String, int> _moodDistribution = {};
  final Map<String, bool> _weekCheckIn = {};
  List<String> _photoPaths = [];
  Map<String, int> _weatherDistribution = {};
  Map<String, int> _tagDistribution = {};
  int? _avgHour;
  bool _isLoading = true;
  MilestoneInfo? _nextMilestone;

  // 动画控制器
  late AnimationController _pageController;
  late Animation<double> _pageFadeAnimation;
  late Animation<Offset> _pageSlideAnimation;
  
  // 统计数字动画
  late AnimationController _numberController;
  late Animation<double> _numberAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadStats();
  }

  void _initAnimations() {
    // 页面进入动画
    _pageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _pageFadeAnimation = CurvedAnimation(
      parent: _pageController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    
    _pageSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _pageController,
      curve: AppTheme.easeOutExpo,
    ));

    // 数字动画
    _numberController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _numberAnimation = CurvedAnimation(
      parent: _numberController,
      curve: const Interval(0.2, 1.0, curve: AppTheme.spring),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);

    final diaries = await DatabaseService.getAllDiaries();

    if (diaries.isEmpty) {
      setState(() => _isLoading = false);
      _pageController.forward();
      return;
    }

    // 计算统计数据
    final dates =
        diaries.map((d) => DateFormat('yyyy-MM-dd').parse(d.date)).toList();
    dates.sort();

    _startDate = dates.first;
    _totalDiaries = diaries.length;
    
    // 计算实际记载日记的唯一天数
    _uniqueDays = dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).toSet().length;

    // 计算总字符数
    _totalChars = diaries.fold(0, (sum, d) => sum + d.wordCount);

    // 计算连续记录天数
    _calculateStreaks(dates);

    // 生成本周打卡数据
    _generateWeekCheckIn(dates);

    // 获取心情分布
    _moodDistribution = await DatabaseService.getMoodDistribution();
    
    // 收集照片路径（最多10张）
    _photoPaths = diaries
        .where((d) => d.images != null && d.images!.isNotEmpty)
        .expand((d) => d.imageList)
        .take(10)
        .toList();
    
    // 统计天气分布
    _weatherDistribution = {};
    for (final diary in diaries) {
      if (diary.weather != null && diary.weather!.isNotEmpty) {
        _weatherDistribution[diary.weather!] = 
            (_weatherDistribution[diary.weather!] ?? 0) + 1;
      }
    }
    
    // 统计标签分布
    _tagDistribution = {};
    for (final diary in diaries) {
      final tags = await DatabaseService.getTagsByDiaryId(diary.id!);
      for (final tag in tags) {
        _tagDistribution[tag.name] = (_tagDistribution[tag.name] ?? 0) + 1;
      }
    }
    
    // 计算平均写作时间（简化版，基于创建时间）
    if (diaries.isNotEmpty && diaries.first.createdAt != null) {
      final hours = diaries
          .where((d) => d.createdAt != null)
          .map((d) => DateTime.parse(d.createdAt!).hour)
          .toList();
      if (hours.isNotEmpty) {
        final avgHour = hours.reduce((a, b) => a + b) ~/ hours.length;
        _avgHour = avgHour;
      }
    }
    
    // 获取下一个里程碑
    _nextMilestone = MilestoneService.getNextMilestone(_uniqueDays);

    setState(() => _isLoading = false);
    
    // 启动动画
    _pageController.forward();
    _numberController.forward();
  }

  void _calculateStreaks(List<DateTime> dates) {
    final uniqueDates = dates.toSet().toList();
    uniqueDates.sort();

    if (uniqueDates.isEmpty) return;

    // 计算当前连续天数
    _currentStreak = 0;
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    var checkDate = today;
    while (uniqueDates.any((d) =>
        d.year == checkDate.year &&
        d.month == checkDate.month &&
        d.day == checkDate.day)) {
      _currentStreak++;
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    // 如果今天没写，检查昨天
    if (_currentStreak == 0) {
      checkDate = yesterday;
      while (uniqueDates.any((d) =>
          d.year == checkDate.year &&
          d.month == checkDate.month &&
          d.day == checkDate.day)) {
        _currentStreak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      }
    }

    // 计算最长连续天数
    _maxStreak = 0;
    var currentStreak = 1;
    for (var i = 1; i < uniqueDates.length; i++) {
      final diff = uniqueDates[i].difference(uniqueDates[i - 1]).inDays;
      if (diff == 1) {
        currentStreak++;
        _maxStreak = _maxStreak < currentStreak ? currentStreak : _maxStreak;
      } else {
        currentStreak = 1;
      }
    }
    _maxStreak = _maxStreak < currentStreak ? currentStreak : _maxStreak;
  }

  void _generateWeekCheckIn(List<DateTime> dates) {
    final uniqueDates =
        dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).toSet();
    final today = DateTime.now();

    for (var i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      _weekCheckIn[dateStr] = uniqueDates.contains(dateStr);
    }
  }

  Future<void> _refreshStats() async {
    _pageController.reset();
    _numberController.reset();
    await _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(scheme.primaryColor),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        // 底部不处理，让 MainScreen 的 SafeArea 统一处理
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshStats,
          color: scheme.primaryColor,
          backgroundColor: scheme.cardColor,
          child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SlideTransition(
            position: _pageSlideAnimation,
            child: FadeTransition(
              opacity: _pageFadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题和搜索栏
                  _buildHeader(),

                  const SizedBox(height: 24),

                  // 统计卡片 - 带渐变背景
                  _buildStatsCard(),

                  const SizedBox(height: 20),

                  // 连续记录卡片
                  _buildStreakCard(),

                  const SizedBox(height: 20),

                  // 去年今日
                  _buildLastYearTodayCard(),

                  const SizedBox(height: 20),

                  // 按标签分类入口
                  _buildTagClassificationCard(),

                  const SizedBox(height: 20),

                  // 智能回忆入口
                  _buildSmartRecallCard(),

                  const SizedBox(height: 20),

                  // 情绪趋势入口
                  _buildEmotionTrendCard(),

                  const SizedBox(height: 20),

                  // 心情分布
                  if (_moodDistribution.isNotEmpty) _buildMoodCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildHeader() {
    final scheme = AppTheme.schemeOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回顾',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: scheme.textDarkColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '记录你的每一步成长',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.textMediumColor,
                  ),
                ),
              ],
            ),
          ),
          // 搜索按钮
          Container(
            decoration: BoxDecoration(
              color: scheme.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppTheme.softShadow,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DiarySearchScreen(),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.search_rounded, 
                    color: scheme.primaryColor,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    final scheme = AppTheme.schemeOf(context);

    return TiltCard(
      maxTilt: 0.03,
      onTap: _showStatsDetail,
      child: AnimatedBuilder(
        animation: _numberAnimation,
        builder: (context, child) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              // 第一行统计
              Row(
                children: [
                  Expanded(
                    child: _buildStatItemWithIcon(
                      _animateNumber(_totalDiaries),
                      '日记',
                      Icons.auto_stories_rounded,
                      scheme.primaryColor,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: scheme.dividerColor,
                  ),
                  Expanded(
                    child: _buildStatItemWithIcon(
                      _animateNumber(_uniqueDays),
                      '记载天数',
                      Icons.calendar_today_rounded,
                      scheme.darkColor,
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Divider(
                  color: scheme.dividerColor,
                  height: 1,
                ),
              ),

              // 第二行统计
              Row(
                children: [
                  Expanded(
                    child: _buildStatItemWithIcon(
                      _totalChars > 1000
                          ? '${(_totalChars * _numberAnimation.value / 1000).toStringAsFixed(1)}K'
                          : _animateNumber(_totalChars),
                      '字符',
                      Icons.edit_note_rounded,
                      AppTheme.success,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: scheme.dividerColor,
                  ),
                  Expanded(
                    child: _buildStatItemWithIcon(
                      _startDate != null
                          ? DateFormat('yyyy/M/d').format(_startDate!)
                          : '-',
                      '开始日期',
                        Icons.play_circle_outline_rounded,
                        AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }

  String _animateNumber(int value) {
    return (value * _numberAnimation.value).toInt().toString();
  }

  Widget _buildStatItemWithIcon(
    String value, 
    String label, 
    IconData icon,
    Color iconColor,
  ) {
    final scheme = AppTheme.schemeOf(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 22,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: scheme.textDarkColor,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: scheme.textMediumColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStreakCard() {
    final scheme = AppTheme.schemeOf(context);
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.selectedGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      color: AppTheme.selectedGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '连续记录',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // 下一个里程碑提示
                  if (_nextMilestone != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _nextMilestone!.remainingDays <= 5
                              ? [
                                  AppTheme.selectedGreen.withValues(alpha: 0.2),
                                  AppTheme.selectedGreen.withValues(alpha: 0.1),
                                ]
                              : [
                                  scheme.lightColor.withValues(alpha: 0.3),
                                  scheme.lightColor.withValues(alpha: 0.15),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '还差${_nextMilestone!.remainingDays}天${_nextMilestone!.badge}',
                        style: TextStyle(
                          fontSize: 11,
                          color: _nextMilestone!.remainingDays <= 5
                              ? AppTheme.selectedGreen
                              : scheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: scheme.primaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '$_currentStreak天',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: scheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // 本周打卡
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.lightColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(7, (index) {
                final date = today.subtract(Duration(days: 6 - index));
                final dateStr = DateFormat('yyyy-MM-dd').format(date);
                final day = DateFormat('d').format(date);
                final weekday = ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1];
                final hasCheckIn = _weekCheckIn[dateStr] ?? false;
                final isToday = index == 6;

                return Column(
                  children: [
                    // 星期标签
                    Text(
                      weekday,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.textLightColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 日期圆圈 - 带弹性入场
                    TweenAnimationBuilder<double>(
                      key: ValueKey('streak_$dateStr'),
                      tween: Tween(begin: 0.6, end: 1.0),
                      duration: Duration(milliseconds: 400 + index * 60),
                      curve: AppTheme.spring,
                      builder: (context, scale, child) {
                        return Transform.scale(
                          scale: scale,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: AppTheme.spring,
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: hasCheckIn
                                  ? LinearGradient(
                                      colors: [
                                        AppTheme.selectedGreen,
                                        AppTheme.selectedGreen.withValues(alpha: 0.8),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : isToday
                                      ? LinearGradient(
                                          colors: [
                                            scheme.lightColor.withValues(alpha: 0.5),
                                            scheme.lightColor.withValues(alpha: 0.3),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                              color: hasCheckIn || isToday
                                  ? null
                                  : scheme.lightColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: hasCheckIn
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.selectedGreen.withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: Center(
                        child: hasCheckIn
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 22,
                              )
                            : Text(
                                day,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isToday
                                      ? scheme.primaryColor
                                      : scheme.textLightColor,
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 最长连续记录
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_events_rounded,
                size: 16,
                color: AppTheme.warning,
              ),
              const SizedBox(width: 6),
              Text(
                '最长连续记录：',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.textMediumColor,
                ),
              ),
              Text(
                '$_maxStreak天',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: scheme.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 按标签分类入口卡片
  Widget _buildTagClassificationCard() {
    final scheme = AppTheme.schemeOf(context);
    return InteractiveButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TagsClassificationScreen(),
        ),
      ),
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryColor.withValues(alpha: 0.2),
                    scheme.primaryColor.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.label_outline,
                color: scheme.primaryColor,
                size: 26,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '按标签分类',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '查看各标签下的日记分布',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.textMediumColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: scheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartRecallCard() {
    final scheme = AppTheme.schemeOf(context);
    return InteractiveButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SmartRecallScreen(),
        ),
      ),
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.warmYellow.withValues(alpha: 0.15),
              scheme.cardColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.cardShadow,
          border: Border.all(
            color: AppTheme.warmYellow.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.warmYellow,
                    AppTheme.warmYellow.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '智能回忆',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '发现值得回味的精彩瞬间',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.textMediumColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warmYellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppTheme.warmYellow.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionTrendCard() {
    final scheme = AppTheme.schemeOf(context);
    return InteractiveButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const EmotionStatsScreen(),
        ),
      ),
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.warmPink.withValues(alpha: 0.1),
              scheme.cardColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.cardShadow,
          border: Border.all(
            color: AppTheme.warmPink.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.warmPink,
                    AppTheme.warmPink.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.psychology_outlined,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '情绪分析',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '了解自己的情绪变化趋势',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.textMediumColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warmPink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppTheme.warmPink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodCard() {
    final scheme = AppTheme.schemeOf(context);
    final total = _moodDistribution.values.fold(0, (sum, count) => sum + count);
    final entries = _moodDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.sentiment_satisfied_rounded,
                  color: AppTheme.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '心情分布',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 心情分布列表 - 带 staggered 入场和交互反馈
          ...entries.asMap().entries.map((mapEntry) {
            final index = mapEntry.key;
            final entry = mapEntry.value;
            final percentage =
                total > 0 ? (entry.value / total * 100).toInt() : 0;
            final progress = total > 0 ? entry.value / total : 0.0;
            final moodColor = _getMoodColor(entry.key);

            return SlideInAnimation(
              index: index,
              delay: const Duration(milliseconds: 50),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: InteractiveButton(
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  scaleFactor: 0.98,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.dividerColor),
                    ),
                    child: Row(
                      children: [
                        // 心情图标
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                moodColor.withValues(alpha: 0.2),
                                moodColor.withValues(alpha: 0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              _getMoodEmoji(entry.key),
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.textDarkColor,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '${entry.value}篇',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: scheme.textLightColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$percentage%',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: moodColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // 自定义圆角进度条
                              AnimatedBuilder(
                                animation: _numberAnimation,
                                builder: (context, child) {
                                  return Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: scheme.lightColor
                                          .withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor:
                                          progress * _numberAnimation.value,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              moodColor,
                                              moodColor.withValues(alpha: 0.8),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          boxShadow: [
                                            BoxShadow(
                                              color: moodColor.withValues(
                                                  alpha: 0.35),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // 获取心情颜色
  Color _getMoodColor(String mood) {
    final scheme = AppTheme.schemeOf(context);
    
    final moodColors = {
      '开心': const Color(0xFFFFB74D),
      '平静': const Color(0xFF81C784),
      '难过': const Color(0xFF64B5F6),
      '生气': const Color(0xFFE57373),
      '惊讶': const Color(0xFFFFB74D),
      '害怕': const Color(0xFF9575CD),
      '疲惫': const Color(0xFF90A4AE),
      '兴奋': const Color(0xFFFF8A65),
      '焦虑': const Color(0xFFFFB74D),
      '满足': const Color(0xFFAED581),
    };
    
    return moodColors[mood] ?? scheme.primaryColor;
  }

  // 获取心情表情
  String _getMoodEmoji(String mood) {
    final moodEmojis = {
      '开心': '😊',
      '平静': '😌',
      '难过': '😢',
      '生气': '😠',
      '惊讶': '😲',
      '害怕': '😨',
      '疲惫': '😴',
      '兴奋': '🤩',
      '焦虑': '😰',
      '满足': '😌',
    };
    
    return moodEmojis[mood] ?? '📝';
  }

  // 去年今日卡片
  Widget _buildLastYearTodayCard() {
    return FutureBuilder(
      future: _getLastYearTodayDiary(),
      builder: (context, snapshot) {
        final hasDiary = snapshot.hasData && snapshot.data != null;
        final lastYearDate = DateTime.now().subtract(const Duration(days: 365));
        final scheme = AppTheme.schemeOf(context);
        
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          color: AppTheme.warning,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '去年今日',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: scheme.textDarkColor,
                        ),
                      ),
                    ],
                  ),
                  if (hasDiary)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.lightColor.withValues(alpha: 0.4),
                            scheme.lightColor.withValues(alpha: 0.2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        DateFormat('M月d日').format(lastYearDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // 内容区域
              if (hasDiary && snapshot.data != null) ...[
                // 有日记时显示日记标题预览
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.lightColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        snapshot.data!.title ?? '无标题日记',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.textDarkColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (snapshot.data!.content != null && snapshot.data!.content!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            snapshot.data!.content!,
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.textMediumColor.withValues(alpha: 0.8),
                              height: 1.5,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ] else ...[
                // 无日记时显示提示
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        size: 48,
                        color: scheme.lightColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '去年今日还没有写日记哦',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.textMediumColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 20),
              
              // 查看按钮
              GestureDetector(
                onTap: () => _viewLastYearToday(hasDiary ? snapshot.data : null),
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.darkColor,
                        scheme.primaryColor,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          hasDiary ? Icons.visibility_rounded : Icons.edit_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hasDiary ? '查看去年今日' : '去写日记',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 获取去年今日的日记
  Future<dynamic> _getLastYearTodayDiary() async {
    final now = DateTime.now();
    final lastYear = DateTime(now.year - 1, now.month, now.day);
    final dateStr = DateFormat('yyyy-MM-dd').format(lastYear);
    
    final diaries = await DatabaseService.getDiariesByDate(dateStr);
    return diaries.isNotEmpty ? diaries.first : null;
  }

  // 显示统计详情页面
  void _showStatsDetail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatsDetailScreen(
          totalDiaries: _totalDiaries,
          uniqueDays: _uniqueDays,
          totalChars: _totalChars,
          startDate: _startDate,
          moodDistribution: _moodDistribution,
          photoPaths: _photoPaths,
          weatherDistribution: _weatherDistribution,
          tagDistribution: _tagDistribution,
          avgHour: _avgHour,
        ),
      ),
    );
  }

  // 查看去年今日
  void _viewLastYearToday(dynamic diary) async {
    if (diary != null) {
      // 有日记，查看详情
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DiaryDetailScreen(diary: diary),
        ),
      );
      if (result == true) {
        _loadStats();
      }
    } else {
      // 无日记，去写日记（日期设为去年今日）
      final lastYear = DateTime.now().subtract(const Duration(days: 365));
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WriteDiaryScreen(selectedDate: lastYear),
        ),
      );
      if (result == true) {
        _loadStats();
      }
    }
  }
}
