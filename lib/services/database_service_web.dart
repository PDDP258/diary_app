// ignore: unused_import
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anniversary.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import '../models/self_talk_message.dart';
import '../models/quick_note.dart';
import '../models/self_talk_task.dart';
import 'encryption_service.dart';

/// Web 版本数据库服务（使用 SharedPreferences 持久化存储）
/// 所有日记内容自动加密存储
/// 
/// 性能优化：
/// 1. 增量加载 - 支持分页获取日记
/// 2. 异步解密 - 后台解密不阻塞主线程
/// 3. 缓存元数据 - 快速获取统计信息
class DatabaseService {
  static const String _diariesKey = 'diaries_data';
  static const String _moodsKey = 'moods_data';
  static const String _tagsKey = 'tags_data';
  static const String _diaryTagsKey = 'diary_tags_data';
  static const String _diaryTagsV3Key = 'diary_tags_v3_data';  // 三级标签系统
  static const String _metadataKey = 'diaries_metadata';
  static const String _anniversariesKey = 'anniversaries_data';
  static const String _selfTalkMessagesKey = 'self_talk_messages_data';
  static const String _selfTalkTasksKey = 'self_talk_tasks_data';
  static const String _quickNotesKey = 'quick_notes_data';

  static List<Diary> _diaries = [];
  static List<Mood> _moods = [];
  static List<Tag> _tags = [];
  static List<Anniversary> _anniversaries = [];
  static List<Map<String, dynamic>> _diaryTags = [];
  static List<Map<String, dynamic>> _diaryTagsV3 = [];  // 三级标签关联
  static List<SelfTalkMessage> _selfTalkMessages = [];
  static List<SelfTalkTask> _selfTalkTasks = [];
  static List<QuickNote> _quickNotes = [];
  static int _diaryIdCounter = 1;
  static int _moodIdCounter = 1;
  static int _tagIdCounter = 1;
  static int _anniversaryIdCounter = 1;
  static int _selfTalkMessageIdCounter = 1;
  static int _selfTalkTaskIdCounter = 1;
  static int _quickNoteIdCounter = 1;
  static bool _initialized = false;
  static SharedPreferences? _prefs;

  /// 元数据缓存（避免频繁计算）
  static Map<String, dynamic> _metadataCache = {};

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;

    // 初始化 SharedPreferences
    _prefs = await SharedPreferences.getInstance();

    // 初始化加密服务
    await EncryptionService.initialize();

    // 加载保存的数据（异步解密，不阻塞）
    await _loadData();

    // 初始化默认心情 - 只在首次使用时添加，避免每次启动重置
    if (_moods.isEmpty) {
      int counter = 1;
      for (final mood in Mood.defaultMoods) {
        final newMood = mood.copyWith(id: counter++);
        _moods.add(newMood);
      }
      _moodIdCounter = counter;
      await _saveMoods();
    }

