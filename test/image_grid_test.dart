import 'dart:async';

import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
    'natural images reserve space before their first frame, then keep source ratios',
    (tester) async {
      const urls = [
        'https://static.chiphell.com/grid-pending-portrait.jpeg',
        'https://static.chiphell.com/grid-pending-landscape.jpeg',
      ];
      final frames = [Completer<ImageInfo>(), Completer<ImageInfo>()];
      for (var i = 0; i < urls.length; i++) {
        final key = await boundedNetworkImage(
          urls[i],
          boundedImageDecodeWidth(320, tester.view.devicePixelRatio),
        ).obtainKey(ImageConfiguration.empty);
        PaintingBinding.instance.imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(frames[i].future),
        );
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: ImageGrid(urls, preserveAspectRatio: true),
                ),
              ),
            ),
          ),
        ),
      );
      // Neither an image frame nor a network chunk event has arrived.
      expect(tester.getSize(find.byType(ImageGrid)), const Size(320, 496));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(find.byType(ImageGrid)).height, 496);

      final portrait = (await tester.runAsync(
        () => createTestImage(width: 120, height: 240, cache: false),
      ))!;
      final landscape = (await tester.runAsync(
        () => createTestImage(width: 240, height: 120, cache: false),
      ))!;
      frames[0].complete(ImageInfo(image: portrait));
      frames[1].complete(ImageInfo(image: landscape));
      await tester.pump();
      await tester.pump();
      // 640px portrait + 160px landscape + 16px inter-image spacing.
      expect(tester.getSize(find.byType(ImageGrid)), const Size(320, 816));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
