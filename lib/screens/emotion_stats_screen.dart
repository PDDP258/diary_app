import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../providers/diary_provider.dart';
import '../services/sentiment_analysis_service.dart';
import '../widgets/interactive_button.dart';
import '../providers/theme_provider.dart';
import 'package:provider/provider.dart';

/// 情绪统计页面
class EmotionStatsScreen extends StatefulWidget {
  const EmotionStatsScreen({super.key});

  @override
  State<EmotionStatsScreen> createState() => _EmotionStatsScreenState();
}

class _EmotionStatsScreenState extends State<EmotionStatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Diary> _diaries = [];
  bool _isLoading = true;
  
  // 统计数据
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _weeklyData = [];
  List<Map<String, dynamic>> _monthlyData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final provider = context.read<DiaryProvider>();
    final diaries = provider.diaries;
    
    // 分析情绪
    final stats = await SentimentAnalysisService.analyzeDiaries(diaries);
    
    // 生成周数据
    final weeklyData = _generateWeeklyData(diaries);
    
    // 生成月数据
    final monthlyData = _generateMonthlyData(diaries);
    
    if (mounted) {
      setState(() {
        _diaries = diaries;
        _stats = stats;
        _weeklyData = weeklyData;
        _monthlyData = monthlyData;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _generateWeeklyData(List<Diary> diaries) {
    final now = DateTime.now();
    final data = <Map<String, dynamic>>[];
    
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayDiaries = diaries.where((d) {
        final diaryDate = DateTime.parse(d.date);
        return diaryDate.year == date.year && 
               diaryDate.month == date.month && 
               diaryDate.day == date.day;
      }).toList();
      
      if (dayDiaries.isNotEmpty) {
        final result = SentimentAnalysisService.analyze(
          dayDiaries.map((d) => '${d.title ?? ''} ${d.content ?? ''}').join(' '),
        );
        data.add({
          'date': date,
          'weekday': ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday - 1],
          'positive': result.positive,
          'negative': result.negative,
          'emotion': result.dominantEmotion,
          'emoji': result.emoji,
          'color': result.color,
          'count': dayDiaries.length,
        });
      } else {
        data.add({
          'date': date,
          'weekday': ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday - 1],
          'positive': 0,
          'negative': 0,
          'emotion': '无记录',
          'emoji': '-',
          'color': 0xFFE0E0E0,
          'count': 0,
        });
      }
    }
    
    return data;
  }

  List<Map<String, dynamic>> _generateMonthlyData(List<Diary> diaries) {
    final now = DateTime.now();
    final data = <Map<String, dynamic>>[];
    
    for (int i = 29; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayDiaries = diaries.where((d) {
        final diaryDate = DateTime.parse(d.date);
        return diaryDate.year == date.year && 
               diaryDate.month == date.month && 
               diaryDate.day == date.day;
      }).toList();
      
      if (dayDiaries.isNotEmpty) {
        final result = SentimentAnalysisService.analyze(
          dayDiaries.map((d) => '${d.title ?? ''} ${d.content ?? ''}').join(' '),
        );
        data.add({
          'date': date,
          'day': date.day,
          'positive': result.positive,
          'negative': result.negative,
          'emotion': result.dominantEmotion,
          'emoji': result.emoji,
          'color': result.color,
        });
      } else {
        data.add({
          'date': date,
          'day': date.day,
          'positive': 0.33,
          'negative': 0.33,
          'emotion': '无',
          'emoji': '',
          'color': 0xFFE0E0E0,
        });
      }
    }
    
    return data;
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
          '情绪分析',
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
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '本周'),
            Tab(text: '本月'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(scheme),
                _buildWeeklyTab(scheme),
                _buildMonthlyTab(scheme),
              ],
            ),
    );
  }

  Widget _buildOverviewTab(ThemeScheme scheme) {
    final emotionDistribution = _stats['emotionDistribution'] as Map<String, int>? ?? {};
    final total = emotionDistribution.values.fold(0, (a, b) => a + b);
    
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primaryMint,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 情绪概览卡片
            _buildEmotionOverviewCard(scheme),
            
            const SizedBox(height: AppTheme.spacingLg),
            
            // 情绪分布饼图
            if (total > 0) ...[
              Text(
                '情绪分布',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              _buildEmotionDistributionChart(scheme, emotionDistribution, total),
            ],
            
            const SizedBox(height: AppTheme.spacingLg),
            
            // 情绪关键词
            if (_diaries.isNotEmpty) ...[
              Text(
                '常见情绪关键词',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              _buildKeywordsCloud(scheme),
            ],
            
            const SizedBox(height: AppTheme.spacingLg),
            
            // 情绪建议
            _buildAdviceCard(scheme),
            
            const SizedBox(height: AppTheme.spacingXxl),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionOverviewCard(ThemeScheme scheme) {
    final dominantEmotion = _stats['dominantEmotion'] as String? ?? '平静';
    final avgPositive = (_stats['averagePositive'] as double? ?? 0.33) * 100;
    final avgNegative = (_stats['averageNegative'] as double? ?? 0.33) * 100;
    
    String emoji;
    int color;
    String description;
    
    switch (dominantEmotion) {
      case '开心':
        emoji = '😊';
        color = 0xFF4CAF50;
        description = '整体情绪积极';
        break;
      case '难过':
        emoji = '😢';
        color = 0xFF9E9E9E;
        description = '需要更多关爱';
        break;
      case '生气':
        emoji = '😠';
        color = 0xFFF44336;
        description = '情绪较为激动';
        break;
      case '惊喜':
        emoji = '😮';
        color = 0xFFFF9800;
        description = '充满惊喜';
        break;
      case '疲惫':
        emoji = '😴';
        color = 0xFF795548;
        description = '需要注意休息';
        break;
      default:
        emoji = '😌';
        color = 0xFF2196F3;
        description = '情绪平稳';
    }
    
    return Container(
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(color).withValues(alpha: 0.2),
            scheme.cardColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          // 主导情绪
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(color),
                  Color(color).withValues(alpha: 0.7),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(color).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 48),
              ),
            ),
          ),
          
          const SizedBox(height: AppTheme.spacingMd),
          
          Text(
            dominantEmotion,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: scheme.textDarkColor,
            ),
          ),
          
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: scheme.textMediumColor,
            ),
          ),
          
          const SizedBox(height: AppTheme.spacingLg),
          
          // 积极/消极比例
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  '积极',
                  '${avgPositive.toInt()}%',
                  AppTheme.success,
                  Icons.trending_up,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: scheme.lightColor,
              ),
              Expanded(
                child: _buildStatItem(
                  '消极',
                  '${avgNegative.toInt()}%',
                  AppTheme.error,
                  Icons.trending_down,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEmotionDistributionChart(
    ThemeScheme scheme,
    Map<String, int> distribution,
    int total,
  ) {
    final emotions = [
      {'name': '开心', 'color': 0xFF4CAF50, 'emoji': '😊'},
      {'name': '平静', 'color': 0xFF2196F3, 'emoji': '😌'},
      {'name': '难过', 'color': 0xFF9E9E9E, 'emoji': '😢'},
      {'name': '生气', 'color': 0xFFF44336, 'emoji': '😠'},
      {'name': '惊喜', 'color': 0xFFFF9800, 'emoji': '😮'},
      {'name': '疲惫', 'color': 0xFF795548, 'emoji': '😴'},
    ];

    return Container(
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: emotions.map((emotion) {
          final name = emotion['name'] as String;
          final count = distribution[name] ?? 0;
          final percentage = total > 0 ? (count / total * 100) : 0;
          final color = Color(emotion['color'] as int);
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text(
                  emotion['emoji'] as String,
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.textDarkColor,
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.backgroundColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: percentage / 100,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color, color.withValues(alpha: 0.7)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${percentage.toInt()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKeywordsCloud(ThemeScheme scheme) {
    // 从所有日记中提取关键词
    final allKeywords = <String, int>{};
    for (final diary in _diaries) {
      final content = '${diary.title ?? ''} ${diary.content ?? ''}';
      final result = SentimentAnalysisService.analyze(content);
      for (final keyword in result.keywords) {
        allKeywords[keyword] = (allKeywords[keyword] ?? 0) + 1;
      }
    }
    
    final sortedKeywords = allKeywords.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topKeywords = sortedKeywords.take(15).toList();
    
    if (topKeywords.isEmpty) {
      return Container(
        padding: AppTheme.cardPadding,
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(AppTheme.largeRadius),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Center(
          child: Text(
            '暂无关键词数据',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textLightColor,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: topKeywords.map((entry) {
          final intensity = entry.value / topKeywords.first.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.lightColor.withValues(alpha: 0.2 + intensity * 0.3),
              borderRadius: BorderRadius.circular(AppTheme.chipRadius),
            ),
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: 12 + intensity * 4,
                fontWeight: intensity > 0.7 ? FontWeight.w600 : FontWeight.w500,
                color: scheme.textDarkColor,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAdviceCard(ThemeScheme scheme) {
    final dominantEmotion = _stats['dominantEmotion'] as String? ?? '平静';
    final avgPositive = _stats['averagePositive'] as double? ?? 0.5;
    final advice = SentimentAnalysisService.getAdvice(dominantEmotion, avgPositive);
    
    return Container(
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryMint.withValues(alpha: 0.1),
            scheme.cardColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        border: Border.all(
          color: AppTheme.primaryMint.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: AppTheme.primaryMint,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '情绪建议',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            advice,
            style: TextStyle(
              fontSize: 15,
              color: scheme.textMediumColor,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyTab(ThemeScheme scheme) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primaryMint,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        itemCount: _weeklyData.length,
        itemBuilder: (context, index) {
          final data = _weeklyData[index];
          return _buildDailyEmotionCard(scheme, data);
        },
      ),
    );
  }

  Widget _buildMonthlyTab(ThemeScheme scheme) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primaryMint,
      child: GridView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 0.8,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _monthlyData.length,
        itemBuilder: (context, index) {
          final data = _monthlyData[index];
          return _buildMonthDayCell(scheme, data);
        },
      ),
    );
  }

  Widget _buildDailyEmotionCard(ThemeScheme scheme, Map<String, dynamic> data) {
    final hasRecord = data['count'] > 0;
    final color = Color(data['color'] as int);
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          // 日期
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: hasRecord ? color.withValues(alpha: 0.1) : scheme.backgroundColor,
              borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data['weekday'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.textLightColor,
                  ),
                ),
                Text(
                  '${(data['date'] as DateTime).day}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: hasRecord ? color : scheme.textLightColor,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: AppTheme.spacingMd),
          
          // 情绪
          if (hasRecord) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.7)],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  data['emoji'] as String,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['emotion'] as String,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  Text(
                    '${data['count']}篇日记',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.textLightColor,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                '无记录',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.textLightColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthDayCell(ThemeScheme scheme, Map<String, dynamic> data) {
    final hasRecord = data['emotion'] != '无';
    final color = Color(data['color'] as int);
    
    return Container(
      decoration: BoxDecoration(
        color: hasRecord ? color.withValues(alpha: 0.15) : scheme.backgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.smallRadius),
        border: hasRecord
            ? Border.all(color: color.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${data['day']}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: hasRecord ? color : scheme.textLightColor,
            ),
          ),
          if (hasRecord) ...[
            const SizedBox(height: 4),
            Text(
              data['emoji'] as String,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }
}
