import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/encryption_service.dart';

/// 备份加密测试页面
class BackupTestScreen extends StatefulWidget {
  const BackupTestScreen({super.key});

  @override
  State<BackupTestScreen> createState() => _BackupTestScreenState();
}

class _BackupTestScreenState extends State<BackupTestScreen> {
  final _keyController = TextEditingController();
  final _dataController = TextEditingController();
  String _result = '';
  String _currentKey = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentKey();
  }

  Future<void> _loadCurrentKey() async {
    final key = await EncryptionService.getCloudBackupKey();
    setState(() {
      _currentKey = key ?? '未设置';
    });
  }

  Future<void> _testEncrypt() async {
    try {
      final data = _dataController.text;
      if (data.isEmpty) {
        setState(() => _result = '错误: 请输入要加密的数据');
        return;
      }

      final encrypted = await EncryptionService.encryptWithCloudKey(data);
      setState(() => _result = '加密成功:\n$encrypted');
    } catch (e) {
      setState(() => _result = '加密失败: $e');
    }
  }

  Future<void> _testDecrypt() async {
    try {
      final encrypted = _dataController.text;
      final key = _keyController.text.trim().replaceAll(RegExp(r'\s+'), '');
      
      if (encrypted.isEmpty) {
        setState(() => _result = '错误: 请输入要解密的数据');
        return;
      }
      if (key.isEmpty) {
        setState(() => _result = '错误: 请输入密钥');
        return;
      }

      setState(() => _result = '正在解密...');
      
      final decrypted = await EncryptionService.decryptWithCloudKey(encrypted, key);
      
      if (decrypted == null) {
        setState(() => _result = '解密失败: 返回null\n\n可能原因:\n1. 密钥不正确\n2. 密文格式错误\n3. 密文被篡改');
      } else {
        setState(() => _result = '解密成功:\n$decrypted');
      }
    } catch (e) {
      setState(() => _result = '解密异常: $e');
    }
  }

  Future<void> _importKey() async {
    try {
      final key = _keyController.text.trim().replaceAll(RegExp(r'\s+'), '');
      if (key.isEmpty) {
        setState(() => _result = '错误: 密钥为空');
        return;
      }

      final success = await EncryptionService.importCloudBackupKey(key);
      if (success) {
        await _loadCurrentKey();
        setState(() => _result = '密钥导入成功');
      } else {
        setState(() => _result = '密钥导入失败');
      }
    } catch (e) {
      setState(() => _result = '导入异常: $e');
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
        title: Text('备份加密测试', style: TextStyle(color: scheme.textDarkColor)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 当前密钥
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前设备密钥:', style: TextStyle(color: scheme.textMediumColor)),
                  const SizedBox(height: 8),
                  Text(
                    _currentKey,
                    style: TextStyle(
                      color: scheme.textDarkColor,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 密钥输入
            TextField(
              controller: _keyController,
              decoration: InputDecoration(
                labelText: '密钥（用于解密/导入）',
                hintText: '粘贴密钥 here',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: () async {
                    // 粘贴功能
                  },
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _importKey,
                    child: const Text('导入为新设备密钥'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 数据输入
            TextField(
              controller: _dataController,
              decoration: const InputDecoration(
                labelText: '数据（要加密的明文或密文）',
                hintText: '{"diaries": [...]} 或 __CLOUD__xxx',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 16),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _testEncrypt,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primaryColor,
                    ),
                    child: const Text('测试加密'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _testDecrypt,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.darkColor,
                    ),
                    child: const Text('测试解密'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 结果显示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('结果:', style: TextStyle(color: scheme.textMediumColor)),
                  const SizedBox(height: 8),
                  Text(
                    _result,
                    style: TextStyle(color: scheme.textDarkColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
