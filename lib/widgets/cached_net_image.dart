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
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../data/image_disk_cache.dart';

/// 全局磁盘缓存;目录由 setupDependencies 异步就绪后替换,就绪前是 no-op 实例
ImageDiskCache imageDiskCache = ImageDiskCache(null);

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

/// 同一 url 同时 miss 时共享一个在途下载,避免重复请求与写入竞争
final Map<String, Future<Uint8List>> _inflight = {};

@immutable
class ChhCachedImageKey {
  const ChhCachedImageKey(this.url, this.headers);

  final String url;
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      other is ChhCachedImageKey &&
      other.url == url &&
      mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

class ChhCachedImage extends ImageProvider<ChhCachedImageKey> {
  const ChhCachedImage(this.url, {this.headers = const {}});

  final String url;
  final Map<String, String> headers;

  @override
  Future<ChhCachedImageKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ChhCachedImageKey>(ChhCachedImageKey(url, headers));

  @override
  ImageStreamCompleter loadImage(
    ChhCachedImageKey key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<ChhCachedImageKey>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _load(
    ChhCachedImageKey key,
    ImageDecoderCallback decode,
  ) async {
    final cached = await imageDiskCache.read(key.url);
    if (cached != null) {
      try {
        return await _decode(cached, decode);
      } catch (_) {
        // 缓存文件损坏:当作 miss 重新下载,覆盖坏文件
      }
    }
    final bytes = await (_inflight[key.url] ??= _download(key));
    return _decode(bytes, decode);
  }

  /// 用外层(可能是 ResizeImage)传入的 decode,解码宽度上限才继续生效
  static Future<ui.Codec> _decode(
    Uint8List bytes,
    ImageDecoderCallback decode,
  ) async => decode(await ui.ImmutableBuffer.fromUint8List(bytes));

  /// 下载并校验;只有 200、非空、能解码才落盘,否则抛错交给 errorBuilder
  Future<Uint8List> _download(ChhCachedImageKey key) async {
    try {
      downloadCount++;
      final client = _client ??= _clientFactory();
      final request = await client.getUrl(Uri.parse(key.url));
      key.headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: request.uri);
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) throw const HttpException('empty body');
      // 满幅解码一次仅为验证字节确为图片,验证后立即释放
      (await ui.instantiateImageCodec(bytes)).dispose();
      await imageDiskCache.write(key.url, bytes);
      return bytes;
    } finally {
      _inflight.remove(key.url);
    }
  }

  @override
  String toString() => 'ChhCachedImage("$url")';
}
