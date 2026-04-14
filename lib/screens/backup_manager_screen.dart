import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/diary_provider.dart';
import '../providers/theme_provider.dart';
import '../services/auto_backup_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/encryption_service.dart';

/// 备份管理页面
/// 
/// 功能：
/// 1. 显示本地备份列表
/// 2. 显示云端其他备份（v1.1.5新增）
/// 3. 手动触发备份
/// 4. 从备份恢复
/// 5. 从其他备份导入（合并不覆盖）
/// 6. 删除备份
class BackupManagerScreen extends StatefulWidget {
  const BackupManagerScreen({super.key});

  @override
  State<BackupManagerScreen> createState() => _BackupManagerScreenState();
}

class _BackupManagerScreenState extends State<BackupManagerScreen> {
  List<Map<String, dynamic>> _backups = [];
  List<CloudBackupInfo> _cloudBackups = [];
  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isScanningCloud = false;
  String? _totalSize;
  bool _isCloudLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
    _checkCloudStatus();
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

  Future<void> _checkCloudStatus() async {
    final cloudService = CloudSyncFactory.instance;
    await cloudService.initialize();
    setState(() {
      _isCloudLoggedIn = cloudService.isLoggedIn;
    });
    
    if (_isCloudLoggedIn) {
      await _scanCloudBackups();
    }
  }