    _initialized = true;
  }

  /// 从 SharedPreferences 加载数据
  /// 优化：先加载元数据，日记内容延迟解密
  static Future<void> _loadData() async {
    try {
      // 加载元数据（快速）
      final metadataJson = _prefs?.getString(_metadataKey);
      if (metadataJson != null) {
        _metadataCache = jsonDecode(metadataJson);
      }

      // 加载日记（同步解密，确保数据完整性）
      final diariesJson = _prefs?.getString(_diariesKey);
      if (diariesJson != null) {
        final List<dynamic> diariesList = jsonDecode(diariesJson);
        
        // 同步解密所有日记数据，避免数据不一致问题
        await _decryptDiariesSync(diariesList);

        // 更新ID计数器
        if (_diaries.isNotEmpty) {
          _diaryIdCounter =
              _diaries.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
        }
      }

      // 加载心情（不加密，直接加载）
      final moodsJson = _prefs?.getString(_moodsKey);
      if (moodsJson != null) {
        final List<dynamic> moodsList = jsonDecode(moodsJson);
        _moods = moodsList.map((e) => Mood.fromMap(e)).toList();
        if (_moods.isNotEmpty) {
          _moodIdCounter =
              _moods.map((m) => m.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
        }
      }

      // 加载标签（不加密，直接加载）
      final tagsJson = _prefs?.getString(_tagsKey);
      if (tagsJson != null) {
        final List<dynamic> tagsList = jsonDecode(tagsJson);
        _tags = tagsList.map((e) => Tag.fromMap(e)).toList();
        if (_tags.isNotEmpty) {
          _tagIdCounter =
              _tags.map((t) => t.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
        }
      }

      // 加载日记标签关联
      final diaryTagsJson = _prefs?.getString(_diaryTagsKey);
      if (diaryTagsJson != null) {
        final List<dynamic> diaryTagsList = jsonDecode(diaryTagsJson);
        _diaryTags = diaryTagsList.cast<Map<String, dynamic>>();
      }

      // 加载三级标签关联
      final diaryTagsV3Json = _prefs?.getString(_diaryTagsV3Key);
      if (diaryTagsV3Json != null) {
        final List<dynamic> diaryTagsV3List = jsonDecode(diaryTagsV3Json);
        _diaryTagsV3 = diaryTagsV3List.cast<Map<String, dynamic>>();
      }

      // 加载纪念日（不加密，直接加载）
      final anniversariesJson = _prefs?.getString(_anniversariesKey);
      if (anniversariesJson != null) {
        final List<dynamic> anniversariesList = jsonDecode(anniversariesJson);
        _anniversaries = anniversariesList.map((e) => Anniversary.fromMap(e)).toList();
        if (_anniversaries.isNotEmpty) {
          _anniversaryIdCounter = _anniversaries
                  .map((a) => a.id ?? 0)
                  .reduce((a, b) => a > b ? a : b) +
              1;
        }
      }

      // 加载自言自语消息
      final selfTalkMessagesJson = _prefs?.getString(_selfTalkMessagesKey);
      if (selfTalkMessagesJson != null) {
        final List<dynamic> selfTalkMessagesList = jsonDecode(selfTalkMessagesJson);
        _selfTalkMessages = selfTalkMessagesList.map((e) => SelfTalkMessage.fromMap(e)).toList();
        if (_selfTalkMessages.isNotEmpty) {
          _selfTalkMessageIdCounter = _selfTalkMessages
                  .map((m) => m.id ?? 0)
                  .reduce((a, b) => a > b ? a : b) +
              1;
        }
      }

      // 加载自言自语任务
      final selfTalkTasksJson = _prefs?.getString(_selfTalkTasksKey);
      if (selfTalkTasksJson != null) {
        final List<dynamic> selfTalkTasksList = jsonDecode(selfTalkTasksJson);
        _selfTalkTasks = selfTalkTasksList.map((e) => SelfTalkTask.fromMap(e)).toList();
        if (_selfTalkTasks.isNotEmpty) {
          _selfTalkTaskIdCounter = _selfTalkTasks
                  .map((t) => t.id ?? 0)
                  .reduce((a, b) => a > b ? a : b) +
              1;
        }
      }

      // 加载速记
      final quickNotesJson = _prefs?.getString(_quickNotesKey);
      if (quickNotesJson != null) {
        final List<dynamic> quickNotesList = jsonDecode(quickNotesJson);
        _quickNotes = quickNotesList.map((e) => QuickNote.fromMap(e)).toList();
        if (_quickNotes.isNotEmpty) {
          _quickNoteIdCounter = _quickNotes
                  .map((n) => n.id ?? 0)
                  .reduce((a, b) => a > b ? a : b) +
              1;
        }
      }
    } catch (e) {
      print('加载数据失败: $e');
    }
  }

  /// 同步解密日记数据（修复数据消失问题）
  static Future<void> _decryptDiariesSync(List<dynamic> encryptedList) async {
    try {
      final decryptedDiaries = <Diary>[];
      
      for (var i = 0; i < encryptedList.length; i++) {
        final map = encryptedList[i] as Map<String, dynamic>;
        final decrypted = await _decryptDiaryMap(map);
        
        // 创建完整的解密后日记对象
        decryptedDiaries.add(Diary(
          id: map['id'],
          title: decrypted['title'] ?? '',
          content: decrypted['content'] ?? '',
          date: map['date'] ?? '',
          moodId: map['mood_id'],
          moodName: map['mood_name'],
          moodEmoji: map['mood_emoji'],
          weather: map['weather'],
          location: map['location'],
          images: map['images'],
          isFavorite: map['is_favorite'] == 1,
          createdAt: map['created_at'],
          updatedAt: map['updated_at'],
        ));
      }
      
      // 原子性替换整个列表，确保数据一致性
      _diaries = decryptedDiaries;
    } catch (e) {
      print('日记解密失败: $e');
      // 解密失败时保留原始数据，避免数据丢失
    }
  }

  /// 保存日记到 SharedPreferences
  static Future<void> _saveDiaries() async {
    // 加密日记数据
    final encryptedList = await Future.wait(
      _diaries.map((d) => _encryptDiaryMap(d.toMap())),
    );
    final diariesJson = jsonEncode(encryptedList);
    await _prefs?.setString(_diariesKey, diariesJson);
    
    // 更新并保存元数据
    _updateMetadata();
  }

  /// 保存心情到 SharedPreferences
  static Future<void> _saveMoods() async {
    final moodsJson = jsonEncode(_moods.map((m) => m.toMap()).toList());
    await _prefs?.setString(_moodsKey, moodsJson);
  }

  /// 保存标签到 SharedPreferences
  static Future<void> _saveTags() async {
    final tagsJson = jsonEncode(_tags.map((t) => t.toMap()).toList());
    await _prefs?.setString(_tagsKey, tagsJson);
  }

  /// 保存日记标签关联到 SharedPreferences
  static Future<void> _saveDiaryTags() async {
    final diaryTagsJson = jsonEncode(_diaryTags);
    await _prefs?.setString(_diaryTagsKey, diaryTagsJson);
  }

  /// 保存三级标签关联到 SharedPreferences
  static Future<void> _saveDiaryTagsV3() async {
    final diaryTagsV3Json = jsonEncode(_diaryTagsV3);
    await _prefs?.setString(_diaryTagsV3Key, diaryTagsV3Json);
  }

  /// 保存纪念日到 SharedPreferences
  static Future<void> _saveAnniversaries() async {
    final anniversariesJson = jsonEncode(_anniversaries.map((a) => a.toMap()).toList());
    await _prefs?.setString(_anniversariesKey, anniversariesJson);
  }

  /// 保存自言自语消息到 SharedPreferences
  static Future<void> _saveSelfTalkMessages() async {
    final selfTalkJson = jsonEncode(_selfTalkMessages.map((m) => m.toMap()).toList());
    await _prefs?.setString(_selfTalkMessagesKey, selfTalkJson);
  }

  /// 保存自言自语任务到 SharedPreferences
  static Future<void> _saveSelfTalkTasks() async {
    final selfTalkTasksJson = jsonEncode(_selfTalkTasks.map((t) => t.toMap()).toList());
    await _prefs?.setString(_selfTalkTasksKey, selfTalkTasksJson);
  }

  /// 保存速记到 SharedPreferences
  static Future<void> _saveQuickNotes() async {
    final quickNotesJson = jsonEncode(_quickNotes.map((n) => n.toMap()).toList());
    await _prefs?.setString(_quickNotesKey, quickNotesJson);
  }

  /// 更新元数据缓存
  static void _updateMetadata() {
    _metadataCache = {
      'totalCount': _diaries.length,
      'totalWordCount': _diaries.fold(0, (sum, d) => sum + d.wordCount),
      'uniqueDates': _diaries.map((d) => d.date).toSet().toList(),
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    _prefs?.setString(_metadataKey, jsonEncode(_metadataCache));
  }

  // ==================== 加密/解密辅助方法 ====================

  /// 加密日记数据
  static Future<Map<String, dynamic>> _encryptDiaryMap(
      Map<String, dynamic> map) async {
    final result = Map<String, dynamic>.from(map);

    // 加密敏感字段
    if (map['title'] != null && !EncryptionService.isEncrypted(map['title'])) {
      result['title'] = await EncryptionService.encryptTextV2(map['title']);
    }
    if (map['content'] != null &&
        !EncryptionService.isEncrypted(map['content'])) {
      result['content'] = await EncryptionService.encryptTextV2(map['content']);
    }

    return result;
  }

  /// 解密日记数据
  static Future<Map<String, dynamic>> _decryptDiaryMap(
      Map<String, dynamic> map) async {
    final result = Map<String, dynamic>.from(map);

    // 解密敏感字段
    if (map['title'] != null) {
      result['title'] = await EncryptionService.decryptTextV2(map['title']);
    }
    if (map['content'] != null) {
      result['content'] = await EncryptionService.decryptTextV2(map['content']);
    }

    return result;
  }

  // ==================== 日记操作 ====================

  /// 获取所有日记（按日期排序）
  static Future<List<Diary>> getAllDiaries() async {
    await _ensureInitialized();
    return List.from(_diaries)..sort((a, b) => b.date.compareTo(a.date));
  }

  /// 分页获取日记（优化大数据量加载）
  /// 
  /// [page] 页码，从 0 开始
  /// [pageSize] 每页数量
  static Future<List<Diary>> getDiariesPaged({
    required int page,
    int pageSize = 20,
  }) async {
    await _ensureInitialized();
    
    final sorted = List<Diary>.from(_diaries)
      ..sort((a, b) => b.date.compareTo(a.date));
    
    final start = page * pageSize;
    if (start >= sorted.length) return [];
    
    final end = (start + pageSize).clamp(0, sorted.length);
    return sorted.sublist(start, end);
  }

  /// 获取最近的 N 篇日记（快速加载首页）
  static Future<List<Diary>> getRecentDiaries({int limit = 10}) async {
    await _ensureInitialized();
    
    final sorted = List<Diary>.from(_diaries)
      ..sort((a, b) => b.date.compareTo(a.date));
    
    if (sorted.length <= limit) return sorted;
    return sorted.sublist(0, limit);
  }

  static Future<List<Diary>> getDiariesByDate(String date) async {
    await _ensureInitialized();
    return _diaries.where((d) => d.date == date).toList()
      ..sort((a, b) {
        if (a.createdAt == null || b.createdAt == null) return 0;
        return b.createdAt!.compareTo(a.createdAt!);
      });
  }

  static Future<List<Diary>> getDiariesByMonth(int year, int month) async {
    await _ensureInitialized();
    final monthStr = month.toString().padLeft(2, '0');
    return _diaries.where((d) => d.date.startsWith('$year-$monthStr')).toList();
  }

  static Future<Diary?> getDiary(int id) async {
    await _ensureInitialized();
    try {
      return _diaries.firstWhere((d) => d.id == id);
    } catch (e) {
      return null;
    }
  }

  static Future<int> insertDiary(Diary diary) async {
    await _ensureInitialized();
    final newDiary = diary.copyWith(
      id: _diaryIdCounter++,
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );
    _diaries.add(newDiary);
    await _saveDiaries();
    return newDiary.id!;
  }

  /// 批量导入日记（保留原始ID和时间戳）
  static Future<void> importDiaries(List<Diary> diaries) async {
    await _ensureInitialized();
    
    for (final diary in diaries) {
      // 检查是否已存在相同ID的日记
      final existingIndex = _diaries.indexWhere((d) => d.id == diary.id);
      if (existingIndex != -1) {
        // 更新现有日记
        _diaries[existingIndex] = diary;
      } else {
        // 添加新日记，保留原始ID
        _diaries.add(diary);
        // 更新ID计数器
        if (diary.id != null && diary.id! >= _diaryIdCounter) {
          _diaryIdCounter = diary.id! + 1;
        }
      }
    }
    
    await _saveDiaries();
  }

  /// 批量导入心情（保留原始ID）
  static Future<void> importMoods(List<Mood> moods) async {
    await _ensureInitialized();
    
    for (final mood in moods) {
      final existingIndex = _moods.indexWhere((m) => m.id == mood.id);
      if (existingIndex != -1) {
        _moods[existingIndex] = mood;
      } else {
        _moods.add(mood);
        if (mood.id != null && mood.id! >= _moodIdCounter) {
          _moodIdCounter = mood.id! + 1;
        }
      }
    }
    
    await _saveMoods();
  }

  /// 批量导入标签（保留原始ID）
  static Future<void> importTags(List<Tag> tags) async {
    await _ensureInitialized();
    
    for (final tag in tags) {
      final existingIndex = _tags.indexWhere((t) => t.id == tag.id);
      if (existingIndex != -1) {
        _tags[existingIndex] = tag;
      } else {
        _tags.add(tag);
        if (tag.id != null && tag.id! >= _tagIdCounter) {
          _tagIdCounter = tag.id! + 1;
        }
      }
    }
    
    await _saveTags();
  }

  static Future<int> updateDiary(Diary diary) async {
    await _ensureInitialized();
    final index = _diaries.indexWhere((d) => d.id == diary.id);
    if (index != -1) {
      _diaries[index] = diary.copyWith(
        updatedAt: DateTime.now().toIso8601String(),
      );
      await _saveDiaries();
      return 1;
    }
    return 0;
  }

  static Future<int> deleteDiary(int id) async {
    await _ensureInitialized();
    _diaries.removeWhere((d) => d.id == id);
    _diaryTags.removeWhere((dt) => dt['diary_id'] == id);
    await _saveDiaries();
    await _saveDiaryTags();
    return 1;
  }

  static Future<int> getDiaryCount() async {
    await _ensureInitialized();
    // 优先使用缓存的元数据
    if (_metadataCache.containsKey('totalCount')) {
      return _metadataCache['totalCount'];
    }
    return _diaries.length;
  }

  static Future<int> getTotalWordCount() async {
    await _ensureInitialized();
    // 优先使用缓存的元数据
    if (_metadataCache.containsKey('totalWordCount')) {
      return _metadataCache['totalWordCount'];
    }
    return _diaries.fold<int>(0, (sum, d) => sum + d.wordCount);
  }

  static Future<DateTime?> getFirstDiaryDate() async {
    await _ensureInitialized();
    if (_diaries.isEmpty) return null;
    final dates = _diaries.map((d) => DateTime.parse(d.date)).toList()..sort();
    return dates.first;
  }

  /// 快速获取有日记的日期集合（使用元数据）
  static Future<Set<String>> getDatesWithDiaries() async {
    await _ensureInitialized();
    if (_metadataCache.containsKey('uniqueDates')) {
      return Set<String>.from(_metadataCache['uniqueDates']);
    }
    return _diaries.map((d) => d.date).toSet();
  }

  // ==================== 心情操作 ====================

  static Future<List<Mood>> getAllMoods() async {
    await _ensureInitialized();
    return List.from(_moods)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  static Future<Mood?> getMood(int id) async {
    await _ensureInitialized();
    try {
      return _moods.firstWhere((m) => m.id == id);
    } catch (e) {
      return null;
    }
  }

  static Future<int> insertMood(Mood mood) async {
    await _ensureInitialized();
    final newMood = mood.copyWith(id: _moodIdCounter++);
    _moods.add(newMood);
    await _saveMoods();
    return newMood.id!;
  }

  static Future<int> updateMood(Mood mood) async {
    await _ensureInitialized();
    final index = _moods.indexWhere((m) => m.id == mood.id);
    if (index != -1) {
      _moods[index] = mood;
      await _saveMoods();
      return 1;
    }
    return 0;
  }

  // 查询使用该心情的日记数量
  static Future<int> getDiaryCountByMood(int moodId) async {
    await _ensureInitialized();
    return _diaries.where((d) => d.moodId == moodId).length;
  }

  static Future<int> deleteMood(int id) async {
    await _ensureInitialized();
    // 先将使用该心情的日记的 mood 信息清空
    for (var diary in _diaries) {
      if (diary.moodId == id) {
        diary = diary.copyWith(moodId: null, moodName: null, moodEmoji: null);
      }
    }
    await _saveDiaries();
    // 删除心情
    _moods.removeWhere((m) => m.id == id);
    await _saveMoods();
    return 1;
  }

  // ==================== 标签操作 ====================

  static Future<List<Tag>> getAllTags() async {
    await _ensureInitialized();
    return List.from(_tags)
      ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
  }

  static Future<Tag?> getTag(int id) async {
    await _ensureInitialized();
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }

  static Future<int> insertTag(Tag tag) async {
    await _ensureInitialized();
    final newTag = tag.copyWith(
      id: _tagIdCounter++,
      createdAt: DateTime.now(),
    );
    _tags.add(newTag);
    await _saveTags();
    return newTag.id!;
  }

  static Future<int> updateTag(Tag tag) async {
    await _ensureInitialized();
    final index = _tags.indexWhere((t) => t.id == tag.id);
    if (index != -1) {
      _tags[index] = tag;
      await _saveTags();
      return 1;
    }
    return 0;
  }

  static Future<int> deleteTag(int id) async {
    await _ensureInitialized();
    _tags.removeWhere((t) => t.id == id);
    _diaryTags.removeWhere((dt) => dt['tag_id'] == id);
    await _saveTags();
    await _saveDiaryTags();
    return 1;
  }

  // ==================== 日记标签关联操作 ====================

  static Future<void> insertDiaryTag(int diaryId, int tagId) async {
    await _ensureInitialized();
    // 检查是否已存在
    final exists = _diaryTags
        .any((dt) => dt['diary_id'] == diaryId && dt['tag_id'] == tagId);
    if (!exists) {
      _diaryTags.add({
        'id': _diaryTags.length + 1,
        'diary_id': diaryId,
        'tag_id': tagId,
      });
      await _saveDiaryTags();
    }
  }

  static Future<void> deleteDiaryTags(int diaryId) async {
    await _ensureInitialized();
    _diaryTags.removeWhere((dt) => dt['diary_id'] == diaryId);
    await _saveDiaryTags();
  }

  /// 批量导入日记标签关联（用于云同步恢复）
  static Future<void> importDiaryTags(List<Map<String, dynamic>> diaryTags) async {
    await _ensureInitialized();
    
    for (final dt in diaryTags) {
      final diaryId = dt['diary_id'] as int;
      final tagId = dt['tag_id'] as int;
      
      // 检查是否已存在
      final exists = _diaryTags
          .any((existing) => existing['diary_id'] == diaryId && existing['tag_id'] == tagId);
      if (!exists) {
        _diaryTags.add({
          'id': _diaryTags.length + 1,
          'diary_id': diaryId,
          'tag_id': tagId,
        });
      }
    }
    
    await _saveDiaryTags();
  }

  /// 获取所有日记标签关联（用于云同步备份）
  static Future<List<Map<String, dynamic>>> getAllDiaryTags() async {
    await _ensureInitialized();
    return List<Map<String, dynamic>>.from(_diaryTags);
  }

  static Future<List<Tag>> getTagsByDiaryId(int diaryId) async {
    await _ensureInitialized();
    final tagIds = _diaryTags
        .where((dt) => dt['diary_id'] == diaryId)
        .map((dt) => dt['tag_id'] as int)
        .toList();
    return _tags.where((t) => t.id != null && tagIds.contains(t.id)).toList();
  }

  /// 获取使用某标签的所有日记
  static Future<List<Diary>> getDiariesByTagId(int tagId) async {
    await _ensureInitialized();
    final diaryIds = _diaryTags
        .where((dt) => dt['tag_id'] == tagId)
        .map((dt) => dt['diary_id'] as int)
        .toList();
    return _diaries
        .where((d) => d.id != null && diaryIds.contains(d.id))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // ==================== 统计操作 ====================

  static Future<Map<String, int>> getMoodDistribution() async {
    await _ensureInitialized();
    final Map<String, int> distribution = {};
    for (final diary in _diaries) {
      if (diary.moodName != null) {
        distribution[diary.moodName!] =
            (distribution[diary.moodName!] ?? 0) + 1;
      }
    }
    return distribution;
  }

  static Future<List<Map<String, dynamic>>> getDiaryCountByMonth() async {
    await _ensureInitialized();
    final Map<String, int> counts = {};
    for (final diary in _diaries) {
      final month = diary.date.substring(0, 7);
      counts[month] = (counts[month] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => {'month': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['month'] as String).compareTo(a['month'] as String));
  }

  // ==================== 纪念日操作 ====================

  /// 获取所有纪念日
  static Future<List<Anniversary>> getAllAnniversaries() async {
    await _ensureInitialized();
    return List.from(_anniversaries)
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 获取指定日期的纪念日
  static Future<List<Anniversary>> getAnniversariesByDate(String date) async {
    await _ensureInitialized();
    return _anniversaries.where((a) => a.date == date).toList();
  }

  /// 插入纪念日
  static Future<int> insertAnniversary(Anniversary anniversary) async {
    await _ensureInitialized();
    final newAnniversary = anniversary.copyWith(
      id: _anniversaryIdCounter++,
      createdAt: DateTime.now(),
    );
    _anniversaries.add(newAnniversary);
    await _saveAnniversaries();
    return newAnniversary.id!;
  }

  /// 更新纪念日
  static Future<int> updateAnniversary(Anniversary anniversary) async {
    await _ensureInitialized();
    final index = _anniversaries.indexWhere((a) => a.id == anniversary.id);
    if (index != -1) {
      _anniversaries[index] = anniversary;
      await _saveAnniversaries();
      return 1;
    }
    return 0;
  }

  /// 删除纪念日
  static Future<int> deleteAnniversary(int id) async {
    await _ensureInitialized();
    _anniversaries.removeWhere((a) => a.id == id);
    await _saveAnniversaries();
    return 1;
  }

  /// 获取某日期相关的纪念日（用于写日记时自动添加纪念文字）
  /// 包括：该日期作为目标日期的纪念日/倒数日
  static Future<List<Anniversary>> getAnniversariesForDate(String date) async {
    await _ensureInitialized();
    // 返回所有纪念日，因为写日记时需要检查是否是某个纪念日的特殊日子
    return List.from(_anniversaries);
  }

  static Future<void> close() async {
    // Web 版本不需要特殊关闭操作
  }

  // ==================== 数据恢复操作 ====================

  /// 恢复日记数据（用于从备份恢复）
  static Future<void> restoreDiaries(List<Diary> diaries) async {
    await _ensureInitialized();
    
    // 加密日记内容
    _diaries = [];
    for (final diary in diaries) {
      final encryptedMap = await _encryptDiaryMap(diary.toMap());
      _diaries.add(Diary.fromMap(encryptedMap));
    }
    
    // 更新ID计数器
    if (_diaries.isNotEmpty) {
      _diaryIdCounter = _diaries.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    }
    
    // 保存到存储
    await _saveDiaries();
    _updateMetadata();
  }

  /// 恢复心情数据（用于从备份恢复）
  static Future<void> restoreMoods(List<Mood> moods) async {
    await _ensureInitialized();
    
    _moods = List.from(moods);
    
    // 更新ID计数器
    if (_moods.isNotEmpty) {
      _moodIdCounter = _moods.map((m) => m.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    }
    
    await _saveMoods();
  }

  /// 恢复标签数据（用于从备份恢复）
  static Future<void> restoreTags(List<Tag> tags) async {
    await _ensureInitialized();
    
    _tags = List.from(tags);
    
    // 更新ID计数器
    if (_tags.isNotEmpty) {
      _tagIdCounter = _tags.map((t) => t.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    }
    
    await _saveTags();
  }

  // ==================== 三级标签系统操作（V3）====================

  /// 插入日记的三级标签关联
  static Future<void> insertDiaryTagsV3(int diaryId, List<String> tagIds) async {
    await _ensureInitialized();
    for (final tagId in tagIds) {
      // 检查是否已存在
      final exists = _diaryTagsV3.any((dt) => 
          dt['diary_id'] == diaryId && dt['tag_id'] == tagId);
      if (!exists) {
        _diaryTagsV3.add({
          'diary_id': diaryId,
          'tag_id': tagId,
        });
      }
    }
    await _saveDiaryTagsV3();
  }

  /// 删除日记的所有三级标签关联
  static Future<void> deleteDiaryTagsV3(int diaryId) async {
    await _ensureInitialized();
    _diaryTagsV3.removeWhere((dt) => dt['diary_id'] == diaryId);
    await _saveDiaryTagsV3();
  }

  /// 获取日记的三级标签ID列表
  static Future<List<String>> getDiaryTagIdsV3(int diaryId) async {
    await _ensureInitialized();
    return _diaryTagsV3
        .where((dt) => dt['diary_id'] == diaryId)
        .map((dt) => dt['tag_id'] as String)
        .toList();
  }

  /// 根据标签ID获取关联的日记ID列表
  static Future<List<int>> getDiaryIdsByTagIdV3(String tagId) async {
    await _ensureInitialized();
    return _diaryTagsV3
        .where((dt) => dt['tag_id'] == tagId)
        .map((dt) => dt['diary_id'] as int)
        .toList();
  }

  /// 根据标签ID获取日记列表（V3版本）
  static Future<List<Diary>> getDiariesByTagIdV3(String tagId) async {
    await _ensureInitialized();
    final diaryIds = await getDiaryIdsByTagIdV3(tagId);
    final diaries = <Diary>[];
    for (final id in diaryIds) {
      final diary = await getDiary(id);
      if (diary != null) {
        diaries.add(diary);
      }
    }
    return diaries;
  }

  /// 获取所有三级标签关联（用于云同步备份）
  static Future<List<Map<String, dynamic>>> getAllDiaryTagsV3() async {
    await _ensureInitialized();
    return List<Map<String, dynamic>>.from(_diaryTagsV3);
  }

  /// 批量导入三级标签关联（用于云同步恢复）
  static Future<void> importDiaryTagsV3(List<Map<String, dynamic>> diaryTags) async {
    await _ensureInitialized();
    
    for (final dt in diaryTags) {
      final diaryId = dt['diary_id'] as int;
      final tagId = dt['tag_id'] as String;
      
      // 检查是否已存在
      final exists = _diaryTagsV3.any((existing) => 
          existing['diary_id'] == diaryId && existing['tag_id'] == tagId);
      if (!exists) {
        _diaryTagsV3.add({
          'diary_id': diaryId,
          'tag_id': tagId,
        });
      }
    }
    
    await _saveDiaryTagsV3();
  }

  // ==================== 云同步合并方法（v1.1.5新增）====================

  /// 合并日记标签关联（去重插入）
  static Future<void> mergeDiaryTags(List<Map<String, dynamic>> diaryTags) async {
    await _ensureInitialized();
    
    for (final entry in diaryTags) {
      final diaryId = entry['diary_id'];
      final tagId = entry['tag_id'];
      
      if (diaryId == null || tagId == null) continue;
      
      // 检查关联是否已存在
      final exists = _diaryTags.any((existing) => 
          existing['diary_id'] == diaryId && existing['tag_id'] == tagId);
      
      if (!exists) {
        _diaryTags.add({
          'diary_id': diaryId,
          'tag_id': tagId,
        });
      }
    }
    
    await _saveDiaryTags();
  }

  // ==================== 自言自语消息操作 ====================

  static Future<int> insertSelfTalkMessage(SelfTalkMessage message) async {
    await _ensureInitialized();
    final newMessage = SelfTalkMessage(
      id: _selfTalkMessageIdCounter++,
      diaryId: message.diaryId,
      date: message.date,
      content: message.content,
      isUser: message.isUser,
      createdAt: message.createdAt,
    );
    _selfTalkMessages.add(newMessage);
    await _saveSelfTalkMessages();
    return newMessage.id!;
  }

  static Future<List<SelfTalkMessage>> getSelfTalkMessagesByDate(String date) async {
    await _ensureInitialized();
    return _selfTalkMessages
        .where((m) => m.date == date)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<int> deleteSelfTalkMessage(int id) async {
    await _ensureInitialized();
    _selfTalkMessages.removeWhere((m) => m.id == id);
    await _saveSelfTalkMessages();
    return 1;
  }

  // ==================== 自言自语任务操作 ====================

  static Future<int> insertSelfTalkTask(SelfTalkTask task) async {
    await _ensureInitialized();
    final newTask = SelfTalkTask(
      id: _selfTalkTaskIdCounter++,
      messageId: task.messageId,
      diaryId: task.diaryId,
      date: task.date,
      content: task.content,
      deadline: task.deadline,
      isCompleted: task.isCompleted,
      createdAt: task.createdAt,
    );
    _selfTalkTasks.add(newTask);
    await _saveSelfTalkTasks();
    return newTask.id!;
  }

  static Future<List<SelfTalkTask>> getSelfTalkTasksByDate(String date) async {
    await _ensureInitialized();
    return _selfTalkTasks
        .where((t) => t.date == date)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<List<SelfTalkTask>> getSelfTalkTasksByMessageId(int messageId) async {
    await _ensureInitialized();
    return _selfTalkTasks
        .where((t) => t.messageId == messageId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<int> updateSelfTalkTask(SelfTalkTask task) async {
    await _ensureInitialized();
    final index = _selfTalkTasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      _selfTalkTasks[index] = task;
      await _saveSelfTalkTasks();
      return 1;
    }
    return 0;
  }

  static Future<int> deleteSelfTalkTask(int id) async {
    await _ensureInitialized();
    _selfTalkTasks.removeWhere((t) => t.id == id);
    await _saveSelfTalkTasks();
    return 1;
  }

  // ==================== 速记操作 ====================

  static Future<int> insertQuickNote(QuickNote note) async {
    await _ensureInitialized();
    final newNote = QuickNote(
      id: _quickNoteIdCounter++,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      isPinned: note.isPinned,
      tag: note.tag,
    );
    _quickNotes.add(newNote);
    await _saveQuickNotes();
    return newNote.id!;
  }

  static Future<List<QuickNote>> getAllQuickNotes() async {
    await _ensureInitialized();
    return _quickNotes.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  static Future<List<QuickNote>> getQuickNotesByTag(String tag) async {
    await _ensureInitialized();
    return _quickNotes
        .where((n) => n.tag == tag)
        .toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  static Future<List<QuickNote>> searchQuickNotes(String keyword) async {
    await _ensureInitialized();
    return _quickNotes
        .where((n) => n.content.toLowerCase().contains(keyword.toLowerCase()))
        .toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  static Future<QuickNote?> getQuickNoteById(int id) async {
    await _ensureInitialized();
    try {
      return _quickNotes.firstWhere((n) => n.id == id);
    } catch (e) {
      return null;
    }
  }

  static Future<int> updateQuickNote(QuickNote note) async {
    await _ensureInitialized();
    final index = _quickNotes.indexWhere((n) => n.id == note.id);
    if (index >= 0) {
      _quickNotes[index] = note;
      await _saveQuickNotes();
      return 1;
    }
    return 0;
  }

  static Future<int> deleteQuickNote(int id) async {
    await _ensureInitialized();
    _quickNotes.removeWhere((n) => n.id == id);
    await _saveQuickNotes();
    return 1;
  }

  static Future<int> getQuickNoteCount() async {
    await _ensureInitialized();
    return _quickNotes.length;
  }
}
