/// 带磁盘缓存的站点图片 Provider
///
/// 站点原图动辄 1~3MB,只靠内存 ImageCache 会在滚动、回访时反复下载。
/// 缓存键只用 url + headers,不含解码宽度:ResizeImage 在外层包装,
/// 它自己的键已带宽度供内存缓存区分;内层若再按宽度分键,
/// 满幅路径与限宽路径会各下载一次同一张图。一个 url 只落一份磁盘文件。
///
/// 图片流量刻意不写 AppLog:日志有 10MB 上限,图片请求会挤掉排障用的 HTML 记录。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../data/image_disk_cache.dart';

/// 与 direct_fetcher 的接收超时一致;卡住的响应体会连带拖住所有共享在途下载的等待者
@visibleForTesting
Duration imageReceiveTimeout = const Duration(seconds: 30);

HttpClient Function() _clientFactory = _defaultClient;
HttpClient? _client;

HttpClient _defaultClient() =>
    HttpClient()..connectionTimeout = const Duration(seconds: 15);

/// 测试注入 fake HttpClient,同时丢弃已复用的真实 client
@visibleForTesting
set imageHttpClientFactory(HttpClient Function() factory) {
  _clientFactory = factory;
  _client = null;
}

/// 真正发出的下载请求数(测试断言「二次加载零请求」用)
@visibleForTesting
int downloadCount = 0;

@visibleForTesting
int imageDownloadConcurrency = 4;
@visibleForTesting
int imageMemoryBufferLimit = 2 << 20;
@visibleForTesting
int imageRevisionLimit = 4096;
@visibleForTesting
int get imageRevisionEntryCount => _revisions.length;

int _activeDownloads = 0;
final _downloadWaiters = Queue<Completer<void>>();

Future<void> _acquireDownload() async {
  if (_activeDownloads < imageDownloadConcurrency) {
    _activeDownloads++;
  } else {
    final waiter = Completer<void>();
    _downloadWaiters.add(waiter);
    await waiter.future;
  }
}

void _releaseDownload() {
  if (_downloadWaiters.isEmpty) {
    _activeDownloads--;
  } else {
    _downloadWaiters.removeFirst().complete();
  }
}

class _EncodedImage {
  _EncodedImage.bytes(this.bytes) : file = null, temporary = null;
  _EncodedImage.file(this.file, [this.temporary]) : bytes = null;
  final Uint8List? bytes;
  final File? file;
  final Directory? temporary;
  Future<ui.ImmutableBuffer> buffer() => bytes != null
      ? ui.ImmutableBuffer.fromUint8List(bytes!)
      : ui.ImmutableBuffer.fromFilePath(file!.path);
  Future<void> dispose() async {
    try {
      await temporary?.delete(recursive: true);
    } on FileSystemException {
      // The OS may already have reclaimed the temporary directory.
    }
  }
}

class _ImageDownload {
  late Future<_EncodedImage> future;
  _EncodedImage? source;
  int users = 0;
  bool valid = true;
}

final Map<(String, int), _ImageDownload> _inflight = {};
final Map<String, int> _activeRevisions = {};
final _revisions = <String, int>{};
final Map<String, Future<void>> _invalidating = {};
int _nextRevision = 0;

int _revisionFor(String url, {int? fresh}) {
  final previous = _revisions.remove(url);
  var revision = fresh ?? previous;
  revision ??= _activeRevisions[url];
  _revisions[url] = revision ??= ++_nextRevision;
  while (_revisions.length > imageRevisionLimit) {
    _revisions.remove(_revisions.keys.first);
  }
  return revision;
}

bool _isCurrent(ChhCachedImageKey key) =>
    _revisions[key.url] == key.revision ||
    _inflight[(key.url, key.revision)]?.valid == true;

@immutable
class ChhCachedImageKey {
  const ChhCachedImageKey(
    this.url,
    this.headers, [
    this.revision = 0,
    this.cacheVariant,
  ]);

  final String url;
  final Map<String, String> headers;
  final int revision;
  final Object? cacheVariant;

