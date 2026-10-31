import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../services/database_service.dart';
import '../services/encryption_service.dart';
import '../services/sync_log_service.dart';

/// 收件箱里的一个条目（「麦麦写来的日记」）。
///
/// 服务器上存的是**密文**：内容用和云备份同一把 cloud_key 加密，
/// 解密密钥只在 App 的安全存储里。服务器被攻破也看不到日记正文。
class InboxItem {
  /// 服务器上的文件名，形如 `draft_20261029-120000_ab12.mbk`
  final String name;

  /// 字节数
  final int size;

  /// 服务器上的修改时间
  final DateTime? modified;

  /// 解密后的正文（列表页为 null，点开详情时才去拉）
  final Map<String, dynamic>? payload;

  const InboxItem({
    required this.name,
    this.size = 0,
    this.modified,
    this.payload,
  });

  String get title {
    final t = payload?['title'];
    if (t is String && t.trim().isNotEmpty) return t.trim();
    return '未命名';
  }

  String get content => payload?['content'] is String ? payload!['content'] as String : '';

  String get date {
    final d = payload?['date'];
    if (d is String && d.isNotEmpty) return d;
    return '';
  }

  String get mood {
    final m = payload?['mood'];
    return m is String ? m.trim() : '';
  }

  String get source {
    final s = payload?['source'];
    return s is String ? s : '';
  }
}

/// 收件箱服务：拉取服务器上「麦麦写来的日记」，让用户逐条确认。
///
/// 链路：
///   1. PROPFIND `inbox/` 列出条目（只看 displayname + 大小 + 时间）
///   2. GET 单条 → 用 cloud_key 解密 → 得到标题/正文/日期/心情
///   3. 用户「确认导入」→ 写进本地数据库 → DELETE 掉服务器上的原件
///      用户「丢弃」→ 直接 DELETE
///
/// ⚠️ 已处理的条目记在本地（SharedPreferences）里，即使 DELETE 失败
/// （比如换了个不支持 DELETE 的 WebDAV）也不会重复导入。
class InboxService {
  static const String _processedKey = 'inbox_processed_files';

  /// 服务器上的收件箱目录（相对 WebDAV 根）
  static const String remoteDir = 'inbox';

  /// 拉取收件箱列表（不下载正文）
  static Future<List<InboxItem>> listItems({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final base = _normalizeBase(serverUrl);
      final uri = Uri.parse('$base$remoteDir/');
      debugPrint('[Inbox] 列目录: $uri');

      final request = await httpClient.openUrl('PROPFIND', uri);
      final auth = base64Encode(utf8.encode('$username:$password'));
      request.headers.set('Authorization', 'Basic $auth');
      request.headers.set('Depth', '1');
      request.headers.set('Content-Type', 'application/xml');
      request.headers.set('Connection', 'close');
      request.write(
        '<?xml version="1.0"?>'
        '<d:propfind xmlns:d="DAV:">'
        '<d:prop><d:displayname/><d:getcontentlength/><d:getlastmodified/>'
        '<d:resourcetype/></d:prop>'
        '</d:propfind>',
      );

      final response = await request.close().timeout(const Duration(seconds: 30));
      final status = response.statusCode;

      if (status == 404) {
        // 服务器还没建 inbox/ 目录 → 当作空收件箱
        await response.drain();
        debugPrint('[Inbox] 收件箱目录不存在');
        return [];
      }
      if (status != 207) {
        await response.drain();
        debugPrint('[Inbox] PROPFIND 返回 $status');
        return [];
      }

      final bytes = await response.fold<List<int>>([], (p, c) => p..addAll(c));
      final xml = utf8.decode(bytes);
      httpClient.close();

      final processed = await _processedSet();
      final items = parseListing(xml)
          .where((e) => e.name.endsWith('.mbk'))
          .where((e) => !processed.contains(e.name))
          .toList()
        ..sort((a, b) => b.name.compareTo(a.name)); // 文件名带时间戳，倒序=最新在前

      debugPrint('[Inbox] 发现 ${items.length} 条待确认');
      return items;
    } catch (e) {
      httpClient.close();
      debugPrint('[Inbox] 列目录失败: $e');
      return [];
    }
  }

