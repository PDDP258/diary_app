import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../models/tag.dart';
import '../providers/theme_provider.dart';
import '../services/database_service.dart';
import '../utils/platform_helpers.dart';
import 'tag_diaries_screen.dart';

/// 按标签分类页面
/// 显示所有标签的网格布局，每个标签显示最近9篇日记的预览（3x3九宫格）
class TagsClassificationScreen extends StatefulWidget {
  const TagsClassificationScreen({super.key});

  @override
  State<TagsClassificationScreen> createState() => _TagsClassificationScreenState();
}

class _TagsClassificationScreenState extends State<TagsClassificationScreen> {
  List<Tag> _tags = [];
  Map<int, List<Diary>> _tagDiaries = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 获取所有标签
      final tags = await DatabaseService.getAllTags();
      
      // 获取每个标签的日记（最多9篇用于预览）
      final Map<int, List<Diary>> tagDiaries = {};
      for (final tag in tags) {
        if (tag.id != null) {
          final diaries = await DatabaseService.getDiariesByTagId(tag.id!);
          tagDiaries[tag.id!] = diaries.take(9).toList();
        }
      }

      if (mounted) {
        setState(() {
          _tags = tags;
          _tagDiaries = tagDiaries;
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

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        title: const Text('按标签分类'),
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
          : _tags.isEmpty
              ? _buildEmptyState(scheme)
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: scheme.primaryColor,
                  child: _buildTagsGrid(scheme),
                ),
    );
  }

  Widget _buildEmptyState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.label_outlined,
            size: 64,
            color: scheme.textLightColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有标签',
            style: TextStyle(
              fontSize: 18,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在写日记时添加标签，这里会显示分类',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsGrid(ThemeScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            '标签分类',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: scheme.textDarkColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击标签查看所有相关日记',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 20),
          // 标签网格 - 每行1个（扩大两倍）
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,  // 改为1列，每个卡片占满整行（扩大两倍）
              childAspectRatio: 0.85,  // 调整宽高比，让卡片更高以容纳九宫格
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _tags.length,
            itemBuilder: (context, index) {
              return _buildTagCard(_tags[index], scheme);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTagCard(Tag tag, ThemeScheme scheme) {
    final tagColor = Color(int.parse(tag.color.replaceFirst('#', '0xFF')));
    final diaries = _tagDiaries[tag.id] ?? [];
    final diaryCount = diaries.length;

    return GestureDetector(
      onTap: () => _navigateToTagDiaries(tag),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标签头部
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: tagColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tag.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: tagColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$diaryCount篇',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.textLightColor,
                    ),
                  ),
                ],
              ),
            ),
            // 9宫格预览（3x3）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                height: 320, // 增加高度确保九宫格完整显示
                child: _buildPreviewGrid(diaries, scheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewGrid(List<Diary> diaries, ThemeScheme scheme) {
    // 生成9个格子（3x3九宫格）
    final items = <Widget>[];
    for (int i = 0; i < 9; i++) {
      if (i < diaries.length) {
        items.add(_buildPreviewItem(diaries[i], scheme));
      } else {
        items.add(_buildEmptyPreviewItem(scheme));
      }
    }

    return GridView.count(
      crossAxisCount: 3,  // 3x3九宫格
      childAspectRatio: 1,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: items,
    );
  }

  Widget _buildPreviewItem(Diary diary, ThemeScheme scheme) {
    final images = diary.imageList;
    
    // 如果有图片，只显示图片，不显示文字
    if (images.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.grey[200],
          child: PlatformImage(
            path: images.first,
            fit: BoxFit.cover,
            cacheWidth: 150,
            cacheHeight: 150,
          ),
        ),
      );
    }

    // 无图片时显示文字（取标题前2字或内容前2字或"记"）
    String displayText = '记';
    if (diary.title != null && diary.title!.isNotEmpty) {
      displayText = diary.title!.length >= 2 
          ? diary.title!.substring(0, 2) 
          : diary.title!;
    } else if (diary.content != null && diary.content!.isNotEmpty) {
      displayText = diary.content!.length >= 2 
          ? diary.content!.substring(0, 2) 
          : diary.content!;
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.lightColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          displayText,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: scheme.textMediumColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildEmptyPreviewItem(ThemeScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.lightColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  void _navigateToTagDiaries(Tag tag) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagDiariesScreen(tag: tag),
      ),
    );
    // 如果有日记被删除，刷新数据
    if (result == true) {
      _loadData();
    }
  }
}
