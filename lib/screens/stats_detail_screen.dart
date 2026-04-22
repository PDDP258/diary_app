import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/diary_provider.dart';
import '../services/text_analysis_service.dart';
import '../utils/platform_helpers.dart';
import '../services/image_cache_service.dart';
import 'diary_cinema_screen.dart';
import 'tags_classification_screen.dart';

class StatsDetailScreen extends StatefulWidget {
  final int totalDiaries;
  final int uniqueDays;
  final int totalChars;
  final DateTime? startDate;
  final Map<String, int> moodDistribution;
  final List<String>? photoPaths;
  final Map<String, int>? weatherDistribution;
  final Map<String, int>? tagDistribution;
  final int? avgHour;

  const StatsDetailScreen({
    super.key,
    required this.totalDiaries,
    required this.uniqueDays,
    required this.totalChars,
    this.startDate,
    required this.moodDistribution,
    this.photoPaths,
    this.weatherDistribution,
    this.tagDistribution,
    this.avgHour,
  });

  @override
  State<StatsDetailScreen> createState() => _StatsDetailScreenState();
}

class _StatsDetailScreenState extends State<StatsDetailScreen> {
  List<MapEntry<String, int>> _topIdioms = [];
  List<MoodSnippet> _moodSnippets = [];
  bool _isAnalyzing = true;
  int _totalIdiomCount = 0;

  @override
  void initState() {
    super.initState();
    _analyzeTexts();
  }

  Future<void> _analyzeTexts() async {
    final provider = context.read<DiaryProvider>();
    final diaries = provider.diaries;

    if (diaries.isEmpty) {
      setState(() => _isAnalyzing = false);
      return;
    }

    // 分析成语
    final idioms = TextAnalysisService.getTopIdioms(diaries, limit: 10);

    // 计算成语总使用次数
    int totalCount = 0;
    for (final entry in idioms) {
      totalCount += entry.value;
    }

    // 提取心情片段
    final snippets = TextAnalysisService.extractMoodSnippets(diaries);

    if (mounted) {
      setState(() {
        _topIdioms = idioms;
        _moodSnippets = snippets;
        _totalIdiomCount = totalCount;
        _isAnalyzing = false;
      });
    }
  }

