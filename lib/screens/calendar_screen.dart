import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/anniversary.dart';
import '../models/diary.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../services/database_service.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';

import '../services/image_cache_service.dart';
import '../services/lunar_calendar_service.dart';
import '../widgets/custom_sticker_overlay.dart';
import '../widgets/random_sticker_overlay.dart';
import '../widgets/goal_progress_card.dart';
import 'write_diary_screen.dart';
import 'diary_detail_screen.dart';
import 'diary_search_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _selectedDate;
  late DateTime _currentMonth;
  List<Anniversary> _anniversaries = [];

  @override
  void initState() {
    super.initState();
    // 每次打开日历都重置到今天
    _resetToToday();
    _loadAnniversaries();
    // 加载目标
    _loadGoal();
  }
  
  void _loadGoal() {
    Future.microtask(() {
      context.read<GoalProvider>().loadCurrentGoal();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在首次加载时重置，避免每次依赖变化都重置导致闪屏
    // _resetToToday(); // 已移到 initState 中调用
  }

  void _resetToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDate = now;
      _currentMonth = now;
    });
  }

  Future<void> _loadAnniversaries() async {
    final anniversaries = await DatabaseService.getAllAnniversaries();
    if (mounted) {
      setState(() {
        _anniversaries = anniversaries;
      });
    }
  }

  Future<void> _loadCalendarState() async {
    final settings = context.read<SettingsProvider>();
    setState(() {
      _currentMonth = DateTime(settings.calendarYear, settings.calendarMonth);
    });
  }

  Future<void> _saveCalendarState() async {
    final settings = context.read<SettingsProvider>();
    await settings.setCalendarState(_currentMonth.year, _currentMonth.month);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Consumer<DiaryProvider>(
      builder: (context, provider, child) {
        final datesWithDiaries = provider.datesWithDiaries;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Column(
                children: [
                  // 农历信息卡片
                  LunarInfoCard(date: _selectedDate),
                  // 目标进度卡片
                  GoalProgressCard(
                    onTapSettings: () => _showGoalSettings(context),
                  ),
                  // 顶部日期标题和导航 - 玻璃态设计（缩小版）
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.cardColor,
                          scheme.cardColor.withOpacity(0.9),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.xlRadius),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 左侧：日期信息 + 快捷操作
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 日期和今天按钮
                            Row(
                              children: [
                                Text(
                                  DateFormat('M月d日', 'zh_CN')
                                      .format(_selectedDate),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.textDarkColor,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                // 如果不是今天，显示"今天"快捷按钮
                                if (!DateUtils.isSameDay(
                                    _selectedDate, DateTime.now()))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedDate = DateTime.now();
                                          _currentMonth = DateTime.now();
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: scheme.primaryColor
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: scheme.primaryColor
                                                .withOpacity(0.3),
                                          ),
                                        ),
                                        child: Text(
                                          '今天',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: scheme.primaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // 星期和本月统计
                            Row(
                              children: [
                                Text(
                                  DateFormat('EEEE', 'zh_CN')
                                      .format(_selectedDate),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.textMediumColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 本月日记数量
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.lightColor.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Consumer<DiaryProvider>(
                                    builder: (context, provider, child) {
                                      final currentMonthStr =
                                          DateFormat('yyyy-MM')
                                              .format(_currentMonth);
                                      final monthDiaries = provider.diaries
                                          .where((d) => d.date
                                              .startsWith(currentMonthStr))
                                          .length;
                                      return Text(
                                        '本月 $monthDiaries 篇',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: scheme.textMediumColor,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // 右侧：快捷功能按钮
                        Row(
                          children: [
                            // 搜索按钮
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const DiarySearchScreen(),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: scheme.lightColor.withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.search_rounded,
                                  size: 20,
                                  color: scheme.textMediumColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 纪念日按钮
                            GestureDetector(
                              onTap: _showAnniversaryDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.pink.withOpacity(0.1),
                                      Colors.red.withOpacity(0.05),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.pink.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.favorite_rounded,
                                      size: 16,
                                      color: Colors.pink[400],
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '纪念日',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.pink[400],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 月份导航栏 - 简洁设计
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _previousMonth,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.cardColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: AppTheme.softShadow,
                              ),
                              child: Icon(
                                Icons.chevron_left_rounded,
                                color: scheme.textMediumColor,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          decoration: BoxDecoration(
                            color: scheme.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: Text(
                            DateFormat('yyyy年M月', 'zh_CN')
                                .format(_currentMonth),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: scheme.textDarkColor,
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _nextMonth,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.cardColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: AppTheme.softShadow,
                              ),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                color: scheme.textMediumColor,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 星期标题 - 现代设计
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['一', '二', '三', '四', '五', '六', '日']
                          .map((day) => SizedBox(
                                width: 40,
                                child: Text(
                                  day,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: day == '六' || day == '日'
                                        ? scheme.primaryColor
                                        : scheme.textMediumColor,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),

                  // 日历网格
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.count(
                        crossAxisCount: 7,
                        childAspectRatio: 0.9,
                        physics: const NeverScrollableScrollPhysics(),
                        children: _getDaysInMonth().map((date) {
                          final dateStr = DateFormat('yyyy-MM-dd').format(date);
                          final isSelected =
                              DateFormat('yyyy-MM-dd').format(_selectedDate) ==
                                  dateStr;
                          final isCurrentMonth =
                              date.month == _currentMonth.month;
                          final hasDiary = datesWithDiaries.contains(dateStr);

                          // 获取当天的日记，检查是否有图片
                          final diaries = provider.getDiariesByDate(dateStr);
                          final hasImages = diaries.isNotEmpty &&
                              diaries.any((d) => d.imageList.isNotEmpty);
                          final firstImagePath = hasImages
                              ? diaries
                                  .firstWhere((d) => d.imageList.isNotEmpty)
                                  .imageList
                                  .first
                              : null;

                          return _buildDayCell(
                            date: date,
                            isSelected: isSelected,
                            isCurrentMonth: isCurrentMonth,
                            hasDiary: hasDiary,
                            hasImages: hasImages,
                            firstImagePath: firstImagePath,
                            scheme: scheme,
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // 日期日记数量指示器
                  _buildDateIndicator(scheme, provider),

                  // 底部装饰区域 - 固定小高度
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        color: scheme.cardColor.withOpacity(0.5),
                        borderRadius:
                            BorderRadius.circular(AppTheme.largeRadius),
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppTheme.largeRadius),
                        child: Stack(
                          children: [
                            // 云朵
                            Positioned(
                              top: 20,
                              left: 30,
                              child: _buildCloud(50, scheme.cardColor),
                            ),
                            Positioned(
                              top: 30,
                              right: 40,
                              child: _buildCloud(60, scheme.cardColor),
                            ),
                            Positioned(
                              top: 60,
                              left: 70,
                              child: _buildCloud(40, scheme.cardColor),
                            ),
                            // 房子
                            Positioned(
                              bottom: 50,
                              left: 30,
                              child: _buildHouse(scheme),
                            ),
                            // 草地和花朵
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: _buildGrassland(scheme),
                            ),
                            // 自定义贴图
                            const CustomStickerOverlay(targetPage: 'calendar'),
                            // 随机贴图装饰
                            const RandomStickerOverlay(
                                targetPage: 'calendar', appearProbability: 0.6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showYearPicker() {
    final currentYear = DateTime.now().year;
    final years = List.generate(21, (index) => currentYear - 10 + index);
    final scheme = AppTheme.schemeOf(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 400,
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.largeRadius),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '选择年份',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('完成',
                        style: TextStyle(color: scheme.primaryColor)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                itemCount: years.length,
                itemBuilder: (context, index) {
                  final year = years[index];
                  final isSelected = year == _currentMonth.year;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentMonth = DateTime(year, _currentMonth.month);
                      });
                      _saveCalendarState();
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? scheme.primaryColor
                            : scheme.lightColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '$year',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : scheme.textDarkColor,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示月份选择器
  void _showMonthPicker() {
    final scheme = AppTheme.schemeOf(context);
    final months = List.generate(12, (index) => index + 1);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 400,
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.largeRadius),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_currentMonth.year}年 选择月份',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('完成',
                        style: TextStyle(color: scheme.primaryColor)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                itemCount: months.length,
                itemBuilder: (context, index) {
                  final month = months[index];
                  final isSelected = month == _currentMonth.month;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentMonth = DateTime(_currentMonth.year, month);
                      });
                      _saveCalendarState();
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? scheme.primaryColor
                            : scheme.lightColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '$month月',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : scheme.textDarkColor,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
    _saveCalendarState();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
    _saveCalendarState();
  }

  /// 构建日记预览卡片 - 优化后的现代设计
  Widget _buildDiaryPreview(ThemeScheme scheme) {
    return Consumer<DiaryProvider>(
      builder: (context, provider, child) {
        // 确保日期格式正确
        final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        final diaries = provider.getDiariesByDate(dateStr);

        if (diaries.isEmpty) {
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: GestureDetector(
                onTap: _writeDiary,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.cardColor.withOpacity(0.98),
                        scheme.cardColor.withOpacity(0.85),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primaryColor.withOpacity(0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                        spreadRadius: -2,
                      ),
                    ],
                    border: Border.all(
                      color: scheme.primaryColor.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.primaryColor,
                              scheme.primaryColor.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '记录今天',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: scheme.textDarkColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '点击写下美好时刻',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.textMediumColor.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // 如果日记数量大于2，使用可上滑的展开面板
        if (diaries.length > 2) {
          return _buildExpandableDiaryPreview(scheme, diaries);
        }

        // 2篇及以下使用优化后的普通预览
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.cardColor.withOpacity(0.98),
                    scheme.cardColor.withOpacity(0.88),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.cardShadow,
                border: Border.all(
                  color: scheme.lightColor.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 头部区域
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.lightColor.withOpacity(0.3),
                            scheme.lightColor.withOpacity(0.1),
                          ],
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: scheme.lightColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      scheme.primaryColor,
                                      scheme.primaryColor.withOpacity(0.8),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          scheme.primaryColor.withOpacity(0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.book_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${diaries.length} 篇日记',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _writeDiary,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: scheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: scheme.primaryColor.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_rounded,
                                      size: 16,
                                      color: scheme.primaryColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '再写一篇',
                                      style: TextStyle(
                                        color: scheme.primaryColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 日记列表
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: diaries.asMap().entries.map((entry) {
                          final index = entry.key;
                          final diary = entry.value;
                          return _buildDiaryListItem(
                            diary,
                            scheme,
                            showBorder: index < diaries.length - 1,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建可展开的上滑预览面板（日记数量>2时使用）- 优化后的现代设计
  Widget _buildExpandableDiaryPreview(ThemeScheme scheme, List<Diary> diaries) {
    // 计算高度：根据日记数量动态调整（更紧凑）
    // 头部约80px + 每篇日记约100px
    const headerHeight = 80.0;
    const itemHeight = 100.0;
    final totalHeight = headerHeight + (diaries.length * itemHeight);
    // 限制最大高度为屏幕的40%，避免遮挡日历
    final maxHeight = MediaQuery.of(context).size.height * 0.40;
    final containerHeight = totalHeight > maxHeight ? maxHeight : totalHeight;

    return Container(
      height: containerHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.cardColor.withOpacity(0.99),
            scheme.cardColor.withOpacity(0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, -6),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: scheme.primaryColor.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, -10),
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // 顶部把手和标题（始终可见）
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.lightColor.withOpacity(0.4),
                    scheme.lightColor.withOpacity(0.1),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: scheme.lightColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖拽把手
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.lightColor,
                          scheme.lightColor.withOpacity(0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.primaryColor,
                              scheme.primaryColor.withOpacity(0.85),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primaryColor.withOpacity(0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.collections_bookmark_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${diaries.length} 篇日记',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _writeDiary(),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: scheme.primaryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: scheme.primaryColor.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  size: 18,
                                  color: scheme.primaryColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '写一篇',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 上滑提示
                  if (diaries.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 16,
                            color: scheme.textLightColor.withOpacity(0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '上滑查看更多',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.textLightColor.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // 可滚动的日记列表
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: diaries.length,
                itemBuilder: (context, index) {
                  final diary = diaries[index];
                  return _buildDiaryListItem(
                    diary,
                    scheme,
                    showBorder: index < diaries.length - 1,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建日记列表项 - 简化设计
  Widget _buildDiaryListItem(Diary diary, ThemeScheme scheme,
      {bool showBorder = false}) {
    final hasImages = diary.imageList.isNotEmpty;

    // 获取该日期的纪念日/倒数日
    final dateAnniversaries = _getAnniversariesForDateString(diary.date);
    final hasAnniversaries = dateAnniversaries.isNotEmpty;

    // 预览文本：最多显示2行内容，为纪念日/倒数日留出空间
    String previewText = '';
    if (diary.content != null && diary.content!.isNotEmpty) {
      final lines = diary.content!.split('\n');
      if (lines.length >= 2) {
        previewText = lines.sublist(0, 2).join('\n');
      } else {
        // 按字符截断到约2行（每行约25个中文字符）
        const charsPerLine = 25;
        final maxChars = charsPerLine * 2;
        previewText = diary.content!.length > maxChars
            ? diary.content!.substring(0, maxChars)
            : diary.content!;
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _viewDiary(diary),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.lightColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: showBorder
                ? Border(
                    bottom: BorderSide(
                      color: scheme.lightColor.withOpacity(0.2),
                      width: 1,
                    ),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图片缩略图或心情表情
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: hasImages
                      ? scheme.primaryColor.withOpacity(0.15)
                      : scheme.lightColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasImages
                    ? OptimizedCachedImage(
                        path: diary.imageList.first,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        quality: CacheQuality.small,
                      )
                    : Center(
                        child: Text(
                          diary.moodEmoji ?? '📝',
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
              ),

              const SizedBox(width: 14),
              // 内容区域
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            diary.title ?? '无标题',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: scheme.textDarkColor,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: scheme.textLightColor.withOpacity(0.6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 内容预览（最多2行，为纪念日留出空间）
                    if (previewText.isNotEmpty)
                      Text(
                        previewText,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textMediumColor,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // 纪念日/倒数日标签
                    if (hasAnniversaries)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: dateAnniversaries.map((a) {
                            final isAnniversary =
                                a.type == AnniversaryType.anniversary;
                            final diaryDate = DateTime.parse(diary.date);
                            final targetDate = DateTime.parse(a.date);
                            final days =
                                diaryDate.difference(targetDate).inDays;
                            String label;
                            if (isAnniversary) {
                              label = days == 0
                                  ? '${a.displayName} ✨'
                                  : '${a.displayName} · 第$days天';
                            } else {
                              final daysLeft =
                                  targetDate.difference(diaryDate).inDays;
                              label = daysLeft == 0
                                  ? '${a.displayName} 🎯'
                                  : '${a.displayName} · 剩$daysLeft天';
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isAnniversary
                                    ? Colors.pink.withOpacity(0.1)
                                    : Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isAnniversary
                                      ? Colors.pink.withOpacity(0.3)
                                      : Colors.blue.withOpacity(0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isAnniversary
                                      ? Colors.pink.shade700
                                      : Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 根据日期字符串获取纪念日列表
  List<Anniversary> _getAnniversariesForDateString(String date) {
    return _anniversaries.where((a) => a.date == date).toList();
  }

  Future<void> _writeDiary() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriteDiaryScreen(selectedDate: _selectedDate),
      ),
    );
    if (result == true && mounted) {
      context.read<DiaryProvider>().loadDiaries();
    }
  }

  Future<void> _viewDiary(Diary diary) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryDetailScreen(diary: diary),
      ),
    );
    if (result == true && mounted) {
      context.read<DiaryProvider>().loadDiaries();
    }
  }

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    var firstWeekday = firstDay.weekday;
    var leadingDays = firstWeekday == 7 ? 0 : firstWeekday;

    final days = <DateTime>[];

    for (var i = leadingDays; i > 0; i--) {
      days.add(firstDay.subtract(Duration(days: i)));
    }

    for (var i = 1; i <= lastDay.day; i++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month, i));
    }

    var remainingDays = 42 - days.length;

    for (var i = 1; i <= remainingDays; i++) {
      days.add(lastDay.add(Duration(days: i)));
    }

    return days;
  }

  /// 构建日历单元格 - 优化后的现代设计
  Widget _buildDayCell({
    required DateTime date,
    required bool isSelected,
    required bool isCurrentMonth,
    required bool hasDiary,
    required bool hasImages,
    required String? firstImagePath,
    required ThemeScheme scheme,
  }) {
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) ==
        DateFormat('yyyy-MM-dd').format(date);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDate = date;
        });
        // 如果该日期有日记，显示日记预览
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final diaries = context.read<DiaryProvider>().getDiariesByDate(dateStr);
        if (diaries.isNotEmpty) {
          _showDiaryPreviewBottomSheet(date, diaries);
        }
      },
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryColor,
                    scheme.primaryColor.withOpacity(0.85),
                  ],
                )
              : (hasImages && isCurrentMonth && !isSelected)
                  ? null // 有图片时不设置背景渐变，用图片代替
                  : hasDiary && isCurrentMonth
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.lightColor.withOpacity(0.6),
                            scheme.lightColor.withOpacity(0.3),
                          ],
                        )
                      : null,
          color: isSelected ||
                  (hasDiary && isCurrentMonth) ||
                  (hasImages && isCurrentMonth && !isSelected)
              ? null
              : isCurrentMonth
                  ? scheme.cardColor.withOpacity(0.3)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: scheme.primaryColor.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: -2,
                  ),
                ]
              : hasDiary && isCurrentMonth
                  ? [
                      BoxShadow(
                        color: scheme.lightColor.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
          border: isToday && !isSelected
              ? Border.all(
                  color: scheme.primaryColor.withOpacity(0.5),
                  width: 2,
                )
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 图片背景（如果有）
            if (hasImages &&
                firstImagePath != null &&
                isCurrentMonth &&
                !isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CalendarImage(
                    path: firstImagePath,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            // 渐变遮罩（有图片时）
            if (hasImages && isCurrentMonth && !isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.1),
                        Colors.black.withOpacity(0.35),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            // 选中状态的装饰光环
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            // 日期数字
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: isSelected ? 18 : 16,
                      fontWeight:
                          (hasImages && isCurrentMonth && !isSelected) ||
                                  isSelected
                              ? FontWeight.w800
                              : isToday
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (hasImages && isCurrentMonth && !isSelected)
                              ? Colors.white
                              : !isCurrentMonth
                                  ? scheme.textLightColor.withOpacity(0.35)
                                  : isToday
                                      ? scheme.primaryColor
                                      : scheme.textDarkColor,
                      shadows: (hasImages && isCurrentMonth && !isSelected)
                          ? [
                              Shadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text('${date.day}'),
                  ),
                  const SizedBox(height: 2),
                  // 农历显示
                  if (isCurrentMonth)
                    LunarDayLabel(
                      date: date,
                      isSelected: isSelected,
                      isToday: isToday,
                      textColor: hasImages && !isSelected
                          ? Colors.white.withOpacity(0.9)
                          : null,
                    ),
                  const SizedBox(height: 2),
                  // 日记标记指示器
                  if (hasDiary && isCurrentMonth && !isSelected && !hasImages)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.primaryColor,
                            scheme.primaryColor.withOpacity(0.7),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primaryColor.withOpacity(0.4),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  // 图片日记标记
                  if (hasImages && isCurrentMonth && !isSelected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_camera_rounded,
                            size: 10,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloud(double size, Color cloudColor) {
    return Container(
      width: size,
      height: size * 0.6,
      decoration: BoxDecoration(
        color: cloudColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }

  Widget _buildHouse(ThemeScheme scheme) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 30,
          decoration: BoxDecoration(
            color: scheme.darkColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
        ),
        Container(
          width: 60,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 16,
                decoration: BoxDecoration(
                  color: scheme.lightColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 12,
                height: 16,
                decoration: BoxDecoration(
                  color: scheme.lightColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrassland(ThemeScheme scheme) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.lightColor.withOpacity(0.6),
            scheme.darkColor.withOpacity(0.8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppTheme.largeRadius),
          bottomRight: Radius.circular(AppTheme.largeRadius),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(8, (index) {
          final colors = [
            scheme.primaryColor,
            scheme.darkColor,
            scheme.textMediumColor,
            scheme.textLightColor,
          ];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Icon(
              Icons.local_florist,
              color: colors[index % 4].withOpacity(0.7),
              size: 20 + (index % 3) * 5,
            ),
          );
        }),
      ),
    );
  }

  // ==================== 日记预览相关方法 ====================

  /// 显示日期指示器（底部日记数量提示）
  Widget _buildDateIndicator(ThemeScheme scheme, DiaryProvider provider) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final diaries = provider.getDiariesByDate(dateStr);
    final hasDiaries = diaries.isNotEmpty;

    if (!hasDiaries) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _showDiaryPreviewBottomSheet(_selectedDate, diaries),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryColor,
              scheme.primaryColor.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: scheme.primaryColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.article_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '${DateFormat('M月d日').format(_selectedDate)} 有 ${diaries.length} 篇日记',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_up,
              color: Colors.white70,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  /// 显示日记预览底部弹窗
  void _showDiaryPreviewBottomSheet(DateTime date, List<Diary> diaries) {
    final scheme = AppTheme.schemeOf(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryColor,
                    scheme.primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('M月d日', 'zh_CN').format(date),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${diaries.length} 篇日记',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // 写日记按钮
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _writeDiary();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '写一篇',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 关闭按钮
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 日记列表
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.cardColor,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  shrinkWrap: true,
                  itemCount: diaries.length,
                  itemBuilder: (context, index) {
                    final diary = diaries[index];
                    return _buildDiaryListItem(
                      diary,
                      scheme,
                      showBorder: index < diaries.length - 1,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 目标相关方法 ====================

  /// 显示目标设置弹窗
  void _showGoalSettings(BuildContext context) {
    final goalProvider = context.read<GoalProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => GoalSettingSheet(
        currentGoal: goalProvider.currentGoal,
      ),
    );
  }

  // ==================== 纪念日相关方法 ====================

  /// 显示纪念日管理对话框
  void _showAnniversaryDialog() {
    final scheme = AppTheme.schemeOf(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: scheme.cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.largeRadius),
              ),
            ),
            child: Column(
              children: [
                // 顶部标题栏
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.favorite, color: scheme.primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            '纪念日管理',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: scheme.textDarkColor,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // 添加按钮
                          TextButton.icon(
                            onPressed: () =>
                                _showAddAnniversaryDialog(setModalState),
                            icon: Icon(Icons.add, color: scheme.primaryColor),
                            label: Text(
                              '添加',
                              style: TextStyle(color: scheme.primaryColor),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close,
                                color: scheme.textMediumColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: scheme.lightColor),
                // 纪念日列表
                Expanded(
                  child: _anniversaries.isEmpty
                      ? _buildEmptyAnniversaryView(scheme)
                      : _buildAnniversaryList(setModalState, scheme),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建空状态视图
  Widget _buildEmptyAnniversaryView(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 64,
            color: scheme.textLightColor.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有纪念日',
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角添加按钮创建纪念日或倒数日',
            style: TextStyle(
              fontSize: 13,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建纪念日列表
  Widget _buildAnniversaryList(StateSetter setModalState, ThemeScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _anniversaries.length,
      itemBuilder: (context, index) {
        final anniversary = _anniversaries[index];
        return _buildAnniversaryItem(anniversary, setModalState, scheme);
      },
    );
  }

  /// 构建单个纪念日项
  Widget _buildAnniversaryItem(
    Anniversary anniversary,
    StateSetter setModalState,
    ThemeScheme scheme,
  ) {
    final isAnniversary = anniversary.type == AnniversaryType.anniversary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.lightColor.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          // 类型图标
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isAnniversary
                  ? Colors.pink.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                isAnniversary ? Icons.favorite : Icons.hourglass_empty,
                color: isAnniversary ? Colors.pink : Colors.blue,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anniversary.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isAnniversary
                            ? Colors.pink.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        anniversary.typeDisplayName,
                        style: TextStyle(
                          fontSize: 11,
                          color: isAnniversary ? Colors.pink : Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      anniversary.date,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textMediumColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 操作按钮
          Row(
            children: [
              IconButton(
                onPressed: () =>
                    _showEditAnniversaryDialog(anniversary, setModalState),
                icon: Icon(Icons.edit_outlined,
                    size: 20, color: scheme.textMediumColor),
              ),
              IconButton(
                onPressed: () => _deleteAnniversary(anniversary, setModalState),
                icon: Icon(Icons.delete_outline,
                    size: 20, color: Colors.red.withOpacity(0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 显示添加纪念日对话框
  void _showAddAnniversaryDialog(StateSetter setModalState) {
    _showAnniversaryFormDialog(
      title: '添加纪念日',
      onSave: (anniversary) async {
        await DatabaseService.insertAnniversary(anniversary);
        await _loadAnniversaries();
        setModalState(() {});
      },
    );
  }

  /// 显示编辑纪念日对话框
  void _showEditAnniversaryDialog(
      Anniversary anniversary, StateSetter setModalState) {
    _showAnniversaryFormDialog(
      title: '编辑纪念日',
      initialAnniversary: anniversary,
      onSave: (updated) async {
        await DatabaseService.updateAnniversary(updated);
        await _loadAnniversaries();
        setModalState(() {});
      },
    );
  }

  /// 显示纪念日表单对话框
  void _showAnniversaryFormDialog({
    required String title,
    Anniversary? initialAnniversary,
    required Function(Anniversary) onSave,
  }) {
    final scheme = AppTheme.schemeOf(context);
    final nameController =
        TextEditingController(text: initialAnniversary?.name ?? '');
    final subjectNameController =
        TextEditingController(text: initialAnniversary?.subjectName ?? '');
    final quoteController =
        TextEditingController(text: initialAnniversary?.quote ?? '');

    AnniversaryType selectedType =
        initialAnniversary?.type ?? AnniversaryType.anniversary;
    DateTime selectedDate = initialAnniversary != null
        ? DateTime.parse(initialAnniversary.date)
        : _selectedDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: scheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: scheme.textDarkColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 类型选择
                  Text(
                    '类型',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTypeOption(
                          title: '纪念日',
                          icon: Icons.favorite,
                          color: Colors.pink,
                          isSelected:
                              selectedType == AnniversaryType.anniversary,
                          onTap: () => setDialogState(() {
                            selectedType = AnniversaryType.anniversary;
                          }),
                          scheme: scheme,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTypeOption(
                          title: '倒数日',
                          icon: Icons.hourglass_empty,
                          color: Colors.blue,
                          isSelected: selectedType == AnniversaryType.countdown,
                          onTap: () => setDialogState(() {
                            selectedType = AnniversaryType.countdown;
                          }),
                          scheme: scheme,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 日期选择
                  Text(
                    '日期',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: scheme.primaryColor,
                                onPrimary: Colors.white,
                                surface: scheme.cardColor,
                                onSurface: scheme.textDarkColor,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.lightColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 18, color: scheme.textMediumColor),
                          const SizedBox(width: 8),
                          Text(
                            '${selectedDate.year}年${selectedDate.month}月${selectedDate.day}日',
                            style: TextStyle(
                              color: scheme.textDarkColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 事件名称输入
                  Text(
                    '事件名称',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: '例如：恋爱纪念日、生日、旅行...',
                      hintStyle: TextStyle(color: scheme.textLightColor),
                      filled: true,
                      fillColor: scheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 对象名称输入（可选）
                  Text(
                    '对象名称（可选）',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '填写后会显示为"对象：距离事件过去了X天"',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.textLightColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: subjectNameController,
                    decoration: InputDecoration(
                      hintText: '例如：小明、妈妈、宝宝...',
                      hintStyle: TextStyle(color: scheme.textLightColor),
                      filled: true,
                      fillColor: scheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 自定义祝福语（可选）
                  Text(
                    '自定义祝福语（可选）',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: quoteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: '特殊日子时显示的祝福语，留空使用默认',
                      hintStyle: TextStyle(color: scheme.textLightColor),
                      filled: true,
                      fillColor: scheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    Text('取消', style: TextStyle(color: scheme.textMediumColor)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入名称')),
                    );
                    return;
                  }

                  final anniversary = Anniversary(
                    id: initialAnniversary?.id,
                    name: nameController.text.trim(),
                    subjectName: subjectNameController.text.trim().isEmpty
                        ? null
                        : subjectNameController.text.trim(),
                    date:
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                    type: selectedType,
                    quote: quoteController.text.trim().isEmpty
                        ? null
                        : quoteController.text.trim(),
                  );

                  Navigator.pop(context);
                  onSave(anniversary);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建类型选项
  Widget _buildTypeOption({
    required String title,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeScheme scheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : scheme.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : scheme.lightColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : scheme.textMediumColor),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? color : scheme.textMediumColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 删除纪念日
  Future<void> _deleteAnniversary(
      Anniversary anniversary, StateSetter setModalState) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除"${anniversary.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && anniversary.id != null) {
      await DatabaseService.deleteAnniversary(anniversary.id!);
      await _loadAnniversaries();
      setModalState(() {});
    }
  }
}
