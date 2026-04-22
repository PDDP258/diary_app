/// 速记模型 - 快速捕捉一闪而过的想法
/// 
/// 与日记的区别：
/// - 只有纯文本内容，无标题/心情/天气/图片
/// - 极简操作，打开→打字→保存
/// - 独立存储，不参与日记搜索（初期）
class QuickNote {
  final int? id;
  final String content;      // 纯文本内容，必填
  final String createdAt;    // ISO8601 创建时间
  final String? updatedAt;   // ISO8601 最后修改时间
  final bool isPinned;       // 是否置顶
  final String? tag;         // 可选标签（如"灵感"、"待办"）

  QuickNote({
    this.id,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.isPinned = false,
    this.tag,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_pinned': isPinned ? 1 : 0,
      'tag': tag,
    };
  }

  factory QuickNote.fromMap(Map<String, dynamic> map) {
    return QuickNote(
      id: map['id'] as int?,
      content: map['content'] as String,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String?,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      tag: map['tag'] as String?,
    );
  }

  QuickNote copyWith({
    int? id,
    String? content,
    String? createdAt,
    String? updatedAt,
    bool? isPinned,
    String? tag,
  }) {
    return QuickNote(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      tag: tag ?? this.tag,
    );
  }
}
