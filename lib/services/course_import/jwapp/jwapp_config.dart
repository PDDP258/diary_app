/// jwapp 接入点的本地持久化
///
/// 存的是 [JwappEndpoints]（学校名 + 入口地址 + 模块路径），
/// 不含任何账号密码 —— 登录态由 WebView 自己的 Cookie 存储持有。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'jwapp_endpoints.dart';

class JwappConfig {
  static const _endpointsKey = 'course_jwapp_endpoints';

  /// 读取已选学校；未配置或数据损坏时返回 null
  static Future<JwappEndpoints?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_endpointsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final ep = JwappEndpoints.fromMap(Map<String, dynamic>.from(decoded));
      return ep.isValid ? ep : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(JwappEndpoints endpoints) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_endpointsKey, jsonEncode(endpoints.toMap()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_endpointsKey);
  }
}
