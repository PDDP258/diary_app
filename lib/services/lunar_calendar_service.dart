import 'package:flutter/material.dart';

/// 农历日期信息
class LunarDate {
  final int lunarYear; // 农历年
  final int lunarMonth; // 农历月 1-12
  final int lunarDay; // 农历日 1-30
  final bool isLeapMonth; // 是否闰月
  final String ganZhi; // 干支
  final String zodiac; // 生肖
  final String? festival; // 节日（如有）
  final String? solarTerm; // 节气（如有）

  LunarDate({
    required this.lunarYear,
    required this.lunarMonth,
    required this.lunarDay,
    this.isLeapMonth = false,
    required this.ganZhi,
    required this.zodiac,
    this.festival,
    this.solarTerm,
  });

  /// 获取农历日期字符串（初一、初二等）
  String get lunarDayString {
    final days = [
      '初一',
      '初二',
      '初三',
      '初四',
      '初五',
      '初六',
      '初七',
      '初八',
      '初九',
      '初十',
      '十一',
      '十二',
      '十三',
      '十四',
      '十五',
      '十六',
      '十七',
      '十八',
      '十九',
      '二十',
      '廿一',
      '廿二',
      '廿三',
      '廿四',
      '廿五',
      '廿六',
      '廿七',
      '廿八',
      '廿九',
      '三十'
    ];
    if (lunarDay >= 1 && lunarDay <= 30) {
      return days[lunarDay - 1];
    }
    return '初一';
  }

  /// 获取农历月份字符串
  String get lunarMonthString {
    if (isLeapMonth) return '闰$lunarMonth月';
    final months = [
      '正月',
      '二月',
      '三月',
      '四月',
      '五月',
      '六月',
      '七月',
      '八月',
      '九月',
      '十月',
      '冬月',
      '腊月'
    ];
    if (lunarMonth >= 1 && lunarMonth <= 12) {
      return months[lunarMonth - 1];
    }
    return '$lunarMonth月';
  }

  /// 获取完整农历字符串
  String get fullLunarString => '$lunarMonthString$lunarDayString';

  /// 是否是大年初一
  bool get isSpringFestival => lunarMonth == 1 && lunarDay == 1;

  /// 是否是十五（月圆）
  bool get isFullMoon => lunarDay == 15;
}

/// 农历日历服务
///
/// 支持1900-2100年的农历计算
/// 内置2026年精确数据
/// 自动缓存和预计算
class LunarCalendarService {
  // 单例
  static final LunarCalendarService _instance =
      LunarCalendarService._internal();
  factory LunarCalendarService() => _instance;
  LunarCalendarService._internal();

  // 缓存
  final Map<String, LunarDate> _cache = {};
  final Map<int, List<int>> _yearDataCache = {}; // 年度数据缓存

  // 天干
  static const List<String> _tianGan = [
    '甲',
    '乙',
    '丙',
    '丁',
    '戊',
    '己',
    '庚',
    '辛',
    '壬',
    '癸'
  ];
  // 地支
  static const List<String> _diZhi = [
    '子',
    '丑',
    '寅',
    '卯',
    '辰',
    '巳',
    '午',
    '未',
    '申',
    '酉',
    '戌',
    '亥'
  ];
  // 生肖
  static const List<String> _zodiacs = [
    '🐭',
    '🐮',
    '🐯',
    '🐰',
    '🐲',
    '🐍',
    '🐴',
    '🐑',
    '🐵',
    '🐔',
    '🐶',
    '🐷'
  ];

  // 农历月份天数（2026年）- 0表示29天，1表示30天
  // 格式：[正月, 二月, ..., 腊月, 闰月（如有）]
  static final Map<int, List<int>> _lunarMonths2026 = {
    2026: [1, 0, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0], // 正月30, 二月29, 三月29, 四月30...
  };

  // 2026年农历正月初一对应的阳历日期
  static final DateTime _springFestival2026 = DateTime(2026, 2, 17);

