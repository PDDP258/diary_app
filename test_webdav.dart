import 'dart:io';
import 'dart:convert';

void main() async {
  const serverUrl = 'https://dav.jianguoyun.com/dav/';
  const username = '1638615339@qq.com';
  const password = 'aa8vmg2tbbrhmttj';

  print('Testing WebDAV connection...');
  print('URL: $serverUrl');
  print('Username: $username');

  try {
    // 创建HttpClient
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        print('SSL: Accepting certificate for $host:$port');
        return true;
      };

    print('\n--- Attempt 1: GET request ---');
    try {
      final request = await httpClient.getUrl(Uri.parse(serverUrl));
      final auth = base64Encode(utf8.encode('$username:$password'));
      request.headers.set('Authorization', 'Basic $auth');
      request.headers.set('Connection', 'close');
      request.headers.set('User-Agent', 'DiaryApp/1.0');

      final response = await request.close().timeout(Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();

      print('Status: ${response.statusCode}');
      print('Headers: ${response.headers}');
      print('Body length: ${body.length}');
      print(
          'Body preview: ${body.substring(0, body.length > 200 ? 200 : body.length)}');

      httpClient.close();

      if (response.statusCode == 200 || response.statusCode == 404) {
        print('\n✅ Connection SUCCESS!');
        return;
      }
    } catch (e) {
      print('GET failed: $e');
      httpClient.close();
    }

    print('\n--- Attempt 2: PROPFIND request ---');
    final httpClient2 = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final request =
          await httpClient2.openUrl('PROPFIND', Uri.parse(serverUrl));
      final auth = base64Encode(utf8.encode('$username:$password'));
      request.headers.set('Authorization', 'Basic $auth');
      request.headers.set('Depth', '0');
      request.headers.set('Content-Type', 'application/xml');
      request.headers.set('Connection', 'close');
      request.headers.set('User-Agent', 'DiaryApp/1.0');
      request.write(
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop></d:prop></d:propfind>');

      final response = await request.close().timeout(Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();

      print('Status: ${response.statusCode}');
      print(
          'Body preview: ${body.substring(0, body.length > 200 ? 200 : body.length)}');

      httpClient2.close();

      if (response.statusCode == 207 ||
          response.statusCode == 200 ||
          response.statusCode == 404) {
        print('\n✅ Connection SUCCESS!');
        return;
      }
    } catch (e) {
      print('PROPFIND failed: $e');
      httpClient2.close();
    }

    print('\n❌ All attempts failed');
  } catch (e) {
    print('Exception: $e');
  }
}
