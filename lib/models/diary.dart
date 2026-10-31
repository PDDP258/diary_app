/// 日记的来源。
///
/// 只回答一个问题：这篇是谁写的。
/// 落库用字符串（`source` 列），不用 int 枚举序号 —— 以后加来源不必改表，
/// 也能容忍「老版本 App 读到不认识的值」：认不出来就当作没有标记。
enum DiarySource {
  /// 用户自己在 App 里写的。
  ///
  /// 历史数据没有 `source` 列（null），语义上等同于本人手写。
  self('self', '我', '我写的'),

  /// 麦麦（MaiBot）写进收件箱、用户确认后导入的。
  maibot('maibot', '麦麦', '麦麦写的');

  const DiarySource(this.code, this.label, this.detailLabel);

  /// 存储用的字符串标识（写进 DB / 备份 JSON）。
  final String code;

  /// 展示用短名（列表里的紧凑徽标）。
  final String label;

  /// 详情页用的完整说法。
  final String detailLabel;

  /// 从存储值解析；null / 空 / 不认识 → null（= 没有来源标记）。
  static DiarySource? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final value in DiarySource.values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

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

  /// 来源标识，见 [DiarySource] 的 `code`。
  ///
  /// null 表示「没有标记」（历史数据 / 本人手写）。
  /// 存原始字符串而不是枚举，是为了让不认识的来源能原样带回去，
  /// 不会在「读一次再写一次」的过程中被悄悄抹掉。
  final String? source;

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
    this.source,
    this.createdAt,
    this.updatedAt,
  });

  /// 解析后的来源；null 表示没有标记或认不出来。
  DiarySource? get sourceType => DiarySource.fromCode(source);

  /// 是否是麦麦写来的（收件箱导入）。
  bool get isFromMaibot => source == DiarySource.maibot.code;

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
      'source': source,
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
      source: map['source'] is String ? map['source'] as String : null,
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
    String? source,
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
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ==================== 派生字段缓存 ====================
  //
  // `Diary` 的所有字段都是 final，实例不可变，所以派生值可以安全地缓存。
  // 此前 `imageList` / `wordCount` 每次访问都重新计算：
  //   - `imageList`：`split(',')` + `where().toList()` 每次都新建 List
  //   - `wordCount`：**每次都 new RegExp** 再对全文 `replaceAll`
  // 全仓库 `.imageList` 命中 38 处、`.wordCount` 命中 17 处，其中统计页 /
  // 徽章 / 目标 / 文本分析都是对**全量日记**做 fold —— N=1000 时等于每次
  // 上千次正则编译 + 上千次全文替换，是统计类页面卡顿的固定成本。

  /// 纪念日文字的正则：**提成 static final，只编译一次**。
  /// 原先写在 getter 里，每次访问都重新构造 RegExp。
  static final RegExp _anniversaryPattern = RegExp(
    r'[\n]*[🎉⏰][^\n]*(?:纪念日|倒数日)[^\n]*',
    multiLine: true,
  );

  List<String>? _imageListCache;
  int? _wordCountCache;

  // 获取图片列表（带缓存）
  List<String> get imageList {
    final cached = _imageListCache;
    if (cached != null) return cached;

    final raw = images;
    final List<String> result;
    if (raw == null || raw.isEmpty) {
      result = const <String>[];
    } else {
      result = List<String>.unmodifiable(
        raw.split(',').where((path) => path.isNotEmpty),
      );
    }
    _imageListCache = result;
    return result;
  }

  // 计算内容字数（排除纪念日文字，带缓存）
  int get wordCount {
    final cached = _wordCountCache;
    if (cached != null) return cached;

    int count = 0;
    final t = title;
    if (t != null) count += t.length;
    final c = content;
    if (c != null) {
      // 排除纪念日文字
      final userContent = c.replaceAll(_anniversaryPattern, '').trim();
      count += userContent.length;
    }
    _wordCountCache = count;
    return count;
  }

  /// 清除派生缓存。
  ///
  /// 仅用于「极少数就地修改最终字段」的防御路径 —— 正常代码走 `copyWith`
  /// 生成新实例，缓存会自然重算，不需要调这个。
  void invalidateDerivedCache() {
    _imageListCache = null;
    _wordCountCache = null;
  }
}