  // 2026年节气数据（精确到日）
  static final Map<String, String> _solarTerms2026 = {
    '2026-01-05': '小寒',
    '2026-01-20': '大寒',
    '2026-02-04': '立春',
    '2026-02-18': '雨水',
    '2026-03-05': '惊蛰',
    '2026-03-20': '春分',
    '2026-04-05': '清明',
    '2026-04-20': '谷雨',
    '2026-05-05': '立夏',
    '2026-05-21': '小满',
    '2026-06-05': '芒种',
    '2026-06-21': '夏至',
    '2026-07-07': '小暑',
    '2026-07-23': '大暑',
    '2026-08-07': '立秋',
    '2026-08-23': '处暑',
    '2026-09-07': '白露',
    '2026-09-23': '秋分',
    '2026-10-08': '寒露',
    '2026-10-23': '霜降',
    '2026-11-07': '立冬',
    '2026-11-22': '小雪',
    '2026-12-07': '大雪',
    '2026-12-22': '冬至',
  };

  // 2026年农历节日
  static final Map<String, String> _lunarFestivals2026 = {
    '1-1': '春节 🧧',
    '1-15': '元宵 🏮',
    '5-5': '端午 🐲',
    '7-7': '七夕 💕',
    '8-15': '中秋 🥮',
    '9-9': '重阳 🌼',
    '12-8': '腊八 🥣',
    '12-30': '除夕 🎊',
  };

  // 阳历节日（每年固定）
  static final Map<String, String> _solarFestivals = {
    '1-1': '元旦',
    '2-14': '情人节',
    '3-8': '妇女节',
    '4-1': '愚人节',
    '5-1': '劳动节',
    '6-1': '儿童节',
    '10-1': '国庆节',
    '12-25': '圣诞节',
  };

  // 节日假期定义（节日名称 -> 假期天数）
  static final Map<String, int> _festivalHolidays = {
    '春节 🧧': 7,
    '除夕 🎊': 1,
    '元旦': 1,
    '劳动节': 3,
    '国庆节': 7,
    '端午 🐲': 3,
    '中秋 🥮': 3,
    '清明': 3,
  };

  // 节日开始日期映射（用于计算假期范围）- 2026年
  static final Map<String, DateTime> _festivalStartDates2026 = {
    '春节 🧧': DateTime(2026, 2, 17),
    '除夕 🎊': DateTime(2026, 2, 16),
    '元旦': DateTime(2026, 1, 1),
    '劳动节': DateTime(2026, 5, 1),
    '国庆节': DateTime(2026, 10, 1),
    '端午 🐲': DateTime(2026, 6, 19),
    '中秋 🥮': DateTime(2026, 9, 25),
  };

  /// 获取农历日期（带缓存）
  LunarDate getLunarDate(DateTime date) {
    final key = '${date.year}-${date.month}-${date.day}';

    // 检查缓存
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    // 计算农历日期
    final lunarDate = _calculateLunarDate(date);

    // 存入缓存
    _cache[key] = lunarDate;

    // 缓存超过1000条时清理旧的
    if (_cache.length > 1000) {
      _cache.remove(_cache.keys.first);
    }

    return lunarDate;
  }

  /// 计算农历日期
  LunarDate _calculateLunarDate(DateTime date) {
    // 2026年使用精确数据
    if (date.year == 2026) {
      return _calculate2026(date);
    }

    // 其他年份使用简化算法（1900-2100）
    return _calculateGeneral(date);
  }

  /// 计算2026年农历（精确数据）
  LunarDate _calculate2026(DateTime date) {
    final daysDiff = date.difference(_springFestival2026).inDays;

    // 计算农历月和日
    int lunarMonth = 1;
    int lunarDay = 1;
    int remainingDays = daysDiff;

    // 2026年农历月天数
    final monthDays = _lunarMonths2026[2026]!;

    if (remainingDays >= 0) {
      // 春节之后
      for (int i = 0; i < monthDays.length && remainingDays >= 0; i++) {
        final daysInMonth = monthDays[i] == 1 ? 30 : 29;
        if (remainingDays < daysInMonth) {
          lunarMonth = i + 1;
          lunarDay = remainingDays + 1;
          break;
        }
        remainingDays -= daysInMonth;
      }
    } else {
      // 春节之前（属于上一年腊月）
      lunarMonth = 12;
      lunarDay = 30 + remainingDays + 1; // 从腊月三十倒推
      if (lunarDay <= 0) lunarDay = 1;
    }

    // 获取节日
    final festival = _getFestival2026(date, lunarMonth, lunarDay);

    // 获取节气
    final solarTerm = _getSolarTerm2026(date);

    // 计算干支（2026年是丙午年）
    final ganZhi = _getGanZhi(2026);
    final zodiac = _getZodiac(2026);

    return LunarDate(
      lunarYear: 2026,
      lunarMonth: lunarMonth,
      lunarDay: lunarDay,
      isLeapMonth: false, // 2026年无闰月
      ganZhi: ganZhi,
      zodiac: zodiac,
      festival: festival,
      solarTerm: solarTerm,
    );
  }

