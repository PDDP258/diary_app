import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../models/self_talk_message.dart';
import '../models/self_talk_task.dart';
import '../services/self_talk_service.dart';
import '../widgets/glass_panel.dart';
import '../widgets/code_comment.dart';
import '../services/sound_service.dart';
import '../widgets/smart_notifications.dart';

/// 自言自语页面
/// 
/// 交互规则：
/// - "我"发送 → 消息在右边，主色气泡
/// - "另一个我"发送 → 消息在左边，紫色气泡，带 🧠 头像
/// - 系统回复 → 在发送者的反方向
///   - 回复"我" → 左边
///   - 回复"另一个我" → 右边
/// - AI 开关 → 控制之后是否生成新的系统回复，不影响已有历史
class SelfTalkScreen extends StatefulWidget {
  final String? initialDate;

  const SelfTalkScreen({super.key, this.initialDate});

  @override
  State<SelfTalkScreen> createState() => _SelfTalkScreenState();
}

class _SelfTalkScreenState extends State<SelfTalkScreen> {
  late DateTime _selectedDate;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<SelfTalkMessage> _messages = [];
  List<SelfTalkTask> _tasks = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _aiEnabled = true;
  SelfTalkSenderType _senderType = SelfTalkSenderType.me;
  static const String _senderTypeKey = 'self_talk_sender_type';

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate != null
        ? DateTime.parse(widget.initialDate!)
        : DateTime.now();
    _loadAiSetting();
    _loadPersistedSenderType();
    _loadMessages();
  }

  Future<void> _loadPersistedSenderType() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_senderTypeKey);
    if (savedIndex != null &&
        savedIndex >= 0 &&
        savedIndex < SelfTalkSenderType.values.length) {
      if (mounted) {
        setState(() => _senderType = SelfTalkSenderType.values[savedIndex]);
      }
    }
  }

  Future<void> _persistSenderType(SelfTalkSenderType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_senderTypeKey, type.index);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  Future<void> _loadAiSetting() async {
    final enabled = await SelfTalkService.getAiEnabled();
    if (mounted) {
      setState(() => _aiEnabled = enabled);
    }
  }

  Future<void> _toggleAi() async {
    final newValue = !_aiEnabled;
    await SelfTalkService.setAiEnabled(newValue);
    setState(() => _aiEnabled = newValue);
    HapticFeedback.lightImpact();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final messages = await SelfTalkService.getMessagesByDate(_dateStr);
    final tasks = await SelfTalkService.getTasksByDate(_dateStr);
    if (mounted) {
      setState(() {
        _messages = messages;
        _tasks = tasks;
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({SelfTalkSenderType? explicitSenderType}) async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    HapticFeedback.lightImpact();

    // 三重保障：
    // 1. 优先使用显式传入的 senderType（按钮闭包捕获）
    // 2. 回退到持久化的 senderType（SharedPreferences）
    // 3. 最后回退到实例变量
    SelfTalkSenderType currentSenderType;
    if (explicitSenderType != null) {
      currentSenderType = explicitSenderType;
    } else {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_senderTypeKey);
      if (savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < SelfTalkSenderType.values.length) {
        currentSenderType = SelfTalkSenderType.values[savedIndex];
      } else {
        currentSenderType = _senderType;
      }
    }

    final sentMessage = await SelfTalkService.sendMessage(
      text,
      _dateStr,
      senderType: currentSenderType,
    );
    _inputController.clear();

    await _loadMessages();

    // 任务检测通知（"我"和"另一个我"都能触发）
    if (sentMessage.senderType != SelfTalkSenderType.system &&
        _aiEnabled &&
        sentMessage.id != null) {
      final detectedTasks =
          _tasks.where((t) => t.messageId == sentMessage.id).toList();
      if (detectedTasks.isNotEmpty) {
        await SoundService.playSuccess();
        await HapticFeedback.heavyImpact();
        if (mounted) {
          final task = detectedTasks.first;
          final taskDesc = task.deadline != null
              ? '已识别任务「${task.content}」'
              : '已识别备忘「${task.content}」';
          ToastManager().show(
            context,
            message: taskDesc,
            type: ToastType.success,
            duration: const Duration(seconds: 4),
          );
        }
      }
    }

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  Future<void> _deleteMessage(SelfTalkMessage message) async {
    if (!message.isUser) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = AppTheme.schemeOf(context);
        return AlertDialog(
          backgroundColor: scheme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('删除这条记录？', style: TextStyle(color: scheme.textDarkColor)),
          content: Text(
            '删除后不可恢复，确定吗？',
            style: TextStyle(color: scheme.textMediumColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消', style: TextStyle(color: scheme.textLightColor)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('删除', style: TextStyle(color: scheme.errorColor)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await SelfTalkService.deleteMessage(message);
      await _loadMessages();
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadMessages();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: now,
      builder: (context, child) {
        final scheme = AppTheme.schemeOf(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: scheme.primaryColor,
              onPrimary: Colors.white,
              surface: scheme.cardColor,
              onSurface: scheme.textDarkColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadMessages();
    }
  }

  /// 找到系统回复前最近的一条用户消息，用于判断回复位置
  SelfTalkMessage? _findRepliedUserMessage(int systemIndex) {
    for (int i = systemIndex - 1; i >= 0; i--) {
      if (_messages[i].senderType != SelfTalkSenderType.system) {
        return _messages[i];
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final isToday = _dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left, color: scheme.textMediumColor),
              onPressed: () => _changeDate(-1),
            ),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.lightColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isToday ? '今天' : _dateStr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right, color: scheme.textMediumColor),
              onPressed: isToday ? null : () => _changeDate(1),
            ),
          ],
        ),
        actions: [
          _buildAiToggle(scheme),
          const SizedBox(width: 8),
        ],
        iconTheme: IconThemeData(color: scheme.textDarkColor),
      ),
      body: Column(
        children: [
          // 当前身份状态指示器
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: _senderType == SelfTalkSenderType.me
                ? scheme.primaryColor.withValues(alpha: 0.08)
                : const Color(0xFF7C4DFF).withValues(alpha: 0.08),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _senderType == SelfTalkSenderType.me
                          ? Icons.person_outline
                          : Icons.psychology_outlined,
                      size: 14,
                      color: _senderType == SelfTalkSenderType.me
                          ? scheme.primaryColor
                          : const Color(0xFF7C4DFF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _senderType == SelfTalkSenderType.me ? '当前身份：我（消息在右边）' : '当前身份：另一个我（消息在左边）',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _senderType == SelfTalkSenderType.me
                            ? scheme.primaryColor
                            : const Color(0xFF7C4DFF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: scheme.primaryColor))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final msgTasks = msg.id != null
                          ? _tasks.where((t) => t.messageId == msg.id).toList()
                          : <SelfTalkTask>[];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMessageBubble(index, msg, scheme),
                          ...msgTasks.map((task) => _buildTaskCard(task, scheme, msg.senderType)),
                        ],
                      );
                    },
                  ),
          ),
          _buildInputArea(scheme),
        ],
      ),
    );
  }

  Widget _buildAiToggle(ThemeScheme scheme) {
    return GestureDetector(
      onTap: _toggleAi,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _aiEnabled
              ? scheme.primaryColor.withValues(alpha: 0.12)
              : scheme.dividerColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _aiEnabled
                ? scheme.primaryColor.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                _aiEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                key: ValueKey(_aiEnabled),
                size: 16,
                color: _aiEnabled ? scheme.primaryColor : scheme.textLightColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _aiEnabled ? 'AI 开' : 'AI 关',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _aiEnabled ? scheme.primaryColor : scheme.textLightColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 核心：消息气泡构建
  /// 规则：
  /// - me → 右边，主色
  /// - alterEgo → 左边，紫色，带 🧠 头像和标签
  /// - system → 反方向（回复 me 在左边，回复 alterEgo 在右边），灰色
  Widget _buildMessageBubble(int index, SelfTalkMessage message, ThemeScheme scheme) {
    final time = DateFormat('HH:mm').format(DateTime.parse(message.createdAt));

    // 判断对齐方向
    final bool isRight;
    final Color bgColor;
    final Color borderColor;
    final String? label;
    final String? avatar;

    switch (message.senderType) {
      case SelfTalkSenderType.me:
        isRight = true;
        bgColor = scheme.primaryColor.withValues(alpha: 0.15);
        borderColor = scheme.primaryColor.withValues(alpha: 0.35);
        label = null;
        avatar = null;
        break;
      case SelfTalkSenderType.alterEgo:
        isRight = false;
        bgColor = const Color(0xFF7C4DFF).withValues(alpha: 0.12);
        borderColor = const Color(0xFF7C4DFF).withValues(alpha: 0.40);
        label = '另一个我';
        avatar = '🧠';
        break;
      case SelfTalkSenderType.system:
        // 系统回复在发送者的反方向
        // 优先使用 repliedToSenderType（可靠），回退到回溯查找
        final repliedType = message.repliedToSenderType ?? _findRepliedUserMessage(index)?.senderType;
        if (repliedType == SelfTalkSenderType.alterEgo) {
          isRight = true; // 回复 alterEgo → 显示在右边
        } else {
          isRight = false; // 回复 me 或找不到 → 显示在左边
        }
        bgColor = scheme.surfaceColor;
        borderColor = scheme.dividerColor;
        label = null;
        avatar = '📝';
        break;
    }

    final bubbleContent = GestureDetector(
      onLongPress: message.isUser ? () => _deleteMessage(message) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isRight ? 16 : 4),
            bottomRight: Radius.circular(isRight ? 4 : 16),
          ),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment:
              isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7C4DFF),
                  ),
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                fontSize: 15,
                color: scheme.textDarkColor,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time,
              style: TextStyle(
                fontSize: 11,
                color: scheme.textMediumColor,
              ),
            ),
          ],
        ),
      ),
    );

    if (avatar != null) {
      // 带头像的消息：使用 Row 精确控制对齐
      final avatarWidget = Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Text(avatar, style: const TextStyle(fontSize: 16)),
        ),
      );

      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(
          mainAxisAlignment: isRight ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: isRight
              ? [
                  Flexible(child: bubbleContent),
                  const SizedBox(width: 8),
                  avatarWidget,
                  const SizedBox(width: 48),
                ]
              : [
                  const SizedBox(width: 8),
                  avatarWidget,
                  const SizedBox(width: 8),
                  Flexible(child: bubbleContent),
                  const SizedBox(width: 48),
                ],
        ),
      );
    } else {
      // 无头像的消息（me）：直接用 Row 推到右边
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(child: bubbleContent),
            const SizedBox(width: 8),
          ],
        ),
      );
    }
  }

  Widget _buildTaskCard(SelfTalkTask task, ThemeScheme scheme, SelfTalkSenderType messageSenderType) {
    final hasDeadline = task.deadline != null;
    final deadlineText = hasDeadline
        ? DateFormat('MM/dd HH:mm').format(DateTime.parse(task.deadline!))
        : '备忘';
    final accentColor = task.isCompleted
        ? scheme.successColor
        : (hasDeadline ? scheme.warningColor : scheme.primaryColor);
    final isLeftAligned = messageSenderType == SelfTalkSenderType.alterEgo;

    return Align(
      alignment: isLeftAligned ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(left: isLeftAligned ? 48 : 0, right: isLeftAligned ? 0 : 8, bottom: 8, top: 2),
        child: GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            await SelfTalkService.updateTaskCompletion(task, !task.isCompleted);
            await _loadMessages();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  task.isCompleted
                      ? Icons.check_circle
                      : (hasDeadline ? Icons.access_time : Icons.sticky_note_2_outlined),
                  size: 16,
                  color: accentColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.content,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textDarkColor,
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        deadlineText,
                        style: TextStyle(
                          fontSize: 11,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(ThemeScheme scheme) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final bool isAlterEgo = _senderType == SelfTalkSenderType.alterEgo;

    return GlassPanel(
      borderRadius: 0,
      dark: Theme.of(context).brightness == Brightness.dark,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + (bottomPadding > 0 ? 0 : 8)),
      decoration: BoxDecoration(
        color: scheme.cardColor.withValues(alpha: 0.85),
        border: Border(top: BorderSide(color: scheme.dividerColor.withValues(alpha: 0.3))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 发送者切换 + AI 状态
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: scheme.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildSenderButton(
                            label: '我',
                            icon: Icons.person_outline,
                            selected: _senderType == SelfTalkSenderType.me,
                            selectedColor: scheme.primaryColor,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _senderType = SelfTalkSenderType.me);
                              _persistSenderType(SelfTalkSenderType.me);
                            },
                          ),
                        ),
                        Expanded(
                          child: _buildSenderButton(
                            label: '另一个我',
                            icon: Icons.psychology_outlined,
                            selected: _senderType == SelfTalkSenderType.alterEgo,
                            selectedColor: const Color(0xFF7C4DFF),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _senderType = SelfTalkSenderType.alterEgo);
                              _persistSenderType(SelfTalkSenderType.alterEgo);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (!_aiEnabled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.textLightColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'AI 已关闭',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.textLightColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // 输入框 + 发送按钮
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: scheme.backgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isAlterEgo
                            ? const Color(0xFF7C4DFF).withValues(alpha: 0.3)
                            : scheme.dividerColor,
                      ),
                    ),
                    child: TextField(
                      controller: _inputController,
                      focusNode: _focusNode,
                      maxLines: 5,
                      minLines: 1,
                      key: ValueKey('input_$_senderType'),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(explicitSenderType: _senderType),
                      style: TextStyle(fontSize: 15, color: scheme.textDarkColor),
                      decoration: InputDecoration(
                        hintText: isAlterEgo
                            ? '从另一个视角说些什么...'
                            : '今天有什么新想法？',
                        hintStyle: TextStyle(color: scheme.textLightColor),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildSendButton(scheme),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildSenderButton({
    required String label,
    required IconData icon,
    required bool selected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selectedColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                size: 18,
                color: selected ? selectedColor : Colors.grey,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? selectedColor : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton(ThemeScheme scheme) {
    final isAlterEgo = _senderType == SelfTalkSenderType.alterEgo;
    final color = isAlterEgo ? const Color(0xFF7C4DFF) : scheme.primaryColor;

    return GestureDetector(
      onTap: _isSending ? null : () => _sendMessage(explicitSenderType: _senderType),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color,
              color.withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: _isSending
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            : const Icon(Icons.send, color: Colors.white, size: 22),
      ),
    );
  }
}
