import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

/// 字体下载服务
/// 自动下载开源中文字体以支持PDF导出
class FontDownloadService {
  static const String _fontVersionKey = 'downloaded_font_version';
  
  /// 开源中文字体配置
  /// 使用思源宋体（Source Han Serif / Noto Serif CJK）
  /// 字体已打包到APK，路径：assets/fonts/
  static const Map<String, FontConfig> _fonts = {
    'NotoSerifCJKsc-Regular': FontConfig(
      name: 'NotoSerifCJKsc-Regular.otf',
      url: '', // 已打包到APK，无需下载
      size: 24 * 1024 * 1024, // 约24MB
      version: '2.004',
    ),
    'NotoSerifCJKsc-Bold': FontConfig(
      name: 'NotoSerifCJKsc-Bold.otf',
      url: '', // 已打包到APK，无需下载
      size: 25 * 1024 * 1024,
      version: '2.004',
    ),
  };

  /// 备用字体源（CDN镜像）- 按可靠性排序
  /// 针对中国大陆网络环境优化
  static const List<String> _mirrorUrls = [
    // === 国内CDN（最可靠）===
    'https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://fastly.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://gcore.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/',
    
    // === 国内大学镜像 ===
    // 清华大学
    'https://mirrors.tuna.tsinghua.edu.cn/github-release/notofonts/noto-cjk/Sans2.004/',
    // 中科大
    'https://mirrors.ustc.edu.cn/github-release/notofonts/noto-cjk/Sans2.004/',
    // 阿里云
    'https://mirrors.aliyun.com/github-release/notofonts/noto-cjk/Sans2.004/',
    
    // === 国内代理服务 ===
    'https://ghproxy.com/https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://mirror.ghproxy.com/https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://hub.gitmirror.com/https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://raw.gitmirror.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/',
    'https://gh.api.99988866.xyz/https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/',
    
    // === 海外CDN（备用）===
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
  /// 优先使用国内源，添加智能重试
  static Future<bool> _downloadFontWithRetry(String fontName, FontConfig config) async {
    // 构建所有URL列表（主URL + 镜像）
    final allUrls = [config.url, ..._mirrorUrls.map((m) => '$m${config.name}')];
    
    // 记录失败的URL，避免重复尝试
    final failedUrls = <String>[];
    
    // 第一轮：快速尝试（短超时）
    for (final url in allUrls) {
      if (failedUrls.contains(url)) continue;
      
      // 国内CDN使用较短超时
      final isDomestic = url.contains('jsdelivr') || 
                         url.contains('tuna.tsinghua') || 
                         url.contains('ustc.edu') ||
                         url.contains('aliyun');
      final timeout = isDomestic ? 15 : 8;
      
      if (await _downloadFont(url, config.name, timeoutSeconds: timeout)) {
        return true;
      }
      failedUrls.add(url);
    }
    
    // 第二轮：长超时重试（针对可能较慢的源）
    print('FontDownload: 第一轮快速尝试失败，开始长超时重试...');
    for (final url in allUrls) {
      if (await _downloadFont(url, config.name, timeoutSeconds: 45)) {
        return true;
      }
    }

    return false;
  }

  /// 下载单个字体
  /// [timeoutSeconds] 超时时间（秒），根据网络环境调整
  static Future<bool> _downloadFont(String url, String fileName, {int timeoutSeconds = 30}) async {
    try {
      // 只打印域名部分，避免日志过长
      final uri = Uri.parse(url);
      final host = uri.host;
      print('FontDownload: 尝试从 $host 下载...');
      
      // 创建自定义HttpClient
      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      httpClient.connectionTimeout = Duration(seconds: timeoutSeconds ~/ 2); // 连接超时
      
      final client = IOClient(httpClient);
      
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers.addAll({
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0',
          'Accept': '*/*, application/octet-stream, application/font-otf',
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
        });
        
        final streamedResponse = await client.send(request).timeout(
          Duration(seconds: timeoutSeconds),
          onTimeout: () {
            print('FontDownload: $host 超时(${timeoutSeconds}s)');
            throw TimeoutException('下载超时');
          },
        );
        
        if (streamedResponse.statusCode == 200) {
          final bytes = await streamedResponse.stream.toBytes();
          
          // 验证下载内容
          if (bytes.length < 10000) {
            print('FontDownload: 内容太小，跳过');
            return false;
          }
          
          // 验证文件头
          if (!_isValidFontHeader(bytes)) {
            print('FontDownload: 文件头无效，跳过');
            return false;
          }
          
          final fontFile = await _getFontFile(fileName);
          await fontFile.writeAsBytes(bytes);
          
          // 验证文件大小
          final fileSize = await fontFile.length();
          final sizeMb = (fileSize / 1024 / 1024).toStringAsFixed(2);
          print('FontDownload: ✓ 下载成功 (${sizeMb}MB)');
          return true;
          
        } else if (streamedResponse.statusCode == 302 || streamedResponse.statusCode == 301) {
          // 处理重定向
          final location = streamedResponse.headers['location'];
          if (location != null && !location.startsWith('http')) {
            // 相对路径，构建完整URL
            final resolvedUrl = uri.resolve(location).toString();
            return await _downloadFont(resolvedUrl, fileName, timeoutSeconds: timeoutSeconds);
          } else if (location != null) {
            return await _downloadFont(location, fileName, timeoutSeconds: timeoutSeconds);
          }
        } else {
          print('FontDownload: HTTP ${streamedResponse.statusCode}');
        }
      } finally {
        client.close();
      }
    } on TimeoutException {
      // 超时已在上方处理
    } on SocketException catch (e) {
      // 网络错误，静默处理
    } catch (e) {
      // 其他错误，静默处理
    }
    return false;
  }

