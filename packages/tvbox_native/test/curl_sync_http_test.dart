import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tvbox_core/tvbox_core.dart';
import 'package:tvbox_native/tvbox_native.dart';

/// 真实网络请求测试。
///
/// 需要外网可达（默认访问 baidu.com 与 httpbin.org）。
/// 两种跳过方式：
/// - 显式：环境变量 `TVBOX_SKIP_NET=1`
/// - 自动：启动时探测连通性失败（断网/代理抖动）也会跳过，
///   避免"代码没回归但网络抖了"造成的假失败。
final bool skipNet = Platform.environment.containsKey('TVBOX_SKIP_NET');

/// 启动时探测一次，供所有网络用例共享。
final Future<bool> _netOk = skipNet
    ? Future.value(false)
    : _probe('www.baidu.com', 443);

Future<bool> _probe(String host, int port) async {
  // 必须做完整 HTTPS 请求：本机若有透明代理，TCP 可通但 TLS 失败，
  // 只测 Socket 会产生"探测通过、请求失败"的假结果。
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client
        .headUrl(Uri.https(host, '/'))
        .timeout(const Duration(seconds: 6));
    await req.close().timeout(const Duration(seconds: 6));
    return true;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final netOk = await _netOk;
  final curl = CurlLib.open();

  test('libcurl 版本信息', () {
    expect(curl.version, contains('libcurl/'));
    // ignore: avoid_print
    print('libcurl: ${curl.version}');
  });

  group('CurlSyncHttpClient', () {
    test('同步 GET（https + 重定向 + header 解析）', () {
      if (skipNet) return markTestSkipped('TVBOX_SKIP_NET=1');
      if (!netOk) return markTestSkipped('网络不可达（探测失败）');
      final client = CurlSyncHttpClient();
      final res = client.execute(
        const SyncHttpRequest(
          url: 'http://baidu.com/',
          headers: {'User-Agent': 'tvbox-test/0.1'},
          timeoutMs: 15000,
        ),
      );
      final text = res.contentAsString;
      expect(text, isNotEmpty, reason: 'baidu.com 应 301 到 www 并返回页面');
      expect(res.headers, isNotEmpty);
      expect(
        res.headers.keys.any((k) => k.toLowerCase() == 'content-type'),
        isTrue,
      );
    });

    test('HEAD 请求不返回 body', () {
      if (skipNet) return markTestSkipped('TVBOX_SKIP_NET=1');
      if (!netOk) return markTestSkipped('网络不可达（探测失败）');
      final client = CurlSyncHttpClient();
      final res = client.execute(
        const SyncHttpRequest(
          url: 'https://www.baidu.com/',
          method: 'header',
          timeoutMs: 15000,
        ),
      );
      expect(res.contentAsString, isEmpty);
      expect(res.headers, isNotEmpty);
    });

    test('POST form 数据', () {
      if (skipNet) return markTestSkipped('TVBOX_SKIP_NET=1');
      if (!netOk) return markTestSkipped('网络不可达（探测失败）');
      final client = CurlSyncHttpClient();
      final res = client.execute(
        SyncHttpRequest(
          url: 'https://httpbin.org/post',
          method: 'post',
          postType: HttpPostType.form,
          data: {'name': 'tvbox', 'value': '你好'},
          timeoutMs: 20000,
        ),
      );
      final body = res.contentAsString;
      expect(body, contains('tvbox'));
      // httpbin 返回 JSON，非 ASCII 会被转义成 \uXXXX
      expect(
        body.contains('你好') || body.contains(r'\u4f60\u597d'),
        isTrue,
        reason: 'form 编码后服务端应能还原 UTF-8 内容',
      );
    });

    test('POST JSON 数据', () {
      if (skipNet) return markTestSkipped('TVBOX_SKIP_NET=1');
      if (!netOk) return markTestSkipped('网络不可达（探测失败）');
      final client = CurlSyncHttpClient();
      final res = client.execute(
        SyncHttpRequest(
          url: 'https://httpbin.org/post',
          method: 'post',
          postType: HttpPostType.json,
          data: {'site': 'csp_test', 'page': 1},
          timeoutMs: 20000,
        ),
      );
      final body = jsonDecode(res.contentAsString) as Map;
      expect((body['json'] as Map)['site'], 'csp_test');
    });

    test('base64 响应模式（二进制资源）', () {
      if (skipNet) return markTestSkipped('TVBOX_SKIP_NET=1');
      if (!netOk) return markTestSkipped('网络不可达（探测失败）');
      final client = CurlSyncHttpClient();
      final res = client.execute(
        const SyncHttpRequest(
          url: 'https://www.baidu.com/favicon.ico',
          buffer: HttpBufferMode.base64,
          timeoutMs: 15000,
        ),
      );
      final decoded = base64Decode(res.contentAsString);
      expect(decoded, isNotEmpty);
    });

    test('连接失败返回空响应不抛异常', () {
      final client = CurlSyncHttpClient();
      final res = client.execute(
        const SyncHttpRequest(
          url: 'http://127.0.0.1:1/',
          timeoutMs: 2000,
        ),
      );
      expect(res.contentAsString, isEmpty);
      expect(res.headers, isEmpty);
    });

    test('超时生效', () {
      final client = CurlSyncHttpClient();
      final sw = Stopwatch()..start();
      final res = client.execute(
        const SyncHttpRequest(
          url: 'https://10.255.255.1/', // 不可路由地址，必然超时
          timeoutMs: 1000,
          connectTimeoutMs: 1000,
        ),
      );
      sw.stop();
      expect(res.contentAsString, isEmpty);
      expect(
        sw.elapsed.inMilliseconds,
        lessThan(10000),
        reason: '应在超时附近返回而不是挂死',
      );
    });
  });
}