  @override
  bool operator ==(Object other) =>
      other is ChhCachedImageKey &&
      other.url == url &&
      other.revision == revision &&
      other.cacheVariant == cacheVariant &&
      mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(
    url,
    revision,
    cacheVariant,
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

class ChhCachedImage extends ImageProvider<ChhCachedImageKey> {
  const ChhCachedImage(this.url, {this.headers = const {}, this.cacheVariant});

  final String url;
  final Map<String, String> headers;
  final Object? cacheVariant;

  /// Rebuild the Image after awaiting this; all ResizeImage sizes get fresh keys.
  static Future<void> invalidate(String url) {
    _activeRevisions.remove(url);
    for (final entry in _inflight.entries) {
      if (entry.key.$1 == url) entry.value.valid = false;
    }
    _revisionFor(url, fresh: ++_nextRevision);
    final removal = imageDiskCache.remove(url);
    _invalidating[url] = removal;
    return removal.whenComplete(() {
      if (identical(_invalidating[url], removal)) _invalidating.remove(url);
    });
  }

  @override
  Future<ChhCachedImageKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ChhCachedImageKey>(
        ChhCachedImageKey(url, headers, _revisionFor(url), cacheVariant),
      );

  @override
  ImageStreamCompleter loadImage(
    ChhCachedImageKey key,
    ImageDecoderCallback decode,
  ) {
    final completer = MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<ChhCachedImageKey>('Image key', key),
      ],
    );
    // 失败后从 ImageCache 驱逐,否则未包 ResizeImage 的满幅路径会永久重放同一个错误
    completer.addEphemeralErrorListener(
      (_, _) => scheduleMicrotask(() {
        // ResizeImage owns an outer cache key; advance it too after a failure.
        if (_isCurrent(key)) {
          unawaited(invalidate(key.url));
        }
        PaintingBinding.instance.imageCache.evict(key);
      }),
    );
    return completer;
  }

  Future<ui.Codec> _load(
    ChhCachedImageKey key,
    ImageDecoderCallback decode,
  ) async {
    await _invalidating[key.url];
    final large = await imageDiskCache.fileFor(
      key.url,
      minBytes: imageMemoryBufferLimit + 1,
    );
    final bytes = large == null ? await imageDiskCache.read(key.url) : null;
    final cached = large != null
        ? _EncodedImage.file(large)
        : bytes != null
        ? _EncodedImage.bytes(bytes)
        : null;
    if (cached != null) {
      try {
        return await _decode(cached, decode);
      } catch (_) {
        if (_isCurrent(key)) await invalidate(key.url);
      }
    }
    await _invalidating[key.url];
    final current = ChhCachedImageKey(
      key.url,
      key.headers,
      _revisionFor(key.url),
    );
    return _withDownload(current, (source) => _decode(source, decode));
  }

  Future<T> _withDownload<T>(
    ChhCachedImageKey key,
    Future<T> Function(_EncodedImage source) use,
  ) async {
    final record = (key.url, key.revision);
    final download = _inflight.putIfAbsent(record, () {
      final task = _ImageDownload();
      _activeRevisions[key.url] = key.revision;
      task.future = _download(key, task).then((source) {
        task.source = source;
        return source;
      });
      return task;
    });
    download.users++;
    try {
      return await use(await download.future);
    } finally {
      download.users--;
      if (download.users == 0) {
        _inflight.remove(record);
        if (_activeRevisions[key.url] == key.revision) {
          _activeRevisions.remove(key.url);
        }
        await download.source?.dispose();
      }
    }
  }

