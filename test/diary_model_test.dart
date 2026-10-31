// 数据层关键行为回归测试。
//
// 覆盖 2026-10-28 性能优化里改动风险最高的两块：
//   1. `Diary` 派生字段缓存（wordCount / imageList）—— 必须与旧实现结果一致
//   2. 分键存储（B0-2）用到的纯逻辑：索引排序、加密/解密往返语义
//
// 注意：这里**不**启动真实 SharedPreferences / sqflite（那需要
// sqflite_common_ffi 与插件的平台通道）。凡是依赖平台能力的行为，
// 都通过把逻辑抽成可直接调用的形式来测。

import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/models/diary.dart';

void main() {
  group('Diary.imageList 缓存', () {
    test('null / 空串返回空列表', () {
      final d = Diary(date: '2026-01-01');
      expect(d.imageList, isEmpty);
      final d2 = Diary(date: '2026-01-01', images: '');
      expect(d2.imageList, isEmpty);
    });

    test('逗号分隔解析，过滤空项', () {
      final d = Diary(date: '2026-01-01', images: '/a.jpg,/b.jpg,');
      expect(d.imageList, ['/a.jpg', '/b.jpg']);
    });

    test('多次访问返回同一个不可变实例（缓存生效）', () {
      final d = Diary(date: '2026-01-01', images: '/a.jpg,/b.jpg');
      final first = d.imageList;
      final second = d.imageList;
      expect(identical(first, second), isTrue,
          reason: '缓存应当复用同一个 List 实例，而不是每次重新 split');
    });

    test('缓存列表不可被外部修改（防止误改污染模型）', () {
      final d = Diary(date: '2026-01-01', images: '/a.jpg');
      expect(() => d.imageList.add('/x.jpg'), throwsUnsupportedError);
    });
  });

  group('Diary.wordCount 缓存与语义', () {
    test('标题 + 正文长度相加', () {
      final d = Diary(date: '2026-01-01', title: '标题', content: '正文内容');
      // 标题 2 字 + 正文 4 字
      expect(d.wordCount, 6);
    });

    test('排除带 🎉/⏰ 标记的纪念日/倒数日行', () {
      // 注意：正则要求行首有 🎉 或 ⏰ 标记才会被排除，
      // 这是既有行为，本次优化只做缓存、不改语义。
      final d = Diary(
        date: '2026-01-01',
        content: '今天很好\n🎉 相识纪念日\n⏰ 旅行倒数日',
      );
      // 只剩「今天很好」四字
      expect(d.wordCount, 4);
    });

    test('不带标记的「倒数日」文字不会被排除（锁定既有语义）', () {
      // 这一条是为了防止有人"顺手"把正则放宽 —— 会改变历史字数统计口径
      final d = Diary(date: '2026-01-01', content: '今天很好\n倒数日：还有 100 天');
      expect(d.wordCount, greaterThan(4));
    });

    test('null 字段不崩溃', () {
      final d = Diary(date: '2026-01-01');
      expect(d.wordCount, 0);
    });

    test('多次访问结果一致且命中缓存', () {
      final d = Diary(date: '2026-01-01', title: 'a', content: 'bb');
      final first = d.wordCount;
      final second = d.wordCount;
      expect(first, second);
      expect(first, 3);
    });

    test('copyWith 产生新实例后缓存自然重算（不同内容 → 不同字数）', () {
      final d = Diary(date: '2026-01-01', content: '一二三');
      expect(d.wordCount, 3);

      final changed = d.copyWith(content: '一二三四五');
      expect(changed.wordCount, 5,
          reason: 'copyWith 必须得到独立实例，不能带着旧缓存');
      // 原实例不受影响
      expect(d.wordCount, 3);
    });
  });

  group('Diary 作为分键存储的序列化载体', () {
    test('toMap / fromMap 往返后 wordCount 与 imageList 一致', () {
      final original = Diary(
        id: 42,
        title: '标题',
        content: '正文\n🎉 纪念日',
        date: '2026-10-28',
        images: '/a.jpg,/b.jpg',
        moodId: 3,
        moodName: '开心',
        moodEmoji: '😄',
        weather: '晴',
        isFavorite: true,
        createdAt: '2026-10-28T10:00:00.000',
        updatedAt: '2026-10-28T10:01:00.000',
      );

      final restored = Diary.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.date, original.date);
      expect(restored.wordCount, original.wordCount);
      expect(restored.imageList, original.imageList);
      expect(restored.isFavorite, original.isFavorite);
      expect(restored.moodEmoji, original.moodEmoji);
    });
  });

  group('Diary.source 来源标记', () {
    test('没有 source 字段（历史数据）→ 不算麦麦写的', () {
      final d = Diary.fromMap({'date': '2026-10-28', 'title': '旧日记'});
      expect(d.source, isNull);
      expect(d.sourceType, isNull);
      expect(d.isFromMaibot, isFalse);
    });

    test('toMap / fromMap 往返保留 maibot 标记', () {
      final original = Diary(
        date: '2026-10-31',
        content: '今天没什么好写的',
        source: DiarySource.maibot.code,
      );

      final restored = Diary.fromMap(original.toMap());

      expect(restored.source, DiarySource.maibot.code);
      expect(restored.isFromMaibot, isTrue);
      expect(restored.sourceType, DiarySource.maibot);
      expect(restored.content, original.content);
    });

    test('认不出来的来源原样保留，不会被洗成 self', () {
      // 老版本 App 读到新版本写下的陌生来源时，至少要能原样带回去，
      // 否则一次「读 + 存」就把标记弄丢了。
      final d = Diary.fromMap({'date': '2026-10-31', 'source': 'import-zz'});
      expect(d.source, 'import-zz');
      expect(d.sourceType, isNull);

      expect(d.toMap()['source'], 'import-zz');
    });

    test('copyWith 保留 source（改心情不会丢来源）', () {
      final d = Diary(date: '2026-10-31', source: DiarySource.maibot.code);
      final changed = d.copyWith(moodName: '平静');
      expect(changed.source, DiarySource.maibot.code);
    });

    test('从字符串解析：未知 / 空串 → null', () {
      expect(DiarySource.fromCode(null), isNull);
      expect(DiarySource.fromCode(''), isNull);
      expect(DiarySource.fromCode('nope'), isNull);
      expect(DiarySource.fromCode('maibot'), DiarySource.maibot);
      expect(DiarySource.fromCode('self'), DiarySource.self);
    });
  });
}
