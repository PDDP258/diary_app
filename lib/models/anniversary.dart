/// 纪念日类型枚举
enum AnniversaryType { anniversary, countdown }

/// 纪念日/倒数日模型
class Anniversary {
  final int? id;
  final String name; // 事件名称（如：恋爱纪念日、生日）
  final String? subjectName; // 对象名称（如：小明、妈妈），可为空
  final String date; // 日期 yyyy-MM-dd
  final AnniversaryType type; // 纪念日或倒数日
  final String? quote; // 自定义祝福语（可选）
  final DateTime? createdAt;

  Anniversary({
    this.id,
    required this.name,
    this.subjectName,
    required this.date,
    required this.type,
    this.quote,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subject_name': subjectName,
      'date': date,
      'type': type.name, // 存储为字符串
      'quote': quote,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Anniversary.fromMap(Map<String, dynamic> map) {
    return Anniversary(
      id: map['id'] as int?,
      name: map['name'] as String,
      subjectName: map['subject_name'] as String?,
      date: map['date'] as String,
      type: AnniversaryType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AnniversaryType.anniversary,
      ),
      quote: map['quote'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  Anniversary copyWith({
    int? id,
    String? name,
    String? subjectName,
    String? date,
    AnniversaryType? type,
    String? quote,
    DateTime? createdAt,
  }) {
    return Anniversary(
      id: id ?? this.id,
      name: name ?? this.name,
      subjectName: subjectName ?? this.subjectName,
      date: date ?? this.date,
      type: type ?? this.type,
      quote: quote ?? this.quote,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 获取类型显示名称
  String get typeDisplayName {
    return type == AnniversaryType.anniversary ? '纪念日' : '倒数日';
  }

  /// 获取距离今天还有多少天（按日期边界计算，不考虑具体时间）
  int get daysUntil {
    final targetDate = DateTime.parse(date);
    final today = DateTime.now();
    // 统一使用凌晨0点进行计算，确保按整天数计算
    final todayDate = DateTime(today.year, today.month, today.day);
    final targetDateOnly =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    return targetDateOnly.difference(todayDate).inDays;
  }

  /// 获取格式化后的日期字符串
  String get dateStr {
    final dt = DateTime.parse(date);
    return '${dt.year}年${dt.month}月${dt.day}日';
  }

  /// 获取显示名称（对象名字：事件名字）
  String get displayName {
    if (subjectName != null && subjectName!.isNotEmpty) {
      return '$subjectName：$name';
    }
    return name;
  }

  /// 生成纪念日文字
  /// 格式：对象名字：距离事件名字过去了X天（带表情）
  static String generateAnniversaryText(
      Anniversary anniversary, DateTime diaryDate) {
    final targetDate = DateTime.parse(anniversary.date);
    final daysDiff = diaryDate.difference(targetDate).inDays;

    // 获取显示前缀（对象名字：）
    final prefix =
        anniversary.subjectName != null && anniversary.subjectName!.isNotEmpty
            ? '${anniversary.subjectName}：'
            : '';

    // 特殊日子判断
    bool isSpecial = false;
    String specialQuote = '';

    if (daysDiff == 365 || daysDiff == 364) {
      isSpecial = true;
      specialQuote = '💕 一周年纪念！愿时光不老，我们不散。';
    } else if (daysDiff == 730 || daysDiff == 729) {
      isSpecial = true;
      specialQuote = '💕 两周年了！感谢有你相伴的每一天。';
    } else if (daysDiff % 365 == 0 && daysDiff > 0) {
      isSpecial = true;
      specialQuote = '💕 ${daysDiff ~/ 365}周年纪念日，值得铭记的一天！';
    } else if (daysDiff == 30 || daysDiff == 31) {
      isSpecial = true;
      specialQuote = '🌸 一个月了！每一天都因你而精彩。';
    } else if (daysDiff == 100) {
      isSpecial = true;
      specialQuote = '💯 第100天！百年好合，百尺竿头。';
    } else if (daysDiff == 200) {
      isSpecial = true;
      specialQuote = '🎉 第200天！双百临门，好事成双。';
    } else if (daysDiff == 500) {
      isSpecial = true;
      specialQuote = '✨ 第500天！五百次的回眸，换来今生的相遇。';
    } else if (daysDiff == 1000) {
      isSpecial = true;
      specialQuote = '💎 第1000天！千年等一回，珍贵无比。';
    }

    // 如果有自定义祝福语且是特殊日子，使用自定义的
    if (isSpecial &&
        anniversary.quote != null &&
        anniversary.quote!.isNotEmpty) {
      specialQuote = anniversary.quote!;
    }

    // 基础文字格式：对象名字：距离事件名字过去了X天
    final baseText = '$prefix距离${anniversary.name}过去了 $daysDiff 天';

    if (isSpecial) {
      return '🎉 $baseText\n$specialQuote';
    } else {
      return '✨ $baseText';
    }
  }

  /// 生成倒数日文字
  /// 格式：对象名字：距离事件名字还有X天（带表情）
  static String generateCountdownText(
      Anniversary anniversary, DateTime diaryDate) {
    final targetDate = DateTime.parse(anniversary.date);
    // 统一使用日期部分进行计算，忽略具体时间
    final targetDateOnly =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    final diaryDateOnly =
        DateTime(diaryDate.year, diaryDate.month, diaryDate.day);
    final daysLeft = targetDateOnly.difference(diaryDateOnly).inDays;

    // 获取显示前缀（对象名字：）
    final prefix =
        anniversary.subjectName != null && anniversary.subjectName!.isNotEmpty
            ? '${anniversary.subjectName}：'
            : '';

    if (daysLeft < 0) {
      return '📅 $prefix距离${anniversary.name}已经过期 ${-daysLeft} 天';
    } else if (daysLeft == 0) {
      return '🎊 $prefix${anniversary.name}就是今天！\n重要的一天终于到来，祝你一切顺利！';
    }

    // 基础文字
    final baseText = '$prefix距离${anniversary.name}还有 $daysLeft 天';

    // 关键节点提醒（超过100天的倒数日会在这些节点显示特殊提醒）
    String? milestoneQuote;
    bool isMilestone = false;

    if (daysLeft == 100) {
      isMilestone = true;
      milestoneQuote = '💪 百日倒计时开始！百日冲刺，全力以赴！';
    } else if (daysLeft == 50) {
      isMilestone = true;
      milestoneQuote = '🎯 还有50天！halfway there，继续坚持！';
    } else if (daysLeft == 30) {
      isMilestone = true;
      milestoneQuote = '🔥 最后30天！冲刺阶段，加油！';
    } else if (daysLeft == 10) {
      isMilestone = true;
      milestoneQuote = '⏰ 倒计时10天！近在咫尺，做好准备！';
    } else if (daysLeft == 5) {
      isMilestone = true;
      milestoneQuote = '🚀 最后5天！激动人心的时刻即将到来！';
    } else if (daysLeft == 3) {
      isMilestone = true;
      milestoneQuote = '💫 还有3天！期待已久的日子就要到了！';
    } else if (daysLeft == 1) {
      isMilestone = true;
      milestoneQuote = '🌟 就是明天！一切准备就绪，迎接重要时刻！';
    } else if (daysLeft <= 7) {
      // 倒计时7天内（但不是上面的特殊节点）
      return '⏰ $baseText\n紧张又期待，${anniversary.name}即将到来！';
    }

    // 如果有自定义祝福语且是关键节点，优先使用自定义的
    if (isMilestone &&
        anniversary.quote != null &&
        anniversary.quote!.isNotEmpty) {
      milestoneQuote = anniversary.quote!;
    }

    if (isMilestone) {
      return '🎯 $baseText\n$milestoneQuote';
    } else {
      return '📅 $baseText';
    }
  }

  /// 根据类型生成纪念文字
  static String generateText(Anniversary anniversary, DateTime diaryDate) {
    if (anniversary.type == AnniversaryType.anniversary) {
      return generateAnniversaryText(anniversary, diaryDate);
    } else {
      return generateCountdownText(anniversary, diaryDate);
    }
  }

  /// 判断是否触发特殊日子（用于字体加粗）
  static bool isSpecialDay(Anniversary anniversary, DateTime diaryDate) {
    if (anniversary.type != AnniversaryType.anniversary) {
      // 倒数日：关键节点算特殊日子
      final targetDate = DateTime.parse(anniversary.date);
      final daysLeft = targetDate.difference(diaryDate).inDays;

      // 关键节点：100天、50天、30天、10天、5天、3天、1天、当天、7天内
      if (daysLeft < 0) return false; // 已过期不算
      if (daysLeft == 0) return true; // 当天
      if (daysLeft == 1 || daysLeft == 3 || daysLeft == 5 || daysLeft == 10) {
        return true;
      }
      if (daysLeft == 30 || daysLeft == 50 || daysLeft == 100) return true;
      if (daysLeft <= 7) return true; // 7天内
      return false;
    }

    final targetDate = DateTime.parse(anniversary.date);
    final daysDiff = diaryDate.difference(targetDate).inDays;

    // 纪念日特殊日子判断
    if (daysDiff == 365 || daysDiff == 364) return true;
    if (daysDiff == 730 || daysDiff == 729) return true;
    if (daysDiff % 365 == 0 && daysDiff > 0) return true;
    if (daysDiff == 30 || daysDiff == 31) return true;
    if (daysDiff == 100 ||
        daysDiff == 200 ||
        daysDiff == 500 ||
        daysDiff == 1000) {
      return true;
    }
    return false;
  }
}
