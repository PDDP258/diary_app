import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/tag_system.dart';
import '../services/tag_system_service.dart';
import '../providers/theme_provider.dart';

/// 三级标签管理页面
class TagManagementScreenV3 extends StatefulWidget {
  const TagManagementScreenV3({super.key});

  @override
  State<TagManagementScreenV3> createState() => _TagManagementScreenV3State();
}

class _TagManagementScreenV3State extends State<TagManagementScreenV3> {
  TagSystem? _tagSystem;
  bool _isLoading = true;
  
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
  
  Future<void> _saveTagSystem() async {
    if (_tagSystem != null) {
      await TagSystemService.saveTagSystem(_tagSystem!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        title: Text(
          '标签管理',
          style: TextStyle(color: scheme.textDarkColor),
        ),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
        actions: [
          // 添加分类按钮
          TextButton.icon(
            onPressed: () => _showAddCategoryDialog(context),
            icon: Icon(Icons.add, color: scheme.primaryColor),
            label: Text(
              '分类',
              style: TextStyle(color: scheme.primaryColor),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: scheme.primaryColor),
            )
          : _tagSystem == null || _tagSystem!.categories.isEmpty
              ? _buildEmptyState(scheme)
              : _buildTagSystemList(scheme),
    );
  }
  
  /// 空状态
  Widget _buildEmptyState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.label_outline,
            size: 64,
            color: scheme.textLightColor,
          ),
          const SizedBox(height: 16),
          Text(
            '还没有创建任何标签',
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角添加分类开始创建标签',
            style: TextStyle(
              fontSize: 12,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 标签系统列表
  Widget _buildTagSystemList(ThemeScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tagSystem!.categories.length,
      itemBuilder: (context, index) {
        final category = _tagSystem!.categories[index];
        return _buildCategoryCard(category, scheme);
      },
    );
  }
  
  /// 分类卡片
  Widget _buildCategoryCard(TagLevel1 category, ThemeScheme scheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: scheme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: category.color.withValues(alpha: 0.3), width: 2),
      ),
      child: ExpansionTile(
        leading: GestureDetector(
          onTap: () => _showEditCategoryDialog(context, category),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                category.emoji ?? '🏷️',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
        ),
        title: Text(
          category.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: scheme.textDarkColor,
          ),
        ),
        subtitle: Text(
          '${category.subCategories.length}个子分类 · ${category.totalTags}个标签',
          style: TextStyle(
            fontSize: 12,
            color: scheme.textLightColor,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.add, color: scheme.primaryColor),
              onPressed: () => _showAddSubCategoryDialog(context, category),
              tooltip: '添加子分类',
            ),
            IconButton(
              icon: Icon(Icons.more_vert, color: scheme.textMediumColor),
              onPressed: () => _showCategoryMenu(context, category),
            ),
          ],
        ),
        children: category.subCategories.map((sub) {
          return _buildSubCategoryTile(category, sub, scheme);
        }).toList(),
      ),
    );
  }
  
  /// 子分类项
  Widget _buildSubCategoryTile(TagLevel1 category, TagLevel2 sub, ThemeScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.lightColor.withValues(alpha: 0.1)),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: Text(
          sub.emoji ?? '📁',
          style: const TextStyle(fontSize: 18),
        ),
        title: Text(
          sub.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.textDarkColor,
          ),
        ),
        subtitle: Text(
          '${sub.tags.length}个标签',
          style: TextStyle(
            fontSize: 11,
            color: scheme.textLightColor,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.add, size: 20, color: scheme.primaryColor),
              onPressed: () => _showAddTagDialog(context, category, sub),
              tooltip: '添加标签',
            ),
            IconButton(
              icon: Icon(Icons.edit, size: 20, color: scheme.textMediumColor),
              onPressed: () => _showEditSubCategoryDialog(context, category, sub),
            ),
          ],
        ),
        children: sub.tags.map((tag) {
          return _buildTagTile(category, sub, tag, scheme);
        }).toList(),
      ),
    );
  }
  
  /// 标签项
  Widget _buildTagTile(TagLevel1 category, TagLevel2 sub, TagLevel3 tag, ThemeScheme scheme) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 48, right: 24),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: category.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            tag.emoji ?? '🏷️',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
      title: Text(
        tag.name,
        style: TextStyle(
          fontSize: 13,
          color: scheme.textDarkColor,
        ),
      ),
      subtitle: Text(
        '使用 ${tag.usageCount} 次',
        style: TextStyle(
          fontSize: 11,
          color: scheme.textLightColor,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit, size: 18, color: scheme.textMediumColor),
            onPressed: () => _showEditTagDialog(context, category, sub, tag),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: scheme.errorColor.withValues(alpha: 0.7)),
            onPressed: () => _showDeleteTagConfirm(context, category, sub, tag),
          ),
        ],
      ),
    );
  }
  
  // ==================== 对话框 ====================
  
  /// 添加分类对话框
  void _showAddCategoryDialog(BuildContext context) {
    final nameController = TextEditingController();
    String selectedEmoji = '📂';
    Color selectedColor = Colors.blue;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji选择
              GestureDetector(
                onTap: () async {
                  final emoji = await showEmojiPicker(context);
                  if (emoji != null) {
                    setDialogState(() => selectedEmoji = emoji);
                  }
                },
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: selectedColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(selectedEmoji, style: const TextStyle(fontSize: 30)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 名称输入
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '分类名称',
                  hintText: '如：生活、工作、情感...',
                ),
              ),
              const SizedBox(height: 16),
              // 颜色选择
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Colors.blue,
                  Colors.green,
                  Colors.orange,
                  Colors.purple,
                  Colors.pink,
                  Colors.teal,
                  Colors.indigo,
                  Colors.red,
                ].map((color) {
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = color),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selectedColor == color
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: selectedColor == color
                            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.trim().isNotEmpty) {
                  await TagSystemService.addCategory(
                    name: nameController.text.trim(),
                    emoji: selectedEmoji,
                    color: selectedColor,
                  );
                  await _loadTagSystem();
                  if (mounted) Navigator.pop(context);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 编辑分类对话框
  void _showEditCategoryDialog(BuildContext context, TagLevel1 category) {
    final nameController = TextEditingController(text: category.name);
    String selectedEmoji = category.emoji ?? '🏷️';
    Color selectedColor = category.color;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final emoji = await showEmojiPicker(context);
                  if (emoji != null) {
                    setDialogState(() => selectedEmoji = emoji);
                  }
                },
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: selectedColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(selectedEmoji, style: const TextStyle(fontSize: 30)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '分类名称'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Colors.blue,
                  Colors.green,
                  Colors.orange,
                  Colors.purple,
                  Colors.pink,
                  Colors.teal,
                  Colors.indigo,
                  Colors.red,
                ].map((color) {
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = color),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selectedColor == color
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                final newCategory = category.copyWith(
                  name: nameController.text.trim(),
                  emoji: selectedEmoji,
                  color: selectedColor,
                );
                await TagSystemService.updateCategory(newCategory);
                await _loadTagSystem();
                if (mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 添加子分类对话框
  void _showAddSubCategoryDialog(BuildContext context, TagLevel1 category) {
    final nameController = TextEditingController();
    String selectedEmoji = '📁';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加子分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final emoji = await showEmojiPicker(context);
                  if (emoji != null) {
                    setDialogState(() => selectedEmoji = emoji);
                  }
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(selectedEmoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '子分类名称',
                  hintText: '如：美食、旅行、日常...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.trim().isNotEmpty) {
                  await TagSystemService.addSubCategory(
                    categoryId: category.id,
                    name: nameController.text.trim(),
                    emoji: selectedEmoji,
                  );
                  await _loadTagSystem();
                  if (mounted) Navigator.pop(context);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 编辑子分类对话框
  void _showEditSubCategoryDialog(BuildContext context, TagLevel1 category, TagLevel2 sub) {
    final nameController = TextEditingController(text: sub.name);
    String selectedEmoji = sub.emoji ?? '📁';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑子分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final emoji = await showEmojiPicker(context);
                  if (emoji != null) {
                    setDialogState(() => selectedEmoji = emoji);
                  }
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(selectedEmoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '子分类名称'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                final newSub = sub.copyWith(
                  name: nameController.text.trim(),
                  emoji: selectedEmoji,
                );
                await TagSystemService.updateSubCategory(
                  categoryId: category.id,
                  subCategory: newSub,
                );
                await _loadTagSystem();
                if (mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 添加标签对话框
  void _showAddTagDialog(BuildContext context, TagLevel1 category, TagLevel2 sub) {
    final nameController = TextEditingController();
    String selectedEmoji = '🏷️';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final emoji = await showEmojiPicker(context);
                  if (emoji != null) {
                    setDialogState(() => selectedEmoji = emoji);
                  }
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(selectedEmoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '标签名称',
                  hintText: '输入标签名称',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.trim().isNotEmpty) {
                  await TagSystemService.addTag(
                    categoryId: category.id,
                    subCategoryId: sub.id,
                    name: nameController.text.trim(),
                    emoji: selectedEmoji,
                  );
                  await _loadTagSystem();
                  if (mounted) Navigator.pop(context);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 编辑标签对话框
  void _showEditTagDialog(BuildContext context, TagLevel1 category, TagLevel2 sub, TagLevel3 tag) {
    final nameController = TextEditingController(text: tag.name);
    String selectedEmoji = tag.emoji ?? '🏷️';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final emoji = await showEmojiPicker(context);
                  if (emoji != null) {
                    setDialogState(() => selectedEmoji = emoji);
                  }
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(selectedEmoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '标签名称'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                final newTag = tag.copyWith(
                  name: nameController.text.trim(),
                  emoji: selectedEmoji,
                );
                await TagSystemService.updateTag(
                  categoryId: category.id,
                  subCategoryId: sub.id,
                  tag: newTag,
                );
                await _loadTagSystem();
                if (mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 删除标签确认
  void _showDeleteTagConfirm(BuildContext context, TagLevel1 category, TagLevel2 sub, TagLevel3 tag) {
    final scheme = AppTheme.schemeOf(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: scheme.errorColor),
            const SizedBox(width: 8),
            const Text('确认删除'),
          ],
        ),
        content: Text(
          '删除标签"${tag.name}"后，该标签将从所有日记中移除。此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await TagSystemService.deleteTag(
                categoryId: category.id,
                subCategoryId: sub.id,
                tagId: tag.id,
              );
              await _loadTagSystem();
              if (mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: scheme.errorColor),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
  
  /// 分类菜单
  void _showCategoryMenu(BuildContext context, TagLevel1 category) {
    final scheme = AppTheme.schemeOf(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑分类'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditCategoryDialog(context, category);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.errorColor),
                title: Text('删除分类', style: TextStyle(color: scheme.errorColor)),
                subtitle: Text('将同时删除所有子分类和标签'),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteCategoryConfirm(context, category);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 删除分类确认
  void _showDeleteCategoryConfirm(BuildContext context, TagLevel1 category) {
    final scheme = AppTheme.schemeOf(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: scheme.errorColor),
            const SizedBox(width: 8),
            const Text('确认删除分类'),
          ],
        ),
        content: Text(
          '删除分类"${category.name}"将同时删除其下的${category.subCategories.length}个子分类和${category.totalTags}个标签。此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await TagSystemService.deleteCategory(category.id);
              await _loadTagSystem();
              if (mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: scheme.errorColor),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// Emoji选择器
Future<String?> showEmojiPicker(BuildContext context) async {
  final emojis = [
    '🏷️', '📌', '📍', '🔖', '🏠', '💼', '❤️', '🎮', '✈️', '📷',
    '🍔', '🍜', '🍰', '☕', '🍵', '🍺', '🎬', '🎵', '📚', '💻',
    '📱', '💰', '🛒', '🎁', '🎉', '🎊', '🌟', '⭐', '💫', '✨',
    '🔥', '💥', '💢', '💦', '💨', '🌈', '☀️', '🌤️', '⛅', '🌧️',
    '🌸', '🍀', '🌿', '🌲', '🌵', '🍄', '🌰', '🌾', '🌷', '🌹',
    '🏃', '🚴', '🏊', '🧘', '🎨', '🎭', '🎪', '🎯', '🎲', '🎳',
    '😊', '😄', '😆', '😅', '😂', '🥰', '😍', '🤔', '😴', '😭',
    '👨‍👩‍👧', '👨‍👩‍👧‍👦', '👨‍👩‍👦‍👦', '👩‍👩‍👧', '👨‍👨‍👧', '👪', '👫', '👭', '👬', '💑',
    '💡', '🎓', '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🏵️', '🎗️',
  ];
  
  return await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: 350,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '选择图标',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context, emojis[index]),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(emojis[index], style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
