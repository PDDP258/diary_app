import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import 'font_download_service.dart';

/// PDF导出服务
class PdfExportService {
  static pw.Font? _chineseFont;
  static pw.Font? _chineseBoldFont;
  static bool _fontLoadFailed = false;
  static bool _isDownloading = false;

  /// 预加载字体（在导出前调用）
  static Future<bool> preloadFonts({Function(double)? onProgress}) async {
    if (_chineseFont != null && !_fontLoadFailed) return true;
    
    // 使用_loadChineseFont确保字体正确加载
    try {
      _chineseFont = await _loadChineseFont();
      
      // 同时尝试加载粗体（失败也没关系，会用普通字体代替）
      try {
        _chineseBoldFont = await _loadChineseBoldFont();
      } catch (e) {
        print('PDF: 粗体字体加载失败，将使用普通字体代替');
        _chineseBoldFont = _chineseFont;
      }
      
      return true;
    } catch (e) {
      print('PDF: 预加载字体失败: $e');
      return false;
    }
  }
  
  /// 测试字体加载（用于诊断）
  static Future<Map<String, dynamic>> diagnoseFontLoading() async {
    final results = <String, dynamic>{};
    
    // 1. 测试从assets加载
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSerifCJKsc-Regular.otf');
      results['assets_load'] = {
        'success': true,
        'size_mb': (fontData.lengthInBytes / 1024 / 1024).toStringAsFixed(2),
      };
    } catch (e) {
      results['assets_load'] = {'success': false, 'error': e.toString()};
    }
    
    // 2. 测试通过FontDownloadService加载
    try {
      final fontData = await FontDownloadService.getFontData('NotoSerifCJKsc-Regular');
      results['service_load'] = {
        'success': fontData != null,
        'size_mb': fontData != null ? (fontData.lengthInBytes / 1024 / 1024).toStringAsFixed(2) : null,
      };
    } catch (e) {
      results['service_load'] = {'success': false, 'error': e.toString()};
    }
    
    // 3. 测试系统字体
    try {
      final systemFont = await _loadSystemChineseFont();
      results['system_font'] = {'success': systemFont != null};
    } catch (e) {
      results['system_font'] = {'success': false, 'error': e.toString()};
    }
    
