import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../services/image_cache_service.dart';

/// 平台相关的图片显示组件 - 带缩略图缓存优化
/// 
/// 使用说明：
/// - 列表/网格中的小图：使用默认参数，自动加载缩略图
/// - 日历单元格图片：使用 [CalendarImage] 组件，400x400 清晰度
/// - 详情页图片：使用 [DetailImage] 组件，800x800 高清
/// - 全屏大图预览：使用 [PreviewImage] 组件，1200x1200 超清或原图
/// - 必须使用原图：使用 [OriginalImage] 组件
/// 
/// 注意：所有组件都支持跨平台，Web 版本直接使用原图路径
class PlatformImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;

  const PlatformImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web 版本：路径就是图片 URL 或 base64
      return Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder();
        },
      );
    }

    // Native 版本 - 检查文件存在性后再加载
    return FutureBuilder<bool>(
      future: File(path).exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingWidget();
        }
        
        if (snapshot.data != true) {
          // 文件不存在，显示占位图
          return _buildPlaceholder();
        }
        
        // 文件存在，使用优化的缩略图缓存
        return OptimizedCachedImage(
          path: path,
          width: width,
          height: height,
          fit: fit,
          quality: CacheQuality.small,
        );
      },
    );
  }

  /// 构建加载占位图
  Widget _buildLoadingWidget() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// 构建图片不存在的占位图（贴纸风格）
  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              color: Colors.grey[400],
              size: (width ?? 50) * 0.4,
            ),
            if ((width ?? 0) > 60) ...[
              const SizedBox(height: 4),
              Text(
                '图片不可用',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 检查路径是否是本地文件路径
bool isLocalFile(String path) {
  if (kIsWeb) return false;
  return !path.startsWith('http') && !path.startsWith('data:');
}

/// 计算适合设备的图片缓存尺寸
/// 
/// 根据设备像素比计算，避免加载超过屏幕分辨率的图片
int calculateCacheSize(double? displaySize) {
  if (displaySize == null) return 300;
  
  // 获取设备像素比
  final pixelRatio = PlatformDispatcher.instance.views.first.devicePixelRatio;
  
  // 计算物理像素尺寸，最大限制为 2048（避免内存问题）
  final physicalSize = (displaySize * pixelRatio).round();
  return physicalSize.clamp(100, 2048);
}
