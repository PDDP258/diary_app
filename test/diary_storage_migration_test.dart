// 「日记归零」事故回归测试（2026-10-28 B0-2）。
//
// 事故根因（已修复）：
//   `_loadDiariesFromSplitKeys()` 里
//     `final List<int> ids = jsonDecode(...).cast<num>().map(...).toList();`
//   `jsonDecode` 返回 `List<dynamic>`，直接赋给 `List<int>` 会抛
//     `type 'List<dynamic>' is not a subtype of type 'List<int>'`
//   而该异常被 `_loadData()` 的 try/catch 吞掉，只打一句「加载数据失败」
//   → `_diaries` 保持为空 → **日记全部显示 0 篇**（磁盘数据其实完好）。
//
// ⚠️ 测试约束：`DatabaseService` 持有**静态内存状态**（`_initialized`、
// `_diaries`），同一个测试进程内所有用例共享它，且无法从外部重置。
// 因此本文件只允许有**一个**真正触发加载的用例，其余断言全部放在这个
// 用例内部完成 —— 否则后续用例会读到前一个用例的残留状态，产生假失败。

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diary_app/services/database_service.dart';

Map<String, dynamic> _diary(int id, String date, String content) => {
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
        case 'delete':
          store.remove(call.arguments['key'] as String);
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

  test('索引缺失时自愈：日记不允许显示 0 篇（事故回归）', () async {
    final legacy = [
      _diary(1, '2026-10-01', '第一篇内容'),
      _diary(2, '2026-10-02', '第二篇内容'),
    ];

    // 事故现场：迁移标记已置位、分键都在，唯独 diary_index 丢了
    SharedPreferences.setMockInitialValues({
      'diaries_data': jsonEncode(legacy),
      'diary_1': jsonEncode(legacy[0]),
      'diary_2': jsonEncode(legacy[1]),
      'diary_split_migrated_v1': true,
    });

    final diaries = await DatabaseService.getAllDiaries();

    // —— 核心断言：必须自愈，不能是 0 ——
    expect(diaries.length, 2,
        reason: '索引缺失必须从分键扫描自愈；这是本次数据丢失事故的直接回归点');
    expect(diaries.map((d) => d.id).toSet(), {1, 2});
    expect(diaries.first.content, isNotEmpty);

    // —— 内容可读：不能被当成密文 ——
    for (final d in diaries) {
      expect(d.content, isNot(contains('__ENC2__')));
      expect(d.content, isNot(contains('__ENC__')));
    }

    // —— 自愈后索引应已修好，供下次启动走快路径 ——
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final indexJson = prefs.getString('diary_index');
    expect(indexJson, isNotNull, reason: '自愈后必须写回索引');
    expect((jsonDecode(indexJson!) as List).length, 2);

    // —— 旧键必须保留（最后一道回滚保险）——
    expect(prefs.getString('diaries_data'), isNotNull,
        reason: '旧键是回滚保险，任何情况下都不能删');
  });
}