  /// 验证字体文件头
  static bool _isValidFontHeader(List<int> bytes) {
    if (bytes.length < 4) return false;
    
    // OTF字体以 "OTTO" 开头
    final otfHeader = [0x4F, 0x54, 0x54, 0x4F]; // "OTTO"
    // TTF字体以 \x00\x01\x00\x00 开头
    final ttfHeader1 = [0x00, 0x01, 0x00, 0x00];
    // TTF字体以 "true" 开头
    final ttfHeader2 = [0x74, 0x72, 0x75, 0x65]; // "true"
    
    final header = bytes.sublist(0, 4);
    
    return _listEquals(header, otfHeader) || 
           _listEquals(header, ttfHeader1) || 
           _listEquals(header, ttfHeader2);
  }

  /// 比较两个列表是否相等
  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 获取字体数据（用于PDF）
  /// 优先级：1.assets字体(打包) 2.已下载字体(缓存) 3.自动下载
  /// 方案2（打包字体）：字体已打包进APK，直接从assets加载
  static Future<ByteData?> getFontData(String fontName) async {
    try {
      final config = _fonts[fontName];
      if (config == null) return null;

      // === 方案2: 优先从assets加载（字体已打包进APK）===
      try {
        final assetData = await rootBundle.load('assets/fonts/${config.name}');
        if (assetData.lengthInBytes > 1000000) { // 验证大小（字体应大于1MB）
          print('FontDownload: 使用打包字体: ${config.name} (${(assetData.lengthInBytes/1024/1024).toStringAsFixed(2)}MB)');
          // 同时缓存到本地，加快下次加载
          final fontFile = await _getFontFile(config.name);
          if (!await fontFile.exists()) {
            await fontFile.writeAsBytes(assetData.buffer.asUint8List());
          }
          return assetData;
        } else {
          print('FontDownload: 打包字体文件太小(${assetData.lengthInBytes} bytes)，可能损坏');
        }
      } catch (e) {
        // assets中没有字体，继续尝试其他方式
        print('FontDownload: 打包字体未找到: ${config.name} - $e');
      }

      // 2. 尝试加载已下载的字体（缓存）
      final fontFile = await _getFontFile(config.name);
      if (await fontFile.exists() && await fontFile.length() > 1000000) {
        print('FontDownload: 使用缓存字体: ${config.name}');
        final bytes = await fontFile.readAsBytes();
        return ByteData.sublistView(Uint8List.fromList(bytes));
      }

      // 3. 尝试自动下载字体（备选方案）
      print('FontDownload: 尝试自动下载字体: ${config.name}');
      final downloaded = await _downloadFontWithRetry(fontName, config);
      if (downloaded) {
        final bytes = await fontFile.readAsBytes();
        return ByteData.sublistView(Uint8List.fromList(bytes));
      }

      return null;
    } catch (e) {
      print('FontDownload: 读取字体失败: $e');
      return null;
    }
  }

  /// 从assets预加载字体（应用启动时调用）
  static Future<void> preloadFontsFromAssets() async {
    for (final entry in _fonts.entries) {
      final config = entry.value;
      final fontFile = await _getFontFile(config.name);
      
      // 如果已下载则跳过
      if (await fontFile.exists() && await fontFile.length() > 10000) {
        continue;
      }

      // 尝试从assets复制
      try {
        final assetData = await rootBundle.load('assets/fonts/${config.name}');
        if (assetData.lengthInBytes > 10000) {
          await fontFile.writeAsBytes(assetData.buffer.asUint8List());
          print('FontDownload: 从assets复制字体: ${config.name}');
        }
      } catch (e) {
        // assets中没有，忽略
      }
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
