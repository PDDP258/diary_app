import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/maibot_service.dart';

/// 和麦麦聊天。
///
/// 走的是服务器上的「对话桥」，只发一句话、拿一句回复；
/// 对话历史存在本地，麦麦那边不会把它并进 QQ 的记忆。
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final MaibotService _service = MaibotService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  List<MaibotMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _configured = false;
  bool _connected = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final configured = await _service.isConfigured();
    final history = await _service.loadHistory();
    if (!mounted) return;
    setState(() {
      _configured = configured;
      _messages = history;
      _loading = false;
    });
    _jumpToBottom();
    if (configured) {
      final health = await _service.health();
      if (!mounted) return;
      setState(() => _connected = health.connected);
      if (health.reachable && !health.connected) {
        await _service.warmup();
      }
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_configured) {
      await _openSettings();
      return;
    }

    final userMessage = MaibotMessage(
      role: 'user',
      text: text,
      time: DateTime.now(),
    );
    setState(() {
      _sending = true;
      _hint = null;
      _messages = [..._messages, userMessage];
      _input.clear();
    });
    await _service.appendHistory(userMessage);
    _jumpToBottom();

    final reply = await _service.send(text);
    if (!mounted) return;

    if (reply.ok) {
      final botMessage = MaibotMessage(
        role: 'bot',
        text: reply.text,
        time: DateTime.now(),
        durationMs: reply.durationMs,
      );
      await _service.appendHistory(botMessage);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, botMessage];
        _sending = false;
        _connected = true;
      });
      _jumpToBottom();
    } else {
      setState(() {
        _sending = false;
        _hint = reply.error;
      });
    }
  }

  Future<void> _clearHistory() async {
    final scheme = AppTheme.readSchemeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.cardColor,
        title: Text('清空对话', style: TextStyle(color: scheme.textDarkColor)),
        content: Text(
          '本地这段对话记录会被删掉，麦麦那边本来就不知道。',
          style: TextStyle(color: scheme.textMediumColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('算了', style: TextStyle(color: scheme.textMediumColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('清空', style: TextStyle(color: scheme.errorColor)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.clearHistory();
    if (!mounted) return;
    setState(() => _messages = []);
  }

  Future<void> _openSettings() async {
    final scheme = AppTheme.readSchemeOf(context);

    // 读不到就用默认值：设置界面必须能打开，
    // 存储层出问题时不能让按钮变成「点了没反应」。
    var currentBase = MaibotService.defaultBaseUrl;
    var currentToken = '';
    try {
      currentBase = await _service.baseUrl;
      currentToken = await _service.token;
    } catch (_) {
      // 忽略，回落到默认值
    }
    if (!mounted) return;
    // 不用 TextEditingController：弹窗的退场动画还在跑时 controller 就 dispose 了，
    // 动画期间重建 TextField 会撞上「used after being disposed」。
    // 用 TextFormField + 局部变量，值一样拿得到，也不牵扯生命周期。
    var baseInput = currentBase;
    var tokenInput = currentToken;
    String? saveError;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.cardColor,
        title: Text('连接设置', style: TextStyle(color: scheme.textDarkColor)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '这两项由服务器提供。token 只用于这条通道，换掉它不会影响别的。',
                style: TextStyle(fontSize: 12, color: scheme.textLightColor),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: currentBase,
                onChanged: (value) => baseInput = value,
                style: TextStyle(color: scheme.textDarkColor),
                decoration: InputDecoration(
                  labelText: '桥地址',
                  hintText: MaibotService.defaultBaseUrl,
                  labelStyle: TextStyle(color: scheme.textMediumColor),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: currentToken,
                onChanged: (value) => tokenInput = value,
                style: TextStyle(color: scheme.textDarkColor),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '访问 token',
                  labelStyle: TextStyle(color: scheme.textMediumColor),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: scheme.textMediumColor)),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _service.setBaseUrl(baseInput);
                await _service.setToken(tokenInput);
              } catch (e) {
                // 安全存储不可用（如 keystore 异常）时，不能让弹窗僵在这里
                saveError = '保存失败：$e';
              }
              if (context.mounted) Navigator.pop(context, saveError == null);
            },
            child: Text('保存', style: TextStyle(color: scheme.primaryColor)),
          ),
        ],
      ),
    );

    if (saveError != null && mounted) {
      setState(() => _hint = saveError);
    }

    if (saved == true && mounted) {
      final configured = await _service.isConfigured();
      final health = configured ? await _service.health() : (reachable: false, connected: false);
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _connected = health.connected;
        _hint = configured && !health.reachable ? '保存了，但连不上，检查地址和网络' : null;
      });
      if (health.reachable) await _service.warmup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        foregroundColor: scheme.textDarkColor,
        title: Row(
          children: [
            Text(
              '麦麦',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(width: 8),
            if (_configured)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _connected ? scheme.successColor : scheme.textLightColor,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            tooltip: '连接设置',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: '清空对话',
            onPressed: _messages.isEmpty ? null : _clearHistory,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primaryColor,
              ),
            )
          : Column(
              children: [
                Expanded(child: _buildMessageList(scheme)),
                if (_hint != null) _buildHint(scheme),
                _buildInputBar(scheme),
              ],
            ),
    );
  }

  Widget _buildMessageList(ThemeScheme scheme) {
    if (_messages.isEmpty) {
      return _buildEmpty(scheme);
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _messages.length) {
          return _buildThinking(scheme);
        }
        return _buildBubble(scheme, _messages[index]);
      },
    );
  }

  Widget _buildEmpty(ThemeScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.nightlight_round,
              size: 34,
              color: scheme.textLightColor,
            ),
            const SizedBox(height: 16),
            Text(
              _configured ? '想说什么就说' : '还没连上麦麦',
              style: TextStyle(
                fontSize: 15,
                color: scheme.textDarkColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _configured
                  ? '这里说的话只留在这一页，不会混进 QQ 里的聊天。'
                  : '点右上角填上桥地址和 token，就能开始聊。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: scheme.textLightColor,
              ),
            ),
            if (!_configured) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _openSettings,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scheme.primaryColor),
                  foregroundColor: scheme.primaryColor,
                ),
                child: const Text('去设置'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ThemeScheme scheme, MaibotMessage message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryColor : scheme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: isUser ? null : Border.all(color: scheme.dividerColor),
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: isUser ? Colors.white : scheme.textDarkColor,
          ),
        ),
      ),
    );
  }

  Widget _buildThinking(ThemeScheme scheme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: scheme.textLightColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '正在想…',
              style: TextStyle(fontSize: 12, color: scheme.textLightColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHint(ThemeScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.warningColor.withValues(alpha: 0.12),
      child: Text(
        _hint!,
        style: TextStyle(fontSize: 12, color: scheme.textMediumColor),
      ),
    );
  }

  Widget _buildInputBar(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.backgroundColor,
        border: Border(top: BorderSide(color: scheme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: scheme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.dividerColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(fontSize: 14, color: scheme.textDarkColor),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: _configured ? '说点什么…' : '先连上麦麦',
                    hintStyle: TextStyle(color: scheme.textLightColor),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _sending
                      ? scheme.dividerColor
                      : scheme.primaryColor,
                ),
                child: _sending
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: scheme.textLightColor,
                        ),
                      )
                    : const Icon(Icons.arrow_upward, size: 19, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
