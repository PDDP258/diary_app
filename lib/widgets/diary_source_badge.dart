import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';

/// 日记来源徽标：告诉用户这篇是谁写的。
///
/// 设计取舍：
/// - **本人手写的日记不显示任何东西**。给 99% 的日记都挂一个「我」的标签
///   只会变成噪音，真正需要被看见的是「这篇不是我写的」。
/// - 颜色只从 `AppTheme.schemeOf(context)` 取，跟随主题，不硬编码。
/// - 列表用紧凑版（只有一个短名），详情页用完整版（「麦麦写的」）。
///
/// 用法：
/// ```dart
/// DiarySourceBadge(diary: diary)              // 列表
/// DiarySourceBadge(diary: diary, verbose: true) // 详情
/// ```
class DiarySourceBadge extends StatelessWidget {
  const DiarySourceBadge({
    super.key,
    required this.diary,
    this.verbose = false,
  });

  final Diary diary;

  /// 是否显示完整说法（详情页用）。
  final bool verbose;

  @override
  Widget build(BuildContext context) {
    final source = diary.sourceType;
    // null = 没有标记；self = 本人手写。两种都不需要打扰用户。
    if (source == null || source == DiarySource.self) {
      return const SizedBox.shrink();
    }

    final scheme = AppTheme.schemeOf(context);
    final color = scheme.primaryColor;
    final text = verbose ? source.detailLabel : source.label;
    final fontSize = verbose ? 12.0 : 11.0;

    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: verbose ? 10 : 6,
        vertical: verbose ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(verbose ? 10 : 8),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: verbose ? 13 : 11,
            color: color,
          ),
          SizedBox(width: verbose ? 5 : 3),
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.1,
            ),
          ),
        ],
      ),
    );

    // 徽标本身信息量很小（一个名字），补一句无障碍说明，
    // 免得读屏时只听到「麦麦」两个字不知所云。
    return Semantics(
      label: '来源：${source.detailLabel}',
      child: Tooltip(
        message: '来自${source.label}，经收件箱确认导入',
        child: badge,
      ),
    );
  }
}
