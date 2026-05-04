import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/anniversary.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import '../models/self_talk_message.dart';
import '../models/quick_note.dart';
import '../models/self_talk_task.dart';
import 'encryption_service.dart';

/// Native 版本数据库服务（使用 SQLite）
/// 所有日记内容自动加密存储
class DatabaseService {
  static Database? _database;
  static const String _databaseName = 'diary_app.db';
  static const int _databaseVersion = 13; // 版本13：自言自语表添加 replied_to_sender_type 实现系统回复精确定位

  // 表名
  static const String tableDiaries = 'diaries';
  static const String tableMoods = 'moods';
  static const String tableTags = 'tags';
  static const String tableDiaryTags = 'diary_tags';
  static const String tableAnniversaries = 'anniversaries';
  static const String tableSelfTalkMessages = 'self_talk_messages';
  static const String tableSelfTalkTasks = 'self_talk_tasks';
  static const String tableQuickNotes = 'quick_notes';

  // 获取数据库实例
  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  // 初始化数据库
  static Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);

    // 初始化加密服务
    await EncryptionService.initialize();

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // 创建表
  static Future<void> _onCreate(Database db, int version) async {
    // 日记表
    await db.execute('''
      CREATE TABLE $tableDiaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        date TEXT NOT NULL,
        images TEXT,
        mood_id INTEGER,
        mood_name TEXT,
        mood_emoji TEXT,
        weather TEXT,
        is_favorite INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        is_encrypted INTEGER DEFAULT 1
      )
    ''');

    // 心情表
    await db.execute('''
      CREATE TABLE $tableMoods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        emoji TEXT,
        color TEXT,
        sort_order INTEGER DEFAULT 0
      )
    ''');

    // 标签表
    await db.execute('''
      CREATE TABLE $tableTags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color TEXT,
        usage_count INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    // 日记标签关联表
    await db.execute('''
      CREATE TABLE $tableDiaryTags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        diary_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        FOREIGN KEY (diary_id) REFERENCES $tableDiaries (id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES $tableTags (id) ON DELETE CASCADE
      )
    ''');

    // 纪念日表
    await db.execute('''
      CREATE TABLE $tableAnniversaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        quote TEXT,
        created_at TEXT
      )
    ''');

    // 三级标签系统关联表（V3版本，支持String类型的tagId）
    await db.execute('''
      CREATE TABLE diary_tags_v3 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        diary_id INTEGER NOT NULL,
        tag_id TEXT NOT NULL,
        created_at TEXT,
        FOREIGN KEY (diary_id) REFERENCES $tableDiaries (id) ON DELETE CASCADE
      )
    ''');

    // 自言自语消息表（v12：彻底移除 diary_id，与日记系统物理独立）
    await db.execute('''
      CREATE TABLE $tableSelfTalkMessages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        content TEXT,
        is_user INTEGER DEFAULT 1,
        sender_type INTEGER DEFAULT 0,
        replied_to_sender_type INTEGER,
        created_at TEXT
      )
    ''');

    // 自言自语任务表（v12：彻底移除 diary_id，与日记系统物理独立）
    await db.execute('''
      CREATE TABLE $tableSelfTalkTasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id INTEGER,
        date TEXT NOT NULL,
        content TEXT,
        deadline TEXT,
        is_completed INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    // 速记表
    await db.execute('''
      CREATE TABLE $tableQuickNotes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        is_pinned INTEGER DEFAULT 0,
        tag TEXT
      )
    ''');

    // 插入默认心情
    await _insertDefaultMoods(db);
  }

  // 插入默认心情
  static Future<void> _insertDefaultMoods(Database db) async {
    final defaultMoods = Mood.defaultMoods;
    for (var i = 0; i < defaultMoods.length; i++) {
      final mood = defaultMoods[i];
      await db.insert(tableMoods, {
        'name': mood.name,
        'emoji': mood.emoji,
        'color': mood.color,
        'sort_order': i,
      });
    }
  }

  // 升级数据库
  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 版本2添加加密支持
      await db.execute(
          'ALTER TABLE $tableDiaries ADD COLUMN is_encrypted INTEGER DEFAULT 0');
    }
    if (oldVersion < 3) {
      // 版本3添加三级标签系统V3支持
      await db.execute('''
        CREATE TABLE diary_tags_v3 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          diary_id INTEGER NOT NULL,
          tag_id TEXT NOT NULL,
          created_at TEXT,
          FOREIGN KEY (diary_id) REFERENCES $tableDiaries (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 4) {
      // 版本4添加自言自语消息支持
      // v12 重构：此处保留历史结构，最终由 v12 迁移统一处理
      await db.execute('''
        CREATE TABLE $tableSelfTalkMessages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          diary_id INTEGER,
          date TEXT NOT NULL,
          content TEXT,
          is_user INTEGER DEFAULT 1,
          created_at TEXT
        )
      ''');
    }
    if (oldVersion < 5) {
      // 版本5添加自言自语任务支持
      // v12 重构：此处保留历史结构，最终由 v12 迁移统一处理
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableSelfTalkTasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id INTEGER,
          diary_id INTEGER,
          date TEXT NOT NULL,
          content TEXT,
          deadline TEXT,
          is_completed INTEGER DEFAULT 0,
          created_at TEXT
        )
      ''');
    }
    if (oldVersion < 6) {
      // 版本6：为已有用户补建可能缺失的自言自语表
      // v12 重构：此处保留历史结构，最终由 v12 迁移统一处理
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableSelfTalkMessages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          diary_id INTEGER,
          date TEXT NOT NULL,
          content TEXT,
          is_user INTEGER DEFAULT 1,
          created_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableSelfTalkTasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id INTEGER,
          diary_id INTEGER,
          date TEXT NOT NULL,
          content TEXT,
          deadline TEXT,
          is_completed INTEGER DEFAULT 0,
          created_at TEXT
        )
      ''');
    }
    if (oldVersion < 7) {
      // 版本7：为自言自语消息表添加 sender_type 字段
      try {
        await db.execute('ALTER TABLE $tableSelfTalkMessages ADD COLUMN sender_type INTEGER DEFAULT 0');
      } catch (e) {
        // 列已存在时忽略错误
      }
    }
    if (oldVersion < 8) {
      // 版本8：修复 sender_type 字段可能缺失的问题（确保列存在）
      try {
        await db.execute('ALTER TABLE $tableSelfTalkMessages ADD COLUMN sender_type INTEGER DEFAULT 0');
      } catch (e) {
        // 列已存在时忽略错误
      }
    }
    if (oldVersion < 9) {
      // 版本9：自言自语重构，完全独立于日记系统
      // 表结构不变（diary_id 列保留以兼容旧数据），但逻辑上不再关联日记
      // 新消息不再写入 diary_id，删除消息不再修改日记正文
    }
    if (oldVersion < 10) {
      // 版本10：新增速记功能
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableQuickNotes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT,
          is_pinned INTEGER DEFAULT 0,
          tag TEXT
        )
      ''');
    }
    if (oldVersion < 11) {
      // 版本11：确保速记表存在（修复部分用户 v10 表未创建的问题）
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableQuickNotes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT,
          is_pinned INTEGER DEFAULT 0,
          tag TEXT
        )
      ''');
    }
    if (oldVersion < 12) {
      // 版本12：彻底移除自言自语表中的 diary_id 列，实现与日记系统物理独立
      await _migrateSelfTalkTablesRemoveDiaryId(db);
    }
    if (oldVersion < 13) {
      // 版本13：添加 replied_to_sender_type 字段，实现系统回复精确定位
      try {
        await db.execute('ALTER TABLE $tableSelfTalkMessages ADD COLUMN replied_to_sender_type INTEGER');
      } catch (e) {
        // 列已存在时忽略错误
      }
    }
  }

  /// v12 迁移：移除 self_talk_messages / self_talk_tasks 中的 diary_id 列
  static Future<void> _migrateSelfTalkTablesRemoveDiaryId(Database db) async {
    // 迁移 self_talk_messages 表
    await db.execute('''
      CREATE TABLE ${tableSelfTalkMessages}_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        content TEXT,
        is_user INTEGER DEFAULT 1,
        sender_type INTEGER DEFAULT 0,
        replied_to_sender_type INTEGER,
        created_at TEXT
      )
    ''');
    await db.execute('''
      INSERT INTO ${tableSelfTalkMessages}_new (id, date, content, is_user, sender_type, replied_to_sender_type, created_at)
      SELECT id, date, content, is_user, sender_type, NULL, created_at
      FROM $tableSelfTalkMessages
    ''');
    await db.execute('DROP TABLE $tableSelfTalkMessages');
    await db.execute('ALTER TABLE ${tableSelfTalkMessages}_new RENAME TO $tableSelfTalkMessages');

    // 迁移 self_talk_tasks 表
    await db.execute('''
      CREATE TABLE ${tableSelfTalkTasks}_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id INTEGER,
        date TEXT NOT NULL,
        content TEXT,
        deadline TEXT,
        is_completed INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');
    await db.execute('''
      INSERT INTO ${tableSelfTalkTasks}_new (id, message_id, date, content, deadline, is_completed, created_at)
      SELECT id, message_id, date, content, deadline, is_completed, created_at
      FROM $tableSelfTalkTasks
    ''');
    await db.execute('DROP TABLE $tableSelfTalkTasks');
    await db.execute('ALTER TABLE ${tableSelfTalkTasks}_new RENAME TO $tableSelfTalkTasks');
  }

  // ==================== 日记操作 ====================

  static Future<List<Diary>> getAllDiaries() async {
    final db = await database;
    final maps = await db.query(tableDiaries, orderBy: 'date DESC');

    // 解密数据
    final decryptedMaps = await Future.wait(
      maps.map((map) => _decryptDiaryMap(map)),
    );

    return decryptedMaps.map((map) => Diary.fromMap(map)).toList();
  }

  static Future<List<Diary>> getDiariesByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      tableDiaries,
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'created_at DESC',
    );

    // 解密数据
    final decryptedMaps = await Future.wait(
      maps.map((map) => _decryptDiaryMap(map)),
    );

    return decryptedMaps.map((map) => Diary.fromMap(map)).toList();
  }

  static Future<List<Diary>> getDiariesByMonth(int year, int month) async {
    final monthStr = month.toString().padLeft(2, '0');
    final db = await database;
    final maps = await db.query(
      tableDiaries,
      where: 'date LIKE ?',
      whereArgs: ['$year-$monthStr%'],
    );

    // 解密数据
    final decryptedMaps = await Future.wait(
      maps.map((map) => _decryptDiaryMap(map)),
    );

    return decryptedMaps.map((map) => Diary.fromMap(map)).toList();
  }

  static Future<Diary?> getDiary(int id) async {
    final db = await database;
    final maps = await db.query(
      tableDiaries,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      final decryptedMap = await _decryptDiaryMap(maps.first);
      return Diary.fromMap(decryptedMap);
    }
    return null;
  }

  static Future<int> insertDiary(Diary diary) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // 加密敏感数据
    final encryptedMap = await _encryptDiaryMap(diary.toMap());
    encryptedMap['created_at'] = now;
    encryptedMap['updated_at'] = now;
    encryptedMap['is_encrypted'] = 1;

    return await db.insert(tableDiaries, encryptedMap);
  }

  static Future<int> updateDiary(Diary diary) async {
    final db = await database;

    // 加密敏感数据
    final map = diary.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    map['is_encrypted'] = 1;

    final encryptedMap = await _encryptDiaryMap(map);

    return await db.update(
      tableDiaries,
      encryptedMap,
      where: 'id = ?',
      whereArgs: [diary.id],
    );
  }

  static Future<int> deleteDiary(int id) async {
    final db = await database;
    // 先删除关联的标签
    await db.delete(
      tableDiaryTags,
      where: 'diary_id = ?',
      whereArgs: [id],
    );
    // 删除日记
    return await db.delete(
      tableDiaries,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> getDiaryCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM $tableDiaries');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<int> getTotalWordCount() async {
    // 获取所有日记并计算字数（需要解密）
    final diaries = await getAllDiaries();
    return diaries.fold<int>(0, (sum, d) => sum + d.wordCount);
  }

  static Future<DateTime?> getFirstDiaryDate() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT date FROM $tableDiaries ORDER BY date ASC LIMIT 1');
    if (result.isNotEmpty) {
      return DateTime.tryParse(result.first['date'] as String);
    }
    return null;
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

  // ==================== 心情操作 ====================

  static Future<List<Mood>> getAllMoods() async {
    final db = await database;
    final maps = await db.query(tableMoods, orderBy: 'sort_order ASC');
    return maps.map((map) => Mood.fromMap(map)).toList();
  }

  static Future<Mood?> getMood(int id) async {
    final db = await database;
    final maps = await db.query(
      tableMoods,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Mood.fromMap(maps.first);
    }
    return null;
  }

  static Future<int> insertMood(Mood mood) async {
    final db = await database;
    return await db.insert(tableMoods, mood.toMap());
  }

  static Future<int> updateMood(Mood mood) async {
    final db = await database;
    return await db.update(
      tableMoods,
      mood.toMap(),
      where: 'id = ?',
      whereArgs: [mood.id],
    );
  }

  // 查询使用该心情的日记数量
  static Future<int> getDiaryCountByMood(int moodId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableDiaries WHERE mood_id = ?',
      [moodId],
    );
    return result.first['count'] as int? ?? 0;
  }

  static Future<int> deleteMood(int id) async {
    final db = await database;
    // 先将使用该心情的日记的 mood_id 设为 null
    await db.update(
      tableDiaries,
      {'mood_id': null, 'mood_name': null, 'mood_emoji': null},
      where: 'mood_id = ?',
      whereArgs: [id],
    );
    // 删除心情
    return await db.delete(
      tableMoods,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== 标签操作 ====================

  static Future<List<Tag>> getAllTags() async {
    final db = await database;
    final maps = await db.query(tableTags, orderBy: 'usage_count DESC');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  static Future<Tag?> getTag(int id) async {
    final db = await database;
    final maps = await db.query(
      tableTags,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Tag.fromMap(maps.first);
    }
    return null;
  }

  static Future<int> insertTag(Tag tag) async {
    final db = await database;
    final map = tag.toMap();
    map['created_at'] = DateTime.now().toIso8601String();
    return await db.insert(tableTags, map);
  }

  static Future<int> updateTag(Tag tag) async {
    final db = await database;
    return await db.update(
      tableTags,
      tag.toMap(),
      where: 'id = ?',
      whereArgs: [tag.id],
    );
  }

  static Future<int> deleteTag(int id) async {
    final db = await database;
    // 先删除关联
    await db.delete(
      tableDiaryTags,
      where: 'tag_id = ?',
      whereArgs: [id],
    );
    // 删除标签
    return await db.delete(
      tableTags,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== 日记标签关联操作 ====================

  static Future<void> insertDiaryTag(int diaryId, int tagId) async {
    final db = await database;
    await db.insert(tableDiaryTags, {
      'diary_id': diaryId,
      'tag_id': tagId,
    });
    // 更新标签使用次数
    await db.rawUpdate(
      'UPDATE $tableTags SET usage_count = usage_count + 1 WHERE id = ?',
      [tagId],
    );
  }

  static Future<void> deleteDiaryTags(int diaryId) async {
    final db = await database;
    await db.delete(
      tableDiaryTags,
      where: 'diary_id = ?',
      whereArgs: [diaryId],
    );
  }

  static Future<List<Tag>> getTagsByDiaryId(int diaryId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.* FROM $tableTags t
      INNER JOIN $tableDiaryTags dt ON t.id = dt.tag_id
      WHERE dt.diary_id = ?
    ''', [diaryId]);
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  // ==================== 统计操作 ====================

  static Future<Map<String, int>> getMoodDistribution() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT mood_name, COUNT(*) as count 
      FROM $tableDiaries 
      WHERE mood_name IS NOT NULL 
      GROUP BY mood_name
    ''');
    final Map<String, int> distribution = {};
    for (final row in result) {
      distribution[row['mood_name'] as String] = row['count'] as int;
    }
    return distribution;
  }

  static Future<List<Map<String, dynamic>>> getDiaryCountByMonth() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUBSTR(date, 1, 7) as month, COUNT(*) as count 
      FROM $tableDiaries 
      GROUP BY SUBSTR(date, 1, 7)
      ORDER BY month DESC
    ''');
    return result;
  }

  // ==================== 纪念日操作 ====================

  /// 获取所有纪念日
  static Future<List<Anniversary>> getAllAnniversaries() async {
    final db = await database;
    final maps = await db.query(tableAnniversaries, orderBy: 'date ASC');
    return maps.map((map) => Anniversary.fromMap(map)).toList();
  }

  /// 获取指定日期的纪念日
  static Future<List<Anniversary>> getAnniversariesByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      tableAnniversaries,
      where: 'date = ?',
      whereArgs: [date],
    );
    return maps.map((map) => Anniversary.fromMap(map)).toList();
  }

  /// 插入纪念日
  static Future<int> insertAnniversary(Anniversary anniversary) async {
    final db = await database;
    final map = anniversary.toMap();
    map['created_at'] = DateTime.now().toIso8601String();
    return await db.insert(tableAnniversaries, map);
  }

  /// 更新纪念日
  static Future<int> updateAnniversary(Anniversary anniversary) async {
    final db = await database;
    return await db.update(
      tableAnniversaries,
      anniversary.toMap(),
      where: 'id = ?',
      whereArgs: [anniversary.id],
    );
  }

  /// 删除纪念日
  static Future<int> deleteAnniversary(int id) async {
    final db = await database;
    return await db.delete(
      tableAnniversaries,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取某日期相关的纪念日（用于写日记时自动添加纪念文字）
  static Future<List<Anniversary>> getAnniversariesForDate(String date) async {
    // 返回所有纪念日，因为写日记时需要检查是否是某个纪念日的特殊日子
    return getAllAnniversaries();
  }

  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // ==================== 三级标签系统 V3 方法 ====================
  
  /// 保存日记的标签关联（V3版本，支持String类型的tagId）
  static Future<void> insertDiaryTagsV3(int diaryId, List<String> tagIds) async {
    final db = await database;
    final batch = db.batch();
    
    for (final tagId in tagIds) {
      batch.insert('diary_tags_v3', {
        'diary_id': diaryId,
        'tag_id': tagId,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    
    await batch.commit(noResult: true);
  }
  
  /// 删除日记的所有标签关联（V3版本）
  static Future<void> deleteDiaryTagsV3(int diaryId) async {
    final db = await database;
    await db.delete(
      'diary_tags_v3',
      where: 'diary_id = ?',
      whereArgs: [diaryId],
    );
  }
  
  /// 获取日记的标签ID列表（V3版本）
  static Future<List<String>> getDiaryTagIds(int diaryId) async {
    final db = await database;
    final maps = await db.query(
      'diary_tags_v3',
      columns: ['tag_id'],
      where: 'diary_id = ?',
      whereArgs: [diaryId],
    );
    return maps.map((m) => m['tag_id'] as String).toList();
  }
  
  /// 根据标签ID获取日记列表（V3版本）
  static Future<List<Diary>> getDiariesByTagIdV3(String tagId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT d.* FROM $tableDiaries d
      INNER JOIN diary_tags_v3 dt ON d.id = dt.diary_id
      WHERE dt.tag_id = ?
      ORDER BY d.date DESC
    ''', [tagId]);
    return maps.map((map) => Diary.fromMap(map)).toList();
  }

  // ==================== 云同步合并方法（v1.1.5新增）====================

  /// 合并日记标签关联（去重插入）
  static Future<void> mergeDiaryTags(List<Map<String, dynamic>> diaryTags) async {
    final db = await database;
    
    for (final entry in diaryTags) {
      final diaryId = entry['diary_id'];
      final tagId = entry['tag_id'];
      
      if (diaryId == null || tagId == null) continue;
      
      // 检查关联是否已存在
      final existing = await db.query(
        tableDiaryTags,
        where: 'diary_id = ? AND tag_id = ?',
        whereArgs: [diaryId, tagId],
      );
      
      if (existing.isEmpty) {
        // 不存在，插入新关联
        await db.insert(tableDiaryTags, {
          'diary_id': diaryId,
          'tag_id': tagId,
        });
      }
    }
  }

  /// 导入日记列表（合并模式：根据ID去重）
  static Future<int> importDiaries(List<Diary> diaries) async {
    int count = 0;
    for (final diary in diaries) {
      if (diary.id == null) continue;
      final existing = await getDiary(diary.id!);
      if (existing == null) {
        await insertDiary(diary);
        count++;
      }
    }
    return count;
  }

  /// 导入心情列表（合并模式：根据ID去重）
  static Future<int> importMoods(List<Mood> moods) async {
    int count = 0;
    for (final mood in moods) {
      if (mood.id == null) continue;
      final existing = await getMood(mood.id!);
      if (existing == null) {
        await insertMood(mood);
        count++;
      }
    }
    return count;
  }

  /// 导入标签列表（合并模式：根据ID去重）
  static Future<int> importTags(List<Tag> tags) async {
    int count = 0;
    for (final tag in tags) {
      if (tag.id == null) continue;
      final existing = await getTag(tag.id!);
      if (existing == null) {
        await insertTag(tag);
        count++;
      }
    }
    return count;
  }

  // ==================== 自言自语消息操作 ====================

  static Future<int> insertSelfTalkMessage(SelfTalkMessage message) async {
    final db = await database;
    return await db.insert(tableSelfTalkMessages, message.toMap());
  }

  static Future<List<SelfTalkMessage>> getSelfTalkMessagesByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      tableSelfTalkMessages,
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'created_at ASC, id ASC',
    );
    return maps.map((map) => SelfTalkMessage.fromMap(map)).toList();
  }

  static Future<int> deleteSelfTalkMessage(int id) async {
    final db = await database;
    return await db.delete(
      tableSelfTalkMessages,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== 自言自语任务操作 ====================

  static Future<int> insertSelfTalkTask(SelfTalkTask task) async {
    final db = await database;
    return await db.insert(tableSelfTalkTasks, task.toMap());
  }

  static Future<List<SelfTalkTask>> getSelfTalkTasksByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      tableSelfTalkTasks,
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'created_at ASC',
    );
    return maps.map((map) => SelfTalkTask.fromMap(map)).toList();
  }

  static Future<List<SelfTalkTask>> getSelfTalkTasksByMessageId(int messageId) async {
    final db = await database;
    final maps = await db.query(
      tableSelfTalkTasks,
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'created_at ASC',
    );
    return maps.map((map) => SelfTalkTask.fromMap(map)).toList();
  }

  static Future<int> updateSelfTalkTask(SelfTalkTask task) async {
    final db = await database;
    return await db.update(
      tableSelfTalkTasks,
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  static Future<int> deleteSelfTalkTask(int id) async {
    final db = await database;
    return await db.delete(
      tableSelfTalkTasks,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== 自言自语搜索操作 ====================

  /// 搜索自言自语消息
  ///
  /// [keyword] 内容关键词（模糊匹配）
  /// [dateFrom] 日期范围开始（yyyy-MM-dd，包含）
  /// [dateTo] 日期范围结束（yyyy-MM-dd，包含）
  /// [senderType] 发送者类型筛选（0=me, 1=alterEgo, 2=system）
  static Future<List<SelfTalkMessage>> searchSelfTalkMessages({
    String? keyword,
    String? dateFrom,
    String? dateTo,
    int? senderType,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (keyword != null && keyword.isNotEmpty) {
      conditions.add('content LIKE ?');
      args.add('%$keyword%');
    }
    if (dateFrom != null && dateFrom.isNotEmpty) {
      conditions.add('date >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      conditions.add('date <= ?');
      args.add(dateTo);
    }
    if (senderType != null) {
      conditions.add('sender_type = ?');
      args.add(senderType);
    }

    final whereClause = conditions.isEmpty ? null : conditions.join(' AND ');

    final maps = await db.query(
      tableSelfTalkMessages,
      where: whereClause,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
    );
    return maps.map((map) => SelfTalkMessage.fromMap(map)).toList();
  }

  /// 按日期范围获取自言自语消息
  static Future<List<SelfTalkMessage>> getSelfTalkMessagesByDateRange(
    String dateFrom,
    String dateTo,
  ) async {
    final db = await database;
    final maps = await db.query(
      tableSelfTalkMessages,
      where: 'date >= ? AND date <= ?',
      whereArgs: [dateFrom, dateTo],
      orderBy: 'created_at ASC, id ASC',
    );
    return maps.map((map) => SelfTalkMessage.fromMap(map)).toList();
  }

  /// 获取所有有自言自语记录的日期（去重，降序）
  static Future<List<String>> getSelfTalkDates() async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT date FROM $tableSelfTalkMessages ORDER BY date DESC',
    );
    return maps.map((m) => m['date'] as String).toList();
  }

  /// 搜索自言自语任务
  ///
  /// [keyword] 内容关键词（模糊匹配）
  /// [dateFrom] 日期范围开始（yyyy-MM-dd，包含）
  /// [dateTo] 日期范围结束（yyyy-MM-dd，包含）
  /// [isCompleted] 完成状态筛选
  static Future<List<SelfTalkTask>> searchSelfTalkTasks({
    String? keyword,
    String? dateFrom,
    String? dateTo,
    bool? isCompleted,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (keyword != null && keyword.isNotEmpty) {
      conditions.add('content LIKE ?');
      args.add('%$keyword%');
    }
    if (dateFrom != null && dateFrom.isNotEmpty) {
      conditions.add('date >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      conditions.add('date <= ?');
      args.add(dateTo);
    }
    if (isCompleted != null) {
      conditions.add('is_completed = ?');
      args.add(isCompleted ? 1 : 0);
    }

    final whereClause = conditions.isEmpty ? null : conditions.join(' AND ');

    final maps = await db.query(
      tableSelfTalkTasks,
      where: whereClause,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
    );
    return maps.map((map) => SelfTalkTask.fromMap(map)).toList();
  }

  // ==================== 速记操作 ====================

  static Future<int> insertQuickNote(QuickNote note) async {
    final db = await database;
    return await db.insert(tableQuickNotes, note.toMap());
  }

  static Future<List<QuickNote>> getAllQuickNotes() async {
    final db = await database;
    final maps = await db.query(
      tableQuickNotes,
      orderBy: 'is_pinned DESC, created_at DESC',
    );
    return maps.map((map) => QuickNote.fromMap(map)).toList();
  }

  static Future<List<QuickNote>> getQuickNotesByTag(String tag) async {
    final db = await database;
    final maps = await db.query(
      tableQuickNotes,
      where: 'tag = ?',
      whereArgs: [tag],
      orderBy: 'is_pinned DESC, created_at DESC',
    );
    return maps.map((map) => QuickNote.fromMap(map)).toList();
  }

  static Future<List<QuickNote>> searchQuickNotes(String keyword) async {
    final db = await database;
    final maps = await db.query(
      tableQuickNotes,
      where: 'content LIKE ?',
      whereArgs: ['%$keyword%'],
      orderBy: 'is_pinned DESC, created_at DESC',
    );
    return maps.map((map) => QuickNote.fromMap(map)).toList();
  }

  static Future<QuickNote?> getQuickNoteById(int id) async {
    final db = await database;
    final maps = await db.query(
      tableQuickNotes,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return QuickNote.fromMap(maps.first);
  }

  static Future<int> updateQuickNote(QuickNote note) async {
    final db = await database;
    return await db.update(
      tableQuickNotes,
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  static Future<int> deleteQuickNote(int id) async {
    final db = await database;
    return await db.delete(
      tableQuickNotes,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> getQuickNoteCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $tableQuickNotes');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
