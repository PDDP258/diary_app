import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'badge_service.dart';
import 'database_service.dart';
import 'tag_system_service.dart';
import '../screens/custom_sticker_screen.dart';
import '../models/tag.dart';
import '../models/tag_system.dart';

/// 扭蛋稀有度
enum GachaRarity {
  common,    // 普通 - 60%
  uncommon,  // 稀有 - 25%
  rare,      // 史诗 - 12%
  legendary, // 传说 - 3%
}

/// 扭蛋奖励类型
enum GachaRewardType {
  sticker,            // 贴图
  theme,              // 主题色
  badgeHint,          // 徽章提示
  diaryPrompt,        // 日记提示
  luckyWord,          // 幸运语
  extraDraw,          // 额外抽奖次数
  milestone,          // 里程碑祝福
  memoryPrompt,       // 回忆提示
  moodSuggestion,     // 心情建议
  tagIdea,            // 标签创意
  stickerPack,        // 贴图包
  diaryTemplate,      // 日记模板
  photoChallenge,     // 照片挑战
  emotionAnalyze,     // 情感分析
  anniversaryHint,    // 纪念日提示
  achievementBonus,   // 成就加成
  avatar,             // 个人头像
  tag,                // 标签奖励
  currency,           // 货币奖励（经验、装饰点、碎片）
}

/// 扭蛋奖励
class GachaReward {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final GachaRarity rarity;
  final GachaRewardType type;
  final String? data;
  final String? effect;

  const GachaReward({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.rarity,
    required this.type,
    this.data,
    this.effect,
  });
}

/// 扭蛋结果
class GachaDrawResult {
  final GachaReward reward;
  final bool isDuplicate;
  String? duplicateBonus;

  GachaDrawResult({
    required this.reward,
    required this.isDuplicate,
    this.duplicateBonus,
  });
}

/// 扭蛋记录
class GachaRecord {
  final String id;
  final GachaReward reward;
  final DateTime time;

  GachaRecord({
    required this.id,
    required this.reward,
    required this.time,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rewardId': reward.id,
      'time': time.toIso8601String(),
    };
  }
}

/// 扭蛋服务
class GachaService {
  static const String _drawsKey = 'gacha_draws_remaining';
  static const String _lastDrawDateKey = 'gacha_last_draw_date';
  static const String _historyKey = 'gacha_history_';
  static const String _collectionKey = 'gacha_collection_';
  static const String _dailyDiaryCountKey = 'gacha_daily_diary_count_';
  static const String _firstDiaryAwardedKey = 'gacha_first_diary_awarded_';
  static const String _threeDiaryAwardedKey = 'gacha_three_diary_awarded_';
  static const int _initialDrawsDaily = 0;

  static final Random _random = Random();

