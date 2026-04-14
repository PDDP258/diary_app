import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../models/tag_system.dart';
import '../providers/theme_provider.dart';
import '../services/database_service.dart';
import '../services/tag_system_service.dart';
import '../utils/platform_helpers.dart';
import 'tag_diaries_screen.dart';

/// 按标签分类页面
/// 显示所有三级标签的网格布局，每个标签显示最近9篇日记的预览（3x3九宫格）
class TagsClassificationScreen extends StatefulWidget {
  const TagsClassificationScreen({super.key});

  @override
  State<TagsClassificationScreen> createState() => _TagsClassificationScreenState();
}

class _TagsClassificationScreenState extends State<TagsClassificationScreen> {
  List<TagLevel3> _tags = [];
  Map<String, List<Diary>> _tagDiaries = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 获取三级标签系统
      final tagSystem = await TagSystemService.getTagSystem();
      
      // 获取所有三级标签
      final List<TagLevel3> allTags = [];
      for (final category in tagSystem.categories) {
        for (final subCategory in category.subCategories) {
          allTags.addAll(subCategory.tags);
        }
      }
      
      // 按使用次数排序
      allTags.sort((a, b) => b.usageCount.compareTo(a.usageCount));
      
      // 获取每个标签的日记（最多9篇用于预览）
      final Map<String, List<Diary>> tagDiaries = {};
      for (final tag in allTags) {
        final diaries = await TagSystemService.getDiariesByTagId(tag.id);
        tagDiaries[tag.id] = diaries.take(9).toList();
      }

      if (mounted) {
        setState(() {
          _tags = allTags;
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
              fontSize: 16,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在写日记时添加标签，这里会显示分类',
            style: TextStyle(
              fontSize: 13,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsGrid(ThemeScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tags.length,
      itemBuilder: (context, index) {
        final tag = _tags[index];
        final diaries = _tagDiaries[tag.id] ?? [];
        
        return _buildTagCard(tag, diaries, scheme);
      },
    );
  }

  Widget _buildTagCard(TagLevel3 tag, List<Diary> diaries, ThemeScheme scheme) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TagDiariesScreen(
              tagId: tag.id,
              tagName: tag.emoji != null ? '${tag.emoji} ${tag.name}' : tag.name,
            ),
          ),
        ).then((_) => _loadData()); // 返回后刷新
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: scheme.textDarkColor.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标签标题
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tag.emoji != null ? '${tag.emoji} ${tag.name}' : tag.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.primaryColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${tag.usageCount} 篇日记',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.textLightColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: scheme.textLightColor,
                ),
              ],
            ),
            
            // 日记预览九宫格
            if (diaries.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDiaryPreviewGrid(diaries, scheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiaryPreviewGrid(List<Diary> diaries, ThemeScheme scheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: diaries.length.clamp(0, 9),
      itemBuilder: (context, index) {
        final diary = diaries[index];
        return _buildDiaryPreviewItem(diary, scheme);
      },
    );
  }

  Widget _buildDiaryPreviewItem(Diary diary, ThemeScheme scheme) {
    final hasImage = diary.imageList.isNotEmpty;
    
    if (hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: PlatformImage(
          path: diary.imageList.first,
          fit: BoxFit.cover,
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: scheme.lightColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          diary.title?.isNotEmpty == true
              ? diary.title!.substring(0, diary.title!.length.clamp(1, 2))
              : diary.date.substring(5),
          style: TextStyle(
            fontSize: 12,
            color: scheme.textLightColor,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
