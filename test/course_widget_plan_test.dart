import 'dart:convert';

import 'package:diary_app/models/course.dart';
import 'package:diary_app/services/course_widget_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌面小组件的「预计算计划」
///
/// 这份计划是 Dart 与原生之间的**数据契约**：原生侧（Kotlin）只按
/// `day["items"]` 查表渲染，字段名/类型一改就得两边同步。
/// 所以这里把契约钉死，顺带覆盖那些算错就会让小组件显示错课的场景。
void main() {
  // 2026-09-07 是第 1 周周一（与真实教务学期一致）
  final semesterStart = DateTime(2026, 9, 7);

  SemesterConfig semester({int totalWeeks = 20}) => SemesterConfig(
        name: '2026 秋季学期',
        startDate: '2026-09-07',
        totalWeeks: totalWeeks,
      );

  Course course({
    int id = 1,
    String name = '城乡规划管理与法规',
    int color = 0xFFC4956A,
    required int dayOfWeek,
    required int startSection,
    int sectionCount = 2,
    required List<int> weeks,
    String? location,
  }) =>
      Course(
        id: id,
        name: name,
        color: color,
        sessions: [
          CourseSession(
            courseId: id,
            dayOfWeek: dayOfWeek,
            startSection: startSection,
            sectionCount: sectionCount,
            weeks: weeks,
            location: location,
          ),
        ],
      );

  const theme = CourseWidgetTheme.fallback;

  group('计划的日期窗口', () {
    test('默认覆盖 14 天，rangeStart/End 与 days 对齐', () {
      final plan = CourseWidgetPlan.build(
        courses: [],
        semester: semester(),
        theme: theme,
        from: DateTime(2026, 9, 28),
      );

      expect(plan.days, hasLength(CourseWidgetPlan.defaultHorizonDays));
      expect(plan.rangeStart, '2026-09-28');
      expect(plan.rangeEnd, '2026-10-11'); // 28 日起第 14 天
      expect(plan.hasSemester, isTrue);
      expect(plan.semesterName, '2026 秋季学期');
    });

    test('日期键是零填充的 yyyy-MM-dd，原生按它查表', () {
      final plan = CourseWidgetPlan.build(
        courses: [],
        semester: semester(),
        theme: theme,
        from: DateTime(2026, 9, 8),
      );
      expect(plan.days[0].date, '2026-09-08');
      expect(plan.days[0].weekday, DateTime.tuesday);
      expect(plan.days[6].date, '2026-09-14');
    });

    test('跨月也连续', () {
      final plan = CourseWidgetPlan.build(
        courses: [],
        semester: semester(),
        theme: theme,
        from: DateTime(2026, 9, 29),
      );
      expect(plan.dayFor('2026-09-30'), isNotNull);
      expect(plan.dayFor('2026-10-01'), isNotNull);
      // 09-29 起 14 天 → 末日 10-12（含），10-13 已在窗口外
      expect(plan.rangeEnd, '2026-10-12');
      expect(plan.dayFor('2026-10-12'), isNotNull);
      expect(plan.dayFor('2026-10-13'), isNull);
    });
  });

  group('每天排什么课', () {
    test('按星期与周次筛课，并按起始节次排序', () {
      final courses = [
        course(
          id: 1,
          name: '晚课',
          dayOfWeek: DateTime.monday,
          startSection: 9,
          weeks: [4],
          location: 'S1313',
        ),
        course(
          id: 2,
          name: '早课',
          dayOfWeek: DateTime.monday,
          startSection: 1,
          weeks: [4],
          location: 'S1512',
        ),
      ];

      final plan = CourseWidgetPlan.build(
        courses: courses,
        semester: semester(),
        theme: theme,
        from: DateTime(2026, 9, 28), // 第 4 周周一
      );

      final monday = plan.days[0];
      expect(monday.week, 4);
      expect(monday.items.map((e) => e.name).toList(), ['早课', '晚课']);
      expect(monday.items.first.section, 1);
    });

    test('单双周 / 周次集合之外的日期不排课', () {
      final courses = [
        course(
          id: 1,
          name: '单周课',
          dayOfWeek: DateTime.tuesday,
          startSection: 3,
          weeks: [1, 3, 5],
        ),
      ];

      // 第 4 周周二（9/29）→ 不在 [1,3,5] 里
      final plan = CourseWidgetPlan.build(
        courses: courses,
        semester: semester(),
        theme: theme,
        from: DateTime(2026, 9, 29),
      );
      expect(plan.days[0].items, isEmpty);

      // 第 5 周周二（10/6）→ 有课
      final next = CourseWidgetPlan.build(
        courses: courses,
        semester: semester(),
        theme: theme,
        from: DateTime(2026, 10, 6),
      );
      expect(next.days[0].week, 5);
      expect(next.days[0].items, hasLength(1));
    });

    test('节次换算成钟点与分钟数（原生靠它判断已上完/正在上）', () {
      final courses = [
        course(
          id: 1,
          name: '控制性详细规划',
          dayOfWeek: DateTime.monday,
          startSection: 5,
          weeks: [4],
        ),
      ];
      final plan = CourseWidgetPlan.build(
        courses: courses,
        semester: semester(),
        theme: theme,
        from: DateTime(2026, 9, 28),
      );

      final item = plan.days[0].items.single;
      // 默认节次表：第 5 节 14:30-15:15
      expect(item.time, '14:30');
      expect(item.startMinutes, 14 * 60 + 30);
      expect(item.endMinutes, 15 * 60 + 15);
    });

    test('节次表里没有该节次时退化成「第N节」，分钟数为 null（而不是瞎猜）', () {
      final sem = SemesterConfig(
        name: 'x',
        startDate: '2026-09-07',
        sections: const [
          SectionTime(section: 1, startTime: '08:00', endTime: '08:45'),
        ],
      );
      final courses = [
        course(
          id: 1,
          name: '神秘课',
          dayOfWeek: DateTime.monday,
          startSection: 7,
          weeks: [1],
        ),
      ];
      final plan = CourseWidgetPlan.build(
        courses: courses,
        semester: sem,
        theme: theme,
        from: semesterStart,
      );

      final item = plan.days[0].items.single;
      expect(item.time, '第7节');
      expect(item.startMinutes, isNull);
      expect(item.endMinutes, isNull);
    });

    test('地点与课程色一并带上（原生直接拿去渲染）', () {
      final courses = [
        course(
          id: 1,
          name: '房地产开发与经营管理',
          color: 0xFF64B5F6,
          dayOfWeek: DateTime.monday,
          startSection: 9,
          weeks: [1],
          location: '南校区 S1313',
        ),
      ];
      final plan = CourseWidgetPlan.build(
        courses: courses,
        semester: semester(),
        theme: theme,
        from: semesterStart,
      );

      final item = plan.days[0].items.single;
      expect(item.location, '南校区 S1313');
      expect(item.color, 0xFF64B5F6);
    });

    test('没填地点的课 location 是空串而不是 null', () {
      final plan = CourseWidgetPlan.build(
        courses: [
          course(
            id: 1,
            dayOfWeek: DateTime.monday,
            startSection: 1,
            weeks: [1],
          ),
        ],
        semester: semester(),
        theme: theme,
        from: semesterStart,
      );
      expect(plan.days[0].items.single.location, '');
    });
  });

  group('学期之外', () {
    test('开学前的日子 week 为 null 且不排课（原生据此显示「假期中」）', () {
      final plan = CourseWidgetPlan.build(
        courses: [
          course(
            id: 1,
            dayOfWeek: DateTime.friday,
            startSection: 1,
            weeks: [1],
          ),
        ],
        semester: semester(),
        theme: theme,
        from: DateTime(2026, 9, 1), // 开学前
      );

      final first = plan.days.first;
      expect(first.week, isNull);
      expect(first.items, isEmpty);
    });

    test('超出总周数的日子同样是 week=null', () {
      final plan = CourseWidgetPlan.build(
        courses: [],
        semester: semester(totalWeeks: 2),
        theme: theme,
        from: DateTime(2026, 9, 28), // 第 4 周，已超 2 周
      );
      expect(plan.days.first.week, isNull);
    });

    test('没有学期配置时给空计划，hasSemester=false（原生显示导入引导）', () {
      final plan = CourseWidgetPlan.build(
        courses: [
          course(
            id: 1,
            dayOfWeek: DateTime.monday,
            startSection: 1,
            weeks: [1],
          ),
        ],
        semester: null,
        theme: theme,
        from: semesterStart,
      );

      expect(plan.hasSemester, isFalse);
      expect(plan.days, isEmpty);
      expect(plan.semesterName, '');
    });

    test('学期配置的 startDate 是垃圾字符串时也不炸，退化成空计划', () {
      final plan = CourseWidgetPlan.build(
        courses: [],
        semester: SemesterConfig(name: 'x', startDate: '不是日期'),
        theme: theme,
        from: semesterStart,
      );
      expect(plan.hasSemester, isFalse);
    });
  });

  group('JSON 契约（Dart ↔ 原生）', () {
    test('字段名与类型固定，原生 Kotlin 侧按这些键解析', () {
      final plan = CourseWidgetPlan.build(
        courses: [
          course(
            id: 1,
            name: '城乡规划管理与法规',
            dayOfWeek: DateTime.monday,
            startSection: 3,
            weeks: [1],
            location: 'S1512',
          ),
        ],
        semester: semester(),
        theme: theme,
        from: semesterStart,
      );

      final json = jsonDecode(jsonEncode(plan.toJson())) as Map;
      expect(json['schemaVersion'], CourseWidgetPlan.currentSchemaVersion);
      expect(json['hasSemester'], true);
      expect(json['semesterName'], '2026 秋季学期');
      expect(json['rangeStart'], '2026-09-07');
      expect(json['rangeEnd'], isA<String>());

      final day = (json['days'] as List).first as Map;
      expect(day['date'], '2026-09-07');
      expect(day['week'], 1);
      expect(day['weekday'], DateTime.monday);

      final item = (day['items'] as List).single as Map;
      expect(item.keys.toSet(), {
        'time',
        'startMin',
        'endMin',
        'section',
        'name',
        'location',
        'color',
      });
      expect(item['name'], '城乡规划管理与法规');
      expect(item['section'], 3);
      // 颜色是 ARGB int，超过 int32 —— 原生必须按 long 解析
      expect(item['color'], 0xFFC4956A);

      final themeJson = json['theme'] as Map;
      expect(themeJson.keys.toSet(), {
        'background',
        'foreground',
        'secondary',
        'accent',
        'divider',
      });
    });

    test('序列化 → 反序列化后内容不丢', () {
      final plan = CourseWidgetPlan.build(
        courses: [
          course(
            id: 1,
            dayOfWeek: DateTime.monday,
            startSection: 3,
            weeks: [1],
            location: 'S1512',
          ),
        ],
        semester: semester(),
        theme: const CourseWidgetTheme(
          background: 0xFF221E1B,
          foreground: 0xFFFDF8F0,
          secondary: 0xFF8A7D6F,
          accent: 0xFFC4956A,
          divider: 0xFF3A332E,
        ),
        from: semesterStart,
      );

      final back = CourseWidgetPlan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>,
      );

      expect(back.rangeStart, plan.rangeStart);
      expect(back.rangeEnd, plan.rangeEnd);
      expect(back.days, hasLength(plan.days.length));
      expect(back.days.first.week, plan.days.first.week);
      expect(back.days.first.items.single.name,
          plan.days.first.items.single.name);
      expect(
        back.days.first.items.single.startMinutes,
        plan.days.first.items.single.startMinutes,
      );
      expect(back.theme.background, 0xFF221E1B);
      expect(back.theme.divider, 0xFF3A332E);
    });

    test('JSON 里 days 是数组（原生按数组遍历），不是对象', () {
      final plan = CourseWidgetPlan.build(
        courses: [],
        semester: semester(),
        theme: theme,
        from: semesterStart,
      );
      final json = plan.toJson();
      expect(json['days'], isA<List>());
    });
  });

  group('切主题只换配色', () {
    test('withTheme 保留课程数据，只替换 theme', () {
      final plan = CourseWidgetPlan.build(
        courses: [
          course(
            id: 1,
            name: '高数',
            dayOfWeek: DateTime.monday,
            startSection: 1,
            weeks: [1],
          ),
        ],
        semester: semester(),
        theme: theme,
        from: semesterStart,
      );

      const dark = CourseWidgetTheme(
        background: 0xFF221E1B,
        foreground: 0xFFFDF8F0,
        secondary: 0xFF9E9188,
        accent: 0xFFC4956A,
        divider: 0xFF3A332E,
      );
      final restyled = plan.withTheme(dark);

      expect(restyled.theme.background, 0xFF221E1B);
      expect(restyled.days, same(plan.days));
      expect(restyled.rangeStart, plan.rangeStart);
      expect(restyled.semesterName, plan.semesterName);
    });
  });
}
