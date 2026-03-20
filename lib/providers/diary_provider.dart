import 'package:flutter/foundation.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import '../services/database_service.dart';
import '../services/image_cache_service.dart';
import '../services/tag_system_service.dart';

/// 日记状态管理 - 优化版本
/// 
/// 性能优化：
/// 1. 分页加载日记，避免一次性加载所有数据
/// 2. 异步图片预加载，不阻塞主线程
/// 3. 延迟加载非关键数据
class DiaryProvider extends ChangeNotifier {
  // 已加载的日记列表
  List<Diary> _diaries = [];
  List<Mood> _moods = [];
  List<Tag> _tags = [];
  bool _isLoading = false;
  String? _error;
  
  // 分页加载状态
  int _currentPage = 0;
  static const int _pageSize = 20;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;

  // Getters
  List<Diary> get diaries => _diaries;
  List<Mood> get moods => _moods;
  List<Tag> get tags => _tags;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreData => _hasMoreData;
  String? get error => _error;

  // 获取某一天的日记
  List<Diary> getDiariesByDate(String date) {
    return _diaries.where((d) => d.date == date).toList();
  }

  // 获取有日记的所有日期
  Set<String> get datesWithDiaries {
    return _diaries.map((d) => d.date).toSet();
  }

  // 获取收藏日记
  List<Diary> get favoriteDiaries {
    return _diaries.where((d) => d.isFavorite).toList();
  }

  // 获取总字数
  int get totalWordCount {
    return _diaries.fold(0, (sum, d) => sum + d.wordCount);
  }

