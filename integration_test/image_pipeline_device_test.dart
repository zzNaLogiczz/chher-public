/// 真机验证原生图片处理:解码转正、压缩到上限、动图保留。只读写本机临时文件,不联网。
///
/// 运行(用测试包名,不覆盖正式应用):
///   cp tool/preview_package.gradle ~/.gradle/init.d/chh-preview.gradle
///   flutter test integration_test/image_pipeline_device_test.dart -d <设备>
///   rm ~/.gradle/init.d/chh-preview.gradle
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chh_app/attachments/image_pipeline.dart';
import 'package:chh_app/attachments/image_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 带细节的大图:随机色块和细线,JPEG 压不出很小的体积,接近真实照片
Future<Uint8List> _noisyPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final random = math.Random(7);
  final paint = Paint();
  for (var i = 0; i < 60000; i++) {
    paint.color = Color.fromARGB(
      255,
      random.nextInt(256),
      random.nextInt(256),
      random.nextInt(256),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        random.nextDouble() * width,
        random.nextDouble() * height,
        2 + random.nextDouble() * 24,
        2 + random.nextDouble() * 24,
      ),
      paint,
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<String> _write(String name, List<int> bytes) async {
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(bytes);
  return Uri.file(file.path).toString();
}

Future<(int, int)> _size(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final frame = await codec.getNextFrame();
  return (frame.image.width, frame.image.height);
}

/// 在 JPEG 的 SOI 之后插入只含 Orientation=6(顺时针转 90°)的 EXIF 段
Uint8List _withOrientation6(Uint8List jpeg) {
  final tiff = <int>[
    0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08, // 大端,IFD0 偏移 8
    0x00, 0x01, // 1 个条目
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // 没有下一个 IFD
  ];
  final payload = [...'Exif'.codeUnits, 0, 0, ...tiff];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xff, 0xd8, // SOI
    0xff, 0xe1, length >> 8, length & 0xff, ...payload,
    ...jpeg.sublist(2),
  ]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const platform = ChannelImagePlatform();
  const pipeline = ImagePipeline(platform);

  testWidgets('截图类 PNG 装得下时无损保留', (tester) async {
    final uri = await _write('shot.png', await _noisyPng(1080, 2400));
    final image = await pipeline.prepare(uri, maxBytes: 8 * 1024 * 1024);
    debugPrint('CHH-IMAGE png: ${image.size}B ${image.contentType}');
    expect(image.contentType, 'image/png');
    expect(await _size(image.path), (1080, 2400));
    await platform.discard(image.path);
  });

  testWidgets('4000×3000 照片压到上限以内,先降质量再缩尺寸', (tester) async {
    // 由原生编码出一张高质量 JPEG 当作相机原图
    final png = await platform.open(
      await _write('photo.png', await _noisyPng(4000, 3000)),
    );
    final camera = await platform.encode(
      png.handle,
      maxSide: 4000,
      quality: 100,
    );
    await platform.close(png.handle);
    final uri = Uri.file(camera.path).toString();

    final kept = await pipeline.prepare(uri);
    final limit = kept.size ~/ 3;
    final watch = Stopwatch()..start();
    final image = await pipeline.prepare(uri, maxBytes: limit);
    watch.stop();
    final (w, h) = await _size(image.path);
    debugPrint(
      'CHH-IMAGE photo: source ${camera.size}B, q95 ${kept.size}B, '
      'limit ${limit}B -> ${image.size}B ${w}x$h ${watch.elapsedMilliseconds}ms',
    );
    expect(image.size, lessThanOrEqualTo(limit));
    expect(image.contentType, 'image/jpeg');
    expect(math.max(w, h), inInclusiveRange(1280, 4000));
    expect(w / h, closeTo(4 / 3, .01));
    for (final path in [image.path, kept.path, camera.path]) {
      await platform.discard(path);
    }
  });

  testWidgets('EXIF 方向标签被转正,输出不再带方向', (tester) async {
    // 先由原生编码出一张 300×200 的 JPEG,再写入"顺时针 90°"标签
    final source = await platform.open(
      await _write('wide.png', await _noisyPng(300, 200)),
    );
    final plain = await platform.encode(
      source.handle,
      maxSide: 300,
      quality: 90,
    );
    await platform.close(source.handle);
    final tagged = _withOrientation6(await File(plain.path).readAsBytes());
    final image = await pipeline.prepare(await _write('tagged.jpg', tagged));
    final (w, h) = await _size(image.path);
    debugPrint('CHH-IMAGE exif: ${w}x$h');
    expect((w, h), (200, 300));
    await platform.discard(image.path);
    await platform.discard(plain.path);
  });

  testWidgets('动图原样保留', (tester) async {
    // 1×1 的最小 GIF
    final gif = Uint8List.fromList([
      ...'GIF89a'.codeUnits, 1, 0, 1, 0, 0x80, 0, 0, //
      0, 0, 0, 0xff, 0xff, 0xff, //
      0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0, //
      2, 2, 0x44, 1, 0, 0x3b,
    ]);
    final image = await pipeline.prepare(
      await _write('one.gif', gif),
      maxBytes: 1024 * 1024,
    );
    expect(image.contentType, 'image/gif');
    expect(await File(image.path).readAsBytes(), gif);
    await platform.discard(image.path);
  });
}
