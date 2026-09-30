/// jwapp 取数：注入脚本生成 + 回传结果解析
///
/// 取数不走原生 HTTP 客户端：接口要 CAS 登录态，而登录发生在 WebView 里，
/// 只有页面上下文的 `fetch`（`credentials: 'include'`）才带得上 Cookie。
/// 所以这里只做两件事：
/// 1. 生成一段极短的 JS，在页面里 POST 接口并把**响应原文**回传；
/// 2. 把回传的 JSON 字符串还原成 [JwappFetchResult]。
///
/// 解析（拆包、字段映射）全部在 Dart 侧 —— JS 里不写业务逻辑。
library;

import 'dart:convert';

/// 一次注入取数的结果
class JwappFetchResult {
  final bool ok;
  final String url;
  final String? body;
  final String? error;
  final int? status;

  const JwappFetchResult({
    required this.ok,
    required this.url,
    this.body,
    this.error,
    this.status,
  });

  bool get hasBody => ok && (body?.trim().isNotEmpty ?? false);
}

class JwappClient {
  /// Dart 侧注册的回传通道名，须与 [buildFetchScript] 里一致
  static const handlerName = 'onJwappData';

  /// 登录/取数页面使用的**桌面版** User-Agent
  ///
  /// 教务系统（ehall / jwapp）是面向桌面的 SPA：用移动 UA 打开时，页面会走
  /// 移动端布局甚至是另一套入口，课表页常常显示不正常。所以内置默认桌面模式。
  ///
  /// 这里写死一个主流桌面 Chrome UA，而不去改写真实 UA —— 真实 UA 里带着
  /// WebView 的 Chrome 版本号，各机型不一致，学校端的兼容判断反而容易出岔子。
  static const desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// 生成取数脚本
  ///
  /// [origin] 用门户源而不是 `location.origin`：用户在哪个子页面点的按钮
  /// 都能命中正确地址（万一被弹到 CAS 域也不会打歪）。
  static String buildFetchScript({
    required String origin,
    required String path,
    String? formBody,
  }) {
    final url = '$origin$path';
    final bodyLine = formBody == null ? '' : 'body: ${jsonEncode(formBody)},';
    return '''
(function () {
  var target = ${jsonEncode(url)};
  function send(extra) {
    extra.url = target;
    var text = JSON.stringify(extra);
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('$handlerName', text);
      }
    } catch (e) { /* handler 未就绪：Dart 侧会走超时分支并提示 */ }
  }
  try {
    fetch(target, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      $bodyLine
    }).then(function (r) {
      return r.text().then(function (t) {
        send({ ok: true, status: r.status, body: t });
      });
    }).catch(function (e) {
      send({ ok: false, error: String(e) });
    });
  } catch (e) {
    send({ ok: false, error: String(e) });
  }
})();
''';
  }

  /// 桌面布局宽度：页面自己没有声明宽度时按这个宽度排版。
  ///
  /// 1280 是常见桌面站点的布局宽度；调小会让桌面布局被挤变形，
  /// 调大则在一屏内能看到的有效内容更少。
  static const desktopLayoutWidth = 1280;

