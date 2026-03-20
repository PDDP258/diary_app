/// 标签模型
class Tag {
  final int? id;
  final String name;
  final String color; // 十六进制颜色值
  final int usageCount;
  final DateTime? createdAt;

  Tag({
    this.id,
    required this.name,
    required this.color,
    this.usageCount = 0,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'usage_count': usageCount,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int?,
      name: map['name'] as String,
      color: map['color'] as String,
      usageCount: map['usage_count'] as int? ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  Tag copyWith({
    int? id,
    String? name,
    String? color,
    int? usageCount,
    DateTime? createdAt,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
