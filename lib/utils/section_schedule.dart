import '../models/course.dart';

/// 节次作息工具：夏/冬季预设 + 固定课时联动调整
///
/// 固定课时模式核心规则（用户反馈驱动）：
/// - 修改某节上课时间 → 下课时间 = 上课 + 课时时长
/// - 后续所有非自定义节次自动顺延，**保持原有课间间隔**
/// - 标记 isCustom 的节次不参与联动，可单独设置时间
class SectionSchedule {
  /// 夏季作息（默认）：上午 8:00-11:50（9:40 后 30 分钟大课间），
  /// 下午 14:30-18:10（16:10 后 20 分钟大课间），晚上 19:30-21:05（课间 5 分钟）
  static const summer = <SectionTime>[
    SectionTime(section: 1, startTime: '08:00', endTime: '08:45'),
    SectionTime(section: 2, startTime: '08:55', endTime: '09:40'),
    SectionTime(section: 3, startTime: '10:10', endTime: '10:55'),
    SectionTime(section: 4, startTime: '11:05', endTime: '11:50'),
    SectionTime(section: 5, startTime: '14:30', endTime: '15:15'),
    SectionTime(section: 6, startTime: '15:25', endTime: '16:10'),
    SectionTime(section: 7, startTime: '16:30', endTime: '17:15'),
    SectionTime(section: 8, startTime: '17:25', endTime: '18:10'),
    SectionTime(section: 9, startTime: '19:30', endTime: '20:15'),
    SectionTime(section: 10, startTime: '20:20', endTime: '21:05'),
  ];

  /// 冬季作息：上午不变，下午提前半小时（14:00-17:40），晚上 19:00-21:25（3 节）
  static const winter = <SectionTime>[
    SectionTime(section: 1, startTime: '08:00', endTime: '08:45'),
    SectionTime(section: 2, startTime: '08:55', endTime: '09:40'),
    SectionTime(section: 3, startTime: '10:10', endTime: '10:55'),
    SectionTime(section: 4, startTime: '11:05', endTime: '11:50'),
    SectionTime(section: 5, startTime: '14:00', endTime: '14:45'),
    SectionTime(section: 6, startTime: '14:55', endTime: '15:40'),
    SectionTime(section: 7, startTime: '16:00', endTime: '16:45'),
    SectionTime(section: 8, startTime: '16:55', endTime: '17:40'),
    SectionTime(section: 9, startTime: '19:00', endTime: '19:45'),
    SectionTime(section: 10, startTime: '19:50', endTime: '20:35'),
    SectionTime(section: 11, startTime: '20:40', endTime: '21:25'),
  ];

  static int toMinutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  static String toTime(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// 固定课时模式下修改 [index] 节的上课时间，联动调整后续节次。
  /// 课间间隔取修改前相邻两节的差值；isCustom 节次保持不动。
  static List<SectionTime> cascadeFrom(
    List<SectionTime> sections,
    int index,
    String newStart,
    int classMinutes,
  ) {
    final old = List.of(sections);
    final result = List.of(sections);

    // 记录修改前的课间间隔（第 i 节上课 - 第 i-1 节下课）
    final gaps = List<int>.generate(old.length, (i) {
      if (i == 0) return 0;
      return toMinutes(old[i].startTime) - toMinutes(old[i - 1].endTime);
    });

    // 应用本次修改
    result[index] = SectionTime(
      section: old[index].section,
      startTime: newStart,
      endTime: toTime(toMinutes(newStart) + classMinutes),
      isCustom: old[index].isCustom,
    );

    // 后续非自定义节次按原间隔顺延
    for (var j = index + 1; j < result.length; j++) {
      if (result[j].isCustom) continue;
      final start = toMinutes(result[j - 1].endTime) + gaps[j];
      result[j] = SectionTime(
        section: result[j].section,
        startTime: toTime(start),
        endTime: toTime(start + classMinutes),
        isCustom: false,
      );
    }
    return result;
  }

  /// 修改课时时长：所有非自定义节次下课时间 = 上课 + 时长，并保持间隔顺延
  static List<SectionTime> applyDuration(
      List<SectionTime> sections, int classMinutes) {
    if (sections.isEmpty) return sections;
    return cascadeFrom(sections, 0, sections.first.startTime, classMinutes);
  }

  /// 追加一节（固定课时模式：紧接上一节，间隔 10 分钟）
  static SectionTime nextAfter(SectionTime last, int classMinutes) {
    final start = toMinutes(last.endTime) + 10;
    return SectionTime(
      section: last.section + 1,
      startTime: toTime(start),
      endTime: toTime(start + classMinutes),
    );
  }
}
