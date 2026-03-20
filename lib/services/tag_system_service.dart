import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tag_system.dart';
import 'database_service.dart';

/// 三级标签系统服务
class TagSystemService {
  static const String _tagSystemKey = 'tag_system_v3';
  static const String _legacyTagsKey = 'diary_tags';
  static TagSystem? _cache;
  
  /// 获取标签系统
  static Future<TagSystem> getTagSystem() async {
    // 使用内存缓存
    if (_cache != null) return _cache!;
    
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_tagSystemKey);
    
    if (jsonStr != null) {
      try {
        _cache = TagSystem.fromJson(jsonDecode(jsonStr));
        return _cache!;
      } catch (e) {
        debugPrint('解析标签系统失败: $e');
      }
    }
    
    // 检查是否有旧版标签需要迁移
    final legacyTags = prefs.getStringList(_legacyTagsKey);
    if (legacyTags != null && legacyTags.isNotEmpty) {
      _cache = await _migrateFromLegacy(legacyTags);
      await _saveTagSystem(_cache!);
      return _cache!;
    }
    
    // 创建默认系统
    _cache = TagSystem.createDefault();
    await _saveTagSystem(_cache!);
    return _cache!;
  }
  
  /// 保存标签系统
  static Future<void> _saveTagSystem(TagSystem system) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tagSystemKey, jsonEncode(system.toJson()));
    _cache = system;
  }
  
  /// 从旧版标签迁移
  static Future<TagSystem> _migrateFromLegacy(List<String> legacyTags) async {
    final system = TagSystem.createDefault();
    
    // 智能映射旧标签到新分类
    for (final tagName in legacyTags) {
      _migrateTag(system, tagName);
    }
    
    return system;
  }
  
  /// 迁移单个标签
  static void _migrateTag(TagSystem system, String tagName) {
    // 映射规则
    final mapping = {
      // 饮食类
      '早餐': ['生活', '饮食', '早餐'],
      '午餐': ['生活', '饮食', '午餐'],
      '晚餐': ['生活', '饮食', '晚餐'],
      '美食': ['生活', '饮食', '美食'],
      '做饭': ['生活', '饮食', '美食'],
      // 健康类
      '运动': ['生活', '健康', '运动'],
      '健身': ['生活', '健康', '运动'],
      '跑步': ['生活', '健康', '运动'],
      '睡眠': ['生活', '健康', '睡眠'],
      // 工作类
      '工作': ['工作', '日常', '上班'],
      '上班': ['工作', '日常', '上班'],
      '加班': ['工作', '日常', '加班'],
      '学习': ['工作', '成长', '学习'],
      '会议': ['工作', '日常', '会议'],
      '出差': ['工作', '日常', '出差'],
      // 情感类
      '家人': ['情感', '家人', '父母'],
      '朋友': ['情感', '朋友', '聚会'],
      '聚会': ['情感', '朋友', '聚会'],
      '开心': ['情感', '心情', '开心'],
      '难过': ['情感', '心情', '难过'],
      '感恩': ['情感', '心情', '感恩'],
      // 娱乐类
      '电影': ['娱乐', '影视', '电影'],
      '电视剧': ['娱乐', '影视', '电视剧'],
      '游戏': ['娱乐', '游戏', '手游'],
      '阅读': ['娱乐', '阅读', '书籍'],
      '书籍': ['娱乐', '阅读', '书籍'],
      // 旅行类
      '旅行': ['旅行', '目的地', '国内游'],
      '旅游': ['旅行', '目的地', '国内游'],
      '出差': ['工作', '日常', '出差'],
    };
    
    final path = mapping[tagName];
    if (path != null) {
      // 找到对应分类
      final category = system.categories.firstWhere(
        (c) => c.name == path[0],
        orElse: () => system.categories.first,
      );
      
      final subCategory = category.subCategories.firstWhere(
        (s) => s.name == path[1],
        orElse: () => category.subCategories.first,
      );
      
      // 检查是否已存在
      final existingTag = subCategory.tags.firstWhere(
        (t) => t.name == path[2],
        orElse: () => subCategory.addTag(path[2]),
      );
      
      // 增加使用次数
      existingTag.incrementUsage();
    } else {
      // 未找到映射，放入"其他"分类
      var otherCategory = system.categories.firstWhere(
        (c) => c.name == '其他',
        orElse: () {
          final newCat = system.addCategory('其他', emoji: '📦', color: Colors.grey);
          final newSub = newCat.addSubCategory('未分类', emoji: '📋');
          return newCat;
        },
      );
      
      final otherSub = otherCategory.subCategories.firstWhere(
        (s) => s.name == '未分类',
        orElse: () => otherCategory.addSubCategory('未分类', emoji: '📋'),
      );
      
      final tag = otherSub.addTag(tagName);
      tag.incrementUsage();
    }
  }
  
  /// 更新标签系统
  static Future<void> updateTagSystem(TagSystem system) async {
    await _saveTagSystem(system);
  }
  
  /// 重置为默认
  static Future<TagSystem> resetToDefault() async {
    final system = TagSystem.createDefault();
    await _saveTagSystem(system);
    return system;
  }
  
  /// 导出数据
  static Future<String> exportData() async {
    final system = await getTagSystem();
    return jsonEncode({
      'version': '3.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'data': system.toJson(),
    });
  }
  
  /// 导入数据
  static Future<TagSystem> importData(String jsonStr) async {
    final data = jsonDecode(jsonStr);
    final system = TagSystem.fromJson(data['data']);
    await _saveTagSystem(system);
    return system;
  }
  
  /// 清空缓存
  static void clearCache() {
    _cache = null;
  }
  
  /// 记录标签使用
  static Future<void> recordTagUsage(String tagId) async {
    final system = await getTagSystem();
    final tag = system.findTagById(tagId);
    if (tag != null) {
      tag.incrementUsage();
      await _saveTagSystem(system);
    }
  }
  
  /// 增加标签使用次数（简化的公共方法）
  static Future<void> incrementTagUsage(String tagId) async {
    await recordTagUsage(tagId);
  }
  
  /// 获取日记的标签ID列表
  static Future<List<String>> getDiaryTagIds(int diaryId) async {
    return await DatabaseService.getDiaryTagIdsV3(diaryId);
  }
  
  /// 保存日记的标签关联
  static Future<void> saveDiaryTags(int diaryId, List<String> tagIds) async {
    await DatabaseService.deleteDiaryTagsV3(diaryId);
    await DatabaseService.insertDiaryTagsV3(diaryId, tagIds);
  }
  
  // ==================== 标签管理公共方法 ====================
  
  /// 添加分类
  static Future<TagLevel1> addCategory({
    required String name,
    String? emoji,
    required Color color,
  }) async {
    final system = await getTagSystem();
    final category = system.addCategory(name, emoji: emoji, color: color);
    await _saveTagSystem(system);
    return category;
  }
  
  /// 更新分类
  static Future<void> updateCategory(TagLevel1 category) async {
    final system = await getTagSystem();
    final index = system.categories.indexWhere((c) => c.id == category.id);
    if (index != -1) {
      system.categories[index] = category;
      await _saveTagSystem(system);
    }
  }
  
  /// 删除分类
  static Future<void> deleteCategory(String categoryId) async {
    final system = await getTagSystem();
    system.removeCategory(categoryId);
    await _saveTagSystem(system);
  }
  
  /// 添加子分类
  static Future<TagLevel2> addSubCategory({
    required String categoryId,
    required String name,
    String? emoji,
  }) async {
    final system = await getTagSystem();
    final category = system.categories.firstWhere((c) => c.id == categoryId);
    final subCategory = category.addSubCategory(name, emoji: emoji);
    await _saveTagSystem(system);
    return subCategory;
  }
  
  /// 更新子分类
  static Future<void> updateSubCategory({
    required String categoryId,
    required TagLevel2 subCategory,
  }) async {
    final system = await getTagSystem();
    final category = system.categories.firstWhere((c) => c.id == categoryId);
    final index = category.subCategories.indexWhere((s) => s.id == subCategory.id);
    if (index != -1) {
      category.subCategories[index] = subCategory;
      await _saveTagSystem(system);
    }
  }
  
  /// 添加标签
  static Future<TagLevel3> addTag({
    required String categoryId,
    required String subCategoryId,
    required String name,
    String? emoji,
  }) async {
    final system = await getTagSystem();
    final category = system.categories.firstWhere((c) => c.id == categoryId);
    final subCategory = category.subCategories.firstWhere((s) => s.id == subCategoryId);
    final tag = subCategory.addTag(name, emoji: emoji);
    await _saveTagSystem(system);
    return tag;
  }
  
  /// 更新标签
  static Future<void> updateTag({
    required String categoryId,
    required String subCategoryId,
    required TagLevel3 tag,
  }) async {
    final system = await getTagSystem();
    final category = system.categories.firstWhere((c) => c.id == categoryId);
    final subCategory = category.subCategories.firstWhere((s) => s.id == subCategoryId);
    final index = subCategory.tags.indexWhere((t) => t.id == tag.id);
    if (index != -1) {
      subCategory.tags[index] = tag;
      await _saveTagSystem(system);
    }
  }
  
  /// 删除标签
  static Future<void> deleteTag({
    required String categoryId,
    required String subCategoryId,
    required String tagId,
  }) async {
    final system = await getTagSystem();
    final category = system.categories.firstWhere((c) => c.id == categoryId);
    final subCategory = category.subCategories.firstWhere((s) => s.id == subCategoryId);
    subCategory.removeTag(tagId);
    await _saveTagSystem(system);
  }
  
  /// 保存标签系统（公共方法）
  static Future<void> saveTagSystem(TagSystem system) async {
    await _saveTagSystem(system);
  }
}
