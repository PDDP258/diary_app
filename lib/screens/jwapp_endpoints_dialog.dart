import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/course_import/jwapp/jwapp_endpoints.dart';

/// 选择教务系统接入点。返回 null 表示用户取消。
Future<JwappEndpoints?> showJwappEndpointsDialog(
  BuildContext context, {
  JwappEndpoints? current,
}) {
  return showModalBottomSheet<JwappEndpoints>(
    context: context,
    backgroundColor: AppTheme.schemeOf(context).cardColor,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _JwappEndpointsSheet(current: current),
  );
}

class _JwappEndpointsSheet extends StatefulWidget {
  final JwappEndpoints? current;

  const _JwappEndpointsSheet({this.current});

  @override
  State<_JwappEndpointsSheet> createState() => _JwappEndpointsSheetState();
}

class _JwappEndpointsSheetState extends State<_JwappEndpointsSheet> {
  final _input = TextEditingController();
  bool _custom = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '选择教务系统',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                '导入需要你在应用内登录学校门户（账号密码只经过学校页面，应用不保存）',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: scheme.textMediumColor,
                ),
              ),
            ),
            ...JwappEndpoints.presets.map(
              (ep) => ListTile(
                leading: Icon(Icons.school_outlined, color: scheme.primaryColor),
                title: Text(ep.name,
                    style: TextStyle(fontSize: 15, color: scheme.textDarkColor)),
                subtitle: Text(ep.host,
                    style: TextStyle(
                        fontSize: 12, color: scheme.textMediumColor)),
                trailing: widget.current?.name == ep.name
                    ? Icon(Icons.check_circle, size: 18, color: scheme.primaryColor)
                    : null,
                onTap: () => Navigator.pop(context, ep),
              ),
            ),
            if (!_custom)
              ListTile(
                leading: Icon(Icons.edit_outlined, color: scheme.textMediumColor),
                title: Text('其它学校',
                    style: TextStyle(fontSize: 15, color: scheme.textDarkColor)),
                subtitle: Text('手动填学校门户地址（需同为 jwapp 系统）',
                    style: TextStyle(
                        fontSize: 12, color: scheme.textMediumColor)),
                onTap: () => setState(() => _custom = true),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _input,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      style: TextStyle(fontSize: 14, color: scheme.textDarkColor),
                      decoration: InputDecoration(
                        hintText: '例如 ehall.xxx.edu.cn',
                        hintStyle: TextStyle(
                            fontSize: 13, color: scheme.textLightColor),
                        errorText: _error,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: (_) => _submitCustom(),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primaryColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _submitCustom,
                      child: const Text('使用这个地址',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _submitCustom() {
    final ep = JwappEndpoints.fromHostInput(_input.text);
    if (ep == null) {
      setState(() => _error = '地址格式不正确');
      return;
    }
    Navigator.pop(context, ep);
  }
}
