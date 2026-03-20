import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clipboard/clipboard.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import '../providers/diary_provider.dart';
import '../providers/theme_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/backup_export_service.dart';
import '../services/pdf_export_service.dart';
import '../services/database_service.dart';
import '../services/encryption_service.dart';
import '../services/app_lock_service.dart';
import 'backup_decrypt_screen.dart';
import 'backup_manager_screen.dart';

/// 数据管理页面
class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  final CloudSyncService _syncService = CloudSyncFactory.instance;
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _initSyncService();
  }

  Future<void> _initSyncService() async {
    await _syncService.initialize();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: scheme.textDarkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '数据管理',
          style: TextStyle(
            color: scheme.textDarkColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 云同步模块
            _buildSectionTitle('云同步', scheme),
            const SizedBox(height: 12),
            _buildCloudSyncCard(scheme),

            const SizedBox(height: 24),

            // 第三方备份导入
            _buildSectionTitle('第三方备份', scheme),
            const SizedBox(height: 12),
            _buildCard([
              _buildMenuItem(
                icon: Icons.lock_open,
                title: '导入加密的MBK备份',
                subtitle: '从其他日记App导入（需要密码）',
                onTap: () => _showMBKDecryptTool(context),
                scheme: scheme,
              ),
            ], scheme),

            const SizedBox(height: 24),

            // 自动备份管理
            _buildSectionTitle('自动备份', scheme),
            const SizedBox(height: 12),
            _buildCard([
              _buildMenuItem(
                icon: Icons.auto_fix_high,
                title: '备份管理',
                subtitle: '查看和管理自动备份（保留最近7次）',
                onTap: () => _showBackupManager(context),
                scheme: scheme,
              ),
            ], scheme),

            const SizedBox(height: 24),

            // 本地备份
            _buildSectionTitle('本地备份', scheme),
            const SizedBox(height: 12),
            _buildCard([
              _buildMenuItem(
                icon: Icons.upload_file_outlined,
                title: '导出.mbk备份文件',
                subtitle: '用于迁移或备份数据',
                onTap: _exportBackup,
                isLoading: _isExporting,
                scheme: scheme,
              ),
              Divider(
                  height: 1,
                  indent: 56,
                  color: scheme.lightColor.withValues(alpha: 0.5)),
              _buildMenuItem(
                icon: Icons.download_outlined,
                title: '导入备份文件',
                subtitle: '用于恢复数据',
                onTap: _importBackup,
                isLoading: _isImporting,
                scheme: scheme,
              ),
            ], scheme),

            const SizedBox(height: 24),

            // 导出
            _buildSectionTitle('导出', scheme),
            const SizedBox(height: 12),
            _buildCard([
              _buildMenuItem(
                icon: Icons.text_snippet_outlined,
                title: '导出.txt文件',
                subtitle: '纯文本，不含图片等资源',
                onTap: _exportTxt,
                scheme: scheme,
              ),
              Divider(
                  height: 1,
                  indent: 56,
                  color: scheme.lightColor.withValues(alpha: 0.5)),
              _buildMenuItem(
                icon: Icons.picture_as_pdf_outlined,
                title: '导出PDF',
                subtitle: '导出为PDF文件，可打印或分享',
                onTap: _exportPdf,
                scheme: scheme,
              ),
            ], scheme),
          ],
        ),
      ),
    );
  }

  // 云同步卡片
  Widget _buildCloudSyncCard(ThemeScheme scheme) {
    final isLoggedIn = _syncService.isLoggedIn;
    final lastSyncTime = _syncService.lastSyncTime;

    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          // 登录状态/账号信息
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: isLoggedIn
                        ? LinearGradient(
                            colors: [scheme.lightColor, scheme.primaryColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isLoggedIn
                        ? null
                        : scheme.lightColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Icon(
                      isLoggedIn ? Icons.cloud_done : Icons.cloud_off,
                      color: isLoggedIn ? Colors.white : scheme.textLightColor,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoggedIn ? '已连接云服务' : '未连接云服务',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: scheme.textDarkColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isLoggedIn
                            ? (lastSyncTime != null
                                ? '上次同步: ${_formatDateTime(lastSyncTime)}'
                                : '尚未同步')
                            : '登录后可自动备份和同步数据',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textLightColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 登录/退出按钮
          if (!isLoggedIn) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _login,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.login, size: 20),
                  label: Text(_isSyncing ? '登录中...' : '登录 WebDAV'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            // WebDAV教程
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.help_outline, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '坚果云 WebDAV 使用教程',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '1. 登录坚果云官网 → 账户信息 → 安全选项\n'
                      '2. 找到"第三方应用管理" → 添加应用密码\n'
                      '3. 输入应用名称（如"小记日记"）→ 生成密码\n'
                      '4. 复制服务器地址、账号和应用密码',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textMediumColor,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(
                                text:
                                    'https://www.jianguoyun.com/d/account#safe',
                              ));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('链接已复制到剪贴板'),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('复制链接'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(
                                  'https://help.jianguoyun.com/?p=2064');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('查看教程'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _startSync,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync, size: 20),
                      label: Text(_isSyncing ? '同步中...' : '立即同步'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('退出'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.textMediumColor,
                      side: BorderSide(color: scheme.lightColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 自动同步开关
          if (isLoggedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.lightColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _syncService.autoSyncEnabled
                          ? Icons.auto_mode
                          : Icons.auto_mode_outlined,
                      color: _syncService.autoSyncEnabled
                          ? scheme.primaryColor
                          : scheme.textLightColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '自动同步',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: scheme.textDarkColor,
                            ),
                          ),
                          Text(
                            '写日记后自动备份文字数据',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.textLightColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _syncService.autoSyncEnabled,
                      onChanged: (value) async {
                        await _syncService.setAutoSync(value);
                        setState(() {});
                      },
                      activeThumbColor: scheme.primaryColor,
                    ),
                  ],
                ),
              ),
            ),

          // 图片同步提示和按钮
          if (isLoggedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '图片同步说明',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 自动同步仅备份文字数据\n'
                      '• 图片同步较耗时，建议WiFi环境操作\n'
                      '• 跨设备恢复时需手动同步图片',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textMediumColor,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSyncing ? null : _syncImages,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.photo_library, size: 18),
                        label: Text(_isSyncing ? '同步中...' : '手动同步图片'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 备份密钥管理
          if (isLoggedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.vpn_key, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '备份密钥管理',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 备份密钥用于解密云端备份\n'
                      '• 跨设备恢复时必须输入此密钥\n'
                      '• 请妥善保管，泄露会导致数据被盗\n'
                      '• 丢失密钥将无法恢复云端数据',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textMediumColor,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showCloudKeyDialog(context),
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('复制备份密钥'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _importCloudKeyDialog(context),
                            icon: const Icon(Icons.input, size: 18),
                            label: const Text('导入密钥'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';

    return DateFormat('MM-dd HH:mm').format(dateTime);
  }

  // 登录
  Future<void> _login() async {
    setState(() => _isSyncing = true);
    try {
      final success = await _syncService.login(context);
      if (mounted) {
        setState(() => _isSyncing = false);
        if (success) {
          _showSuccess('登录成功');
        } else {
          _showError('登录失败，请检查服务器地址、用户名和密码是否正确');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        _showError('登录出错: $e');
      }
    }
  }

  // 退出登录
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后将无法自动同步，确定要退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _syncService.logout();
      setState(() {});
      if (mounted) {
        _showSuccess('已退出登录');
      }
    }
  }

  // 开始同步
  Future<void> _startSync() async {
    setState(() => _isSyncing = true);

    final provider = context.read<DiaryProvider>();
    final diaryTags = await DatabaseService.getAllDiaryTags();

    final result = await _syncService.syncToCloud(
      diaries: provider.diaries,
      moods: provider.moods,
      tags: provider.tags,
      diaryTags: diaryTags,
    );

    setState(() => _isSyncing = false);

    if (mounted) {
      if (result.success) {
        _showSuccess('${result.message}\n上传了 ${result.uploadedCount} 篇日记');
      } else {
        _showError(result.message);
      }
    }
  }

  // 手动同步图片
  Future<void> _syncImages() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同步图片'),
        content: const Text('图片同步可能需要较长时间，建议在WiFi环境下操作。\n\n确定要开始同步吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始同步'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSyncing = true);

    final provider = context.read<DiaryProvider>();
    final diaryTags = await DatabaseService.getAllDiaryTags();

    final result = await _syncService.syncToCloud(
      diaries: provider.diaries,
      moods: provider.moods,
      tags: provider.tags,
      diaryTags: diaryTags,
      syncImages: true,
    );

    setState(() => _isSyncing = false);

    if (mounted) {
      if (result.success) {
        _showSuccess('图片同步完成');
      } else {
        _showError(result.message);
      }
    }
  }

  // 从云端恢复
  Future<void> _restoreFromCloud() async {
    // 先检查是否有云端备份密钥
    final hasKey = await EncryptionService.hasCloudBackupKey();
    if (!hasKey) {
      // 没有密钥，提示用户导入
      final shouldImport = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.vpn_key, color: Colors.orange),
              SizedBox(width: 8),
              Text('需要备份密钥'),
            ],
          ),
          content: const Text(
            '首次恢复或清除数据后，需要输入之前保存的备份密钥才能解密云端数据。\n\n'
            '如果您没有保存密钥，将无法恢复之前的云端备份。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入密钥'),
            ),
          ],
        ),
      );

      if (shouldImport == true) {
        await _importCloudKeyDialog(context);
      }
      return;
    }

    setState(() => _isSyncing = true);

    final result = await _syncService.syncFromCloud();

    setState(() => _isSyncing = false);

    if (mounted) {
      if (result.success) {
        // 刷新Provider数据
        await context.read<DiaryProvider>().loadDiaries();
        _showSuccess('${result.message}\n恢复了 ${result.downloadedCount} 篇日记');
      } else {
        _showError(result.message);
      }
    }
  }

  Widget _buildSectionTitle(String title, ThemeScheme scheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: scheme.textDarkColor,
      ),
    );
  }

  Widget _buildCard(List<Widget> children, ThemeScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLoading = false,
    required ThemeScheme scheme,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primaryColor),
              ),
            )
          : Icon(icon, color: scheme.textMediumColor),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: scheme.textDarkColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: scheme.textLightColor.withValues(alpha: 0.8),
        ),
      ),
      onTap: isLoading ? null : onTap,
    );
  }

  Future<void> _exportBackup() async {
    // 弹出密码设置对话框
    final password = await _showPasswordDialog(context, isExport: true);
    if (password == null) return;

    setState(() => _isExporting = true);

    try {
      final provider = context.read<DiaryProvider>();

      final backupData = {
        'version': '1.0.0',
        'exportTime': DateTime.now().toIso8601String(),
        'diaries': provider.diaries.map((d) => d.toMap()).toList(),
        'moods': provider.moods.map((m) => m.toMap()).toList(),
        'tags': provider.tags.map((t) => t.toMap()).toList(),
      };

      // 使用加密方式导出
      final filePath = await BackupExportService.exportWithPassword(
        backupData: backupData,
        password: password,
      );

      if (mounted) {
        _showSuccess('加密备份已保存到:\n$filePath');
      }
    } catch (e) {
      if (mounted) {
        _showError('导出失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  /// 密码输入对话框
  Future<String?> _showPasswordDialog(BuildContext context,
      {required bool isExport}) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isExport ? '设置备份密码' : '输入备份密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: isExport ? '设置密码' : '输入密码',
                hintText: isExport ? '请输入6位以上密码' : '请输入备份时的密码',
                border: const OutlineInputBorder(),
              ),
            ),
            if (isExport) ...[
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认密码',
                  hintText: '请再次输入密码',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final password = passwordController.text;
              if (password.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码至少需要6个字符')),
                );
                return;
              }
              if (isExport && password != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次输入的密码不一致')),
                );
                return;
              }
              Navigator.pop(context, password);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBackup() async {
    try {
      // 使用文件选择器选择备份文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return; // 用户取消了选择
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        _showError('无法读取文件路径');
        return;
      }

      setState(() => _isImporting = true);

      // 检查是否是加密的.mbk文件
      final isEncrypted = await BackupExportService.isEncrypted(filePath);

      Map<String, dynamic>? backupData;

      if (isEncrypted) {
        // 需要密码解密
        final password = await _showPasswordDialog(context, isExport: false);
        if (password == null) {
          setState(() => _isImporting = false);
          return;
        }

        backupData = await BackupExportService.importWithPassword(
          filePath: filePath,
          password: password,
        );
      } else {
        // 不加密的备份
        backupData = await BackupExportService.importPlain(filePath);
      }

      if (backupData == null) {
        if (mounted) {
          _showError('导入失败: 密码错误或文件损坏');
        }
        setState(() => _isImporting = false);
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认导入'),
          content: const Text('导入备份将覆盖现有数据，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('导入'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isImporting = false);
        return;
      }

      // 导入数据到数据库
      final provider = context.read<DiaryProvider>();

      // 导入日记（使用批量导入保留原始ID）
      final diariesData = backupData['diaries'] as List<dynamic>?;
      if (diariesData != null && diariesData.isNotEmpty) {
        final diaries = diariesData
            .map((d) => Diary.fromMap(d as Map<String, dynamic>))
            .toList();
        await DatabaseService.importDiaries(diaries);
      }

      // 导入心情
      final moodsData = backupData['moods'] as List<dynamic>?;
      if (moodsData != null && moodsData.isNotEmpty) {
        final moods = moodsData
            .map((m) => Mood.fromMap(m as Map<String, dynamic>))
            .toList();
        await DatabaseService.importMoods(moods);
      }

      // 导入标签
      final tagsData = backupData['tags'] as List<dynamic>?;
      if (tagsData != null && tagsData.isNotEmpty) {
        final tags = tagsData
            .map((t) => Tag.fromMap(t as Map<String, dynamic>))
            .toList();
        await DatabaseService.importTags(tags);
      }

      // 刷新数据
      await provider.loadAllData();

      if (mounted) {
        _showSuccess('导入成功');
      }
    } catch (e) {
      if (mounted) {
        _showError('导入失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _exportTxt() async {
    try {
      final provider = context.read<DiaryProvider>();

      if (provider.diaries.isEmpty) {
        _showError('没有日记可导出');
        return;
      }

      final buffer = StringBuffer();

      buffer.writeln('=' * 50);
      buffer.writeln('小记日记导出');
      buffer.writeln(
          '导出时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      buffer.writeln('共 ${provider.diaries.length} 篇日记');
      buffer.writeln('=' * 50);
      buffer.writeln();

      // 按日期排序（最新的在前）
      final sortedDiaries = List<Diary>.from(provider.diaries)
        ..sort((a, b) => b.date.compareTo(a.date));

      for (final diary in sortedDiaries) {
        buffer.writeln('【日期】${diary.date}');
        if (diary.title != null && diary.title!.isNotEmpty) {
          buffer.writeln('【标题】${diary.title}');
        }
        if (diary.moodName != null) {
          buffer.writeln('【心情】${diary.moodEmoji} ${diary.moodName}');
        }
        buffer.writeln('-' * 30);
        buffer.writeln(diary.content ?? '');
        buffer.writeln();
        buffer.writeln('=' * 50);
        buffer.writeln();
      }

      // 获取Download目录
      final directory = await getExternalStorageDirectory();
      final downloadDir = Directory('${directory!.path}/Download');

      // 确保Download目录存在
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'diary_export_$timestamp.txt';
      final filePath = '${downloadDir.path}/$fileName';

      // 写入文件
      final file = File(filePath);
      await file.writeAsString(buffer.toString());

      // 显示成功对话框，并复制路径到剪贴板
      if (mounted) {
        await FlutterClipboard.copy(filePath);
        _showSuccess('文本已保存到Download文件夹，路径已复制到剪贴板');
      }
    } catch (e) {
      _showError('导出失败: $e');
    }
  }

  Future<void> _exportPdf() async {
    try {
      final provider = context.read<DiaryProvider>();
      await PdfExportService.exportDiaries(
        diaries: provider.diaries,
        moods: provider.moods,
        tags: provider.tags,
      );
    } catch (e) {
      _showError('PDF导出失败: $e');
    }
  }

  void _showError(String message) {
    final scheme = AppTheme.schemeOf(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccess(String message) {
    final scheme = AppTheme.schemeOf(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: scheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showMBKDecryptTool(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BackupDecryptScreen(),
      ),
    );
  }

  void _showBackupManager(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BackupManagerScreen(),
      ),
    );
  }

  // 显示备份密钥对话框（需要手势密码验证）
  Future<void> _showCloudKeyDialog(BuildContext context) async {
    // 检查是否启用了应用锁
    if (await AppLockService.isEnabled) {
      // 需要验证手势密码
      final verified = await _verifyAppLock(context);
      if (!verified) return;
    }

    if (!mounted) return;

    // 获取或生成云端备份密钥
    var cloudKey = await EncryptionService.getCloudBackupKey();
    cloudKey ??= await EncryptionService.generateCloudBackupKey();

    if (!mounted) return;

    // 显示密钥对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Colors.red),
            SizedBox(width: 8),
            Text('备份密钥'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Text(
                '⚠️ 重要提示\n'
                '• 此密钥用于解密云端备份\n'
                '• 请妥善保管，切勿泄露\n'
                '• 丢失将无法恢复数据',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              cloudKey!,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await FlutterClipboard.copy(cloudKey!);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('备份密钥已复制到剪贴板'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
              Navigator.pop(context);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制密钥'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // 导入备份密钥对话框
  Future<void> _importCloudKeyDialog(BuildContext context) async {
    final keyController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.input, color: Colors.red),
            SizedBox(width: 8),
            Text('导入备份密钥'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '请粘贴之前保存的备份密钥\n'
                '导入后将覆盖当前密钥',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '备份密钥',
                hintText: '粘贴密钥...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (keyController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入备份密钥')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await EncryptionService.importCloudBackupKey(
        keyController.text.trim(),
      );

      if (mounted) {
        if (success) {
          _showSuccess('备份密钥导入成功');
        } else {
          _showError('备份密钥导入失败');
        }
      }
    }
  }

  // 验证应用锁
  Future<bool> _verifyAppLock(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _AppLockVerifyDialog(),
        ) ??
        false;
  }
}

// 应用锁验证对话框
class _AppLockVerifyDialog extends StatefulWidget {
  @override
  State<_AppLockVerifyDialog> createState() => _AppLockVerifyDialogState();
}

class _AppLockVerifyDialogState extends State<_AppLockVerifyDialog> {
  final List<int> _selectedPoints = [];
  String? _error;
  int? _currentPoint;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return AlertDialog(
      title: const Text('验证手势密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '请滑动输入手势密码',
            style: TextStyle(color: scheme.textMediumColor),
          ),
          const SizedBox(height: 20),
          _buildGestureGrid(scheme),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildGestureGrid(ThemeScheme scheme) {
    return GestureDetector(
      onPanStart: (details) => _onPanStart(details, scheme),
      onPanUpdate: (details) => _onPanUpdate(details, scheme),
      onPanEnd: (_) => _onPanEnd(),
      child: Container(
        width: 240,
        height: 240,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            // 连接线
            CustomPaint(
              size: const Size(200, 200),
              painter: _LinePainter(
                points: _selectedPoints,
                currentPoint: _currentPoint,
                color: scheme.primaryColor,
              ),
            ),
            // 9个点
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
              ),
              itemCount: 9,
              itemBuilder: (context, index) {
                final isSelected = _selectedPoints.contains(index);
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? scheme.primaryColor
                        : scheme.lightColor.withOpacity(0.3),
                    border: Border.all(
                      color:
                          isSelected ? scheme.primaryColor : scheme.lightColor,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            isSelected ? Colors.white : scheme.textLightColor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails details, ThemeScheme scheme) {
    final point = _getPointAtPosition(details.localPosition, scheme);
    if (point != null && !_selectedPoints.contains(point)) {
      setState(() {
        _selectedPoints.add(point);
        _currentPoint = point;
        _error = null;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, ThemeScheme scheme) {
    final point = _getPointAtPosition(details.localPosition, scheme);
    if (point != null && !_selectedPoints.contains(point)) {
      setState(() {
        _selectedPoints.add(point);
        _currentPoint = point;
      });
    }
  }

  void _onPanEnd() {
    setState(() {
      _currentPoint = null;
    });

    if (_selectedPoints.length >= 4) {
      _verifyPattern();
    } else {
      setState(() {
        _error = '至少需要连接4个点';
        _selectedPoints.clear();
      });
    }
  }

  int? _getPointAtPosition(Offset localPosition, ThemeScheme scheme) {
    // 计算每个点的位置
    const gridSize = 200.0;
    const padding = 20.0;
    const cellSize = (gridSize - padding * 2) / 2;

    for (int i = 0; i < 9; i++) {
      final row = i ~/ 3;
      final col = i % 3;
      final centerX = padding + col * cellSize + cellSize / 2;
      final centerY = padding + row * cellSize + cellSize / 2;

      final distance = (localPosition - Offset(centerX, centerY)).distance;
      if (distance < 30) {
        return i;
      }
    }
    return null;
  }

  void _verifyPattern() {
    final isValid = AppLockService.verifyPattern(_selectedPoints);

    if (isValid) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = '手势密码错误';
        _selectedPoints.clear();
      });
    }
  }
}

// 连接线画笔
class _LinePainter extends CustomPainter {
  final List<int> points;
  final int? currentPoint;
  final Color color;

  _LinePainter({
    required this.points,
    this.currentPoint,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    const padding = 20.0;
    const cellSize = (200 - padding * 2) / 2;

    for (int i = 0; i < points.length - 1; i++) {
      final row1 = points[i] ~/ 3;
      final col1 = points[i] % 3;
      final row2 = points[i + 1] ~/ 3;
      final col2 = points[i + 1] % 3;

      final x1 = padding + col1 * cellSize + cellSize / 2;
      final y1 = padding + row1 * cellSize + cellSize / 2;
      final x2 = padding + col2 * cellSize + cellSize / 2;
      final y2 = padding + row2 * cellSize + cellSize / 2;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    return points != oldDelegate.points ||
        currentPoint != oldDelegate.currentPoint;
  }
}
