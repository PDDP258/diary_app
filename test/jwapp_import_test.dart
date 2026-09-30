/// jwapp（教务系统）导入解析测试
///
/// fixture 是**真实教务响应**脱敏而来（只换掉学号/姓名），
/// 由 `tool/make_jwapp_fixture.js` 生成 —— 覆盖真实长度、中文、
/// 【本】前缀、逗号分隔教师等真实特征。
library;

import 'dart:io';

import 'package:diary_app/models/course.dart';
import 'package:diary_app/screens/jwapp_login_screen.dart';
import 'package:diary_app/services/course_import/jwapp/jwapp_client.dart';
import 'package:diary_app/services/course_import/jwapp/jwapp_course_parser.dart';
import 'package:diary_app/services/course_import/jwapp/jwapp_endpoints.dart';
import 'package:diary_app/services/course_import/jwapp/jwapp_models.dart';
import 'package:diary_app/services/course_import/jwapp/jwapp_response.dart';
import 'package:diary_app/services/course_import/jwapp/jwapp_semester_parser.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/jwapp/$name').readAsStringSync();

/// 测试固定的「今天」。
///
/// 当前学期判定依赖当天日期，必须写死 —— 用 `DateTime.now()` 的话，
/// 过几个月这些断言会自己失效。
final _testNow = DateTime(2026, 9, 29);

