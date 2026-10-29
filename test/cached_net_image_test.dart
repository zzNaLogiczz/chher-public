import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

class _FakeHeaders implements HttpHeaders {
  final Map<String, String> sent = {};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      sent[name] = '$value';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, this.body);
  @override
  final int statusCode;
  final List<int> body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([body]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  int get contentLength => body.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.uri, this.client);
  @override
  final Uri uri;
  final _FakeClient client;
  @override
  final _FakeHeaders headers = _FakeHeaders();
  @override
  Future<HttpClientResponse> close() async {
    client.lastHeaders = headers.sent;
    // Yield so concurrent loads genuinely overlap.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return _FakeResponse(client.status, client.body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements HttpClient {
  int status = 200;
  List<int> body = _png;
  Map<String, String> lastHeaders = {};
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(url, this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _FakeClient client;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('imgcache_test');
    imageDiskCache = ImageDiskCache(dir);
    client = _FakeClient();
    imageHttpClientFactory = () => client;
    downloadCount = 0;
    PaintingBinding.instance.imageCache.clear();
  });

  tearDown(() {
    imageDiskCache = ImageDiskCache(null);
    dir.deleteSync(recursive: true);
  });

  Future<void> load(ImageProvider provider) async {
    PaintingBinding.instance.imageCache.clear();
    final done = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      info.dispose();
      done.complete();
    }, onError: (e, s) => done.completeError(e, s));
    stream.addListener(listener);
    try {
      await done.future;
    } finally {
      stream.removeListener(listener);
    }
  }

  const url = 'https://static.chiphell.com/a.jpg';
  const provider = ChhCachedImage(url, headers: chhImageHeaders);

  test('二次加载同一 url 不再发请求', () async {
    await load(provider);
    await imageDiskCache.totalBytes(); // flush the queued write
    await load(provider);
    expect(downloadCount, 1);
    expect(imageDiskCache.hits, 1);
    expect(client.lastHeaders['Referer'], chhImageHeaders['Referer']);
    expect(client.lastHeaders.containsKey('User-Agent'), isTrue);
  });

  test('404 不写入缓存', () async {
    client.status = 404;
    await expectLater(load(provider), throwsA(isA<HttpException>()));
    expect(await imageDiskCache.totalBytes(), 0);
    expect(dir.listSync(), isEmpty);
  });

  test('同一 url 并发 miss 只下载一次', () async {
    await Future.wait([for (var i = 0; i < 5; i++) load(provider)]);
    expect(downloadCount, 1);
    expect(await imageDiskCache.totalBytes(), _png.length);
    expect(dir.listSync().length, 1);
  });

  test('解码失败不写入缓存', () async {
    client.body = utf8.encode('<html>not an image</html>');
    await expectLater(load(provider), throwsA(anything));
    expect(await imageDiskCache.totalBytes(), 0);
    expect(dir.listSync(), isEmpty);
  });

  test('空响应体不写入缓存', () async {
    client.body = Uint8List(0);
    await expectLater(load(provider), throwsA(isA<HttpException>()));
    expect(dir.listSync(), isEmpty);
  });

  test('失败后同一 url 可重新下载,不残留在途 Future', () async {
    client.status = 500;
    await expectLater(load(provider), throwsA(isA<HttpException>()));
    client.status = 200;
    await load(provider);
    expect(downloadCount, 2);
  });

  test('限宽包装与满幅路径共用同一份磁盘缓存', () async {
    await load(boundedNetworkImage(url, 64));
    await imageDiskCache.totalBytes();
    await load(provider);
    expect(downloadCount, 1);
  });

  test('boundedNetworkImage 仍返回 ResizeImage 且保留解码宽度', () {
    final p = boundedNetworkImage('https://static.chiphell.com/a.jpg', 640);
    expect(p, isA<ResizeImage>());
    expect((p as ResizeImage).width, 640);
  });
}
