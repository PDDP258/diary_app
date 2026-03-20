import 'package:flutter/material.dart' hide Badge;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/anniversary.dart';
import '../providers/theme_provider.dart';
import '../models/diary.dart';
import '../models/tag.dart';
import '../services/database_service.dart';
import '../providers/diary_provider.dart';

import '../services/image_cache_service.dart';
import '../services/motion_photo_service.dart';
import '../widgets/motion_photo_widget.dart';
import '../widgets/random_sticker_overlay.dart';
import 'write_diary_screen.dart';
import 'dart:io';

class DiaryDetailScreen extends StatefulWidget {
  final Diary diary;

  const DiaryDetailScreen({
    super.key,
    required this.diary,
  });

  @override
  State<DiaryDetailScreen> createState() => _DiaryDetailScreenState();
}

class _DiaryDetailScreenState extends State<DiaryDetailScreen> {
  List<Tag> _tags = [];
  bool _isLoading = true;
  List<Anniversary> _anniversaries = [];
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.diary.isFavorite;
    _loadTags();
    _loadAnniversaries();
  }

  Future<void> _loadAnniversaries() async {
    final anniversaries = await DatabaseService.getAllAnniversaries();
    if (mounted) {
      setState(() {
        _anniversaries = anniversaries;
      });
    }
  }

  Future<void> _loadTags() async {
    final provider = context.read<DiaryProvider>();
    final tags = await provider.getDiaryTags(widget.diary.id!);
    if (mounted) {
      setState(() {
        _tags = tags;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final provider = context.read<DiaryProvider>();
    final newFavoriteState = await provider.toggleFavorite(widget.diary.id!);
    if (mounted) {
      setState(() {
        _isFavorite = newFavoriteState;
      });
    }
  }

  Future<void> _editDiary() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriteDiaryScreen(diary: widget.diary),
      ),
    );
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd').parse(widget.diary.date);
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        title: const Text('日记详情'),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : null,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editDiary,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // 主要内容
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 日期和心情卡片
                _buildHeaderCard(date),
                const SizedBox(height: 20),

                // 标签
                if (_tags.isNotEmpty) _buildTags(),
                if (_tags.isNotEmpty) const SizedBox(height: 20),

                // 标题
                if (widget.diary.title != null &&
                    widget.diary.title!.isNotEmpty)
                  _buildTitle(),
                if (widget.diary.title != null &&
                    widget.diary.title!.isNotEmpty)
                  const SizedBox(height: 20),

                // 内容
                if (widget.diary.content != null &&
                    widget.diary.content!.isNotEmpty)
                  _buildContent(),
                if (widget.diary.content != null &&
                    widget.diary.content!.isNotEmpty)
                  const SizedBox(height: 20),

                // 图片
                if (widget.diary.images != null &&
                    widget.diary.images!.isNotEmpty)
                  _buildImages(),

                const SizedBox(height: 32),

                // 底部信息
                _buildFooter(),

                const SizedBox(height: 40),
              ],
            ),
          ),
          // 随机贴图装饰
          const RandomStickerOverlay(
              targetPage: 'diary', appearProbability: 0.5),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(DateTime date) {
    final scheme = AppTheme.schemeOf(context);
    final weekDay = DateFormat('EEEE', 'zh_CN').format(date);
    final isWeekend = weekDay.contains('六') || weekDay.contains('日');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.cardColor,
            scheme.cardColor,
            scheme.lightColor.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(
          color: scheme.lightColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 日期圆形徽章
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isWeekend
                    ? [
                        scheme.primaryColor.withValues(alpha: 0.9),
                        scheme.darkColor
                      ]
                    : [scheme.primaryColor, scheme.darkColor],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: scheme.primaryColor.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('dd').format(date),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM', 'zh_CN').format(date).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 年份
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.lightColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    DateFormat('yyyy', 'zh_CN').format(date),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primaryColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 完整日期
                Text(
                  DateFormat('M月d日', 'zh_CN').format(date),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: scheme.textDarkColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                // 星期和心情
                Row(
                  children: [
                    Text(
                      weekDay,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: scheme.textMediumColor,
                      ),
                    ),
                    if (widget.diary.moodName != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.diary.moodEmoji ?? '',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.diary.moodName!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTags() {
    final scheme = AppTheme.schemeOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.softShadow,
        border: Border.all(
          color: scheme.lightColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _tags.map((tag) {
          final tagColor =
              Color(int.parse(tag.color.replaceFirst('#', '0xFF')));
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: tagColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: tagColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tagColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tagColor.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTitle() {
    final scheme = AppTheme.schemeOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryColor.withValues(alpha: 0.08),
            scheme.lightColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(
          color: scheme.primaryColor.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4, right: 12),
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: scheme.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              widget.diary.title!,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: scheme.textDarkColor,
                height: 1.4,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final scheme = AppTheme.schemeOf(context);
    final contentParts = _parseContent(widget.diary.content!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(
          color: scheme.lightColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 正文部分
          if (contentParts.mainContent.isNotEmpty)
            Text(
              contentParts.mainContent,
              style: TextStyle(
                fontSize: 17,
                color: scheme.textDarkColor,
                height: 1.9,
                letterSpacing: 0.3,
              ),
            ),
          // 纪念文字部分
          if (contentParts.anniversaryText != null) ...[
            if (contentParts.mainContent.isNotEmpty) const SizedBox(height: 24),
            _buildAnniversaryText(contentParts.anniversaryText!, scheme),
          ],
        ],
      ),
    );
  }

  /// 解析日记内容，分离正文和纪念文字
  ({String mainContent, String? anniversaryText}) _parseContent(
      String content) {
    // 纪念文字的标识：包含特定前缀的连续行
    final lines = content.split('\n');
    int anniversaryStartIndex = -1;

    // 从后往前找，找到第一个纪念文字标记
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      // 检查是否是纪念文字的开始（包含特定emoji）
      if (line.startsWith('🎉') ||
          line.startsWith('✨') ||
          line.startsWith('⏰') ||
          line.startsWith('📅') ||
          line.startsWith('🎊')) {
        // 向前查找这个纪念文字的完整内容（可能包含多行）
        anniversaryStartIndex = i;
        // 如果前一行是空行，也包含进来作为分隔
        while (anniversaryStartIndex > 0 &&
            lines[anniversaryStartIndex - 1].trim().isEmpty) {
          anniversaryStartIndex--;
        }
        break;
      }
    }

    if (anniversaryStartIndex == -1) {
      // 没有找到纪念文字
      return (mainContent: content, anniversaryText: null);
    }

    // 分离正文和纪念文字
    final mainLines = lines.sublist(0, anniversaryStartIndex);
    final anniversaryLines = lines.sublist(anniversaryStartIndex);

    // 清理正文末尾的空行
    while (mainLines.isNotEmpty && mainLines.last.trim().isEmpty) {
      mainLines.removeLast();
    }

    return (
      mainContent: mainLines.join('\n'),
      anniversaryText: anniversaryLines.join('\n').trim(),
    );
  }

  /// 构建纪念文字显示
  Widget _buildAnniversaryText(String text, ThemeScheme scheme) {
    final isSpecial = _isSpecialAnniversaryDay(text);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isSpecial
              ? [
                  scheme.primaryColor.withValues(alpha: 0.12),
                  scheme.lightColor.withValues(alpha: 0.06),
                ]
              : [
                  scheme.lightColor.withValues(alpha: 0.15),
                  scheme.backgroundColor.withValues(alpha: 0.5),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSpecial
              ? scheme.primaryColor.withValues(alpha: 0.3)
              : scheme.lightColor.withValues(alpha: 0.4),
          width: isSpecial ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: text.split('\n').map((line) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSpecial ? FontWeight.w600 : FontWeight.w500,
                color: isSpecial ? scheme.primaryColor : scheme.textMediumColor,
                height: 1.5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 判断是否是特殊日子的纪念文字
  bool _isSpecialAnniversaryDay(String text) {
    return text.contains('🎉') || text.contains('🎊') || text.contains('⏰');
  }

  Widget _buildImages() {
    final images = widget.diary.imageList;
    final scheme = AppTheme.schemeOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(
          color: scheme.lightColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.photo_library_outlined,
                  color: scheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '照片回忆',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${images.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: scheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 图片网格
          _buildImageGrid(images),
        ],
      ),
    );
  }

  Widget _buildImageGrid(List<String> images) {
    final crossAxisCount = images.length == 1 ? 1 : 2;
    final childAspectRatio = images.length == 1 ? 16 / 10 : 1.0;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return _buildImageThumbnail(images[index], index);
      },
    );
  }

  Widget _buildImageThumbnail(String path, int index) {
    final scheme = AppTheme.schemeOf(context);

    return GestureDetector(
      onTap: () => _showImageViewer(path, index),
      child: Hero(
        tag: 'image_$path',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DetailImage(
                  path: path,
                  fit: BoxFit.cover,
                ),
                // 悬停效果遮罩
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.3),
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
                // 查看图标
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.zoom_in,
                      color: scheme.primaryColor,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showImageViewer(String path, int index) {
    final images = widget.diary.imageList;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          images: images,
          initialIndex: index,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final scheme = AppTheme.schemeOf(context);
    final createdAt = widget.diary.createdAt != null
        ? DateFormat('yyyy-MM-dd HH:mm')
            .format(DateTime.parse(widget.diary.createdAt!))
        : '-';
    final updatedAt = widget.diary.updatedAt != null &&
            widget.diary.updatedAt != widget.diary.createdAt
        ? DateFormat('yyyy-MM-dd HH:mm')
            .format(DateTime.parse(widget.diary.updatedAt!))
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.lightColor.withValues(alpha: 0.15),
            scheme.backgroundColor.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        border: Border.all(
          color: scheme.lightColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 14,
                color: scheme.textLightColor,
              ),
              const SizedBox(width: 6),
              Text(
                '创建于 $createdAt',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.textMediumColor,
                ),
              ),
            ],
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 14,
                  color: scheme.textLightColor,
                ),
                const SizedBox(width: 6),
                Text(
                  '更新于 $updatedAt',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: scheme.textMediumColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 图片查看器页面 - 支持滑动浏览和缩放
class ImageViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  final MotionPhotoService _motionPhotoService = MotionPhotoService();
  final Map<int, bool> _isMotionPhotoMap = {};
  final Map<int, String?> _videoPathMap = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _checkMotionPhotos();
  }

  Future<void> _checkMotionPhotos() async {
    for (int i = 0; i < widget.images.length; i++) {
      final isMotion =
          await _motionPhotoService.isMotionPhoto(widget.images[i]);
      if (isMotion) {
        final videoPath =
            await _motionPhotoService.extractVideo(widget.images[i]);
        if (mounted) {
          setState(() {
            _isMotionPhotoMap[i] = true;
            _videoPathMap[i] = videoPath;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _playMotionPhoto(int index) {
    final videoPath = _videoPathMap[index];
    if (videoPath != null && File(videoPath).existsSync()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MotionPhotoVideoPlayer(
            videoPath: videoPath,
            imagePath: widget.images[index],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final isMotionPhoto = _isMotionPhotoMap[index] ?? false;

          return GestureDetector(
            onLongPress: isMotionPhoto ? () => _playMotionPhoto(index) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 图片
                InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Hero(
                      tag: 'image_${widget.images[index]}',
                      child: OriginalImage(
                        path: widget.images[index],
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                // 实况标识
                if (isMotionPhoto)
                  Positioned(
                    top: 40,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            color: Colors.orange.shade300,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '实况',
                            style: TextStyle(
                              color: Colors.orange.shade300,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 长按提示
                if (isMotionPhoto)
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '长按播放实况',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
