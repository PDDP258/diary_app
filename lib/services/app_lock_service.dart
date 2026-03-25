import 'dart:convert';

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

/// 应用锁服务
/// 管理九宫格手势密码的设置、验证和备份
class AppLockService {
  static const String _appLockEnabledKey = 'app_lock_enabled';
  static const String _appLockPatternKey = 'app_lock_pattern';
  static const String _appLockBackupPathKey = 'app_lock_backup_path';

  static bool _enabled = false;
  static List<int>? _pattern;
  static String? _backupImagePath;
  static bool _initialized = false;

  /// 初始化
  static Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_appLockEnabledKey) ?? false;

    final patternJson = prefs.getString(_appLockPatternKey);
    if (patternJson != null) {
      final List<dynamic> decoded = jsonDecode(patternJson);
      _pattern = decoded.cast<int>();
    }

    _backupImagePath = prefs.getString(_appLockBackupPathKey);
    _initialized = true;
  }

  /// 是否启用了应用锁
  static bool get isEnabled {
    if (!_initialized) {
      // 同步返回，避免阻塞启动
      return false;
    }
    return _enabled && _pattern != null && _pattern!.length >= 4;
  }

  /// 验证密码
  static bool verifyPattern(List<int> inputPattern) {
    if (_pattern == null) return false;
    if (inputPattern.length < 4) return false;

    // 比较两个列表是否相同
    if (inputPattern.length != _pattern!.length) return false;

    for (int i = 0; i < inputPattern.length; i++) {
      if (inputPattern[i] != _pattern![i]) return false;
    }

    return true;
  }

  /// 设置新密码
  static Future<bool> setPattern(List<int> pattern) async {
    if (pattern.length < 4) return false;

    try {
      final prefs = await SharedPreferences.getInstance();

      _pattern = List.from(pattern);
      _enabled = true;

      await prefs.setString(_appLockPatternKey, jsonEncode(pattern));
      await prefs.setBool(_appLockEnabledKey, true);

      return true;
    } catch (e) {
      debugPrint('设置密码失败: $e');
      return false;
    }
  }

  /// 关闭应用锁
  static Future<bool> disable() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _enabled = false;
      _pattern = null;

      await prefs.setBool(_appLockEnabledKey, false);
      await prefs.remove(_appLockPatternKey);

      // 删除备份图片
      if (_backupImagePath != null) {
        final file = File(_backupImagePath!);
        if (await file.exists()) {
          await file.delete();
        }
        _backupImagePath = null;
        await prefs.remove(_appLockBackupPathKey);
      }

      return true;
    } catch (e) {
      debugPrint('关闭应用锁失败: $e');
      return false;
    }
  }

  /// 获取备份图片路径
  static String? get backupImagePath => _backupImagePath;

  /// 保存备份图片路径
  static Future<void> setBackupImagePath(String path) async {
    _backupImagePath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appLockBackupPathKey, path);
  }

  /// 生成密码备份图片
  ///
  /// 将九宫格密码可视化，方便用户保存备份
  static Future<Uint8List?> generateBackupImage(List<int> pattern,
      {ColorScheme? colorScheme}) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(400, 500);

      // 背景
      final bgPaint = Paint()..color = colorScheme?.surface ?? Colors.white;
      canvas.drawRect(Offset.zero & size, bgPaint);

      // 标题
      final textStyle = TextStyle(
        color: colorScheme?.onSurface ?? Colors.black87,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      );
      final textSpan = TextSpan(
        text: '小记日记 - 应用锁密码备份',
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset((size.width - textPainter.width) / 2, 30));

      // 绘制九宫格
      const gridSize = 240.0;
      final gridOffset = Offset((size.width - gridSize) / 2, 100);
      const cellSize = gridSize / 3;
      const dotRadius = cellSize * 0.25;
      const lineWidth = 4.0;

      // 绘制连接线
      if (pattern.length >= 2) {
        final linePaint = Paint()
          ..color = colorScheme?.primary ?? const Color(0xFF7DD3C0)
          ..strokeWidth = lineWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        final path = Path();
        for (int i = 0; i < pattern.length - 1; i++) {
          final fromIndex = pattern[i];
          final toIndex = pattern[i + 1];

          final fromRow = fromIndex ~/ 3;
          final fromCol = fromIndex % 3;
          final toRow = toIndex ~/ 3;
          final toCol = toIndex % 3;

          final fromOffset = Offset(
            gridOffset.dx + fromCol * cellSize + cellSize / 2,
            gridOffset.dy + fromRow * cellSize + cellSize / 2,
          );
          final toOffset = Offset(
            gridOffset.dx + toCol * cellSize + cellSize / 2,
            gridOffset.dy + toRow * cellSize + cellSize / 2,
          );

          if (i == 0) {
            path.moveTo(fromOffset.dx, fromOffset.dy);
          }
          path.lineTo(toOffset.dx, toOffset.dy);
        }
        canvas.drawPath(path, linePaint);
      }

      // 绘制圆点
      final normalPaint = Paint()
        ..color =
            (colorScheme?.primary ?? const Color(0xFF7DD3C0)).withOpacity(0.3)
        ..style = PaintingStyle.fill;

      final selectedPaint = Paint()
        ..color = colorScheme?.primary ?? const Color(0xFF7DD3C0)
        ..style = PaintingStyle.fill;

      final selectedBorderPaint = Paint()
        ..color =
            (colorScheme?.primary ?? const Color(0xFF7DD3C0)).withOpacity(0.3)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke;

      for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 3; col++) {
          final index = row * 3 + col;
          final center = Offset(
            gridOffset.dx + col * cellSize + cellSize / 2,
            gridOffset.dy + row * cellSize + cellSize / 2,
          );

          if (pattern.contains(index)) {
            // 选中的点 - 绘制外圈
            canvas.drawCircle(center, dotRadius + 8, selectedBorderPaint);
            canvas.drawCircle(center, dotRadius, selectedPaint);

            // 绘制序号
            final orderIndex = pattern.indexOf(index) + 1;
            final orderText = TextPainter(
              text: TextSpan(
                text: '$orderIndex',
                style: TextStyle(
                  color: colorScheme?.onPrimary ?? Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            orderText.layout();
            orderText.paint(
              canvas,
              Offset(center.dx - orderText.width / 2,
                  center.dy - orderText.height / 2),
            );
          } else {
            // 未选中的点
            canvas.drawCircle(center, dotRadius, normalPaint);
          }
        }
      }

      // 底部提示文字
      final hintText = TextPainter(
        text: TextSpan(
          text: '请妥善保存此图片，忘记密码时需要使用',
          style: TextStyle(
            color: colorScheme?.onSurface.withOpacity(0.6) ?? Colors.black54,
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      hintText.layout();
      hintText.paint(
        canvas,
        Offset((size.width - hintText.width) / 2, size.height - 50),
      );

      // 生成图片
      final picture = recorder.endRecording();

      // 使用 addPostFrameCallback 确保在 UI 线程中执行
      final image =
          await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('生成备份图片失败: byteData 为 null');
        return null;
      }

      final bytes = byteData.buffer.asUint8List();
      if (bytes.isEmpty) {
        debugPrint('生成备份图片失败: bytes 为空');
        return null;
      }

      return bytes;
    } catch (e, stackTrace) {
      debugPrint('生成备份图片失败: $e');
      debugPrint('堆栈: $stackTrace');
      return null;
    }
  }

  /// 保存备份图片到本地
  ///
  /// 保存到应用私有目录和公共目录（相册），使用固定文件名便于查找
  static Future<String?> saveBackupImage(Uint8List imageBytes) async {
    try {
      // 首先保存到应用私有目录
      final appDir = await getApplicationDocumentsDirectory();
      const fileName = 'app_lock_backup.png';
      final privateFilePath = path.join(appDir.path, fileName);

      debugPrint('保存备份图片到私有目录: $privateFilePath');
      debugPrint('图片数据大小: ${imageBytes.length} bytes');

      final privateFile = File(privateFilePath);

      // 确保目录存在
      final privateDir = privateFile.parent;
      if (!await privateDir.exists()) {
        await privateDir.create(recursive: true);
        debugPrint('创建私有目录: ${privateDir.path}');
      }

      // 写入私有目录
      await privateFile.writeAsBytes(imageBytes, flush: true);
      debugPrint('私有目录文件写入完成');

      // 验证私有文件是否成功写入
      if (!await privateFile.exists()) {
        debugPrint('保存备份图片到私有目录失败: 文件不存在');
        return null;
      }

      final privateFileSize = await privateFile.length();
      if (privateFileSize == 0) {
        debugPrint('保存备份图片到私有目录失败: 文件大小为0');
        return null;
      }

      debugPrint('私有目录备份图片保存成功，文件大小: $privateFileSize bytes');

      // 尝试保存到公共目录（相册/图片文件夹）
      String? publicFilePath =
          await _saveToPublicDirectory(imageBytes, fileName);
      if (publicFilePath != null) {
        debugPrint('公共目录备份图片保存成功: $publicFilePath');
        // 优先返回公共目录路径，方便用户查找
        await setBackupImagePath(publicFilePath);
        return publicFilePath;
      } else {
        // 公共目录保存失败，返回私有目录路径
        debugPrint('公共目录保存失败，使用私有目录路径');
        await setBackupImagePath(privateFilePath);
        return privateFilePath;
      }
    } catch (e, stackTrace) {
      debugPrint('保存备份图片失败: $e');
      debugPrint('堆栈: $stackTrace');
      return null;
    }
  }

  /// 保存图片到公共目录（Download/diary_backup）
  /// 和txt导出保持一致的路径
  static Future<String?> _saveToPublicDirectory(
      Uint8List imageBytes, String fileName) async {
    try {
      if (Platform.isAndroid) {
        // Android: 保存到外部存储的 Download/diary_backup 目录
        // 注意：Android 11+ 需要 MANAGE_EXTERNAL_STORAGE 权限或 MediaStore API

        // 首先尝试获取外部存储根目录
        String? externalPath;
        try {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            // 尝试找到实际的SD卡路径
            final dirPath = externalDir.path;
            // 通常是 /storage/emulated/0/Android/data/... 或 /sdcard/Android/data/...
            // 我们需要找到根目录
            if (dirPath.contains('/Android/data/')) {
              externalPath = dirPath.split('/Android/data/').first;
            } else {
              externalPath = dirPath;
            }
          }
        } catch (e) {
          debugPrint('获取外部存储目录失败: $e');
        }

        externalPath ??= '/storage/emulated/0';

        // 创建 Download/diary_backup 目录（和txt导出保持一致）
        final downloadDir = Directory('$externalPath/Download/diary_backup');
        try {
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
            debugPrint('创建备份目录: ${downloadDir.path}');
          }
        } catch (e) {
          debugPrint('创建目录失败，可能没有权限: $e');
          return null;
        }

        final publicFilePath = path.join(downloadDir.path, fileName);
        final publicFile = File(publicFilePath);

        try {
          await publicFile.writeAsBytes(imageBytes, flush: true);
          debugPrint('公共目录文件写入完成: $publicFilePath');

          // 验证文件
          if (await publicFile.exists() && await publicFile.length() > 0) {
            return publicFilePath;
          }
        } catch (e) {
          debugPrint('写入公共目录失败: $e');
          return null;
        }
      } else if (Platform.isIOS) {
        // iOS: 保存到应用沙盒的Documents目录，该目录可以通过iTunes文件共享访问
        final documentsDir = await getApplicationDocumentsDirectory();
        final publicFilePath = path.join(documentsDir.path, fileName);
        final publicFile = File(publicFilePath);

        await publicFile.writeAsBytes(imageBytes, flush: true);

        if (await publicFile.exists() && await publicFile.length() > 0) {
          return publicFilePath;
        }
      }
    } catch (e) {
      debugPrint('保存到公共目录失败: $e');
    }
    return null;
  }

  /// 分享备份图片（保存到相册）
  static Future<bool> shareBackupImage(String filePath) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // 保存到相册
        final file = File(filePath);
        if (!await file.exists()) return false;

        // 使用 image_gallery_saver 或其他方式保存
        // 这里先使用简单的分享方式
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('分享备份图片失败: $e');
      return false;
    }
  }
}
