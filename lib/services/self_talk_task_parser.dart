/// 自言自语任务解析结果
class ParsedTask {
  final String content;    // 任务内容
  final String? deadline;  // ISO8601 格式截止时间

  ParsedTask({required this.content, this.deadline});
}

/// 本地规则解析用户输入中的任务/提醒/DLL
class SelfTalkTaskParser {
  static ParsedTask? parse(String input, String baseDate) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final lower = trimmed.toLowerCase();

    // ===== 意图识别 =====
    // 强意图词：明确表达要做某事
    final strongIntents = [
      '提醒', '记得', '别忘了', '不要忘记', '务必', '一定',
      '完成', '去做', '去', '交', '还', '买', '拿', '取',
      '准备', '做', '写', '发', '打', '约', '报名', '预约',
      '开会', '上课', '见', '看', '读', '学', '练', '跑', '吃', '喝',
      '打扫', '整理', '收拾', '清洗', '修理', '安装', '卸载',
      '提交', '上传', '下载', '转发', '回复', '回复邮件', '回电话',
      '付款', '转账', '缴费', '充值', '订票', '订房', '订餐',
      '预约', '挂号', '体检', '复查', '复诊', '换药',
    ];

    // 弱意图词：需要结合时间/语境
    final weakIntents = [
      'ddl', 'deadline', '截止', '到期', '期限', '最后期限',
      'task', 'todo', '待办', '事项', '事情',
    ];

    // DDL 标志词（即使没有动作，也视为任务）
    final ddlMarkers = [
      'ddl', 'deadline', '截止', '到期', '最后期限',
    ];

    // 时间标志词
    final timeMarkers = [
      '今天', '明天', '后天', '大后天', '号', '日', '周', '星期',
      '点', '分', '上午', '下午', '晚上', '早上', '中午', '凌晨',
      '前', '之前', '以后', '之后', '内',
    ];

    final hasStrongIntent = strongIntents.any((kw) => lower.contains(kw));
    final hasWeakIntent = weakIntents.any((kw) => lower.contains(kw));
    final hasDdlMarker = ddlMarkers.any((kw) => lower.contains(kw));
    final hasTimeMarker = timeMarkers.any((kw) => lower.contains(kw));

    // 排除纯情绪/状态表达
    final excludePatterns = [
      RegExp(r'^[我他她它].*(?:是|在|想|觉得|感觉|认为|知道|看到|听到)'),
      RegExp(r'^(今天|明天|昨天).*(?:天气|温度|冷|热|下雨|下雪|晴|阴)'),
      RegExp(r'.*(?:开心|难过|伤心|生气|愤怒|无聊|累|困|烦|焦虑|害怕|担心|失望|兴奋|激动|平静).*极了$'),
      RegExp(r'.*(?:好|太|真|非常|特别|有点|比较).*(?:开心|难过|累|困|烦|无聊|焦虑)$'),
    ];
    final isExcluded = excludePatterns.any((p) => p.hasMatch(trimmed));
    if (isExcluded) return null;

    // 判定是否是任务
    bool isTask = false;
    if (hasDdlMarker) {
      isTask = true;
    } else if (hasStrongIntent) {
      isTask = true;
    } else if (hasWeakIntent && hasTimeMarker) {
      isTask = true;
    } else if (hasTimeMarker && trimmed.length <= 30 && !_isPureMood(trimmed)) {
      // 短句 + 有时间 + 不是纯情绪，也视为备忘
      isTask = true;
    }

    if (!isTask) return null;

    // 提取时间
    final deadline = _extractDeadline(trimmed, baseDate);

    // 提取任务内容
    var taskContent = _extractTaskContent(trimmed);
    if (taskContent.isEmpty || taskContent.length < 2) {
      taskContent = trimmed;
    }

