/// OCR 服务客户端与配置
///
/// App 不持有腾讯云密钥——密钥在云函数里（见 `cloud/ocr-proxy/`）。
/// App 只需要知道「云函数 URL」和「应用密钥」这两个字符串，存在
/// SharedPreferences 里，由用户在课表页配置一次。
///
/// 之所以把服务地址做成运行时可配置而不是编译期常量：一是不同人自部署的
/// 地址不同，二是地址变了不用发版。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'ocr_models.dart';

/// 识别服务配置（持久化）
class OcrServiceConfig {
  static const _endpointKey = 'course_ocr_endpoint';
  static const _appKeyKey = 'course_ocr_app_key';

  static Future<String> endpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_endpointKey) ?? '').trim();
  }

  static Future<String> appKey() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_appKeyKey) ?? '').trim();
  }

  static Future<bool> isConfigured() async => (await endpoint()).isNotEmpty;

  /// 保存配置。空串表示清除该项。
  static Future<void> save({required String endpoint, String? appKey}) async {
    final prefs = await SharedPreferences.getInstance();
    if (endpoint.trim().isEmpty) {
      await prefs.remove(_endpointKey);
    } else {
      await prefs.setString(_endpointKey, endpoint.trim());
    }
    if (appKey == null) return;
    if (appKey.trim().isEmpty) {
      await prefs.remove(_appKeyKey);
    } else {
      await prefs.setString(_appKeyKey, appKey.trim());
    }
  }
}

/// 识别客户端接口（便于测试替换）
abstract class OcrClient {
  Future<OcrResult> recognize(Uint8List imageBytes);
}

/// HTTP 客户端：压缩图片 → POST 云函数 → 解析归一化结果
class HttpOcrClient implements OcrClient {
  HttpOcrClient({String? endpoint, String? appKey})
      : _endpointOverride = endpoint,
        _appKeyOverride = appKey;

  final String? _endpointOverride;
  final String? _appKeyOverride;

  /// 图片长边上限。腾讯云建议分辨率 600*800 以上、长宽比 < 3；
  /// 2000 是「够清晰」与「请求体不超云函数限制」的折中。
  static const maxImageSide = 2000;

  /// 压缩后允许的最大字节数（base64 膨胀 4/3，云函数请求体留足余量）
  static const maxImageBytes = 3 * 1024 * 1024;

  static const _timeout = Duration(seconds: 40);

  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async {
    final endpoint =
        _endpointOverride ?? await OcrServiceConfig.endpoint();
    if (endpoint.isEmpty) {
      throw const OcrException(
        '还没配置识别服务地址。点「识别服务设置」填入云函数 URL 后再试',
        code: 'NOT_CONFIGURED',
      );
    }
    final appKey = _appKeyOverride ?? await OcrServiceConfig.appKey();

    final prepared = prepareImage(imageBytes);
    final body = jsonEncode({'image': base64Encode(prepared)});

    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              if (appKey.isNotEmpty) 'X-App-Key': appKey,
            },
            body: body,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const OcrException('识别服务响应超时，请检查网络后重试', code: 'TIMEOUT');
    } on SocketException catch (e) {
      throw OcrException('连不上识别服务：${e.osError?.message ?? '网络不可用'}',
          code: 'NETWORK');
    } on http.ClientException catch (e) {
      throw OcrException('连不上识别服务：${e.message}', code: 'NETWORK');
    }

    final text = _decodeBody(resp);

    if (resp.statusCode == 401) {
      throw const OcrException('识别服务拒绝了请求：应用密钥不正确', code: 'BAD_APP_KEY');
    }
    if (resp.statusCode == 413) {
      throw const OcrException('图片太大，识别服务不收。换一张分辨率低些的截图', code: 'TOO_LARGE');
    }
    if (resp.statusCode >= 400) {
      throw OcrException(_extractError(text) ?? '识别服务返回 ${resp.statusCode}',
          code: 'HTTP_${resp.statusCode}');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const OcrException('识别服务返回了非预期内容，请检查云函数地址是否为完整 URL',
          code: 'BAD_RESPONSE');
    }
    if (decoded is! Map) {
      throw const OcrException('识别服务返回格式不对', code: 'BAD_RESPONSE');
    }
    return OcrResult.fromJson(Map<String, dynamic>.from(decoded));
  }

  /// 优先取响应里的 error 字段，比 HTTP 状态码更能说明问题
  String? _extractError(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return null;
  }

  String _decodeBody(http.Response resp) {
    try {
      return utf8.decode(resp.bodyBytes);
    } catch (_) {
      return resp.body;
    }
  }

  /// 压缩为 JPEG：长边限 [maxImageSide]，并保证不超过 [maxImageBytes]。
  /// 纯函数式（无 IO），便于单测。
  static Uint8List prepareImage(
    Uint8List input, {
    int maxSide = maxImageSide,
    int maxBytes = maxImageBytes,
  }) {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const OcrException('图片无法解码，请换一张图片', code: 'BAD_IMAGE');
    }

    var side = maxSide;
    var quality = 88;
    var last = <int>[];
    for (var attempt = 0; attempt < 5; attempt++) {
      final scaled = _resize(decoded, side);
      last = img.encodeJpg(scaled, quality: quality);
      if (last.length <= maxBytes) break;
      side = (side * 0.75).round();
      quality = math.max(55, quality - 10);
    }
    return Uint8List.fromList(last);
  }

  static img.Image _resize(img.Image src, int maxSide) {
    final longest = math.max(src.width, src.height);
    if (longest <= maxSide) return src;
    final scale = maxSide / longest;
    return img.copyResize(
      src,
      width: (src.width * scale).round().clamp(1, 1 << 20),
      height: (src.height * scale).round().clamp(1, 1 << 20),
      interpolation: img.Interpolation.average,
    );
  }
}
