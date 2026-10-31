import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条对话消息（本地保存，不依赖任何远端记忆）
class MaibotMessage {
  final String role; // 'user' | 'bot'
  final String text;
  final DateTime time;
  final int durationMs;

  const MaibotMessage({
    required this.role,
    required this.text,
    required this.time,
    this.durationMs = 0,
  });

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'time': time.toIso8601String(),
        'duration_ms': durationMs,
      };

  factory MaibotMessage.fromJson(Map<String, dynamic> json) => MaibotMessage(
        role: (json['role'] as String?) ?? 'bot',
        text: (json['text'] as String?) ?? '',
        time: DateTime.tryParse((json['time'] as String?) ?? '') ?? DateTime.now(),
        durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      );
}

/// 一次回复的结果
class MaibotReply {
  final bool ok;
  final String text;
  final String error;
  final int durationMs;

  const MaibotReply({
    required this.ok,
    required this.text,
    this.error = '',
    this.durationMs = 0,
  });

  factory MaibotReply.failure(String error, {int durationMs = 0}) =>
      MaibotReply(ok: false, text: '', error: error, durationMs: durationMs);
}

/// 与「麦麦对话桥」通信。
///
/// 桥跑在麦麦同机，只暴露 `/health` 与 `/chat` 两个动作；
/// App 这边只持有桥自己的 Bearer token，拿不到麦麦 WebUI 的管理权限。
class MaibotService {
  /// 默认地址：nginx 上 `/ai/` 反代到桥的 8021
  static const String defaultBaseUrl = 'https://203.195.219.170:8080/ai';

  static const String _prefBaseUrl = 'maibot_bridge_url';
  static const String _prefEnabled = 'maibot_enabled';
  static const String _prefHistory = 'maibot_chat_history';
  static const String _secureToken = 'maibot_app_token';

  /// 桥侧单轮最长等 75 秒，这里留余量
  static const Duration requestTimeout = Duration(seconds: 150);

  /// 本地最多保留多少条历史
  static const int historyLimit = 200;

  static final FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ---------------------------------------------------------------- 配置 --

  Future<String> get baseUrl async {
    final prefs = await SharedPreferences.getInstance();
    final value = (prefs.getString(_prefBaseUrl) ?? '').trim();
    return value.isEmpty ? defaultBaseUrl : value;
  }

  Future<void> setBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    var normalized = value.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    await prefs.setString(_prefBaseUrl, normalized);
  }

  Future<String> get token async {
    try {
      return (await _secure.read(key: _secureToken))?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> setToken(String value) async {
    await _secure.write(key: _secureToken, value: value.trim());
  }

  Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, value);
  }

  Future<bool> isConfigured() async {
    if ((await token).isEmpty) return false;
    if ((await baseUrl).isEmpty) return false;
    return true;
  }

  // ---------------------------------------------------------------- 网络 --

  HttpClient _newClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    // 自建服务用的是自签证书，只对这条自有通道放行
    ..badCertificateCallback = (cert, host, port) => true;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final base = await baseUrl;
    final appToken = await token;
    final client = _newClient();
    try {
      final uri = Uri.parse('$base$path');
      final request = await client.openUrl(method, uri).timeout(
            const Duration(seconds: 20),
          );
      request.headers.set('Authorization', 'Bearer $appToken');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(requestTimeout);
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401) {
        throw const _MaibotException('token 无效，请在设置里重新填写');
      }
      if (raw.isEmpty) {
        return {'ok': response.statusCode == 200};
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        if (response.statusCode >= 400) {
          final detail = decoded['detail']?.toString() ?? 'HTTP ${response.statusCode}';
          throw _MaibotException(detail);
        }
        return decoded;
      }
      return {'ok': response.statusCode == 200, 'data': decoded};
    } on SocketException {
      throw const _MaibotException('连不上麦麦，检查网络或地址');
    } on HandshakeException {
      throw const _MaibotException('证书握手失败');
    } finally {
      client.close(force: true);
    }
  }

  /// 连通性 + 桥是否已连上麦麦
  Future<({bool reachable, bool connected})> health() async {
    try {
      final data = await _request('GET', '/health');
      return (reachable: true, connected: data['connected'] == true);
    } catch (_) {
      return (reachable: false, connected: false);
    }
  }

  /// 发一句话，等麦麦回
  Future<MaibotReply> send(String text) async {
    final started = DateTime.now();
    try {
      final data = await _request('POST', '/chat', body: {'text': text});
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final replyText = (data['text'] as String? ?? '').trim();
      if (data['ok'] == true && replyText.isNotEmpty) {
        return MaibotReply(
          ok: true,
          text: replyText,
          durationMs: (data['duration_ms'] as num?)?.toInt() ?? elapsed,
        );
      }
      final error = (data['error'] as String? ?? '').trim();
      return MaibotReply.failure(
        error.isEmpty ? '麦麦这轮没说话，再试一次' : error,
        durationMs: elapsed,
      );
    } on _MaibotException catch (e) {
      return MaibotReply.failure(e.message);
    } on TimeoutException {
      return MaibotReply.failure('等太久了，麦麦可能正忙');
    } catch (e) {
      return MaibotReply.failure('出错了：$e');
    }
  }

  /// 提前建连，避免第一句话多等一两秒
  Future<void> warmup() async {
    try {
      await _request('POST', '/warmup');
    } catch (_) {
      // 预热失败不影响正式发送
    }
  }

  // ---------------------------------------------------------------- 历史 --

  Future<List<MaibotMessage>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefHistory);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(MaibotMessage.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> appendHistory(MaibotMessage message) async {
    final list = await loadHistory();
    list.add(message);
    final trimmed = list.length > historyLimit
        ? list.sublist(list.length - historyLimit)
        : list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefHistory,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefHistory);
  }
}

class _MaibotException implements Exception {
  final String message;
  const _MaibotException(this.message);

  @override
  String toString() => message;
}