  /// 下载并解密一条。
  ///
  /// 返回 null 表示失败（网络问题或密钥不对）。
  static Future<Map<String, dynamic>?> fetchPayload({
    required String serverUrl,
    required String username,
    required String password,
    required String name,
  }) async {
    final cloudKey = await EncryptionService.getCloudBackupKey();
    if (cloudKey == null || cloudKey.isEmpty) {
      debugPrint('[Inbox] 没有云端备份密钥，无法解密');
      return null;
    }

    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final base = _normalizeBase(serverUrl);
      final file = Uri.encodeComponent(name);
      final uri = Uri.parse('$base$remoteDir/$file');
      debugPrint('[Inbox] 下载: $uri');

      final request = await httpClient.getUrl(uri);
      final auth = base64Encode(utf8.encode('$username:$password'));
      request.headers.set('Authorization', 'Basic $auth');
      request.headers.set('Connection', 'close');

      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        await response.drain();
        debugPrint('[Inbox] 下载返回 ${response.statusCode}');
        return null;
      }

      final bytes = await response.fold<List<int>>([], (p, c) => p..addAll(c));
      httpClient.close();

      final outer = jsonDecode(utf8.decode(bytes));
      if (outer is! Map) return null;
      final data = outer['data'];
      if (data is! String || !data.startsWith('__CLOUD__')) {
        debugPrint('[Inbox] 不是收件箱密文格式');
        return null;
      }

