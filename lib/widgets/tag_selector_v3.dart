import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/tag_system.dart';
import '../services/tag_system_service.dart';
import '../providers/theme_provider.dart';

/// 三级标签选择器
class TagSelectorV3 extends StatefulWidget {
  final List<String> selectedTagIds;
  final Function(List<String>) onChanged;
  final int maxSelection;
  
  const TagSelectorV3({
    super.key,
    required this.selectedTagIds,
    required this.onChanged,
    this.maxSelection = 5,
  });

  @override
  State<TagSelectorV3> createState() => _TagSelectorV3State();
}

class _TagSelectorV3State extends State<TagSelectorV3> {
  TagSystem? _tagSystem;
  bool _isLoading = true;
  String _searchQuery = '';
  TagLevel1? _expandedCategory;
  
  @override
  void initState() {
    super.initState();
    _loadTagSystem();
  }
  
  Future<void> _loadTagSystem() async {
    final system = await TagSystemService.getTagSystem();
    setState(() {
      _tagSystem = system;
      _isLoading = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_tagSystem == null || _tagSystem!.categories.isEmpty) {
      return Center(
        child: Text(
          '暂无标签',
          style: TextStyle(color: scheme.textMediumColor),
        ),
      );
    }
    
    // 搜索模式
    if (_searchQuery.isNotEmpty) {
      return _buildSearchResults();
    }
    
    return Column(
      children: [
        // 搜索栏
        _buildSearchBar(scheme),
        const SizedBox(height: 12),
        // 已选标签
        if (widget.selectedTagIds.isNotEmpty) ...[
          _buildSelectedTags(scheme),
          const SizedBox(height: 12),
        ],
        // 分类列表
        Expanded(
          child: ListView.builder(
            itemCount: _tagSystem!.categories.length,
            itemBuilder: (context, index) {
              return _buildCategoryItem(_tagSystem!.categories[index], scheme);
            },
          ),
        ),
      ],
    );
  }
  
  /// 搜索栏
  Widget _buildSearchBar(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: scheme.textLightColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索标签...',
                hintStyle: TextStyle(color: scheme.textLightColor),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(color: scheme.textDarkColor),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _searchQuery = ''),
              child: Icon(Icons.close, color: scheme.textLightColor, size: 18),
            ),
        ],
      ),
    );
  }
  
  /// 已选标签
  Widget _buildSelectedTags(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已选标签',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.primaryColor,
                ),
              ),
              Text(
                '${widget.selectedTagIds.length}/${widget.maxSelection}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.textLightColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selectedTagIds.map((tagId) {
              final tag = _tagSystem!.findTagById(tagId);
              if (tag == null) return const SizedBox.shrink();
              
              return Chip(
                label: Text(tag.name),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _toggleTag(tagId),
                backgroundColor: scheme.primaryColor.withOpacity(0.1),
                side: BorderSide(color: scheme.primaryColor.withOpacity(0.3)),
                labelStyle: TextStyle(
                  color: scheme.primaryColor,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  /// 分类项
  Widget _buildCategoryItem(TagLevel1 category, ThemeScheme scheme) {
    final isExpanded = _expandedCategory?.id == category.id;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: scheme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpanded 
              ? category.color 
              : scheme.lightColor.withOpacity(0.1),
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: category.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              category.emoji ?? '🏷️',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
        title: Text(
          category.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.textDarkColor,
          ),
        ),
        subtitle: Text(
          '${category.totalTags}个标签 · ${category.totalUsage}次使用',
          style: TextStyle(
            fontSize: 11,
            color: scheme.textLightColor,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isExpanded 
                ? category.color.withOpacity(0.2)
                : scheme.lightColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            color: isExpanded ? category.color : scheme.textMediumColor,
          ),
        ),
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedCategory = expanded ? category : null;
          });
        },
        children: category.subCategories.map((sub) {
          return _buildSubCategoryItem(sub, category.color, scheme);
        }).toList(),
      ),
    );
  }
  
  /// 子分类项
  Widget _buildSubCategoryItem(TagLevel2 sub, Color categoryColor, ThemeScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 子分类标题
          Row(
            children: [
              Text(
                sub.emoji ?? '📁',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 6),
              Text(
                sub.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${sub.tags.length}',
                  style: TextStyle(
                    fontSize: 10,
                    color: categoryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 标签网格
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sub.tags.map((tag) {
              final isSelected = widget.selectedTagIds.contains(tag.id);
              return _buildTagChip(tag, isSelected, categoryColor, scheme);
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  /// 标签芯片
  Widget _buildTagChip(TagLevel3 tag, bool isSelected, Color categoryColor, ThemeScheme scheme) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tag.emoji != null) ...[
            Text(tag.emoji!, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
          ],
          Text(tag.name),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => _toggleTag(tag.id),
      selectedColor: categoryColor.withOpacity(0.2),
      backgroundColor: scheme.lightColor.withOpacity(0.3),
      checkmarkColor: categoryColor,
      side: BorderSide(
        color: isSelected ? categoryColor : Colors.transparent,
        width: 1.5,
      ),
      labelStyle: TextStyle(
        color: isSelected ? categoryColor : scheme.textDarkColor,
        fontSize: 12,
      ),
    );
  }
  
  /// 搜索结果
  Widget _buildSearchResults() {
    final results = _tagSystem!.searchTags(_searchQuery);
    final scheme = AppTheme.schemeOf(context);
    
    return Column(
      children: [
        _buildSearchBar(scheme),
        const SizedBox(height: 12),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    '未找到相关标签',
                    style: TextStyle(color: scheme.textMediumColor),
                  ),
                )
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return _buildSearchResultItem(result, scheme);
                  },
                ),
        ),
      ],
    );
  }
  
  /// 搜索结果项
  Widget _buildSearchResultItem(TagSearchResult result, ThemeScheme scheme) {
    final isSelected = widget.selectedTagIds.contains(result.tag.id);
    
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: result.category.color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            result.tag.emoji ?? result.category.emoji ?? '🏷️',
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ),
      title: Text(result.tag.name),
      subtitle: Text(
        '${result.category.name} / ${result.subCategory.name}',
        style: TextStyle(
          fontSize: 12,
          color: scheme.textLightColor,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: scheme.primaryColor)
          : Icon(Icons.circle_outlined, color: scheme.textLightColor),
      onTap: () => _toggleTag(result.tag.id),
    );
  }
  
  /// 切换标签选择
  void _toggleTag(String tagId) {
    if (widget.selectedTagIds.contains(tagId)) {
      widget.onChanged(widget.selectedTagIds.where((id) => id != tagId).toList());
    } else {
      if (widget.selectedTagIds.length >= widget.maxSelection) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('最多选择${widget.maxSelection}个标签')),
        );
        return;
      }
      widget.onChanged([...widget.selectedTagIds, tagId]);
    }
  }
}

/// 标签选择底部弹窗
void showTagSelectorBottomSheet(
  BuildContext context, {
  required List<String> selectedTagIds,
  required Function(List<String>) onChanged,
  int maxSelection = 5,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 顶部把手
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  '选择标签',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
          // 标签选择器
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TagSelectorV3(
                selectedTagIds: selectedTagIds,
                onChanged: onChanged,
                maxSelection: maxSelection,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
