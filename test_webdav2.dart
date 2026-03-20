import 'dart:io';
import 'dart:convert';

void main() async {
  const serverUrl = 'https://dav.jianguoyun.com/dav/';
  const username = '1638615339@qq.com';
  const password = 'aa8vmg2tbbrhmttj';

  print('=== Flutter WebDAV Connection Test ===');
  print('URL: $serverUrl');
  print('Username: $username');
  print('');

  // 测试1: 直接用PROPFIND (和Flutter代码一样)
  print('--- Test 1: PROPFIND (like Flutter code) ---');
  await testPropfindLikeFlutter(serverUrl, username, password);

  print('');

  // 测试2: 完整读取响应
  print('--- Test 2: PROPFIND with full body read ---');
  await testPropfindFullBody(serverUrl, username, password);
}

Future<void> testPropfindLikeFlutter(
    String serverUrl, String username, String password) async {
  try {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final request =
          await httpClient.openUrl('PROPFIND', Uri.parse(serverUrl));
      final auth = base64Encode(utf8.encode('$username:$password'));
      request.headers.set('Authorization', 'Basic $auth');
      request.headers.set('Depth', '0');
      request.headers.set('Content-Type', 'application/xml');
      request.headers.set('Connection', 'close');
      request.write(
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop></d:prop></d:propfind>');

      final response = await request.close().timeout(Duration(seconds: 30));

      // Flutter代码中用的是 await response.drain()
      await response.drain();

      print('Status: ${response.statusCode}');
      print('Response after drain()');

      httpClient.close();

      if (response.statusCode == 207) {
        print('✅ SUCCESS: 207 Multi-Status');
      } else if (response.statusCode == 401) {
        print('❌ FAILED: 401 Unauthorized');
      } else {
        print('Other status: ${response.statusCode}');
      }
    } catch (e) {
      print('PROPFIND exception: $e');
      httpClient.close();
    }
  } catch (e) {
    print('Outer exception: $e');
  }
}

Future<void> testPropfindFullBody(
    String serverUrl, String username, String password) async {
  try {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final request =
          await httpClient.openUrl('PROPFIND', Uri.parse(serverUrl));
      final auth = base64Encode(utf8.encode('$username:$password'));
      request.headers.set('Authorization', 'Basic $auth');
      request.headers.set('Depth', '0');
      request.headers.set('Content-Type', 'application/xml');
      request.headers.set('Connection', 'close');
      request.write(
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop></d:prop></d:propfind>');

      final response = await request.close().timeout(Duration(seconds: 30));

      // 完整读取响应体
      final body = await response.transform(utf8.decoder).join();

      print('Status: ${response.statusCode}');
      print('Body length: ${body.length}');
      print(
          'Body preview: ${body.substring(0, body.length > 100 ? 100 : body.length)}');

      httpClient.close();

      if (response.statusCode == 207) {
        print('✅ SUCCESS: 207 Multi-Status');
      }
    } catch (e) {
      print('PROPFIND exception: $e');
      httpClient.close();
    }
  } catch (e) {
    print('Outer exception: $e');
  }
}
