/// 心情模型
class Mood {
  final int? id;
  final String name;
  final String emoji;
  final String color; // 十六进制颜色值，如 #FF5733
  final int sortOrder;

  Mood({
    this.id,
    required this.name,
    required this.emoji,
    required this.color,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'color': color,
      'sort_order': sortOrder,
    };
  }

  factory Mood.fromMap(Map<String, dynamic> map) {
    return Mood(
      id: map['id'] as int?,
      name: map['name'] as String,
      emoji: map['emoji'] as String,
      color: map['color'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Mood copyWith({
    int? id,
    String? name,
    String? emoji,
    String? color,
    int? sortOrder,
  }) {
    return Mood(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  // 默认心情列表
  static List<Mood> get defaultMoods => [
    Mood(
      name: '开心',
      emoji: '😊',
      color: '#4CAF50',
      sortOrder: 0,
    ),
    Mood(
      name: '平静',
      emoji: '😌',
      color: '#2196F3',
      sortOrder: 1,
    ),
    Mood(
      name: '难过',
      emoji: '😢',
      color: '#9E9E9E',
      sortOrder: 2,
    ),
    Mood(
      name: '生气',
      emoji: '😠',
      color: '#F44336',
      sortOrder: 3,
    ),
    Mood(
      name: '惊喜',
      emoji: '😮',
      color: '#FF9800',
      sortOrder: 4,
    ),
    Mood(
      name: '疲惫',
      emoji: '😴',
      color: '#795548',
      sortOrder: 5,
    ),
  ];
}
