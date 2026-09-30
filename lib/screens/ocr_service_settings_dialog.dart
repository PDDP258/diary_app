import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/course_import/ocr/ocr_client.dart';

/// 识别服务（云函数）配置弹窗
///
/// 用户要填两样东西：云函数 URL（必填）、应用密钥（与云函数环境变量 APP_KEY 一致）。
/// 部署步骤见仓库内 `cloud/ocr-proxy/README.md`。
Future<bool> showOcrServiceSettingsDialog(BuildContext context) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const _OcrServiceDialog(),
  );
  return saved == true;
}

class _OcrServiceDialog extends StatefulWidget {
  const _OcrServiceDialog();

  @override
  State<_OcrServiceDialog> createState() => _OcrServiceDialogState();
}

class _OcrServiceDialogState extends State<_OcrServiceDialog> {
  final _endpointController = TextEditingController();
  final _appKeyController = TextEditingController();
  bool _obscureKey = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final endpoint = await OcrServiceConfig.endpoint();
    final appKey = await OcrServiceConfig.appKey();
    if (!mounted) return;
    setState(() {
      _endpointController.text = endpoint;
      _appKeyController.text = appKey;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _appKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final endpoint = _endpointController.text.trim();
    if (endpoint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写云函数 URL')));
      return;
    }
    if (!endpoint.startsWith('http://') && !endpoint.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('地址要以 http:// 或 https:// 开头')));
      return;
    }
    await OcrServiceConfig.save(
      endpoint: endpoint,
      appKey: _appKeyController.text,
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return AlertDialog(
      backgroundColor: scheme.cardColor,
      title: Text('识别服务设置', style: TextStyle(color: scheme.textDarkColor)),
      content: _loading
          ? const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '图片识别走你自部署的腾讯云函数中转，'
                    '腾讯云密钥只存在云函数里，不会进 App。\n'
                    '部署步骤见项目内 cloud/ocr-proxy/README.md。',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: scheme.textLightColor),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _endpointController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '云函数 URL',
                      hintText: 'https://xxxx.ap-guangzhou.tencentscf.com',
                      hintStyle: TextStyle(
                          fontSize: 12, color: scheme.textLightColor),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _appKeyController,
                    obscureText: _obscureKey,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '应用密钥（可选，与云函数 APP_KEY 一致）',
                      hintStyle: TextStyle(
                          fontSize: 12, color: scheme.textLightColor),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('取消', style: TextStyle(color: scheme.textLightColor)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.primaryColor),
          onPressed: _loading ? null : _save,
          child: const Text('保存', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
