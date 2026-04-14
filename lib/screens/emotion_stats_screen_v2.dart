import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../providers/diary_provider.dart';
import '../services/sentiment_analysis_service.dart';
import 'package:provider/provider.dart';

/// 情绪统计页面 - 重新设计版
class EmotionStatsScreen extends StatefulWidget {
  const EmotionStatsScreen({super.key});

  @override
  State<EmotionStatsScreen> createState() => _EmotionStatsScreenState();
}

class _EmotionStatsScreenState extends State<EmotionStatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _weeklyData = [];

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
    
    final stats = await SentimentAnalysisService.analyzeDiaries(diaries);
    final weeklyData = _generateWeeklyData(diaries);
    
    if (mounted) {
      setState(() {
        _stats = stats;
        _weeklyData = weeklyData;
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
          'weekday': ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1],
          'emotion': result.dominantEmotion,
          'emoji': result.emoji,
          'color': result.color,
        });
      } else {
        data.add({
          'date': date,
          'weekday': ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1],
          'emotion': null,
          'emoji': null,
          'color': null,
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
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '情绪分析',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: scheme.textDarkColor,
          ),
        ),
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
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '本周'),
            Tab(text: '趋势'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildWeeklyTab(),
                _buildTrendTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    final scheme = AppTheme.schemeOf(context);
    final emotionDistribution = _stats['emotionDistribution'] as Map<String, int>? ?? {};
    final total = emotionDistribution.values.fold(0, (a, b) => a + b);
    final dominantEmotion = _stats['dominantEmotion'] as String? ?? '平静';
    final avgPositive = (_stats['averagePositive'] as double? ?? 0.33) * 100;
    
    // 情绪配置
    final emotionConfig = {
      '开心': {'emoji': '😊', 'color': 0xFF4CAF50, 'label': '开心'},
      '平静': {'emoji': '😌', 'color': 0xFF2196F3, 'label': '平静'},
      '难过': {'emoji': '😢', 'color': 0xFF9E9E9E, 'label': '难过'},
      '生气': {'emoji': '😠', 'color': 0xFFF44336, 'label': '生气'},
      '惊喜': {'emoji': '😮', 'color': 0xFFFF9800, 'label': '惊喜'},
      '疲惫': {'emoji': '😴', 'color': 0xFF795548, 'label': '疲惫'},
    };
    
    final config = emotionConfig[dominantEmotion] ?? emotionConfig['平静']!;
    
    return RefreshIndicator(
      onRefresh: _loadData,
      color: scheme.primaryColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 主导情绪卡片
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: scheme.lightColor.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // 情绪表情
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Color(config['color'] as int).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          config['emoji'] as String,
                          style: const TextStyle(fontSize: 40),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      dominantEmotion,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: scheme.textDarkColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '整体情绪状态',
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.textLightColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 积极度
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStatItem('积极度', '${avgPositive.toInt()}%', AppTheme.success),
                        Container(
                          width: 1,
                          height: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          color: scheme.lightColor,
                        ),
                        _buildStatItem('日记数', '$total', scheme.primaryColor),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 情绪分布
            if (total > 0) ...[
              Text(
                '情绪分布',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: scheme.lightColor.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: emotionDistribution.entries.map((entry) {
                      final config = emotionConfig[entry.key] ?? 
                          {'emoji': '😶', 'color': 0xFF9E9E9E};
                      final percentage = total > 0 ? (entry.value / total * 100) : 0;
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Text(
                              config['emoji'] as String,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: scheme.textDarkColor,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percentage / 100,
                                  backgroundColor: scheme.lightColor.withValues(alpha: 0.3),
                                  valueColor: AlwaysStoppedAnimation(
                                    Color(config['color'] as int),
                                  ),
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 45,
                              child: Text(
                                '${percentage.toInt()}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(config['color'] as int),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyTab() {
    final scheme = AppTheme.schemeOf(context);
    
    return RefreshIndicator(
      onRefresh: _loadData,
      color: scheme.primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _weeklyData.length,
        itemBuilder: (context, index) {
          final data = _weeklyData[index];
          final hasRecord = data['emotion'] != null;
          final isToday = index == _weeklyData.length - 1;
          
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isToday 
                    ? scheme.primaryColor.withValues(alpha: 0.3)
                    : scheme.lightColor.withValues(alpha: 0.5),
                width: isToday ? 2 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 日期
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isToday
                          ? scheme.primaryColor.withValues(alpha: 0.1)
                          : scheme.lightColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '周${data['weekday']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.textLightColor,
                          ),
                        ),
                        Text(
                          '${(data['date'] as DateTime).day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isToday ? scheme.primaryColor : scheme.textDarkColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 情绪
                  if (hasRecord) ...[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(data['color'] as int).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          data['emoji'] as String,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        data['emotion'] as String,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: scheme.textDarkColor,
                        ),
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrendTab() {
    final scheme = AppTheme.schemeOf(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 64,
              color: scheme.lightColor,
            ),
            const SizedBox(height: 16),
            Text(
              '情绪趋势',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '持续记录日记，我们会为你生成\n更详细的情绪趋势分析',
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
}