  /// 查看照片展览 - 显示所有照片，支持左右滑动浏览
  void _viewPhoto(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoGalleryScreen(
          photoPaths: widget.photoPaths!,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final daysSinceStart = widget.startDate != null
        ? DateTime.now().difference(widget.startDate!).inDays
        : 0;

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      '统计详情',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 年份标题
                Text(
                  DateTime.now().year.toString(),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: scheme.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(height: 24),

                // 问候语卡片
                _buildSummaryCard(daysSinceStart),
                const SizedBox(height: 20),

                // 电影放映入口
                _buildCinemaCard(),
                const SizedBox(height: 20),

                // 成语统计卡片
                if (_isAnalyzing)
                  _buildLoadingCard()
                else if (_topIdioms.isNotEmpty)
                  _buildIdiomCard(),

                if (!_isAnalyzing && _topIdioms.isNotEmpty)
                  const SizedBox(height: 20),

                // 心情片段卡片
                if (!_isAnalyzing && _moodSnippets.isNotEmpty) ...[
                  _buildMoodSnippetsCard(),
                  const SizedBox(height: 20),
                ],

                // 照片展览
                if (widget.photoPaths != null &&
                    widget.photoPaths!.isNotEmpty) ...[
                  _buildPhotoGallery(),
                  const SizedBox(height: 20),
                ],

                // 天气心情统计
                if (widget.weatherDistribution != null &&
                    widget.weatherDistribution!.isNotEmpty) ...[
                  _buildWeatherCard(),
                  const SizedBox(height: 20),
                ],

                // 写日记时间统计
                if (widget.avgHour != null) ...[
                  _buildTimeCard(),
                  const SizedBox(height: 20),
                ],

                // 详细统计
                _buildDetailCard(),
                const SizedBox(height: 20),

                // 心情分布
                if (widget.moodDistribution.isNotEmpty) ...[
                  _buildMoodCard(),
                  const SizedBox(height: 20),
                ],

                // 标签统计
                if (widget.tagDistribution != null &&
                    widget.tagDistribution!.isNotEmpty) ...[
                  _buildTagCard(),
                  const SizedBox(height: 20),
                ],

                const SizedBox(height: 40),
                _buildFooter(),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    final scheme = AppTheme.schemeOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primaryColor,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '正在分析日记内容...',
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdiomCard() {
    final scheme = AppTheme.schemeOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
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
                  color: AppTheme.selectedGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '成语',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.selectedGreen,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '共使用 $_totalIdiomCount 次',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.textLightColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 最常使用的成语
          if (_topIdioms.isNotEmpty) ...[
            Text(
              '你最常用的成语',
              style: TextStyle(
                fontSize: 14,
                color: scheme.textMediumColor,
              ),
            ),
            const SizedBox(height: 12),

            // 最大的成语展示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.selectedGreen.withValues(alpha: 0.3),
                    AppTheme.selectedGreen.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    _topIdioms.first.key,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.selectedGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '使用了 ${_topIdioms.first.value} 次',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.textMediumColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 其他成语标签
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _topIdioms.skip(1).take(9).map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.lightColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.textDarkColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMoodSnippetsCard() {
    final scheme = AppTheme.schemeOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
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
                  color: scheme.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.format_quote,
                  size: 20,
                  color: scheme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '心情片段',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 心情片段列表
          ..._moodSnippets.take(5).map((snippet) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: scheme.primaryColor.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 日期和表情
                  Row(
                    children: [
                      Text(
                        snippet.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        snippet.formattedDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.textLightColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 日记内容
                  Text(
                    '「${snippet.content}」',
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.textDarkColor,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 感悟
                  Text(
                    snippet.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(int daysSinceStart) {
    final scheme = AppTheme.schemeOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hi，',
              style: TextStyle(fontSize: 18, color: scheme.textDarkColor)),
          const SizedBox(height: 8),
          Text('时光匆匆，',
              style: TextStyle(fontSize: 16, color: scheme.textDarkColor)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 16, color: scheme.textDarkColor),
              children: [
                const TextSpan(text: '小记日记已陪伴你 '),
                TextSpan(
                  text: '$daysSinceStart',
                  style: TextStyle(
                    color: scheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const TextSpan(text: ' 天'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('在过去的一年中，',
              style: TextStyle(fontSize: 16, color: scheme.textDarkColor)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 16, color: scheme.textDarkColor),
              children: [
                const TextSpan(text: '你记录了 '),
                TextSpan(
                  text: '${widget.totalDiaries}',
                  style: TextStyle(
                    color: scheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const TextSpan(text: ' 篇日记，'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 16, color: scheme.textDarkColor),
              children: [
                const TextSpan(text: '总字数达到了 '),
                TextSpan(
                  text: widget.totalChars > 1000
                      ? '${(widget.totalChars / 1000).toStringAsFixed(1)}K'
                      : '${widget.totalChars}',
                  style: TextStyle(
                    color: scheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const TextSpan(text: ' 字'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGallery() {
    final scheme = AppTheme.schemeOf(context);
    final displayPhotos = widget.photoPaths!.take(6).toList();
    final hasMore = widget.photoPaths!.length > 6;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题区域
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    color: scheme.primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '照片回忆',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => _viewPhoto(0),
                child: Text(
                  '查看全部 ${widget.photoPaths!.length} 张',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 胶片风格照片墙
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A), // 深色胶片背景
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                // 胶片孔装饰 - 顶部
                _buildFilmHoles(),
                const SizedBox(height: 12),

                // 照片网格
                SizedBox(
                  height: 280, // 固定高度确保Y轴居中
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: displayPhotos.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == displayPhotos.length && hasMore) {
                        // 查看更多按钮
                        return GestureDetector(
                          onTap: () => _viewPhoto(0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 32,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '+${widget.photoPaths!.length - 6}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return GestureDetector(
                        onTap: () => _viewPhoto(index),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: PlatformImage(
                              path: displayPhotos[index],
                              fit: BoxFit.cover,
                              cacheWidth: 300,
                              cacheHeight: 300,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),
                // 胶片孔装饰 - 底部
                _buildFilmHoles(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 胶片孔装饰
  Widget _buildFilmHoles() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        12,
        (index) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: const Color(0xFF444444),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    final scheme = AppTheme.schemeOf(context);
    final mainWeather = widget.weatherDistribution!.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '这里的天气',
                  style: TextStyle(fontSize: 14, color: scheme.textMediumColor),
                ),
                const SizedBox(height: 4),
                Text(
                  '常常是 $mainWeather',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor),
                ),
              ],
            ),
          ),
          Icon(
            _getWeatherIcon(mainWeather),
            size: 40,
            color: scheme.primaryColor,
          ),
        ],
      ),
    );
  }

  IconData _getWeatherIcon(String weather) {
    switch (weather) {
      case '晴':
        return Icons.wb_sunny;
      case '多云':
        return Icons.wb_cloudy;
      case '阴':
        return Icons.cloud;
      case '雨':
        return Icons.water_drop;
      case '雪':
        return Icons.ac_unit;
      default:
        return Icons.wb_sunny_outlined;
    }
  }

  Widget _buildTimeCard() {
    final hour = widget.avgHour!;
    final timePeriod = _getTimePeriod(hour);
    final timeDesc = _getTimeDescription(hour);
    final timeEmoji = _getTimeEmoji(hour);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667eea).withValues(alpha: 0.8),
            const Color(0xFF764ba2).withValues(alpha: 0.8),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '最喜欢写日记的时间是',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              Text(
                timeEmoji,
                style: const TextStyle(fontSize: 32),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$timePeriod $hour点',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            timeDesc,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  String _getTimePeriod(int hour) {
    if (hour >= 0 && hour < 5) return '凌晨';
    if (hour >= 5 && hour < 9) return '早上';
    if (hour >= 9 && hour < 12) return '上午';
    if (hour >= 12 && hour < 14) return '中午';
    if (hour >= 14 && hour < 18) return '下午';
    if (hour >= 18 && hour < 22) return '晚上';
    return '深夜';
  }

  String _getTimeDescription(int hour) {
    if (hour >= 0 && hour < 5) return '夜深人静，适合回忆';
    if (hour >= 5 && hour < 9) return '清晨时光，宁静美好';
    if (hour >= 9 && hour < 12) return '上午时光，充满活力';
    if (hour >= 12 && hour < 14) return '午休时光，惬意悠闲';
    if (hour >= 14 && hour < 18) return '下午时光，思绪飞扬';
    if (hour >= 18 && hour < 22) return '傍晚时光，记录一天';
    return '深夜时光，与自己对话';
  }

  String _getTimeEmoji(int hour) {
    if (hour >= 0 && hour < 5) return '🌙';
    if (hour >= 5 && hour < 9) return '🌅';
    if (hour >= 9 && hour < 12) return '☀️';
    if (hour >= 12 && hour < 14) return '🌤️';
    if (hour >= 14 && hour < 18) return '🌇';
    if (hour >= 18 && hour < 22) return '🌆';
    return '🌙';
  }

  Widget _buildDetailCard() {
    final scheme = AppTheme.schemeOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '详细统计',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('日记总数', '${widget.totalDiaries} 篇'),
          _buildDetailRow('记载天数', '${widget.uniqueDays} 天'),
          _buildDetailRow('总字符数', '${widget.totalChars} 字'),
          _buildDetailRow(
            '开始日期',
            widget.startDate != null
                ? DateFormat('yyyy年M月d日').format(widget.startDate!)
                : '-',
          ),
          _buildDetailRow(
            '平均每日字数',
            widget.uniqueDays > 0
                ? '${(widget.totalChars / widget.uniqueDays).toStringAsFixed(0)} 字'
                : '0 字',
          ),
        ],
      ),
    );
  }

  Widget _buildMoodCard() {
    final scheme = AppTheme.schemeOf(context);
    final total = widget.moodDistribution.values.fold(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '心情分布',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor),
          ),
          const SizedBox(height: 16),
          ...widget.moodDistribution.entries.map((entry) {
            final percentage =
                total > 0 ? (entry.value / total * 100).toInt() : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                      width: 80,
                      child: Text(entry.key,
                          style: TextStyle(color: scheme.textDarkColor))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total > 0 ? entry.value / total : 0,
                        backgroundColor:
                            scheme.lightColor.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation(scheme.primaryColor),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$percentage%',
                      style: TextStyle(color: scheme.textMediumColor)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTagCard() {
    final scheme = AppTheme.schemeOf(context);
    final sortedTags = widget.tagDistribution!.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TagsClassificationScreen(),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(AppTheme.largeRadius),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '最常用的标签',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '查看全部',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: scheme.primaryColor,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sortedTags.take(10).map((entry) {
                return Chip(
                  label: Text('${entry.key} (${entry.value})'),
                  backgroundColor: scheme.lightColor.withValues(alpha: 0.3),
                  labelStyle: TextStyle(color: scheme.primaryColor),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCinemaCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const DiaryCinemaScreen(),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF667eea).withValues(alpha: 0.8),
              const Color(0xFF764ba2).withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.largeRadius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667eea).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.movie,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '电影放映',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '像看电影一样回顾日记',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward,
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final scheme = AppTheme.schemeOf(context);
    return Center(
      child: Column(
        children: [
          Text(
            '每一页日记，',
            style: TextStyle(fontSize: 16, color: scheme.textMediumColor),
          ),
          const SizedBox(height: 8),
          Text(
            '都是时光的定格。',
            style: TextStyle(fontSize: 16, color: scheme.textMediumColor),
          ),
          const SizedBox(height: 8),
          Text(
            '期待与你在未来的日子里，',
            style: TextStyle(fontSize: 16, color: scheme.textMediumColor),
          ),
          const SizedBox(height: 8),
          Text(
            '继续书写属于你的故事',
            style: TextStyle(fontSize: 16, color: scheme.textMediumColor),
          ),
          const SizedBox(height: 24),
          Text(
            '小记日记 v1.20.0',
            style: TextStyle(fontSize: 14, color: scheme.textLightColor),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final scheme = AppTheme.schemeOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 15, color: scheme.textMediumColor),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.textDarkColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// 照片展览页面 - 显示所有照片，支持左右滑动浏览
class PhotoGalleryScreen extends StatefulWidget {
  final List<String> photoPaths;
  final int initialIndex;

  const PhotoGalleryScreen({
    super.key,
    required this.photoPaths,
    required this.initialIndex,
  });

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 照片页面视图
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photoPaths.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: PreviewImage(
                    path: widget.photoPaths[index],
                    fit: BoxFit.contain,
                    useOriginal: true,
                  ),
                ),
              );
            },
          ),

          // 顶部工具栏
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 返回按钮
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  // 页码指示器
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.photoPaths.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 占位，保持对称
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),

          // 底部缩略图列表
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.photoPaths.length,
                    itemBuilder: (context, index) {
                      final isSelected = index == _currentIndex;
                      return GestureDetector(
                        onTap: () {
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  )
                                : null,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: PlatformImage(
                            path: widget.photoPaths[index],
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
