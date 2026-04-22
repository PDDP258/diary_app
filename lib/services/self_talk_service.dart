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
    final now = DateTime.now().toIso8601String();
    final aiEnabled = await getAiEnabled();

    // 保存消息（不再关联日记）
    final message = SelfTalkMessage(
      date: date,
      content: content,
      isUser: senderType != SelfTalkSenderType.system,
      senderType: senderType,
      createdAt: now,
    );
    final messageId = await DatabaseService.insertSelfTalkMessage(message);

    // 只有"我"发的消息，且 AI 开启时，才解析任务并生成系统反馈
    if (senderType == SelfTalkSenderType.me && aiEnabled) {
      final parsedTask = SelfTalkTaskParser.parse(content, date);
      if (parsedTask != null) {
        final task = SelfTalkTask(
          messageId: messageId,
          date: date,
          content: parsedTask.content,
          deadline: parsedTask.deadline,
          createdAt: now,
        );
        await DatabaseService.insertSelfTalkTask(task);

        // 插入系统反馈消息
        final deadlineText = parsedTask.deadline != null
            ? _formatDeadlineFriendly(parsedTask.deadline!)
            : null;
        final replyContent = deadlineText != null
            ? '✅ 已识别任务：${parsedTask.content}\n⏰ 截止 $deadlineText'
            : '✅ 已识别备忘：${parsedTask.content}';
        await DatabaseService.insertSelfTalkMessage(
          SelfTalkMessage(
            date: date,
            content: replyContent,
            isUser: false,
            senderType: SelfTalkSenderType.system,
            createdAt: now,
          ),
        );
      }
    }

    return message.copyWith(id: messageId);
  }

  /// 获取某天的所有消息
  /// 
  /// 规则：
  /// - AI 开启时：为"我"的消息动态插入系统聊天回复（纯展示，不存库）
  /// - AI 关闭时：只返回数据库中实际存在的消息，没有任何自动回复
  /// - Alter Ego 消息永远不触发任何系统回复
  static Future<List<SelfTalkMessage>> getMessagesByDate(String date) async {
    final messages = await DatabaseService.getSelfTalkMessagesByDate(date);
    final aiEnabled = await getAiEnabled();

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

    // AI 关闭时：直接返回原始消息，不添加任何动态回复
    if (!aiEnabled) {
      return messages;
    }

    // AI 开启时：只在"我"的消息后动态插入系统聊天回复
    final result = <SelfTalkMessage>[];
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      result.add(msg);
      // 只有"我"的消息才生成动态回复；Alter Ego 和 System 都不生成
      if (msg.senderType == SelfTalkSenderType.me) {
        // 如果下一条已经是系统回复（数据库中已存在，如任务识别回复），则不再自动生成
        if (i + 1 < messages.length && messages[i + 1].senderType == SelfTalkSenderType.system) {
          continue;
        }
        final reply = _generateReply(messages.sublist(0, i + 1), msg.content);
        result.add(
          SelfTalkMessage(
            date: date,
            content: reply,
            isUser: false,
            senderType: SelfTalkSenderType.system,
            createdAt: msg.createdAt,
          ),
        );
      }
    }

    return result;
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

  /// 生成系统回复
  static String _generateReply(List<SelfTalkMessage> history, String latestContent) {
    final userMessages = history.where((m) => m.senderType == SelfTalkSenderType.me).toList();
    final count = userMessages.length;

    final lower = latestContent.toLowerCase();
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

    if (count == 1) {
      return '已记录 ✓';
    }
    if (count == 3) {
      return '今天思绪很活跃呢';
    }
    if (count >= 5 && count % 5 == 0) {
      return '已经记录了 $count 条，你在认真生活。';
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
}
