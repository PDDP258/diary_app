import 'dart:math';
import 'package:flutter/material.dart';

/// 三级标签系统
/// 
/// 用户可完全自定义，但提供三级结构框架
/// 一级：分类（Category） 如：生活、工作
/// 二级：子分类（SubCategory） 如：饮食、健康
/// 三级：标签（Tag） 如：早餐、午餐

/// 三级标签
class TagLevel3 {
  String id;
  String name;
  String? emoji;
  int usageCount;
  DateTime createdAt;
  DateTime? lastUsedAt;
  
  TagLevel3({
    required this.id,
    required this.name,
    this.emoji,
    this.usageCount = 0,
    DateTime? createdAt,
    this.lastUsedAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'usageCount': usageCount,
    'createdAt': createdAt.toIso8601String(),
    'lastUsedAt': lastUsedAt?.toIso8601String(),
  };
  
  factory TagLevel3.fromJson(Map<String, dynamic> json) => TagLevel3(
    id: json['id'],
    name: json['name'],
    emoji: json['emoji'],
    usageCount: json['usageCount'] ?? 0,
    createdAt: DateTime.parse(json['createdAt']),
    lastUsedAt: json['lastUsedAt'] != null 
        ? DateTime.parse(json['lastUsedAt'])
        : null,
  );
  
  void incrementUsage() {
    usageCount++;
    lastUsedAt = DateTime.now();
  }
  
  TagLevel3 copyWith({
    String? id,
    String? name,
    String? emoji,
    int? usageCount,
    DateTime? lastUsedAt,
  }) => TagLevel3(
    id: id ?? this.id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    usageCount: usageCount ?? this.usageCount,
    createdAt: createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
}

/// 二级子分类
class TagLevel2 {
  String id;
  String name;
  String? emoji;
  List<TagLevel3> tags;
  int sortOrder;
  DateTime createdAt;
  
  TagLevel2({
    required this.id,
    required this.name,
    this.emoji,
    List<TagLevel3>? tags,
    this.sortOrder = 0,
    DateTime? createdAt,
  }) : tags = tags ?? [],
       createdAt = createdAt ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'tags': tags.map((t) => t.toJson()).toList(),
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory TagLevel2.fromJson(Map<String, dynamic> json) => TagLevel2(
    id: json['id'],
    name: json['name'],
    emoji: json['emoji'],
    tags: (json['tags'] as List).map((t) => TagLevel3.fromJson(t)).toList(),
    sortOrder: json['sortOrder'] ?? 0,
    createdAt: DateTime.parse(json['createdAt']),
  );
  
  /// 添加标签
  TagLevel3 addTag(String name, {String? emoji}) {
    final tag = TagLevel3(
      id: 'tag_${DateTime.now().millisecondsSinceEpoch}_${_randomString(4)}',
      name: name,
      emoji: emoji,
    );
    tags.add(tag);
    return tag;
  }
  
  /// 删除标签
  void removeTag(String tagId) {
    tags.removeWhere((t) => t.id == tagId);
  }
  
  /// 获取总使用次数
  int get totalUsage => tags.fold(0, (sum, t) => sum + t.usageCount);
  
  TagLevel2 copyWith({
    String? id,
    String? name,
    String? emoji,
    List<TagLevel3>? tags,
    int? sortOrder,
  }) => TagLevel2(
    id: id ?? this.id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    tags: tags ?? this.tags,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
  );
}

/// 一级分类
class TagLevel1 {
  String id;
  String name;
  String? emoji;
  Color color;
  List<TagLevel2> subCategories;
  int sortOrder;
  bool isExpanded;
  DateTime createdAt;
  
  TagLevel1({
    required this.id,
    required this.name,
    this.emoji,
    required this.color,
    List<TagLevel2>? subCategories,
    this.sortOrder = 0,
    this.isExpanded = false,
    DateTime? createdAt,
  }) : subCategories = subCategories ?? [],
       createdAt = createdAt ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'color': color.toARGB32(),
    'subCategories': subCategories.map((s) => s.toJson()).toList(),
    'sortOrder': sortOrder,
    'isExpanded': isExpanded,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory TagLevel1.fromJson(Map<String, dynamic> json) => TagLevel1(
    id: json['id'],
    name: json['name'],
    emoji: json['emoji'],
    color: Color(json['color']),
    subCategories: (json['subCategories'] as List)
        .map((s) => TagLevel2.fromJson(s))
        .toList(),
    sortOrder: json['sortOrder'] ?? 0,
    isExpanded: json['isExpanded'] ?? false,
    createdAt: DateTime.parse(json['createdAt']),
  );
  
  /// 添加子分类
  TagLevel2 addSubCategory(String name, {String? emoji}) {
    final sub = TagLevel2(
      id: 'sub_${DateTime.now().millisecondsSinceEpoch}_${_randomString(4)}',
      name: name,
      emoji: emoji,
    );
    subCategories.add(sub);
    return sub;
  }
  
  /// 删除子分类
  void removeSubCategory(String subId) {
    subCategories.removeWhere((s) => s.id == subId);
  }
  
  /// 获取总标签数
  int get totalTags => subCategories.fold(0, (sum, s) => sum + s.tags.length);
  
  /// 获取总使用次数
  int get totalUsage => subCategories.fold(0, (sum, s) => sum + s.totalUsage);
  
  TagLevel1 copyWith({
    String? id,
    String? name,
    String? emoji,
    Color? color,
    List<TagLevel2>? subCategories,
    int? sortOrder,
    bool? isExpanded,
  }) => TagLevel1(
    id: id ?? this.id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    color: color ?? this.color,
    subCategories: subCategories ?? this.subCategories,
    sortOrder: sortOrder ?? this.sortOrder,
    isExpanded: isExpanded ?? this.isExpanded,
    createdAt: createdAt,
  );
}

/// 标签系统
class TagSystem {
  List<TagLevel1> categories;
  DateTime updatedAt;
  String version;
  
  TagSystem({
    List<TagLevel1>? categories,
    DateTime? updatedAt,
    this.version = '3.0',
  }) : categories = categories ?? [],
       updatedAt = updatedAt ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'categories': categories.map((c) => c.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'version': version,
  };
  
  factory TagSystem.fromJson(Map<String, dynamic> json) => TagSystem(
    categories: (json['categories'] as List)
        .map((c) => TagLevel1.fromJson(c))
        .toList(),
    updatedAt: DateTime.parse(json['updatedAt']),
    version: json['version'] ?? '3.0',
  );
  
  /// 添加分类
  TagLevel1 addCategory(String name, {String? emoji, Color? color}) {
    final category = TagLevel1(
      id: 'cat_${DateTime.now().millisecondsSinceEpoch}_${_randomString(4)}',
      name: name,
      emoji: emoji,
      color: color ?? Colors.blue,
    );
    categories.add(category);
    updatedAt = DateTime.now();
    return category;
  }
  
  /// 删除分类
  void removeCategory(String categoryId) {
    categories.removeWhere((c) => c.id == categoryId);
    updatedAt = DateTime.now();
  }
  
  /// 通过ID查找标签
  TagLevel3? findTagById(String tagId) {
    for (final cat in categories) {
      for (final sub in cat.subCategories) {
        for (final tag in sub.tags) {
          if (tag.id == tagId) return tag;
        }
      }
    }
    return null;
  }
  
  /// 通过标签ID查找所属分类
  TagLevel1? findCategoryByTagId(String tagId) {
    for (final cat in categories) {
      for (final sub in cat.subCategories) {
        for (final tag in sub.tags) {
          if (tag.id == tagId) return cat;
        }
      }
    }
    return null;
  }
  
  /// 搜索标签
  List<TagSearchResult> searchTags(String query) {
    final results = <TagSearchResult>[];
    final lowerQuery = query.toLowerCase();
    
    for (final cat in categories) {
      for (final sub in cat.subCategories) {
        for (final tag in sub.tags) {
          if (tag.name.toLowerCase().contains(lowerQuery)) {
            results.add(TagSearchResult(
              tag: tag,
              category: cat,
              subCategory: sub,
            ));
          }
        }
      }
    }
    
    // 按使用次数排序
    results.sort((a, b) => b.tag.usageCount.compareTo(a.tag.usageCount));
    return results;
  }
  
  /// 获取所有标签（扁平化）
  List<TagLevel3> getAllTags() {
    final tags = <TagLevel3>[];
    for (final cat in categories) {
      for (final sub in cat.subCategories) {
        tags.addAll(sub.tags);
      }
    }
    return tags;
  }
  
  /// 创建默认标签系统
  factory TagSystem.createDefault() {
    final system = TagSystem();
    
    // 1. 生活分类
    final life = system.addCategory('生活', emoji: '🏠', color: Colors.green);
    
    // 饮食子分类
    final food = life.addSubCategory('饮食', emoji: '🍔');
    food.addTag('早餐', emoji: '🍳');
    food.addTag('午餐', emoji: '🍱');
    food.addTag('晚餐', emoji: '🍽️');
    food.addTag('美食', emoji: '😋');
    food.addTag('做饭', emoji: '👨‍🍳');
    
    // 健康子分类
    final health = life.addSubCategory('健康', emoji: '💪');
    health.addTag('运动', emoji: '🏃');
    health.addTag('健身', emoji: '🏋️');
    health.addTag('睡眠', emoji: '😴');
    health.addTag('体检', emoji: '🏥');
    
    // 日常子分类
    final daily = life.addSubCategory('日常', emoji: '📅');
    daily.addTag('购物', emoji: '🛒');
    daily.addTag('打扫', emoji: '🧹');
    daily.addTag('理财', emoji: '💰');
    
    // 2. 工作分类
    final work = system.addCategory('工作', emoji: '💼', color: Colors.blue);
    
    // 日常工作子分类
    final workDaily = work.addSubCategory('日常', emoji: '📊');
    workDaily.addTag('上班', emoji: '💻');
    workDaily.addTag('加班', emoji: '🌙');
    workDaily.addTag('会议', emoji: '👥');
    workDaily.addTag('出差', emoji: '✈️');
    
    // 成长子分类
    final growth = work.addSubCategory('成长', emoji: '📈');
    growth.addTag('学习', emoji: '📚');
    growth.addTag('技能', emoji: '🎯');
    growth.addTag('证书', emoji: '🏆');
    
    // 3. 情感分类
    final emotion = system.addCategory('情感', emoji: '❤️', color: Colors.pink);
    
    // 家人子分类
    final family = emotion.addSubCategory('家人', emoji: '👨‍👩‍👧');
    family.addTag('父母', emoji: '👴');
    family.addTag('孩子', emoji: '👶');
    family.addTag('家庭聚会', emoji: '🎉');
    
    // 朋友子分类
    final friends = emotion.addSubCategory('朋友', emoji: '👫');
    friends.addTag('聚会', emoji: '🎊');
    friends.addTag('聊天', emoji: '💬');
    friends.addTag('互助', emoji: '🤝');
    
    // 心情子分类
    final mood = emotion.addSubCategory('心情', emoji: '🌈');
    mood.addTag('开心', emoji: '😊');
    mood.addTag('难过', emoji: '😢');
    mood.addTag('感恩', emoji: '🙏');
    mood.addTag('期待', emoji: '✨');
    
    // 4. 娱乐分类
    final entertainment = system.addCategory('娱乐', emoji: '🎮', color: Colors.purple);
    
    // 影视子分类
    final movie = entertainment.addSubCategory('影视', emoji: '🎬');
    movie.addTag('电影', emoji: '🎞️');
    movie.addTag('电视剧', emoji: '📺');
    movie.addTag('综艺', emoji: '🎪');
    
    // 游戏子分类
    final game = entertainment.addSubCategory('游戏', emoji: '🎮');
    game.addTag('手游', emoji: '📱');
    game.addTag('网游', emoji: '💻');
    game.addTag('桌游', emoji: '🎲');
    
    // 阅读子分类
    final reading = entertainment.addSubCategory('阅读', emoji: '📖');
    reading.addTag('书籍', emoji: '📚');
    reading.addTag('小说', emoji: '📕');
    reading.addTag('漫画', emoji: '🎨');
    
    // 5. 旅行分类
    final travel = system.addCategory('旅行', emoji: '✈️', color: Colors.orange);
    
    // 目的地子分类
    final destination = travel.addSubCategory('目的地', emoji: '🗺️');
    destination.addTag('国内游', emoji: '🇨🇳');
    destination.addTag('出境游', emoji: '🌍');
    destination.addTag('周边游', emoji: '🚗');
    
    // 行程子分类
    final itinerary = travel.addSubCategory('行程', emoji: '📋');
    itinerary.addTag('计划', emoji: '📝');
    itinerary.addTag('回顾', emoji: '📸');
    itinerary.addTag('攻略', emoji: '🗺️');
    
    return system;
  }
}

/// 标签搜索结果
class TagSearchResult {
  final TagLevel3 tag;
  final TagLevel1 category;
  final TagLevel2 subCategory;
  
  TagSearchResult({
    required this.tag,
    required this.category,
    required this.subCategory,
  });
}

/// 生成随机字符串
String _randomString(int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}
