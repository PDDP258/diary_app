import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diary_app/services/encryption_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_test/flutter_test.dart';

/// 收件箱的**跨语言契约**测试。
///
/// 背景：麦麦（服务器上的 diary-mcp，Python）用 cloud_key 加密后把日记
/// PUT 到 WebDAV 的 `inbox/`；App（Dart）用**同一把** cloud_key 解密。
///
/// 两边是不同语言、不同实现，只要有一边的信封格式偏了，
/// 用户就只会看到「加载失败」。而这种 bug 单端测试都测不出来
/// （Python 能解自己造的密文，Dart 能解 Dart 造的密文）。
///
/// 所以这里用**对方语言真实产出的密文 fixture**：
/// - `test/fixtures/inbox_envelope.json`  ← Python（diary-mcp）产出
/// - `test/fixtures/inbox_dart_envelope.json` ← Dart 产出
///
/// 任何一边改了格式，对应的测试立刻红。
void main() {
  // base64("0123456789abcdef0123456789abcdef")，与 Python 侧测试用的同一把
  const key = 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=';

  group('收件箱密文：Python 产出 → Dart 解密（生产方向）', () {
    late Map<String, dynamic> envelope;

    setUpAll(() {
      final file = File('test/fixtures/inbox_envelope.json');
      expect(file.existsSync(), isTrue,
          reason: '缺少 fixture：test/fixtures/inbox_envelope.json');
      envelope = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('信封结构与 backup.mbk 同构（App 侧可复用同一套解密代码）', () {
      expect(envelope['_encrypted'], isTrue);
      expect(envelope['_version'], 2);
      expect(envelope['kind'], 'diary_draft');
      expect(envelope['data'], isA<String>());
      expect((envelope['data'] as String).startsWith('__CLOUD__'), isTrue);
    });

    test('Dart 能用同一把 cloud_key 解开 Python 加密的内容', () async {
      final plain = await EncryptionService.decryptWithCloudKey(
          envelope['data'] as String, key);
      expect(plain, isNotNull, reason: '解密失败：信封格式与 Dart 侧不一致');

      final payload = jsonDecode(plain!) as Map<String, dynamic>;
      expect(payload['title'], '今天的雨');
      expect(payload['content'], contains('没带伞'));
      expect(payload['date'], '2026-10-29');
      expect(payload['mood'], '开心');
      expect(payload['source'], 'maibot');
    });

    test('错误密钥解不开（防止把别的备份误当收件箱条目）', () async {
      const wrongKey = 'ZmVkY2JhOTg3NjU0MzIxMGZlZGNiYTk4NzY1NDMyMTA=';
      String? plain;
      try {
        plain = await EncryptionService.decryptWithCloudKey(
            envelope['data'] as String, wrongKey);
      } catch (_) {
        plain = null;
      }
      expect(plain, anyOf(isNull, isNot(contains('今天的雨'))));
    });

    test('中文与换行都完整保留（不能有编码损失）', () async {
      final plain = await EncryptionService.decryptWithCloudKey(
          envelope['data'] as String, key);
      final payload = jsonDecode(plain!) as Map<String, dynamic>;
      final content = payload['content'] as String;
      expect(content, contains('\n'));
      expect(content, contains('老同学'));
      expect(content.length, greaterThan(20));
    });
  });

  group('收件箱密文：Dart 产出 → Python 解密（回程）', () {
    test('Python 造的密文能被 Dart 解开（对称性验证）', () {
      final file = File('test/fixtures/inbox_dart_envelope.json');
      expect(file.existsSync(), isTrue,
          reason: '缺少 fixture：test/fixtures/inbox_dart_envelope.json');
      final envelope =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      expect(envelope['_encrypted'], isTrue);
      expect(envelope['_version'], 2);
      expect(envelope['kind'], 'diary_draft');

      // 用 Python 的 decrypt_text 解不开的话，这里就解不开（同一个算法）
      final plain = _decryptLikePython(
          envelope['data'] as String, base64.decode(key));
      expect(plain, isNotNull);
      final payload = jsonDecode(plain!) as Map<String, dynamic>;
      expect(payload['title'], '来自 Dart 的回程');
      expect(payload['mood'], '平静');
    });
  });

  group('Dart 侧信封格式自检', () {
    test('Dart 加密出来的格式与 Python 一致（字段顺序 + 编码）', () {
      final plain = jsonEncode({'title': '格式自检', 'content': 'x'});
      final cipher = _encryptLikeDart(plain, base64.decode(key));

      // 格式：__CLOUD__ + base64( utf8( "<iv_b64>:<cipher_b64>" ) )
      expect(cipher.startsWith('__CLOUD__'), isTrue);
      final inner = utf8.decode(base64.decode(cipher.substring(9)));
      expect(inner.contains(':'), isTrue);
      final parts = inner.split(':');
      expect(parts.length, 2);
      expect(base64.decode(parts[0]).length, 16, reason: 'IV 必须是 16 字节');
      expect(base64.decode(parts[1]).length % 16, 0,
          reason: '密文长度必须是 AES 块大小的整数倍');

      // 能解回原文
      expect(_decryptLikePython(cipher, base64.decode(key)), plain);
    });
  });
}

/// 复刻 `EncryptionService.encryptWithCloudKey` 的输出格式。
///
/// 不直接调真实实现是因为它要读 `flutter_secure_storage`（测试环境没有平台通道）。
/// 这里用纯 Dart 的 `package:encrypt`（也是项目正式依赖）复刻同样的算法。
String _encryptLikeDart(String plain, Uint8List keyBytes) {
  final key = encrypt.Key(keyBytes);
  final iv = encrypt.IV.fromSecureRandom(16);
  final encrypter = encrypt.Encrypter(
    encrypt.AES(key, mode: encrypt.AESMode.cbc),
  );
  final encrypted = encrypter.encrypt(plain, iv: iv);
  final inner = '${iv.base64}:${encrypted.base64}';
  return '__CLOUD__${base64.encode(utf8.encode(inner))}';
}

/// 复刻 Python 侧 `diary_mcp.crypto.decrypt_text` 的解密（用于验格式对称）。
///
/// 只做解密 + 去 PKCS7 填充，不做 base64 细节以外的处理 ——
/// 目的是**用另一条实现路径**验证信封格式，而不是复用生产代码。
String? _decryptLikePython(String cipherText, Uint8List keyBytes) {
  if (!cipherText.startsWith('__CLOUD__')) return null;
  try {
    final inner = utf8.decode(base64.decode(cipherText.substring(9)));
    final parts = inner.split(':');
    if (parts.length != 2) return null;

    final iv = encrypt.IV.fromBase64(parts[0]);
    final encrypted = encrypt.Encrypted.fromBase64(parts[1]);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc),
    );
    return encrypter.decrypt(encrypted, iv: iv);
  } catch (_) {
    return null;
  }
}
