/// 日记模型（完善版）
class Diary {
  final int? id;
  final String? title;
  final String? content;
  final String date;
  final String? images; // 逗号分隔的图片路径
  final int? moodId; // 心情ID
  final String? moodName; // 心情名称（冗余存储，方便查询）
  final String? moodEmoji; // 心情表情
  final String? weather; // 天气
  final String? location; // 位置
  final bool isFavorite; // 是否收藏
  final String? createdAt;
  final String? updatedAt;

  Diary({
    this.id,
    this.title,
    this.content,
    required this.date,
    this.images,
    this.moodId,
    this.moodName,
    this.moodEmoji,
    this.weather,
    this.location,
    this.isFavorite = false,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'date': date,
      'images': images,
      'mood_id': moodId,
      'mood_name': moodName,
      'mood_emoji': moodEmoji,
      'weather': weather,
      'location': location,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Diary.fromMap(Map<String, dynamic> map) {
    return Diary(
      id: map['id'] as int?,
      title: map['title'] as String?,
      content: map['content'] as String?,
      date: map['date'] as String,
      images: map['images'] as String?,
      moodId: map['mood_id'] as int?,
      moodName: map['mood_name'] as String?,
      moodEmoji: map['mood_emoji'] as String?,
      weather: map['weather'] as String?,
      location: map['location'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  Diary copyWith({
    int? id,
    String? title,
    String? content,
    String? date,
    String? images,
    int? moodId,
    String? moodName,
    String? moodEmoji,
    String? weather,
    String? location,
    bool? isFavorite,
    String? createdAt,
    String? updatedAt,
  }) {
    return Diary(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      date: date ?? this.date,
      images: images ?? this.images,
      moodId: moodId ?? this.moodId,
      moodName: moodName ?? this.moodName,
      moodEmoji: moodEmoji ?? this.moodEmoji,
      weather: weather ?? this.weather,
      location: location ?? this.location,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // 获取图片列表
  List<String> get imageList {
    if (images == null || images!.isEmpty) return [];
    return images!.split(',').where((path) => path.isNotEmpty).toList();
  }

  // 计算内容字数（排除纪念日文字）
  int get wordCount {
    int count = 0;
    if (title != null) count += title!.length;
    if (content != null) {
      // 排除纪念日文字
      final anniversaryPattern = RegExp(
        r'[\n]*[🎉⏰][^\n]*(?:纪念日|倒数日)[^\n]*',
        multiLine: true,
      );
      final userContent = content!.replaceAll(anniversaryPattern, '').trim();
      count += userContent.length;
    }
    return count;
  }
}
