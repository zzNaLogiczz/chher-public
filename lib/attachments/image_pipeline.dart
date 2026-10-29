/// 上传前的图片处理:去元数据、按站点上限压缩
///
/// 原则是在装得下的前提下尽量保住画质:
///   1. 先按原尺寸(最长边不超过 4096)高质量重新编码。截图类 PNG 先试无损。
///   2. 超限时在当前尺寸上二分查找装得下的最高 JPEG 质量,质量不低于 70。
///   3. 质量 70 仍超限才缩小尺寸,按体积比例估算一步到位,最小到 1280。
///   4. 最后兜底才在更小尺寸上降低质量;仍装不下就报错,不把超限文件交给站点。
/// 动图转成 JPEG 会丢掉动画,超限时直接提示,不做静默转换。
library;

import 'dart:math' as math;

import 'image_platform.dart';

class PreparedImage {
  final String path;
  final int size;
  final String filename;
  final String contentType;

  const PreparedImage({
    required this.path,
    required this.size,
    required this.filename,
    required this.contentType,
  });
}

class ImagePrepException implements Exception {
  final String message;
  const ImagePrepException(this.message);

  @override
  String toString() => message;
}

class ImagePipeline {
  final ImagePlatform platform;

  const ImagePipeline([this.platform = const ChannelImagePlatform()]);

  static const maxSide = 4096;
  static const minSide = 1280;
  static const keepQuality = 95;
  static const topQuality = 94;
  static const floorQuality = 70;

  /// 处理一张图。[maxBytes] 为 null 时只做去元数据和尺寸上限。
  Future<PreparedImage> prepare(
    String uri, {
    int? maxBytes,
    Set<String> allowed = const {},
  }) async {
    final SourceImage source;
    try {
      source = await platform.open(uri);
    } catch (_) {
      throw const ImagePrepException('无法读取这张图片');
    }
    try {
      return await _prepare(source, maxBytes, allowed);
    } finally {
      await platform.close(source.handle);
    }
  }

  Future<PreparedImage> _prepare(
    SourceImage source,
    int? maxBytes,
    Set<String> allowed,
  ) async {
    bool fits(EncodedImage e) => maxBytes == null || e.size <= maxBytes;
    bool allows(String ext) => allowed.isEmpty || allowed.contains(ext);

    if (source.format == SourceFormat.gif) {
      if (!allows('gif')) throw const ImagePrepException('站点不支持动图');
      if (maxBytes != null && source.size > maxBytes) {
        throw ImagePrepException('动图超过 ${_mb(maxBytes)}，压缩会丢掉动画，请换一张');
      }
      return _done(await platform.original(source.handle), 'gif');
    }
    if (!allows('jpg') && !allows('jpeg')) {
      throw const ImagePrepException('站点不接受这类图片');
    }

    final side = math.min(source.longestSide, maxSide);
    if (source.format == SourceFormat.png && allows('png')) {
      final lossless = await platform.encode(
        source.handle,
        maxSide: side,
        quality: 100,
        png: true,
      );
      if (fits(lossless)) return _done(lossless, 'png');
      await platform.discard(lossless.path);
    }

    final kept = await platform.encode(
      source.handle,
      maxSide: side,
      quality: keepQuality,
    );
    if (fits(kept)) return _done(kept, 'jpg');
    await platform.discard(kept.path);
    final limit = maxBytes!;

    var current = side;
    while (true) {
      final probe = await _bestQuality(
        source.handle,
        current,
        floorQuality,
        topQuality,
        limit,
      );
      if (probe.best != null) return _done(probe.best!, 'jpg');
      if (current <= minSide) break;
      // 体积大致随像素数变化:按最低质量时的超出比例估算下一档尺寸,再留一点余量
      final estimate = (current * math.sqrt(limit / probe.lowestSize) * .95)
          .floor();
      current = math.max(minSide, math.min(estimate, (current * .85).floor()));
    }

    for (final small in const [1280, 1080, 960, 800]) {
      if (small > current) continue;
      final probe = await _bestQuality(source.handle, small, 40, 69, limit);
      if (probe.best != null) return _done(probe.best!, 'jpg');
    }
    throw ImagePrepException('这张图片压缩后仍超过 ${_mb(limit)}');
  }

  /// 在 [side] 尺寸下找装得下的最高质量;最低质量都装不下时返回其体积,供估算下一档尺寸
  Future<({EncodedImage? best, int lowestSize})> _bestQuality(
    int handle,
    int side,
    int low,
    int high,
    int limit,
  ) async {
    final floor = await platform.encode(handle, maxSide: side, quality: low);
    if (floor.size > limit) {
      await platform.discard(floor.path);
      return (best: null, lowestSize: floor.size);
    }
    var best = floor;
    var lo = low + 1;
    var hi = high;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final e = await platform.encode(handle, maxSide: side, quality: mid);
      if (e.size <= limit) {
        await platform.discard(best.path);
        best = e;
        lo = mid + 1;
      } else {
        await platform.discard(e.path);
        hi = mid - 1;
      }
    }
    return (best: best, lowestSize: floor.size);
  }

  PreparedImage _done(EncodedImage e, String ext) => PreparedImage(
    path: e.path,
    size: e.size,
    filename: 'image_${DateTime.now().microsecondsSinceEpoch}.$ext',
    contentType: switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    },
  );
}

String _mb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 1
      ? '${mb.toStringAsFixed(mb == mb.roundToDouble() ? 0 : 1)} MB'
      : '${(bytes / 1024).round()} KB';
}
