import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../models/quick_note.dart';
import '../services/quick_note_service.dart';
import 'quick_notes_screen.dart';

/// 速记编辑页 - 极简设计，只有一个多行文本框
class QuickNoteEditorScreen extends StatefulWidget {
  final QuickNote? note; // 为 null 时创建新速记

  const QuickNoteEditorScreen({super.key, this.note});

  @override
  State<QuickNoteEditorScreen> createState() => _QuickNoteEditorScreenState();
}

class _QuickNoteEditorScreenState extends State<QuickNoteEditorScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSaving = false;
  String? _selectedTag;

  static const List<String> _presetTags = ['灵感', '待办', '备忘', '读书', '想法'];

  @override
  void initState() {
    super.initState();
    if (widget.note != null) {
      _controller.text = widget.note!.content;
      _selectedTag = widget.note!.tag;
    }
    // 自动聚焦
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      HapticFeedback.lightImpact();
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      if (widget.note != null) {
        await QuickNoteService.update(
          widget.note!.id!,
          text,
          tag: _selectedTag,
        );
      } else {
        await QuickNoteService.insert(text, tag: _selectedTag);
      }
      if (mounted) {
        // 保存成功后提示用户去哪里查看
        final count = await QuickNoteService.getCount();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存，共 $count 条速记'),
            action: SnackBarAction(
              label: '查看全部',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QuickNotesScreen()),
                );
              },
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final isEditing = widget.note != null;

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: scheme.textDarkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? '编辑速记' : '新建速记',
          style: TextStyle(color: scheme.textDarkColor, fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primaryColor,
                    ),
                  )
                : Text(
                    '保存',
                    style: TextStyle(
                      color: scheme.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.textDarkColor,
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  hintText: '写下你的想法，无需任何格式...',
                  hintStyle: TextStyle(color: scheme.textLightColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          // 标签选择
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: scheme.cardColor,
              border: Border(top: BorderSide(color: scheme.dividerColor)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '标签（可选）',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.textLightColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._presetTags.map((tag) => _buildTagChip(tag, scheme)),
                      if (_selectedTag != null && !_presetTags.contains(_selectedTag))
                        _buildTagChip(_selectedTag!, scheme),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag, ThemeScheme scheme) {
    final isSelected = _selectedTag == tag;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedTag = isSelected ? null : tag;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primaryColor.withValues(alpha: 0.12)
              : scheme.backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? scheme.primaryColor.withValues(alpha: 0.5)
                : scheme.dividerColor,
          ),
        ),
        child: Text(
          tag,
          style: TextStyle(
            fontSize: 13,
            color: isSelected ? scheme.primaryColor : scheme.textMediumColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
