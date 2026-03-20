import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/anniversary.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import 'encryption_service.dart';

/// Native 版本数据库服务（使用 SQLite）
/// 所有日记内容自动加密存储
class DatabaseService {
  static Database? _database;
  static const String _databaseName = 'diary_app.db';
  static const int _databaseVersion = 2; // 升级版本号以支持加密

  // 表名
  static const String tableDiaries = 'diaries';
  static const String tableMoods = 'moods';
  static const String tableTags = 'tags';
  static const String tableDiaryTags = 'diary_tags';
  static const String tableAnniversaries = 'anniversaries';

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
}