      final plain = await EncryptionService.decryptWithCloudKey(data, cloudKey);
      if (plain == null) {
        debugPrint('[Inbox] 解密失败');
        return null;
      }
      final inner = jsonDecode(plain);
      return inner is Map ? Map<String, dynamic>.from(inner) : null;
    } catch (e) {
      httpClient.close();
      debugPrint('[Inbox] 下载失败: $e');
      return null;
    }
  }

  /// 删除服务器上的原件。
  ///
  /// 返回 true 表示确实删掉了。失败不算致命 —— 已处理的条目记在本地，
  /// 不会重复出现在列表里。
  static Future<bool> deleteRemote({
    required String serverUrl,
    required String username,
    required String password,
    required String name,
  }) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final base = _normalizeBase(serverUrl);
      final file = Uri.encodeComponent(name);
      final uri = Uri.parse('$base$remoteDir/$file');

      final request = await httpClient.openUrl('DELETE', uri);
      final auth = base64Encode(utf8.encode('$username:$password'));
      request.headers.set('Authorization', 'Basic $auth');
      request.headers.set('Connection', 'close');

      final response = await request.close().timeout(const Duration(seconds: 30));
      final status = response.statusCode;
      await response.drain();
      httpClient.close();

      debugPrint('[Inbox] DELETE $name → $status');
      return status == 200 || status == 204 || status == 404;
    } catch (e) {
      httpClient.close();
      debugPrint('[Inbox] 删除失败: $e');
      return false;
    }
  }

  /// 确认导入：把解密后的内容写进本地日记库。
  ///
  /// 心情按名称回查本地心情表；查不到就不设置（不能凭空造心情）。
  static Future<bool> importToLocal(Map<String, dynamic> payload) async {
    try {
      final content = payload['content'];
      if (content is! String || content.trim().isEmpty) return false;

      final day = payload['date'];
      final title = payload['title'];
      final moodName = payload['mood'];

      int? moodId;
      String? resolvedMoodName;
      String? moodEmoji;
      if (moodName is String && moodName.trim().isNotEmpty) {
        final moods = await DatabaseService.getAllMoods();
        for (final Mood m in moods) {
          if (m.name == moodName.trim()) {
            moodId = m.id;
            resolvedMoodName = m.name;
            moodEmoji = m.emoji;
            break;
          }
        }
      }

      final diary = Diary(
        title: (title is String && title.trim().isNotEmpty) ? title.trim() : null,
        content: content.trim(),
        date: (day is String && day.isNotEmpty) ? day : _today(),
        moodId: moodId,
        moodName: resolvedMoodName,
        moodEmoji: moodEmoji,
      );

      await DatabaseService.insertDiary(diary);
      debugPrint('[Inbox] 已导入日记: ${diary.date} ${diary.title ?? ''}');
      return true;
    } catch (e) {
      debugPrint('[Inbox] 导入失败: $e');
      SyncLogService.log('收件箱导入失败: $e', level: 'ERROR');
      return false;
    }
  }

  /// 标记某条已处理（无论导入还是丢弃），并尝试删掉服务器原件。
  static Future<void> markProcessed({
    required String serverUrl,
    required String username,
    required String password,
    required String name,
  }) async {
    final set = await _processedSet();
    set.add(name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_processedKey, set.toList());

    await deleteRemote(
      serverUrl: serverUrl,
      username: username,
      password: password,
      name: name,
    );
  }

  // ---------- 内部 ----------

  static String _normalizeBase(String serverUrl) {
    var base = serverUrl.trim();
    if (!base.endsWith('/')) base = '$base/';
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    return base;
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static Future<Set<String>> _processedSet() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_processedKey) ?? <String>[]).toSet();
  }

  /// 解析 PROPFIND 的 207 响应。
  ///
  /// ⚠️ 不能只 grep `<d:displayname>`（现有的 `_parseWebDAVListing` 就是那样），
  /// 因为要拿到**每一条**自己的大小和时间，必须按 `<d:response>` 分块。
  ///
  /// fixture 用的是**服务器真实吐出来的 XML**
  /// （`test/fixtures/inbox_propfind_real.xml`），不是自己编的 ——
  /// 自己造 XML 测自己，格式一变就悄悄失效。
  @visibleForTesting
  static List<InboxItem> parseListing(String xml) {
    final items = <InboxItem>[];
    final blocks = RegExp(r'<d:response>(.*?)</d:response>', dotAll: true)
        .allMatches(xml);

    for (final match in blocks) {
      final block = match.group(1)!;

      final nameMatch = RegExp(r'<d:displayname>([^<]*)</d:displayname>')
          .firstMatch(block);
      if (nameMatch == null) continue;
      final name = nameMatch.group(1)!.trim();
      if (name.isEmpty) continue;

      // 目录跳过（收件箱是平铺的，不该有子目录）
      if (block.contains('<d:collection/>')) continue;

      final sizeMatch =
          RegExp(r'<d:getcontentlength>(\d+)</d:getcontentlength>')
              .firstMatch(block);
      final size = sizeMatch == null ? 0 : int.tryParse(sizeMatch.group(1)!) ?? 0;

      DateTime? modified;
      final modMatch = RegExp(r'<d:getlastmodified>([^<]*)</d:getlastmodified>')
          .firstMatch(block);
      if (modMatch != null) {
        modified = _parseHttpDate(modMatch.group(1)!.trim());
      }

      items.add(InboxItem(name: name, size: size, modified: modified));
    }
    return items;
  }

  /// 解析 `<d:getlastmodified>`。
  ///
  /// ⚠️ WebDAV（我们的 diary-webdav、坚果云等）吐的是 **RFC 1123**，
  /// 形如 `Thu, 29 Oct 2026 04:41:58 GMT`，**不是** ISO 8601。
  /// 而 Dart 的 `DateTime.parse` 只认 ISO 8601，对这个格式**返回 null** ——
  /// 结果就是列表页每一条的修改时间都是空的。
  /// 必须用 `HttpDate.parse`。
  ///
  /// 万一哪天服务端换成 ISO 8601，也照样能解，所以留个回退。
  static DateTime? _parseHttpDate(String text) {
    if (text.isEmpty) return null;
    try {
      return HttpDate.parse(text);
    } catch (_) {
      return DateTime.tryParse(text);
    }
  }
}
