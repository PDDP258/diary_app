import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/diary_provider.dart';
import '../providers/theme_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/inbox_service.dart';

/// 「麦麦写来的日记」收件箱。
///
/// 麦麦（通过 diary-mcp 的 `diary_write_draft`）把内容加密后传到服务器的
/// `inbox/` 目录，这里拉出来逐条给用户确认：
///   - 确认导入 → 写进本地日记库，然后删掉服务器原件
///   - 丢弃     → 直接删掉服务器原件
///
/// 导入的日记会标记来源，用户自己写的和麦麦写的一眼能分清。
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final CloudSyncService _syncService = CloudSyncFactory.instance;

  List<InboxItem> _items = [];
  bool _isLoading = true;
  String? _error;
  bool _dataChanged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = _syncService.syncServerUrl;
    final user = _syncService.syncUsername;
    final pwd = _syncService.syncPassword;

    if (url == null || user == null || pwd == null) {
      setState(() {
        _isLoading = false;
        _error = '请先在「数据管理 → 云同步」里登录 WebDAV';
      });
      return;
    }

    try {
      final items = await InboxService.listItems(
        serverUrl: url,
        username: user,
        password: pwd,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '拉取收件箱失败：$e';
      });
    }
  }

  /// 打开详情：下载 + 解密 + 弹窗
  ///
  /// 弹窗只负责「用户选了什么」和把已解密的正文带回来，
  /// 真正写库与删服务器原件由外层做
  /// （弹窗里拿不到凭证，也不该管服务器上的事）。
  Future<void> _openDetail(InboxItem item) async {
    final url = _syncService.syncServerUrl!;
    final user = _syncService.syncUsername!;
    final pwd = _syncService.syncPassword!;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DetailDialog(
        item: item,
        onLoad: () => InboxService.fetchPayload(
          serverUrl: url,
          username: user,
          password: pwd,
          name: item.name,
        ),
      ),
    );

    if (!mounted || result == null) return;

    final action = result['action'] as String?;
    if (action == 'import') {
      await _importItem(item, result['payload'] as Map<String, dynamic>?);
    } else if (action == 'discard') {
      await _discardItem(item);
    }

    _load();
  }

  /// 导入并删除原件
  Future<void> _importItem(InboxItem item, [Map<String, dynamic>? payload]) async {
    final url = _syncService.syncServerUrl!;
    final user = _syncService.syncUsername!;
    final pwd = _syncService.syncPassword!;

    // 弹窗里已经解密过一次了，优先用它；实在没有才重新拉
    final data = payload ??
        item.payload ??
        await InboxService.fetchPayload(
          serverUrl: url,
          username: user,
          password: pwd,
          name: item.name,
        );

    if (data == null) {
      _toast('下载或解密失败，请检查云端备份密钥', isError: true);
      return;
    }

    final ok = await InboxService.importToLocal(data);
    if (!ok) {
      _toast('导入失败，请稍后再试', isError: true);
      return;
    }

    await InboxService.markProcessed(
      serverUrl: url,
      username: user,
      password: pwd,
      name: item.name,
    );

    _dataChanged = true;
    if (mounted) {
      await context.read<DiaryProvider>().loadDiaries();
    }
    _toast('已导入日记');
  }

  /// 丢弃（只删服务器原件，不写本地）
  Future<void> _discardItem(InboxItem item) async {
    final url = _syncService.syncServerUrl!;
    final user = _syncService.syncUsername!;
    final pwd = _syncService.syncPassword!;

    await InboxService.markProcessed(
      serverUrl: url,
      username: user,
      password: pwd,
      name: item.name,
    );
    _toast('已丢弃');
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    final scheme = AppTheme.schemeOf(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? scheme.errorColor : scheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _dataChanged);
      },
      child: Scaffold(
        backgroundColor: scheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: scheme.backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: scheme.textDarkColor),
            onPressed: () => Navigator.pop(context, _dataChanged),
          ),
          title: Text(
            '麦麦写来的日记',
            style: TextStyle(color: scheme.textDarkColor),
          ),
          iconTheme: IconThemeData(color: scheme.textDarkColor),
          actions: [
            TextButton.icon(
              onPressed: _isLoading ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
              style: TextButton.styleFrom(foregroundColor: scheme.primaryColor),
            ),
          ],
        ),
        body: _buildBody(scheme),
      ),
    );
  }

  Widget _buildBody(ThemeScheme scheme) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: scheme.primaryColor));
    }

    if (_error != null) {
      return _buildEmpty(scheme, Icons.cloud_off_outlined, _error!,
          actionLabel: '重试', onAction: _load);
    }

    if (_items.isEmpty) {
      return _buildEmpty(
        scheme,
        Icons.inbox_outlined,
        '暂时没有待确认的日记',
        subtitle: '麦麦在聊天里说「帮我记下来」时，内容会出现在这里，\n'
            '你确认之后才会成为真正的日记。',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: scheme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildTip(scheme),
          const SizedBox(height: 12),
          ..._items.map((item) => _buildItem(item, scheme)),
        ],
      ),
    );
  }

  Widget _buildTip(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primaryColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.primaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '共 ${_items.length} 条待确认。导入后会在对应日期生成日记；'
              '服务器上的原件会被删除。',
              style: TextStyle(
                fontSize: 13,
                color: scheme.textMediumColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(InboxItem item, ThemeScheme scheme) {
    final time = item.modified != null
        ? DateFormat('MM-dd HH:mm').format(item.modified!)
        : item.name.replaceFirst('draft_', '').split('_').take(2).join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: scheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.mark_email_unread_outlined,
              color: scheme.primaryColor),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.textDarkColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$time · ${_formatSize(item.size)}',
            style: TextStyle(fontSize: 13, color: scheme.textMediumColor),
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.textLightColor),
        onTap: () => _openDetail(item),
      ),
    );
  }

  Widget _buildEmpty(
    ThemeScheme scheme,
    IconData icon,
    String message, {
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: scheme.lightColor),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: scheme.textMediumColor),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.textLightColor,
                  height: 1.6,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

