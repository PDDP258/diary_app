import '../models/diary.dart';

/// 情感分析结果
class SentimentResult {
  final double positive; // 积极程度 0.0 - 1.0
  final double negative; // 消极程度 0.0 - 1.0
  final double neutral; // 中性程度 0.0 - 1.0
  final String dominantEmotion; // 主导情绪
  final String emoji; // 情绪表情
  final int color; // 情绪颜色
  final List<String> keywords; // 检测到的关键词
  final double intensity; // 情绪强度 0.0 - 1.0

  const SentimentResult({
    required this.positive,
    required this.negative,
    required this.neutral,
    required this.dominantEmotion,
    required this.emoji,
    required this.color,
    this.keywords = const [],
    this.intensity = 0.5,
  });

  /// 中性结果
  factory SentimentResult.neutral() {
    return const SentimentResult(
      positive: 0.33,
      negative: 0.33,
      neutral: 0.34,
      dominantEmotion: '平静',
      emoji: '😌',
      color: 0xFF2196F3,
      keywords: [],
      intensity: 0.3,
    );
  }

  /// 获取情绪描述
  String get description {
    if (dominantEmotion == '开心') {
      if (intensity > 0.8) return '非常愉快';
      if (intensity > 0.5) return '心情不错';
      return '有点开心';
    } else if (dominantEmotion == '难过') {
      if (intensity > 0.8) return '非常难过';
      if (intensity > 0.5) return '心情低落';
      return '有些伤感';
    } else if (dominantEmotion == '生气') {
      if (intensity > 0.8) return '非常愤怒';
      if (intensity > 0.5) return '有些烦躁';
      return '略有不快';
    } else if (dominantEmotion == '惊喜') {
      return '充满惊喜';
    } else if (dominantEmotion == '疲惫') {
      return '感到疲惫';
    }
    return '心情平静';
  }
}

/// 情绪关键词库
class EmotionKeywords {
  // 积极情绪关键词及其权重
  static const Map<String, double> positiveWords = {
    // 开心
    '开心': 1.0, '快乐': 1.0, '高兴': 1.0, '愉快': 0.9, '兴奋': 0.9,
    '幸福': 1.0, '满足': 0.8, '欣慰': 0.8, '喜悦': 0.9, '欢喜': 0.9,
    '爽': 0.8, '棒': 0.8, '赞': 0.8, '完美': 0.8, '优秀': 0.7,
    '成功': 0.8, '达成': 0.7, '收获': 0.7, '进步': 0.7, '成长': 0.7,
    '喜欢': 0.8, '爱': 0.9, '热爱': 0.9, '享受': 0.8, '陶醉': 0.8,
    '期待': 0.7, '希望': 0.7, '憧憬': 0.7, '向往': 0.7, '渴望': 0.7,
    '轻松': 0.6, '自在': 0.6, '舒服': 0.6, '惬意': 0.7, '舒适': 0.6,
    '感恩': 0.8, '感谢': 0.7, '感激': 0.8, '感动': 0.8, '温暖': 0.7,
    '美好': 0.8, '精彩': 0.8, '美丽': 0.7, '可爱': 0.7, '有趣': 0.7,
    '哈哈': 0.6, '嘿嘿': 0.5, '嘻嘻': 0.6, '呵呵': 0.4, '笑脸': 0.6,
    '胜利': 0.8, '突破': 0.8, '超越': 0.8, '创新': 0.7, '惊喜': 0.9,
  };

  // 消极情绪关键词及其权重
  static const Map<String, double> negativeWords = {
    // 难过
    '难过': 1.0, '伤心': 1.0, '悲伤': 0.9, '痛苦': 0.9, '难受': 0.8,
    '失落': 0.8, '沮丧': 0.8, '郁闷': 0.7, '压抑': 0.7, '沉重': 0.7,
    '委屈': 0.8, '无奈': 0.7, '无助': 0.8, '孤独': 0.8, '寂寞': 0.7,
    '失望': 0.8, '绝望': 0.9, '灰心': 0.7, '气馁': 0.7, '挫败': 0.8,
    '哭': 0.8, '流泪': 0.8, '哭泣': 0.9, '泪流': 0.8, '心碎': 0.9,
    '遗憾': 0.7, '后悔': 0.7, '自责': 0.7, '内疚': 0.7, '愧疚': 0.7,
    '担心': 0.6, '焦虑': 0.7, '紧张': 0.6, '不安': 0.6, '害怕': 0.7,
    '疲惫': 0.6, '累': 0.6, '困倦': 0.5, '乏力': 0.6, '精疲力竭': 0.8,
    
    // 生气
    '生气': 1.0, '愤怒': 0.9, '气愤': 0.9, '恼火': 0.8, '恼怒': 0.8,
    '烦躁': 0.7, '暴躁': 0.8, '暴怒': 0.9, '火大': 0.8,
    '讨厌': 0.7, '厌恶': 0.7, '憎恨': 0.8, '反感': 0.6, '不满': 0.6,
    '抱怨': 0.6, '埋怨': 0.6, '不公平': 0.6, '冤': 0.6,
    '压力': 0.6, '窒息': 0.7, '透不过气': 0.7,
    '气死': 0.9, '烦死': 0.8, '累死了': 0.7, '崩溃': 0.9, '疯了': 0.8,
  };

