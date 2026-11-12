import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'dart:ui' as ui;

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
  _FakeResponse(this.statusCode, this.body, [this.chunks]);
  final Stream<List<int>>? chunks;
  @override
  final int statusCode;
  final List<int> body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => (chunks ?? Stream<List<int>>.fromIterable([body])).listen(
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
    if (client.respond != null) return client.respond!(uri);
    return _FakeResponse(client.status, client.body, client.chunks);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    client.aborts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements HttpClient {
  Future<HttpClientResponse> Function(Uri)? respond;
  int status = 200;
  int aborts = 0;
  Stream<List<int>>? chunks;
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
    imageReceiveTimeout = const Duration(seconds: 30);
    imageDownloadConcurrency = 4;
    imageMemoryBufferLimit = 2 << 20;
    imageRevisionLimit = 4096;
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

  Future<ImageInfo> resolveOnce(ImageProvider provider) async {
    final done = Completer<ImageInfo>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) => done.complete(info),
      onError: (Object error, StackTrace? stack) =>
          done.completeError(error, stack),
    );
    stream.addListener(listener);
    try {
      return await done.future;
    } finally {
      stream.removeListener(listener);
    }
  }

  Future<Uint8List> pngOfSize(int size) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF336699),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return bytes!.buffer.asUint8List();
  }

  const url = 'https://static.chiphell.com/a.jpg';
  const provider = ChhCachedImage(url, headers: chhImageHeaders);

  test(
    'corrupt disk entry is removed even when the replacement fails',
    () async {
      await imageDiskCache.write(url, Uint8List.fromList([1, 2, 3]));
      client.status = 500;
      await expectLater(load(provider), throwsA(anything));
      expect(await imageDiskCache.read(url), isNull);
      expect(await imageDiskCache.totalBytes(), 0);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'failed ResizeImage key can retry without clearing the image cache',
    () async {
      client.status = 500;
      await expectLater(
        resolveOnce(ResizeImage(provider, width: 32)),
        throwsA(anything),
      );
      await Future<void>.delayed(Duration.zero);
      client.status = 200;
      final info = await resolveOnce(ResizeImage(provider, width: 32));
      expect(info.image.width, 1);
      info.dispose();
      expect(downloadCount, 2);
    },
  );

  test(
    'URL invalidation bypasses every resize key and leaves other URLs cached',
    () async {
      final info = await resolveOnce(ResizeImage(provider, width: 32));
      info.dispose();
      const other = ChhCachedImage('https://static.chiphell.com/other.jpg');
      final otherInfo = await resolveOnce(other);
      otherInfo.dispose();
      await ChhCachedImage.invalidate(url);
      client.body = await pngOfSize(2);
      for (final width in [32, 64]) {
        final updated = await resolveOnce(ResizeImage(provider, width: width));
        expect(updated.image.width, 2);
        updated.dispose();
      }
      final retained = await resolveOnce(other);
      expect(retained.image.width, 1);
      retained.dispose();
      expect(downloadCount, 3);
      expect(await imageDiskCache.read(url), client.body);
      expect(dir.listSync(), hasLength(2));
    },
  );

  test(
    'refresh isolates old download writes and preserves new in-flight deduplication',
    () async {
      final oldBody = StreamController<List<int>>();
      final newBody = StreamController<List<int>>();
      final newBytes = await pngOfSize(2);
      client.chunks = oldBody.stream;
      final old = resolveOnce(ResizeImage(provider, width: 32));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await ChhCachedImage.invalidate(url);
      client.chunks = newBody.stream;
      final fresh = resolveOnce(ResizeImage(provider, width: 64));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      oldBody.add(_png);
      await oldBody.close();
      (await old).dispose();
      expect(await imageDiskCache.read(url), isNull);
      final joined = resolveOnce(ResizeImage(provider, width: 128));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(downloadCount, 2);
      newBody.add(newBytes);
      await newBody.close();
      for (final info in await Future.wait([fresh, joined])) {
        expect(info.image.width, 2);
        info.dispose();
      }
      expect(await imageDiskCache.read(url), newBytes);
      expect(dir.listSync(), hasLength(1));
    },
  );

  for (final limit in [4, 2]) {
    test('global download concurrency is bounded at $limit', () async {
      imageDownloadConcurrency = limit;
      final bodies = <StreamController<List<int>>>[];
      client.respond = (_) async {
        final body = StreamController<List<int>>();
        bodies.add(body);
        return _FakeResponse(200, const [], body.stream);
      };
      final pending = [
        for (var i = 0; i < 7; i++)
          resolveOnce(
            ChhCachedImage('https://static.chiphell.com/parallel-$limit-$i'),
          ),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(downloadCount, limit);
      expect(bodies, hasLength(limit));
      for (var i = 0; i < pending.length; i++) {
        bodies[i].add(_png);
        await bodies[i].close();
        (await pending[i]).dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(downloadCount, lessThanOrEqualTo(i + 1 + limit));
      }
      expect(downloadCount, 7);
    });
  }

  test(
    'large encodings spill to files without reducing original resolution',
    () async {
      imageMemoryBufferLimit = 32;
      final original = await pngOfSize(8);
      client.chunks = (() async* {
        for (var i = 0; i < original.length; i += 16) {
          yield original.sublist(i, (i + 16).clamp(0, original.length));
        }
      })();
      final info = await resolveOnce(provider);
      expect(info.image.width, 8);
      info.dispose();
      expect(await imageDiskCache.read(url), original);
      final full = await resolveOnce(ResizeImage(provider, width: 128));
      expect(full.image.width, 8);
      full.dispose();
      expect(downloadCount, 1);
      expect(dir.listSync(), hasLength(1));
    },
  );

  test(
    'validated source lease survives invalidation and expires after use',
    () async {
      imageMemoryBufferLimit = 16;
      File? lease;
      final original = await ChhCachedImage.withEncodedFile(url, (file) async {
        lease = file;
        await ChhCachedImage.invalidate(url);
        expect(await file.exists(), isTrue);
        return file.readAsBytes();
      });
      expect(original, _png);
      expect(await lease!.exists(), isFalse);
      expect(await imageDiskCache.read(url), isNull);
      expect(downloadCount, 1);
    },
  );

  test(
    'cached source lease survives global disk eviction and callback errors',
    () async {
      await load(provider);
      File? lease;
      await expectLater(
        ChhCachedImage.withEncodedFile(url, (file) async {
          lease = file;
          await imageDiskCache.clear();
          expect(await file.readAsBytes(), _png);
          throw StateError('region decoder fixture');
        }),
        throwsStateError,
      );
      expect(await lease!.exists(), isFalse);
      expect(downloadCount, 1);
    },
  );

  test(
    'large uncached source remains readable beyond disk cache capacity',
    () async {
      imageMemoryBufferLimit = 16;
      imageDiskCache = ImageDiskCache(dir, maxBytes: 32);
      expect(
        await ChhCachedImage.withEncodedFile(url, (file) => file.readAsBytes()),
        _png,
      );
      expect(await imageDiskCache.totalBytes(), 0);
      expect(downloadCount, 1);
    },
  );

  test(
    'revision LRU never reuses old epochs and preserves active downloads',
    () async {
      imageRevisionLimit = 2;
      final old = await provider.obtainKey(ImageConfiguration.empty);
      final body = StreamController<List<int>>();
      client.chunks = body.stream;
      final pending = resolveOnce(provider);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      for (var i = 0; i < 5; i++) {
        await ChhCachedImage(
          'https://static.chiphell.com/revision-$i',
        ).obtainKey(ImageConfiguration.empty);
      }
      expect(imageRevisionEntryCount, 2);
      expect(await provider.obtainKey(ImageConfiguration.empty), old);
      body.add(_png);
      await body.close();
      (await pending).dispose();
      expect(await imageDiskCache.read(url), _png);
      for (var i = 5; i < 10; i++) {
        await ChhCachedImage(
          'https://static.chiphell.com/revision-$i',
        ).obtainKey(ImageConfiguration.empty);
      }
      final next = await provider.obtainKey(ImageConfiguration.empty);
      expect(next.revision, greaterThan(old.revision));
      expect(next, isNot(old));
      expect(imageRevisionEntryCount, 2);
      expect(downloadCount, 1);
    },
  );

  test('cache variants isolate memory and ResizeImage keys', () async {
    const plain = ChhCachedImage(url);
    const preview = ChhCachedImage(url, cacheVariant: 'preview-pixels-v1');
    final plainKey = await plain.obtainKey(ImageConfiguration.empty);
    final previewKey = await preview.obtainKey(ImageConfiguration.empty);
    expect(plainKey, isNot(previewKey));
    expect({plainKey, previewKey}, hasLength(2));
    expect(
      await ResizeImage(plain, width: 32).obtainKey(ImageConfiguration.empty),
      isNot(
        await ResizeImage(
          preview,
          width: 32,
        ).obtainKey(ImageConfiguration.empty),
      ),
    );
    expect(previewKey.revision, plainKey.revision);
  });

  test(
    'different memory variants share one URL download and disk file',
    () async {
      final images = await Future.wait([
        resolveOnce(
          const ChhCachedImage(url, cacheVariant: 'preview-pixels-v1'),
        ),
        resolveOnce(const ChhCachedImage(url)),
      ]);
      for (final info in images) {
        info.dispose();
      }
      expect(downloadCount, 1);
      expect(dir.listSync(), hasLength(1));
      PaintingBinding.instance.imageCache.clear();
      final cached = await resolveOnce(
        const ChhCachedImage(url, cacheVariant: 'third-variant'),
      );
      cached.dispose();
      expect(downloadCount, 1);
      expect(await imageDiskCache.read(url), _png);
    },
  );

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

  test('corrupt compressed frame is rejected before it reaches disk', () async {
    final broken = Uint8List.fromList(_png);
    // Keep PNG metadata readable but damage its IDAT compression stream.
    broken[45] ^= 0xff;
    final metadataOnly = await ui.instantiateImageCodec(broken);
    try {
      await expectLater(metadataOnly.getNextFrame(), throwsA(anything));
    } finally {
      metadataOnly.dispose();
    }
    client.body = broken;
    await expectLater(load(provider), throwsA(anything));
    expect(await imageDiskCache.totalBytes(), 0);
    expect(dir.listSync(), isEmpty);
  });

  test(
    'legacy corrupt frame on disk is removed after display failure',
    () async {
      final broken = Uint8List.fromList(_png)..[45] ^= 0xff;
      await imageDiskCache.write(url, broken);
      await expectLater(
        resolveOnce(ResizeImage(provider, width: 32)),
        throwsA(anything),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await imageDiskCache.read(url), isNull);
      expect(await imageDiskCache.totalBytes(), 0);
      final info = await resolveOnce(ResizeImage(provider, width: 32));
      expect(info.image.width, 1);
      info.dispose();
      expect(downloadCount, 1);
    },
  );

  test(
    'error from an old generation cannot delete the refreshed disk image',
    () async {
      final oldBody = StreamController<List<int>>();
      client.chunks = oldBody.stream;
      final stale = resolveOnce(ResizeImage(provider, width: 32));
      final failed = expectLater(stale, throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await ChhCachedImage.invalidate(url);
      client.chunks = null;
      final fresh = await resolveOnce(ResizeImage(provider, width: 64));
      fresh.dispose();
      oldBody.addError(const SocketException('old request failed'));
      await oldBody.close();
      await failed;
      await Future<void>.delayed(Duration.zero);
      expect(await imageDiskCache.read(url), _png);
      expect(downloadCount, 2);
      final retained = await resolveOnce(ResizeImage(provider, width: 128));
      retained.dispose();
      expect(downloadCount, 2);
    },
  );

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

  test('满幅路径失败后不被 ImageCache 钉死,下次 resolve 可成功', () async {
    // 故意不清 ImageCache:这是区分「已驱逐」与「永久重放错误」的唯一路径
    Future<ImageInfo> resolveOnce() {
      final done = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener l;
      l = ImageStreamListener(
        (info, _) {
          stream.removeListener(l);
          done.complete(info);
        },
        onError: (e, s) {
          stream.removeListener(l);
          done.completeError(e, s);
        },
      );
      stream.addListener(l);
      return done.future;
    }

    client.status = 500;
    await expectLater(resolveOnce(), throwsA(isA<HttpException>()));
    await Future<void>.delayed(Duration.zero); // let the eviction microtask run
    client.status = 200;
    final info = await resolveOnce();
    expect(info.image.width, 1);
    expect(downloadCount, 2);
    info.dispose();
  });

  test('ResizeImage 的 decode 宽度上限对缓存 provider 生效', () async {
    // 需要一张比目标宽的图:用 PictureRecorder 生成 8x8 PNG
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 8, 8),
      ui.Paint()..color = const ui.Color(0xFF336699),
    );
    final big = await recorder.endRecording().toImage(8, 8);
    final data = await big.toByteData(format: ui.ImageByteFormat.png);
    client.body = data!.buffer.asUint8List();

    final done = Completer<ImageInfo>();
    ResizeImage(provider, width: 2)
        .resolve(ImageConfiguration.empty)
        .addListener(ImageStreamListener((i, _) => done.complete(i)));
    final info = await done.future;
    expect(info.image.width, 2);
    expect(info.image.height, 2);
    info.dispose();
  });
  test('never closing non-200 aborts promptly and permits retry', () async {
    var canceled = false;
    final stalled = StreamController<List<int>>(
      onCancel: () {
        canceled = true;
      },
    );
    client.status = 500;
    client.chunks = stalled.stream;
    await expectLater(
      load(provider).timeout(const Duration(seconds: 1)),
      throwsA(isA<HttpException>()),
    );
    expect(canceled, isTrue);
    expect(client.aborts, greaterThanOrEqualTo(1));
    client.status = 200;
    client.chunks = null;
    await load(provider);
    expect(downloadCount, 2);
    await stalled.close();
  });

  test('progressing chunks survive beyond the idle deadline', () async {
    imageReceiveTimeout = const Duration(milliseconds: 100);
    client.chunks = (() async* {
      for (var i = 0; i < _png.length; i += 10) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        yield _png.sublist(i, (i + 10).clamp(0, _png.length));
      }
    })();
    final elapsed = Stopwatch()..start();
    await load(provider);
    expect(elapsed.elapsed, greaterThan(imageReceiveTimeout));
    expect(client.aborts, 0);
    expect(await imageDiskCache.read(url), _png);
  });

  test(
    'idle stream cancels source and aborts request, then retry succeeds',
    () async {
      imageReceiveTimeout = const Duration(milliseconds: 50);
      var canceled = false;
      final stalled = StreamController<List<int>>(
        onCancel: () {
          canceled = true;
        },
      );
      client.chunks = stalled.stream;
      await expectLater(load(provider), throwsA(isA<TimeoutException>()));
      expect(canceled, isTrue);
      expect(client.aborts, greaterThanOrEqualTo(1));
      client.chunks = null;
      await load(provider);
      expect(downloadCount, 2);
      await stalled.close();
    },
  );
  test(
    'failed status releases waiters before asynchronous cancel cleanup',
    () async {
      final cleanup = Completer<void>();
      var canceled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          canceled = true;
          return cleanup.future;
        },
      );
      client.status = 500;
      client.chunks = source.stream;
      await expectLater(
        load(provider).timeout(const Duration(seconds: 1)),
        throwsA(isA<HttpException>()),
      );
      expect(canceled, isTrue);
      expect(cleanup.isCompleted, isFalse);
      client.status = 200;
      client.chunks = null;
      await load(provider);
      expect(downloadCount, 2);
      cleanup.complete();
      await source.close();
    },
  );
}