  Future<void> _scanCloudBackups() async {
    setState(() => _isScanningCloud = true);
    
    try {
      final cloudService = CloudSyncFactory.instance;
      final backups = await cloudService.scanAllBackups();
      
      setState(() {
        _cloudBackups = backups;
        _isScanningCloud = false;
      });
    } catch (e) {
      setState(() => _isScanningCloud = false);
      debugPrint('扫描云端备份失败: $e');
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

  /// 导入其他云端备份（合并不覆盖）
  Future<void> _importCloudBackup(CloudBackupInfo backup) async {
    // 如果是当前设备的备份，提示使用恢复功能
    if (backup.isCurrentDevice) {
      _showError('这是当前设备的备份，请使用"恢复"功能');
      return;
    }

    // 显示输入密钥对话框
    final keyController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入云端备份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请输入该备份的密钥以解密数据：'),
            const SizedBox(height: 8),
            const Text(
              '提示：密钥可在原设备的"数据管理 → 云端备份密钥"中查看',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: '备份密钥',
                border: OutlineInputBorder(),
                hintText: '粘贴密钥 here',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (keyController.text.isEmpty) {
      _showError('请输入密钥');
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final cloudService = CloudSyncFactory.instance;
      
      // 1. 从云端下载备份（不解密，先检查是否能下载）
      final encryptedData = await cloudService.downloadBackupFromFolderRaw(
        backup.folderName,
      );
      
      if (encryptedData == null) {
        setState(() => _isLoading = false);
        _showError('下载备份失败，请检查网络连接和云存储路径');
        return;
      }
      
      // 显示原始内容供调试（如果数据很小）
      final rawJson = jsonEncode(encryptedData);
      if (rawJson.length < 500) {
        print('原始备份内容: $rawJson');
      }
      
      // 2. 解密备份（清理密钥中的换行符和空格）
      final cleanKey = keyController.text.trim().replaceAll(RegExp(r'\s+'), '');
      print('使用密钥: ${cleanKey.substring(0, cleanKey.length > 10 ? 10 : cleanKey.length)}...');
      
      // 直接使用 EncryptionService 解密
      final encryptedContent = encryptedData['data'] as String?;
      if (encryptedContent == null) {
        setState(() => _isLoading = false);
        _showError('备份数据格式错误：缺少加密内容');
        return;
      }
      
      final decryptedJson = await EncryptionService.decryptWithCloudKey(
        encryptedContent,
        cleanKey,
      );
      
      if (decryptedJson == null) {
        setState(() => _isLoading = false);
        _showError('解密失败，请检查密钥是否正确');
        _showDebugDialog(encryptedData, cleanKey);
        return;
      }
      
      Map<String, dynamic>? backupData;
      try {
        backupData = jsonDecode(decryptedJson) as Map<String, dynamic>;
      } catch (e) {
        setState(() => _isLoading = false);
        _showError('解密后的数据格式错误: $e');
        return;
      }

      // 2. 合并到本地（不覆盖），同时恢复图片
      final result = await cloudService.mergeBackupToLocal(
        backupData,
        folderName: backup.folderName,
      );
      
      setState(() => _isLoading = false);
      
      if (result.success) {
        // 刷新日记显示 - 等待加载完成
        if (mounted) {
          await context.read<DiaryProvider>().loadDiaries();
        }
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('导入成功'),
              content: Text('成功导入 ${result.downloadedCount} 条数据'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // 关闭备份管理页面，返回到数据管理页面，并返回true表示数据有更改
                    Navigator.pop(context, true);
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      } else {
        _showError('导入失败: ${result.message}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('导入失败: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  /// 显示调试对话框，帮助排查解密问题
  void _showDebugDialog(Map<String, dynamic> encryptedData, String key) {
    final scheme = AppTheme.schemeOf(context);
    final dataContent = encryptedData['data']?.toString() ?? '无';
    final hasCloudPrefix = dataContent.startsWith('__CLOUD__');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解密失败 - 调试信息'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('密钥前10位: ${key.substring(0, key.length > 10 ? 10 : key.length)}...', 
                style: TextStyle(fontSize: 12, color: scheme.textMediumColor)),
              const SizedBox(height: 8),
              Text('密钥长度: ${key.length}', 
                style: TextStyle(fontSize: 12, color: scheme.textMediumColor)),
              const SizedBox(height: 8),
              Text('是否加密格式: ${encryptedData['_encrypted'] == true ? "是" : "否"}', 
                style: TextStyle(fontSize: 12, color: scheme.textMediumColor)),
              const SizedBox(height: 8),
              Text('数据版本: ${encryptedData['_version']?.toString() ?? "未知"}', 
                style: TextStyle(fontSize: 12, color: scheme.textMediumColor)),
              const SizedBox(height: 8),
              Text('是否有__CLOUD__前缀: ${hasCloudPrefix ? "是" : "否"}', 
                style: TextStyle(fontSize: 12, color: hasCloudPrefix ? Colors.green : Colors.red)),
              const SizedBox(height: 16),
              const Text('密文前50字符:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                dataContent.length > 50 ? dataContent.substring(0, 50) + '...' : dataContent,
                style: TextStyle(fontSize: 10, color: scheme.textLightColor, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              Text(
                '提示: 如果"是否有__CLOUD__前缀"为否，说明这不是加密备份，可能是旧版本格式。',
                style: TextStyle(fontSize: 12, color: scheme.textMediumColor),
              ),
              const SizedBox(height: 16),
              // 密钥自测
              FutureBuilder<Map<String, dynamic>>(
                future: EncryptionService.verifyKey(key),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final verifyResult = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '密钥自测结果:',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: scheme.textDarkColor),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '密钥有效性: ${verifyResult['valid'] == true ? "✓ 有效" : "✗ 无效"}',
                          style: TextStyle(
                            fontSize: 13,
                            color: verifyResult['valid'] == true ? Colors.green : Colors.red,
                          ),
                        ),
                        Text(
                          '能否加密: ${verifyResult['canEncrypt'] == true ? "✓" : "✗"}',
                          style: TextStyle(fontSize: 12, color: scheme.textMediumColor),
                        ),
                        Text(
                          '能否解密: ${verifyResult['canDecrypt'] == true ? "✓" : "✗"}',
                          style: TextStyle(fontSize: 12, color: scheme.textMediumColor),
                        ),
                        if (verifyResult['error'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '错误: ${verifyResult['error']}',
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ],
                        const SizedBox(height: 16),
                        // 尝试用这个密钥解密实际数据
                        Text(
                          '实际备份解密测试:',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: scheme.textDarkColor),
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<String?>(
                          future: EncryptionService.decryptWithCloudKey(dataContent, key),
                          builder: (context, decryptSnapshot) {
                            if (decryptSnapshot.connectionState == ConnectionState.waiting) {
                              return const Text('测试中...', style: TextStyle(fontSize: 12));
                            }
                            if (decryptSnapshot.hasError) {
                              return Text(
                                '解密异常: ${decryptSnapshot.error}',
                                style: const TextStyle(fontSize: 12, color: Colors.red),
                              );
                            }
                            if (decryptSnapshot.data == null) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '解密结果: ✗ 失败（返回null）',
                                    style: TextStyle(fontSize: 13, color: Colors.red),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '可能原因:\n1. 该备份不是用此密钥加密的\n2. 备份文件已损坏\n3. 加密/解密算法不匹配',
                                    style: TextStyle(fontSize: 11, color: scheme.textMediumColor),
                                  ),
                                ],
                              );
                            }
                            return Text(
                              '解密结果: ✓ 成功（长度: ${decryptSnapshot.data!.length}）',
                              style: const TextStyle(fontSize: 13, color: Colors.green),
                            );
                          },
                        ),
                      ],
                    );
                  }
                  return const CircularProgressIndicator();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
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
          : RefreshIndicator(
              onRefresh: () async {
                await _loadBackups();
                if (_isCloudLoggedIn) {
                  await _scanCloudBackups();
                }
              },
              child: CustomScrollView(
                slivers: [
                  // 本地备份区域
                  SliverToBoxAdapter(
                    child: _buildSectionHeader('本地备份', scheme),
                  ),
                  
                  // 本地备份统计
                  SliverToBoxAdapter(
                    child: _buildLocalBackupStats(scheme),
                  ),
                  
                  // 本地备份列表
                  _backups.isEmpty
                      ? SliverToBoxAdapter(
                          child: _buildEmptyState(scheme, '暂无本地备份'),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final backup = _backups[index];
                              return _buildBackupItem(backup, scheme, index == 0);
                            },
                            childCount: _backups.length,
                          ),
                        ),

                  // 云端其他备份区域
                  SliverToBoxAdapter(
                    child: _buildSectionHeader('云端其他备份', scheme),
                  ),
                  
                  // 云端备份说明
                  SliverToBoxAdapter(
                    child: _buildCloudBackupInfo(scheme),
                  ),
                  
                  // 云端备份列表
                  _buildCloudBackupList(scheme),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: scheme.textMediumColor,
        ),
      ),
    );
  }

