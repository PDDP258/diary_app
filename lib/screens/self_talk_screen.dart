import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../models/self_talk_message.dart';
import '../models/self_talk_task.dart';
import '../services/self_talk_service.dart';
import '../services/sound_service.dart';
import '../widgets/animated_feedback.dart';
import '../widgets/smart_notifications.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate != null
        ? DateTime.parse(widget.initialDate!)
        : DateTime.now();
    _loadAiSetting();
    _loadMessages();
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

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    HapticFeedback.lightImpact();

    // 强制捕获当前 senderType，避免任何异步状态漂移
    final currentSenderType = _senderType;

    final sentMessage = await SelfTalkService.sendMessage(
      text,
      _dateStr,
      senderType: currentSenderType,
    );
    _inputController.clear();

    await _loadMessages();

    // 增强通知：如果是我发的消息且检测到了任务，播放成功音效+强震动+Toast
    if (_senderType == SelfTalkSenderType.me && _aiEnabled && sentMessage.id != null) {
      final detectedTasks = _tasks.where((t) => t.messageId == sentMessage.id).toList();
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
          // AI 对话开关
          _buildAiToggle(scheme),
          const SizedBox(width: 8),
        ],
        iconTheme: IconThemeData(color: scheme.textDarkColor),
      ),
      body: Column(
        children: [
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
                      final msgTasks = msg.senderType == SelfTalkSenderType.me && msg.id != null
                          ? _tasks.where((t) => t.messageId == msg.id).toList()
                          : <SelfTalkTask>[];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMessageBubble(msg, scheme),
                          ...msgTasks.map((task) => _buildTaskCard(task, scheme)),
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

  /// AI 开关按钮
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
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
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

  Widget _buildMessageBubble(SelfTalkMessage message, ThemeScheme scheme) {
    final time = DateFormat('HH:mm').format(DateTime.parse(message.createdAt));

    // 使用 if-else 替代 switch，确保 senderType 判断不会被编译器优化出错
    if (message.senderType == SelfTalkSenderType.me) {
      return _buildRightBubble(
        content: message.content,
        time: time,
        scheme: scheme,
        onLongPress: () => _deleteMessage(message),
      );
    } else if (message.senderType == SelfTalkSenderType.alterEgo) {
      return _buildLeftBubble(
        content: message.content,
        time: time,
        scheme: scheme,
        avatarEmoji: '🧠',
        senderLabel: '另一个我',
        textColor: const Color(0xFF7C4DFF),
        gradientColors: [
          const Color(0xFF7C4DFF).withValues(alpha: 0.18),
          const Color(0xFF651FFF).withValues(alpha: 0.10),
        ],
        borderColor: const Color(0xFF7C4DFF).withValues(alpha: 0.50),
        onLongPress: () => _deleteMessage(message),
      );
    } else {
      // system
      return _buildLeftBubble(
        content: message.content,
        time: time,
        scheme: scheme,
        avatarEmoji: '📝',
        senderLabel: null,
        textColor: scheme.textDarkColor,
        gradientColors: [
          scheme.surfaceColor,
          scheme.cardColor,
        ],
        borderColor: scheme.dividerColor,
      );
    }
  }

  /// "我"的消息：右对齐主色气泡
  Widget _buildRightBubble({
    required String content,
    required String time,
    required ThemeScheme scheme,
    VoidCallback? onLongPress,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(left: 48, top: 4, bottom: 4),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primaryColor.withValues(alpha: 0.20),
                  scheme.primaryColor.withValues(alpha: 0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(
                color: scheme.primaryColor.withValues(alpha: 0.30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.textDarkColor,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
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
        ),
      ),
    );
  }

  /// 左侧气泡：Alter Ego / 系统
  Widget _buildLeftBubble({
    required String content,
    required String time,
    required ThemeScheme scheme,
    required String avatarEmoji,
    String? senderLabel,
    required Color textColor,
    required List<Color> gradientColors,
    required Color borderColor,
    VoidCallback? onLongPress,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(right: 48, top: 4, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Text(avatarEmoji, style: const TextStyle(fontSize: 18)),
              ),
            ),
            Flexible(
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (senderLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            senderLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                        ),
                      Text(
                        content,
                        style: TextStyle(
                          fontSize: 15,
                          color: scheme.textDarkColor,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.textLightColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(SelfTalkTask task, ThemeScheme scheme) {
    final hasDeadline = task.deadline != null;
    final deadlineText = hasDeadline
        ? DateFormat('MM/dd HH:mm').format(DateTime.parse(task.deadline!))
        : '备忘';
    final accentColor = task.isCompleted
        ? scheme.successColor
        : (hasDeadline ? scheme.warningColor : scheme.primaryColor);

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8, top: 2),
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
                  task.isCompleted ? Icons.check_circle : (hasDeadline ? Icons.access_time : Icons.sticky_note_2_outlined),
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + (bottomPadding > 0 ? 0 : 8)),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        border: Border(top: BorderSide(color: scheme.dividerColor)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadowColor.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
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
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
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
                _buildSendButton(isAlterEgo, scheme),
              ],
            ),
          ],
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

  Widget _buildSendButton(bool isAlterEgo, ThemeScheme scheme) {
    final color = isAlterEgo ? const Color(0xFF7C4DFF) : scheme.primaryColor;

    return GestureDetector(
      onTap: _isSending ? null : _sendMessage,
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
