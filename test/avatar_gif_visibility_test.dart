import 'dart:ui' as ui;
import 'dart:io';

import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'viewport_ticker_mode_test.dart' as fixture;

class _OfflineImages extends Fake implements HttpClient {
  int calls = 0;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    calls++;
    throw const SocketException('offline fixture');
  }
}

void main() {
  testWidgets('lazy avatar visibility does not retry an immediate failure', (
    tester,
  ) async {
    final client = _OfflineImages();
    imageDiskCache = ImageDiskCache(null);
    imageHttpClientFactory = () => client;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: const Column(
              children: [
                AvatarImage(
                  url: 'https://example.test/offline-visibility-avatar.jpg',
                  size: 44,
                  lazy: true,
                ),
                SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    await fixture.advance(tester, 8);
    expect(client.calls, 1);
    scroll.jumpTo(900);
    await tester.pump();
    await fixture.advance(tester, 2);
    scroll.jumpTo(0);
    await tester.pump();
    await fixture.advance(tester, 3);
    expect(client.calls, 1);
    expect(find.byKey(const ValueKey('avatar-logo')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'retained GIF avatar pauses offscreen and keeps its cached frame',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      const url = 'https://static.chiphell.com/local-avatar-animation.gif';
      final key = await boundedNetworkImage(
        url,
        64,
      ).obtainKey(ImageConfiguration.empty);
      final codec = (await tester.runAsync(
        () => ui.instantiateImageCodec(fixture.gif),
      ))!;
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => MultiFrameImageStreamCompleter(
          codec: SynchronousFuture(codec),
          scale: 1,
        ),
      );
      final requests = downloadCount;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: const Column(
                children: [
                  AvatarImage(url: url, size: 60, lazy: true),
                  SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      await fixture.advance(tester, 8);
      final state = tester.state(find.byType(AvatarImage));
      ui.Image bitmap() => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .firstWhere((w) => w.image?.width == 12)
          .image!;
      final playing = bitmap();
      await fixture.advance(tester, 3);
      expect(identical(bitmap(), playing), isFalse);
      scroll.jumpTo(900);
      await tester.pump();
      await tester.pump();
      await fixture.advance(tester, 2);
      final paused = bitmap();
      await fixture.advance(tester);
      expect(identical(bitmap(), paused), isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      scroll.jumpTo(0);
      await tester.pump();
      await fixture.advance(tester);
      expect(tester.state(find.byType(AvatarImage)), same(state));
      expect(identical(bitmap(), paused), isFalse);
      expect(downloadCount, requests);
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.advance(tester, 2);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