  Widget _buildLocalBackupStats(ThemeScheme scheme) {
    return Container(
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
    );
  }

  Widget _buildCloudBackupInfo(ThemeScheme scheme) {
    if (!_isCloudLoggedIn) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: scheme.textLightColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '未登录云服务，请先登录以查看云端备份',
                style: TextStyle(color: scheme.textMediumColor),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.lightColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, 
                color: scheme.primaryColor, 
                size: 20
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '关于其他备份',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '这里显示其他设备上传到云端的备份。导入时会合并到当前数据，不会覆盖已有内容。',
            style: TextStyle(
              fontSize: 13,
              color: scheme.textMediumColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudBackupList(ThemeScheme scheme) {
    if (_isScanningCloud) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: CircularProgressIndicator(color: scheme.primaryColor),
          ),
        ),
      );
    }

    if (!_isCloudLoggedIn) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    if (_cloudBackups.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(scheme, '暂无其他云端备份'),
      );
    }

    // 过滤掉当前设备的备份（通常在其他列表中显示）
    final otherBackups = _cloudBackups.where((b) => !b.isCurrentDevice).toList();
    
    if (otherBackups.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(scheme, '暂无其他设备的云端备份'),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final backup = otherBackups[index];
          return _buildCloudBackupItem(backup, scheme);
        },
        childCount: otherBackups.length,
      ),
    );
  }

  Widget _buildEmptyState(ThemeScheme scheme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: scheme.lightColor,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: scheme.textLightColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupItem(Map<String, dynamic> backup, ThemeScheme scheme, bool isLatest) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
        border: isLatest
            ? Border.all(color: scheme.primaryColor.withValues(alpha: 0.5), width: 2)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isLatest
                ? scheme.primaryColor.withValues(alpha: 0.1)
                : scheme.lightColor.withValues(alpha: 0.3),
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
                  color: scheme.primaryColor.withValues(alpha: 0.1),
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

  Widget _buildCloudBackupItem(CloudBackupInfo backup, ThemeScheme scheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.cloud_download,
            color: scheme.primaryColor,
          ),
        ),
        title: Text(
          '设备备份 ${backup.folderName.substring(7)}', // 去掉 backup_ 前缀
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.textDarkColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            backup.isCurrentDevice ? '当前设备' : '其他设备',
            style: TextStyle(
              fontSize: 13,
              color: backup.isCurrentDevice 
                ? scheme.primaryColor 
                : scheme.textMediumColor,
            ),
          ),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () => _importCloudBackup(backup),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('导入'),
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}
