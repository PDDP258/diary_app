import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/utils/week_parser.dart';

void main() {
  group('WeekParser.parseWeeks', () {
    final cases = <String, List<int>>{
      '1-16周': List.generate(16, (i) => i + 1),
      '1-16': List.generate(16, (i) => i + 1),
      '1,3,5': [1, 3, 5],
      '1，3，5周': [1, 3, 5], // 全角逗号
      '2,4,6-8周': [2, 4, 6, 7, 8],
      '1-8,10-16周': [
        ...List.generate(8, (i) => i + 1),
        ...List.generate(7, (i) => i + 10),
      ],
      '1-15周(单)': [1, 3, 5, 7, 9, 11, 13, 15],
      '1-15单周': [1, 3, 5, 7, 9, 11, 13, 15],
      '2-16周(双)': [2, 4, 6, 8, 10, 12, 14, 16],
      '2-16双': [2, 4, 6, 8, 10, 12, 14, 16],
      '3周': [3],
      ' 1 - 4 周 ': [1, 2, 3, 4], // 空白容忍
      '1－4周': [1, 2, 3, 4], // 全角连字符
      '1,1,2-3,2': [1, 2, 3], // 去重排序
    };

    cases.forEach((input, expected) {
      test('"$input" -> $expected', () {
        expect(WeekParser.parseWeeks(input), expected);
      });
    });

    test('空字符串抛 FormatException', () {
      expect(() => WeekParser.parseWeeks(''), throwsFormatException);
    });
    test('无效区间抛 FormatException', () {
      expect(() => WeekParser.parseWeeks('5-3周'), throwsFormatException);
      expect(() => WeekParser.parseWeeks('abc'), throwsFormatException);
      expect(() => WeekParser.parseWeeks('0-4周'), throwsFormatException);
    });
  });

  group('WeekParser.formatWeeks', () {
    test('紧凑格式化', () {
      expect(WeekParser.formatWeeks([1, 2, 3, 5, 7, 9]), '1-3,5,7,9');
      expect(WeekParser.formatWeeks([1]), '1');
      expect(WeekParser.formatWeeks([]), '');
      expect(WeekParser.formatWeeks([1, 3, 5]), '1,3,5');
      expect(WeekParser.formatWeeks([3, 1, 2]), '1-3'); // 排序
    });

    test('与 parseWeeks 互逆', () {
      final weeks = [1, 2, 3, 5, 7, 8, 9, 12];
      expect(WeekParser.parseWeeks(WeekParser.formatWeeks(weeks)), weeks);
    });
  });

  group('WeekParser.currentWeek', () {
    final start = DateTime(2026, 9, 7); // 周一开学

    test('开学当天是第 1 周', () {
      expect(
          WeekParser.currentWeek(
              semesterStart: start, totalWeeks: 20, date: DateTime(2026, 9, 7)),
          1);
    });
    test('开学后第 8 天是第 2 周', () {
      expect(
          WeekParser.currentWeek(
              semesterStart: start,
              totalWeeks: 20,
              date: DateTime(2026, 9, 14)),
          2);
    });
    test('开学前返回 null', () {
      expect(
          WeekParser.currentWeek(
              semesterStart: start, totalWeeks: 20, date: DateTime(2026, 9, 6)),
          isNull);
    });
    test('超出总周数返回 null', () {
      expect(
          WeekParser.currentWeek(
              semesterStart: start, totalWeeks: 2, date: DateTime(2026, 9, 21)),
          isNull);
    });
    test('总周数最后一周周日仍有效', () {
      expect(
          WeekParser.currentWeek(
              semesterStart: start, totalWeeks: 2, date: DateTime(2026, 9, 20)),
          2);
    });
  });
}
