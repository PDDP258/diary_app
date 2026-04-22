import '../models/quick_note.dart';
import 'database_service.dart';

/// 速记服务 - 快速笔记的 CRUD 和搜索
class QuickNoteService {
  /// 创建速记
  static Future<int> insert(String content, {String? tag}) async {
    final now = DateTime.now().toIso8601String();
    final note = QuickNote(
      content: content,
      createdAt: now,
      updatedAt: now,
      tag: tag,
    );
    return await DatabaseService.insertQuickNote(note);
  }

  /// 更新速记
  static Future<void> update(int id, String content, {String? tag}) async {
    final existing = await DatabaseService.getQuickNoteById(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      content: content,
      updatedAt: DateTime.now().toIso8601String(),
      tag: tag,
    );
    await DatabaseService.updateQuickNote(updated);
  }

  /// 删除速记
  static Future<void> delete(int id) async {
    await DatabaseService.deleteQuickNote(id);
  }

  /// 切换置顶状态
  static Future<void> togglePin(int id) async {
    final note = await DatabaseService.getQuickNoteById(id);
    if (note == null) return;
    final updated = note.copyWith(
      isPinned: !note.isPinned,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await DatabaseService.updateQuickNote(updated);
  }

  /// 获取所有速记（置顶优先，然后按时间倒序）
  static Future<List<QuickNote>> getAll() async {
    return await DatabaseService.getAllQuickNotes();
  }

  /// 按标签筛选
  static Future<List<QuickNote>> getByTag(String tag) async {
    return await DatabaseService.getQuickNotesByTag(tag);
  }

  /// 搜索速记内容
  static Future<List<QuickNote>> search(String keyword) async {
    if (keyword.trim().isEmpty) return getAll();
    return await DatabaseService.searchQuickNotes(keyword.trim());
  }

  /// 获取单条速记
  static Future<QuickNote?> getById(int id) async {
    return await DatabaseService.getQuickNoteById(id);
  }

  /// 获取速记总数
  static Future<int> getCount() async {
    return await DatabaseService.getQuickNoteCount();
  }

  /// 获取所有标签列表（去重）
  static Future<List<String>> getAllTags() async {
    final notes = await getAll();
    final tags = notes.where((n) => n.tag != null && n.tag!.isNotEmpty)
        .map((n) => n.tag!)
        .toSet()
        .toList();
    tags.sort();
    return tags;
  }
}
