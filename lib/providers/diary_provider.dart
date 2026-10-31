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

      // ⚠️ 2026-10-28 修复：「搜索能搜到、主界面没有」。
      //
      // `loadRecentDiaries` 走 `getRecentDiaries`，它只读内存里的 `_diaries`。
      // 若此刻数据层尚未完成初始化（或初始化异常被吞），它拿到的是空列表
      // 且**不会抛错** → 主界面永远空着。
      // 而搜索页调 `getAllDiaries()` 会 `await _ensureInitialized()`，
      // 所以它能正确读到 —— 这正是两者表现不一致的根因。
      //
      // 兜底：快速路径拿到空列表、但磁盘上确实有数据时，
      // 切换到会强制初始化的全量加载。
      if (_diaries.isEmpty && await DatabaseService.hasDiaryDataOnDisk()) {
        debugPrint('⚠️ 快速路径为空但磁盘有数据，改用全量加载');
        await loadDiaries();
      }

      // 2. 并行加载心情和标签（数据量小，不影响启动速度）
      await Future.wait([
        loadMoods(),
        loadTags(),
      ]);
      
      _error = null;
    } catch (e, st) {
      _error = e.toString();
      debugPrint('❌ loadAllData 失败: $e\n$st');
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
    } catch (e, st) {
      // ⚠️ 2026-10-28：「搜索能搜到、主界面没有」的排查经验表明，
      // 这里如果静默失败，用户只会看到一个空列表，完全不知道出了错。
      // 记下带堆栈的错误，并**主动尝试一次全量加载**作为兜底 ——
      // `getRecentDiaries` 走的是分页快速路径，万一它出错，
      // 全量 `getAllDiaries` 往往仍能成功。
      _error = '加载日记失败: $e';
      debugPrint('❌ loadRecentDiaries 失败: $e\n$st');

      try {
        final all = await DatabaseService.getAllDiaries();
        if (all.isNotEmpty) {
          _diaries = all;
          _currentPage = 0;
          _hasMoreData = false;
          debugPrint('✅ 已通过全量加载兜底，取回 ${all.length} 篇');
        }
      } catch (e2) {
        debugPrint('❌ 全量兜底也失败: $e2');
      }

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

      // 更新标签使用次数：**批量写盘一次**（B0-3）。
      // 原先对每个 tagId 单独 await，每个都会把整个标签系统 JSON 全量
      // 重写一遍 SharedPreferences（commit 同步 fsync）→ 带 3 个标签
      // 就是 3 次全量写盘。
      await TagSystemService.incrementTagUsages(tagIds);

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

      // 更新标签使用次数：批量写盘一次（B0-3，理由同 addDiary）
      await TagSystemService.incrementTagUsages(tagIds);

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
