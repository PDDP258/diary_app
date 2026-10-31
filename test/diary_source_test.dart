// 「麦麦写来的日记」来源标记回归测试。
//
// 这条链路只有一件事不能错：**导入时来源必须落地**。
// 一旦丢了，用户在列表里就再也分不清哪篇是麦麦写的、哪篇是自己写的，
// 而且这种丢失是静默的 —— 界面看着一切正常，只是标记没了。
//
// 覆盖两层：
//   1. 数据层：payload → Diary 的转换（纯函数，不碰数据库）
//   2. UI 层：DiarySourceBadge 在「本人手写」时不出现、在「麦麦写的」时出现

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diary_app/models/diary.dart';
import 'package:diary_app/models/mood.dart';
import 'package:diary_app/providers/theme_provider.dart';
import 'package:diary_app/services/inbox_service.dart';
import 'package:diary_app/widgets/diary_source_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('收件箱导入：来源标记', () {
    test('payload 带 source=maibot → Diary.source 为 maibot', () {
      final diary = InboxService.buildDiaryFromPayload({
        'title': '今天',
        'content': '发呆了一会儿',
        'date': '2026-10-31',
        'mood': '平静',
        'source': 'maibot',
      });

      expect(diary.source, DiarySource.maibot.code);
      expect(diary.isFromMaibot, isTrue);
      expect(diary.sourceType, DiarySource.maibot);
    });

    test('payload 没有 source → 兜底标记为麦麦（收件箱里本来就是她写的）', () {
      final diary = InboxService.buildDiaryFromPayload({
        'content': '没写来源的老条目',
        'date': '2026-10-31',
      });

      expect(diary.source, InboxService.fallbackSourceCode);
      expect(diary.isFromMaibot, isTrue);
    });

    test('payload 的 source 是空白串 → 同样兜底，不会存成空字符串', () {
      final diary = InboxService.buildDiaryFromPayload({
        'content': 'x',
        'date': '2026-10-31',
        'source': '   ',
      });

      expect(diary.source, InboxService.fallbackSourceCode);
    });

    test('标题 / 正文 / 日期按 payload 落地并 trim', () {
      final diary = InboxService.buildDiaryFromPayload({
        'title': '  标题带空格  ',
        'content': '  正文  ',
        'date': '2026-10-30',
        'source': 'maibot',
      });

      expect(diary.title, '标题带空格');
      expect(diary.content, '正文');
      expect(diary.date, '2026-10-30');
    });

    test('title 缺失或空白 → null（不留空字符串标题）', () {
      final diary = InboxService.buildDiaryFromPayload({
        'content': '正文',
        'date': '2026-10-31',
        'title': '   ',
      });

      expect(diary.title, isNull);
    });

    test('心情查到了就带上 id / 名称 / emoji', () {
      final mood = Mood(id: 7, name: '平静', emoji: '😌', color: '#888888');

      final diary = InboxService.buildDiaryFromPayload({
        'content': '正文',
        'date': '2026-10-31',
        'mood': '平静',
      }, mood: mood);

      expect(diary.moodId, 7);
      expect(diary.moodName, '平静');
      expect(diary.moodEmoji, '😌');
    });

    test('心情没匹配上就留空（不能凭空造心情）', () {
      final diary = InboxService.buildDiaryFromPayload({
        'content': '正文',
        'date': '2026-10-31',
        'mood': '不存在的情绪',
      });

      expect(diary.moodId, isNull);
      expect(diary.moodName, isNull);
      expect(diary.moodEmoji, isNull);
    });
  });

  group('DiarySourceBadge', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Future<void> pumpBadge(WidgetTester tester, Diary diary,
        {bool verbose = false}) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: DiarySourceBadge(diary: diary, verbose: verbose),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('本人手写的日记不渲染任何东西', (tester) async {
      await pumpBadge(tester, Diary(date: '2026-10-31', content: '自己写的'));
      expect(find.text('麦麦'), findsNothing);
      expect(find.text('我'), findsNothing);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
    });

    testWidgets('没有来源标记（历史数据）也不渲染', (tester) async {
      await pumpBadge(tester, Diary.fromMap({'date': '2026-10-31'}));
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
    });

    testWidgets('麦麦写的显示紧凑版短名', (tester) async {
      await pumpBadge(
        tester,
        Diary(date: '2026-10-31', source: DiarySource.maibot.code),
      );
      expect(find.text('麦麦'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('详情页 verbose 显示「麦麦写的」', (tester) async {
      await pumpBadge(
        tester,
        Diary(date: '2026-10-31', source: DiarySource.maibot.code),
        verbose: true,
      );
      expect(find.text('麦麦写的'), findsOneWidget);
    });
  });
}
