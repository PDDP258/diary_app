import 'dart:math';
import '../models/diary.dart';
import '../models/mood.dart';
import 'database_service.dart';

/// 智能回忆类型
enum RecallType {
  onThisDay,        // 历史上的今天
  similarMood,      // 相似心情
  sameLocation,     // 同一地点
  sameWeather,      // 相似天气
  thematic,         // 主题相关
  random,           // 随机回忆
}

/// 回忆项
class RecallItem {
  final Diary diary;
  final RecallType type;
  final String title;
  final String subtitle;
  final String? highlight;
  final int relevance; // 相关度 1-100

  RecallItem({
    required this.diary,
    required this.type,
    required this.title,
    required this.subtitle,
    this.highlight,
    this.relevance = 50,
  });

  // 获取类型图标
  String get icon {
    switch (type) {
      case RecallType.onThisDay:
        return '📅';
      case RecallType.similarMood:
        return '😊';
      case RecallType.sameLocation:
        return '📍';
      case RecallType.sameWeather:
        return '☁️';
      case RecallType.thematic:
        return '🔗';
      case RecallType.random:
        return '✨';
    }
  }

  // 获取类型颜色
  int get color {
    switch (type) {
      case RecallType.onThisDay:
        return 0xFF2196F3; // 蓝色
      case RecallType.similarMood:
        return 0xFF4CAF50; // 绿色
      case RecallType.sameLocation:
        return 0xFFFF9800; // 橙色
      case RecallType.sameWeather:
        return 0xFF9C27B0; // 紫色
      case RecallType.thematic:
        return 0xFF00BCD4; // 青色
      case RecallType.random:
        return 0xFFE91E63; // 粉色
    }
  }
}

/// 智能回忆服务 - 纯本地，无需联网
class SmartRecallService {
  SmartRecallService._();
  
  static final SmartRecallService _instance = SmartRecallService._();
  static SmartRecallService get instance => _instance;

  final Random _random = Random();

  /// 获取综合回忆推荐
  static Future<List<RecallItem>> getSmartRecalls({
    int limit = 5,
    Diary? currentDiary, // 当前正在查看的日记
    Mood? currentMood,   // 当前心情
  }) async {
    final recalls = <RecallItem>[];
    final usedDiaryIds = <int>{};
    
    // 1. 历史上的今天（优先级最高）
    final onThisDay = await _getOnThisDayRecall();
    if (onThisDay != null) {
      recalls.add(onThisDay);
      usedDiaryIds.add(onThisDay.diary.id!);
    }
    
    // 2. 相似心情
    if (currentMood != null) {
      final similarMood = await _getSimilarMoodRecall(currentMood, usedDiaryIds);
      if (similarMood != null) {
        recalls.add(similarMood);
        usedDiaryIds.add(similarMood.diary.id!);
      }
    }
    
    // 3. 主题相关（基于当前日记）
    if (currentDiary != null) {
      final thematic = await _getThematicRecall(currentDiary, usedDiaryIds);
      if (thematic != null) {
        recalls.add(thematic);
        usedDiaryIds.add(thematic.diary.id!);
      }
    }
    
    // 4. 随机回忆
    final randomRecalls = await _getRandomRecalls(
      limit: limit - recalls.length,
      excludeIds: usedDiaryIds,
    );
    recalls.addAll(randomRecalls);
    
    return recalls;
  }

  /// 获取"历史上的今天"
  static Future<RecallItem?> _getOnThisDayRecall() async {
    final now = DateTime.now();
    final diaries = await DatabaseService.getAllDiaries();
    
    // 查找同月同日的日记（不同年份）
    final candidates = diaries.where((d) {
      final date = DateTime.parse(d.date);
      return date.month == now.month && 
             date.day == now.day && 
             date.year < now.year;
    }).toList();
    
    if (candidates.isEmpty) return null;
    
    // 优先选择去年，其次前年
    candidates.sort((a, b) {
      final dateA = DateTime.parse(a.date);
      final dateB = DateTime.parse(b.date);
      return dateB.year.compareTo(dateA.year);
    });
    
    final diary = candidates.first;
    final date = DateTime.parse(diary.date);
    final yearsAgo = now.year - date.year;
    
    String title;
    if (yearsAgo == 1) {
      title = '去年的今天';
    } else if (yearsAgo == 2) {
      title = '前年的今天';
    } else {
      title = '$yearsAgo年前的今天';
    }
    
    return RecallItem(
      diary: diary,
      type: RecallType.onThisDay,
      title: title,
      subtitle: _formatDateShort(date),
      highlight: diary.title ?? _getContentPreview(diary.content ?? '', 30),
      relevance: 100,
    );
  }

  /// 获取相似心情的回忆
  static Future<RecallItem?> _getSimilarMoodRecall(
    Mood mood, 
    Set<int> excludeIds,
  ) async {
    final diaries = await DatabaseService.getAllDiaries();
    
    final candidates = diaries.where((d) {
      return d.moodId == mood.id && 
             d.id != null && 
             !excludeIds.contains(d.id);
    }).toList();
    
    if (candidates.isEmpty) return null;
    
    // 随机选择一篇
    final diary = candidates[Random().nextInt(candidates.length)];
    final date = DateTime.parse(diary.date);
    
    return RecallItem(
      diary: diary,
      type: RecallType.similarMood,
      title: '同样是${mood.name}的日子',
      subtitle: _formatDateRelative(date),
      highlight: diary.title ?? _getContentPreview(diary.content ?? '', 30),
      relevance: 70,
    );
  }