    return ParsedTask(content: taskContent, deadline: deadline);
  }

  /// 判断是否为纯情绪表达
  static bool _isPureMood(String input) {
    final moodWords = [
      '开心', '高兴', '快乐', '兴奋', '激动', '幸福', '满足', '欣慰',
      '难过', '伤心', '悲伤', '痛苦', '失望', '沮丧', '郁闷',
      '生气', '愤怒', '恼火', '烦躁', '焦虑', '紧张', '害怕', '恐惧', '担心',
      '无聊', '空虚', '寂寞', '孤独', '累', '疲惫', '困', '乏',
      '平静', '淡定', '麻木', '无所谓', '迷茫', '困惑',
    ];
    return moodWords.any((w) => input.contains(w)) && input.length < 20;
  }

  /// 从输入中提取截止时间（ISO8601）
  static String? _extractDeadline(String input, String baseDate) {
    final now = DateTime.parse('${baseDate}T00:00:00');
    DateTime? datePart;
    int? hourPart;
    int? minutePart;

    final lower = input.toLowerCase();

    // ===== 日期解析 =====
    if (lower.contains('明天')) {
      datePart = now.add(const Duration(days: 1));
    } else if (lower.contains('后天')) {
      datePart = now.add(const Duration(days: 2));
    } else if (lower.contains('大后天')) {
      datePart = now.add(const Duration(days: 3));
    } else {
      final dayMatch = RegExp(r'(\d+)\s*天后').firstMatch(input);
      if (dayMatch != null) {
        final days = int.parse(dayMatch.group(1)!);
        datePart = now.add(Duration(days: days));
      }
    }

    // 周X / 星期X
    if (datePart == null) {
      final weekMatch = RegExp(r'(?:周|星期)([一二三四五六日天])').firstMatch(input);
      if (weekMatch != null) {
        final weekdayChar = weekMatch.group(1)!;
        final targetWeekday = _chineseWeekdayToNumber(weekdayChar);
        if (targetWeekday != null) {
          final currentWeekday = now.weekday;
          var diff = targetWeekday - currentWeekday;
          if (diff <= 0) diff += 7;
          datePart = now.add(Duration(days: diff));
        }
      }
    }

    // X号
    if (datePart == null) {
      final dayNumMatch = RegExp(r'(\d{1,2})\s*号').firstMatch(input);
      if (dayNumMatch != null) {
        final dayNum = int.parse(dayNumMatch.group(1)!);
        if (dayNum >= 1 && dayNum <= 31) {
          var target = DateTime(now.year, now.month, dayNum);
          if (target.isBefore(now) || target.isAtSameMomentAs(now)) {
            target = DateTime(now.year, now.month + 1, dayNum);
          }
          datePart = target;
        }
      }
    }

    datePart ??= now;

    // ===== 时间解析 =====
    final timePatterns = [
      RegExp(r'下午\s*(\d{1,2})\s*[:：]\s*(\d{1,2})'),
      RegExp(r'下午\s*(\d{1,2})\s*点'),
      RegExp(r'晚上\s*(\d{1,2})\s*[:：]\s*(\d{1,2})'),
      RegExp(r'晚上\s*(\d{1,2})\s*点'),
      RegExp(r'早上\s*(\d{1,2})\s*[:：]\s*(\d{1,2})'),
      RegExp(r'早上\s*(\d{1,2})\s*点'),
      RegExp(r'中午\s*(\d{1,2})\s*[:：]\s*(\d{1,2})'),
      RegExp(r'中午\s*(\d{1,2})\s*点'),
      RegExp(r'凌晨\s*(\d{1,2})\s*[:：]\s*(\d{1,2})'),
      RegExp(r'凌晨\s*(\d{1,2})\s*点'),
      RegExp(r'(\d{1,2})\s*[:：]\s*(\d{1,2})'),
      RegExp(r'(\d{1,2})\s*点\s*(\d{1,2})\s*分'),
      RegExp(r'(\d{1,2})\s*点'),
    ];

    for (final pattern in timePatterns) {
      final match = pattern.firstMatch(input);
      if (match != null) {
        hourPart = int.parse(match.group(1)!);
        minutePart = match.groupCount > 1 && match.group(2) != null
            ? int.parse(match.group(2)!)
            : 0;

        if (input.contains('下午') || input.contains('晚上')) {
          if (hourPart < 12) hourPart += 12;
        }
        break;
      }
    }

    if (hourPart == null) {
      if (lower.contains('前') || lower.contains('之前') || lower.contains('截止') || lower.contains('ddl')) {
        hourPart = 23;
        minutePart = 59;
      } else {
        // 没有时间时返回 null，表示备忘/待办
        return null;
      }
    }

    final result = DateTime(datePart.year, datePart.month, datePart.day, hourPart, minutePart ?? 0);
    return result.toIso8601String();
  }

  /// 提取任务内容，尽量去掉时间描述和引导词
  static String _extractTaskContent(String input) {
    var content = input;

    // 去掉常见引导词
    final prefixes = [
      '提醒我', '记得', '别忘了', '不要忘记', '麻烦你', '请',
    ];
    for (final prefix in prefixes) {
      if (content.startsWith(prefix)) {
        content = content.substring(prefix.length);
        break;
      }
    }

    // 去掉时间状语（简单规则，保留动作核心）
    content = content
        .replaceAll(RegExp(r'明天[早中晚上午下午]*\s*'), '')
        .replaceAll(RegExp(r'后天[早中晚上午下午]*\s*'), '')
        .replaceAll(RegExp(r'大后天[早中晚上午下午]*\s*'), '')
        .replaceAll(RegExp(r'\d+\s*天后[的]*\s*'), '')
        .replaceAll(RegExp(r'(?:周|星期)[一二三四五六日天][的]*\s*'), '')
        .replaceAll(RegExp(r'\d{1,2}\s*号[的]*\s*'), '')
        .replaceAll(RegExp(r'[早中晚上午下午凌晨中午]\s*\d{1,2}\s*[:：]\s*\d{1,2}\s*'), '')
        .replaceAll(RegExp(r'[早中晚上午下午凌晨中午]\s*\d{1,2}\s*点\s*\d{1,2}\s*分\s*'), '')
        .replaceAll(RegExp(r'[早中晚上午下午凌晨中午]\s*\d{1,2}\s*点\s*'), '')
        .replaceAll(RegExp(r'\d{1,2}\s*[:：]\s*\d{1,2}\s*'), '')
        .replaceAll(RegExp(r'\d{1,2}\s*点\s*\d{1,2}\s*分\s*'), '')
        .replaceAll(RegExp(r'\d{1,2}\s*点\s*'), '')
        .replaceAll(RegExp(r'之前\s*'), '')
        .replaceAll(RegExp(r'前\s*'), '')
        .replaceAll(RegExp(r'的时候\s*'), '')
        .trim();

    return content;
  }

  static int? _chineseWeekdayToNumber(String char) {
    const map = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
    };
    return map[char];
  }
}