void main() {
  // ===================== 1. 响应拆包 =====================

  group('JwappResponse 拆包', () {
    test('正常响应取出 rows', () {
      final rows = JwappResponse.unwrapRows(
        '{"code":"0","datas":{"t":{"rows":[{"KCM":"高数"}]}}}',
        key: 't',
      );
      expect(rows, hasLength(1));
      expect(rows.first['KCM'], '高数');
    });

    test('表名传 null 时自动发现第一张含 rows 的表', () {
      final rows = JwappResponse.unwrapRows(
        '{"code":"0","datas":{"a":{"totalSize":1,"rows":[{"x":1}]}}}',
      );
      expect(rows, hasLength(1));
    });

    test('HTML 错误页 → 识别为登录态失效（不是「这学期没课」）', () {
      expect(
        () => JwappResponse.unwrapRows(
            '<!DOCTYPE html><html><title>系统异常</title></html>'),
        throwsA(isA<JwappException>()
            .having((e) => e.kind, 'kind', JwappErrorKind.notJson)),
      );
    });

    test('业务码非 0 → businessCode', () {
      expect(
        () => JwappResponse.unwrapRows('{"code":"1","msg":"参数错误","datas":{}}'),
        throwsA(isA<JwappException>()
            .having((e) => e.kind, 'kind', JwappErrorKind.businessCode)),
      );
    });

    test('空响应 / 非 JSON → notJson', () {
      expect(() => JwappResponse.unwrapRows('   '),
          throwsA(isA<JwappException>()));
      expect(() => JwappResponse.unwrapRows('not json at all'),
          throwsA(isA<JwappException>()));
    });

    test('指定的表名不存在 → malformed', () {
      expect(
        () => JwappResponse.unwrapRows('{"code":"0","datas":{"other":{}}}',
            key: 't'),
        throwsA(isA<JwappException>()
            .having((e) => e.kind, 'kind', JwappErrorKind.malformed)),
      );
    });
  });

  // ===================== 2. SKZC 周次位图 =====================

  group('SKZC 周次位图', () {
    test('按实际长度解析（同一响应里 20 位与 17 位混用）', () {
      expect(JwappCourseParser.parseWeekBitmap('00010000000000000000'), [4]);
      expect(JwappCourseParser.parseWeekBitmap('100000000000000000'), [1]);
      expect(
        JwappCourseParser.parseWeekBitmap('111001111110000000'),
        [1, 2, 3, 6, 7, 8, 9, 10, 11],
      );
    });

    test('第 18 位之后仍有 1 时不会被总周数截断', () {
      final w = JwappCourseParser.parseWeekBitmap('11111111111111111111');
      expect(w, hasLength(20));
      expect(w.last, 20);
    });

    test('全 0 / 空串 / 非 1 字符 → 无课周', () {
      expect(JwappCourseParser.parseWeekBitmap('00000000000000000000'),
          isEmpty);
      expect(JwappCourseParser.parseWeekBitmap(''), isEmpty);
      expect(JwappCourseParser.parseWeekBitmap('---'), isEmpty);
    });
  });

  // ===================== 3. 教师归一化 =====================

  group('教师归一化', () {
    test('重复教师去重（真实数据里的「张刚,张刚」）', () {
      expect(JwappCourseParser.normalizeTeacher('张刚,张刚'), '张刚');
    });

    test('多教师保留首次出现顺序', () {
      expect(JwappCourseParser.normalizeTeacher('张三,李四'), '张三,李四');
      expect(JwappCourseParser.normalizeTeacher('张三、李四;王五'), '张三,李四,王五');
    });

    test('空值 / 纯分隔符 → null', () {
      expect(JwappCourseParser.normalizeTeacher(null), isNull);
      expect(JwappCourseParser.normalizeTeacher('   '), isNull);
      expect(JwappCourseParser.normalizeTeacher(',,；'), isNull);
    });
  });

  // ===================== 4. 地点合成 =====================

  group('地点合成', () {
    test('校区 + 教室', () {
      expect(
        JwappCourseParser.composeLocation(
            {'JASMC': 'S1608', 'XXXQMC': '南校区'}),
        '南校区 S1608',
      );
    });

    test('只有教室 / 只有校区', () {
      expect(JwappCourseParser.composeLocation({'JASMC': 'S1608'}), 'S1608');
      expect(JwappCourseParser.composeLocation({'XXXQMC': '南校区'}), '南校区');
    });

    test('都为空 → null', () {
      expect(JwappCourseParser.composeLocation({}), isNull);
    });

    test('教室名已含校区则不重复拼接', () {
      expect(
        JwappCourseParser.composeLocation(
            {'JASMC': '南校区S1608', 'XXXQMC': '南校区'}),
        '南校区S1608',
      );
    });
  });

  // ===================== 5. 单条记录容错 =====================

  group('单条记录容错', () {
    test('缺课程名 → 记 issue 并跳过', () {
      final r = JwappCourseParser.parseRows([
        {'KCM': '', 'SKXQ': 1, 'KSJC': 1, 'JSJC': 2, 'SKZC': '11'},
      ]);
      expect(r.draft.courses, isEmpty);
      expect(r.draft.issues.single, contains('缺少课程名'));
    });

    test('SKXQ 越界时用 SKXQ_DISPLAY 兜底', () {
      final r = JwappCourseParser.parseRows([
        {
          'KCM': '高数',
          'SKXQ': 9,
          'SKXQ_DISPLAY': '星期四',
          'KSJC': 1,
          'JSJC': 2,
          'SKZC': '11',
        },
      ]);
      expect(r.draft.courses.single.sessions.single.dayOfWeek, 4);
      expect(r.draft.issues, isEmpty);
    });

    test('星期彻底无法识别 → 跳过', () {
      final r = JwappCourseParser.parseRows([
        {
          'KCM': '高数',
          'SKXQ': 0,
          'SKXQ_DISPLAY': '',
          'KSJC': 1,
          'JSJC': 2,
          'SKZC': '11',
        },
      ]);
      expect(r.draft.courses, isEmpty);
      expect(r.draft.issues.single, contains('星期无法识别'));
    });

    test('周次全 0 → 跳过（教务里常见于「时间待定」的课）', () {
      final r = JwappCourseParser.parseRows([
        {'KCM': '高数', 'SKXQ': 1, 'KSJC': 1, 'JSJC': 2, 'SKZC': '0000'},
      ]);
      expect(r.draft.courses, isEmpty);
      expect(r.draft.issues.single, contains('周次为空'));
    });

    test('JSJC < KSJC → 按单节处理并给出提示', () {
      final r = JwappCourseParser.parseRows([
        {'KCM': '高数', 'SKXQ': 1, 'KSJC': 5, 'JSJC': 3, 'SKZC': '11'},
      ]);
      expect(r.draft.courses.single.sessions.single.sectionCount, 1);
      expect(r.notices.any((n) => n.contains('节次区间异常')), isTrue);
    });

    test('同一时段拆成多行 → 合并为一条并取 weeks 并集（调课场景）', () {
      final r = JwappCourseParser.parseRows([
        {
          'KCM': '高数',
          'SKJS': '张刚',
          'SKXQ': 3,
          'KSJC': 1,
          'JSJC': 4,
          'SKZC': '11100000000000000000',
        },
        {
          'KCM': '高数',
          'SKJS': '张刚,张刚',
          'SKXQ': 3,
          'KSJC': 1,
          'JSJC': 4,
          'SKZC': '00010000000000000000',
        },
      ]);
      expect(r.draft.courses, hasLength(1)); // 教师去重后是同一门课
      final sessions = r.draft.courses.single.sessions;
      expect(sessions, hasLength(1)); // 同一时段合并
      expect(sessions.single.weeks, [1, 2, 3, 4]);
    });

    test('同课程不同时段 → 各自成条', () {
      final r = JwappCourseParser.parseRows([
        {'KCM': '高数', 'SKXQ': 1, 'KSJC': 1, 'JSJC': 2, 'SKZC': '11'},
        {'KCM': '高数', 'SKXQ': 3, 'KSJC': 5, 'JSJC': 6, 'SKZC': '11'},
      ]);
      expect(r.draft.courses.single.sessions, hasLength(2));
    });

    test('同名课程不同教师 → 视为两门课', () {
      final r = JwappCourseParser.parseRows([
        {'KCM': '高数', 'SKJS': '张三', 'SKXQ': 1, 'KSJC': 1, 'JSJC': 2, 'SKZC': '11'},
        {'KCM': '高数', 'SKJS': '李四', 'SKXQ': 2, 'KSJC': 1, 'JSJC': 2, 'SKZC': '11'},
      ]);
      expect(r.draft.courses, hasLength(2));
    });

    test('空 rows → 空草稿且不抛错', () {
      final r = JwappCourseParser.parseRows([]);
      expect(r.draft.courses, isEmpty);
      expect(r.rawCount, 0);
      expect(r.maxSection, 0);
    });
  });

  // ===================== 6. 端到端：真实课表 =====================

  group('端到端：真实课表 fixture', () {
    late JwappParseResult result;

    setUpAll(() {
      result = JwappCourseParser.parse(_fixture('courses_2026-2027-1.json'));
    });

    test('14 条记录 → 3 门课 / 10 个上课安排 / 0 条失败', () {
      expect(result.rawCount, 14);
      expect(result.draft.courses, hasLength(3));
      expect(result.draft.sessionCount, 10);
      expect(result.draft.issues, isEmpty);
    });

    test('课程名保留教务原文，教师已去重', () {
      final ctrl = result.draft.courses
          .firstWhere((c) => c.name.contains('控制性详细规划'));
      expect(ctrl.name, '【本】控制性详细规划');
      expect(ctrl.teacher, '张刚');
      expect(ctrl.sessions, hasLength(6));
    });

    test('被调课拆开的两条记录合并为一条，周次是并集', () {
      final ctrl = result.draft.courses
          .firstWhere((c) => c.name.contains('控制性详细规划'));
      final wed = ctrl.sessions
          .firstWhere((s) => s.dayOfWeek == 3 && s.startSection == 1);
      expect(wed.sectionCount, 4);
      expect(wed.weeks, [1, 2, 3, 4]); // 原始为 [1,2,3] 与 [4] 两条
      expect(wed.location, '南校区 S1608');
    });

    test('周次不连续时不补周（1,2,3,[跳4],5…）', () {
      final law = result.draft.courses
          .firstWhere((c) => c.name.contains('城乡规划管理与法规'));
      final tue = law.sessions.firstWhere((s) => s.dayOfWeek == 2);
      expect(tue.weeks, [1, 2, 3, 4, 6, 7, 8, 9, 10, 11]);
    });

    test('记录最大节次，供学期节次表撑开', () {
      expect(result.maxSection, 10);
    });

    test('调课信息汇总为提示，不注入课程数据', () {
      expect(result.notices, hasLength(1));
      expect(result.notices.single, contains('调课'));
    });

    test('学期编码取自记录里的 XNXQDM', () {
      expect(result.semesterCode, '2026-2027-1');
    });

    test('每门课都拿到了颜色（不全是默认色）', () {
      final colors = result.draft.courses.map((c) => c.color).toSet();
      expect(colors, hasLength(3));
    });
  });

  // ===================== 7. 学期配置 =====================

  group('学期配置解析', () {
    late List<JwappSemester> semesters;

    setUpAll(() {
      semesters = JwappSemesterParser.parseAll(_fixture('semesters.json'));
    });

    test('解析出全部学期（fixture 全量保留，含脏行）', () {
      // 曾经 fixture 只留最新 12 条，恰好截掉了末尾那条 PX=null 的脏行，
      // 于是「当前学期选错」的 bug 在单测里完全看不见。现在全量保留。
      expect(semesters, hasLength(80));
    });

    test('当前学期 = 今天落在其区间内的那个（2026-09-29 → 2026-2027-1）', () {
      final cur = JwappSemesterParser.pickCurrent(
        semesters,
        now: _testNow,
      )!;
      expect(cur.code, '2026-2027-1');
      expect(cur.startDate, '2026-09-07');
      expect(cur.totalWeeks, 20);
      expect(cur.displayName, '2026-2027学年 秋');
    });

    test('PX 为 null 的脏行不会被误判成当前学期', () {
      // 真实数据里有一条 2025-2026-3（暑假小学期）：PX=null、SFSY=1、
      // 开学日 2026-08-31、总周数 1。若把 PX=null 当成 0 参与排序，它会排到
      // 最前面被选中 —— 后果是课表按 2025-2026-3 查询，一门课都查不到，
      // 学期配置也被写成错的开学日与总周数。
      final dirty = JwappSemesterParser.findByCode(semesters, '2025-2026-3')!;
      expect(dirty.sortOrder, isNull);
      expect(dirty.startDate, '2026-08-31');
      expect(dirty.totalWeeks, 1);

      expect(
        JwappSemesterParser.pickCurrent(semesters, now: DateTime(2026, 9, 29))!
            .code,
        isNot('2025-2026-3'),
      );
    });

    test('按学期编码查找', () {
      expect(
        JwappSemesterParser.findByCode(semesters, '2025-2026-2')!.startDate,
        '2026-03-02',
      );
      expect(JwappSemesterParser.findByCode(semesters, '1999-2000-1'), isNull);
    });

    test('顺序被打乱后当前学期仍然正确（不依赖响应顺序）', () {
      expect(
        JwappSemesterParser.pickCurrent(semesters.reversed.toList(),
                now: _testNow)!
            .code,
        '2026-2027-1',
      );
    });

    test('转成本地学期配置', () {
      final cfg =
          JwappSemesterParser.pickCurrent(semesters, now: _testNow)!.toSemesterConfig();
      expect(cfg.startDate, '2026-09-07');
      expect(cfg.totalWeeks, 20);
      expect(cfg.sections, hasLength(10));
      expect(cfg.isActive, isTrue);
    });

    test('课表节次超出默认 10 节时，节次表被撑长且时间递增', () {
      final cfg = JwappSemesterParser.pickCurrent(semesters, now: _testNow)!
          .toSemesterConfig(minSections: 12);
      expect(cfg.sections, hasLength(12));
      expect(cfg.sections[10].section, 11);
      expect(
        cfg.sections[10].startTime.compareTo(cfg.sections[9].startTime),
        greaterThan(0),
      );
    });

    test('缺少必要字段的行被忽略，不会写坏学期配置', () {
      final r = JwappSemesterParser.parseAll(
        '{"code":"0","datas":{"cxjcs":{"rows":['
        '{"XN":"2026-2027","XQ":"1","XQKSRQ":null,"ZZC":20,"PX":1},'
        '{"XN":"2026-2027","XQ":"1","XQKSRQ":"2026-09-07 00:00:00","ZZC":0,"PX":2}'
        ']}}}',
      );
      expect(r, isEmpty);
    });

    test('已有学期配置时保留用户改过的节次时间', () {
      final sem = JwappSemesterParser.pickCurrent(semesters, now: _testNow)!;
      final mine = [
        const SectionTime(section: 1, startTime: '09:30', endTime: '10:15'),
        const SectionTime(section: 2, startTime: '10:25', endTime: '11:10'),
      ];
      final existing = SemesterConfig(
        name: '我的手填学期',
        startDate: '2026-09-01',
        totalWeeks: 18,
        sections: mine,
        classMinutes: 50,
      );

      final cfg = sem.toSemesterConfig(minSections: 2, mergeWith: existing);
      // 教务数据覆盖开学日与总周数
      expect(cfg.startDate, '2026-09-07');
      expect(cfg.totalWeeks, 20);
      expect(cfg.name, '2026-2027学年 秋');
      // 用户改过的作息与设置保留
      expect(cfg.sections.first.startTime, '09:30');
      expect(cfg.classMinutes, 50);
      expect(cfg.id, existing.id);
    });
  });

  // ===================== 7b. 当前学期判定（按日期） =====================

  group('当前学期判定（按日期，不靠 PX）', () {
    JwappSemester mk(String year, String term, String start, int weeks,
            {int? px}) =>
        JwappSemester(
          academicYear: year,
          term: term,
          startDate: start,
          totalWeeks: weeks,
          sortOrder: px,
          inUse: true,
        );

    test('今天落在学期区间内 → 选它', () {
      final all = [
        mk('2025-2026', '1', '2025-09-08', 20, px: 9923),
        mk('2025-2026', '2', '2026-03-02', 20, px: 9922),
        mk('2026-2027', '1', '2026-09-07', 20, px: 9921),
      ];
      expect(
        JwappSemesterParser.pickCurrent(all, now: DateTime(2026, 10, 15))!.code,
        '2026-2027-1',
      );
    });

    test('落在学期之间的假期 → 选刚结束的那学期', () {
      final all = [
        mk('2025-2026', '2', '2026-03-02', 18, px: 9922),
        mk('2026-2027', '1', '2026-09-07', 20, px: 9921),
      ];
      expect(
        JwappSemesterParser.pickCurrent(all, now: DateTime(2026, 7, 20))!.code,
        '2025-2026-2',
      );
    });

    test('全部学期都还没开学 → 选最早开学的', () {
      final all = [
        mk('2026-2027', '2', '2027-03-01', 20, px: 9920),
        mk('2026-2027', '1', '2026-09-07', 20, px: 9921),
      ];
      expect(
        JwappSemesterParser.pickCurrent(all, now: DateTime(2026, 8, 1))!.code,
        '2026-2027-1',
      );
    });

    test('第 N 周最后一天仍算在学期内', () {
      final all = [mk('2026-2027', '1', '2026-09-07', 20, px: 9921)];
      // 第 20 周最后一天 = 2026-09-07 + 20×7 - 1 天 = 2027-01-24
      expect(
        JwappSemesterParser.pickCurrent(all, now: DateTime(2027, 1, 24))!.code,
        '2026-2027-1',
      );
    });

    test('开学日都不可解析时退回 PX 排序（null 排最后）', () {
      final all = [
        JwappSemester(
          academicYear: '2025-2026',
          term: '3',
          startDate: '',
          totalWeeks: 1,
          sortOrder: null,
          inUse: true,
        ),
        mk('2025-2026', '2', '', 18, px: 9922),
      ];
      expect(
        JwappSemesterParser.pickCurrent(all, now: _testNow)!.code,
        '2025-2026-2',
      );
    });

    test('空列表返回 null', () {
      expect(
        JwappSemesterParser.pickCurrent(<JwappSemester>[], now: _testNow),
        isNull,
      );
    });
  });

  // ===================== 8. 取数（注入脚本 + 回传解析） =====================

  group('注入脚本生成', () {
    test('用绝对地址取数，不依赖当前页面位置', () {
      final script = JwappClient.buildFetchScript(
        origin: 'https://ehall.nwafu.edu.cn',
        path: '/jwapp/sys/wdkbby/modules/xskcb/cxxszhxqkb.do',
        formBody: 'XNXQDM=2026-2027-1',
      );
      expect(
        script,
        contains(
            'https://ehall.nwafu.edu.cn/jwapp/sys/wdkbby/modules/xskcb/cxxszhxqkb.do'),
      );
      expect(script, contains('XNXQDM=2026-2027-1'));
      expect(script, contains(JwappClient.handlerName));
      // 教务接口要 CAS 登录态，必须带上 Cookie
      expect(script, contains("credentials: 'include'"));
    });

    test('无表单参数时不写 body 字段（学期配置接口免参）', () {
      final script = JwappClient.buildFetchScript(
        origin: 'https://ehall.nwafu.edu.cn',
        path: '/x.do',
      );
      // 注意：脚本里的 send() 自身带 `body: t`（那是回传的响应体），
      // 所以不能笼统断言 `body:` 不存在。这里要判别的是 fetch 的「请求选项」里没有请求体 ——
      // 请求体一律写成 JSON 编码后的字符串字面量（body: "..."），据此判定。
      expect(script, isNot(contains('body: "')));
    });

    test('路径里的特殊字符被正确转义，不会打断脚本', () {
      final script = JwappClient.buildFetchScript(
        origin: 'https://a.edu.cn',
        path: '/x.do',
        formBody: 'a="b"&\n',
      );
      expect(script, contains(r'a=\"b\"'));
      expect(script, isNot(contains('body: a=')));
    });
  });

  group('回传消息解析', () {
    test('成功回传', () {
      final r = JwappClient.parseMessage(
        '{"ok":true,"url":"https://a/b.do","status":200,"body":"{\\"code\\":\\"0\\"}"}',
      );
      expect(r.ok, isTrue);
      expect(r.hasBody, isTrue);
      expect(r.body, '{"code":"0"}');
      expect(r.status, 200);
    });

    test('网络失败回传', () {
      final r = JwappClient.parseMessage('{"ok":false,"url":"u","error":"boom"}');
      expect(r.ok, isFalse);
      expect(r.hasBody, isFalse);
      expect(r.error, 'boom');
    });

    test('坏数据给出明确错误，而不是静默当作空数据', () {
      expect(JwappClient.parseMessage(null).error, isNotNull);
      expect(JwappClient.parseMessage(123).error, isNotNull);
      expect(JwappClient.parseMessage('not-json').error, isNotNull);
      expect(JwappClient.parseMessage('').error, isNotNull);
    });

    test('空白 body 不算有效数据', () {
      final r = JwappClient.parseMessage('{"ok":true,"url":"u","body":"   "}');
      expect(r.hasBody, isFalse);
    });

    test('回包归属判定：地址一致才算本次取数', () {
      const coursePath = '/jwapp/sys/wdkbby/modules/xskcb/cxxszhxqkb.do';
      const semesterPath = '/jwapp/sys/wdkbby/modules/jshkcb/cxjcs.do';

      final course = JwappClient.parseMessage(
        '{"ok":true,"url":"https://ehall.nwafu.edu.cn$coursePath","body":"{}"}',
      );
      expect(JwappClient.belongsTo(course, coursePath), isTrue);
      // 上一次超时的学期回包迟到 —— 不能被当成课表的响应
      expect(JwappClient.belongsTo(course, semesterPath), isFalse);
    });

    test('回包地址缺失或不可解析时不拦截（宁可放行也别卡死取数）', () {
      final noUrl = JwappClient.parseMessage('{"ok":false,"error":"boom"}');
      expect(JwappClient.belongsTo(noUrl, '/x.do'), isTrue);

      final broken = JwappClient.parseMessage('{"ok":true,"url":"","body":"{}"}');
      expect(JwappClient.belongsTo(broken, '/x.do'), isTrue);
    });
  });

  group('接入点配置', () {
    test('预置西农，接口路径拼装正确', () {
      expect(JwappEndpoints.presets, isNotEmpty);
      final ep = JwappEndpoints.presets.first;
      expect(ep.isValid, isTrue);
      expect(ep.origin, 'https://ehall.nwafu.edu.cn');
      expect(ep.courseTablePath, '/jwapp/sys/wdkbby/modules/xskcb/cxxszhxqkb.do');
      expect(ep.semesterPath, '/jwapp/sys/wdkbby/modules/jshkcb/cxjcs.do');
    });

    test('手工域名输入容错：补协议、补尾斜杠、去空格', () {
      expect(JwappEndpoints.fromHostInput(' ehall.x.edu.cn ')!.homeUrl,
          'https://ehall.x.edu.cn/');
      expect(JwappEndpoints.fromHostInput('http://a.b.c')!.homeUrl,
          'http://a.b.c/');
      expect(JwappEndpoints.fromHostInput('') , isNull);
      expect(JwappEndpoints.fromHostInput('   '), isNull);
    });

    test('序列化往返一致', () {
      final ep = JwappEndpoints.fromMap(JwappEndpoints.nwafu.toMap());
      expect(ep.name, JwappEndpoints.nwafu.name);
      expect(ep.homeUrl, JwappEndpoints.nwafu.homeUrl);
      expect(ep.modulePath, JwappEndpoints.defaultModulePath);
      expect(ep.isValid, isTrue);
    });

    test('老数据缺 modulePath 时回落到默认值', () {
      final ep =
          JwappEndpoints.fromMap({'name': 'x', 'homeUrl': 'https://x.edu.cn/'});
      expect(ep.modulePath, JwappEndpoints.defaultModulePath);
      expect(ep.courseTablePath, contains('/jwapp/sys/wdkbby/'));
    });
  });

  // ===================== 8. 登录页 WebView 模式 =====================

  group('登录页 WebView 默认桌面模式', () {
    test('UA 是桌面版，不能是移动端', () {
      const ua = JwappClient.desktopUserAgent;
      expect(ua, contains('Windows NT'));
      expect(ua, contains('Chrome/'));
      final lower = ua.toLowerCase();
      for (final mobile in ['android', 'iphone', 'ipad', 'mobile']) {
        expect(lower, isNot(contains(mobile)), reason: 'UA 里不该出现「$mobile」');
      }
    });

    test('页面设置里的桌面模式关键项都开着', () {
      final s = buildJwappWebViewSettings();
      // 桌面 UA：让教务系统下发桌面版页面
      expect(s.userAgent, JwappClient.desktopUserAgent);
      // iOS 侧走官方开关（Android 忽略该字段）
      expect(s.preferredContentMode, UserPreferredContentMode.DESKTOP);
      // 宽视口：让页面自己的 viewport meta 生效，布局宽度交给注入脚本控制
      expect(s.useWideViewPort, isTrue);
      // 关键回归点：overview 模式会把「铺满宽度」的那个缩放当成**缩放下限**，
      // 于是只能放大、缩不回去（2026-09-30 真机反馈）。必须关掉。
      expect(s.loadWithOverviewMode, isFalse);
      // 缩放：既要能用，也要有个看得见、点得到的入口（桌面版页面字号偏小）
      expect(s.supportZoom, isTrue);
      expect(s.builtInZoomControls, isTrue);
      expect(s.displayZoomControls, isTrue);
      // 取数依赖 JS 与页面上下文
      expect(s.javaScriptEnabled, isTrue);
      expect(s.domStorageEnabled, isTrue);
    });

    test('桌面 UA 是最终生效值（不是「追加」语义）', () {
      final s = buildJwappWebViewSettings();
      // 文档：设置 userAgent 会覆盖 applicationNameForUserAgent。
      // 这里断言我们走的是覆盖语义，避免将来有人改用 append 写法而把桌面 UA 稀释掉。
      expect(s.userAgent, isNotNull);
      expect(s.userAgent, isNot(contains('wv)')));
    });
  });

  // ===================== 12. viewport 重写脚本 =====================

  group('viewport 重写脚本（桌面布局 + 双向缩放）', () {
    test('显式给出最小/最大缩放，两个方向都能调', () {
      final s = JwappClient.buildViewportScript();
      expect(s, contains('meta[name="viewport"]'));
      expect(s, contains('initial-scale='));
      expect(s, contains('minimum-scale='));
      expect(s, contains('maximum-scale=5.0'));
      expect(s, contains('user-scalable=yes'));
      // 不该再往页面上写死「禁止缩放」
      expect(s, isNot(contains('user-scalable=no')));
    });

    test('最小缩放明显小于打开时的缩放 —— 这才叫「能缩小」', () {
      final s = JwappClient.buildViewportScript();
      // 打开时 fit、最小 fit*0.5：留出一半的缩小余量
      expect(s, contains('Math.min(1, deviceWidth / layoutWidth)'));
      expect(s, contains('fit * 0.5'));
    });

    test('布局宽度钉在桌面宽度，页面写 device-width 也挤不成移动布局', () {
      final s = JwappClient.buildViewportScript();
      expect(
        s,
        contains('var DESKTOP_WIDTH = ${JwappClient.desktopLayoutWidth}'),
      );
      // 我们自己不写 width=device-width
      expect(s, isNot(contains('width=device-width')));
    });

    test('页面自己声明了数字宽度时尊重它，只在 device-width/缺省时才套桌面宽度', () {
      final s = JwappClient.buildViewportScript();
      expect(s, contains(r'width\s*=\s*([0-9]+)'));
      expect(s, contains('declared ? parseInt(declared[1], 10) : DESKTOP_WIDTH'));
    });

    test('整串覆盖而不是追加，反复执行 content 不会越滚越长', () {
      final s = JwappClient.buildViewportScript();
      // 幂等：内容一致就直接返回
      expect(s, contains("meta.getAttribute('content') === next"));
      // 不存在把原值拼后面的写法
      expect(s, isNot(contains("getAttribute('content') + ")));
    });

    test('自带短轮询，兜住 SPA 路由切换后重设 viewport 的情况', () {
      final s = JwappClient.buildViewportScript();
      expect(s, contains('setInterval'));
      expect(s, contains('clearInterval'));
    });
  });
}
