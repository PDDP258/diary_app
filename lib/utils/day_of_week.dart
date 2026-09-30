/// 星期解析（课表导入边界共用：模板 / ICS / OCR 管线）
library;

/// 星期解析：1-7 / 周一~周日 / 星期一 / 礼拜天 / Mon / Monday / 全角数字 等。
/// 无法识别返回 null。
int? tryParseDayOfWeek(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // 全角数字与全角空格归一化
  s = _normalizeFullWidth(s);

  // 去掉常见包裹字符，如「周一」「(周一)」「星期1」
  s = s.replaceAll(RegExp(r'[\(（\[【\)）\]】\s]'), '');

  final num = _parseIntLoose(s);
  if (num != null && num >= 1 && num <= 7) return num;

  s = s.toLowerCase()
      .replaceAll('星期', '')
      .replaceAll('礼拜', '')
      .replaceAll('周', '');
  if (s.isEmpty) return null;

  const cn = ['一', '二', '三', '四', '五', '六', '日'];
  final idx = cn.indexOf(s);
  if (idx >= 0) return idx + 1;
  if (s == '天') return 7;

  const en = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  for (var i = 0; i < en.length; i++) {
    if (s.startsWith(en[i])) return i + 1;
  }
  return null;
}

/// 同 [tryParseDayOfWeek]，但必须给出结果
int parseDayOfWeek(String raw) {
  final n = tryParseDayOfWeek(raw);
  if (n == null) throw FormatException('星期无效: $raw');
  return n;
}

/// 全角数字/字母/空格 → 半角
String _normalizeFullWidth(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x3000) {
      buf.write(' ');
    } else if (r >= 0xFF01 && r <= 0xFF5E) {
      buf.writeCharCode(r - 0xFEE0);
    } else {
      buf.writeCharCode(r);
    }
  }
  return buf.toString();
}

/// 容忍 "3.0" 这类被 toString 过的整数
int? _parseIntLoose(String s) {
  final cleaned = s.replaceAll('第', '').replaceAll('节', '').trim();
  final direct = int.tryParse(cleaned);
  if (direct != null) return direct;
  final d = double.tryParse(cleaned);
  if (d != null && d == d.roundToDouble()) return d.toInt();
  return null;
}