    return results;
  }

  /// 加载中文字体 - 确保中文正常显示
  /// 按优先级尝试：1.assets字体 2.已缓存字体 3.系统字体 4.尝试下载
  /// 如果所有方式都失败，抛出异常而不是使用默认字体（避免中文乱码）
  static Future<pw.Font> _loadChineseFont() async {
    // 如果已有字体且未标记失败，直接返回
    if (_chineseFont != null && !_fontLoadFailed) {
      print('PDF: 使用已缓存字体');
      return _chineseFont!;
    }
    
    // 重置状态，允许重试
    _fontLoadFailed = false;
    _chineseFont = null;

    // 1. 优先尝试加载assets中的字体（最可靠，无需网络）
    try {
      print('PDF: 尝试加载assets字体...');
      final fontData = await rootBundle.load('assets/fonts/NotoSerifCJKsc-Regular.otf');
      if (fontData.lengthInBytes > 1000000) { // 验证字体大小（应大于1MB）
        _chineseFont = pw.Font.ttf(fontData);
        print('PDF: ✓ 加载assets字体成功 (${(fontData.lengthInBytes/1024/1024).toStringAsFixed(2)}MB)');
        return _chineseFont!;
      } else {
        print('PDF: assets字体文件太小，可能损坏');
      }
    } catch (e) {
      print('PDF: assets字体加载失败: $e');
    }

    // 2. 尝试通过FontDownloadService加载（包含缓存和下载逻辑）
    try {
      print('PDF: 尝试通过FontDownloadService加载字体...');
      final fontData = await FontDownloadService.getFontData('NotoSerifCJKsc-Regular');
      if (fontData != null && fontData.lengthInBytes > 1000000) {
        _chineseFont = pw.Font.ttf(fontData);
        print('PDF: ✓ 加载字体成功 (${(fontData.lengthInBytes/1024/1024).toStringAsFixed(2)}MB)');
        return _chineseFont!;
      }
    } catch (e) {
      print('PDF: FontDownloadService加载失败: $e');
    }

    // 3. 尝试从系统加载中文字体（仅桌面端有效）
    try {
      print('PDF: 尝试加载系统字体...');
      _chineseFont = await _loadSystemChineseFont();
      if (_chineseFont != null) {
        print('PDF: ✓ 加载系统字体成功');
        return _chineseFont!;
      }
    } catch (e) {
      print('PDF: 系统字体加载失败: $e');
    }

    // 4. 所有方式都失败，标记失败并抛出异常
    _fontLoadFailed = true;
    final errorMsg = '中文字体加载失败，无法导出PDF。请确保字体文件已正确打包到应用。';
    print('PDF: ✗ $errorMsg');
    throw Exception(errorMsg);
  }

  /// 尝试加载系统中的中文字体
  static Future<pw.Font?> _loadSystemChineseFont() async {
    // 各平台常见中文字体路径
    final fontPaths = [
      // Windows
      'C:/Windows/Fonts/msyh.ttc', // 微软雅黑
      'C:/Windows/Fonts/simhei.ttf', // 黑体
      'C:/Windows/Fonts/simsun.ttc', // 宋体
      // macOS
      '/System/Library/Fonts/PingFang.ttc', // 苹方
      '/System/Library/Fonts/STHeiti Light.ttc', // 华文黑体
      '/Library/Fonts/Arial Unicode.ttf',
      // Linux
      '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', // 文泉驿
      '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ];

    for (final path in fontPaths) {
      try {
        final file = File(path);
        if (await file.exists() && await file.length() > 1000000) {
          final bytes = await file.readAsBytes();
          print('PDF: 找到系统字体: $path (${(bytes.length/1024/1024).toStringAsFixed(2)}MB)');
          // 将 Uint8List 转换为 ByteData
          return pw.Font.ttf(ByteData.sublistView(bytes));
        }
      } catch (e) {
        // 继续尝试下一个
      }
    }
    return null;
  }
  
  /// 加载粗体中文字体
  static Future<pw.Font> _loadChineseBoldFont() async {
    // 如果已有字体且未标记失败，直接返回
    if (_chineseBoldFont != null && !_fontLoadFailed) return _chineseBoldFont!;
    
    // 重置状态，允许重试
    _chineseBoldFont = null;

    // 1. 尝试加载assets中的粗体字体
    try {
      print('PDF: 尝试加载assets粗体字体...');
      final fontData = await rootBundle.load('assets/fonts/NotoSerifCJKsc-Bold.otf');
      if (fontData.lengthInBytes > 1000000) {
        // 将 ByteData 转换为 Uint8List
        _chineseBoldFont = pw.Font.ttf(fontData);
        print('PDF: ✓ 加载assets粗体字体成功 (${(fontData.lengthInBytes/1024/1024).toStringAsFixed(2)}MB)');
        return _chineseBoldFont!;
      }
    } catch (e) {
      print('PDF: assets粗体字体加载失败: $e');
    }

    // 2. 尝试通过FontDownloadService加载粗体字体
    try {
      print('PDF: 尝试通过FontDownloadService加载粗体字体...');
      final fontData = await FontDownloadService.getFontData('NotoSerifCJKsc-Bold');
      if (fontData != null && fontData.lengthInBytes > 1000000) {
        // 将 ByteData 转换为 Uint8List
        _chineseBoldFont = pw.Font.ttf(fontData);
        print('PDF: ✓ 加载粗体字体成功 (${(fontData.lengthInBytes/1024/1024).toStringAsFixed(2)}MB)');
        return _chineseBoldFont!;
      }
    } catch (e) {
      print('PDF: FontDownloadService粗体字体加载失败: $e');
    }

    // 3. 尝试系统粗体字体
    final boldFontPaths = [
      'C:/Windows/Fonts/msyhbd.ttc', // 微软雅黑粗体
      'C:/Windows/Fonts/simhei.ttf', // 黑体
      '/System/Library/Fonts/PingFang.ttc',
      '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
    ];

    for (final path in boldFontPaths) {
      try {
        final file = File(path);
        if (await file.exists() && await file.length() > 1000000) {
          final bytes = await file.readAsBytes();
          // 将 Uint8List 转换为 ByteData
          _chineseBoldFont = pw.Font.ttf(ByteData.sublistView(bytes));
          print('PDF: ✓ 加载系统粗体字体成功: $path');
          return _chineseBoldFont!;
        }
      } catch (e) {
        // 继续尝试
      }
    }

    // 4. 使用普通字体代替粗体（如果普通字体已加载）
    print('PDF: 使用普通字体代替粗体');
    _chineseBoldFont = await _loadChineseFont();
    return _chineseBoldFont!;
  }

  /// 获取支持中文的文本样式
  static Future<pw.TextStyle> _getChineseTextStyle({
    double fontSize = 12,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    PdfColor color = PdfColors.black,
    double lineSpacing = 1.2,
  }) async {
    final font = await _loadChineseFont();
    return pw.TextStyle(
      font: font,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      lineSpacing: lineSpacing,
    );
  }

  /// 导出日记为PDF - 确保中文正常显示
  /// [fileName] 自定义文件名（不含.pdf后缀），为空则使用默认命名
  static Future<void> exportDiaries({
    required List<Diary> diaries,
    required List<Mood> moods,
    required List<Tag> tags,
    String? fileName,
    Function(double)? onFontDownloadProgress,
  }) async {
    if (diaries.isEmpty) {
      throw Exception('没有日记可导出');
    }

    // 加载中文字体 - 必须成功才能导出PDF（否则中文会乱码）
    print('PDF: 开始加载中文字体...');
    bool fontLoaded = false;
    int retryCount = 0;
    const maxRetries = 3;
    
    while (!fontLoaded && retryCount < maxRetries) {
      try {
        // 使用_loadChineseFont确保字体正确加载
        final font = await _loadChineseFont();
        _chineseFont = font;
        fontLoaded = true;
        print('PDF: ✓ 字体加载成功');
      } catch (e) {
        retryCount++;
        print('PDF: 字体加载失败，第$retryCount次重试... ($e)');
        if (retryCount < maxRetries) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    
    // 如果字体加载失败，抛出异常阻止导出（避免生成乱码PDF）
    if (!fontLoaded || _chineseFont == null) {
      throw Exception('中文字体加载失败，无法导出PDF。请检查字体文件是否已正确打包到assets/fonts/目录。');
    }
    
    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy年MM月dd日');
    final fullFormat = DateFormat('yyyy年MM月dd日 HH:mm');
    final titleStyle = pw.TextStyle(
        font: _chineseFont!, fontSize: 36, fontWeight: pw.FontWeight.bold);
    final subtitleStyle = pw.TextStyle(font: _chineseFont!, fontSize: 16);
    final dateStyle =
        pw.TextStyle(font: _chineseFont!, fontSize: 12, color: PdfColors.grey600);
    final headerStyle = pw.TextStyle(
        font: _chineseFont!, fontSize: 18, fontWeight: pw.FontWeight.bold);
    final contentStyle =
        pw.TextStyle(font: _chineseFont!, fontSize: 12, lineSpacing: 4);
    final footerStyle =
        pw.TextStyle(font: _chineseFont!, fontSize: 10, color: PdfColors.grey500);
    final imageCaptionStyle =
        pw.TextStyle(font: _chineseFont!, fontSize: 10, color: PdfColors.grey500);

    // 添加封面
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                '小记日记',
                style: titleStyle,
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                '共 ${diaries.length} 篇日记',
                style: subtitleStyle,
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                '导出日期：${fullFormat.format(DateTime.now())}',
                style: dateStyle,
              ),
            ],
          ),
        ),
      ),
    );

    int pageNumber = 1;

    // 添加每一篇日记
    for (final diary in diaries) {
      final mood = moods.where((m) => m.id == diary.moodId).firstOrNull;

      // 处理图片
      final List<pw.Widget> imageWidgets = [];
      for (final imagePath in diary.imageList.take(4)) {
        try {
          final file = File(imagePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final image = pw.MemoryImage(bytes);
            imageWidgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                height: 150,
                width: double.infinity,
                child: pw.ClipRRect(
                  horizontalRadius: 8,
                  verticalRadius: 8,
                  child: pw.Image(image, fit: pw.BoxFit.cover),
                ),
              ),
            );
          } else {
            imageWidgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                height: 150,
                width: double.infinity,
                color: PdfColors.grey100,
                child: pw.Center(
                  child: pw.Text('[图片未找到]', style: imageCaptionStyle),
                ),
              ),
            );
          }
        } catch (e) {
          imageWidgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              height: 150,
              width: double.infinity,
              color: PdfColors.grey100,
              child: pw.Center(
                child: pw.Text('[图片加载失败]', style: imageCaptionStyle),
              ),
            ),
          );
        }
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 日期和天气
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    dateFormat.format(DateTime.parse(diary.date)),
                    style: headerStyle,
                  ),
                  if (mood != null)
                    pw.Text(
                      mood.emoji,
                      style: pw.TextStyle(font: _chineseFont!, fontSize: 20),
                    ),
                ],
              ),
              pw.SizedBox(height: 20),

              // 标题
              if (diary.title != null && diary.title!.isNotEmpty)
                pw.Text(
                  diary.title!,
                  style: pw.TextStyle(
                      font: _chineseFont!,
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold),
                ),
              pw.SizedBox(height: 10),

              // 内容
              pw.Text(
                diary.content ?? '',
                style: contentStyle,
              ),

              // 图片（如果有）
              if (imageWidgets.isNotEmpty) pw.SizedBox(height: 20),
              ...imageWidgets,

              pw.Spacer(),

              // 页脚
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  '- 第 ${++pageNumber} 页 -',
                  style: footerStyle,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 共享/打印PDF
    final String finalFileName = fileName?.isNotEmpty == true 
        ? '$fileName.pdf' 
        : '小记日记_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: finalFileName,
    );
  }

  /// 导出单篇日记为PDF
  /// [fileName] 自定义文件名（不含.pdf后缀），为空则使用默认命名
  static Future<void> exportSingleDiary(
    Diary diary,
    Mood? mood,
    List<Tag> tags, {
    String? fileName,
  }) async {
    final dateFormat = DateFormat('yyyy年MM月dd日 HH:mm');
    final pdf = pw.Document();

    // 预加载字体 - 使用改进的字体加载逻辑
    try {
      _chineseFont = await _loadChineseFont();
    } catch (e) {
      throw Exception('中文字体加载失败，无法导出PDF: $e');
    }
    
    final chineseFont = _chineseFont!;
    final dateStyle = pw.TextStyle(
        font: chineseFont,
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey600);
    final titleStyle = pw.TextStyle(
        font: chineseFont, fontSize: 24, fontWeight: pw.FontWeight.bold);
    final contentStyle =
        pw.TextStyle(font: chineseFont, fontSize: 14, lineSpacing: 6);
    final imageCaptionStyle =
        pw.TextStyle(font: chineseFont, fontSize: 10, color: PdfColors.grey500);

    // 处理图片
    final List<pw.Widget> imageWidgets = [];
    for (final imagePath in diary.imageList) {
      try {
        final file = File(imagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final image = pw.MemoryImage(bytes);
          imageWidgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              height: 200,
              width: double.infinity,
              child: pw.ClipRRect(
                horizontalRadius: 8,
                verticalRadius: 8,
                child: pw.Image(image, fit: pw.BoxFit.cover),
              ),
            ),
          );
        } else {
          imageWidgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              height: 200,
              width: double.infinity,
              color: PdfColors.grey100,
              child: pw.Center(
                child: pw.Text('[图片未找到]', style: imageCaptionStyle),
              ),
            ),
          );
        }
      } catch (e) {
        imageWidgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            height: 200,
            width: double.infinity,
            color: PdfColors.grey100,
            child: pw.Center(
              child: pw.Text('[图片加载失败]', style: imageCaptionStyle),
            ),
          ),
        );
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // 日期和天气
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  dateFormat.format(DateTime.parse(diary.date)),
                  style: dateStyle,
                ),
                if (mood != null)
                  pw.Text(
                    mood.emoji,
                    style: pw.TextStyle(font: chineseFont, fontSize: 24),
                  ),
              ],
            ),
            pw.SizedBox(height: 20),

            // 标题
            if (diary.title != null && diary.title!.isNotEmpty) ...[
              pw.Text(
                diary.title!,
                style: titleStyle,
              ),
              pw.SizedBox(height: 15),
            ],

            // 内容
            pw.Text(
              diary.content ?? '',
              style: contentStyle,
            ),

            // 图片
            if (imageWidgets.isNotEmpty) pw.SizedBox(height: 30),
            ...imageWidgets,
          ],
        ),
      ),
    );

    // 共享/打印
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'diary_${diary.id}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  /// 保存PDF到文件
  static Future<String?> savePdfToFile(
      List<Diary> diaries, List<Mood> moods, List<Tag> tags) async {
    if (diaries.isEmpty) {
      throw Exception('没有日记可导出');
    }

    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy年MM月dd日');
    final fullFormat = DateFormat('yyyy年MM月dd日 HH:mm');

    // 预加载字体
    pw.Font chineseFont;
    try {
      chineseFont = await _loadChineseFont();
    } catch (e) {
      throw Exception('中文字体加载失败，无法导出PDF: $e');
    }
    final titleStyle = pw.TextStyle(
        font: chineseFont, fontSize: 36, fontWeight: pw.FontWeight.bold);
    final subtitleStyle = pw.TextStyle(font: chineseFont, fontSize: 16);
    final dateStyle =
        pw.TextStyle(font: chineseFont, fontSize: 12, color: PdfColors.grey600);
    final headerStyle = pw.TextStyle(
        font: chineseFont, fontSize: 18, fontWeight: pw.FontWeight.bold);
    final contentStyle =
        pw.TextStyle(font: chineseFont, fontSize: 12, lineSpacing: 4);
    final footerStyle =
        pw.TextStyle(font: chineseFont, fontSize: 10, color: PdfColors.grey500);

    // 添加封面
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text('小记日记', style: titleStyle),
              pw.SizedBox(height: 20),
              pw.Text('共 ${diaries.length} 篇日记', style: subtitleStyle),
              pw.SizedBox(height: 10),
              pw.Text(
                '导出日期：${fullFormat.format(DateTime.now())}',
                style: dateStyle,
              ),
            ],
          ),
        ),
      ),
    );

    int pageNumber = 1;

    // 添加每一篇日记
    for (final diary in diaries) {
      final mood = moods.where((m) => m.id == diary.moodId).firstOrNull;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    dateFormat.format(DateTime.parse(diary.date)),
                    style: headerStyle,
                  ),
                  if (mood != null)
                    pw.Text(mood.emoji,
                        style: pw.TextStyle(font: chineseFont, fontSize: 20)),
                ],
              ),
              pw.SizedBox(height: 20),
              if (diary.title != null && diary.title!.isNotEmpty) ...[
                pw.Text(
                  diary.title!,
                  style: pw.TextStyle(
                      font: chineseFont,
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
              ],
              pw.Text(diary.content ?? '', style: contentStyle),
              pw.Spacer(),
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  '- 第 ${++pageNumber} 页 -',
                  style: footerStyle,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 保存到文件
    final directory = await getApplicationDocumentsDirectory();
    final fileName =
        'diary_export_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }
}