  // 情绪强度修饰词
  static const Map<String, double> intensityModifiers = {
    '非常': 1.5, '特别': 1.4, '十分': 1.4, '极其': 1.6, '超级': 1.5,
    '很': 1.3, '挺': 1.2, '有点': 0.8, '稍微': 0.7, '略': 0.8,
    '太': 1.4, '好': 1.3, '真': 1.2, '实在': 1.3, '真的': 1.3,
    '无比': 1.6, '无限': 1.5, '极度': 1.6, '万分': 1.5,
    '不': -1.0, '没': -0.8, '没有': -0.8, '别': -0.8,
  };

  // 表情符号映射
  static const Map<String, String> emojiMap = {
    '开心': '😊', '快乐': '😄', '兴奋': '🤩', '幸福': '🥰',
    '难过': '😢', '伤心': '😭', '悲伤': '😞', '痛苦': '😫',
    '生气': '😠', '愤怒': '😡', '烦躁': '😤', '暴怒': '🤬',
    '惊喜': '😮', '惊讶': '😲', '期待': '🤗',
    '疲惫': '😴', '累': '😪', '困倦': '🥱',
    '平静': '😌', '安心': '😊', '放松': '😎',
    '担心': '😰', '焦虑': '😨', '害怕': '😱',
    '感动': '🥺', '温暖': '🥰', '感恩': '🙏',
  };
}

/// 本地情感分析服务 - 基于规则引擎，无需联网
class SentimentAnalysisService {
  SentimentAnalysisService._();
  
  static final SentimentAnalysisService _instance = SentimentAnalysisService._();
  static SentimentAnalysisService get instance => _instance;

  /// 分析文本情绪
  static SentimentResult analyze(String text) {
    if (text.trim().isEmpty) {
      return SentimentResult.neutral();
    }

    final detectedKeywords = <String>[];
    double positiveScore = 0;
    double negativeScore = 0;
    
    // 遍历积极词汇
    for (final entry in EmotionKeywords.positiveWords.entries) {
      if (text.contains(entry.key)) {
        double weight = entry.value;
        
        // 检查修饰词
        for (final mod in EmotionKeywords.intensityModifiers.entries) {
          if (text.contains(mod.key + entry.key) || 
              text.contains(entry.key + mod.key)) {
            weight *= mod.value.abs();
            detectedKeywords.add(mod.key + entry.key);
            break;
          }
        }
        
        positiveScore += weight;
        if (!detectedKeywords.any((k) => k.contains(entry.key))) {
          detectedKeywords.add(entry.key);
        }
      }
    }

    // 遍历消极词汇
    for (final entry in EmotionKeywords.negativeWords.entries) {
      if (text.contains(entry.key)) {
        double weight = entry.value;
        
        // 检查修饰词
        for (final mod in EmotionKeywords.intensityModifiers.entries) {
          if (text.contains(mod.key + entry.key) || 
              text.contains(entry.key + mod.key)) {
            weight *= mod.value.abs();
            detectedKeywords.add(mod.key + entry.key);
            break;
          }
        }
        
        negativeScore += weight;
        if (!detectedKeywords.any((k) => k.contains(entry.key))) {
          detectedKeywords.add(entry.key);
        }
      }
    }

    // 计算中性分数
    double totalScore = positiveScore + negativeScore;
    double neutralScore = totalScore > 0 ? 0.1 : 1.0;

    // 归一化
    if (totalScore > 0) {
      final sum = positiveScore + negativeScore + neutralScore;
      positiveScore /= sum;
      negativeScore /= sum;
      neutralScore /= sum;
    } else {
      return SentimentResult.neutral();
    }

    // 确定主导情绪
    String emotion;
    String emoji;
    int color;
    double intensity;

    if (positiveScore > negativeScore && positiveScore > neutralScore) {
      // 积极情绪
      intensity = positiveScore;
      if (detectedKeywords.any((k) => ['兴奋', '惊喜', '激动', '太棒了'].contains(k))) {
        emotion = '惊喜';
        emoji = '😮';
        color = 0xFFFF9800;
      } else if (detectedKeywords.any((k) => ['幸福', '爱', '热爱', '感动'].contains(k))) {
        emotion = '开心';
        emoji = '🥰';
        color = 0xFFE91E63;
      } else {
        emotion = '开心';
        emoji = '😊';
        color = 0xFF4CAF50;
      }
    } else if (negativeScore > positiveScore && negativeScore > neutralScore) {
      // 消极情绪
      intensity = negativeScore;
      if (detectedKeywords.any((k) => ['生气', '愤怒', '气愤', '恼火'].contains(k))) {
        emotion = '生气';
        emoji = '😠';
        color = 0xFFF44336;
      } else if (detectedKeywords.any((k) => ['疲惫', '累', '困倦', '精疲力竭'].contains(k))) {
        emotion = '疲惫';
        emoji = '😴';
        color = 0xFF795548;
      } else {
        emotion = '难过';
        emoji = '😢';
        color = 0xFF9E9E9E;
      }
    } else {
      // 中性
      emotion = '平静';
      emoji = '😌';
      color = 0xFF2196F3;
      intensity = neutralScore;
    }

    return SentimentResult(
      positive: positiveScore,
      negative: negativeScore,
      neutral: neutralScore,
      dominantEmotion: emotion,
      emoji: emoji,
      color: color,
      keywords: detectedKeywords.take(5).toList(),
      intensity: intensity.clamp(0.0, 1.0),
    );
  }

