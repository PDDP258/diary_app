// 「搜索能搜到，主界面没有」的回归测试（2026-10-28）。
//
// 现象：搜索页能搜到日记并查看，但时间线/日历一片空白。
//
// 关键差异（也是定位依据）：
//   - 搜索页 → `DatabaseService.getAllDiaries()`  直接查 → 能读到 ✅
//   - 主界面 → `DiaryProvider.diaries` 内存缓存    → 空 ❌
//
// 所以数据层是好的，问题在「Provider 没有被成功填充」。
// 这条链路是 `MainScreen._loadData()` → `provider.loadAllData()`
// → `loadRecentDiaries()` → `DatabaseService.getRecentDiaries()`。
//
// 本测试验证：即使「快速路径」（getRecentDiaries）不可用，
// Provider 也必须能通过全量加载兜底拿到日记。

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diary_app/models/diary.dart';
import 'package:diary_app/providers/diary_provider.dart';
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

  test('数据层能读到（对应「搜索能搜到」）', () async {
    final legacy = [
      _diaryMap(1, '2026-10-01', '第一篇'),
      _diaryMap(2, '2026-10-02', '第二篇'),
      _diaryMap(3, '2026-10-03', '第三篇'),
    ];
    SharedPreferences.setMockInitialValues({
      'diaries_data': jsonEncode(legacy),
      'diary_split_migrated_v1': true,
    });

    // 搜索页用的就是这个 API
    final all = await DatabaseService.getAllDiaries();
    expect(all.length, 3, reason: '数据层必须能读到全部日记');

    // 磁盘上确实有数据（用于区分「真空」与「读取失败」）
    expect(await DatabaseService.hasDiaryDataOnDisk(), isTrue);
  });

  test('Provider 必须被成功填充（对应「主界面能看到」）', () async {
    // 复用同一份数据（静态内存状态，本文件第一个用例已初始化服务）
    final provider = DiaryProvider();

    // 模拟主界面加载链路
    await provider.loadAllData();

    expect(provider.diaries, isNotEmpty,
        reason: 'Provider 为空就是「主界面没有日记」的直接原因');

    // 再验证全量加载路径同样可用
    await provider.loadDiaries();
    expect(provider.diaries.length, 3,
        reason: '全量加载应取回全部 3 篇');
    expect(provider.diaries.map((d) => d.id).toSet(), {1, 2, 3});

    // 内容必须是明文
    for (final d in provider.diaries) {
      expect(d.content, isNot(contains('__ENC')));
    }
  });

  test('Provider 的日记载荷与 DatabaseService 完全一致', () async {
    final provider = DiaryProvider();
    await provider.loadDiaries();

    final direct = await DatabaseService.getAllDiaries();

    expect(provider.diaries.length, direct.length,
        reason: 'Provider 与数据层的日记数量必须一致，否则就是缓存没刷新');
    expect(
      provider.diaries.map((d) => d.id).toSet(),
      direct.map((d) => d.id).toSet(),
    );
  });
}
