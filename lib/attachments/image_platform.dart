/// 图片原生通道:选图、解码转正、缩放编码。压缩策略不在这里,见 image_pipeline.dart。
library;

import 'package:flutter/services.dart';

enum SourceFormat { jpeg, png, gif, webp, heif, unknown }

class SourceImage {
  final int handle;
  final int width;
  final int height;
  final SourceFormat format;

  /// 原始文件字节数
  final int size;

  const SourceImage({
    required this.handle,
    required this.width,
    required this.height,
    required this.format,
    required this.size,
  });

  int get longestSide => width > height ? width : height;
}

class EncodedImage {
  final String path;
  final int size;

  const EncodedImage(this.path, this.size);
}

abstract class ImagePlatform {
  /// 打开系统选图;取消时返回空列表
  Future<List<String>> pick(int max);

  /// 读入并解码(按 EXIF 转正);动图只读不解码
  Future<SourceImage> open(String uri);

  /// 缩到最长边不超过 [maxSide] 后编码成文件;[png] 为 false 时编码为 JPEG
  Future<EncodedImage> encode(
    int handle, {
    required int maxSide,
    required int quality,
    bool png = false,
  });

  /// 原样写出(动图)
  Future<EncodedImage> original(int handle);

  Future<void> close(int handle);

  /// 删除不再需要的临时文件
  Future<void> discard(String path);
}

class ChannelImagePlatform implements ImagePlatform {
  static const _channel = MethodChannel('chh/image');

  const ChannelImagePlatform();

  @override
  Future<List<String>> pick(int max) async {
    final uris = await _channel.invokeListMethod<String>('pick', {'max': max});
    return uris ?? const [];
  }

  @override
  Future<SourceImage> open(String uri) async {
    final m = (await _channel.invokeMapMethod<String, Object?>('open', {
      'uri': uri,
    }))!;
    return SourceImage(
      handle: m['handle']! as int,
      width: m['width']! as int,
      height: m['height']! as int,
      format: SourceFormat.values.firstWhere(
        (f) => f.name == m['format'],
        orElse: () => SourceFormat.unknown,
      ),
      size: m['size']! as int,
    );
  }

  @override
  Future<EncodedImage> encode(
    int handle, {
    required int maxSide,
    required int quality,
    bool png = false,
  }) async => _encoded(
    await _channel.invokeMapMethod<String, Object?>('encode', {
      'handle': handle,
      'maxSide': maxSide,
      'quality': quality,
      'format': png ? 'png' : 'jpeg',
    }),
  );

  @override
  Future<EncodedImage> original(int handle) async => _encoded(
    await _channel.invokeMapMethod<String, Object?>('original', {
      'handle': handle,
    }),
  );

  EncodedImage _encoded(Map<String, Object?>? m) =>
      EncodedImage(m!['path']! as String, m['size']! as int);

  @override
  Future<void> close(int handle) =>
      _channel.invokeMethod('close', {'handle': handle});

  @override
  Future<void> discard(String path) =>
      _channel.invokeMethod('discard', {'path': path});
}