  /// 批量分析日记情绪
  static Future<Map<String, dynamic>> analyzeDiaries(List<Diary> diaries) async {
    if (diaries.isEmpty) {
      return {
        'averagePositive': 0.33,
        'averageNegative': 0.33,
        'averageNeutral': 0.34,
        'dominantEmotion': '平静',
        'emotionDistribution': {'开心': 0, '难过': 0, '生气': 0, '平静': 0, '惊喜': 0, '疲惫': 0},
      };
    }

    double totalPositive = 0;
    double totalNegative = 0;
    double totalNeutral = 0;
    Map<String, int> emotionCount = {
      '开心': 0, '难过': 0, '生气': 0, '平静': 0, '惊喜': 0, '疲惫': 0,
    };

    for (final diary in diaries) {
      final content = '${diary.title ?? ''} ${diary.content ?? ''}';
      final result = analyze(content);
      
      totalPositive += result.positive;
      totalNegative += result.negative;
      totalNeutral += result.neutral;
      
      emotionCount[result.dominantEmotion] = 
          (emotionCount[result.dominantEmotion] ?? 0) + 1;
    }

    final count = diaries.length;
    
    // 找出主导情绪
    String dominantEmotion = '平静';
    int maxCount = 0;
    emotionCount.forEach((emotion, count) {
      if (count > maxCount) {
        maxCount = count;
        dominantEmotion = emotion;
      }
    });

    return {
      'averagePositive': totalPositive / count,
      'averageNegative': totalNegative / count,
      'averageNeutral': totalNeutral / count,
      'dominantEmotion': dominantEmotion,
      'emotionDistribution': emotionCount,
    };
  }

  /// 获取情绪建议
  static String getAdvice(String emotion, double intensity) {
    if (emotion == '开心') {
      if (intensity > 0.8) {
        return '你的快乐很有感染力！记得记录下这些美好时刻。';
      }
      return '保持这份好心情，今天会是美好的一天。';
    } else if (emotion == '难过') {
      if (intensity > 0.8) {
        return '看起来你现在很难受。给自己一些时间，情绪会像云一样飘走的。';
      }
      return '每个人都有低落的时候，允许自己感受这些情绪。';
    } else if (emotion == '生气') {
      return '深呼吸，试着让自己冷静下来。写下感受有助于释放情绪。';
    } else if (emotion == '疲惫') {
      return '你需要好好休息。照顾好自己，别给自己太大压力。';
    } else if (emotion == '惊喜') {
      return '生活中的小惊喜真美好！期待更多美好的发生。';
    }
    return '平静也是一种力量。享受当下的宁静吧。';
  }

  /// 获取情绪趋势描述
  static String getTrendDescription(List<double> scores) {
    if (scores.length < 2) return '数据不足';
    
    final recent = scores.take(7).toList();
    final avg = recent.reduce((a, b) => a + b) / recent.length;
    
    if (avg > 0.7) return '最近情绪很积极';
    if (avg > 0.5) return '情绪整体不错';
    if (avg > 0.3) return '情绪较为平稳';
    return '最近可能有些低落，多关爱自己';
  }
}
