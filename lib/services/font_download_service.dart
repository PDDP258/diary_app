import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 字体下载服务
/// 自动下载开源中文字体以支持PDF导出
class FontDownloadService {
  static const String _fontVersionKey = 'downloaded_font_version';
  
  /// 开源中文字体配置
  /// 使用思源黑体（Source Han Sans / Noto Sans CJK）
  static const Map<String, FontConfig> _fonts = {
    'NotoSansSC-Regular': FontConfig(
      name: 'NotoSansSC-Regular.otf',
      // 使用国内CDN加速 - 多个备选源
      url: 'https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Regular.otf',
      size: 8 * 1024 * 1024, // 约8MB
      version: '2.004',
    ),
    'NotoSansSC-Bold': FontConfig(
      name: 'NotoSansSC-Bold.otf',
      url: 'https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Bold.otf',
      size: 8 * 1024 * 1024,
      version: '2.004',
    ),
  };

  /// 备用字体源（CDN镜像）- 按可靠性排序
  static const List<String> _mirrorUrls = [
    // 国内CDN优先
    'https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://fastly.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://gcore.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/',
    // 代理服务
    'https://ghproxy.com/https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://mirror.ghproxy.com/https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/',
    // 直接GitHub（可能受限）
    'https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/',
  ];

  /// 检查字体是否已下载
  static Future<bool> isFontDownloaded(String fontName) async {
    try {
      final fontFile = await _getFontFile(fontName);
      return await fontFile.exists() && await fontFile.length() > 1000;
    } catch (e) {
      return false;
    }
  }

  /// 获取字体文件
  static Future<File> _getFontFile(String fontName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fontDir = Directory('${appDir.path}/fonts');
    if (!await fontDir.exists()) {
      await fontDir.create(recursive: true);
    }
    return File('${fontDir.path}/$fontName');
  }

  /// 下载所有字体
  /// 返回是否成功下载至少一个字体
  static Future<bool> downloadAllFonts({Function(double)? onProgress}) async {
    bool anySuccess = false;
    int total = _fonts.length;
    int completed = 0;

    for (final entry in _fonts.entries) {
      final fontName = entry.key;
      final config = entry.value;

      // 检查是否已下载
      if (await isFontDownloaded(config.name)) {
        print('FontDownload: $fontName 已存在，跳过');
        completed++;
        onProgress?.call(completed / total);
        anySuccess = true;
        continue;
      }

      // 尝试下载
      final success = await _downloadFontWithRetry(fontName, config);
      if (success) {
        anySuccess = true;
        print('FontDownload: $fontName 下载成功');
      } else {
        print('FontDownload: $fontName 下载失败');
      }

      completed++;
      onProgress?.call(completed / total);
    }

    return anySuccess;
  }

  /// 带重试的字体下载
  static Future<bool> _downloadFontWithRetry(String fontName, FontConfig config) async {
    // 先尝试主URL
    if (await _downloadFont(config.url, config.name)) {
      return true;
    }

    // 尝试镜像URL
    for (final mirror in _mirrorUrls) {
      final mirrorUrl = '$mirror${config.name}';
      if (await _downloadFont(mirrorUrl, config.name)) {
        return true;
      }
    }

    return false;
  }

  /// 下载单个字体
  static Future<bool> _downloadFont(String url, String fileName) async {
    try {
      print('FontDownload: 尝试下载 $url');
      
      // 创建HttpClient并设置代理（如果需要）
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers.addAll({
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive',
        });
        
        final streamedResponse = await client.send(request).timeout(const Duration(seconds: 60));
        
        if (streamedResponse.statusCode == 200) {
          final bytes = await streamedResponse.stream.toBytes();
          final fontFile = await _getFontFile(fileName);
          await fontFile.writeAsBytes(bytes);
          
          // 验证文件大小
          final fileSize = await fontFile.length();
          if (fileSize > 10000) { // 至少10KB
            print('FontDownload: 下载成功，大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
            return true;
          } else {
            print('FontDownload: 文件太小，删除重试');
            await fontFile.delete();
            return false;
          }
        } else {
          print('FontDownload: HTTP ${streamedResponse.statusCode}');
        }
      } finally {
        client.close();
      }
    } on TimeoutException {
      print('FontDownload: 下载超时');
    } catch (e) {
      print('FontDownload: 下载失败: $e');
    }
    return false;
  }

  /// 获取字体数据（用于PDF）
  static Future<ByteData?> getFontData(String fontName) async {
    try {
      final config = _fonts[fontName];
      if (config == null) return null;

      final fontFile = await _getFontFile(config.name);
      if (!await fontFile.exists()) {
        return null;
      }

      final bytes = await fontFile.readAsBytes();
      return ByteData.sublistView(bytes);
    } catch (e) {
      print('FontDownload: 读取字体失败: $e');
      return null;
    }
  }

  /// 清理字体缓存
  static Future<void> clearFonts() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fontDir = Directory('${appDir.path}/fonts');
      if (await fontDir.exists()) {
        await fontDir.delete(recursive: true);
      }
    } catch (e) {
      print('FontDownload: 清理字体失败: $e');
    }
  }

  /// 获取字体下载状态
  static Future<Map<String, bool>> getFontStatus() async {
    final status = <String, bool>{};
    for (final entry in _fonts.entries) {
      status[entry.key] = await isFontDownloaded(entry.value.name);
    }
    return status;
  }
}

/// 字体配置
class FontConfig {
  final String name;
  final String url;
  final int size;
  final String version;

  const FontConfig({
    required this.name,
    required this.url,
    required this.size,
    required this.version,
  });
}
