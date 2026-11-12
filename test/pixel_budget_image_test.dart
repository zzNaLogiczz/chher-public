import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chh_app/widgets/pixel_budget_image.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/data/image_disk_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<ImageInfo> _resolve(ImageProvider provider) async {
  final done = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) => done.complete(image.clone()),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => imageDiskCache = ImageDiskCache(null));
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('ordinary preview sizes and small originals are unchanged', () {
    final photo = previewDecodeSize(
      4000,
      3000,
      const ui.TargetImageSize(width: 1280),
    );
    expect((photo.width, photo.height), (1280, 960));
    final small = previewDecodeSize(
      120,
      300,
      const ui.TargetImageSize(width: 1280),
    );
    expect((small.width, small.height), (120, 300));
    final fit = previewDecodeSize(
      2000,
      3000,
      const ui.TargetImageSize(width: 800, height: 1200),
    );
    expect((fit.width, fit.height), (800, 1200));
  });

  test(
    'large and long previews keep all content and a bounded pixel count',
    () {
      for (final (width, height) in [
        (1080, 30000),
        (8000, 6000),
        (1, 10000000),
      ]) {
        final output = previewDecodeSize(
          width,
          height,
          const ui.TargetImageSize(),
        );
        expect(
          output.width! * output.height!,
          lessThanOrEqualTo(previewImagePixelBudget),
        );
        expect(output.width, inInclusiveRange(1, width));
        expect(output.height, inInclusiveRange(1, height));
        if (width > 1) {
          expect(output.width! / output.height!, closeTo(width / height, .002));
        }
      }
    },
  );

  test(
    'the actual image codec receives the bounded target; original remains intact',
    () async {
      final bytes = await _png(3000, 1800);
      imageHttpClientFactory = () => _ImageClient(bytes);
      const source = ChhCachedImage('https://example.test/budget.jpg');
      final preview = await _resolve(PreviewResizeImage(source, width: 3000));
      expect(
        preview.image.width * preview.image.height,
        lessThanOrEqualTo(previewImagePixelBudget),
      );
      expect(preview.image.width, lessThan(3000));
      expect(
        preview.image.width / preview.image.height,
        closeTo(3000 / 1800, .002),
      );
      preview.dispose();
      final original = await _resolve(source);
      expect((original.image.width, original.image.height), (3000, 1800));
      original.dispose();
      // Same dimensions must never share an unbounded/preview memory decode.
      final fullResize = await _resolve(ResizeImage(source, width: 3000));
      expect(fullResize.image.width, 3000);
      fullResize.dispose();
      final boundedAgain = await _resolve(
        PreviewResizeImage(source, width: 3000),
      );
      expect(
        boundedAgain.image.width * boundedAgain.image.height,
        lessThanOrEqualTo(previewImagePixelBudget),
      );
      boundedAgain.dispose();
    },
  );
}

class _ImageClient extends Fake implements HttpClient {
  _ImageClient(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async => _ImageRequest(uri, bytes);
}

class _ImageHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _ImageRequest extends Fake implements HttpClientRequest {
  _ImageRequest(this.uri, this.bytes);
  @override
  final Uri uri;
  final Uint8List bytes;
  @override
  final headers = _ImageHeaders();
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
