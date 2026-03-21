import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../models/tag.dart';
import '../providers/theme_provider.dart';
import '../services/database_service.dart';
import '../services/tag_system_service.dart';
import '../utils/platform_helpers.dart';
import 'diary_detail_screen.dart';

/// 标签日记列表页
/// 显示某个标签下的所有日记
/// 支持旧版Tag对象或新版三级标签系统的String tagId
class TagDiariesScreen extends StatefulWidget {
  final Tag? tag;
  final String? tagId;
  final String? tagName;

  const TagDiariesScreen({
    super.key,
    this.tag,
    this.tagId,
    this.tagName,
  }) : assert(tag != null || tagId != null, '必须提供tag或tagId');

  @override
  State<TagDiariesScreen> createState() => _TagDiariesScreenState();
}

class _TagDiariesScreenState extends State<TagDiariesScreen> {
  List<Diary> _diaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDiaries();
  }

  Future<void> _loadDiaries() async {
    setState(() => _isLoading = true);

    try {
      List<Diary> diaries = [];
      
      if (widget.tagId != null) {
        // 使用新版三级标签系统
        diaries = await TagSystemService.getDiariesByTagId(widget.tagId!);
      } else if (widget.tag?.id != null) {
        // 使用旧版标签系统
        diaries = await DatabaseService.getDiariesByTagId(widget.tag!.id!);
      }
      
      if (mounted) {
        setState(() {
          _diaries = diaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    // 获取标签显示信息
    final String tagName = widget.tagName ?? widget.tag?.name ?? '标签';
    final Color tagColor = widget.tag != null 
        ? Color(int.parse(widget.tag!.color.replaceFirst('#', '0xFF')))
        : scheme.primaryColor;

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tagColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tagName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tagColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_diaries.length}篇',
              style: TextStyle(
                fontSize: 14,
                color: scheme.textLightColor,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(scheme.primaryColor),
              ),
            )
          : _diaries.isEmpty
              ? _buildEmptyState(scheme)
              : RefreshIndicator(
                  onRefresh: _loadDiaries,
                  color: scheme.primaryColor,
                  child: _buildDiariesList(scheme),
                ),
    );
  }

  Widget _buildEmptyState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 64,
            color: scheme.textLightColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有日记',
            style: TextStyle(
              fontSize: 18,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '使用此标签的日记会显示在这里',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiariesList(ThemeScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _diaries.length,
      itemBuilder: (context, index) {
        return _buildDiaryCard(_diaries[index], scheme);
      },
    );
  }

  Widget _buildDiaryCard(Diary diary, ThemeScheme scheme) {
    final date = DateTime.parse(diary.date);
    final images = diary.imageList;
    final hasImages = images.isNotEmpty;

    return GestureDetector(
      onTap: () => _viewDiaryDetail(diary),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.softShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧日期卡片
            Container(
              width: 70,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('dd').format(date),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: scheme.primaryColor,
                    ),
                  ),
                  Text(
                    DateFormat('MMM', 'zh_CN').format(date),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.textMediumColor,
                    ),
                  ),
                ],
              ),
            ),
            // 右侧内容
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题和心情
                    Row(
                      children: [
                        if (diary.moodEmoji != null && diary.moodEmoji!.isNotEmpty) ...[
                          Text(
                            diary.moodEmoji!,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            diary.title ?? '无标题',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: scheme.textDarkColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 内容预览
                    if (diary.content != null && diary.content!.isNotEmpty)
                      Text(
                        diary.content!,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textMediumColor,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // 图片指示器
                    if (hasImages) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 14,
                            color: scheme.textLightColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${images.length}张图片',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.textLightColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 右侧缩略图（如果有图片）
            if (hasImages)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: SizedBox(
                  width: 80,
                  height: 100,
                  child: PlatformImage(
                    path: images.first,
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                    cacheHeight: 200,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _viewDiaryDetail(Diary diary) async {
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryDetailScreen(diary: diary),
      ),
    );
    // 如果日记被删除或修改，刷新列表
    if (result == true && mounted) {
      _loadDiaries();
      // 通知上级页面也刷新
      Navigator.pop(context, true);
    }
  }
}
