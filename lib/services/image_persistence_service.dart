import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 图片持久化服务 - 将外部图片复制到应用私有目录，防止相册移动后丢失
class ImagePersistenceService {
  static Future<String> persistImage(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw Exception('源图片不存在: $sourcePath');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${docsDir.path}/persisted_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final ext = sourcePath.split('.').lastOrNull ?? 'jpg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${imagesDir.path}/img_${timestamp}_${_randomString(6)}.$ext';

    await file.copy(destPath);
    return destPath;
  }

  static String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(chars[DateTime.now().microsecond % chars.length]);
    }
    return sb.toString();
  }
}
