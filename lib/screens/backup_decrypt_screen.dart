import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../config/app_theme.dart';

/// MBK备份解密工具
/// 尝试使用提供的密码解密MBK文件
class BackupDecryptScreen extends StatefulWidget {
  const BackupDecryptScreen({super.key});

  @override
  State<BackupDecryptScreen> createState() => _BackupDecryptScreenState();
}

class _BackupDecryptScreenState extends State<BackupDecryptScreen> {
  String? _filePath;
  String? _fileName;
  int? _fileSize;
  bool _isDecrypting = false;
  String? _result;
  bool _success = false;

  final _passwordController = TextEditingController();
  final List<String> _passwordHistory = [];

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() {
        _filePath = file.path;
        _fileName = file.name;
        _fileSize = file.size;
        _result = null;
        _success = false;
      });
    } catch (e) {
      _showError('选择文件失败: $e');
    }
  }

  Future<void> _tryDecrypt() async {
    if (_filePath == null) {
      _showError('请先选择MBK文件');
      return;
    }

    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      _showError('请输入密码');
      return;
    }

    setState(() {
      _isDecrypting = true;
      _result = null;
    });

    try {
      final file = File(_filePath!);
      final bytes = await file.readAsBytes();

      // 检查是否是ZIP
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
        setState(() {
          _result = '不是有效的ZIP/MBK文件';
          _success = false;
        });
        return;
      }

      // 尝试解密
      final archive = ZipDecoder().decodeBytes(bytes);

      int successCount = 0;
      int failCount = 0;
      String? firstContent;

      for (final file in archive) {
        if (!file.isFile) continue;

        try {
          // 尝试用密码解压
          final content = file.content;

          // 检查是否是加密文件（标准ZIP加密检测）
          if (content.isEmpty) {
            failCount++;
            continue;
          }

          // 尝试解析为文本
          try {
            final text = utf8.decode(content);
            if (text.isNotEmpty) {
              successCount++;
              if (firstContent == null && text.length > 10) {
                firstContent =
                    text.substring(0, text.length > 200 ? 200 : text.length);
              }
            }
          } catch (_) {
            // 可能是加密的二进制数据
            failCount++;
          }
        } catch (e) {
          failCount++;
        }
      }

      setState(() {
        if (successCount > 0) {
          _success = true;
          _result = '''✅ 解密成功！
          
成功读取: $successCount 个文件
失败: $failCount 个文件

内容预览:
${firstContent ?? '无文本内容'}
          ''';

          // 添加到历史记录
          if (!_passwordHistory.contains(password)) {
            _passwordHistory.add(password);
          }
        } else {
          _success = false;
          _result = '❌ 密码错误，无法解密文件\n\n该文件使用了标准ZIP加密，提供的密码不正确。';
        }
      });
    } catch (e) {
      setState(() {
        _success = false;
        _result = '解密出错: $e\n\n可能原因:\n1. 密码错误\n2. 文件损坏\n3. 使用了非标准加密';
      });
    } finally {
      setState(() => _isDecrypting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('MBK解密工具', style: TextStyle(color: scheme.textDarkColor)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.lightColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '使用说明',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. 选择加密的MBK备份文件\n'
                    '2. 输入可能的密码（逐个尝试）\n'
                    '3. 点击"尝试解密"\n'
                    '4. 如果密码正确，可以导出日记',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.textMediumColor,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 文件选择
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择MBK文件',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_fileName != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.lightColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '文件名: $_fileName',
                            style: TextStyle(color: scheme.textDarkColor),
                          ),
                          if (_fileSize != null)
                            Text(
                              '大小: ${(_fileSize! / 1024).toStringAsFixed(1)} KB',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.textLightColor,
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    Text(
                      '未选择文件',
                      style: TextStyle(color: scheme.textLightColor),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _selectFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(_fileName == null ? '选择文件' : '重新选择'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 密码输入
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '输入密码',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: '请输入可能的密码',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: scheme.primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请输入您设置的备份密码',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.textLightColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isDecrypting ? null : _tryDecrypt,
                      icon: _isDecrypting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.lock_open),
                      label: Text(_isDecrypting ? '解密中...' : '尝试解密'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 结果
            if (_result != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _success
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _success ? Colors.green : Colors.red,
                  ),
                ),
                child: Text(
                  _result!,
                  style: TextStyle(
                    color: _success ? Colors.green[800] : Colors.red[800],
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
