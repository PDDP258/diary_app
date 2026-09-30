import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/day_of_week.dart';

void main() {
  group('tryParseDayOfWeek', () {
    test('覆盖常见写法', () {
      expect(tryParseDayOfWeek('周一'), 1);
      expect(tryParseDayOfWeek('星期一'), 1);
      expect(tryParseDayOfWeek('礼拜天'), 7);
      expect(tryParseDayOfWeek('周二'), 2);
      expect(tryParseDayOfWeek('　星期日　'), 7);
      expect(tryParseDayOfWeek('３'), 3); // 全角
      expect(tryParseDayOfWeek('Thu'), 4);
      expect(tryParseDayOfWeek('Friday'), 5);
      expect(tryParseDayOfWeek('节次'), isNull);
      expect(tryParseDayOfWeek(''), isNull);
    });
  });

  group('parseDayOfWeek', () {
    test('解析成功返回 1-7', () {
      expect(parseDayOfWeek('星期三'), 3);
      expect(parseDayOfWeek('5'), 5);
    });

    test('非法输入抛 FormatException', () {
      expect(() => parseDayOfWeek('不知道'), throwsFormatException);
    });
  });
}
