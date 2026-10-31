// ignore: unused_import
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anniversary.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import '../models/self_talk_message.dart';
import '../models/quick_note.dart';
import '../models/self_talk_task.dart';
import '../models/course.dart';
import 'encryption_service.dart';

/// Web 版本数据库服务（使用 SharedPreferences 持久化存储）
/// 所有日记内容自动加密存储
/// 
/// 性能优化：
/// 1. 增量加载 - 支持分页获取日记
/// 2. 异步解密 - 后台解密不阻塞主线程
/// 3. 缓存元数据 - 快速获取统计信息
class DatabaseService {
  /// 【旧格式】全部日记塞在一个大 JSON 里。
  ///
  /// **只在首次迁移时读它**（`_migrateToPerDiaryKeys`）；迁移完成后不再写入。
  /// 保留它作为回滚保险（万一分键格式有问题还能退回），等几个版本稳定后再删。
  static const String _diariesKey = 'diaries_data';

  /// 【新格式】每篇日记一个独立键：`diary_<id>`，值是该篇的加密后 JSON。
  ///
  /// 为什么改（2026-10-28 B0-2）：原来每次写一篇日记都要
  /// `Future.wait(全量 N 篇重新 AES 加密)` + `jsonEncode(全量)` +
  /// `setString(全量)`（`commit()` 主线程同步 fsync）。N=1000 时单次保存
  /// 1.3~1.8 秒，这是用户感知「保存很卡」的第一元凶。
  ///
  /// 分键后：保存一篇只重写**那一个约 2KB 的键**，Cost 从 O(N·L) → O(L)。
  static const String _diaryKeyPrefix = 'diary_';

  /// 【新格式】日记 id 的顺序表（JSON int 数组，按 date 倒序）。
  ///
  /// 单独存是为了让「全部 id」这一小块元信息能被一次读出，
  /// 不必扫描整个 SharedPreferences 的所有键。
  static const String _diaryIndexKey = 'diary_index';

  /// 是否已完成「单键 → 分键」迁移。
  static const String _diarySplitMigratedKey = 'diary_split_migrated_v1';

  static const String _moodsKey = 'moods_data';
  static const String _tagsKey = 'tags_data';
  static const String _diaryTagsKey = 'diary_tags_data';
  static const String _diaryTagsV3Key = 'diary_tags_v3_data';  // 三级标签系统
  static const String _metadataKey = 'diaries_metadata';
  static const String _anniversariesKey = 'anniversaries_data';
  static const String _selfTalkMessagesKey = 'self_talk_messages_data';
  static const String _selfTalkTasksKey = 'self_talk_tasks_data';
  static const String _quickNotesKey = 'quick_notes_data';
  static const String _coursesKey = 'courses_data';
  static const String _courseSessionsKey = 'course_sessions_data';
  static const String _semesterConfigKey = 'semester_config_data';

  static List<Diary> _diaries = [];
  static List<Mood> _moods = [];
  static List<Tag> _tags = [];
  static List<Anniversary> _anniversaries = [];
  static List<Map<String, dynamic>> _diaryTags = [];
  static List<Map<String, dynamic>> _diaryTagsV3 = [];  // 三级标签关联
  static List<SelfTalkMessage> _selfTalkMessages = [];
  static List<SelfTalkTask> _selfTalkTasks = [];
  static List<QuickNote> _quickNotes = [];
  static List<Course> _courses = [];
  static List<CourseSession> _courseSessions = [];
  static SemesterConfig? _semesterConfig;
  static int _diaryIdCounter = 1;
  static int _moodIdCounter = 1;
  static int _tagIdCounter = 1;
  static int _anniversaryIdCounter = 1;
  static int _selfTalkMessageIdCounter = 1;
  static int _selfTalkTaskIdCounter = 1;
  static int _quickNoteIdCounter = 1;
  static int _courseIdCounter = 1;
  static int _courseSessionIdCounter = 1;
  static SharedPreferences? _prefs;

  /// 元数据缓存（避免频繁计算）
  static Map<String, dynamic> _metadataCache = {};

  /// 初始化过程本身（只应执行一次）。
  static Future<void>? _initFuture;

