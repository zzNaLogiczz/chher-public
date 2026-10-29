import 'dart:math' as math;

import 'package:chh_app/attachments/image_pipeline.dart';
import 'package:chh_app/attachments/image_platform.dart';
import 'package:flutter_test/flutter_test.dart';

/// 体积按像素数 × 质量估算的假编码器;记录每次编码,核对临时文件有没有删干净
class _FakePlatform implements ImagePlatform {
  final SourceImage source;
  final encodes = <({int side, int quality, bool png})>[];
  final live = <String>{};
  var _n = 0;
  var closed = false;

  _FakePlatform(this.source);

  int pixels(int side) {
    final f = math.min(1.0, side / source.longestSide);
    return (source.width * f).round() * (source.height * f).round();
  }

  @override
  Future<List<String>> pick(int max) async => const [];

  @override
  Future<SourceImage> open(String uri) async => source;

  @override
  Future<EncodedImage> encode(
    int handle, {
    required int maxSide,
    required int quality,
    bool png = false,
  }) async {
    encodes.add((side: maxSide, quality: quality, png: png));
    final size = png
        ? pixels(maxSide)
        : (pixels(maxSide) * (.05 + quality * .0025)).round();
    final path = 'tmp/${_n++}';
    live.add(path);
    return EncodedImage(path, size);
  }

  @override
  Future<EncodedImage> original(int handle) async {
    final path = 'tmp/${_n++}';
    live.add(path);
    return EncodedImage(path, source.size);
  }

  @override
  Future<void> close(int handle) async => closed = true;

  @override
  Future<void> discard(String path) async => live.remove(path);
}

SourceImage _photo({
  int width = 4000,
  int height = 3000,
  SourceFormat format = SourceFormat.jpeg,
  int size = 4000000,
}) => SourceImage(
  handle: 1,
  width: width,
  height: height,
  format: format,
  size: size,
);

const mb = 1024 * 1024;

void main() {
  test('没有上限:按原尺寸高质量重编码一次,只去元数据', () async {
    final platform = _FakePlatform(_photo());
    final image = await ImagePipeline(platform).prepare('content://1');
    expect(platform.encodes.single, (side: 4000, quality: 95, png: false));
    expect(image.contentType, 'image/jpeg');
    expect(image.filename, endsWith('.jpg'));
    expect(platform.live, {image.path});
    expect(platform.closed, isTrue);
  });

  test('超限时先在原尺寸上找装得下的最高质量,不急着缩图', () async {
    final platform = _FakePlatform(_photo());
    final image = await ImagePipeline(
      platform,
    ).prepare('content://1', maxBytes: 3000000);
    expect(image.size, lessThanOrEqualTo(3000000));
    final chosen = platform.encodes.lastWhere((e) => e.quality == 80);
    expect(chosen.side, 4000);
    // 81 就超了,80 是装得下的最高质量
    expect(
      platform.encodes.where((e) => e.quality > 80 && e.quality < 95),
      everyElement(predicate((e) => (e as dynamic).side == 4000)),
    );
    expect(platform.live, {image.path});
  });

  test('质量 70 仍超限才缩小尺寸,且不低于 1280', () async {
    final platform = _FakePlatform(_photo());
    final image = await ImagePipeline(
      platform,
    ).prepare('content://1', maxBytes: mb);
    expect(image.size, lessThanOrEqualTo(mb));
    final last = platform.encodes.last;
    expect(last.side, inInclusiveRange(1280, 3999));
    final kept = platform.encodes.where(
      (e) => e.side == last.side && e.quality >= 70,
    );
    expect(kept, isNotEmpty);
    expect(platform.live, {image.path});
  });

  test('超过 4096 的大图先限到 4096', () async {
    final platform = _FakePlatform(_photo(width: 8000, height: 6000));
    await ImagePipeline(platform).prepare('content://1');
    expect(platform.encodes.single.side, 4096);
  });

  test('截图类 PNG 装得下就无损保留', () async {
    final platform = _FakePlatform(
      _photo(width: 1080, height: 2400, format: SourceFormat.png),
    );
    final image = await ImagePipeline(
      platform,
    ).prepare('content://1', maxBytes: 3 * mb);
    expect(image.contentType, 'image/png');
    expect(platform.encodes.single.png, isTrue);
  });

  test('PNG 装不下改成高质量 JPEG', () async {
    final platform = _FakePlatform(
      _photo(width: 1440, height: 3168, format: SourceFormat.png),
    );
    final image = await ImagePipeline(
      platform,
    ).prepare('content://1', maxBytes: 2 * mb);
    expect(image.contentType, 'image/jpeg');
    expect(platform.encodes.first.png, isTrue);
    expect(platform.live, {image.path});
  });

  test('站点不收 PNG 时直接给 JPEG', () async {
    final platform = _FakePlatform(
      _photo(width: 1080, height: 2400, format: SourceFormat.png),
    );
    final image = await ImagePipeline(
      platform,
    ).prepare('content://1', maxBytes: 3 * mb, allowed: {'jpg', 'gif'});
    expect(image.contentType, 'image/jpeg');
    expect(platform.encodes.every((e) => !e.png), isTrue);
  });

  test('动图原样上传;超限时提示换图,不转成静态图', () async {
    final small = _FakePlatform(
      _photo(width: 400, height: 300, format: SourceFormat.gif, size: mb),
    );
    final gif = await ImagePipeline(
      small,
    ).prepare('content://1', maxBytes: 2 * mb);
    expect(gif.contentType, 'image/gif');
    expect(small.encodes, isEmpty);

    final large = _FakePlatform(
      _photo(width: 400, height: 300, format: SourceFormat.gif, size: 5 * mb),
    );
    await expectLater(
      ImagePipeline(large).prepare('content://1', maxBytes: 2 * mb),
      throwsA(
        isA<ImagePrepException>().having(
          (e) => e.message,
          'message',
          contains('动图'),
        ),
      ),
    );
    expect(large.closed, isTrue);
  });

  test('压到最小仍装不下就报错,不把超限文件交出去', () async {
    final platform = _FakePlatform(_photo());
    await expectLater(
      ImagePipeline(platform).prepare('content://1', maxBytes: 10 * 1024),
      throwsA(isA<ImagePrepException>()),
    );
    expect(platform.live, isEmpty);
    expect(platform.closed, isTrue);
  });
}