  static const List<GachaReward> _allRewards = [
    GachaReward(
      id: 'sticker_star',
      name: '星星贴图',
      emoji: '⭐',
      description: '一颗闪耀的星星，点缀你的日记',
      rarity: GachaRarity.common,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'sticker_heart',
      name: '爱心贴图',
      emoji: '❤️',
      description: '满满的爱意，温暖每一天',
      rarity: GachaRarity.common,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'sticker_sun',
      name: '太阳贴图',
      emoji: '☀️',
      description: '温暖的阳光，照亮你的生活',
      rarity: GachaRarity.common,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'sticker_flower',
      name: '花朵贴图',
      emoji: '🌸',
      description: '美丽的花朵，绽放美好',
      rarity: GachaRarity.common,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'sticker_moon',
      name: '月亮贴图',
      emoji: '🌙',
      description: '温柔的月光，陪伴你入眠',
      rarity: GachaRarity.common,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'sticker_cloud',
      name: '云朵贴图',
      emoji: '☁️',
      description: '软软的云朵，放松心情',
      rarity: GachaRarity.common,
      type: GachaRewardType.sticker,
    ),
    // 货币奖励 - 普通
    GachaReward(
      id: 'currency_exp_small',
      name: '经验小包',
      emoji: '📈',
      description: '获得10点经验值',
      rarity: GachaRarity.common,
      type: GachaRewardType.currency,
      data: 'exp:10',
    ),
    GachaReward(
      id: 'currency_sticker_small',
      name: '碎片小包',
      emoji: '🧩',
      description: '获得1个贴纸碎片',
      rarity: GachaRarity.common,
      type: GachaRewardType.currency,
      data: 'sticker:1',
    ),
    GachaReward(
      id: 'currency_decor_small',
      name: '装饰点小包',
      emoji: '✨',
      description: '获得5点装饰点',
      rarity: GachaRarity.common,
      type: GachaRewardType.currency,
      data: 'decor:5',
    ),
    GachaReward(
      id: 'lucky_keepGoing',
      name: '继续加油',
      emoji: '💪',
      description: '坚持就是胜利！每一篇日记都是成长的足迹',
      rarity: GachaRarity.common,
      type: GachaRewardType.luckyWord,
    ),
    GachaReward(
      id: 'lucky_today',
      name: '今天很棒',
      emoji: '✨',
      description: '今天的你超棒的！为自己点个赞',
      rarity: GachaRarity.common,
      type: GachaRewardType.luckyWord,
    ),
    GachaReward(
      id: 'lucky_smile',
      name: '保持微笑',
      emoji: '😊',
      description: '记得保持微笑哦~微笑是最好的语言',
      rarity: GachaRarity.common,
      type: GachaRewardType.luckyWord,
    ),
    GachaReward(
      id: 'prompt_nature',
      name: '自然提示',
      emoji: '🌿',
      description: '今天有没有注意到大自然的美好？一片落叶、一缕阳光都是风景',
      rarity: GachaRarity.common,
      type: GachaRewardType.diaryPrompt,
    ),
    GachaReward(
      id: 'prompt_grateful',
      name: '感恩提示',
      emoji: '🙏',
      description: '今天有什么值得感恩的事吗？一个帮助、一份关怀都值得铭记',
      rarity: GachaRarity.common,
      type: GachaRewardType.diaryPrompt,
    ),
    GachaReward(
      id: 'prompt_dream',
      name: '梦想提示',
      emoji: '💭',
      description: '你的梦想是什么？今天为它做了什么？',
      rarity: GachaRarity.common,
      type: GachaRewardType.diaryPrompt,
    ),
    GachaReward(
      id: 'memory_lastWeek',
      name: '上周回忆',
      emoji: '📅',
      description: '回顾一下上周的今天，你在做什么？',
      rarity: GachaRarity.common,
      type: GachaRewardType.memoryPrompt,
    ),
    GachaReward(
      id: 'mood_happy',
      name: '快乐心情',
      emoji: '😄',
      description: '今天有什么让你开心的事？记录下来吧！',
      rarity: GachaRarity.common,
      type: GachaRewardType.moodSuggestion,
    ),
    GachaReward(
      id: 'tag_idea_daily',
      name: '日常标签',
      emoji: '🏷️',
      description: '试试给日记添加"日常"、"小确幸"这样的标签',
      rarity: GachaRarity.common,
      type: GachaRewardType.tagIdea,
    ),
    GachaReward(
      id: 'sticker_rainbow',
      name: '彩虹贴图',
      emoji: '🌈',
      description: '七彩彩虹，带来好运',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'sticker_diamond',
      name: '钻石贴图',
      emoji: '💎',
      description: '闪耀钻石，珍贵回忆',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'extra_1',
      name: '额外1次',
      emoji: '🎁',
      description: '获得额外1次抽奖机会！好运连连',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.extraDraw,
      data: '1',
    ),
    GachaReward(
      id: 'lucky_blessing',
      name: '祝福满满',
      emoji: '🌟',
      description: '愿你每天都开心！所有的美好都将如期而至',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.luckyWord,
    ),
    GachaReward(
      id: 'prompt_love',
      name: '爱情提示',
      emoji: '💕',
      description: '今天和爱的人有什么互动？一个拥抱、一句问候都是爱',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.diaryPrompt,
    ),
    GachaReward(
      id: 'prompt_friend',
      name: '友情提示',
      emoji: '👫',
      description: '最近和朋友联系了吗？友情需要维护',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.diaryPrompt,
    ),
    GachaReward(
      id: 'memory_firstTime',
      name: '初次体验',
      emoji: '🎯',
      description: '回想一下最近的第一次体验，第一次做的事情总是特别的',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.memoryPrompt,
    ),
    GachaReward(
      id: 'mood_calm',
      name: '平静心情',
      emoji: '😌',
      description: '偶尔记录平静的一天也是很好的，平静是一种力量',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.moodSuggestion,
    ),
    GachaReward(
      id: 'tag_idea_travel',
      name: '旅行标签',
      emoji: '✈️',
      description: '如果去了新地方，试试添加"旅行"、"探索"这样的标签',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.tagIdea,
    ),
    GachaReward(
      id: 'template_daily',
      name: '日常模板',
      emoji: '📝',
      description: '今天的三件好事：1.__ 2.__ 3.__',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.diaryTemplate,
      data: '今天的三件好事：\n1. \n2. \n3. ',
    ),
    // === 徽章提示奖励（引导用户解锁更多徽章）===
    GachaReward(
      id: 'hint_badge_time',
      name: '时间徽章提示',
      emoji: '🎖️',
      description: '提示：试试在不同时间段写日记，"早起鸟"(5-8点)和"夜猫子"(0-5点)徽章等着你',
      rarity: GachaRarity.common,
      type: GachaRewardType.badgeHint,
      data: 'time', // 关联时间类徽章
    ),
    GachaReward(
      id: 'hint_badge_photo',
      name: '照片徽章提示',
      emoji: '📸',
      description: '提示：连续7天添加照片可以解锁"每日一拍"徽章！累计50张还能获得"摄影师"',
      rarity: GachaRarity.common,
      type: GachaRewardType.badgeHint,
      data: 'photo', // 关联照片类徽章
    ),
    GachaReward(
      id: 'hint_badge_streak',
      name: '坚持徽章提示',
      emoji: '🔥',
      description: '提示：连续写日记能解锁"三连击"(3天)、"周不懈"(7天)、"满勤奖"(30天)徽章',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.badgeHint,
      data: 'streak', // 关联连续记录类徽章
    ),
    GachaReward(
      id: 'hint_badge_milestone',
      name: '里程碑徽章提示',
      emoji: '🏆',
      description: '提示：累计记录天数解锁"一周坚持"(7天)、"月度达人"(30天)、"百日纪念"(100天)',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.badgeHint,
      data: 'milestone', // 关联里程碑类徽章
    ),
    GachaReward(
      id: 'hint_badge_content',
      name: '创作徽章提示',
      emoji: '✍️',
      description: '提示：写长日记可解锁"五百言"(500字)、"千字文"(1000字)，加标题有"标题党"徽章',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.badgeHint,
      data: 'content', // 关联内容类徽章
    ),
    GachaReward(
      id: 'hint_badge_emotion',
      name: '情感徽章提示',
      emoji: '💝',
      description: '提示：记录不同心情解锁"开心果"(开心3天)、"恋爱中人"(爱情内容)、"旅行家"(旅行记录)',
      rarity: GachaRarity.rare,
      type: GachaRewardType.badgeHint,
      data: 'emotion', // 关联情感类徽章
    ),
    GachaReward(
      id: 'hint_badge_special',
      name: '特殊时刻徽章提示',
      emoji: '🎊',
      description: '提示：特定时间写日记有惊喜！生日"生日星"、元旦"跨年人"、雨天"雨夜思"',
      rarity: GachaRarity.rare,
      type: GachaRewardType.badgeHint,
      data: 'special', // 关联特殊类徽章
    ),
    GachaReward(
      id: 'hint_badge_total',
      name: '数量徽章提示',
      emoji: '📚',
      description: '提示：累计写10篇"初露锋芒"、50篇"笔耕不辍"、100篇"百篇成就"，越多越厉害',
      rarity: GachaRarity.rare,
      type: GachaRewardType.badgeHint,
      data: 'total', // 关联总数类徽章
    ),
    GachaReward(
      id: 'hint_badge_hidden',
      name: '隐藏徽章线索',
      emoji: '🎁',
      description: '线索：午夜12点整写日记有惊喜！累计10000字可解锁"万字王"，收集20个徽章得"徽章猎人"',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.badgeHint,
      data: 'hidden', // 关联隐藏类徽章
    ),
    // 货币奖励 - 稀有
    GachaReward(
      id: 'currency_exp_medium',
      name: '经验礼包',
      emoji: '📈',
      description: '获得30点经验值',
      rarity: GachaRarity.rare,
      type: GachaRewardType.currency,
      data: 'exp:30',
    ),
    GachaReward(
      id: 'currency_sticker_medium',
      name: '碎片礼包',
      emoji: '🧩',
      description: '获得3个贴纸碎片',
      rarity: GachaRarity.rare,
      type: GachaRewardType.currency,
      data: 'sticker:3',
    ),
    GachaReward(
      id: 'currency_decor_medium',
      name: '装饰点礼包',
      emoji: '✨',
      description: '获得15点装饰点',
      rarity: GachaRarity.rare,
      type: GachaRewardType.currency,
      data: 'decor:15',
    ),
    // 货币奖励 - 史诗
    GachaReward(
      id: 'currency_exp_large',
      name: '经验大宝箱',
      emoji: '📈',
      description: '获得80点经验值',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.currency,
      data: 'exp:80',
    ),
    GachaReward(
      id: 'currency_sticker_large',
      name: '碎片大宝箱',
      emoji: '🧩',
      description: '获得8个贴纸碎片',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.currency,
      data: 'sticker:8',
    ),
    GachaReward(
      id: 'currency_decor_large',
      name: '装饰点大宝箱',
      emoji: '✨',
      description: '获得40点装饰点',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.currency,
      data: 'decor:40',
    ),
    GachaReward(
      id: 'sticker_crown',
      name: '皇冠贴图',
      emoji: '👑',
      description: '尊贵的皇冠，你是生活的王者',
      rarity: GachaRarity.rare,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'sticker_firework',
      name: '烟花贴图',
      emoji: '🎆',
      description: '绚烂烟花，庆祝每一个值得纪念的日子',
      rarity: GachaRarity.rare,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'extra_3',
      name: '额外3次',
      emoji: '🎉',
      description: '获得额外3次抽奖机会！好运滚滚来',
      rarity: GachaRarity.rare,
      type: GachaRewardType.extraDraw,
      data: '3',
    ),
    GachaReward(
      id: 'milestone_encourage',
      name: '里程碑祝福',
      emoji: '🏆',
      description: '继续记录，下一个里程碑在等着你！每一步都算数',
      rarity: GachaRarity.rare,
      type: GachaRewardType.milestone,
    ),
    GachaReward(
      id: 'prompt_future',
      name: '未来提示',
      emoji: '🚀',
      description: '给一年后的自己写一段话，时间会给你答案',
      rarity: GachaRarity.rare,
      type: GachaRewardType.diaryPrompt,
    ),
    GachaReward(
      id: 'memory_yearAgo',
      name: '去年今日',
      emoji: '📆',
      description: '去年的今天你在做什么？对比一下，看看自己的成长',
      rarity: GachaRarity.rare,
      type: GachaRewardType.memoryPrompt,
    ),
    GachaReward(
      id: 'photo_challenge',
      name: '照片挑战',
      emoji: '📷',
      description: '今天试着拍三张照片：天空、食物、你喜欢的小物件',
      rarity: GachaRarity.rare,
      type: GachaRewardType.photoChallenge,
    ),
    GachaReward(
      id: 'emotion_analyze',
      name: '情感分析',
      emoji: '🎭',
      description: '今天经历了哪些情绪？试着用三个词描述',
      rarity: GachaRarity.rare,
      type: GachaRewardType.emotionAnalyze,
    ),
    GachaReward(
      id: 'anniversary_check',
      name: '纪念日提醒',
      emoji: '💕',
      description: '检查一下有没有即将到来的纪念日，提前准备惊喜',
      rarity: GachaRarity.rare,
      type: GachaRewardType.anniversaryHint,
    ),
    GachaReward(
      id: 'sticker_pack_basic',
      name: '基础贴图包',
      emoji: '🎨',
      description: '获得星星、爱心、太阳、月亮、花朵全套贴图！',
      rarity: GachaRarity.rare,
      type: GachaRewardType.stickerPack,
    ),
    GachaReward(
      id: 'legendary_golden',
      name: '金色传说',
      emoji: '✨',
      description: '传说中的奖励！你太幸运了！愿所有的美好都属于你',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.luckyWord,
      effect: '获得5次额外抽奖！',
    ),
    GachaReward(
      id: 'sticker_phoenix',
      name: '凤凰贴图',
      emoji: '🔥',
      description: '浴火重生的凤凰，象征着勇气和希望',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.sticker,
    ),
    GachaReward(
      id: 'extra_10',
      name: '额外10次',
      emoji: '🎊',
      description: '哇！获得额外10次抽奖机会！欧皇附体！',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.extraDraw,
      data: '10',
    ),
    GachaReward(
      id: 'legendary_blessing',
      name: '传说祝福',
      emoji: '🌟',
      description: '愿你所有的美好愿望都能实现！你是最棒的！',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.milestone,
      effect: '解锁隐藏徽章"传说收藏家"！',
    ),
    GachaReward(
      id: 'prompt_life',
      name: '人生感悟',
      emoji: '🌌',
      description: '如果用一句话总结你的人生哲学，那会是什么？',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.diaryPrompt,
    ),
    GachaReward(
      id: 'memory_timeCapsule',
      name: '时光胶囊',
      emoji: '⌛',
      description: '写一封信给5年后的自己，封存现在的梦想',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.memoryPrompt,
    ),
    GachaReward(
      id: 'achievement_double',
      name: '双倍成就',
      emoji: '💫',
      description: '今天写的日记将计入双倍进度！',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.achievementBonus,
    ),
    GachaReward(
      id: 'sticker_pack_legendary',
      name: '传说贴图包',
      emoji: '👑',
      description: '获得彩虹、钻石、皇冠、烟花、凤凰全套传说贴图！',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.stickerPack,
    ),
    GachaReward(
      id: 'template_reflection',
      name: '深度反思模板',
      emoji: '💡',
      description: '今日反思：我学到了什么？我感恩什么？明天要改进什么？',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.diaryTemplate,
      data: '今日反思：\n\n📚 我学到了什么：\n\n🙏 我感恩什么：\n\n🔄 明天要改进什么：',
    ),
    // === 精选头像（仅保留30%最好看的）===
    // 记录类头像（3个）- 描述关联用户数据
    GachaReward(
      id: 'avatar_diary_days',
      name: '时光旅人',
      emoji: '⏳',
      description: '已记录{days}天',
      rarity: GachaRarity.common,
      type: GachaRewardType.avatar,
      data: 'personalize_days',
    ),
    GachaReward(
      id: 'avatar_streak_master',
      name: '坚持达人',
      emoji: '🔥',
      description: '连续记录{streak}天',
      rarity: GachaRarity.rare,
      type: GachaRewardType.avatar,
      data: 'personalize_streak',
    ),
    GachaReward(
      id: 'avatar_diary_legend',
      name: '日记传说',
      emoji: '👑',
      description: '累计{totalDiaries}篇日记',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.avatar,
      data: 'personalize_total',
    ),
    // 精选个性头像（8个）
    GachaReward(
      id: 'avatar_northern_light',
      name: '极光之舞',
      emoji: '🌈',
      description: '绚烂的极光',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.avatar,
      effect: '获得时触发彩虹特效',
    ),
    GachaReward(
      id: 'avatar_mountain_top',
      name: '山巅之上',
      emoji: '🏔️',
      description: '登高望远',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.avatar,
      effect: '获得时触发山峰特效',
    ),
    GachaReward(
      id: 'avatar_forest_walk',
      name: '林间漫步',
      emoji: '🌲',
      description: '森林的呼吸',
      rarity: GachaRarity.rare,
      type: GachaRewardType.avatar,
    ),
    GachaReward(
      id: 'avatar_ocean_breeze',
      name: '海风轻拂',
      emoji: '🌊',
      description: '海的味道',
      rarity: GachaRarity.rare,
      type: GachaRewardType.avatar,
    ),
    GachaReward(
      id: 'avatar_sakura_fall',
      name: '樱花落',
      emoji: '🌸',
      description: '粉色的心情',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.avatar,
    ),
    GachaReward(
      id: 'avatar_cat_life',
      name: '猫咪日常',
      emoji: '🐱',
      description: '慵懒的午后',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.avatar,
    ),
    GachaReward(
      id: 'avatar_starry_night',
      name: '星空梦',
      emoji: '🌌',
      description: '繁星点点的梦境',
      rarity: GachaRarity.common,
      type: GachaRewardType.avatar,
    ),
    GachaReward(
      id: 'avatar_sunny_day',
      name: '晴天娃娃',
      emoji: '🌻',
      description: '阳光正好',
      rarity: GachaRarity.common,
      type: GachaRewardType.avatar,
    ),
    // === 目标达成头像（4个）===
    GachaReward(
      id: 'avatar_goal_achiever',
      name: '目标达成者',
      emoji: '🎯',
      description: '本月目标已完成',
      rarity: GachaRarity.rare,
      type: GachaRewardType.avatar,
      data: 'goal_achiever',
    ),
    GachaReward(
      id: 'avatar_consistent_writer',
      name: '笔耕不辍',
      emoji: '✍️',
      description: '连续7天达成目标',
      rarity: GachaRarity.rare,
      type: GachaRewardType.avatar,
      data: 'consistent_writer',
    ),
    GachaReward(
      id: 'avatar_overachiever',
      name: '超额完成',
      emoji: '🚀',
      description: '单月销量翻倍',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.avatar,
      data: 'overachiever',
    ),
    GachaReward(
      id: 'avatar_goal_master',
      name: '目标大师',
      emoji: '🏆',
      description: '连续3个月达成目标',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.avatar,
      data: 'goal_master',
    ),
    // === 目标道具奖励（6个）===
    GachaReward(
      id: 'goal_boost_1day',
      name: '目标加速卡',
      emoji: '⚡',
      description: '今日写日记算2篇进度',
      rarity: GachaRarity.common,
      type: GachaRewardType.currency,
      data: 'goal_boost:1',
    ),
    GachaReward(
      id: 'goal_protect_1day',
      name: '连续记录护盾',
      emoji: '🛡️',
      description: '今日不写也不会中断连续记录',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.currency,
      data: 'goal_protect:1',
    ),
    GachaReward(
      id: 'goal_double_exp',
      name: '双倍经验卡',
      emoji: '💎',
      description: '今日获得双倍经验值',
      rarity: GachaRarity.rare,
      type: GachaRewardType.currency,
      data: 'goal_double_exp:1',
    ),
    GachaReward(
      id: 'goal_streak_freeze',
      name: '连续记录冻结卡',
      emoji: '❄️',
      description: '连续记录暂停3天（期间不算中断）',
      rarity: GachaRarity.rare,
      type: GachaRewardType.currency,
      data: 'goal_streak_freeze:3',
    ),
    GachaReward(
      id: 'goal_bonus_draw',
      name: '目标奖励抽奖',
      emoji: '🎁',
      description: '额外获得3次扭蛋机会',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.extraDraw,
      data: '3',
    ),
    GachaReward(
      id: 'goal_perfect_month',
      name: '完美月度徽章',
      emoji: '🌟',
      description: '整月每天都写日记的荣耀证明',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.currency,
      data: 'perfect_month_badge',
    ),
    // === 标签类扭蛋奖励（8个）===
    GachaReward(
      id: 'tag_daily_life',
      name: '生活标签',
      emoji: '🏠',
      description: '获得"日常"标签，记录平凡生活中的点滴美好',
      rarity: GachaRarity.common,
      type: GachaRewardType.tag,
      data: '日常',
    ),
    GachaReward(
      id: 'tag_work_study',
      name: '奋斗标签',
      emoji: '💼',
      description: '获得"工作/学习"标签，记录职场和学业的成长',
      rarity: GachaRarity.common,
      type: GachaRewardType.tag,
      data: '工作',
    ),
    GachaReward(
      id: 'tag_emotion_mood',
      name: '心情标签',
      emoji: '💭',
      description: '获得"心情"标签，记录当下的情绪与感受',
      rarity: GachaRarity.common,
      type: GachaRewardType.tag,
      data: '心情',
    ),
    GachaReward(
      id: 'tag_travel_explore',
      name: '旅行标签',
      emoji: '✈️',
      description: '获得"旅行"标签，记录旅途中的风景与故事',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.tag,
      data: '旅行',
    ),
    GachaReward(
      id: 'tag_food_delicious',
      name: '美食标签',
      emoji: '🍜',
      description: '获得"美食"标签，记录舌尖上的幸福时刻',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.tag,
      data: '美食',
    ),
    GachaReward(
      id: 'tag_family_love',
      name: '家人标签',
      emoji: '👨‍👩‍👧‍👦',
      description: '获得"家人"标签，记录与亲人相处的温馨时光',
      rarity: GachaRarity.rare,
      type: GachaRewardType.tag,
      data: '家人',
    ),
    GachaReward(
      id: 'tag_dream_goal',
      name: '梦想标签',
      emoji: '🌟',
      description: '获得"梦想"标签，记录追逐目标的每一步',
      rarity: GachaRarity.rare,
      type: GachaRewardType.tag,
      data: '梦想',
    ),
    GachaReward(
      id: 'tag_gratitude_blessing',
      name: '感恩标签',
      emoji: '🙏',
      description: '获得"感恩"标签，记录值得感谢的人和事',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.tag,
      data: '感恩',
    ),
    // === 新增标签收藏奖励（6个）===
    GachaReward(
      id: 'tag_collector_novice',
      name: '标签新手',
      emoji: '🏷️',
      description: '解锁3个标签的收藏证明',
      rarity: GachaRarity.common,
      type: GachaRewardType.currency,
      data: 'tag_collector:3',
    ),
    GachaReward(
      id: 'tag_collector_amateur',
      name: '标签爱好者',
      emoji: '📚',
      description: '解锁10个标签的收藏证明',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.currency,
      data: 'tag_collector:10',
    ),
    GachaReward(
      id: 'tag_collector_expert',
      name: '标签专家',
      emoji: '🎓',
      description: '解锁25个标签的收藏证明',
      rarity: GachaRarity.rare,
      type: GachaRewardType.currency,
      data: 'tag_collector:25',
    ),
    GachaReward(
      id: 'tag_collector_master',
      name: '标签大师',
      emoji: '👑',
      description: '解锁50个标签的收藏证明',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.currency,
      data: 'tag_collector:50',
    ),
    GachaReward(
      id: 'tag_usage_boost',
      name: '标签热度卡',
      emoji: '🔥',
      description: '随机一个标签使用次数+5',
      rarity: GachaRarity.uncommon,
      type: GachaRewardType.currency,
      data: 'tag_usage_boost:5',
    ),
    GachaReward(
      id: 'tag_rainbow_set',
      name: '彩虹标签组',
      emoji: '🌈',
      description: '一次性获得7个彩虹色标签',
      rarity: GachaRarity.legendary,
      type: GachaRewardType.tag,
      data: 'rainbow_set',
    ),
  ];