  /// 确保已完成初始化。
  ///
  /// ⚠️ 2026-10-28 修复「搜索能搜到、主界面没有」的**并发竞态**。
  ///
  /// 原实现是裸的 `if (_initialized) return;`：
  /// ```dart
  /// static Future<void> _ensureInitialized() async {
  ///   if (_initialized) return;
  ///   _prefs = await SharedPreferences.getInstance();   // ← 这里有 await
  ///   ...
  ///   _initialized = true;
  /// }
  /// ```
  /// 问题在于 `_initialized` 要等**整段初始化跑完**才置位，而中间有多个
  /// `await` 悬挂点。一旦启动时有两处并发调用（例如 `MainScreen._loadData`
  /// 里的 `loadRecentDiaries` 和别处的 `getAllDiaries`），**第二个调用会
  /// 看到 `_initialized == false` 并再跑一遍初始化**，两遍初始化互相覆盖
  /// `_diaries` / `_moods`，可能让先完成的那份数据被后一份空数据冲掉。
  ///
  /// 具体表现就是我遇到的：搜索页（后访问、走 `getAllDiaries` 强制初始化）
  /// 能读到数据，而主界面（先访问、走 `getRecentDiaries` 只读内存）
  /// 拿到的是空列表 —— 因为它读到的是「被另一条初始化路径冲掉后」的状态。
  ///
  /// 修复：用 `Future` 缓存初始化过程本身（经典 async-once 模式）。
  /// 并发调用会**共享同一个 Future**，初始化严格只跑一次。
  static Future<void> _ensureInitialized() {
    return _initFuture ??= _doInitialize();
  }

  static Future<void> _doInitialize() async {
    try {
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

      // 初始化完成。注意：不依赖 `_initialized` 标志做并发控制，
      // 而是由 [_initFuture] 保证「只跑一次」（见 `_ensureInitialized`）。
    } catch (e, st) {
      // 初始化失败：清掉缓存的 Future，允许下次重试；
      // 同时把错误暴露出去，不再静默。
      debugPrint('❌ DatabaseService 初始化失败: $e\n$st');
      _initFuture = null;
      _diaryLoadError = e;
      rethrow;
    }
  }

