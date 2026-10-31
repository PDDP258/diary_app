import 'dart:io';

import 'package:diary_app/services/inbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 收件箱列表解析测试。
///
/// fixture 用的是**服务器真实吐出来的 PROPFIND 响应**
/// （`test/fixtures/inbox_propfind_real.xml`，由 diary-webdav 服务生成），
/// 不是自己编的 XML —— 自己造 XML 测自己，服务端格式一变就悄悄失效。
///
/// 这个解析器有个历史包袱：既有的 `_parseWebDAVListing` 只 grep
/// `<d:displayname>`，拿不到每一条自己的大小和时间。收件箱列表页需要
/// 大小和修改时间，所以必须按 `<d:response>` 分块，这里锁住这个行为。
void main() {
  group('收件箱列表解析：服务器真实 PROPFIND 响应', () {
    late String xml;

    setUpAll(() {
      final file = File('test/fixtures/inbox_propfind_real.xml');
      expect(file.existsSync(), isTrue,
          reason: '缺少 fixture：test/fixtures/inbox_propfind_real.xml');
      xml = file.readAsStringSync();
    });

    test('只解析出文件条目，目录自身那一条被跳过', () {
      final items = InboxService.parseListing(xml);
      expect(items.length, 1,
          reason: '第一条 response 是 inbox 目录本身，必须跳过');
      expect(items.first.name, 'draft_20261029-124158_d768.mbk');
    });

    test('每条能拿到自己的大小（不是只 grep displayname 的那种解析）', () {
      final items = InboxService.parseListing(xml);
      expect(items.first.size, 539);
    });

    test('RFC1123 时间能解析（服务器的 getlastmodified 就是这个格式）', () {
      final items = InboxService.parseListing(xml);
      expect(items.first.modified, isNotNull,
          reason: 'getlastmodified 形如 "Thu, 29 Oct 2026 04:41:58 GMT"，'
              'DateTime.parse 必须吃下，否则列表页拿不到时间');
      final utc = items.first.modified!.toUtc();
      expect(utc.year, 2026);
      expect(utc.month, 10);
      expect(utc.day, 29);
    });

    test('两条时按顺序各自拿到自己的大小和时间（分块而不是全局 grep）', () {
      const xml2 = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
<d:response>
<d:href>/dav/inbox/</d:href>
<d:propstat><d:prop>
<d:displayname>inbox</d:displayname>
<d:resourcetype><d:collection/></d:resourcetype>
<d:getlastmodified>Thu, 29 Oct 2026 04:41:58 GMT</d:getlastmodified>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response>
<d:response>
<d:href>/dav/inbox/draft_a.mbk</d:href>
<d:propstat><d:prop>
<d:displayname>draft_a.mbk</d:displayname>
<d:resourcetype/>
<d:getcontentlength>100</d:getcontentlength>
<d:getlastmodified>Thu, 29 Oct 2026 04:41:58 GMT</d:getlastmodified>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response>
<d:response>
<d:href>/dav/inbox/draft_b.mbk</d:href>
<d:propstat><d:prop>
<d:displayname>draft_b.mbk</d:displayname>
<d:resourcetype/>
<d:getcontentlength>200</d:getcontentlength>
<d:getlastmodified>Thu, 29 Oct 2026 05:41:58 GMT</d:getlastmodified>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response>
</d:multistatus>
''';
      final items = InboxService.parseListing(xml2);
      expect(items.length, 2);
      expect(items[0].name, 'draft_a.mbk');
      expect(items[0].size, 100);
      expect(items[1].name, 'draft_b.mbk');
      expect(items[1].size, 200);
      expect(items[0].modified!.toUtc().hour, 4);
      expect(items[1].modified!.toUtc().hour, 5);
    });

    test('空响应 / 空 XML 不炸', () {
      expect(InboxService.parseListing(''), isEmpty);
      expect(
        InboxService.parseListing('<d:multistatus xmlns:d="DAV:"></d:multistatus>'),
        isEmpty,
      );
    });

    test('只保留 .mbk 是列表页的过滤逻辑（解析层不丢数据）', () {
      final items = InboxService.parseListing(xml);
      expect(items.every((e) => e.name.endsWith('.mbk')), isTrue);
    });
  });
}