  static Future<int> getRemainingDraws() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastDate = prefs.getString(_lastDrawDateKey);
    
    if (lastDate != today) {
      await prefs.setString(_lastDrawDateKey, today);
      await prefs.setInt(_drawsKey, _initialDrawsDaily);
      await prefs.setInt('$_dailyDiaryCountKey$today', 0);
      await prefs.setBool('$_firstDiaryAwardedKey$today', false);
      await prefs.setBool('$_threeDiaryAwardedKey$today', false);
      return _initialDrawsDaily;
    }
    
    return prefs.getInt(_drawsKey) ?? _initialDrawsDaily;
  }

  static Future<bool> useDraw() async {
    final remaining = await getRemainingDraws();
    if (remaining <= 0) return false;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_drawsKey, remaining - 1);
    return true;
  }

  static Future<void> addDraws(int count) async {
    final remaining = await getRemainingDraws();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_drawsKey, remaining + count);
  }

  static Future<void> onDiarySaved() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final prefs = await SharedPreferences.getInstance();
    
    final currentCount = prefs.getInt('$_dailyDiaryCountKey$today') ?? 0;
    final newCount = currentCount + 1;
    await prefs.setInt('$_dailyDiaryCountKey$today', newCount);
    
    final firstAwarded = prefs.getBool('$_firstDiaryAwardedKey$today') ?? false;
    if (!firstAwarded && newCount >= 1) {
      await addDraws(1);
      await prefs.setBool('$_firstDiaryAwardedKey$today', true);
    }
    
    final threeAwarded = prefs.getBool('$_threeDiaryAwardedKey$today') ?? false;
    if (!threeAwarded && newCount >= 3) {
      await addDraws(1);
      await prefs.setBool('$_threeDiaryAwardedKey$today', true);
    }
  }

  static GachaReward draw() {
    final double roll = _random.nextDouble();
    GachaRarity rarity;
    
    if (roll < 0.03) {
      rarity = GachaRarity.legendary;
    } else if (roll < 0.15) {
      rarity = GachaRarity.rare;
    } else if (roll < 0.40) {
      rarity = GachaRarity.uncommon;
    } else {
      rarity = GachaRarity.common;
    }
    
    final rewards = _allRewards.where((r) => r.rarity == rarity).toList();
    
    // 安全检查：如果该稀有度没有奖励，返回第一个可用的奖励
    if (rewards.isEmpty) {
      // 尝试其他稀有度
      for (final fallbackRarity in [
        GachaRarity.common,
        GachaRarity.uncommon,
        GachaRarity.rare,
        GachaRarity.legendary,
      ]) {
        final fallback = _allRewards.where((r) => r.rarity == fallbackRarity).toList();
        if (fallback.isNotEmpty) {
          return fallback[_random.nextInt(fallback.length)];
        }
      }
      // 如果全部为空，返回第一个奖励
      return _allRewards.first;
    }
    
    return rewards[_random.nextInt(rewards.length)];
  }

  static Future<GachaDrawResult> performDraw() async {
    final success = await useDraw();
    if (!success) {
      throw Exception('抽奖次数不足');
    }
    
    final reward = draw();
    final isDuplicate = await getCollectionCount(reward.id) > 0;
    
    final result = GachaDrawResult(
      reward: reward,
      isDuplicate: isDuplicate,
      duplicateBonus: null,
    );
    
    if (!isDuplicate) {
      await _handleRewardEffect(reward);
    }
    
    if (reward.type == GachaRewardType.extraDraw && reward.data != null) {
      final extra = int.tryParse(reward.data!) ?? 0;
      if (extra > 0) {
        await addDraws(extra);
      }
    }
    
    if (reward.id == 'legendary_golden') {
      await addDraws(5);
    }
    
    if (isDuplicate) {
      result.duplicateBonus = await _handleDuplicateReward(reward);
    }
    
    await _saveToHistory(reward);
    await _addToCollection(reward);
    
    return result;
  }

  static Future<void> _handleRewardEffect(GachaReward reward) async {
    final prefs = await SharedPreferences.getInstance();
    
    switch (reward.type) {
      case GachaRewardType.sticker:
        final emoji = reward.emoji;
        if (emoji.isNotEmpty) {
          await _addEmojiToCustomStickers(emoji);
        }
        break;
      
      case GachaRewardType.currency:
        // 处理货币奖励
        final data = reward.data;
        if (data != null && data.contains(':')) {
          final parts = data.split(':');
          final currencyType = parts[0];
          final amount = int.tryParse(parts[1]) ?? 0;
          
          switch (currencyType) {
            case 'exp':
              final currentExp = prefs.getInt('user_exp') ?? 0;
              await prefs.setInt('user_exp', currentExp + amount);
              break;
            case 'sticker':
              final currentPoints = prefs.getInt('sticker_points') ?? 0;
              await prefs.setInt('sticker_points', currentPoints + amount);
              break;
            case 'decor':
              final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
              await prefs.setInt('profile_decor_points', currentDecor + amount);
              break;
          }
        }
        break;
      
      case GachaRewardType.stickerPack:
        // 批量添加贴纸，减少多次写入操作
        final emojis = <String>[];
        if (reward.id == 'sticker_pack_basic') {
          emojis.addAll(['⭐', '❤️', '☀️', '🌙', '🌸']);
        } else if (reward.id == 'sticker_pack_legendary') {
          emojis.addAll(['🌈', '💎', '👑', '🎆', '🔥']);
        }
        // 使用批量添加方法
        await _addEmojisToCustomStickers(emojis);
        break;
      
      case GachaRewardType.badgeHint:
        // 徽章提示奖励 - 帮助用户解锁对应类型的徽章
        final hintType = reward.data;
        switch (hintType) {
          case 'time':
            // 解锁时间类徽章（早起鸟、夜猫子）
            await BadgeService.unlockBadge('early_bird');
            await BadgeService.unlockBadge('night_owl');
            break;
          case 'photo':
            // 解锁照片类徽章（每日一拍）
            await BadgeService.unlockBadge('daily_photo');
            break;
          case 'streak':
            // 解锁连续记录类徽章
            await BadgeService.unlockBadge('streak_3');
            await BadgeService.unlockBadge('streak_7');
            break;
          case 'milestone':
            // 里程碑徽章需要满足条件，这里只给一个鼓励性的解锁
            await BadgeService.unlockBadge('milestone_7');
            break;
          case 'content':
            // 内容创作类徽章
            await BadgeService.unlockBadge('content_100');
            await BadgeService.unlockBadge('content_with_title');
            break;
          case 'emotion':
            // 情感类徽章
            await BadgeService.unlockBadge('emotion_happy');
            await BadgeService.unlockBadge('emotion_love');
            break;
          case 'special':
            // 特殊时刻徽章
            await BadgeService.unlockBadge('special_rainy');
            await BadgeService.unlockBadge('special_birthday');
            break;
          case 'total':
            // 数量类徽章
            await BadgeService.unlockBadge('total_10');
            break;
          case 'hidden':
            // 隐藏徽章线索 - 不直接解锁，但给予提示奖励
            // 可以给予一个小奖励作为补偿
            await addDraws(2);
            break;
        }
        break;
      
      case GachaRewardType.milestone:
        if (reward.id == 'legendary_blessing') {
          await BadgeService.unlockBadge('legendary_collector');
        }
        break;

      case GachaRewardType.tag:
        // 处理标签奖励 - 自动创建标签
        final tagName = reward.data;
        if (tagName != null && tagName.isNotEmpty) {
          await _createTagFromGacha(tagName, reward.emoji);
        }
        // 获得标签时给予1点灵感点
        await _addWritingInspiration(1);
        break;

      case GachaRewardType.diaryPrompt:
        // 日记提示获得时给予1点灵感点
        await _addWritingInspiration(1);
        break;

      case GachaRewardType.tagIdea:
        // 标签创意获得时给予1点灵感点
        await _addWritingInspiration(1);
        break;

      case GachaRewardType.photoChallenge:
        // 照片挑战获得时给予1点灵感点
        await _addWritingInspiration(1);
        break;

      case GachaRewardType.luckyWord:
        // 幸运语获得时给予1点灵感点
        await _addWritingInspiration(1);
        break;

      case GachaRewardType.moodSuggestion:
        // 心情建议获得时给予1点灵感点
        await _addWritingInspiration(1);
        break;

      default:
        break;
    }
  }

  /// 处理重复奖励 - 系统联动机制
  /// 
  /// 重复奖励不再是简单的抽奖次数转换，而是根据奖励类型
  /// 转化为对应系统的实用资源，实现各系统联动
  /// 所有重复奖励额外增加50%加成
  /// 多次重复获得奖励递增：每次重复获得，奖励+1
  static Future<String> _handleDuplicateReward(GachaReward reward) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 获取该奖励的重复次数（当前是第几次重复获得）
    final duplicateCount = await getCollectionCount(reward.id);
    // 重复次数加成：每次重复获得，基础奖励+1
    final duplicateBonus = duplicateCount > 0 ? duplicateCount - 1 : 0;
    
    switch (reward.type) {
      // 1. 贴图重复 → 转化为贴纸积分（可兑换稀有贴图）+ 装饰点
      case GachaRewardType.sticker:
        final basePoints = reward.rarity == GachaRarity.legendary ? 5 :
                      reward.rarity == GachaRarity.rare ? 3 :
                      reward.rarity == GachaRarity.uncommon ? 2 : 1;
        final baseDecorPoints = reward.rarity == GachaRarity.legendary ? 10 :
                           reward.rarity == GachaRarity.rare ? 6 :
                           reward.rarity == GachaRarity.uncommon ? 4 : 2;
        // 增加重复次数加成和50%额外加成
        final points = ((basePoints + duplicateBonus) * 1.5).round();
        final decorPoints = ((baseDecorPoints + duplicateBonus) * 1.5).round();
        final currentPoints = prefs.getInt('sticker_points') ?? 0;
        await prefs.setInt('sticker_points', currentPoints + points);
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        return '重复贴图转化为 $points 个贴纸碎片 + $decorPoints 装饰点（第${duplicateCount}次重复，含50%额外加成）';

      // 2. 头像重复 → 转化为个人主页装饰点（降低50%）
      case GachaRewardType.avatar:
        final baseDecorPoints = reward.rarity == GachaRarity.legendary ? 25 :
                           reward.rarity == GachaRarity.rare ? 15 :
                           reward.rarity == GachaRarity.uncommon ? 10 : 5;
        // 增加重复次数加成和50%额外加成
        final decorPoints = ((baseDecorPoints + duplicateBonus) * 1.5).round();
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        return '重复头像转化为 $decorPoints 个装饰点（第${duplicateCount}次重复，含50%额外加成）';

      // 3. 标签重复 → 自动增加标签使用次数（帮助标签升级）
      case GachaRewardType.tag:
        // 标签重复时，给所有日记随机添加这个标签
        final allDiaries = await DatabaseService.getAllDiaries();
        final tagName = reward.data ?? reward.name.replaceAll('标签', '');
        int appliedCount = 0;
        for (var diary in allDiaries.take(3)) { // 给最近3篇日记添加
          if (diary.id != null) {
            await _applyTagToDiaryByName(diary.id!, tagName);
            appliedCount++;
          }
        }
        return '重复标签自动应用到 $appliedCount 篇日记（标签经验+$appliedCount）';

      // 4. 徽章提示重复 → 直接给予徽章进度加成
      case GachaRewardType.badgeHint:
        final baseBonusProgress = reward.rarity == GachaRarity.legendary ? 3 : 1;
        // 增加重复次数加成和50%额外加成
        final bonusProgress = ((baseBonusProgress + duplicateBonus) * 1.5).round();
        final currentBonus = prefs.getInt('badge_progress_bonus') ?? 0;
        await prefs.setInt('badge_progress_bonus', currentBonus + bonusProgress);
        return '重复徽章提示转化为进度加成：接下来 $bonusProgress 篇日记计双倍徽章进度（第${duplicateCount}次重复，含50%额外加成）';

      // 5. 日记模板重复 → 转化为日记字数加成
      case GachaRewardType.diaryTemplate:
        final baseWordBonus = reward.rarity == GachaRarity.legendary ? 500 : 100;
        // 增加重复次数加成和50%额外加成
        final wordBonus = ((baseWordBonus + duplicateBonus * 10) * 1.5).round();
        final currentBonus = prefs.getInt('word_count_bonus') ?? 0;
        await prefs.setInt('word_count_bonus', currentBonus + wordBonus);
        return '重复模板转化为字数加成：下次写日记额外+$wordBonus字统计（第${duplicateCount}次重复，含50%额外加成）';

      // 6. 心情建议重复 → 解锁特殊心情或加成 + 装饰点 + 灵感点
      case GachaRewardType.moodSuggestion:
        // 给予一个"心情能量"，可以让任意日记额外附加一个心情
        final baseMoodEnergy = reward.rarity == GachaRarity.rare ? 2 : 1;
        // 增加重复次数加成和50%额外加成
        final moodEnergy = ((baseMoodEnergy + duplicateBonus) * 1.5).round();
        final currentEnergy = prefs.getInt('mood_energy') ?? 0;
        await prefs.setInt('mood_energy', currentEnergy + moodEnergy);
        // 额外给予5-10装饰点，也增加重复次数加成
        final decorPoints = 5 + _random.nextInt(6) + duplicateBonus;
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        // 重复获得额外给予1点灵感点
        await _addWritingInspiration(1);
        return '重复心情建议转化为 $moodEnergy 点心情能量 + $decorPoints 装饰点 + 1 灵感点（第${duplicateCount}次重复，含50%额外加成）';

      // 7. 回忆提示重复 → 自动发现旧日记 + 装饰点
      case GachaRewardType.memoryPrompt:
        // 随机解锁一篇过去的日记（如果加密则临时解密查看）
        // 额外给予5-10装饰点，增加重复次数加成
        final decorPoints = 5 + _random.nextInt(6) + duplicateBonus;
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        final oldDiaries = await DatabaseService.getAllDiaries();
        if (oldDiaries.length > 7) {
          final randomOld = oldDiaries[_random.nextInt(oldDiaries.length - 7) + 7];
          return '重复回忆奖励：发现一篇回忆「${randomOld.title ?? '无标题'}」+ $decorPoints 装饰点（第${duplicateCount}次重复）';
        }
        return '重复回忆奖励：继续记录，未来将解锁更多回忆 + $decorPoints 装饰点（第${duplicateCount}次重复）';

      // 8. 里程碑/成就重复 → 转化为经验值加速
      case GachaRewardType.milestone:
      case GachaRewardType.achievementBonus:
        final baseExpBonus = reward.rarity == GachaRarity.legendary ? 100 : 50;
        // 增加重复次数加成和50%额外加成
        final expBonus = ((baseExpBonus + duplicateBonus * 5) * 1.5).round();
        final currentExp = prefs.getInt('user_exp') ?? 0;
        await prefs.setInt('user_exp', currentExp + expBonus);
        return '重复里程碑转化为 $expBonus 点经验值（第${duplicateCount}次重复，含50%额外加成）';

      // 货币奖励重复 → 给予额外加成
      case GachaRewardType.currency:
        final data = reward.data;
        if (data != null && data.contains(':')) {
          final parts = data.split(':');
          final currencyType = parts[0];
          final baseAmount = int.tryParse(parts[1]) ?? 0;
          // 重复获得时给予50%额外加成，并增加重复次数加成
          final bonusAmount = ((baseAmount + duplicateBonus) * 0.5).round();

          switch (currencyType) {
            case 'exp':
              final currentExp = prefs.getInt('user_exp') ?? 0;
              await prefs.setInt('user_exp', currentExp + bonusAmount);
              return '重复货币奖励：额外获得 $bonusAmount 点经验值（第${duplicateCount}次重复）';
            case 'sticker':
              final currentPoints = prefs.getInt('sticker_points') ?? 0;
              await prefs.setInt('sticker_points', currentPoints + bonusAmount);
              return '重复货币奖励：额外获得 $bonusAmount 个贴纸碎片（第${duplicateCount}次重复）';
            case 'decor':
              final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
              await prefs.setInt('profile_decor_points', currentDecor + bonusAmount);
              return '重复货币奖励：额外获得 $bonusAmount 点装饰点（第${duplicateCount}次重复）';
          }
        }
        return '重复货币奖励已转化（第${duplicateCount}次重复）';

      // 9. 幸运语重复 → 转化为写作灵感 + 装饰点
      case GachaRewardType.luckyWord:
        final baseInspiration = reward.rarity == GachaRarity.legendary ? 3 : 1;
        // 增加重复次数加成和50%额外加成
        final inspiration = ((baseInspiration + duplicateBonus) * 1.5).round();
        final currentInspiration = prefs.getInt('writing_inspiration') ?? 0;
        await prefs.setInt('writing_inspiration', currentInspiration + inspiration);
        // 额外给予5-10装饰点，增加重复次数加成
        final decorPoints = 5 + _random.nextInt(6) + duplicateBonus;
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        return '重复幸运语转化为 $inspiration 点写作灵感 + $decorPoints 装饰点（第${duplicateCount}次重复，含50%额外加成）';

      // 10. 日记提示重复 → 装饰点 + 灵感点
      case GachaRewardType.diaryPrompt:
        final decorPoints = 5 + _random.nextInt(6) + duplicateBonus; // 5-10 + 重复次数加成
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        // 重复获得额外给予1点灵感点
        await _addWritingInspiration(1);
        return '重复日记提示奖励：获得 $decorPoints 装饰点 + 1 灵感点（第${duplicateCount}次重复）';

      // 11. 标签创意重复 → 装饰点 + 灵感点
      case GachaRewardType.tagIdea:
        final decorPoints = 5 + _random.nextInt(6) + duplicateBonus; // 5-10 + 重复次数加成
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        // 重复获得额外给予1点灵感点
        await _addWritingInspiration(1);
        return '重复标签创意奖励：获得 $decorPoints 装饰点 + 1 灵感点（第${duplicateCount}次重复）';

      // 12. 照片挑战重复 → 装饰点 + 灵感点
      case GachaRewardType.photoChallenge:
        final decorPoints = 5 + _random.nextInt(6) + duplicateBonus; // 5-10 + 重复次数加成
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        // 重复获得额外给予1点灵感点
        await _addWritingInspiration(1);
        return '重复照片挑战奖励：获得 $decorPoints 装饰点 + 1 灵感点（第${duplicateCount}次重复）';

      // 13. 情感分析重复 → 装饰点
      case GachaRewardType.emotionAnalyze:
        final decorPoints = 5 + _random.nextInt(6) + duplicateBonus; // 5-10 + 重复次数加成
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        return '重复情感分析奖励：获得 $decorPoints 装饰点（第${duplicateCount}次重复）';

      // 14. 纪念日提示重复 → 装饰点
      case GachaRewardType.anniversaryHint:
        final decorPoints = 5 + _random.nextInt(6) + duplicateBonus; // 5-10 + 重复次数加成
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        return '重复纪念日提示奖励：获得 $decorPoints 装饰点（第${duplicateCount}次重复）';

      // 15. 主题色重复 → 转化为装饰点 + 贴纸碎片
      case GachaRewardType.theme:
        final baseDecorPoints = reward.rarity == GachaRarity.legendary ? 15 :
                           reward.rarity == GachaRarity.rare ? 10 :
                           reward.rarity == GachaRarity.uncommon ? 7 : 5;
        final baseStickerPoints = reward.rarity == GachaRarity.legendary ? 5 :
                              reward.rarity == GachaRarity.rare ? 3 :
                              reward.rarity == GachaRarity.uncommon ? 2 : 1;
        // 增加重复次数加成和50%额外加成
        final decorPoints = ((baseDecorPoints + duplicateBonus) * 1.5).round();
        final stickerPoints = ((baseStickerPoints + duplicateBonus) * 1.5).round();
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        final currentSticker = prefs.getInt('sticker_points') ?? 0;
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        await prefs.setInt('sticker_points', currentSticker + stickerPoints);
        return '重复主题色转化为 $decorPoints 装饰点 + $stickerPoints 贴纸碎片（第${duplicateCount}次重复，含50%额外加成）';

      // 16. 额外抽奖次数重复 → 转化为更多抽奖次数 + 经验值
      case GachaRewardType.extraDraw:
        final baseExtraDraws = reward.data != null ? int.tryParse(reward.data!) ?? 1 : 1;
        final baseExp = reward.rarity == GachaRarity.legendary ? 30 :
                   reward.rarity == GachaRarity.rare ? 20 :
                   reward.rarity == GachaRarity.uncommon ? 15 : 10;
        // 增加重复次数加成和50%额外加成
        final extraDraws = ((baseExtraDraws + duplicateBonus) * 1.5).round();
        final exp = ((baseExp + duplicateBonus * 2) * 1.5).round();
        final currentExp = prefs.getInt('user_exp') ?? 0;
        await prefs.setInt('user_exp', currentExp + exp);
        await addDraws(extraDraws);
        return '重复额外抽奖转化为 $extraDraws 次抽奖 + $exp 经验值（第${duplicateCount}次重复，含50%额外加成）';

      // 17. 贴图包重复 → 转化为大量贴纸碎片 + 装饰点
      case GachaRewardType.stickerPack:
        final baseStickerPoints = reward.rarity == GachaRarity.legendary ? 15 :
                              reward.rarity == GachaRarity.rare ? 10 :
                              reward.rarity == GachaRarity.uncommon ? 7 : 5;
        final baseDecorPoints = reward.rarity == GachaRarity.legendary ? 20 :
                           reward.rarity == GachaRarity.rare ? 15 :
                           reward.rarity == GachaRarity.uncommon ? 10 : 7;
        // 增加重复次数加成和50%额外加成
        final stickerPoints = ((baseStickerPoints + duplicateBonus) * 1.5).round();
        final decorPoints = ((baseDecorPoints + duplicateBonus) * 1.5).round();
        final currentSticker = prefs.getInt('sticker_points') ?? 0;
        final currentDecor = prefs.getInt('profile_decor_points') ?? 0;
        await prefs.setInt('sticker_points', currentSticker + stickerPoints);
        await prefs.setInt('profile_decor_points', currentDecor + decorPoints);
        return '重复贴图包转化为 $stickerPoints 贴纸碎片 + $decorPoints 装饰点（第${duplicateCount}次重复，含50%额外加成）';
    }
  }

  /// 辅助方法：通过名称给日记添加标签
  static Future<void> _applyTagToDiaryByName(int diaryId, String tagName) async {
    try {
      // 查找或创建标签
      final allTags = await DatabaseService.getAllTags();
      Tag? targetTag = allTags.firstWhere(
        (t) => t.name == tagName,
        orElse: () => Tag(id: -1, name: '', color: '#000000'),
      );
      
      // 如果标签不存在，创建它
      if (targetTag.id == -1) {
        final newTagId = await DatabaseService.insertTag(Tag(
          name: tagName,
          color: '#${Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        ));
        await DatabaseService.insertDiaryTag(diaryId, newTagId);
      } else if (targetTag.id != null) {
        await DatabaseService.insertDiaryTag(diaryId, targetTag.id!);
      }
    } catch (e) {
      debugPrint('应用标签失败: $e');
    }
  }

  static Future<void> _saveToHistory(GachaReward reward) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 使用更轻量的方式存储历史记录
      final record = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'rewardId': reward.id,
        'time': DateTime.now().toIso8601String(),
      };
      
      // 获取现有历史
      final historyKey = '${_historyKey}list';
      final history = prefs.getStringList(historyKey) ?? [];
      
      // 添加新记录到开头
      history.insert(0, jsonEncode(record));
      
      // 只保留最近20条记录
      if (history.length > 20) {
        history.removeRange(20, history.length);
      }
      
      await prefs.setStringList(historyKey, history);
    } catch (e) {
      print('保存历史记录失败: $e');
    }
  }

  static Future<void> _addToCollection(GachaReward reward) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_collectionKey${reward.id}';
    final count = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, count + 1);
  }

  static Future<int> getCollectionCount(String rewardId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_collectionKey$rewardId') ?? 0;
  }

  /// 获取所有收藏统计
  static Future<Map<String, int>> getAllCollectionStats() async {
    final prefs = await SharedPreferences.getInstance();
    final stats = <String, int>{};
    
    for (final reward in _allRewards) {
      final count = prefs.getInt('$_collectionKey${reward.id}') ?? 0;
      if (count > 0) {
        stats[reward.id] = count;
      }
    }
    
    return stats;
  }

  /// 获取历史记录
  static Future<List<GachaRecord>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 尝试新的存储格式
    final historyKey = '${_historyKey}list';
    final historyJson = prefs.getStringList(historyKey) ?? [];
    
    // 如果新格式为空，尝试旧格式迁移
    if (historyJson.isEmpty) {
      final oldHistory = prefs.getStringList(_historyKey) ?? [];
      if (oldHistory.isNotEmpty) {
        // 异步迁移到新的存储格式
        _migrateHistory(prefs, oldHistory);
      }
    }
    
    final records = <GachaRecord>[];
    for (final jsonStr in historyJson) {
      try {
        final data = jsonDecode(jsonStr);
        final rewardId = data['rewardId'] as String;
        final reward = _allRewards.firstWhere(
          (r) => r.id == rewardId,
          orElse: () => _allRewards.first,
        );
        records.add(GachaRecord(
          id: data['id'] as String,
          reward: reward,
          time: DateTime.parse(data['time'] as String),
        ));
      } catch (e) {
        print('解析历史记录失败: $e');
      }
    }
    
    return records;
  }
  
  /// 异步迁移历史记录
  static void _migrateHistory(SharedPreferences prefs, List<String> oldHistory) async {
    try {
      final historyKey = '${_historyKey}list';
      final newHistory = <String>[];
      
      for (final jsonStr in oldHistory.take(20)) {
        try {
          final data = jsonDecode(jsonStr);
          final newRecord = {
            'id': data['id'] as String,
            'rewardId': data['rewardId'] as String,
            'time': data['time'] as String,
          };
          newHistory.add(jsonEncode(newRecord));
        } catch (e) {
          // 跳过无效记录
        }
      }
      
      await prefs.setStringList(historyKey, newHistory);
    } catch (e) {
      print('历史记录迁移失败: $e');
    }
  }

  /// 清空历史记录
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  static Future<List<GachaReward>> getAllRewards() async {
    return List.unmodifiable(_allRewards);
  }

  static Color getRarityColor(GachaRarity rarity) {
    switch (rarity) {
      case GachaRarity.common:
        return const Color(0xFFB0BEC5);
      case GachaRarity.uncommon:
        return const Color(0xFF81C784);
      case GachaRarity.rare:
        return const Color(0xFF64B5F6);
      case GachaRarity.legendary:
        return const Color(0xFFFFD54F);
    }
  }

  static String getRarityName(GachaRarity rarity) {
    switch (rarity) {
      case GachaRarity.common:
        return '普通';
      case GachaRarity.uncommon:
        return '稀有';
      case GachaRarity.rare:
        return '史诗';
      case GachaRarity.legendary:
        return '传说';
    }
  }

  static Future<void> _addEmojiToCustomStickers(String emoji) async {
    await _addEmojisToCustomStickers([emoji]);
  }
  
  /// 批量添加贴纸
  static Future<void> _addEmojisToCustomStickers(List<String> emojis) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stickerListKey = 'custom_sticker_keys';
      var keys = prefs.getStringList(stickerListKey) ?? [];
      
      // 批量写入所有贴纸
      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < emojis.length; i++) {
        final stickerKey = 'custom_sticker_${now + i}_${emojis[i]}';
        await prefs.setString(stickerKey, jsonEncode({
          'emoji': emojis[i],
          'type': 'emoji',
          'createdAt': DateTime.now().toIso8601String(),
        }));
        keys.add(stickerKey);
      }
      
      // 只保留最近100个贴纸
      if (keys.length > 100) {
        final removedKeys = keys.sublist(0, keys.length - 100);
        keys = keys.sublist(keys.length - 100);
        // 异步清理旧贴纸，不阻塞主流程
        _cleanupOldStickers(prefs, removedKeys);
      }
      
      await prefs.setStringList(stickerListKey, keys);
    } catch (e) {
      print('批量添加贴纸失败: $e');
    }
  }
  
  /// 异步清理旧贴纸
  static void _cleanupOldStickers(SharedPreferences prefs, List<String> keys) async {
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  // ==================== 日记模板管理 ====================

  /// 获取所有日记模板奖励
  static List<GachaReward> getDiaryTemplateRewards() {
    return _allRewards.where((r) => r.type == GachaRewardType.diaryTemplate).toList();
  }

  /// 获取已解锁的日记模板（通过扭蛋获得的）
  static Future<List<GachaReward>> getUnlockedDiaryTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final templates = getDiaryTemplateRewards();
    final unlocked = <GachaReward>[];
    
    for (final template in templates) {
      final count = prefs.getInt('$_collectionKey${template.id}') ?? 0;
      if (count > 0) {
        unlocked.add(template);
      }
    }
    
    return unlocked;
  }

  /// 检查是否已解锁指定模板
  static Future<bool> isTemplateUnlocked(String templateId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt('$_collectionKey$templateId') ?? 0) > 0;
  }

  /// 获取已解锁的头像列表
  static Future<List<GachaReward>> getUnlockedAvatars() async {
    final prefs = await SharedPreferences.getInstance();
    final avatars = getAvatarRewards();
    final unlocked = <GachaReward>[];
    
    for (final avatar in avatars) {
      final count = prefs.getInt('$_collectionKey${avatar.id}') ?? 0;
      if (count > 0) {
        unlocked.add(avatar);
      }
    }
    
    return unlocked;
  }

  // ==================== 个性化头像描述生成 ====================

  /// 获取所有头像奖励
  static List<GachaReward> getAvatarRewards() {
    return _allRewards.where((r) => r.type == GachaRewardType.avatar).toList();
  }

  /// 根据用户数据生成个性化头像描述
  /// 
  /// 个性化头像的描述中包含占位符（如{days}），会被替换为实际用户数据
  static String generatePersonalizedDescription(
    GachaReward avatar, {
    required int totalDiaryDays,
    required int currentStreak,
    required int unlockedBadgeCount,
    required int totalPhotos,
    required int totalWords,
    required int uniqueMoodsUsed,
    required int uniqueTagsUsed,
    required int nightEntryCount,
    required int morningEntryCount,
    required int totalDiaries,
  }) {
    if (avatar.type != GachaRewardType.avatar) {
      return avatar.description;
    }
    
    String description = avatar.description;
    
    // 替换所有占位符
    description = description.replaceAll('{days}', totalDiaryDays.toString());
    description = description.replaceAll('{streak}', currentStreak.toString());
    description = description.replaceAll('{badges}', unlockedBadgeCount.toString());
    description = description.replaceAll('{photos}', totalPhotos.toString());
    description = description.replaceAll('{words}', totalWords.toString());
    description = description.replaceAll('{moods}', uniqueMoodsUsed.toString());
    description = description.replaceAll('{tags}', uniqueTagsUsed.toString());
    description = description.replaceAll('{nightEntries}', nightEntryCount.toString());
    description = description.replaceAll('{morningEntries}', morningEntryCount.toString());
    description = description.replaceAll('{totalDiaries}', totalDiaries.toString());
    
    return description;
  }

  /// 简化版：生成个性化描述（使用默认数据）
  static String getAvatarDisplayDescription(GachaReward avatar) {
    if (avatar.type != GachaRewardType.avatar) {
      return avatar.description;
    }

    // 如果是静态头像（没有data或data不是personalize_开头），直接返回
    if (avatar.data == null || !avatar.data!.startsWith('personalize_')) {
      return avatar.description;
    }

    // 返回带占位符的描述，UI层可以调用generatePersonalizedDescription替换
    return avatar.description;
  }

  /// 从扭蛋创建标签（三级标签系统）
  /// 如果标签已存在则不会重复创建
  static Future<void> _createTagFromGacha(String tagName, String emoji) async {
    try {
      // 获取三级标签系统
      final tagSystem = await TagSystemService.getTagSystem();
      
      // 在系统中查找是否已存在
      for (final category in tagSystem.categories) {
        for (final sub in category.subCategories) {
          for (final tag in sub.tags) {
            if (tag.name == tagName) {
              print('标签 "$tagName" 已存在，跳过创建');
              return;
            }
          }
        }
      }
      
      // 根据标签名称智能分类
      final path = _getTagCategoryPath(tagName);
      
      // 查找或创建分类
      var category = tagSystem.categories.firstWhere(
        (c) => c.name == path[0],
        orElse: () {
          final newCat = tagSystem.addCategory(
            path[0],
            emoji: _getCategoryEmoji(path[0]),
            color: Color(_getTagColorByName(tagName)),
          );
          return newCat;
        },
      );
      
      // 查找或创建子分类
      var subCategory = category.subCategories.firstWhere(
        (s) => s.name == path[1],
        orElse: () => category.addSubCategory(path[1], emoji: _getSubCategoryEmoji(path[1])),
      );
      
      // 创建标签
      subCategory.addTag(tagName, emoji: emoji);
      
      // 保存系统
      await TagSystemService.updateTagSystem(tagSystem);
      print('从扭蛋创建标签成功: $tagName $emoji (分类: ${path.join('/')})');
    } catch (e) {
      print('从扭蛋创建标签失败: $e');
    }
  }
  
  /// 获取标签分类路径 [一级, 二级]
  static List<String> _getTagCategoryPath(String tagName) {
    switch (tagName) {
      case '日常':
      case '生活':
        return ['生活', '日常'];
      case '工作':
      case '学习':
        return ['工作', '日常'];
      case '心情':
      case '情绪':
        return ['情感', '心情'];
      case '旅行':
      case '探索':
        return ['旅行', '目的地'];
      case '美食':
      case '吃货':
        return ['生活', '饮食'];
      case '家人':
      case '亲情':
        return ['情感', '家人'];
      case '梦想':
      case '目标':
        return ['工作', '成长'];
      case '感恩':
        return ['情感', '心情'];
      default:
        return ['其他', '未分类'];
    }
  }
  
  /// 获取分类emoji
  static String _getCategoryEmoji(String categoryName) {
    switch (categoryName) {
      case '生活': return '🏠';
      case '工作': return '💼';
      case '情感': return '❤️';
      case '旅行': return '✈️';
      case '其他': return '📦';
      default: return '🏷️';
    }
  }
  
  /// 获取子分类emoji
  static String _getSubCategoryEmoji(String subCategoryName) {
    switch (subCategoryName) {
      case '日常': return '📅';
      case '饮食': return '🍽️';
      case '健康': return '💪';
      case '心情': return '💭';
      case '家人': return '👨‍👩‍👧‍👦';
      case '朋友': return '👫';
      case '成长': return '📈';
      case '目的地': return '📍';
      case '未分类': return '📋';
      default: return '🏷️';
    }
  }

  /// 根据标签名称获取对应的颜色
  static int _getTagColorByName(String tagName) {
    switch (tagName) {
      case '日常':
        return 0xFF9E9E9E; // 灰色 - 日常生活
      case '工作':
        return 0xFF2196F3; // 蓝色 - 工作学习
      case '心情':
        return 0xFFFF9800; // 橙色 - 心情情绪
      case '旅行':
        return 0xFF4CAF50; // 绿色 - 旅行探索
      case '美食':
        return 0xFFE91E63; // 粉色 - 美食
      case '家人':
        return 0xFFF44336; // 红色 - 家人亲情
      case '梦想':
        return 0xFF9C27B0; // 紫色 - 梦想目标
      case '感恩':
        return 0xFFFFD700; // 金色 - 感恩
      default:
        return 0xFF607D8B; // 蓝灰色 - 默认
    }
  }

  // ==================== 系统联动资源管理 ====================

  /// 获取所有联动资源的当前数量
  static Future<Map<String, int>> getAllResourceCounts() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'sticker_points': prefs.getInt('sticker_points') ?? 0,        // 贴纸碎片
      'profile_decor_points': prefs.getInt('profile_decor_points') ?? 0,  // 装饰点
      'user_exp': prefs.getInt('user_exp') ?? 0,                    // 经验值
      'mood_energy': prefs.getInt('mood_energy') ?? 0,              // 心情能量
      'word_count_bonus': prefs.getInt('word_count_bonus') ?? 0,    // 字数加成
      'badge_progress_bonus': prefs.getInt('badge_progress_bonus') ?? 0,  // 徽章进度加成
      'writing_inspiration': prefs.getInt('writing_inspiration') ?? 0,    // 写作灵感
    };
  }

  /// 贴纸商店 - 用贴纸碎片兑换商店专属稀有贴图
  /// 注意：商店贴纸与扭蛋机贴纸完全独立，不会重复
  static final Map<String, Map<String, dynamic>> stickerShop = {
    'sticker_sparkles': {
      'name': '闪耀星星',
      'emoji': '✨',
      'cost': 5,
      'description': '灿烂的星光，点亮日记的每一页',
    },
    'sticker_clover': {
      'name': '幸运四叶草',
      'emoji': '🍀',
      'cost': 8,
      'description': '带来好运的神秘魔法',
    },
    'sticker_butterfly': {
      'name': '美丽蝴蝶',
      'emoji': '🦋',
      'cost': 12,
      'description': '自由翱翔，象征美好的变化',
    },
    'sticker_gift': {
      'name': '精致礼盒',
      'emoji': '🎁',
      'cost': 15,
      'description': '每一篇日记都是给未来的礼物',
    },
    'sticker_bamboo': {
      'name': '青竹',
      'emoji': '🎋',
      'cost': 18,
      'description': '节节高升，竹报平安',
    },
    'sticker_maple': {
      'name': '枫叶',
      'emoji': '🍁',
      'cost': 25,
      'description': '秋日的诗意，记录岁月的变迁',
    },
    'sticker_dream': {
      'name': '梦幻之翼',
      'emoji': '🧚',
      'cost': 30,
      'description': '展翅高飞，追逐梦想',
    },
    'sticker_galaxy': {
      'name': '银河星云',
      'emoji': '🌌',
      'cost': 40,
      'description': '宇宙的奢华，仅属于最珍贵的记忆',
    },
  };

  /// 兑换贴纸
  static Future<bool> exchangeSticker(String stickerId) async {
    final prefs = await SharedPreferences.getInstance();
    final item = stickerShop[stickerId];
    if (item == null) return false;
    
    final currentPoints = prefs.getInt('sticker_points') ?? 0;
    final cost = item['cost'] as int;
    
    if (currentPoints < cost) return false;
    
    // 扣除碎片
    await prefs.setInt('sticker_points', currentPoints - cost);
    // 添加贴图
    await _addEmojiToCustomStickers(item['emoji'] as String);
    return true;
  }

  /// 个人主页主题商店 - 用装饰点兑换
  static final Map<String, Map<String, dynamic>> profileThemeShop = {
    'theme_starry': {
      'name': '星空主题',
      'preview': '🌌',
      'cost': 15,
      'description': '深邃梦幻的星空背景，闪烁星星粒子效果',
      'colors': {
        'primary': 0xFF7C4DFF,      // 梦幻紫
        'background': 0xFF0D0D1F,   // 深蓝黑
        'card': 0xFFFFFFFF,         // 白色卡片（与自定义颜色一致）
        'light': 0xFF2D1B4E,        // 紫罗兰
        'dark': 0xFF5B7CFF,         // 星空蓝
        'textDark': 0xFF2D2D4A,     // 深紫黑（白色卡片上可见）
        'textMedium': 0xFF4A4A6A,   // 中紫灰
        'textLight': 0xFF7A7A9A,    // 浅紫灰
      },
    },
    'theme_sakura': {
      'name': '樱花主题',
      'preview': '🌸',
      'cost': 40,
      'description': '浪漫樱花飘落，粉色花瓣飞舞效果',
      'colors': {
        'primary': 0xFFF48FB1,      // 樱花粉
        'background': 0xFFFFF5F7,   // 极浅粉背景
        'card': 0xFFFFFFFF,         // 白色卡片
        'light': 0xFFFCE4EC,        // 淡粉高光
        'dark': 0xFFF8BBD0,         // 深粉
        'textDark': 0xFF880E4F,     // 深玫红文字
        'textMedium': 0xFFC2185B,   // 中玫红
        'textLight': 0xFFF06292,    // 浅玫红
        'iconColor': 0xFFF48FB1,    // 樱花粉图标
      },
    },
    'theme_ocean': {
      'name': '海洋主题',
      'preview': '🌊',
      'cost': 50,
      'description': '流动舒缓的蓝色波浪，宁静海洋氛围',
      'colors': {
        'primary': 0xFF42A5F5,      // 海洋蓝
        'background': 0xFFE3F2FD,   // 浅天蓝背景
        'card': 0xFFFFFFFF,         // 白色卡片
        'light': 0xFFBBDEFB,        // 天蓝高光
        'dark': 0xFF90CAF9,         // 深天蓝
        'textDark': 0xFF0D47A1,     // 深蓝文字
        'textMedium': 0xFF1565C0,   // 中蓝
        'textLight': 0xFF42A5F5,    // 浅蓝
        'iconColor': 0xFF42A5F5,    // 海洋蓝图标
      },
    },
    'theme_aurora': {
      'name': '极光主题',
      'preview': '🌈',
      'cost': 50,
      'description': '绚丽极光舞动，翠绿色光带流动效果',
      'colors': {
        'primary': 0xFF00C060,      // 青绿主色
        'background': 0xFF001810,   // 深绿黑背景
        'card': 0xFF003328,         // 深青绿卡片
        'light': 0xFF009060,        // 深青绿
        'dark': 0xFF00FFC0,         // 亮青绿
        'textDark': 0xFFE0F7FA,     // 浅青白文字
        'textMedium': 0xFF80DEEA,   // 中青
        'textLight': 0xFF4DD0E1,    // 浅青
        'iconColor': 0xFF00FFC0,    // 亮青绿图标
      },
    },
    'theme_golden': {
      'name': '黄金主题',
      'preview': '✨',
      'cost': 99,
      'description': '奢华金色尊贵体验，金色闪光粒子效果',
      'colors': {
        'primary': 0xFFFFD700,      // 黄金色
        'background': 0xFFFFF8E1,   // 极浅金
        'card': 0xFFFFECB3,         // 浅金卡片
        'light': 0xFFFFE082,        // 中金黄
        'dark': 0xFFFFB300,         // 深金黄
        'textDark': 0xFF5D4037,     // 深棕
        'textMedium': 0xFF795548,   // 中棕
        'textLight': 0xFFA1887F,    // 浅棕
      },
    },
  };

  /// 获取主题配色方案
  static Map<String, dynamic>? getThemeColors(String themeId) {
    final theme = profileThemeShop[themeId];
    return theme?['colors'] as Map<String, dynamic>?;
  }

  /// 兑换个人主页主题
  static Future<bool> exchangeProfileTheme(String themeId) async {
    final prefs = await SharedPreferences.getInstance();
    final item = profileThemeShop[themeId];
    if (item == null) return false;
    
    final currentPoints = prefs.getInt('profile_decor_points') ?? 0;
    final cost = item['cost'] as int;
    
    if (currentPoints < cost) return false;
    
    // 扣除装饰点
    await prefs.setInt('profile_decor_points', currentPoints - cost);
    // 解锁主题（保存到已解锁列表）
    final unlockedThemes = prefs.getStringList('unlocked_themes') ?? [];
    if (!unlockedThemes.contains(themeId)) {
      unlockedThemes.add(themeId);
      await prefs.setStringList('unlocked_themes', unlockedThemes);
    }
    // 设置为当前主题
    await prefs.setString('current_profile_theme', themeId);
    return true;
  }

  /// 获取用户等级（基于经验值）
  static Future<Map<String, dynamic>> getUserLevelInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final exp = prefs.getInt('user_exp') ?? 0;
    
    // 等级计算：每100经验升1级
    final level = (exp / 100).floor() + 1;
    final currentLevelExp = exp % 100;
    final nextLevelNeed = 100 - currentLevelExp;
    
    // 等级称号
    final titles = {
      1: '日记新手',
      5: '记录爱好者',
      10: '日记达人',
      20: '记录大师',
      30: '日记传奇',
      50: '记录之神',
    };
    
    String title = '日记新手';
    for (var entry in titles.entries) {
      if (level >= entry.key) {
        title = entry.value;
      }
    }
    
    return {
      'level': level,
      'total_exp': exp,
      'current_level_exp': currentLevelExp,
      'next_level_need': nextLevelNeed,
      'title': title,
      'progress': currentLevelExp / 100,
    };
  }

  /// 使用心情能量（为日记添加双心情）
  static Future<bool> useMoodEnergy() async {
    final prefs = await SharedPreferences.getInstance();
    final currentEnergy = prefs.getInt('mood_energy') ?? 0;
    if (currentEnergy < 1) return false;
    await prefs.setInt('mood_energy', currentEnergy - 1);
    return true;
  }

  /// 添加写作灵感点数
  static Future<void> _addWritingInspiration(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final currentInspiration = prefs.getInt('writing_inspiration') ?? 0;
    await prefs.setInt('writing_inspiration', currentInspiration + amount);
  }

  /// 使用写作灵感（在写日记时获得深度提示）
  /// 
  /// [upcomingAnniversaries] - 即将到来的纪念日/倒数日列表，用于生成相关联动提示
  static Future<String?> useWritingInspiration({
    List<Map<String, dynamic>>? upcomingAnniversaries,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentInspiration = prefs.getInt('writing_inspiration') ?? 0;
    if (currentInspiration < 1) return null;
    await prefs.setInt('writing_inspiration', currentInspiration - 1);
    
    // 使用传入的纪念日数据（如果有）
    final anniversaries = upcomingAnniversaries ?? [];
    
    // 构建多维度写作提示库
    final prompts = <String>[];
    
    // ===== 回忆类：今天发生的事 =====
    prompts.addAll([
      '今天哪个瞬间让你感到生活很美好？描述那个画面。',
      '今天遇到的一件小事，之前从未注意过，今天却觉得很有趣。',
      '今天说了哪些话，现在回想起来觉得可以说得更好？或者说得很好？',
      '今天的某个瞬间，你突然懂了什么？',
      '今天的你，和昨天的你，有什么不同？',
      '今天哪个人的一个举动，让你印象深刻？',
      '今天的日光下，你想永远记住的一幕是什么？',
      '如果今天是一部电影，最让你动容的镜头是哪一帧？',
    ]);
    
    // ===== 未来规划类：想做的事 =====
    prompts.addAll([
      '最近有什么事情一直在脑海里，你想要去实现它？',
      '如果明天早上醒来，你可以做一件完全为自己的事，你会做什么？',
      '今年还剩下的时间里，有什么你一定要完成的事情？',
      '如果可以学一项新技能，你想学什么？为什么？',
      '下个月这个时候，你希望自己在哪里？做什么？',
      '写下三件你想在未来一年内完成的事，不管多小都可以。',
      '如果有一天完全不用工作，你想怎么度过那一天？',
      '你心中有一个一直想去但还没去的地方吗？描述一下那里。',
    ]);
    
    // ===== 感恩与珍惜类 =====
    prompts.addAll([
      '今天，有谁让你感到被爱着？或者你爱着谁？',
      '写下三个今天值得感谢的小事，即使是很微小的事。',
      '有什么人或事，你已经习以为常，但其实应该珍惜？',
      '如果可以给一个很久没联系的人发消息，你会想对谁说什么？',
      '想起一个对你很重要但没来得及感谢的人，写下你想对TA说的话。',
      '今天的哪个瞬间，让你觉得"还好有这个人在"？',
      '如果明天是世界末日，今天晚上你想和谁度过？做什么？',
      '写下一件你曾经觉得理所当然，现在却十分珍惜的事情。',
    ]);
    
    // ===== 深度反思类 =====
    prompts.addAll([
      '最近有什么事让你夜不能寐？你在担心什么？',
      '如果可以改变自己的一个习惯，你想改变什么？为什么？',
      '什么是你最近才意识到的关于自己的真相？',
      '如果可以给五年后的自己写一句话，你会写什么？',
      '什么事情让你觉得自己真实地活着，而不只是在过日子？',
      '最近有什么情绪一直困扰着你？写下来，也许会清晰一些。',
      '如果可以重新选择，你会怎么过今年的某一天？',
      '什么是你现在最想放下却放不下的东西？写下来，然后告诉自己为什么。',
    ]);
    
    // ===== 人际关系类 =====
    prompts.addAll([
      '最近和某个人的一段对话，让你印象深刻。那是什么？',
      '写下一个你很久没见但很想念的人，以及你想对TA说的话。',
      '有没有一个人，你很想谢谢TA，但一直没说出口？',
      '今天有没有让某个人开心？或者你被某个人让开心？',
      '如果可以邀请任意三个人吃饭（活着或已故），你会选谁？聊什么？',
      '最近有没有和家人发生什么温馨的事？或者你希望发生什么？',
      '写下一个你想要更亲近的人，以及你打算怎么做。',
      '今天有没有遇到一个陌生人，给了你惊喜或感动？',
    ]);
    
    // ===== 自我成长类 =====
    prompts.addAll([
      '这一周，你在哪方面有了进步，即使只是很小的改变？',
      '什么事情让你觉得自己比之前更强大了？',
      '写下一个你今天克服的困难，或者坚持做了的一件事。',
      '最近有什么事让你觉得自己成长了？',
      '如果可以对今天的自己说一声辛苦了，你想夸自己什么？',
      '什么是你最近学到的最重要的一课？关于生活，关于自己。',
      '有没有一件你之前觉得很难，现在却觉得还好的事情？',
      '写下三个你引以为豪的自己的特质或成就。',
    ]);
    
    // ===== 生活仪式感类 =====
    prompts.addAll([
      '今天的早晨，你是以什么心情开始的？',
      '今天的夜晚，你希望以什么心情结束？',
      '今天吃的什么东西，让你觉得生活很美好？',
      '今天看到的最美的景色是什么？在哪里？',
      '今天闻到的最好闻的气味是什么？它让你想起了什么？',
      '如果今天可以重来，你想要更好地体验什么？',
      '写下今天最让你感动的一个细节。',
      '今天的哪个时刻，你觉得"这就是生活"？',
    ]);
    
    // ===== 纪念日/倒数日联动 =====
    if (anniversaries.isNotEmpty) {
      // 添加与即将到来的纪念日相关的提示
      final nextAnniversary = anniversaries.first;
      prompts.addAll([
        '即将到来的${nextAnniversary['title']}，你对这个日子有什么期待？',
        '距离${nextAnniversary['title']}还有${nextAnniversary['days']}天，你准备怎么度过？',
        '回顾上一个${nextAnniversary['title']}，那时候的你在哪里？在做什么？',
        '如果可以给${nextAnniversary['title']}的自己写信，你会说什么？',
      ]);
    }
    
    // 随机选择一个提示
    return prompts[Random().nextInt(prompts.length)];
  }
  
  /// 获取即将到来的纪念日/倒数日
  /// 获取当前资源状态摘要（用于展示）
  static Future<Map<String, dynamic>> getResourceSummary() async {
    final resources = await getAllResourceCounts();
    final levelInfo = await getUserLevelInfo();
    
    return {
      'resources': resources,
      'level': levelInfo,
      'can_exchange_sticker': (resources['sticker_points'] ?? 0) >= 5,
      'can_exchange_theme': (resources['profile_decor_points'] ?? 0) >= 30,
      'has_mood_energy': (resources['mood_energy'] ?? 0) > 0,
      'has_inspiration': (resources['writing_inspiration'] ?? 0) > 0,
      'has_word_bonus': (resources['word_count_bonus'] ?? 0) > 0,
      'has_badge_bonus': (resources['badge_progress_bonus'] ?? 0) > 0,
    };
  }

}