/// 详情弹窗：加载 → 展示 → 导入 / 丢弃
class _DetailDialog extends StatefulWidget {
  final InboxItem item;
  final Future<Map<String, dynamic>?> Function() onLoad;

  const _DetailDialog({required this.item, required this.onLoad});

  @override
  State<_DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<_DetailDialog> {
  Map<String, dynamic>? _payload;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final payload = await widget.onLoad();
    if (!mounted) return;
    setState(() {
      _payload = payload;
      _loading = false;
      _failed = payload == null;
    });
  }

  void _import() {
    // 只回报动作 + 已解密正文。真正的写库在外层做（那里才有凭证，也能统一处理删除原件）
    Navigator.pop(context, {'action': 'import', 'payload': _payload});
  }

  void _discard() {
    Navigator.pop(context, {'action': 'discard'});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return AlertDialog(
      title: Text(
        _payload != null ? (_payload!['title'] as String? ?? '未命名') : '加载中…',
        style: TextStyle(color: scheme.textDarkColor, fontSize: 18),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : _failed
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: scheme.errorColor, size: 36),
                        const SizedBox(height: 12),
                        const Text(
                          '加载失败。\n请检查网络连接与「云端备份密钥」是否正确。',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _buildBody(scheme),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: _failed ? null : _discard,
          style: TextButton.styleFrom(foregroundColor: scheme.errorColor),
          child: const Text('丢弃'),
        ),
        ElevatedButton(
          onPressed: _failed ? null : _import,
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('确认导入'),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeScheme scheme) {
    final content = _payload!['content'] as String? ?? '';
    final date = _payload!['date'] as String? ?? '';
    final mood = _payload!['mood'] as String? ?? '';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (date.isNotEmpty || mood.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              children: [
                if (date.isNotEmpty)
                  _chip(Icons.calendar_today_outlined, date, scheme),
                if (mood.isNotEmpty) _chip(Icons.mood_outlined, mood, scheme),
              ],
            ),
            const SizedBox(height: 14),
          ],
          SelectableText(
            content,
            style: TextStyle(
              fontSize: 15,
              color: scheme.textDarkColor,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text, ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.lightColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.textMediumColor),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: scheme.textMediumColor),
          ),
        ],
      ),
    );
  }
}
