import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import '../models/tag_system.dart';
import 'database_service.dart';
import 'tag_system_service.dart';

/// 增量同步服务
/// 
/// 功能：
/// 1. 记录每个数据项的最后修改时间
/// 2. 只同步自上次同步以来变更的数据
/// 3. 减少同步流量和时间
/// 4. 支持冲突检测和解决
class IncrementalSyncService {
  static const String _syncMetadataKey = 'incremental_sync_metadata';
  static const String _lastSyncTimeKey = 'incremental_last_sync_time';
  static const String _syncDirName = 'incremental_sync';

  /// 获取上次同步时间
  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastSyncTimeKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// 设置上次同步时间
  static Future<void> setLastSyncTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncTimeKey, time.millisecondsSinceEpoch);
  }

  /// 获取需要同步的变更数据
  /// 
  /// [since] 从这个时间点之后的数据变更
  static Future<SyncChanges> getChangesSince(DateTime? since) async {
    final diaries = await DatabaseService.getAllDiaries();
    final moods = await DatabaseService.getAllMoods();
    final tags = await DatabaseService.getAllTags();
    final tagSystem = await TagSystemService.getTagSystem();
    final diaryTagsV3 = await DatabaseService.getAllDiaryTagsV3();

    // 如果没有指定时间，返回所有数据
    if (since == null) {
      return SyncChanges(
        diaries: diaries,
        moods: moods,
        tags: tags,
        tagSystem: tagSystem,
        diaryTagsV3: diaryTagsV3,
        isFullSync: true,
      );
    }

    // 筛选出变更的数据
    final changedDiaries = diaries.where((d) {
      final updatedAtStr = d.updatedAt ?? d.createdAt;
      if (updatedAtStr == null) return false;
      final updatedAt = DateTime.tryParse(updatedAtStr);
      return updatedAt != null && updatedAt.isAfter(since);
    }).toList();

    final changedMoods = moods.where((m) {
      // 心情通常不经常变更，简单处理：如果 ID 大于上次最大 ID 则为新增
      return true; // 心情数据量小，全量同步
    }).toList();

    final changedTags = tags.where((t) {
      // 标签同理
      return true; // 标签数据量小，全量同步
    }).toList();

    return SyncChanges(
      diaries: changedDiaries,
      moods: changedMoods,
      tags: changedTags,
      tagSystem: tagSystem, // 三级标签系统数据量小，全量同步
      diaryTagsV3: diaryTagsV3, // 日记-标签关联全量同步
      isFullSync: false,
    );
  }

  /// 准备增量同步数据包
  static Future<SyncPackage> prepareSyncPackage() async {
    final lastSyncTime = await getLastSyncTime();
    final changes = await getChangesSince(lastSyncTime);

    final package = SyncPackage(
      timestamp: DateTime.now(),
      lastSyncTime: lastSyncTime,
      changes: changes,
    );

    return package;
  }

  /// 应用远程变更到本地
  static Future<ApplyResult> applyRemoteChanges(SyncChanges remoteChanges) async {
    int appliedDiaries = 0;
    int appliedMoods = 0;
    int appliedTags = 0;
    int conflicts = 0;

    try {
      // 应用日记变更
      for (final diary in remoteChanges.diaries) {
        try {
          final existing = await DatabaseService.getDiary(diary.id ?? 0);
          if (existing == null) {
            // 新增
            await DatabaseService.insertDiary(diary);
            appliedDiaries++;
          } else {
            // 更新或冲突
            final localUpdatedStr = existing.updatedAt ?? existing.createdAt;
            final remoteUpdatedStr = diary.updatedAt ?? diary.createdAt;
            
            if (remoteUpdatedStr != null && localUpdatedStr != null) {
              final localUpdated = DateTime.tryParse(localUpdatedStr);
              final remoteUpdated = DateTime.tryParse(remoteUpdatedStr);
              
              if (localUpdated != null && remoteUpdated != null) {
                if (remoteUpdated.isAfter(localUpdated)) {
                  // 远程更新，应用变更
                  await DatabaseService.updateDiary(diary);
                  appliedDiaries++;
                } else if (remoteUpdated.isBefore(localUpdated)) {
                  // 本地更新，保留本地（冲突）
                  conflicts++;
                } else {
                  // 时间相同，视为已同步
                }
              } else {
                // 无法解析时间，直接更新
                await DatabaseService.updateDiary(diary);
                appliedDiaries++;
              }
            } else {
              // 没有时间戳，直接更新
              await DatabaseService.updateDiary(diary);
              appliedDiaries++;
            }
          }
        } catch (e) {
          print('应用日记变更失败: $e');
        }
      }

      // 应用心情变更（全量替换）
      if (remoteChanges.moods.isNotEmpty) {
        await DatabaseService.restoreMoods(remoteChanges.moods);
        appliedMoods = remoteChanges.moods.length;
      }

      // 应用标签变更（全量替换）
      if (remoteChanges.tags.isNotEmpty) {
        await DatabaseService.restoreTags(remoteChanges.tags);
        appliedTags = remoteChanges.tags.length;
      }

      // 应用三级标签系统变更
      if (remoteChanges.tagSystem != null) {
        await TagSystemService.updateTagSystem(remoteChanges.tagSystem!);
      }

      // 应用日记-标签关联变更
      if (remoteChanges.diaryTagsV3 != null && remoteChanges.diaryTagsV3!.isNotEmpty) {
        await DatabaseService.importDiaryTagsV3(remoteChanges.diaryTagsV3!);
      }

      // 更新同步时间
      await setLastSyncTime(DateTime.now());

      return ApplyResult(
        success: true,
        appliedDiaries: appliedDiaries,
        appliedMoods: appliedMoods,
        appliedTags: appliedTags,
        conflicts: conflicts,
      );
    } catch (e) {
      return ApplyResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// 将同步包保存为文件（用于 WebDAV 上传）
  static Future<String> saveSyncPackage(SyncPackage package) async {
    final appDir = await getApplicationDocumentsDirectory();
    final syncDir = Directory('${appDir.path}/$_syncDirName');
    
    if (!await syncDir.exists()) {
      await syncDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'sync_package_$timestamp.json';
    final filePath = '${syncDir.path}/$fileName';

    final file = File(filePath);
    await file.writeAsString(jsonEncode(package.toJson()));

    return filePath;
  }

  /// 从文件加载同步包
  static Future<SyncPackage?> loadSyncPackage(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      return SyncPackage.fromJson(json);
    } catch (e) {
      print('加载同步包失败: $e');
      return null;
    }
  }

  /// 清理旧的同步包文件
  static Future<void> cleanupOldPackages() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final syncDir = Directory('${appDir.path}/$_syncDirName');
      
      if (!await syncDir.exists()) return;

      final files = await syncDir.list().toList();
      final now = DateTime.now();
      
      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          final age = now.difference(stat.modified);
          
          // 删除7天前的同步包
          if (age.inDays > 7) {
            await file.delete();
            print('删除旧同步包: ${file.path}');
          }
        }
      }
    } catch (e) {
      print('清理旧同步包失败: $e');
    }
  }

  /// 获取同步统计信息
  static Future<SyncStats> getSyncStats() async {
    final lastSyncTime = await getLastSyncTime();
    final changes = await getChangesSince(lastSyncTime);

    return SyncStats(
      lastSyncTime: lastSyncTime,
      pendingDiaries: changes.diaries.length,
      pendingMoods: changes.moods.length,
      pendingTags: changes.tags.length,
      isFullSync: changes.isFullSync,
    );
  }
}

