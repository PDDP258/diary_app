// 并发初始化竞态的回归测试（2026-10-28）。
//
// 事故现象：「搜索能搜到日记并查看，但主界面依旧没有」。
//
// 根因（已修复）：`DatabaseService._ensureInitialized()` 原实现是
// ```dart
// if (_initialized) return;        // 标志要等整段跑完才置位
// _prefs = await SharedPreferences.getInstance();   // ← await 悬挂点
// ...
// _initialized = true;
// ```
// 中间多个 `await` 让并发调用都看到 `_initialized == false`，于是
// **初始化被执行多次**，互相覆盖 `_diaries` / `_moods`，
// 导致先完成的那份数据被后一份空数据冲掉：
//   - 搜索页走 `getAllDiaries()`（会 await 初始化）→ 能读到数据 ✅
//   - 主界面走 `getRecentDiaries()`（只读内存）→ 拿到空列表 ❌
//
// 修复：用 `_initFuture ??= _doInitialize()` 让并发调用**共享同一个 Future**。

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diary_app/services/database_service.dart';

Map<String, dynamic> _diaryMap(int id, String date, String content) => {
      'id': id,
      'title': '标题$id',
      'content': content,
      'date': date,
      'images': '',
      'mood_id': null,
      'mood_name': null,
      'mood_emoji': null,
      'weather': '晴',
      'location': null,
      'is_favorite': 0,
      'created_at': '$date 10:00:00',
      'updated_at': '$date 10:00:00',
    };

void _mockSecureStorage() {
  final store = <String, String>{
    'encryption_key_v1': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    'encryption_salt_v1': 'AAAAAAAAAAAAAAAAAAAAAA==',
  };
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      switch (call.method) {
        case 'read':
          return store[call.arguments['key'] as String];
        case 'write':
          store[call.arguments['key'] as String] =
              call.arguments['value'] as String;
          return null;
        default:
          return null;
      }
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_mockSecureStorage);

  test('并发初始化多路径同时访问，结果必须一致且不丢数据', () async {
    final legacy = [
      _diaryMap(1, '2026-10-01', '第一篇'),
      _diaryMap(2, '2026-10-02', '第二篇'),
      _diaryMap(3, '2026-10-03', '第三篇'),
    ];
    SharedPreferences.setMockInitialValues({
      'diaries_data': jsonEncode(legacy),
      'diary_split_migrated_v1': true,
    });

    // 模拟启动瞬间的并发访问：主界面（快速路径）与搜索页（全量路径）
    // 同时打进来 —— 修复前它们会各自跑一遍初始化并互相覆盖。
    final results = await Future.wait([
      DatabaseService.getRecentDiaries(limit: 20), // 主界面用的
      DatabaseService.getAllDiaries(),             // 搜索页用的
      DatabaseService.getRecentDiaries(limit: 20),
      DatabaseService.getAllDiaries(),
    ]);

    for (final r in results) {
      expect(r.length, 3,
          reason: '并发访问下任何一条路径都不能拿到空列表 —— '
              '这正是「搜索能搜到、主界面没有」的根因');
    }

    // 所有路径的 id 集合必须一致
    for (final r in results) {
      expect(r.map((d) => d.id).toSet(), {1, 2, 3});
    }
  });
}
