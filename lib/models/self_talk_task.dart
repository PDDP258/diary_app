/// 自言自语任务模型（DDL / 提醒 / 待办）
class SelfTalkTask {
  final int? id;
  final int? messageId; // 关联的消息ID
  final String date;    // yyyy-MM-dd
  final String content; // 任务内容
  final String? deadline; // 截止时间 ISO8601，可能为null
  final bool isCompleted;
  final String createdAt;

  SelfTalkTask({
    this.id,
    this.messageId,
    required this.date,
    required this.content,
    this.deadline,
    this.isCompleted = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'message_id': messageId,
      'date': date,
      'content': content,
      'deadline': deadline,
      'is_completed': isCompleted ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory SelfTalkTask.fromMap(Map<String, dynamic> map) {
    return SelfTalkTask(
      id: map['id'] as int?,
      messageId: map['message_id'] as int?,
      date: map['date'] as String,
      content: map['content'] as String,
      deadline: map['deadline'] as String?,
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String,
    );
  }

  SelfTalkTask copyWith({
    int? id,
    int? messageId,
    String? date,
    String? content,
    String? deadline,
    bool? isCompleted,
    String? createdAt,
  }) {
    return SelfTalkTask(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      date: date ?? this.date,
      content: content ?? this.content,
      deadline: deadline ?? this.deadline,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
