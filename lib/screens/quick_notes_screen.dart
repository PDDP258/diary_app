import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../models/quick_note.dart';
import '../services/quick_note_service.dart';
import 'quick_note_editor_screen.dart';

/// 速记列表页
class QuickNotesScreen extends StatefulWidget {
  const QuickNotesScreen({super.key});

  @override
  State<QuickNotesScreen> createState() => _QuickNotesScreenState();
}

class _QuickNotesScreenState extends State<QuickNotesScreen> {
  List<QuickNote> _notes = [];
  List<String> _tags = [];
  bool _isLoading = true;
  String? _selectedTag;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final notes = _searchQuery.isNotEmpty
          ? await QuickNoteService.search(_searchQuery)
          : _selectedTag != null
              ? await QuickNoteService.getByTag(_selectedTag!)
              : await QuickNoteService.getAll();
      final tags = await QuickNoteService.getAllTags();
      if (mounted) {
        setState(() {
          _notes = notes;
          _tags = tags;
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

  Future<void> _deleteNote(QuickNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = AppTheme.schemeOf(context);
        return AlertDialog(
          backgroundColor: scheme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('删除速记？', style: TextStyle(color: scheme.textDarkColor)),
          content: Text(
            '删除后不可恢复，确定吗？',
            style: TextStyle(color: scheme.textMediumColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消', style: TextStyle(color: scheme.textLightColor)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('删除', style: TextStyle(color: scheme.errorColor)),
            ),
          ],
        );
      },
    );

    if (confirmed == true && note.id != null) {
      await QuickNoteService.delete(note.id!);
      _loadData();
    }
  }

  Future<void> _togglePin(QuickNote note) async {
    if (note.id == null) return;
    HapticFeedback.lightImpact();
    await QuickNoteService.togglePin(note.id!);
    _loadData();
  }

  Future<void> _openEditor({QuickNote? note}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => QuickNoteEditorScreen(note: note),
      ),
    );
    if (result == true) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        title: Text('速记', style: TextStyle(color: scheme.textDarkColor, fontSize: 17)),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: scheme.primaryColor),
            onPressed: () => _openEditor(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _loadData();
              },
              style: TextStyle(color: scheme.textDarkColor, fontSize: 15),
              decoration: InputDecoration(
                hintText: '搜索速记内容...',
                hintStyle: TextStyle(color: scheme.textLightColor),
                prefixIcon: Icon(Icons.search, color: scheme.textLightColor),
                filled: true,
                fillColor: scheme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          // 标签筛选
          if (_tags.isNotEmpty)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip('全部', _selectedTag == null, () {
                    setState(() => _selectedTag = null);
                    _loadData();
                  }, scheme),
                  ..._tags.map((tag) => _buildFilterChip(
                    tag,
                    _selectedTag == tag,
                    () {
                      setState(() => _selectedTag = tag);
                      _loadData();
                    },
                    scheme,
                  )),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // 列表
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: scheme.primaryColor))
                : _notes.isEmpty
                    ? _buildEmptyState(scheme)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _notes.length,
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          return _buildNoteItem(note, scheme);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: scheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected, VoidCallback onTap, ThemeScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryColor.withValues(alpha: 0.12)
                : scheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primaryColor.withValues(alpha: 0.4)
                  : scheme.dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? scheme.primaryColor : scheme.textMediumColor,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoteItem(QuickNote note, ThemeScheme scheme) {
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // 右滑：置顶
          await _togglePin(note);
          return false; // 不删除
        } else {
          // 左滑：删除
          await _deleteNote(note);
          return false; // 手动处理删除刷新
        }
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: scheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Row(
          children: [
            Icon(
              note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              color: scheme.primaryColor,
            ),
            const SizedBox(width: 8),
            Text(
              note.isPinned ? '取消置顶' : '置顶',
              style: TextStyle(color: scheme.primaryColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: scheme.errorColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '删除',
              style: TextStyle(color: scheme.errorColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Icon(Icons.delete_outline, color: scheme.errorColor),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () => _openEditor(note: note),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: note.isPinned
                ? Border.all(color: scheme.primaryColor.withValues(alpha: 0.3))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.content,
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.textDarkColor,
                  height: 1.5,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (note.tag != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        note.tag!,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.primaryColor,
                        ),
                      ),
                    ),
                  if (note.tag != null) const SizedBox(width: 8),
                  if (note.isPinned)
                    Icon(Icons.push_pin, size: 14, color: scheme.primaryColor),
                  if (note.isPinned) const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatTime(note.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.textLightColor,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 64,
            color: scheme.textLightColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '快速记录你的想法',
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '无需任何格式，打开就能写',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso8601) {
    final dt = DateTime.parse(iso8601);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (dt.year == now.year) return '${dt.month}月${dt.day}日';
    return '${dt.year}年${dt.month}月${dt.day}日';
  }
}
