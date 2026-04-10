import 'package:shared_preferences/shared_preferences.dart';
import '../models/time_capsule.dart';
import 'dart:convert';

/// 时间胶囊服务 - 纯本地存储，无需联网
class TimeCapsuleService {
  TimeCapsuleService._();
  
  static final TimeCapsuleService _instance = TimeCapsuleService._();
  static TimeCapsuleService get instance => _instance;

  // SharedPreferences keys
  static const String _capsulePrefix = 'time_capsule_';
  static const String _capsuleIdsKey = 'time_capsule_ids';

  /// 创建时间胶囊
  static Future<TimeCapsule> createCapsule({
    required String title,
    required String content,
    required DateTime unlockDate,
    List<String>? images,
    String? moodEmoji,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 生成唯一ID
    final id = DateTime.now().millisecondsSinceEpoch;
    
    final capsule = TimeCapsule(
      id: id,
      title: title,
      content: content,
      images: images?.join(','),
      createdAt: DateTime.now(),
      unlockDate: unlockDate,
      moodEmoji: moodEmoji,
    );

    // 保存胶囊数据
    await prefs.setString(
      '$_capsulePrefix$id', 
      jsonEncode(capsule.toMap()),
    );

    // 更新ID列表
    final ids = await _getCapsuleIds();
    ids.add(id);
    await prefs.setStringList(_capsuleIdsKey, ids.map((e) => e.toString()).toList());

    return capsule;
  }

  /// 获取所有时间胶囊
  static Future<List<TimeCapsule>> getAllCapsules() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _getCapsuleIds();
    
    final List<TimeCapsule> capsules = [];
    
    for (final id in ids) {
      final data = prefs.getString('$_capsulePrefix$id');
      if (data != null) {
        try {
          final map = jsonDecode(data) as Map<String, dynamic>;
          capsules.add(TimeCapsule.fromMap(map));
        } catch (e) {
          // 忽略损坏的数据
          continue;
        }
      }
    }

    // 按创建时间倒序排列
    capsules.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    return capsules;
  }

  /// 获取所有胶囊ID
  static Future<List<int>> _getCapsuleIds() async {
    final prefs = await SharedPreferences.getInstance();
    final idStrings = prefs.getStringList(_capsuleIdsKey) ?? [];
    return idStrings.map((e) => int.tryParse(e) ?? 0).where((e) => e > 0).toList();
  }

  /// 获取待解锁的胶囊（已到达解锁日期但未解锁）
  static Future<List<TimeCapsule>> getPendingUnlockCapsules() async {
    final allCapsules = await getAllCapsules();
    final now = DateTime.now();
    
    return allCapsules.where((capsule) {
      return !capsule.isUnlocked && 
             (capsule.unlockDate.isBefore(now) || capsule.unlockDate.isAtSameMomentAs(now));
    }).toList();
  }

  /// 获取已锁定的胶囊
  static Future<List<TimeCapsule>> getLockedCapsules() async {
    final allCapsules = await getAllCapsules();
    final now = DateTime.now();
    
    return allCapsules.where((capsule) {
      return !capsule.isUnlocked && capsule.unlockDate.isAfter(now);
    }).toList();
  }

  /// 获取已解锁的胶囊
  static Future<List<TimeCapsule>> getUnlockedCapsules() async {
    final allCapsules = await getAllCapsules();
    return allCapsules.where((capsule) => capsule.isUnlocked).toList();
  }

  /// 解锁时间胶囊
  static Future<TimeCapsule?> unlockCapsule(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('$_capsulePrefix$id');
    
    if (data == null) return null;

    try {
      final map = jsonDecode(data) as Map<String, dynamic>;
      final capsule = TimeCapsule.fromMap(map);
      
      // 检查是否可以解锁
      if (!capsule.canUnlock) return null;

      // 更新解锁状态
      final updatedCapsule = capsule.copyWith(
        isUnlocked: true,
        unlockedAt: DateTime.now(),
      );

      await prefs.setString(
        '$_capsulePrefix$id',
        jsonEncode(updatedCapsule.toMap()),
      );

      return updatedCapsule;
    } catch (e) {
      return null;
    }
  }

  /// 标记为已读
  static Future<TimeCapsule?> markAsRead(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('$_capsulePrefix$id');
    
    if (data == null) return null;

    try {
      final map = jsonDecode(data) as Map<String, dynamic>;
      final capsule = TimeCapsule.fromMap(map);
      
      final updatedCapsule = capsule.copyWith(isRead: true);

      await prefs.setString(
        '$_capsulePrefix$id',
        jsonEncode(updatedCapsule.toMap()),
      );

      return updatedCapsule;
    } catch (e) {
      return null;
    }
  }

  /// 删除时间胶囊
  static Future<bool> deleteCapsule(int id) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 删除数据
    final success = await prefs.remove('$_capsulePrefix$id');
    
    // 更新ID列表
    final ids = await _getCapsuleIds();
    ids.remove(id);
    await prefs.setStringList(_capsuleIdsKey, ids.map((e) => e.toString()).toList());
    
    return success;
  }

  /// 更新时间胶囊
  static Future<TimeCapsule?> updateCapsule(TimeCapsule capsule) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (capsule.id == null) return null;

    await prefs.setString(
      '$_capsulePrefix${capsule.id}',
      jsonEncode(capsule.toMap()),
    );

    return capsule;
  }

  /// 获取时间胶囊统计
  static Future<Map<String, int>> getCapsuleStats() async {
    final allCapsules = await getAllCapsules();
    
    return {
      'total': allCapsules.length,
      'locked': allCapsules.where((c) => !c.isUnlocked).length,
      'unlocked': allCapsules.where((c) => c.isUnlocked).length,
      'unread': allCapsules.where((c) => c.isUnlocked && !c.isRead).length,
    };
  }

  /// 检查是否有待解锁的胶囊（用于通知）
  static Future<bool> hasPendingUnlockCapsules() async {
    final pending = await getPendingUnlockCapsules();
    return pending.isNotEmpty;
  }

  /// 获取最近待解锁的胶囊
  static Future<TimeCapsule?> getNextUnlockCapsule() async {
    final lockedCapsules = await getLockedCapsules();
    
    if (lockedCapsules.isEmpty) return null;
    
    // 按解锁日期排序，返回最近的一个
    lockedCapsules.sort((a, b) => a.unlockDate.compareTo(b.unlockDate));
    return lockedCapsules.first;
  }

  /// 清除所有数据（仅用于测试）
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _getCapsuleIds();
    
    for (final id in ids) {
      await prefs.remove('$_capsulePrefix$id');
    }
    
    await prefs.remove(_capsuleIdsKey);
  }
}
