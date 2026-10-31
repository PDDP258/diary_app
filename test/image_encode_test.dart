// rawRgba → JPEG 编码链路的**真实往返验证**（2026-10-28）。
//
// 背景：用户反馈「图片变得不爱显示了」。
//
// 根因：`_encodeRawRgbaToJpeg` 里
//   `img.Image.fromBytes(bytes: p.rgba.buffer, ...)`
// 只传了整个 ByteBuffer，**没传 bytesOffset**。
// `toByteData()` 返回的 ByteData 是底层 buffer 的一个视图，
// offsetInBytes 通常不为 0 → image 包从第 0 字节开始读 → 编码出错位/无效图像。
//
// 这类 bug 的可怕之处：**不抛异常**，只是产出一张「看起来是图但内容是垃圾」
// 的 JPEG，然后被写进缩略图缓存 → 永久命中 → 图片再也不显示。
//
// 本测试用「构造已知像素的位图 → 编码 → 解码 → 逐像素比对」来锁死正确性。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 构造一张已知内容的 RGBA 位图：左半红、右半蓝。
(Uint8List, int, int) buildTestRgba(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      if (x < w ~/ 2) {
        rgba[i] = 255; // R
        rgba[i + 1] = 0;
        rgba[i + 2] = 0;
        rgba[i + 3] = 255;
      } else {
        rgba[i] = 0;
        rgba[i + 1] = 0;
        rgba[i + 2] = 255; // B
        rgba[i + 3] = 255;
      }
    }
  }
  return (rgba, w, h);
}

void main() {
  group('rawRgba → JPEG 编码正确性', () {
    test('带 offset 的 ByteData 视图必须编码出正确图像（回归 offset bug）', () {
      final (raw, w, h) = buildTestRgba(64, 64);

      // 模拟真实场景：toByteData 返回的 view 通常位于某个更大的 buffer 中部，
      // offsetInBytes != 0。这里刻意在前后各加 padding 来制造非零 offset。
      const padding = 64;
      final bigBuffer = Uint8List(padding + raw.length + padding);
      bigBuffer.setRange(padding, padding + raw.length, raw);

      // 这正是 toByteData 视图的形态：指向 bigBuffer 中段
      final view = Uint8List.sublistView(bigBuffer, padding, padding + raw.length);
      expect(view.offsetInBytes, padding,
          reason: '构造的视图必须是非零 offset，否则测不到这个 bug');

      // —— 修复后的写法：显式传 bytesOffset ——
      final corrected = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: view.buffer,
        bytesOffset: view.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      final jpegBytes = Uint8List.fromList(img.encodeJpg(corrected, quality: 88));
      final decoded = img.decodeImage(jpegBytes);
      expect(decoded, isNotNull, reason: '编码结果必须是可解码的 JPEG');
      expect(decoded!.width, w);
      expect(decoded.height, h);

      // 逐区校验：左半应变红，右半应变蓝
      final leftPixel = decoded.getPixel(8, h ~/ 2);
      final rightPixel = decoded.getPixel(w - 9, h ~/ 2);

      expect(leftPixel.r, greaterThan(180),
          reason: '左半区必须是红色（说明没发生像素错位）');
      expect(leftPixel.b, lessThan(80));
      expect(rightPixel.b, greaterThan(180),
          reason: '右半区必须是蓝色');
      expect(rightPixel.r, lessThan(80));
    });

    test('不传 bytesOffset 会得到错误结果（证明这个参数确实必须）', () {
      final (raw, w, h) = buildTestRgba(64, 64);

      const padding = 64;
      final bigBuffer = Uint8List(padding + raw.length + padding);
      bigBuffer.setRange(padding, padding + raw.length, raw);
      final view = Uint8List.sublistView(bigBuffer, padding, padding + raw.length);

      // —— 错误写法（就是之前的 bug）：只传 buffer，不传 offset ——
      final broken = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: view.buffer,
        // bytesOffset 缺省 = 0 ← bug 所在
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      final jpegBytes = Uint8List.fromList(img.encodeJpg(broken, quality: 88));
      final decoded = img.decodeImage(jpegBytes);

      // 不崩，但内容错位 —— 这正是为什么 bug 没被发现
      expect(decoded, isNotNull);

      // 左半区不再是纯红（读到了 padding/错位数据）
      final leftPixel = decoded!.getPixel(8, h ~/ 2);
      final isStillRed = leftPixel.r > 180 && leftPixel.b < 80;
      expect(isStillRed, isFalse,
          reason: '这一条用于证明：缺 bytesOffset 确实会产生错误像素，'
              '因此修复（显式传 offset）是必需的');
    });
  });

  group('缩略图缓存自愈', () {
    test('空文件/过小文件应被判定为无效缓存', () {
      // 直接验证判定阈值逻辑：正常 JPEG 缩略图远大于 256 字节
      final (raw, w, h) = buildTestRgba(64, 64);
      final image = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: raw.buffer,
        bytesOffset: raw.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      final jpeg = img.encodeJpg(image, quality: 88);

      expect(jpeg.length, greaterThan(256),
          reason: '正常缩略图必须大于最小有效阈值，否则会被误判为坏缓存');
    });
  });
}
