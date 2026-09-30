import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/services/course_import/template_import_source.dart';
import 'package:diary_app/services/course_import/ics_import_source.dart';
import 'package:diary_app/utils/week_parser.dart';

void main() {
  group('TemplateImportSource.parseRows', () {
    test('标准模板解析', () {
      final draft = TemplateImportSource.parseRows([
        ['课程名称', '教师', '星期', '开始节', '结束节', '周次', '地点'],
        ['高等数学', '张老师', '1', '1', '2', '1-16', '教一101'],
        ['大学英语', '李老师', '3', '3', '4', '1-15单周', '外语楼302'],
      ]);
      expect(draft.courses.length, 2);
      expect(draft.issues, isEmpty);
      final math = draft.courses.first;
      expect(math.name, '高等数学');
      expect(math.sessions.length, 1);
      expect(math.sessions.first.dayOfWeek, 1);
      expect(math.sessions.first.sectionCount, 2);
      expect(math.sessions.first.weeks.length, 16);
      // 单周过滤
      expect(draft.courses[1].sessions.first.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    });

    test('同名课程合并为多个安排', () {
      final draft = TemplateImportSource.parseRows([
        ['课程名称', '教师', '星期', '开始节', '结束节', '周次', '地点'],
        ['高等数学', '张老师', '1', '1', '2', '1-16', 'A'],
        ['高等数学', '张老师', '4', '3', '4', '1-16', 'B'],
      ]);
      expect(draft.courses.length, 1);
      expect(draft.courses.first.sessions.length, 2);
    });

    test('星期支持中文写法', () {
      final draft = TemplateImportSource.parseRows([
        ['课程名称', '教师', '星期', '开始节', '结束节', '周次', '地点'],
        ['体育', '', '周三', '5', '6', '1-16', '操场'],
      ]);
      expect(draft.courses.first.sessions.first.dayOfWeek, 3);
    });

    test('坏行进入 issues 而不中断', () {
      final draft = TemplateImportSource.parseRows([
        ['课程名称', '教师', '星期', '开始节', '结束节', '周次', '地点'],
        ['', '张老师', '1', '1', '2', '1-16', ''], // 无名
        ['物理', '', '9', '1', '2', '1-16', ''], // 星期无效
        ['化学', '', '5', '1', '2', '1-16', ''], // 正常
      ]);
      expect(draft.courses.length, 1);
      expect(draft.issues.length, 2);
      expect(draft.issues.first, contains('第 2 行'));
    });
  });

  group('TemplateImportSource 动态表头', () {
    test('列顺序任意 + 合并节次列', () {
      final draft = TemplateImportSource.parseRows([
        ['地点', '课程名称', '星期', '节次', '周次', '教师'],
        ['教一101', '高等数学', '周一', '1-2', '1-16', '张老师'],
        ['外语楼302', '大学英语', '3', '3-4', '1-15单周', '李老师'],
      ]);
      expect(draft.issues, isEmpty);
      expect(draft.courses.length, 2);
      expect(draft.courses.first.name, '高等数学');
      expect(draft.courses.first.sessions.first.startSection, 1);
      expect(draft.courses.first.sessions.first.sectionCount, 2);
      expect(draft.courses.first.sessions.first.location, '教一101');
    });

    test('表头别名识别（科目/周几/上课周）', () {
      final draft = TemplateImportSource.parseRows([
        ['科目', '周几', '开始节次', '结束节次', '上课周', '教室'],
        ['物理', '星期五', '5', '6', '2-16双周', '实验楼'],
      ]);
      expect(draft.issues, isEmpty);
      final c = draft.courses.first;
      expect(c.name, '物理');
      expect(c.sessions.first.dayOfWeek, 5);
      expect(c.sessions.first.weeks, [2, 4, 6, 8, 10, 12, 14, 16]);
      expect(c.sessions.first.location, '实验楼');
    });

    test('周次缺省按 1-20 周', () {
      final draft = TemplateImportSource.parseRows([
        ['课程名称', '星期', '节次'],
        ['体育', '2', '7-8'],
      ]);
      expect(draft.courses.first.sessions.first.weeks.length, 20);
    });

    test('Excel 数字 toString 成 3.0 也能解析', () {
      final draft = TemplateImportSource.parseRows([
        ['课程名称', '星期', '节次', '周次'],
        ['化学', '3.0', '第1-2节', '1-16'],
      ]);
      expect(draft.issues, isEmpty);
      expect(draft.courses.first.sessions.first.dayOfWeek, 3);
      expect(draft.courses.first.sessions.first.sectionCount, 2);
    });

    test('表头无法识别时回退固定列顺序', () {
      final draft = TemplateImportSource.parseRows([
        ['高等数学', '张老师', '1', '1', '2', '1-16', '教一101'],
      ]);
      expect(draft.courses.length, 1);
      expect(draft.courses.first.name, '高等数学');
    });

    test('周次各种写法', () {
      expect(WeekParser.parseWeeks('1~16'), List.generate(16, (i) => i + 1));
      expect(WeekParser.parseWeeks('第3-5周'), [3, 4, 5]);
      expect(WeekParser.parseWeeks('单周1-7'), [1, 3, 5, 7]);
      expect(WeekParser.parseWeeks('1到4周'), [1, 2, 3, 4]);
      expect(WeekParser.parseWeeks('1、3、5-7'), [1, 3, 5, 6, 7]);
      expect(WeekParser.parseWeeks('全周', totalWeeks: 18).length, 18);
      expect(WeekParser.parseWeeks('（双）2-8'), [2, 4, 6, 8]);
    });
  });

  group('IcsImportSource.parse', () {
    test('标准 VEVENT 解析', () {
      final draft = IcsImportSource.parse('''
BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:高等数学@教一101
DTSTART:20260907T080000
DTEND:20260907T094000
RRULE:FREQ=WEEKLY;UNTIL=20270111T000000
DESCRIPTION:张老师
END:VEVENT
END:VCALENDAR
''', semesterStart: DateTime(2026, 9, 7), totalWeeks: 18);
      expect(draft.courses.length, 1);
      final c = draft.courses.first;
      expect(c.name, '高等数学');
      expect(c.teacher, '张老师');
      expect(c.sessions.first.dayOfWeek, 1); // 2026-09-07 是周一
      expect(c.sessions.first.location, '教一101');
      expect(c.sessions.first.weeks, List.generate(18, (i) => i + 1));
      expect(c.sessions.first.sectionCount, 2); // 100 分钟 → 2 节
    });

    test('INTERVAL=2 隔周', () {
      final draft = IcsImportSource.parse('''
BEGIN:VEVENT
SUMMARY:实验课
DTSTART:20260909T140000
DTEND:20260909T154000
RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=5
END:VEVENT
''', semesterStart: DateTime(2026, 9, 7), totalWeeks: 20);
      expect(draft.courses.first.sessions.first.weeks, [1, 3, 5, 7, 9]);
    });

    test('坏事件不中断解析', () {
      final draft = IcsImportSource.parse('''
BEGIN:VEVENT
DTSTART:20260907T080000
END:VEVENT
BEGIN:VEVENT
SUMMARY:正常课
DTSTART:20260907T100000
DTEND:20260907T104500
END:VEVENT
''', semesterStart: DateTime(2026, 9, 7));
      expect(draft.courses.length, 1);
      expect(draft.issues.length, 1);
    });
  });
}
