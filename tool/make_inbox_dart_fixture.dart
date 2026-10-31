import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart' as encrypt;

/// 生成「Dart 侧产出的收件箱密文」fixture，供 Python 侧测试反向验证。
///
/// 产物：`test/fixtures/inbox_dart_envelope.json`
/// 用法：`dart tool/make_inbox_dart_fixture.dart`
void main() {
  const key = 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=';

  final payload = {
    'title': '来自 Dart 的回程',
    'content': '这条密文由 Dart 侧生成，Python 必须能解开。\n带换行和中文。',
    'date': '2026-10-29',
    'mood': '平静',
    'created_at': '2026-10-29T12:00:00',
    'source': 'maibot',
  };

  final plain = jsonEncode(payload);
  final encrypter = encrypt.Encrypter(
    encrypt.AES(
      encrypt.Key.fromBase64(key),
      mode: encrypt.AESMode.cbc,
    ),
  );
  final iv = encrypt.IV.fromSecureRandom(16);
  final encrypted = encrypter.encrypt(plain, iv: iv);
  final inner = '${iv.base64}:${encrypted.base64}';

  final envelope = {
    '_encrypted': true,
    '_version': 2,
    'kind': 'diary_draft',
    'data': '__CLOUD__${base64.encode(utf8.encode(inner))}',
  };

  final out = File('test/fixtures/inbox_dart_envelope.json');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(envelope));
  stdout.writeln('已写入 ${out.path}');
}