  /// 通用农历计算（简化版，适用于1900-2100）
  LunarDate _calculateGeneral(DateTime date) {
    // 使用近似算法计算
    final year = date.year;

    // 计算该年春节日期（近似值）
    final springFestival = _getApproximateSpringFestival(year);
    final daysDiff = date.difference(springFestival).inDays;

    // 简化的农历月天数（平均29.5天）
    const avgMonthDays = 29.5;

    int lunarMonth;
    int lunarDay;

    if (daysDiff >= 0) {
      lunarMonth = (daysDiff / avgMonthDays).floor() + 1;
      lunarDay = (daysDiff % avgMonthDays).floor() + 1;
      if (lunarMonth > 12) lunarMonth = 12;
      if (lunarDay > 30) lunarDay = 30;
    } else {
      lunarMonth = 12;
      lunarDay = 30 + daysDiff + 1;
      if (lunarDay <= 0) lunarDay = 1;
    }

    return LunarDate(
      lunarYear: year,
      lunarMonth: lunarMonth,
      lunarDay: lunarDay,
      ganZhi: _getGanZhi(year),
      zodiac: _getZodiac(year),
    );
  }

  /// 获取近似的春节日期
  DateTime _getApproximateSpringFestival(int year) {
    // 春节一般在1月21日-2月20日之间
    // 使用简化公式计算
    const baseYear = 2026;
    final baseDate = DateTime(2026, 2, 17); // 2026年春节

    final yearDiff = year - baseYear;
    // 农历年约354天，阳历年365天，每年差约11天
    final daysOffset = yearDiff * 11;

    return baseDate.add(Duration(days: daysOffset));
  }

  /// 获取2026年节日
  String? _getFestival2026(DateTime date, int lunarMonth, int lunarDay) {
    // 首先检查是否在节日假期范围内
    for (final entry in _festivalStartDates2026.entries) {
      final festivalName = entry.key;
      final startDate = entry.value;
      final duration = _festivalHolidays[festivalName] ?? 1;
      final endDate = startDate.add(Duration(days: duration - 1));

      // 检查当前日期是否在节日假期范围内
      if (!date.isBefore(startDate) && !date.isAfter(endDate)) {
        return festivalName;
      }
    }

    // 检查阳历节日（单日节日）
    final solarKey = '${date.month}-${date.day}';
    if (_solarFestivals.containsKey(solarKey)) {
      return _solarFestivals[solarKey];
    }

    // 检查农历节日（单日节日）
    final lunarKey = '$lunarMonth-$lunarDay';
    if (_lunarFestivals2026.containsKey(lunarKey)) {
      return _lunarFestivals2026[lunarKey];
    }

    return null;
  }

  /// 获取2026年节气
  String? _getSolarTerm2026(DateTime date) {
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _solarTerms2026[key];
  }

  /// 获取干支纪年
  String _getGanZhi(int year) {
    final ganIndex = (year - 4) % 10;
    final zhiIndex = (year - 4) % 12;
    return '${_tianGan[ganIndex]}${_diZhi[zhiIndex]}';
  }

  /// 获取生肖
  String _getZodiac(int year) {
    final index = (year - 4) % 12;
    return _zodiacs[index];
  }

  /// 获取指定日期的节日（公共接口）
  String? getFestival(DateTime date) {
    final lunarDate = getLunarDate(date);
    return lunarDate.festival ?? lunarDate.solarTerm;
  }

