/// 消息发送者类型
enum SelfTalkSenderType {
  me,       // 我（用户本人）
  alterEgo, // 另一个我（Alter Ego）
  system,   // 系统/AI
}

/// 自言自语消息模型
class SelfTalkMessage {
  final int? id;
  final int? diaryId; // 关联的日记ID（当天日记）
  final String date; // yyyy-MM-dd
  final String content;
  final bool isUser; // true=用户侧（me/alterEgo）, false=系统
  final SelfTalkSenderType senderType;
  final String createdAt; // ISO8601

  SelfTalkMessage({
    this.id,
    this.diaryId,
    required this.date,
    required this.content,
    this.isUser = true,
    this.senderType = SelfTalkSenderType.me,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'diary_id': diaryId,
      'date': date,
      'content': content,
      'is_user': isUser ? 1 : 0,
      'sender_type': senderType.index,
      'created_at': createdAt,
    };
  }

  factory SelfTalkMessage.fromMap(Map<String, dynamic> map) {
    // sender_type 兼容处理：int / double / String 都可能出现（JSON 序列化后）
    int? senderTypeIndex;
    final rawSenderType = map['sender_type'];
    if (rawSenderType is int) {
      senderTypeIndex = rawSenderType;
    } else if (rawSenderType is double) {
      senderTypeIndex = rawSenderType.toInt();
    } else if (rawSenderType is String) {
      senderTypeIndex = int.tryParse(rawSenderType);
    }
    senderTypeIndex ??= 0;
    senderTypeIndex = senderTypeIndex.clamp(0, SelfTalkSenderType.values.length - 1);

    return SelfTalkMessage(
      id: map['id'] as int?,
      diaryId: map['diary_id'] as int?,
      date: map['date'] as String,
      content: map['content'] as String,
      isUser: (map['is_user'] as int? ?? 1) == 1,
      senderType: SelfTalkSenderType.values[senderTypeIndex],
      createdAt: map['created_at'] as String,
    );
  }

  SelfTalkMessage copyWith({
    int? id,
    int? diaryId,
    String? date,
    String? content,
    bool? isUser,
    SelfTalkSenderType? senderType,
    String? createdAt,
  }) {
    return SelfTalkMessage(
      id: id ?? this.id,
      diaryId: diaryId ?? this.diaryId,
      date: date ?? this.date,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      senderType: senderType ?? this.senderType,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