  /// 生成「重写 viewport」脚本
  ///
  /// 要同时满足两件互相拉扯的事：
  ///
  /// 1. **保住桌面布局**：`useWideViewPort` 会让 WebView 尊重页面自己的
  ///    `<meta name="viewport">`，而教务页面普遍写着 `width=device-width` ——
  ///    于是桌面版页面被挤成移动布局。所以把布局宽度钉在 [desktopLayoutWidth]。
  /// 2. **能放大也能缩小**：`loadWithOverviewMode` 会把「铺满宽度」的那个缩放
  ///    当成缩放下限，结果只能放大、缩不回去（2026-09-30 真机反馈）。
  ///    所以要关掉它，改由这里用 `initial-scale` 负责「打开即铺满」、
  ///    用 `minimum-scale` 给出缩小余量。
  ///
  /// 页面自己声明了数字宽度时**尊重它的值**，只在它写 `device-width` 或没写时
  /// 才套用桌面宽度 —— 免得把本来就按固定宽度设计的老页面顶变形。
  ///
  /// 每次执行都是**整串覆盖**（不往原值后面追加），所以短轮询反复执行
  /// 也不会让 content 越滚越长。
  static String buildViewportScript() => '''
(function () {
  var DESKTOP_WIDTH = $desktopLayoutWidth;
  function fix() {
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    var content = meta ? (meta.getAttribute('content') || '') : '';
    var declared = content.match(/width\\s*=\\s*([0-9]+)/i);
    var layoutWidth = declared ? parseInt(declared[1], 10) : DESKTOP_WIDTH;
    if (!(layoutWidth > 0)) layoutWidth = DESKTOP_WIDTH;
    var deviceWidth =
      (window.screen && window.screen.width) ? window.screen.width : 400;
    var fit = Math.min(1, deviceWidth / layoutWidth);
    var min = Math.max(0.15, fit * 0.5);
    var next = 'width=' + layoutWidth +
      ', initial-scale=' + fit.toFixed(4) +
      ', minimum-scale=' + min.toFixed(4) +
      ', maximum-scale=5.0, user-scalable=yes';
    if (meta && meta.getAttribute('content') === next) return;
    if (!meta) {
      meta = document.createElement('meta');
      meta.setAttribute('name', 'viewport');
      head.appendChild(meta);
    }
    meta.setAttribute('content', next);
  }
  fix();
  if (document.readyState !== 'complete') {
    document.addEventListener('DOMContentLoaded', fix);
  }
  var n = 0;
  var timer = setInterval(function () {
    fix();
    if (++n >= 6) clearInterval(timer);
  }, 800);
})();
''';

  /// 解析页面回传的消息
  static JwappFetchResult parseMessage(Object? message) {
    if (message is! String || message.trim().isEmpty) {
      return const JwappFetchResult(
        ok: false,
        url: '',
        error: '未收到页面回传的数据',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(message);
    } catch (e) {
      return const JwappFetchResult(
        ok: false,
        url: '',
        error: '页面回传的数据无法解析',
      );
    }
    if (decoded is! Map) {
      return const JwappFetchResult(
        ok: false,
        url: '',
        error: '页面回传的数据格式异常',
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    return JwappFetchResult(
      ok: map['ok'] == true,
      url: (map['url'] as String?) ?? '',
      body: map['body'] as String?,
      error: map['error'] as String?,
      status: (map['status'] as num?)?.toInt(),
    );
  }

  /// 判断一条回包是否属于「针对 [path] 的那次取数」
  ///
  /// 为什么不直接用 `_pending` 判断归属：取数有 30 秒超时，超时后用户重试时，
  /// 上一次调用**迟到很久**的回包才到达 —— 这时 `_pending` 已经指向新的等待者，
  /// 迟到回包会错误地把它完成掉（把学期接口的响应当成课表响应）。
  ///
  /// 脚本回包里带着请求地址（`target = origin + path`），据此判定归属。
  /// 地址缺失或不可解析时**不拦截**（宁可放行，也不要因为解析不出地址而卡死取数）。
  static bool belongsTo(JwappFetchResult result, String path) {
    if (result.url.isEmpty) return true;
    final got = Uri.tryParse(result.url)?.path;
    if (got == null || got.isEmpty) return true;
    final expected = Uri.tryParse(path)?.path ?? path;
    return got == expected;
  }
}

/// 登录页取回的原始数据（交给解析层）
class JwappImportData {
  /// 课表接口响应原文
  final String courseBody;

  /// 学期配置接口响应原文
  final String semesterBody;

  const JwappImportData({
    required this.courseBody,
    required this.semesterBody,
  });
}