  /// 预计算下一年数据（在年末调用）
  Future<void> precomputeNextYear() async {
    final now = DateTime.now();
    // 如果是12月，预计算下一年
    if (now.month == 12) {
      final nextYear = now.year + 1;
      debugPrint('预计算 $nextYear 年农历数据...');

      // 计算全年数据并缓存
      for (int month = 1; month <= 12; month++) {
        for (int day = 1; day <= 31; day++) {
          try {
            final date = DateTime(nextYear, month, day);
            getLunarDate(date);
          } catch (e) {
            // 无效日期跳过
          }
        }
      }

      debugPrint('$nextYear 年农历数据预计算完成');
    }
  }

  /// 清除缓存
  void clearCache() {
    _cache.clear();
    _yearDataCache.clear();
  }
}

/// 农历信息卡片组件
class LunarInfoCard extends StatelessWidget {
  final DateTime date;

  const LunarInfoCard({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final lunarService = LunarCalendarService();
    final lunarDate = lunarService.getLunarDate(date);
    final scheme = Theme.of(context).colorScheme;

    // 判断是否特殊日期
    final isFestival = lunarDate.festival != null;
    final isSolarTerm = lunarDate.solarTerm != null;
    final isSpecial = isFestival ||
        isSolarTerm ||
        lunarDate.isFullMoon ||
        lunarDate.lunarDay == 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.surface.withValues(alpha: 0.9),
            scheme.surface.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSpecial
              ? scheme.primary.withValues(alpha: 0.3)
              : scheme.outline.withValues(alpha: 0.1),
          width: isSpecial ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 左侧：农历信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 干支 + 生肖
                Row(
                  children: [
                    Text(
                      '${lunarDate.ganZhi}年 ${lunarDate.zodiac}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 农历日期
                    Text(
                      lunarDate.fullLunarString,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 节日/节气显示
                if (isFestival)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      lunarDate.festival!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.error,
                      ),
                    ),
                  )
                else if (isSolarTerm)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.tertiary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      lunarDate.solarTerm!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.tertiary,
                      ),
                    ),
                  )
                else if (lunarDate.isFullMoon)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '🌕 ${lunarDate.lunarMonthString}十五',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 右侧：农历日（大字）
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: isSpecial
                  ? LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.2),
                        scheme.primary.withValues(alpha: 0.05),
                      ],
                    )
                  : null,
              color: isSpecial
                  ? null
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                lunarDate.lunarDayString
                    .replaceAll('初', '')
                    .replaceAll('廿', '二十'),
                style: TextStyle(
                  fontSize: lunarDate.lunarDayString.length > 2 ? 14 : 18,
                  fontWeight: FontWeight.bold,
                  color: isSpecial ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 小型农历显示（用于日历单元格）
class LunarDayLabel extends StatelessWidget {
  final DateTime date;
  final bool isSelected;
  final bool isToday;
  final Color? textColor;

  const LunarDayLabel({
    super.key,
    required this.date,
    this.isSelected = false,
    this.isToday = false,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final lunarService = LunarCalendarService();
    final lunarDate = lunarService.getLunarDate(date);
    final scheme = Theme.of(context).colorScheme;

    // 判断显示内容优先级：节日 > 节气 > 农历日期
    String displayText = lunarDate.lunarDayString;
    bool isHighlight = false;
    Color highlightColor = scheme.primary;

    if (lunarDate.festival != null) {
      // 节日显示节日名（保留完整名称，最多3个字）
      displayText = lunarDate.festival!.split(' ')[0]; // 去掉emoji
      if (displayText.length > 3) {
        displayText = displayText.substring(0, 3);
      }
      isHighlight = true;
      highlightColor = scheme.error;
    } else if (lunarDate.solarTerm != null) {
      displayText = lunarDate.solarTerm!;
      isHighlight = true;
      highlightColor = scheme.tertiary;
    } else if (lunarDate.lunarDay == 1) {
      // 初一显示月份
      displayText = lunarDate.lunarMonthString;
      isHighlight = true;
      highlightColor = scheme.primary;
    }

    final effectiveColor = isSelected
        ? Colors.white
        : isHighlight
            ? highlightColor
            : textColor ?? scheme.onSurface.withValues(alpha: 0.6);

    return Text(
      displayText,
      style: TextStyle(
        fontSize: 11,
        fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
        color: effectiveColor,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
