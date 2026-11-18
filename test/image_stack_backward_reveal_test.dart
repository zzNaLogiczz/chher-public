import 'dart:ui' as ui;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

void main() {
  for (final cancel in [false, true]) {
    testWidgets('backward portrait reveal stays continuous, cancel=$cancel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final photos = await fixture.makePhotos(
        tester,
        sizes: List.filled(6, const Size(96, 192)),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: RepaintBoundary(
                  key: boundary,
                  child: ImageStackGallery(
                    key: const PageStorageKey('backward-portrait'),
                    urls: List.generate(6, (i) => 'photo-$i'),
                    gallery: List.generate(6, (i) => 'photo-$i'),
                    galleryStartIndex: 0,
                    imageProviderBuilder: (url, _) =>
                        photos[int.parse(url.split('-').last)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ImageStackGallery));
      for (final photo in photos) {
        await tester.runAsync(() => precacheImage(photo, context));
      }
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await fixture.swipe(tester);
      }
      expect(fixture.storedIndex(tester), 3);
      // Fourth -> third photo. The second (green) must never peek in while the
      // spring briefly crosses the third photo's final position.
      if (cancel) {
        final gesture = await tester.startGesture(
          tester.getCenter(fixture.stackStage),
        );
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        await gesture.cancel();
      } else {
        await tester.fling(fixture.stackStage, const Offset(240, 0), 1800);
      }
      var sampledFrames = 0;
      var lastVisiblePixels = -1;
      final earlierIndex = cancel ? 2 : 1;
      final color = fixture.photoColors[earlierIndex];
      for (var tick = 0; tick < 100; tick++) {
        await tester.pump(const Duration(milliseconds: 8));
        final earlier = find.descendant(
          of: fixture.stackCard(earlierIndex),
          matching: find.byType(Visibility),
        );
        if (earlier.evaluate().isEmpty ||
            !tester.widget<Visibility>(earlier).visible) {
          continue;
        }
        sampledFrames++;
        final box = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundary),
        );
        final image = (await tester.runAsync(() => box.toImage()))!;
        final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        var pixels = 0;
        for (var p = 0; p < bytes.lengthInBytes; p += 4) {
          if (bytes.getUint8(p) == (color.toARGB32() >> 16 & 255) &&
              bytes.getUint8(p + 1) == (color.toARGB32() >> 8 & 255) &&
              bytes.getUint8(p + 2) == (color.toARGB32() & 255)) {
            pixels++;
          }
        }
        image.dispose();
        lastVisiblePixels = pixels;
        if (!cancel) {
          expect(
            pixels,
            0,
            reason: 'tick $tick exposes an unrelated earlier photo',
          );
        }
      }
      expect(
        sampledFrames,
        greaterThan(0),
        reason: 'exercise the portrait near its offscreen boundary',
      );
      expect(
        lastVisiblePixels,
        0,
        reason: 'the photo leaves the reveal edge before its slot is hidden',
      );
      await tester.pumpAndSettle();
      expect(fixture.storedIndex(tester), cancel ? 3 : 2);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
