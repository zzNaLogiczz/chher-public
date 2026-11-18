import 'dart:convert';

import 'package:chh_app/widgets/viewport_ticker_mode.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Two synthetic red/blue GIF frames, looping every 80ms.
final gif = base64Decode(
  'R0lGODlhDAAMAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQACAAAACwAAAAADAAMAAAIFgABCBxIsKDBgwgTKlzIsKHDhxARBgQAIfkEAQgAAQAsAAAAAAwADACBAAD/AAAAAAAAAAAACBYAAQgcSLCgwYMIEypcyLChw4cQEQYEADs=',
);

class _CountingGif extends ImageProvider<_CountingGif> {
  final _memory = MemoryImage(gif);
  int loads = 0;
  @override
  Future<_CountingGif> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _CountingGif key,
    ImageDecoderCallback decode,
  ) {
    loads++;
    return _memory.loadImage(_memory, decode);
  }
}

Future<void> advance(WidgetTester tester, [int count = 5]) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('cached NetImage paints its retained pixels on the first frame', (
    tester,
  ) async {
    const url = 'https://static.chiphell.com/cached-viewport-fixture.png';
    final provider = boundedNetworkImage(url, 128);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final frame = (await tester.runAsync(
      () => createTestImage(width: 100, height: 80, cache: false),
    ))!;
    PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: frame)),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NetImage(url: url, width: 100, height: 80, decodeWidth: 128),
        ),
      ),
    );
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retained GIF pauses offscreen and resumes without remounting', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var frame = -1;
    final provider = _CountingGif();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                ViewportTickerMode(
                  child: Image(
                    image: provider,
                    width: 100,
                    height: 100,
                    frameBuilder: (_, child, number, _) {
                      frame = number ?? -1;
                      return child;
                    },
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    await advance(tester);
    expect(frame, greaterThan(0));
    final imageState = tester.state(find.byType(Image));
    scroll.jumpTo(900);
    await tester.pump();
    await tester.pump();
    await advance(tester, 2);
    final paused = frame;
    await advance(tester);
    expect(frame, paused);
    expect(tester.binding.transientCallbackCount, 0);
    scroll.jumpTo(0);
    await tester.pump();
    await advance(tester);
    expect(tester.state(find.byType(Image)), same(imageState));
    expect(frame, greaterThan(paused));
    expect(provider.loads, 1, reason: 'resume reuses the same cached stream');
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester, 2);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('nested horizontal viewport and covering route pause GIF', (
    tester,
  ) async {
    final horizontal = ScrollController();
    final vertical = ScrollController();
    addTearDown(horizontal.dispose);
    addTearDown(vertical.dispose);
    var frame = -1;
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: SingleChildScrollView(
                controller: vertical,
                child: Column(
                  children: [
                    SizedBox(
                      height: 100,
                      child: SingleChildScrollView(
                        controller: horizontal,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ViewportTickerMode(
                              child: Image.memory(
                                gif,
                                width: 100,
                                height: 100,
                                frameBuilder: (_, child, number, _) {
                                  frame = number ?? -1;
                                  return child;
                                },
                              ),
                            ),
                            const SizedBox(width: 2000),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2000),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await advance(tester);
    expect(frame, greaterThan(0));
    horizontal.jumpTo(500);
    await tester.pump();
    await tester.pump();
    await advance(tester, 2);
    final paused = frame;
    await advance(tester);
    expect(frame, paused);
    expect(tester.binding.transientCallbackCount, 0);
    horizontal.jumpTo(0);
    await tester.pump();
    await advance(tester);
    expect(frame, greaterThan(paused));
    Navigator.of(pageContext).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered')),
      ),
    );
    await advance(tester, 8);
    final covered = frame;
    await advance(tester);
    expect(frame, covered);
    expect(tester.binding.transientCallbackCount, 0);
    Navigator.of(pageContext).pop();
    await advance(tester, 8);
    expect(frame, greaterThan(covered));
    vertical.jumpTo(900);
    await tester.pump();
    await tester.pump();
    await advance(tester, 2);
    final below = frame;
    await advance(tester);
    expect(frame, below);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
