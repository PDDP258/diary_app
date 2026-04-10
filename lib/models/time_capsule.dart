/// 时间胶囊模型 - 给未来的信
class TimeCapsule {
  final int? id;
  final String title; // 信件标题
  final String content; // 信件内容
  final String? images; // 逗号分隔的图片路径（可选）
  final DateTime createdAt; // 创建时间
  final DateTime unlockDate; // 解锁日期
  final bool isUnlocked; // 是否已解锁
  final DateTime? unlockedAt; // 实际解锁时间
  final bool isRead; // 是否已阅读
  final String? moodEmoji; // 创建时的心情表情（可选）

  TimeCapsule({
    this.id,
    required this.title,
    required this.content,
    this.images,
    required this.createdAt,
    required this.unlockDate,
    this.isUnlocked = false,
    this.unlockedAt,
    this.isRead = false,
    this.moodEmoji,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'images': images,
      'created_at': createdAt.toIso8601String(),
      'unlock_date': unlockDate.toIso8601String(),
      'is_unlocked': isUnlocked ? 1 : 0,
      'unlocked_at': unlockedAt?.toIso8601String(),
      'is_read': isRead ? 1 : 0,
      'mood_emoji': moodEmoji,
    };
  }

  factory TimeCapsule.fromMap(Map<String, dynamic> map) {
    return TimeCapsule(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      images: map['images'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      unlockDate: DateTime.parse(map['unlock_date'] as String),
      isUnlocked: (map['is_unlocked'] as int? ?? 0) == 1,
      unlockedAt: map['unlocked_at'] != null 
          ? DateTime.parse(map['unlocked_at'] as String) 
          : null,
      isRead: (map['is_read'] as int? ?? 0) == 1,
      moodEmoji: map['mood_emoji'] as String?,
    );
  }

  TimeCapsule copyWith({
    int? id,
    String? title,
    String? content,
    String? images,
    DateTime? createdAt,
    DateTime? unlockDate,
    bool? isUnlocked,
    DateTime? unlockedAt,
    bool? isRead,
    String? moodEmoji,
  }) {
    return TimeCapsule(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      unlockDate: unlockDate ?? this.unlockDate,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      isRead: isRead ?? this.isRead,
      moodEmoji: moodEmoji ?? this.moodEmoji,
    );
  }

  // 获取图片列表
  List<String> get imageList {
    if (images == null || images!.isEmpty) return [];
    return images!.split(',').where((path) => path.isNotEmpty).toList();
  }

  // 检查是否已达到解锁日期
  bool get canUnlock {
    return DateTime.now().isAfter(unlockDate) || 
           DateTime.now().isAtSameMomentAs(unlockDate);
  }

  // 获取剩余天数
  int get remainingDays {
    final now = DateTime.now();
    final difference = unlockDate.difference(now);
    return difference.inDays;
  }

  // 获取等待时间描述
  String get waitingTimeDesc {
    final days = remainingDays;
    if (days > 365) {
      final years = days ~/ 365;
      final remaining = days % 365;
      if (remaining > 30) {
        final months = remaining ~/ 30;
        return '$years年${months}个月后';
      }
      return '$years年后';
    } else if (days > 30) {
      final months = days ~/ 30;
      final remainingDays = days % 30;
      if (remainingDays > 0) {
        return '$months个月$remainingDays天后';
      }
      return '$months个月后';
    } else if (days > 0) {
      return '$days天后';
    } else if (days == 0) {
      return '今天';
    } else {
      return '已可解锁';
    }
  }

  // 获取创建时间描述
  String get createdTimeDesc {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    
    if (difference.inDays > 365) {
      return '${difference.inDays ~/ 365}年前';
    } else if (difference.inDays > 30) {
      return '${difference.inDays ~/ 30}个月前';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}
