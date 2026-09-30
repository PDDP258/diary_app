/// 图片识别导入源（PRD 决策 D4，wayfinder T10）
///
/// 流程：拍照/选图 → 压缩 → 云函数中转（腾讯云表格识别 V3）→
///       网格还原 + 表头定位 + 单元格语义 → 预览确认页。
///
/// 云函数源码与部署步骤见 `cloud/ocr-proxy/README.md`。
/// 密钥不进 APK：App 只持有一个「云函数 URL + 应用密钥」。
library;

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'course_import_source.dart';
import 'ocr/ocr_client.dart';
import 'ocr/ocr_pipeline.dart';

class OcrImportSource extends CourseImportSource {
  OcrImportSource({
    required this.imageSource,
    this.totalWeeks = 20,
    OcrClient? client,
  }) : _client = client;

  /// 拍照 or 从相册选
  final ImageSource imageSource;

  /// 学期总周数：格子里没写周次时按它兜底
  final int totalWeeks;

  final OcrClient? _client;

  /// 便于测试注入自定义选图逻辑；默认走 image_picker
  static Future<Uint8List?> Function(ImageSource source)? pickImageOverride;

  OcrClient get client => _client ?? HttpOcrClient();

  @override
  String get name =>
      imageSource == ImageSource.camera ? '拍照识别' : '相册识别';

  @override
  Future<ImportDraft?> collect() async {
    final bytes = await _pick();
    if (bytes == null) return null; // 用户取消

    final result = await client.recognize(bytes);
    return OcrImportPipeline.buildDraft(
      result,
      totalWeeks: totalWeeks,
      sourceName: name,
    );
  }

  Future<Uint8List?> _pick() async {
    final override = pickImageOverride;
    if (override != null) return override(imageSource);

    final picked = await ImagePicker().pickImage(
      source: imageSource,
      // 原生侧先降一次采样，省内存与耗时；后续还有一次精压
      maxWidth: 3000,
      maxHeight: 3000,
      imageQuality: 95,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }
}