  // 加载所有数据（初始化使用）
  Future<void> loadAllData() async {
    _setLoading(true);
    try {
      // 1. 先加载最近的日记（快速显示首页）
      await loadRecentDiaries(limit: 20);
      
      // 2. 并行加载心情和标签（数据量小，不影响启动速度）
      await Future.wait([
        loadMoods(),
        loadTags(),
      ]);
      
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  /// 加载最近的日记（快速启动）
  Future<void> loadRecentDiaries({int limit = 20}) async {
    try {
      _diaries = await DatabaseService.getRecentDiaries(limit: limit);
      _currentPage = 0;
      _hasMoreData = _diaries.length >= limit;
      
      // 后台预加载图片（不阻塞）
      _preloadImagesAsync();
      
      notifyListeners();
    } catch (e) {
      _error = '加载日记失败: $e';
      notifyListeners();
    }
  }

  /// 加载更多日记（分页）
  Future<void> loadMoreDiaries() async {
    if (_isLoadingMore || !_hasMoreData) return;
    
    _isLoadingMore = true;
    notifyListeners();
    
    try {
      _currentPage++;
      final newDiaries = await DatabaseService.getDiariesPaged(
        page: _currentPage,
        pageSize: _pageSize,
      );
      
      if (newDiaries.isEmpty) {
        _hasMoreData = false;
      } else {
        _diaries.addAll(newDiaries);
        
        // 后台预加载新加载日记的图片
        _preloadImagesForDiaries(newDiaries);
      }
      
      _error = null;
    } catch (e) {
      _error = '加载更多日记失败: $e';
      _currentPage--; // 回退页码
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// 加载所有日记（用于需要完整数据的场景，如搜索、统计）
  Future<void> loadDiaries() async {
    try {
      _diaries = await DatabaseService.getAllDiaries();
      _currentPage = 0;
      _hasMoreData = false;
      
      // 后台预加载图片
      _preloadImagesAsync();
      
      notifyListeners();
    } catch (e) {
      _error = '加载日记失败: $e';
      notifyListeners();
    }
  }

  /// 异步预加载图片（不阻塞主线程）
  void _preloadImagesAsync() {
    // 延迟执行，让 UI 先完成渲染
    Future.delayed(const Duration(milliseconds: 500), () {
      _preloadImagesForDiaries(_diaries);
    });
  }

  /// 预加载指定日记列表的图片
  void _preloadImagesForDiaries(List<Diary> diaries) {
    final allImagePaths = <String>[];
    for (final diary in diaries) {
      if (diary.imageList.isNotEmpty) {
        allImagePaths.addAll(diary.imageList);
      }
    }
    
    if (allImagePaths.isNotEmpty) {
      // 限制预加载数量，优先加载最近的图片
      final pathsToPreload = allImagePaths.length > 30 
          ? allImagePaths.sublist(0, 30) 
          : allImagePaths;
      
      // 使用小尺寸缩略图预加载
      ImageCacheService().preloadImages(
        pathsToPreload,
        quality: 'small',
      );
    }
  }

  // 加载心情列表
  Future<void> loadMoods() async {
    try {
      _moods = await DatabaseService.getAllMoods();
      // 如果没有心情，初始化默认心情
      if (_moods.isEmpty) {
        for (final mood in Mood.defaultMoods) {
          await DatabaseService.insertMood(mood);
        }
        _moods = await DatabaseService.getAllMoods();
      }
      notifyListeners();
    } catch (e) {
      _error = '加载心情失败: $e';
      notifyListeners();
    }
  }

  // 加载标签列表
  Future<void> loadTags() async {
    try {
      _tags = await DatabaseService.getAllTags();
      notifyListeners();
    } catch (e) {
      _error = '加载标签失败: $e';
      notifyListeners();
    }
  }

  // 添加日记 - 返回带有新ID的日记对象
  Future<Diary?> addDiary(Diary diary, List<String> tagIds) async {
    try {
      final id = await DatabaseService.insertDiary(diary);
      // 创建带有ID的日记对象
      final diaryWithId = diary.copyWith(id: id);
      
      // 关联标签（新的三级标签系统）
      await DatabaseService.insertDiaryTagsV3(id, tagIds);
      
      // 更新标签使用次数
      for (final tagId in tagIds) {
        await TagSystemService.incrementTagUsage(tagId);
      }
      
      // 重新加载最近的日记
      await loadRecentDiaries(limit: (_currentPage + 1) * _pageSize);
      return diaryWithId;
    } catch (e) {
      _error = '添加日记失败: $e';
      notifyListeners();
      return null;
    }
  }

  // 更新日记
  Future<bool> updateDiary(Diary diary, List<String> tagIds) async {
    try {
      await DatabaseService.updateDiary(diary);
      // 更新标签关联（新的三级标签系统）
      await DatabaseService.deleteDiaryTagsV3(diary.id!);
      await DatabaseService.insertDiaryTagsV3(diary.id!, tagIds);
      
      // 更新标签使用次数
      for (final tagId in tagIds) {
        await TagSystemService.incrementTagUsage(tagId);
      }
      
      await loadDiaries();
      return true;
    } catch (e) {
      _error = '更新日记失败: $e';
      notifyListeners();
      return false;
    }
  }

  // 删除日记
  Future<bool> deleteDiary(int id) async {
    try {
      await DatabaseService.deleteDiary(id);
      _diaries.removeWhere((d) => d.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '删除日记失败: $e';
      notifyListeners();
      return false;
    }
  }

  // 切换收藏状态
  /// 切换日记收藏状态，返回新的收藏状态
  Future<bool> toggleFavorite(int diaryId) async {
    try {
      final diary = _diaries.firstWhere((d) => d.id == diaryId);
      final newFavoriteState = !diary.isFavorite;
      final updated = diary.copyWith(isFavorite: newFavoriteState);
      await DatabaseService.updateDiary(updated);
      
      // 本地更新，避免重新加载
      final index = _diaries.indexWhere((d) => d.id == diaryId);
      if (index != -1) {
        _diaries[index] = updated;
        notifyListeners();
      }
      return newFavoriteState;
    } catch (e) {
      _error = '操作失败: $e';
      notifyListeners();
      return false;
    }
  }

  // 添加心情
  Future<bool> addMood(Mood mood) async {
    try {
      await DatabaseService.insertMood(mood);
      await loadMoods();
      return true;
    } catch (e) {
      _error = '添加心情失败: $e';
      notifyListeners();
      return false;
    }
  }

  // 删除心情
  Future<bool> deleteMood(int id) async {
    try {
      await DatabaseService.deleteMood(id);
      await loadMoods();
      return true;
    } catch (e) {
      _error = '删除心情失败: $e';
      notifyListeners();
      return false;
    }
  }

  // 添加标签
  Future<bool> addTag(Tag tag) async {
    try {
      await DatabaseService.insertTag(tag);
      await loadTags();
      return true;
    } catch (e) {
      _error = '添加标签失败: $e';
      notifyListeners();
      return false;
    }
  }

  // 更新标签
  Future<bool> updateTag(Tag tag) async {
    try {
      await DatabaseService.updateTag(tag);
      await loadTags();
      return true;
    } catch (e) {
      _error = '更新标签失败: $e';
      notifyListeners();
      return false;
    }
  }

  // 删除标签
  Future<bool> deleteTag(int id) async {
    try {
      await DatabaseService.deleteTag(id);
      await loadTags();
      return true;
    } catch (e) {
      _error = '删除标签失败: $e';
      notifyListeners();
      return false;
    }
  }

  // 获取日记的标签
  Future<List<Tag>> getDiaryTags(int diaryId) async {
    return await DatabaseService.getTagsByDiaryId(diaryId);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