  /// The validated original encoding remains available until [use] completes.
  static Future<T> withEncodedFile<T>(
    String url,
    Future<T> Function(File file) use, {
    Map<String, String> headers = const {},
  }) async {
    final provider = ChhCachedImage(url, headers: headers);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    await _invalidating[url];
    final cached = await imageDiskCache.fileFor(url);
    if (cached != null) {
      final temporary = await Directory.systemTemp.createTemp(
        'chher-image-lease-',
      );
      final file = File('${temporary.path}/source');
      var valid = false;
      try {
        try {
          await cached.copy(file.path);
          await _validate(_EncodedImage.file(file));
          valid = true;
        } catch (_) {
          if (_isCurrent(key)) await invalidate(url);
        }
        if (valid) return await use(file);
      } finally {
        await _EncodedImage.file(file, temporary).dispose();
      }
    }
    await _invalidating[url];
    return provider._withDownload(
      ChhCachedImageKey(url, headers, _revisionFor(url)),
      (source) async {
        if (source.file != null) return use(source.file!);
        final temporary = await Directory.systemTemp.createTemp(
          'chher-image-lease-',
        );
        final file = File('${temporary.path}/source');
        try {
          await file.writeAsBytes(source.bytes!);
          return await use(file);
        } finally {
          await _EncodedImage.file(file, temporary).dispose();
        }
      },
    );
  }

  /// Keep ResizeImage's target dimensions while large encodings remain file-backed.
  static Future<ui.Codec> _decode(
    _EncodedImage source,
    ImageDecoderCallback decode,
  ) async => decode(await source.buffer());

  static Future<void> _validate(_EncodedImage source) async {
    final codec = await ui.instantiateImageCodecFromBuffer(
      await source.buffer(),
      targetWidth: 1,
      targetHeight: 1,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }

  /// 下载并校验;只有 200、非空、能解码才落盘,否则抛错交给 errorBuilder
  Future<_EncodedImage> _download(
    ChhCachedImageKey key,
    _ImageDownload task,
  ) async {
    await _acquireDownload();
    HttpClientRequest? request;
    Directory? temporary;
    RandomAccessFile? output;
    try {
      downloadCount++;
      final client = _client ??= _clientFactory();
      request = await client.getUrl(Uri.parse(key.url));
      key.headers.forEach(request.headers.set);
      final response = await request.close().timeout(imageReceiveTimeout);
      if (response.statusCode != HttpStatus.ok) {
        // Headers have completed the request Future: abort alone no longer
        // closes its socket. Cancel the body subscription instead of draining.
        // Cancellation starts synchronously; cleanup must not delay reporting
        // an already-known HTTP failure or hold the shared in-flight entry.
        unawaited(response.listen((_) {}).cancel().catchError((Object _) {}));
        throw HttpException('HTTP ${response.statusCode}', uri: request.uri);
      }
      final builder = BytesBuilder(copy: false);
      File? file;
      var received = 0;
      await for (final chunk in response.timeout(imageReceiveTimeout)) {
        received += chunk.length;
        if (file == null &&
            builder.length + chunk.length <= imageMemoryBufferLimit) {
          builder.add(chunk);
        } else {
          if (file == null) {
            temporary = await Directory.systemTemp.createTemp('chher-image-');
            file = File('${temporary.path}/source');
            output = await file.open(mode: FileMode.write);
            await output.writeFrom(builder.takeBytes());
          }
          // Await each write so network buffering cannot outrun disk IO.
          await output!.writeFrom(chunk);
        }
      }
      await output?.close();
      output = null;
      if (received == 0) throw const HttpException('empty body');
      final source = file == null
          ? _EncodedImage.bytes(builder.takeBytes())
          : _EncodedImage.file(file, temporary);
      await _validate(source);
      if (task.valid) {
        if (source.bytes != null) {
          await imageDiskCache.write(key.url, source.bytes!);
        } else {
          await imageDiskCache.writeFile(key.url, source.file!);
        }
      }
      return source;
    } catch (_) {
      request?.abort();
      try {
        await output?.close();
      } on FileSystemException {
        // Preserve the original network/decode error.
      }
      try {
        await temporary?.delete(recursive: true);
      } on FileSystemException {
        // Reclaimed while downloading.
      }
      rethrow;
    } finally {
      _releaseDownload();
    }
  }

  @override
  String toString() => 'ChhCachedImage("$url")';
}
