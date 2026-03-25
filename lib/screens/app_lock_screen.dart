import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/app_lock_service.dart';
import '../services/biometric_auth_service.dart';
import '../widgets/pattern_lock.dart';
import 'main_screen.dart';

/// 应用锁解锁页面
/// 
/// 支持两种解锁方式：
/// 1. 生物识别（指纹/面容）- 如果启用
/// 2. 手势密码 - 始终可用
/// 
/// 对于红米K60等光学屏下指纹设备：
/// - 系统会自动在屏幕上显示指纹图标
/// - 用户触摸指纹区域即可识别
class AppLockScreen extends StatefulWidget {
  final bool isSetup;
  final VoidCallback? onSetupComplete;
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
    with WidgetsBindingObserver {
  final PatternLockController _patternController = PatternLockController();

  String _message = '请输入手势密码';
  bool _showError = false;
  bool _isVerifying = false;
  bool _isLoading = true;

  List<int>? _tempPattern;

  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _biometricVerified = false;
  int _biometricFailedCount = 0;
  static const int _maxBiometricFailures = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _initialize() async {
    await BiometricAuthService.initialize();
    final available = await BiometricAuthService.hasAvailableBiometrics();

    if (mounted) {
      setState(() {
        _biometricEnabled = BiometricAuthService.isEnabled;
        _biometricAvailable = available;
        _isLoading = false;
      });
    }

    // 【关键】如果启用了指纹，在界面渲染后自动触发
    // 注意：这需要MainActivity继承FlutterFragmentActivity
    if (!widget.isSetup && _biometricEnabled && _biometricAvailable) {
      // 使用post-frame回调确保界面已渲染
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 延迟500ms确保页面完全显示
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted &&
              !_biometricVerified &&
              _biometricFailedCount < _maxBiometricFailures) {
            debugPrint('[AppLock] 界面就绪，触发指纹验证');
            _authenticateWithBiometric();
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final showBiometricFirst = !widget.isSetup &&
        _biometricEnabled &&
        _biometricAvailable &&
        !_biometricVerified;

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: showBiometricFirst
                    ? _buildBiometricStep(scheme)
                    : _buildPatternStep(scheme),
              ),
      ),
    );
  }

  /// 构建生物识别验证步骤
  /// 
  /// 安全设计：
  /// - 初始不显示"使用手势密码"入口（防止他人看到）
  /// - 失败后（_biometricFailedCount > 0）才显示备用入口
  /// - 失败3次后强制显示入口
  Widget _buildBiometricStep(ThemeScheme scheme) {
    // 失败超过3次后强制显示入口
    final forceShowPattern = _biometricFailedCount >= _maxBiometricFailures;
    // 失败至少1次后显示入口（但不超过3次时仍可继续指纹）
    final canShowPattern = _biometricFailedCount > 0;

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // 锁图标
          Icon(
            Icons.lock_outline,
            size: 72,
            color: scheme.primaryColor,
          ),
          const SizedBox(height: 24),

          // 应用名称
          Text(
            '小记日记',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: scheme.textDarkColor,
            ),
          ),
          const SizedBox(height: 16),

          // 状态文字
          if (_isVerifying)
            Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  '请将手指放在屏幕指纹区域',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.textMediumColor,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '等待系统指纹验证...',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.primaryColor,
                    ),
                  ),
                ),
              ],
            )
          else if (_biometricFailedCount > 0)
            Text(
              forceShowPattern
                  ? '验证失败 $_biometricFailedCount 次，请使用手势密码'
                  : '验证失败，请重试',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: forceShowPattern ? Colors.red : scheme.textMediumColor,
              ),
            ),

          const Spacer(flex: 3),

          // 底部操作
          // 安全设计：失败至少1次后才显示"使用手势密码"入口
          if (canShowPattern || forceShowPattern)
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Column(
                children: [
                  // 失败后提供重试按钮（仅当未超过最大次数）
                  if (!forceShowPattern)
                    ElevatedButton(
                      onPressed: _authenticateWithBiometric,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Text('重试指纹验证'),
                    ),
                  const SizedBox(height: 16),
                  // 使用手势密码入口（失败后显示）
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _biometricVerified = true;
                        _message = '请输入手势密码';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: scheme.lightColor.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '使用手势密码',
                        style: TextStyle(
                          color: scheme.textLightColor,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            // 初始状态：只显示提示，不显示备用入口
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Text(
                '等待指纹验证...',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.textLightColor.withOpacity(0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建手势密码验证步骤
  Widget _buildPatternStep(ThemeScheme scheme) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(flex: 1),

          Icon(
            Icons.lock_outline,
            size: 64,
            color: scheme.primaryColor,
          ),
          const SizedBox(height: 24),

          Text(
            widget.isSetup ? '设置手势密码' : '小记日记',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: scheme.textDarkColor,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            widget.isSetup ? '请连接至少4个点' : '请输入手势密码',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: scheme.textMediumColor,
            ),
          ),

          const SizedBox(height: 48),

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

          const Spacer(flex: 2),

          if (widget.isSetup && _tempPattern != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
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
            )
          else
            const SizedBox(height: 32),
        ],
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

  Future<void> _handleSetupPattern(List<int> pattern) async {
    if (pattern.length < 4) {
      setState(() {
        _showError = true;
        _message = '至少需要连接4个点';
      });
      return;
    }

    if (_tempPattern == null) {
      setState(() {
        _tempPattern = pattern;
        _message = '请再次确认密码';
      });
      _patternController.reset();
    } else {
      _confirmPattern();
    }
  }

  void _confirmPattern() async {
    if (_tempPattern == null) return;

    final currentPattern = _patternController.pattern;

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
      final success = await AppLockService.setPattern(_tempPattern!);
      if (success && mounted) {
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

  Future<void> _autoGenerateAndSaveBackup(List<int> pattern) async {
    try {
      final scheme = AppTheme.schemeOf(context);
      final colorScheme = ColorScheme.light(
        primary: scheme.primaryColor,
        surface: scheme.backgroundColor,
        onSurface: scheme.textDarkColor,
        onPrimary: Colors.white,
      );

      final imageBytes = await AppLockService.generateBackupImage(
        pattern,
        colorScheme: colorScheme,
      );

      if (imageBytes == null) {
        _showBackupResultDialog(null);
        return;
      }

      final path = await AppLockService.saveBackupImage(imageBytes);

      if (mounted) {
        _showBackupResultDialog(path, imageBytes: imageBytes);
      }
    } catch (e) {
      if (mounted) {
        _showBackupResultDialog(null);
      }
    }
  }

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
            ] else ...[
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

  Future<void> _handleUnlockPattern(List<int> pattern) async {
    final isValid = AppLockService.verifyPattern(pattern);

    if (isValid) {
      _unlockSuccess();
    } else {
      setState(() {
        _showError = true;
        _message = '密码错误，请重试';
      });
    }
  }

  Future<void> _authenticateWithBiometric() async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
    });

    debugPrint('[AppLock] 调用生物识别...');

    try {
      final success = await BiometricAuthService.authenticate();

      debugPrint('[AppLock] 生物识别结果: $success');

      if (mounted) {
        if (success) {
          // 指纹验证成功，直接解锁进入软件
          debugPrint('[AppLock] 指纹验证成功，直接解锁');
          _unlockSuccess();
        } else {
          setState(() {
            _isVerifying = false;
            _biometricFailedCount++;
          });
        }
      }
    } catch (e) {
      debugPrint('[AppLock] 生物识别异常: $e');
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _biometricFailedCount++;
        });
      }
    }
  }

  void _unlockSuccess() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const MainScreen(),
        ),
      );
    }
  }

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
                          style: TextStyle(fontSize: 14, color: Colors.blue[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                      Text(
                        backupPath,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.textMediumColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
              ] else ...[
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
                          Icon(Icons.warning_amber, color: Colors.orange, size: 24),
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
              child: Text('关闭应用锁', style: TextStyle(color: Colors.red[400])),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭', style: TextStyle(color: scheme.textLightColor)),
          ),
        ],
      ),
    );
  }

  void _showDisableLockConfirmDialog() {
    final scheme = AppTheme.schemeOf(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认关闭应用锁？', style: TextStyle(color: scheme.textDarkColor)),
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
