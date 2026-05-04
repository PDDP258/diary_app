/// 消息发送者类型
enum SelfTalkSenderType {
  me,       // 我（用户本人）
  alterEgo, // 另一个我（Alter Ego）
  system,   // 系统/AI
}

/// 自言自语消息模型
class SelfTalkMessage {
  final int? id;
  final String date; // yyyy-MM-dd
  final String content;
  final bool isUser; // true=用户侧（me/alterEgo）, false=系统
  final SelfTalkSenderType senderType;
  final String createdAt; // ISO8601
  final SelfTalkSenderType? repliedToSenderType; // 系统回复时记录被回复者的类型

  SelfTalkMessage({
    this.id,
    required this.date,
    required this.content,
    this.isUser = true,
    this.senderType = SelfTalkSenderType.me,
    required this.createdAt,
    this.repliedToSenderType,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'content': content,
      'is_user': isUser ? 1 : 0,
      'sender_type': senderType.index,
      'created_at': createdAt,
      'replied_to_sender_type': repliedToSenderType?.index,
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

    // replied_to_sender_type 兼容处理
    int? repliedToIndex;
    final rawRepliedTo = map['replied_to_sender_type'];
    if (rawRepliedTo is int) {
      repliedToIndex = rawRepliedTo;
    } else if (rawRepliedTo is double) {
      repliedToIndex = rawRepliedTo.toInt();
    } else if (rawRepliedTo is String) {
      repliedToIndex = int.tryParse(rawRepliedTo);
    }

    return SelfTalkMessage(
      id: map['id'] as int?,
      date: map['date'] as String,
      content: map['content'] as String,
      isUser: (map['is_user'] as int? ?? 1) == 1,
      senderType: SelfTalkSenderType.values[senderTypeIndex],
      createdAt: map['created_at'] as String,
      repliedToSenderType:
          repliedToIndex != null ? SelfTalkSenderType.values[repliedToIndex] : null,
    );
  }

  SelfTalkMessage copyWith({
    int? id,
    String? date,
    String? content,
    bool? isUser,
    SelfTalkSenderType? senderType,
    String? createdAt,
    SelfTalkSenderType? repliedToSenderType,
  }) {
    return SelfTalkMessage(
      id: id ?? this.id,
      date: date ?? this.date,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      senderType: senderType ?? this.senderType,
      createdAt: createdAt ?? this.createdAt,
      repliedToSenderType: repliedToSenderType ?? this.repliedToSenderType,
    );
  }
}
