import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/auto_backup_service.dart';

/// 备份管理页面
/// 
/// 功能：
/// 1. 显示备份列表
/// 2. 手动触发备份
/// 3. 从备份恢复
/// 4. 删除备份
class BackupManagerScreen extends StatefulWidget {
  const BackupManagerScreen({super.key});

  @override
  State<BackupManagerScreen> createState() => _BackupManagerScreenState();
}

class _BackupManagerScreenState extends State<BackupManagerScreen> {
  List<Map<String, dynamic>> _backups = [];
  bool _isLoading = true;
  bool _isBackingUp = false;
  String? _totalSize;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    
    try {
      final backups = await AutoBackupService.getBackupList();
      final totalSize = await AutoBackupService.getTotalBackupSize();
      
      setState(() {
        _backups = backups;
        _totalSize = AutoBackupService.formatFileSize(totalSize);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('加载备份列表失败: $e');
    }
  }

  Future<void> _performBackup() async {
    setState(() => _isBackingUp = true);
    
    try {
      await AutoBackupService.performBackup();
      await _loadBackups();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份成功')),
        );
      }
    } catch (e) {
      _showError('备份失败: $e');
    } finally {
      setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreBackup(String filePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text('恢复备份将覆盖当前所有数据，确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('恢复'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    
    try {
      await AutoBackupService.restoreFromBackup(filePath);
      await _loadBackups();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('恢复成功')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('恢复失败: $e');
    }
  }

  Future<void> _deleteBackup(String filePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个备份吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AutoBackupService.deleteBackup(filePath);
      await _loadBackups();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
      }
    } catch (e) {
      _showError('删除失败: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  String _formatDateTime(String isoString) {
    final dateTime = DateTime.parse(isoString);
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        title: Text('备份管理', style: TextStyle(color: scheme.textDarkColor)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
        actions: [
          // 手动备份按钮
          TextButton.icon(
            onPressed: _isBackingUp ? null : _performBackup,
            icon: _isBackingUp
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primaryColor,
                    ),
                  )
                : Icon(Icons.backup, color: scheme.primaryColor),
            label: Text(
              '立即备份',
              style: TextStyle(color: scheme.primaryColor),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: scheme.primaryColor),
            )
          : Column(
              children: [
                // 统计信息
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.storage_outlined,
                        color: scheme.primaryColor,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '备份存储',
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.textMediumColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_backups.length} 个备份',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: scheme.textDarkColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_totalSize != null)
                        Text(
                          _totalSize!,
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.textMediumColor,
                          ),
                        ),
                    ],
                  ),
                ),

                // 备份列表
                Expanded(
                  child: _backups.isEmpty
                      ? _buildEmptyState(scheme)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _backups.length,
                          itemBuilder: (context, index) {
                            final backup = _backups[index];
                            return _buildBackupItem(backup, scheme, index == 0);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 64,
            color: scheme.lightColor,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无备份',
            style: TextStyle(
              fontSize: 18,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角按钮创建第一个备份',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupItem(Map<String, dynamic> backup, ThemeScheme scheme, bool isLatest) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
        border: isLatest
            ? Border.all(color: scheme.primaryColor.withOpacity(0.5), width: 2)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isLatest
                ? scheme.primaryColor.withOpacity(0.1)
                : scheme.lightColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.backup,
            color: isLatest ? scheme.primaryColor : scheme.textMediumColor,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _formatDateTime(backup['backupTime']),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
            ),
            if (isLatest)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '最新',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${backup['diaryCount']} 篇日记 · ${AutoBackupService.formatFileSize(backup['size'])}',
            style: TextStyle(
              fontSize: 13,
              color: scheme.textMediumColor,
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: scheme.textMediumColor),
          onSelected: (value) {
            switch (value) {
              case 'restore':
                _restoreBackup(backup['filePath']);
                break;
              case 'delete':
                _deleteBackup(backup['filePath']);
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'restore',
              child: Row(
                children: [
                  Icon(Icons.restore, color: scheme.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  const Text('恢复此备份'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  const Text('删除', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