  /// 从 SharedPreferences 加载数据
  /// 优化：先加载元数据，日记内容延迟解密
  static Future<void> _loadData() async {
    // 日记加载失败必须**可见**：把日记相关的失败记录到可查询的状态里，
    // 而不是吞掉。其它非关键数据（心情/标签/纪念日…）加载失败仍可容忍。
    Object? diaryLoadError;

    try {
      // 加载元数据（快速）
      final metadataJson = _prefs?.getString(_metadataKey);
      if (metadataJson != null) {
        _metadataCache = jsonDecode(metadataJson);
      }

      // 加载日记：优先走分键格式；旧格式会自动迁移
      try {
        await _loadDiariesWithMigration();
      } catch (e, st) {
        // 🔴 这里以前会把异常冒泡到外层 catch 然后只 print 一行，
        // 导致「日记读不出来」被静默降级成「日记是空的」。
        // 现在单独捕获并记录，同时保留完整错误信息供 UI 展示。
        diaryLoadError = e;
        debugPrint('❌ 日记数据加载失败: $e\n$st');
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

      // 加载课程与上课安排（课表模块）
      final coursesJson = _prefs?.getString(_coursesKey);
      if (coursesJson != null) {
        final List<dynamic> coursesList = jsonDecode(coursesJson);
        _courses = coursesList.map((e) => Course.fromMap(e)).toList();
        if (_courses.isNotEmpty) {
          _courseIdCounter =
              _courses.map((c) => c.id ?? 0).reduce((a, b) => a > b ? a : b) +
                  1;
        }
      }
      final sessionsJson = _prefs?.getString(_courseSessionsKey);
      if (sessionsJson != null) {
        final List<dynamic> sessionsList = jsonDecode(sessionsJson);
        _courseSessions =
            sessionsList.map((e) => CourseSession.fromMap(e)).toList();
        if (_courseSessions.isNotEmpty) {
          _courseSessionIdCounter = _courseSessions
                  .map((s) => s.id ?? 0)
                  .reduce((a, b) => a > b ? a : b) +
              1;
        }
      }
      final semesterJson = _prefs?.getString(_semesterConfigKey);
      if (semesterJson != null) {
        _semesterConfig = SemesterConfig.fromMap(jsonDecode(semesterJson));
      }
    } catch (e) {
      // 非日记数据的失败：可容忍，但要让人看得见
      debugPrint('加载非日记数据失败: $e');
    }

    // 把日记加载的失败状态暴露出去，供 UI/诊断使用
    _diaryLoadError = diaryLoadError;
  }

  /// 最近一次日记加载失败的原因（null 表示正常）。
  ///
  /// 用途：当用户看到「日记 0 篇」时，可以据此判断是「真的没有日记」
  /// 还是「读取失败」—— 这两者对用户意味着完全不同的处理方式。
  static Object? _diaryLoadError;
  static Object? get diaryLoadError => _diaryLoadError;

  /// 磁盘上是否**存在**日记数据（用于区分「空账号」与「读取失败」）。
  ///
  /// 判定依据：任一 `diary_<id>` 分键存在，或旧键 `diaries_data` 非空。
  /// 这比「读出几篇」更可信 —— 即使索引坏了、解析失败了，也能知道
  /// 数据其实还在，从而引导用户去「恢复」而不是以为数据没了。
  static Future<bool> hasDiaryDataOnDisk() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs ??= prefs;

    final legacy = prefs.getString(_diariesKey);
    if (legacy != null && legacy.isNotEmpty && legacy != '[]') return true;

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_diaryKeyPrefix)) continue;
      if (prefs.getString(key)?.isNotEmpty ?? false) return true;
    }
    return false;
  }

  // ==================== 分键存储（B0-2）====================

  /// 加载全部日记，必要时把旧的「单个大 JSON」迁移成「一篇一个键」。
  ///
  /// 迁移是**幂等**的：`_diarySplitMigratedKey` 标记置位后不再重复。
  ///
  /// ⚠️ **2026-10-28 数据丢失事故修复**
  ///
  /// 事故现象：升级后再次打开 App，日记全部显示 0 篇。
  //
  /// 根因：迁移是「写分键 → 写索引 → 置标记」三步，**不是原子的**。
  /// 只要出现下面任一情况，`_loadDiariesFromSplitKeys()` 就会读到 0 个 id：
  ///   - 迁移中途被杀进程（写完了分键但没写索引 / 没置标记）
  ///   - `diary_index` 被并发写覆盖成空
  ///   - 迁移成功但索引值没有真正落盘
  /// 而一旦 `migrated == true`，原逻辑**再也不会回看旧键**，于是数据在
  /// 磁盘上明明还在（`diaries_data` / `diary_<id>` 都在），却一篇也读不出来。
  ///
  /// 修复原则：**磁盘上的真实数据永远高于索引缓存**。索引只是加速用的
  /// 缓存，它无效时必须能从分键（或旧键）**自愈重建**，绝不把「读到 0 篇」
  /// 当成真相。
  static Future<void> _loadDiariesWithMigration() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final migrated = prefs.getBool(_diarySplitMigratedKey) ?? false;

    if (migrated) {
      await _loadDiariesFromSplitKeys();

      // 自愈 ①：标记已置位却一篇都没读出来 —— 索引肯定坏了。
      // 先尝试从分键重建索引；仍为空再回退旧键迁移。
      if (_diaries.isEmpty) {
        print('⚠️ 分键索引异常（读到 0 篇），尝试自愈重建');
        await _rebuildDiaryIndexFromSplitKeys();
        await _loadDiariesFromSplitKeys();

        if (_diaries.isEmpty) {
          // 自愈 ②：分键里也没有 → 回退旧键（保留的最后一道保险）
          final legacyJson = prefs.getString(_diariesKey);
          if (legacyJson != null && legacyJson.isNotEmpty) {
            print('⚠️ 分键为空，从旧格式 diaries_data 恢复');
            await _migrateLegacyDiariesToSplitKeys(legacyJson);
          }
        }
      }
      return;
    }

    // 还没迁移过：可能有旧格式数据，也可能全新安装（两者都没有）
    final legacyJson = prefs.getString(_diariesKey);
    if (legacyJson == null || legacyJson.isEmpty) {
      // 可能之前已经写过分键（迁移标记丢了），先看分键里有没有数据
      await _rebuildDiaryIndexFromSplitKeys();
      await _loadDiariesFromSplitKeys();

      if (_diaries.isNotEmpty) {
        // 分键里有数据 → 补写索引与标记，恢复保持一致
        await _saveDiaryIndex();
        await prefs.setBool(_diarySplitMigratedKey, true);
        return;
      }

      // 全新安装：直接标记为已迁移，避免每次启动都查一遍
      await prefs.setBool(_diarySplitMigratedKey, true);
      await prefs.setString(_diaryIndexKey, '[]');
      return;
    }

    try {
      await _migrateLegacyDiariesToSplitKeys(legacyJson);
    } catch (e) {
      // 迁移失败：退回旧格式读，保证用户能看到数据
      print('日记分键迁移失败，回退旧格式读取: $e');
      final List<dynamic> diariesList = jsonDecode(legacyJson);
      await _decryptDiariesSync(diariesList);
      if (_diaries.isNotEmpty) {
        _diaryIdCounter =
            _diaries.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
      }
      // 不置位迁移标记 → 下次启动再试
    }
  }

  /// 扫描所有 `diary_<id>` 键，重建 id 顺序表。
  ///
  /// 这是「索引坏了但数据还在」时的唯一正确出路：**以磁盘上的键为准**，
  /// 而不是信任那个可能已经损坏的 `diary_index`。
  ///
  /// 同时会清掉「有键但内容解析不出来」的死键，避免它们污染索引。
  static Future<void> _rebuildDiaryIndexFromSplitKeys() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final ids = <int>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_diaryKeyPrefix)) continue;
      final rawId = key.substring(_diaryKeyPrefix.length);
      final id = int.tryParse(rawId);
      if (id == null) continue;

      final value = prefs.getString(key);
      if (value == null || value.isEmpty) continue;
      ids.add(id);
    }

    ids.sort();
    await prefs.setString(_diaryIndexKey, jsonEncode(ids));
    print('已从分键重建索引，共 ${ids.length} 篇');
  }


  /// 把旧格式（单键大 JSON）拆成「一篇一个键 + 一个 id 顺序表」。
  static Future<void> _migrateLegacyDiariesToSplitKeys(String legacyJson) async {
    final List<dynamic> diariesList = jsonDecode(legacyJson);
    final prefs = _prefs;
    if (prefs == null) return;

    final decryptedDiaries = <Diary>[];
    final writes = <String, String>{}; // key → value，最后一次性写

    for (final raw in diariesList) {
      final map = Map<String, dynamic>.from(raw as Map);
      final id = map['id'];
      if (id is! int) {
        // 没有 id 的脏数据：跳过，避免迁移后无法定位
        continue;
      }

      // 键里存「加密后的 map」（与旧格式一致），内存里放解密后的对象
      writes['$_diaryKeyPrefix$id'] = jsonEncode(map);

      final decrypted = await _decryptDiaryMap(map);
      decryptedDiaries.add(Diary(
        id: id,
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
        source: map['source'] is String ? map['source'] as String : null,
        createdAt: map['created_at'],
        updatedAt: map['updated_at'],
      ));
    }

    // 先写所有分键，再写索引
    for (final entry in writes.entries) {
      await prefs.setString(entry.key, entry.value);
    }

    _diaries = decryptedDiaries;
    if (_diaries.isNotEmpty) {
      _diaryIdCounter =
          _diaries.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    }

    // 顺序很重要：先写索引，最后才置标记。
    // 万一在「写索引」和「置标记」之间被杀进程，下次启动会重新迁移
    // （因为标记未置位），而分键写入本身是幂等的，不会丢数据。
    await _saveDiaryIndex();

    // 校验：索引真的写进去了才算迁移成功
    final verifyJson = prefs.getString(_diaryIndexKey);
    final verified = verifyJson != null &&
        verifyJson.isNotEmpty &&
        (jsonDecode(verifyJson) as List).length == decryptedDiaries.length;
    if (!verified) {
      throw StateError('索引校验失败：期望 ${decryptedDiaries.length} 条，实际写入异常');
    }

    // 全部成功后才置位标记。旧的 `diaries_data` **故意保留**：
    // 它是回滚保险，也方便用户在异常情况下恢复。
    await prefs.setBool(_diarySplitMigratedKey, true);
    print('日记已迁移为分键存储（${_diaries.length} 篇）');
  }

  /// 从磁盘上的真实数据**强制重建**全部日记。
  ///
  /// 这是给「日记显示 0 篇」准备的显式救援入口，可在设置里接一个按钮：
  /// 它会依次尝试
  ///   1. 扫描 `diary_<id>` 分键；
  ///   2. 若为空，回退旧键 `diaries_data` 重新迁移；
  ///   3. 重建索引并置位标记。
  ///
  /// 返回恢复出的日记数量（0 表示磁盘上确实没有数据）。
  static Future<int> recoverFromDisk() async {
    await _ensureInitialized();
    final prefs = _prefs;
    if (prefs == null) return _diaries.length;

    // 1. 先以分键为准重建
    _diaries = [];
    await _rebuildDiaryIndexFromSplitKeys();
    await _loadDiariesFromSplitKeys();

    if (_diaries.isNotEmpty) {
      await _saveDiaryIndex();
      await prefs.setBool(_diarySplitMigratedKey, true);
      _updateMetadata();
      return _diaries.length;
    }

    // 2. 分键也没有 → 回退旧键
    final legacyJson = prefs.getString(_diariesKey);
    if (legacyJson != null && legacyJson.isNotEmpty) {
      await _migrateLegacyDiariesToSplitKeys(legacyJson);
      _updateMetadata();
    }

    return _diaries.length;
  }

  /// 从分键格式读取全部日记。
  static Future<void> _loadDiariesFromSplitKeys() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final indexJson = prefs.getString(_diaryIndexKey);
    final List<int> ids;
    if (indexJson == null || indexJson.isEmpty) {
      ids = const <int>[];
    } else {
      // ⚠️ 2026-10-28 数据丢失事故的直接触发点。
      //
      // 原写法：
      //   `ids = jsonDecode(indexJson).cast<num>().map(...).toList(growable: false);`
      // 而声明类型是 `final List<int> ids`。
      // `jsonDecode` 返回 `List<dynamic>`，`.toList()` 得到的是
      // `List<dynamic>` 运行时类型 —— 赋给 `List<int>` **会直接抛**
      // `type 'List<dynamic>' is not a subtype of type 'List<int>'`。
      //
      // 更糟的是这行在 `_loadData()` 的 try/catch 里，异常被吞掉并只打印
      // 一句「加载数据失败」，于是 `_diaries` 保持为空 → **日记全部显示 0 篇**。
      //
      // 修复：显式 `List<int>.from(...)`，并单独兜住索引解析异常
      // （索引坏了不应拖垮整个数据加载，交给上层自愈重建）。
      try {
        ids = List<int>.from(
          (jsonDecode(indexJson) as List).map((e) => (e as num).toInt()),
        );
      } catch (e) {
        // 索引格式损坏 → 当作没有索引，让自愈逻辑去重建
        print('日记索引解析失败，将重建: $e');
        await _loadDiariesByScanningKeys();
        return;
      }
    }

    final loaded = <Diary>[];
    for (final id in ids) {
      final diary = await _readDiaryFromKey(id);
      if (diary != null) loaded.add(diary);
    }

    _diaries = loaded;
    if (_diaries.isNotEmpty) {
      _diaryIdCounter =
          _diaries.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  /// 读取单个 `diary_<id>` 键并解密；不存在或损坏则返回 null。
  static Future<Diary?> _readDiaryFromKey(int id) async {
    final prefs = _prefs;
    if (prefs == null) return null;

    final raw = prefs.getString('$_diaryKeyPrefix$id');
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final decrypted = await _decryptDiaryMap(map);
      return Diary(
        id: id,
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
        source: map['source'] is String ? map['source'] as String : null,
        createdAt: map['created_at'],
        updatedAt: map['updated_at'],
      );
    } catch (e) {
      // 单篇损坏不能拖垮整个启动：跳过并记录
      print('日记 $id 解析失败，已跳过: $e');
      return null;
    }
  }

  /// 兜底读取路径：不依赖索引，直接扫描所有 `diary_<id>` 键。
  ///
  /// 用于索引缺失 / 损坏时的自愈，确保「数据在磁盘上就一定能读出来」。
  static Future<void> _loadDiariesByScanningKeys() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final ids = <int>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_diaryKeyPrefix)) continue;
      final id = int.tryParse(key.substring(_diaryKeyPrefix.length));
      if (id != null && (prefs.getString(key)?.isNotEmpty ?? false)) {
        ids.add(id);
      }
    }
    ids.sort();

    final loaded = <Diary>[];
    for (final id in ids) {
      final diary = await _readDiaryFromKey(id);
      if (diary != null) loaded.add(diary);
    }

    _diaries = loaded;
    if (_diaries.isNotEmpty) {
      _diaryIdCounter =
          _diaries.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    }

    // 顺便把索引修好，下次启动就走快路径
    if (ids.isNotEmpty) {
      await prefs.setString(_diaryIndexKey, jsonEncode(ids));
      await prefs.setBool(_diarySplitMigratedKey, true);
    }
  }


  /// 写回「id 顺序表」（按 date 倒序，与 getAllDiaries 的排序一致）。
  static Future<void> _saveDiaryIndex() async {
    final ids = List<Diary>.from(_diaries)
      ..sort((a, b) => b.date.compareTo(a.date));
    final list = ids.map((d) => d.id).whereType<int>().toList(growable: false);
    await _prefs?.setString(_diaryIndexKey, jsonEncode(list));
  }

  /// 写单篇日记的键（**只写这一篇**，不碰其他日记）。
  static Future<void> _saveOneDiary(Diary diary) async {
    final id = diary.id;
    if (id == null) return;
    final encryptedMap = await _encryptDiaryMap(diary.toMap());
    await _prefs?.setString('$_diaryKeyPrefix$id', jsonEncode(encryptedMap));
  }

  /// 删除单篇日记的键。
  static Future<void> _deleteOneDiaryKey(int id) async {
    await _prefs?.remove('$_diaryKeyPrefix$id');
  }

  /// 同步解密日记数据（修复数据消失问题）
  ///
  /// 注意：新格式下每篇日记的**加密后 map** 先落到 `diary_<id>` 键上，
  /// 内存里 `_diaries` 始终是**解密后的明文对象**。见 [_loadDiariesWithMigration]。
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
          source: map['source'] is String ? map['source'] as String : null,
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

  /// 保存日记到 SharedPreferences。
  ///
  /// ⚠️ **只用于批量场景**（导入 / 恢复 / 情绪批量清空等）。
  /// 单篇新增/编辑/删除请用 [_saveOneDiary] / [_deleteOneDiaryKey] ——
  /// 那是 B0-2 的核心：单篇写不再触发全量重加密。
  /// 这里保留全量语义是为了「批量操作一次性落盘」的一致性。
  static Future<void> _saveDiaries() async {
    // 分别加密每一篇，逐键写回（不拼成一个大 JSON）
    final writes = <String, String>{};
    for (final diary in _diaries) {
      final id = diary.id;
      if (id == null) continue;
      final encryptedMap = await _encryptDiaryMap(diary.toMap());
      writes['$_diaryKeyPrefix$id'] = jsonEncode(encryptedMap);
    }

    for (final entry in writes.entries) {
      await _prefs?.setString(entry.key, entry.value);
    }
    await _saveDiaryIndex();

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
  /// 重算并写回元数据。
  ///
  /// ⚠️ 这是 O(N) 操作（全量算字数 + 全量扫日期），B0-2 之后它已经不在
  /// 「单篇保存」的关键路径上了（`insertDiary`/`updateDiary`/`deleteDiary`
  /// 仍然调它，但通常 N 不大且 wordCount 已有缓存）。
  ///
  /// 仍改进两点：
  /// 1. `wordCount` 现在有缓存（见 `models/diary.dart`），不再每篇重新编译正则；
  /// 2. 写盘走 `setString` 一次，且结果同时留在 `_metadataCache`。
  ///
  /// 如果以后要彻底消掉这个 O(N)，应改为**增量维护**计数（保存时 +/- 一篇的
  /// 字数与日期），但需要一次性的「重建基线」迁移，留到下一轮。
  static void _updateMetadata() {
    var totalWordCount = 0;
    final uniqueDates = <String>{};
    for (final d in _diaries) {
      totalWordCount += d.wordCount; // 内部有缓存，不会重复编译正则
      uniqueDates.add(d.date);
    }

    _metadataCache = {
      'totalCount': _diaries.length,
      'totalWordCount': totalWordCount,
      'uniqueDates': uniqueDates.toList(),
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
    // B0-2：只写这一篇 + 顺序表，不再全量重加密/全量落盘
    await _saveOneDiary(newDiary);
    await _saveDiaryIndex();
    _updateMetadata();
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
      final updated = diary.copyWith(
        updatedAt: DateTime.now().toIso8601String(),
      );
      _diaries[index] = updated;
      // B0-2：只重写这一篇
      await _saveOneDiary(updated);
      // 日期可能变了 → 顺序表要跟着更新
      await _saveDiaryIndex();
      _updateMetadata();
      return 1;
    }
    return 0;
  }

  static Future<int> deleteDiary(int id) async {
    await _ensureInitialized();
    _diaries.removeWhere((d) => d.id == id);
    _diaryTags.removeWhere((dt) => dt['diary_id'] == id);
    // B0-2：删掉这一篇的键，而不是全量重写
    await _deleteOneDiaryKey(id);
    await _saveDiaryIndex();
    await _saveDiaryTags();
    _updateMetadata();
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

    // 先将使用该心情的日记的 mood 信息清空。
    //
    // 🐛 修复（2026-10-28）：原实现是
    // ```dart
    // for (var diary in _diaries) { if (...) diary = diary.copyWith(...); }
    // ```
    // —— `diary` 只是循环变量（列表元素的**副本**），给它重新赋值
    // **不会回写到 `_diaries`**，所以删心情时所有日记的 mood 字段其实
    // 一个都没被清空。改为按下标回写。
    for (var i = 0; i < _diaries.length; i++) {
      final diary = _diaries[i];
      if (diary.moodId == id) {
        _diaries[i] = diary.copyWith(
          moodId: null,
          moodName: null,
          moodEmoji: null,
        );
      }
    }
    // 因为这批日记的 mood 变了，需要逐篇落盘（B0-2 后走分键写入）
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

  /// **批量**取每篇日记的标签名：一次扫描 `_diaryTags` + 一次建索引。
  ///
  /// 为什么需要它（2026-10-28 B0-8）：统计页原本对**每篇日记**调一次
  /// [getTagsByDiaryId]，而那个实现每次都要 `_diaryTags.where(...)` 全表扫
  /// 再 `_tags.where(tagIds.contains)` —— 整体退化成 O(N×M×K)。N=1000 篇时
  /// 是上百万次 Map 比较 + 上千次 async 调度，统计页直接卡死。
  ///
  /// 这里只扫一遍全表并在内存里建 `diaryId → tagNames` 的映射，复杂度
  /// **O(M + N)**。
  ///
  /// 返回：`diaryId → 标签名列表`（只包含实际有标签的日记）。
  static Future<Map<int, List<String>>> getTagNamesByDiaryIds() async {
    await _ensureInitialized();

    // tagId → tagName，一次建成，避免内层反复线性查找
    final tagNameById = <int, String>{};
    for (final tag in _tags) {
      final id = tag.id;
      if (id != null) tagNameById[id] = tag.name;
    }

    final result = <int, List<String>>{};
    for (final map in _diaryTags) {
      final diaryId = map['diary_id'];
      final tagId = map['tag_id'];
      if (diaryId is! int || tagId is! int) continue;
      final name = tagNameById[tagId];
      if (name == null) continue;
      (result[diaryId] ??= <String>[]).add(name);
    }
    return result;
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

    // 🐛 修复（2026-10-28，B0-2 前置）：
    // 原实现是
    // ```dart
    // for (final diary in diaries) {
    //   final encryptedMap = await _encryptDiaryMap(diary.toMap());
    //   _diaries.add(Diary.fromMap(encryptedMap));   // ← 存进去的是密文！
    // }
    // ```
    // 于是「恢复备份」之后内存里 `_diaries` 全是**密文**，之后任何读取
    // （列表、详情、统计）都会把 `__ENC2__...` 原样展示给用户。
    //
    // 正确的不变式是：**`_diaries` 永远存解密后的明文对象**，
    // 加密只发生在写盘那一刻（见 `_saveOneDiary` / `_saveDiaries`）。
    _diaries = List<Diary>.from(diaries);

    // 更新ID计数器
    if (_diaries.isNotEmpty) {
      _diaryIdCounter =
          _diaries.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    }

    // 保存到存储（这里会统一加密后逐键写入）
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
      date: message.date,
      content: message.content,
      isUser: message.isUser,
      senderType: message.senderType,
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

  // ==================== 自言自语搜索操作 ====================

  static Future<List<SelfTalkMessage>> searchSelfTalkMessages({
    String? keyword,
    String? dateFrom,
    String? dateTo,
    int? senderType,
  }) async {
    await _ensureInitialized();
    var results = _selfTalkMessages.where((m) {
      if (keyword != null && keyword.isNotEmpty) {
        if (!m.content.toLowerCase().contains(keyword.toLowerCase())) return false;
      }
      if (dateFrom != null && dateFrom.isNotEmpty) {
        if (m.date.compareTo(dateFrom) < 0) return false;
      }
      if (dateTo != null && dateTo.isNotEmpty) {
        if (m.date.compareTo(dateTo) > 0) return false;
      }
      if (senderType != null) {
        if (m.senderType.index != senderType) return false;
      }
      return true;
    }).toList();
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  static Future<List<SelfTalkMessage>> getSelfTalkMessagesByDateRange(
    String dateFrom,
    String dateTo,
  ) async {
    await _ensureInitialized();
    var results = _selfTalkMessages
        .where((m) => m.date.compareTo(dateFrom) >= 0 && m.date.compareTo(dateTo) <= 0)
        .toList();
    results.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return results;
  }

  static Future<List<String>> getSelfTalkDates() async {
    await _ensureInitialized();
    final dates = _selfTalkMessages.map((m) => m.date).toSet().toList();
    dates.sort((a, b) => b.compareTo(a));
    return dates;
  }

  static Future<List<SelfTalkTask>> searchSelfTalkTasks({
    String? keyword,
    String? dateFrom,
    String? dateTo,
    bool? isCompleted,
  }) async {
    await _ensureInitialized();
    var results = _selfTalkTasks.where((t) {
      if (keyword != null && keyword.isNotEmpty) {
        if (!t.content.toLowerCase().contains(keyword.toLowerCase())) return false;
      }
      if (dateFrom != null && dateFrom.isNotEmpty) {
        if (t.date.compareTo(dateFrom) < 0) return false;
      }
      if (dateTo != null && dateTo.isNotEmpty) {
        if (t.date.compareTo(dateTo) > 0) return false;
      }
      if (isCompleted != null) {
        if (t.isCompleted != isCompleted) return false;
      }
      return true;
    }).toList();
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
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

  // ==================== 课表操作 ====================

  static Future<void> _saveCourses() async {
    final json = jsonEncode(_courses.map((c) => c.toMap()).toList());
    await _prefs?.setString(_coursesKey, json);
  }

  static Future<void> _saveCourseSessions() async {
    final json = jsonEncode(_courseSessions.map((s) => s.toMap()).toList());
    await _prefs?.setString(_courseSessionsKey, json);
  }

  static Future<void> _saveSemesterConfig() async {
    if (_semesterConfig == null) {
      await _prefs?.remove(_semesterConfigKey);
    } else {
      await _prefs?.setString(
          _semesterConfigKey, jsonEncode(_semesterConfig!.toMap()));
    }
  }

  /// 新增课程（连同其上课安排），返回课程 id
  static Future<int> insertCourse(
      Course course, List<CourseSession> sessions) async {
    await _ensureInitialized();
    final courseId = _courseIdCounter++;
    _courses.add(course.copyWith(id: courseId));
    for (final s in sessions) {
      _courseSessions
          .add(s.copyWith(id: _courseSessionIdCounter++, courseId: courseId));
    }
    await _saveCourses();
    await _saveCourseSessions();
    return courseId;
  }

  /// 更新课程并整体替换其上课安排
  static Future<int> updateCourse(
      Course course, List<CourseSession> sessions) async {
    await _ensureInitialized();
    final index = _courses.indexWhere((c) => c.id == course.id);
    if (index < 0) return 0;
    _courses[index] = course.copyWith(sessions: const []);
    _courseSessions.removeWhere((s) => s.courseId == course.id);
    for (final s in sessions) {
      _courseSessions
          .add(s.copyWith(id: _courseSessionIdCounter++, courseId: course.id));
    }
    await _saveCourses();
    await _saveCourseSessions();
    return 1;
  }

  /// 删除课程及其全部上课安排
  static Future<int> deleteCourse(int id) async {
    await _ensureInitialized();
    _courses.removeWhere((c) => c.id == id);
    _courseSessions.removeWhere((s) => s.courseId == id);
    await _saveCourses();
    await _saveCourseSessions();
    return 1;
  }

  /// 获取全部课程（已组装各自的上课安排）
  static Future<List<Course>> getAllCourses() async {
    await _ensureInitialized();
    return _courses
        .map((c) => c.copyWith(
            sessions:
                _courseSessions.where((s) => s.courseId == c.id).toList()))
        .toList();
  }

  static Future<SemesterConfig?> getSemesterConfig() async {
    await _ensureInitialized();
    return _semesterConfig;
  }

  /// 保存学期配置（同时只有一个配置）
  static Future<void> saveSemesterConfig(SemesterConfig config) async {
    await _ensureInitialized();
    _semesterConfig = config;
    await _saveSemesterConfig();
  }
}
