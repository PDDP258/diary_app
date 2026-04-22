import 'dart:io';
import 'package:motion_photos/motion_photos.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// 实况图片服务
/// 支持检测和提取 Android Motion Photo（包括小米、三星、Pixel等）
class MotionPhotoService {
  static final MotionPhotoService _instance = MotionPhotoService._internal();
  factory MotionPhotoService() => _instance;
  MotionPhotoService._internal();

  /// 检测图片是否为实况图片
  Future<bool> isMotionPhoto(String imagePath) async {
    try {
      if (!await File(imagePath).exists()) return false;
      final motionPhotos = MotionPhotos(imagePath);
      return await motionPhotos.isMotionPhoto();
    } catch (e) {
      print('MotionPhoto: 检测失败: $e');
      return false;
    }
  }

  /// 提取实况图片中的视频
  /// 返回视频文件路径，如果不是实况图片或提取失败则返回 null
  Future<String?> extractVideo(String imagePath) async {
    try {
      if (!await File(imagePath).exists()) {
        print('MotionPhoto: 图片不存在: $imagePath');
        return null;
      }

      // 先检测是否为实况图片
      final motionPhotos = MotionPhotos(imagePath);
      final isMotion = await motionPhotos.isMotionPhoto();
      if (!isMotion) {
        print('MotionPhoto: 不是实况图片: $imagePath');
        return null;
      }

      // 获取应用缓存目录
      final cacheDir = await getTemporaryDirectory();
      final videoDir = Directory('${cacheDir.path}/motion_videos');
      if (!await videoDir.exists()) {
        await videoDir.create(recursive: true);
      }

      // 生成唯一视频文件名（避免同名文件冲突 + 路径复用问题）
      final imageFile = File(imagePath);
      final stat = await imageFile.stat();
      final imageName = path.basenameWithoutExtension(imagePath);
      final uniqueId = '${imageName}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
      final videoPath = '${videoDir.path}/${uniqueId}_video.mp4';

      // 检查是否已提取过
      final existingVideo = File(videoPath);
      if (await existingVideo.exists() && await existingVideo.length() > 0) {
        print('MotionPhoto: 使用已缓存的视频: $videoPath');
        return videoPath;
      }

      // 提取视频 - getMotionVideoFile 直接返回文件
      final videoFile = await motionPhotos.getMotionVideoFile();

      if (await videoFile.exists()) {
        // 复制到缓存目录
        await videoFile.copy(videoPath);
        print('MotionPhoto: 视频提取成功: $videoPath');
        return videoPath;
      }

      print('MotionPhoto: 视频提取失败');
      return null;
    } catch (e) {
      print('MotionPhoto: 提取视频失败: $e');
      return null;
    }
  }

  /// 清理过期的缓存视频
  Future<void> clearExpiredCache({Duration maxAge = const Duration(days: 7)}) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final videoDir = Directory('${cacheDir.path}/motion_videos');
      
      if (!await videoDir.exists()) return;

      final now = DateTime.now();
      final files = await videoDir.list().toList();
      
      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          final age = now.difference(stat.modified);
          if (age > maxAge) {
            await file.delete();
            print('MotionPhoto: 清理过期缓存: ${file.path}');
          }
        }
      }
    } catch (e) {
      print('MotionPhoto: 清理缓存失败: $e');
    }
  }

  /// 获取实况图片信息
  Future<MotionPhotoInfo?> getInfo(String imagePath) async {
    try {
      if (!await File(imagePath).exists()) return null;
      
      final motionPhotos = MotionPhotos(imagePath);
      final isMotion = await motionPhotos.isMotionPhoto();
      if (!isMotion) return null;

      final videoPath = await extractVideo(imagePath);
      if (videoPath == null) return null;

      final videoFile = File(videoPath);
      final videoStat = await videoFile.stat();

      return MotionPhotoInfo(
        imagePath: imagePath,
        videoPath: videoPath,
        videoSize: videoStat.size,
        videoModified: videoStat.modified,
      );
    } catch (e) {
      print('MotionPhoto: 获取信息失败: $e');
      return null;
    }
  }
}

/// 实况图片信息
class MotionPhotoInfo {
  final String imagePath;
  final String videoPath;
  final int videoSize;
  final DateTime videoModified;

  MotionPhotoInfo({
    required this.imagePath,
    required this.videoPath,
    required this.videoSize,
    required this.videoModified,
  });

  /// 格式化视频大小
  String get formattedVideoSize {
    if (videoSize < 1024) return '$videoSize B';
    if (videoSize < 1024 * 1024) return '${(videoSize / 1024).toStringAsFixed(1)} KB';
    return '${(videoSize / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
