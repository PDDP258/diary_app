import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../services/app_lock_service.dart';
import '../widgets/pattern_lock.dart';
import 'main_screen.dart';

/// 应用锁解锁页面
///
/// 在启动时显示，验证通过后才能进入主界面
class AppLockScreen extends StatefulWidget {
  /// 是否是首次设置
  final bool isSetup;

  /// 设置完成回调
  final VoidCallback? onSetupComplete;

  /// 取消设置回调
  final VoidCallback? onSetupCancel;

  const AppLockScreen({
    super.key,
    this.isSetup = false,
    this.onSetupComplete,
    this.onSetupCancel,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with SingleTickerProviderStateMixin {
  final PatternLockController _patternController = PatternLockController();

  String _message = '请输入手势密码';
  bool _showError = false;
  bool _isVerifying = false;

  // 设置模式用的临时密码
  List<int>? _tempPattern;
  final bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    // 沉浸式状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题栏
            if (widget.isSetup)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        widget.onSetupCancel?.call();
                        Navigator.pop(context);
                      },
                      icon: Icon(Icons.close, color: scheme.textDarkColor),
                    ),
                    const Spacer(),
                    Text(
                      '设置应用锁',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // 平衡布局
                  ],
                ),
              ),

            const Spacer(),

            // 图标和标题
            Icon(
              Icons.lock_outline,
              size: 64,
              color: scheme.primaryColor,
            ),
            const SizedBox(height: 24),
            Text(
              widget.isSetup ? '设置手势密码' : '小记日记',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isSetup ? '请连接至少4个点' : '快速记录生活点滴',
              style: TextStyle(
                fontSize: 14,
                color: scheme.textMediumColor,
              ),
            ),

            const SizedBox(height: 48),

            // 九宫格密码
            PatternLock(
              controller: _patternController,
              onPatternCompleted: _onPatternCompleted,
              onPatternUpdate: _onPatternUpdate,
              showError: _showError,
              message: _message,
              primaryColor: scheme.primaryColor,
              errorColor: Colors.red,
              autoResetDelay: widget.isSetup ? 0 : 1000,
              onReset: () {
                setState(() {
                  _showError = false;
                });
              },
            ),

            const Spacer(),

            // 底部按钮
            if (widget.isSetup && _tempPattern != null && !_isConfirming)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _tempPattern = null;
                            _message = '请设置手势密码';
                            _patternController.reset();
                          });
                        },
                        child: Text(
                          '重试',
                          style: TextStyle(color: scheme.textMediumColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => _confirmPattern(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '确认',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (!widget.isSetup)
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: TextButton(
                  onPressed: _showForgotPasswordDialog,
                  child: Text(
                    '忘记密码？',
                    style: TextStyle(
                      color: scheme.textLightColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onPatternUpdate(List<int> pattern) {
    setState(() {
      _showError = false;
    });
  }

  void _onPatternCompleted(List<int> pattern) async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
    });

    if (widget.isSetup) {
      await _handleSetupPattern(pattern);
    } else {
      await _handleUnlockPattern(pattern);
    }

    setState(() {
      _isVerifying = false;
    });
  }

  /// 处理设置模式
  Future<void> _handleSetupPattern(List<int> pattern) async {
    if (pattern.length < 4) {
      setState(() {
        _showError = true;
        _message = '至少需要连接4个点';
      });
      return;
    }

    if (_tempPattern == null) {
      // 第一次输入
      setState(() {
        _tempPattern = pattern;
        _message = '请再次确认密码';
      });
      _patternController.reset();
    } else {
      // 确认输入
      _confirmPattern();
    }
  }

  /// 确认密码
  void _confirmPattern() async {
    if (_tempPattern == null) return;

    final currentPattern = _patternController.pattern;

    // 比较两次输入
    bool match = true;
    if (currentPattern.length != _tempPattern!.length) {
      match = false;
    } else {
      for (int i = 0; i < currentPattern.length; i++) {
        if (currentPattern[i] != _tempPattern![i]) {
          match = false;
          break;
        }
      }
    }

    if (match) {
      // 保存密码
      final success = await AppLockService.setPattern(_tempPattern!);
      if (success && mounted) {
        // 自动生成并保存备份图片（不询问用户）
        await _autoGenerateAndSaveBackup(_tempPattern!);
      }
    } else {
      setState(() {
        _showError = true;
        _message = '两次输入不一致，请重试';
        _tempPattern = null;
      });
      _patternController.reset();
    }
  }

  /// 自动生成备份图片并显示预览
  Future<void> _autoGenerateAndSaveBackup(List<int> pattern) async {
    try {
      final scheme = AppTheme.schemeOf(context);
      final colorScheme = ColorScheme.light(
        primary: scheme.primaryColor,
        surface: scheme.backgroundColor,
        onSurface: scheme.textDarkColor,
        onPrimary: Colors.white,
      );

      debugPrint('开始生成手势密码备份图片...');

      // 生成备份图片
      final imageBytes = await AppLockService.generateBackupImage(
        pattern,
        colorScheme: colorScheme,
      );

      if (imageBytes == null) {
        debugPrint('生成备份图片失败: imageBytes 为 null');
        // 继续完成设置，只是没有备份图片
        _showBackupResultDialog(null);
        return;
      }

      debugPrint('备份图片生成成功，大小: ${imageBytes.length} bytes');

      // 保存备份图片
      final path = await AppLockService.saveBackupImage(imageBytes);

      if (path == null) {
        debugPrint('保存备份图片失败: path 为 null');
        _showBackupResultDialog(null);
        return;
      }

      debugPrint('备份图片保存成功: $path');

      // 显示备份结果对话框（带预览）
      if (mounted) {
        _showBackupResultDialog(path, imageBytes: imageBytes);
      }
    } catch (e, stackTrace) {
      debugPrint('自动生成备份图片失败: $e');
      debugPrint('堆栈: $stackTrace');
      if (mounted) {
        _showBackupResultDialog(null);
      }
    }
  }

  /// 显示备份结果对话框（带图片预览）
  void _showBackupResultDialog(String? path, {Uint8List? imageBytes}) {
    final scheme = AppTheme.schemeOf(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          path != null ? '密码备份已保存' : '密码设置成功',
          style: TextStyle(color: scheme.textDarkColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (path != null && imageBytes != null) ...[
              // 图片预览
              Container(
                width: 200,
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.lightColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '备份图片已保存到应用私有目录',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '忘记密码时，可在登录页点击"忘记密码"查看此备份',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // 保存失败提示
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '密码已设置，但备份图片保存失败。建议牢记您的密码图案。',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onSetupComplete?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  /// 处理解锁模式
  Future<void> _handleUnlockPattern(List<int> pattern) async {
    final isValid = AppLockService.verifyPattern(pattern);

    if (isValid) {
      // 解锁成功
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const MainScreen(),
          ),
        );
      }
    } else {
      setState(() {
        _showError = true;
        _message = '密码错误，请重试';
      });
    }
  }

  /// 显示忘记密码对话框（只显示路径，不显示图片内容以保证安全）
  void _showForgotPasswordDialog() {
    final scheme = AppTheme.schemeOf(context);
    final backupPath = AppLockService.backupImagePath;
    final hasBackup = backupPath != null && File(backupPath).existsSync();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('忘记密码？', style: TextStyle(color: scheme.textDarkColor)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasBackup) ...[
                // 安全提示
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '已找到密码备份图片。请复制路径到文件管理器中查看。',
                          style: TextStyle(
                              fontSize: 14, color: Colors.blue[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 文件路径（可复制）
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.lightColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '备份文件路径：',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.textLightColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              backupPath!,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.textMediumColor,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 复制按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: backupPath));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('路径已复制到剪贴板'),
                          backgroundColor: scheme.primaryColor,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icon(Icons.copy, size: 18),
                    label: const Text('复制路径'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '提示：使用文件管理器打开此路径查看备份图片',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.textLightColor,
                  ),
                ),
              ] else ...[
                // 无备份提示
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber,
                              color: Colors.orange, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '未找到备份图片',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '您没有保存密码备份图片。如果忘记密码，将无法恢复数据。建议关闭应用锁后重新设置。',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textMediumColor,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!hasBackup)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showDisableLockConfirmDialog();
              },
              child: Text('关闭应用锁',
                  style: TextStyle(color: Colors.red[400])),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭', style: TextStyle(color: scheme.textLightColor)),
          ),
        ],
      ),
    );
  }

  /// 显示关闭应用锁确认对话框
  void _showDisableLockConfirmDialog() {
    final scheme = AppTheme.schemeOf(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认关闭应用锁？',
            style: TextStyle(color: scheme.textDarkColor)),
        content: Text(
          '关闭应用锁将清除当前密码设置。关闭后您可以重新设置新的手势密码。',
          style: TextStyle(color: scheme.textMediumColor, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: scheme.textLightColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await AppLockService.disable();
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('应用锁已关闭'),
                    backgroundColor: scheme.primaryColor,
                  ),
                );
                // 退出到主界面
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const MainScreen(),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400],
              foregroundColor: Colors.white,
            ),
            child: const Text('确认关闭'),
          ),
        ],
      ),
    );
  }
}
