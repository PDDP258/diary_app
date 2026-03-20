import 'dart:io';
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
    if (_chineseFont != null) return true;
    
    // 尝试加载已下载的字体
    final regularFont = await FontDownloadService.getFontData('NotoSansSC-Regular');
    if (regularFont != null) {
      _chineseFont = pw.Font.ttf(regularFont);
      print('PDF: 使用已下载的字体');
      
      final boldFont = await FontDownloadService.getFontData('NotoSansSC-Bold');
      if (boldFont != null) {
        _chineseBoldFont = pw.Font.ttf(boldFont);
      }
      return true;
    }
    
    // 如果没有下载，尝试自动下载
    if (!_isDownloading) {
      _isDownloading = true;
      final success = await FontDownloadService.downloadAllFonts(onProgress: onProgress);
      _isDownloading = false;
      
      if (!success) {
        print('PDF: 字体下载失败');
        return false;
      }
      
      // 再次尝试加载
      final downloadedFont = await FontDownloadService.getFontData('NotoSansSC-Regular');
      if (downloadedFont != null) {
        _chineseFont = pw.Font.ttf(downloadedFont);
        print('PDF: 自动下载并使用字体');
        
        final downloadedBold = await FontDownloadService.getFontData('NotoSansSC-Bold');
        if (downloadedBold != null) {
          _chineseBoldFont = pw.Font.ttf(downloadedBold);
        }
        return true;
      }
    }
    
    return false;
  }

  /// 加载中文字体 - 确保中文正常显示
  /// 按优先级尝试：1.assets字体 2.已缓存字体 3.系统字体 4.尝试下载 5.默认字体
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
      final fontData = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      _chineseFont = pw.Font.ttf(fontData);
      print('PDF: 加载assets字体成功');
      return _chineseFont!;
    } catch (e) {
      print('PDF: assets字体未找到，尝试其他来源...');
    }

    // 2. 尝试加载已下载的字体
    try {
      final fontData = await FontDownloadService.getFontData('NotoSansSC-Regular');
      if (fontData != null) {
        _chineseFont = pw.Font.ttf(fontData);
        print('PDF: 加载已下载字体成功');
        return _chineseFont!;
      }
    } catch (e) {
      print('PDF: 已下载字体加载失败: $e');
    }

    // 3. 尝试从系统加载中文字体（仅桌面端有效）
    try {
      _chineseFont = await _loadSystemChineseFont();
      if (_chineseFont != null) {
        print('PDF: 加载系统字体成功');
        return _chineseFont!;
      }
    } catch (e) {
      print('PDF: 系统字体加载失败: $e');
    }

    // 4. 尝试下载字体（带超时和错误处理）
    print('PDF: 尝试下载字体...');
    try {
      final success = await FontDownloadService.downloadAllFonts();
      if (success) {
        final fontData = await FontDownloadService.getFontData('NotoSansSC-Regular');
        if (fontData != null) {
          _chineseFont = pw.Font.ttf(fontData);
          print('PDF: 下载字体成功');
          return _chineseFont!;
        }
      }
    } catch (e) {
      print('PDF: 下载字体失败: $e');
    }

    // 5. 使用内置字体（不支持中文，会显示方框）
    print('PDF: 警告！使用默认字体，中文将显示为方框');
    _fontLoadFailed = true;
    _chineseFont = pw.Font.helvetica();
    return _chineseFont!;
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
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          print('PDF: 找到系统字体: $path');
          return pw.Font.ttf(bytes.buffer.asByteData());
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
      final fontData = await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
      _chineseBoldFont = pw.Font.ttf(fontData);
      return _chineseBoldFont!;
    } catch (e) {
      // 继续尝试自动下载的字体
    }

    // 2. 尝试加载自动下载的粗体字体
    try {
      final fontData = await FontDownloadService.getFontData('NotoSansSC-Bold');
      if (fontData != null) {
        _chineseBoldFont = pw.Font.ttf(fontData);
        print('PDF: 加载自动下载粗体字体成功');
        return _chineseBoldFont!;
      }
    } catch (e) {
      print('PDF: 自动下载粗体字体加载失败: $e');
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
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          _chineseBoldFont = pw.Font.ttf(bytes.buffer.asByteData());
          return _chineseBoldFont!;
        }
      } catch (e) {
        // 继续尝试
      }
    }

    // 4. 使用普通字体代替粗体
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

    // 加载中文字体 - 尝试加载但不强制要求成功
    print('PDF: 开始加载中文字体...');
    bool fontLoaded = false;
    int retryCount = 0;
    const maxRetries = 2;
    
    while (!fontLoaded && retryCount < maxRetries) {
      fontLoaded = await preloadFonts(onProgress: onFontDownloadProgress);
      if (!fontLoaded) {
        retryCount++;
        print('PDF: 字体加载失败，第$retryCount次重试...');
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    
    // 如果字体加载失败，使用默认字体（中文会显示为方框，但不影响导出）
    if (!fontLoaded || _chineseFont == null) {
      print('PDF: 警告 - 中文字体加载失败，将使用默认字体（中文可能显示为方框）');
      _chineseFont = pw.Font.helvetica();
      _fontLoadFailed = true;
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

    // 预加载字体
    final chineseFont = await _loadChineseFont();
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
    final chineseFont = await _loadChineseFont();
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