/// 同步变更数据
class SyncChanges {
  final List<Diary> diaries;
  final List<Mood> moods;
  final List<Tag> tags;
  final TagSystem? tagSystem; // 三级标签系统
  final List<Map<String, dynamic>>? diaryTagsV3; // 日记-标签关联
  final bool isFullSync;

  SyncChanges({
    required this.diaries,
    required this.moods,
    required this.tags,
    this.tagSystem,
    this.diaryTagsV3,
    this.isFullSync = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'diaries': diaries.map((d) => d.toMap()).toList(),
      'moods': moods.map((m) => m.toMap()).toList(),
      'tags': tags.map((t) => t.toMap()).toList(),
      'tagSystem': tagSystem?.toJson(),
      'diaryTagsV3': diaryTagsV3,
      'isFullSync': isFullSync,
    };
  }

  factory SyncChanges.fromJson(Map<String, dynamic> json) {
    return SyncChanges(
      diaries: (json['diaries'] as List).map((e) => Diary.fromMap(e)).toList(),
      moods: (json['moods'] as List).map((e) => Mood.fromMap(e)).toList(),
      tags: (json['tags'] as List).map((e) => Tag.fromMap(e)).toList(),
      tagSystem: json['tagSystem'] != null 
          ? TagSystem.fromJson(json['tagSystem']) 
          : null,
      diaryTagsV3: json['diaryTagsV3'] != null 
          ? (json['diaryTagsV3'] as List).cast<Map<String, dynamic>>()
          : null,
      isFullSync: json['isFullSync'] ?? false,
    );
  }
}

/// 同步包
class SyncPackage {
  final DateTime timestamp;
  final DateTime? lastSyncTime;
  final SyncChanges changes;

  SyncPackage({
    required this.timestamp,
    this.lastSyncTime,
    required this.changes,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'lastSyncTime': lastSyncTime?.toIso8601String(),
      'changes': changes.toJson(),
    };
  }

  factory SyncPackage.fromJson(Map<String, dynamic> json) {
    return SyncPackage(
      timestamp: DateTime.parse(json['timestamp']),
      lastSyncTime: json['lastSyncTime'] != null 
          ? DateTime.parse(json['lastSyncTime']) 
          : null,
      changes: SyncChanges.fromJson(json['changes']),
    );
  }
}

/// 应用结果
class ApplyResult {
  final bool success;
  final int appliedDiaries;
  final int appliedMoods;
  final int appliedTags;
  final int conflicts;
  final String? error;

  ApplyResult({
    required this.success,
    this.appliedDiaries = 0,
    this.appliedMoods = 0,
    this.appliedTags = 0,
    this.conflicts = 0,
    this.error,
  });
}

/// 同步统计
class SyncStats {
  final DateTime? lastSyncTime;
  final int pendingDiaries;
  final int pendingMoods;
  final int pendingTags;
  final bool isFullSync;

  SyncStats({
    this.lastSyncTime,
    this.pendingDiaries = 0,
    this.pendingMoods = 0,
    this.pendingTags = 0,
    this.isFullSync = false,
  });

  int get totalPending => pendingDiaries + pendingMoods + pendingTags;
}
