import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/course_import/jwapp/jwapp_client.dart';
import '../services/course_import/jwapp/jwapp_endpoints.dart';
import '../services/course_import/jwapp/jwapp_response.dart';
import '../services/course_import/jwapp/jwapp_semester_parser.dart';

/// 教务系统登录 + 取数页
///
/// 分工很清楚：
/// - **用户**在页面里完成 CAS 登录（账号密码只经过学校自己的页面，App 不接触、不保存）
/// - **App** 只做一件事：用户点按钮后，在页面上下文里 `fetch` 两个接口，
///   把**响应原文**带回来。拆包与字段映射全部在 Dart 侧。
///
/// 取数按钮由用户手动触发（而不是自动检测登录成功）—— 教务系统的登录流程
/// 各校千差万别，与其猜「什么状态算登录好了」，不如让用户自己确认。
class JwappLoginScreen extends StatefulWidget {
  final JwappEndpoints endpoints;

  const JwappLoginScreen({super.key, required this.endpoints});

  @override
  State<JwappLoginScreen> createState() => _JwappLoginScreenState();
}

class _JwappLoginScreenState extends State<JwappLoginScreen> {
  InAppWebViewController? _controller;
  Completer<JwappFetchResult>? _pending;

  /// 当前这次取数期望命中的接口路径 —— 用来丢弃上一次超时后才姗姗来迟的旧回包
  String? _pendingPath;
  bool _busy = false;
  String? _error;
  String _hint = '登录教务系统，进入「我的课表」页面后点下方按钮';

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        title: Text('教务系统导入',
            style: TextStyle(color: scheme.textDarkColor, fontSize: 17)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
      ),
      body: Column(
        children: [
          _hintBar(scheme),
          Expanded(child: _buildWebView()),
          _bottomBar(scheme),
        ],
      ),
    );
  }

  // ===================== WebView =====================

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.endpoints.homeUrl)),
      initialSettings: buildJwappWebViewSettings(),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: JwappClient.handlerName,
          callback: _onJsMessage,
        );
      },
      onLoadStop: (controller, url) async {
        // 重写 viewport：桌面页锁定桌面布局宽度 + 双向可缩放
        await _applyViewportFix(controller);
        if (!mounted || _busy) return;
        final path = url?.path ?? '';
        if (path.contains('/jwapp/')) {
          setState(() => _hint = '已进入教务系统，确认停在课表页后点下方按钮');
        }
      },
    );
  }

  /// 注入「重写 viewport」脚本
  ///
  /// jwapp 是 SPA，路由切换时可能重设 viewport meta，脚本自身带短轮询兜住。
  Future<void> _applyViewportFix(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(
        source: JwappClient.buildViewportScript(),
      );
    } catch (_) {
      // 注入失败不影响取数：WebView 仍显示自带的缩放按钮
    }
  }

  void _onJsMessage(List<dynamic> args) {
    final result = JwappClient.parseMessage(args.isEmpty ? null : args.first);
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    // 回包里带着请求地址：对不上说明是上一次超时调用迟到很久的旧回包，丢掉
    final expected = _pendingPath;
    if (expected != null && !JwappClient.belongsTo(result, expected)) return;
    _pending = null;
    _pendingPath = null;
    pending.complete(result);
  }

  /// 结束当前等待（超时 / 脚本执行失败时调用）
  void _settle(Completer<JwappFetchResult> completer) {
    if (identical(_pending, completer)) {
      _pending = null;
      _pendingPath = null;
    }
  }

  // ===================== 取数 =====================

  Future<String?> _fetch({required String path, String? formBody}) async {
    final controller = _controller;
    if (controller == null) {
      _fail('网页还没加载完成，请稍候再试');
      return null;
    }

    final completer = Completer<JwappFetchResult>();
    _pending = completer;
    _pendingPath = path;
    try {
      await controller.evaluateJavascript(
        source: JwappClient.buildFetchScript(
          origin: widget.endpoints.origin,
          path: path,
          formBody: formBody,
        ),
      );
    } catch (e) {
      _settle(completer);
      _fail('无法在页面中执行取数脚本：$e');
      return null;
    }

    JwappFetchResult result;
    try {
      result = await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _settle(completer);
      _fail('读取超时。请确认已登录，并停留在「我的课表」页面');
      return null;
    }

    if (result.hasBody) {
      final body = result.body!.trimLeft();
      // 拿到 HTML 基本就是会话过期被踢回登录页
      if (body.startsWith('<')) {
        _fail('登录状态已失效，请在页面中重新登录后再试');
        return null;
      }
      return result.body;
    }
    _fail(result.error ?? '接口没有返回数据（HTTP ${result.status ?? '?'}）');
    return null;
  }

  Future<void> _startImport() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // 第一步：学期配置 —— 顺便拿到当前学期的 XNXQDM
      _setHint('正在读取学期信息…');
      final semesterBody = await _fetch(path: widget.endpoints.semesterPath);
      if (semesterBody == null) return;

      String? semesterCode;
      try {
        final semesters = JwappSemesterParser.parseAll(
          semesterBody,
          tableKey: widget.endpoints.semesterTableKey,
        );
        semesterCode = JwappSemesterParser.pickCurrent(semesters)?.code;
      } catch (_) {
        // 学期配置读不出来不致命：课表接口不传参数时会返回默认学期
        semesterCode = null;
      }

      // 第二步：课表
      _setHint('正在读取课表…');
      var courseBody = await _fetch(
        path: widget.endpoints.courseTablePath,
        formBody: semesterCode == null ? null : 'XNXQDM=$semesterCode',
      );
      if (courseBody == null) return;

      // 兜底：带了学期码却一条课都没查到，说明学期判定落到了脏数据上
      // （教务系统学期表里确实存在这样的行）。退回不带参数再取一次 ——
      // 接口默认返回当前学期。宁可多一次请求，也别让用户看到「这学期没课」。
      if (semesterCode != null &&
          !_hasCourseRows(courseBody, widget.endpoints.courseTableKey)) {
        _setHint('按学期码未查到课表，改用默认学期重试…');
        final retry = await _fetch(path: widget.endpoints.courseTablePath);
        if (retry != null &&
            _hasCourseRows(retry, widget.endpoints.courseTableKey)) {
          courseBody = retry;
        }
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        JwappImportData(courseBody: courseBody, semesterBody: semesterBody),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setHint(String text) {
    if (!mounted) return;
    setState(() => _hint = text);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  /// 响应里是否真的有课表记录（用于判断学期码是否可用）
  ///
  /// 表名 [tableKey] 为 null 时由响应自动发现，与导入解析走同一套规则。
  static bool _hasCourseRows(String body, String? tableKey) {
    try {
      return JwappResponse.unwrapRows(body, key: tableKey).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ===================== UI 片段 =====================

  Widget _hintBar(ThemeScheme scheme) {
    final hasError = _error != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: hasError
          ? scheme.warningColor.withValues(alpha: 0.12)
          : scheme.primaryColor.withValues(alpha: 0.1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasError ? Icons.error_outline : Icons.lightbulb_outline,
            size: 16,
            color: hasError ? scheme.warningColor : scheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error ?? _hint,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: hasError ? scheme.warningColor : scheme.textDarkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(ThemeScheme scheme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.endpoints.name,
              style: TextStyle(fontSize: 11, color: scheme.textLightColor),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _busy ? null : _startImport,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('读取课表数据',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 教务系统页面的 WebView 设置
///
/// **默认桌面模式**：教务系统（ehall / jwapp）是面向桌面的 SPA，用移动 UA
/// 打开时页面会走移动端布局、课表页显示不正常，所以这里内置桌面模式：
///
/// - `userAgent` 换成桌面 Chrome，让服务端下发桌面版页面；
/// - `preferredContentMode` 设成 DESKTOP（iOS/WKWebView 生效，Android 忽略）
///   —— iOS 上单改 UA 未必能切到桌面布局，这个开关才是官方途径；
/// - `useWideViewPort` 打开：让 WebView 尊重页面自己的 viewport meta，
///   布局宽度由 [JwappClient.buildViewportScript] 注入的脚本钉在桌面宽度
///   （否则页面写的 `width=device-width` 会把桌面布局挤成移动布局）；
/// - **`loadWithOverviewMode` 必须关掉**（2026-09-30 真机反馈修正）：
///   它会把「铺满宽度」的那个缩放当成**缩放下限**，于是用户只能放大、
///   缩不回去。关掉之后由注入脚本的 `initial-scale` 负责「打开即铺满」、
///   `minimum-scale` 给出缩小余量，两个方向都能调；
/// - `supportZoom` + `builtInZoomControls` + `displayZoomControls` 打开并**显示**
///   +/- 按钮 —— 桌面版字号偏小，得有个看得见、点得到的缩放入口；
/// - `thirdPartyCookiesEnabled` 打开：部分学校的 CAS 登录是嵌在 iframe 里的，
///   没有第三方 Cookie 会登录失败。
///
/// 抽成顶层函数是为了能被单测覆盖 —— 防止哪次改动把桌面模式或缩放弄丢。
InAppWebViewSettings buildJwappWebViewSettings() {
  return InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    useHybridComposition: true,
    userAgent: JwappClient.desktopUserAgent,
    preferredContentMode: UserPreferredContentMode.DESKTOP,
    useWideViewPort: true,
    loadWithOverviewMode: false,
    supportZoom: true,
    builtInZoomControls: true,
    displayZoomControls: true,
    thirdPartyCookiesEnabled: true,
    mediaPlaybackRequiresUserGesture: true,
  );
}