  /// 获取主题相关的回忆
  static Future<RecallItem?> _getThematicRecall(
    Diary currentDiary, 
    Set<int> excludeIds,
  ) async {
    // 提取关键词（简单实现：使用标题中的词语）
    final keywords = _extractKeywords('${currentDiary.title ?? ''} ${currentDiary.content ?? ''}');
    if (keywords.isEmpty) return null;
    
    final diaries = await DatabaseService.getAllDiaries();
    
    // 查找包含相似关键词的日记
    final candidates = <RecallItem>[];
    
    for (final diary in diaries) {
      if (diary.id == null || excludeIds.contains(diary.id)) continue;
      if (diary.id == currentDiary.id) continue;
      
      final content = '${diary.title ?? ''} ${diary.content ?? ''}';
      int matchCount = 0;
      
      for (final keyword in keywords) {
        if (content.contains(keyword)) {
          matchCount++;
        }
      }
      
      if (matchCount > 0) {
        final date = DateTime.parse(diary.date);
        candidates.add(RecallItem(
          diary: diary,
          type: RecallType.thematic,
          title: '相关回忆',
          subtitle: _formatDateRelative(date),
          highlight: diary.title ?? _getContentPreview(diary.content ?? '', 30),
          relevance: 40 + matchCount * 20,
        ));
      }
    }
    
    if (candidates.isEmpty) return null;
    
    // 选择相关度最高的
    candidates.sort((a, b) => b.relevance.compareTo(a.relevance));
    return candidates.first;
  }

  /// 获取随机回忆
  static Future<List<RecallItem>> _getRandomRecalls({
    required int limit,
    required Set<int> excludeIds,
  }) async {
    if (limit <= 0) return [];
    
    final diaries = await DatabaseService.getAllDiaries();
    final candidates = diaries.where((d) {
      return d.id != null && !excludeIds.contains(d.id);
    }).toList();
    
    if (candidates.isEmpty) return [];
    
    // 随机打乱
    candidates.shuffle(Random());
    
    final recalls = <RecallItem>[];
    for (int i = 0; i < min(limit, candidates.length); i++) {
      final diary = candidates[i];
      final date = DateTime.parse(diary.date);
      
      recalls.add(RecallItem(
        diary: diary,
        type: RecallType.random,
        title: '珍贵的回忆',
        subtitle: _formatDateRelative(date),
        highlight: diary.title ?? _getContentPreview(diary.content ?? '', 30),
        relevance: 30,
      ));
    }
    
    return recalls;
  }

  /// 获取指定年份的日记
  static Future<List<Diary>> getDiariesByYear(int year) async {
    final diaries = await DatabaseService.getAllDiaries();
    return diaries.where((d) {
      final date = DateTime.parse(d.date);
      return date.year == year;
    }).toList();
  }

  /// 获取指定月份的日记
  static Future<List<Diary>> getDiariesByMonth(int year, int month) async {
    final diaries = await DatabaseService.getAllDiaries();
    return diaries.where((d) {
      final date = DateTime.parse(d.date);
      return date.year == year && date.month == month;
    }).toList();
  }

  /// 获取指定日期范围的日记
  static Future<List<Diary>> getDiariesByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final diaries = await DatabaseService.getAllDiaries();
    return diaries.where((d) {
      final date = DateTime.parse(d.date);
      return date.isAfter(start.subtract(const Duration(days: 1))) &&
             date.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }

  /// 提取关键词
  static List<String> _extractKeywords(String text) {
    // 简单的关键词提取：过滤掉停用词，返回长度大于1的词
    final stopWords = {
      '的', '了', '是', '我', '你', '在', '和', '就', '不', '人', 
      '有', '都', '一', '个', '上', '也', '很', '到', '说', '要',
      '去', '会', '着', '没有', '看', '好', '自己', '这', '那',
    };
    
    final words = <String>[];
    final segments = text.split(RegExp(r'[\s,，.。!！?？;；]+'));
    
    for (final segment in segments) {
      if (segment.length >= 2 && !stopWords.contains(segment)) {
        words.add(segment);
      }
    }
    
    return words.take(5).toList();
  }

  /// 获取内容预览
  static String _getContentPreview(String content, int maxLength) {
    if (content.length <= maxLength) return content;
    return '${content.substring(0, maxLength)}...';
  }

  /// 格式化日期（短格式）
  static String _formatDateShort(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  /// 格式化日期（相对时间）
  static String _formatDateRelative(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 365) {
      final years = difference.inDays ~/ 365;
      return '$years年前';
    } else if (difference.inDays > 30) {
      final months = difference.inDays ~/ 30;
      return '$months个月前';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else {
      return '今天';
    }
  }

  /// 获取今日回忆标题
  static String getTodayRecallTitle() {
    final now = DateTime.now();
    final hour = now.hour;
    
    if (hour < 6) return '深夜 reminiscing';
    if (hour < 9) return '早安，回忆时刻';
    if (hour < 12) return '上午的回忆';
    if (hour < 14) return '午后 reminiscing';
    if (hour < 18) return '下午的回忆';
    if (hour < 22) return '晚间 reminiscing';
    return '晚安，回忆时刻';
  }

  /// 生成每日回忆推送内容
  static Future<Map<String, dynamic>?> getDailyRecallNotification() async {
    final recalls = await getSmartRecalls(limit: 1);
    if (recalls.isEmpty) return null;
    
    final recall = recalls.first;
    return {
      'title': recall.title,
      'body': recall.highlight ?? '点击查看详情',
      'diaryId': recall.diary.id,
    };
  }
}
