import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/self_talk_message.dart';
import '../models/self_talk_task.dart';
import 'database_service.dart';
import 'self_talk_task_parser.dart';

/// 自言自语服务 - 完全独立于日记系统的聊天式快速记录
///
/// 设计原则：
/// 1. 自言自语与日记零耦合，消息不追加到日记正文
/// 2. 删除自言自语不影响日记
/// 3. 只有"我"的消息可触发 AI 任务解析
/// 4. Alter Ego 纯聊天，不触发任何 AI 逻辑
/// 5. AI 开关只控制"是否生成新的系统回复"，不影响已有回复的显示
class SelfTalkService {
  static final Random _random = Random();
  static const String _aiEnabledKey = 'self_talk_ai_enabled';

  /// 获取 AI 对话开关状态
  static Future<bool> getAiEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_aiEnabledKey) ?? true;
  }

  /// 设置 AI 对话开关状态
  static Future<void> setAiEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiEnabledKey, enabled);
  }

  /// 发送一条自言自语消息
  ///
  /// [content] 消息内容
  /// [date] 日期 yyyy-MM-dd
  /// [senderType] 发送者身份：me / alterEgo / system
  ///
  /// 返回保存后的消息（含 id）
  static Future<SelfTalkMessage> sendMessage(
    String content,
    String date, {
    SelfTalkSenderType senderType = SelfTalkSenderType.me,
  }) async {
    final now = DateTime.now();
    final aiEnabled = await getAiEnabled();

    // 保存用户消息（不再关联日记）
    final message = SelfTalkMessage(
      date: date,
      content: content,
      isUser: senderType != SelfTalkSenderType.system,
      senderType: senderType,
      createdAt: now.toIso8601String(),
    );
    final messageId = await DatabaseService.insertSelfTalkMessage(message);

    // "我"和"另一个我"都共享同一个 AI 配置：
    // AI 开启时，发送任何用户消息都会生成系统回复并保存到数据库
    // AI 关闭时，任何消息都不触发 AI 回复
    if (senderType != SelfTalkSenderType.system && aiEnabled) {
      // 使用递增时间戳确保排序稳定（用户消息 + 系统回复按正确顺序排列）
      var replyIndex = 1;
      // 记录被回复的用户类型，系统回复保存在发送者的反方向
      final repliedToType = senderType;

      // 1. 生成聊天式系统回复（如"已记录 ✓"）并保存到数据库
      final chatReply = _generateChatReply(content);
      if (chatReply != null) {
        await DatabaseService.insertSelfTalkMessage(
          SelfTalkMessage(
            date: date,
            content: chatReply,
            isUser: false,
            senderType: SelfTalkSenderType.system,
            repliedToSenderType: repliedToType,
            createdAt: now.add(Duration(milliseconds: replyIndex++)).toIso8601String(),
          ),
        );
      }

      // 2. 解析任务
      final parsedTask = SelfTalkTaskParser.parse(content, date);
      if (parsedTask != null) {
        final task = SelfTalkTask(
          messageId: messageId,
          date: date,
          content: parsedTask.content,
          deadline: parsedTask.deadline,
          createdAt: now.add(Duration(milliseconds: replyIndex++)).toIso8601String(),
        );
        await DatabaseService.insertSelfTalkTask(task);

        // 任务识别系统回复也保存到数据库
        final deadlineText = parsedTask.deadline != null
            ? _formatDeadlineFriendly(parsedTask.deadline!)
            : null;
        final taskReplyContent = deadlineText != null
            ? '✅ 已识别任务：${parsedTask.content}\n⏰ 截止 $deadlineText'
            : '✅ 已识别备忘：${parsedTask.content}';
        await DatabaseService.insertSelfTalkMessage(
          SelfTalkMessage(
            date: date,
            content: taskReplyContent,
            isUser: false,
            senderType: SelfTalkSenderType.system,
            repliedToSenderType: repliedToType,
            createdAt: now.add(Duration(milliseconds: replyIndex++)).toIso8601String(),
          ),
        );
      }
    }

    return message.copyWith(id: messageId);
  }

  /// 获取某天的所有消息
  ///
  /// 规则：直接返回数据库中的消息，不做任何动态生成。
  /// 系统回复在 sendMessage() 时就已经保存到数据库，切换 AI 开关不会影响已有回复的显示。
  static Future<List<SelfTalkMessage>> getMessagesByDate(String date) async {
    final messages = await DatabaseService.getSelfTalkMessagesByDate(date);

    // 如果没有任何消息，返回一条系统欢迎消息
    if (messages.isEmpty) {
      return [
        SelfTalkMessage(
          date: date,
          content: '自言自语模式开启，想说什么都可以~',
          isUser: false,
          senderType: SelfTalkSenderType.system,
          createdAt: '${date}T00:00:00.000',
        ),
      ];
    }

    return messages;
  }

  /// 删除单条消息及其关联任务
  ///
  /// 不再修改日记正文，自言自语完全独立
  static Future<void> deleteMessage(SelfTalkMessage message) async {
    if (message.id != null) {
      await DatabaseService.deleteSelfTalkMessage(message.id!);
      // 级联删除关联的任务
      final tasks = await DatabaseService.getSelfTalkTasksByMessageId(message.id!);
      for (final task in tasks) {
        if (task.id != null) {
          await DatabaseService.deleteSelfTalkTask(task.id!);
        }
      }
    }
  }

  /// 获取某天的所有任务
  static Future<List<SelfTalkTask>> getTasksByDate(String date) async {
    return await DatabaseService.getSelfTalkTasksByDate(date);
  }

  /// 更新任务完成状态
  static Future<void> updateTaskCompletion(SelfTalkTask task, bool isCompleted) async {
    final updated = task.copyWith(isCompleted: isCompleted);
    await DatabaseService.updateSelfTalkTask(updated);
  }

  /// 生成聊天式系统回复
  /// 根据消息内容关键词匹配，返回一条简短的回复
  static String? _generateChatReply(String content) {
    final lower = content.toLowerCase();
    if (lower.contains('累') || lower.contains('困') || lower.contains('烦') || lower.contains('难')) {
      return '辛苦了，给自己一点喘息的时间吧。';
    }
    if (lower.contains('开心') || lower.contains('高兴') || lower.contains('棒') || lower.contains('快乐')) {
      return '捕捉到一份好心情 ✨';
    }
    if (lower.contains('想') || lower.contains('计划') || lower.contains('明天') || lower.contains('准备')) {
      return '把想法写下来，就已经完成了一半。';
    }
    if (lower.contains('害怕') || lower.contains('担心') || lower.contains('焦虑')) {
      return '没关系的，一切都会好起来的。';
    }
    if (lower.contains('谢谢') || lower.contains('感谢')) {
      return '不用谢，我一直都在这里陪着你。';
    }

    final fallbackReplies = [
      '已记录 ✓',
      '我听到了。',
      '记录下来吧，这是属于你的时刻。',
      '想说更多也没关系。',
      '每一句话都值得被记住。',
    ];
    return fallbackReplies[_random.nextInt(fallbackReplies.length)];
  }

  /// 搜索自言自语消息
  ///
  /// [keyword] 内容关键词（模糊匹配）
  /// [dateFrom] 日期范围开始 yyyy-MM-dd
  /// [dateTo] 日期范围结束 yyyy-MM-dd
  /// [senderType] 发送者类型筛选
  static Future<List<SelfTalkMessage>> searchMessages({
    String? keyword,
    String? dateFrom,
    String? dateTo,
    SelfTalkSenderType? senderType,
  }) async {
    return await DatabaseService.searchSelfTalkMessages(
      keyword: keyword,
      dateFrom: dateFrom,
      dateTo: dateTo,
      senderType: senderType?.index,
    );
  }

  /// 按日期范围获取消息
  static Future<List<SelfTalkMessage>> getMessagesByDateRange(
    String dateFrom,
    String dateTo,
  ) async {
    return await DatabaseService.getSelfTalkMessagesByDateRange(dateFrom, dateTo);
  }

  /// 获取所有有自言自语记录的日期
  static Future<List<String>> getRecordedDates() async {
    return await DatabaseService.getSelfTalkDates();
  }

  /// 搜索自言自语任务
  ///
  /// [keyword] 内容关键词（模糊匹配）
  /// [dateFrom] 日期范围开始 yyyy-MM-dd
  /// [dateTo] 日期范围结束 yyyy-MM-dd
  /// [isCompleted] 完成状态筛选
  static Future<List<SelfTalkTask>> searchTasks({
    String? keyword,
    String? dateFrom,
    String? dateTo,
    bool? isCompleted,
  }) async {
    return await DatabaseService.searchSelfTalkTasks(
      keyword: keyword,
      dateFrom: dateFrom,
      dateTo: dateTo,
      isCompleted: isCompleted,
    );
  }

  /// 友好格式化截止时间
  static String _formatDeadlineFriendly(String iso8601) {
    final dt = DateTime.parse(iso8601);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(dt.year, dt.month, dt.day);
    final diff = taskDay.difference(today).inDays;

    String dayPart;
    if (diff == 0) {
      dayPart = '今天';
    } else if (diff == 1) {
      dayPart = '明天';
    } else if (diff == 2) {
      dayPart = '后天';
    } else {
      dayPart = '${dt.month}月${dt.day}日';
    }

    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$dayPart $hour:$minute';
  }
}
