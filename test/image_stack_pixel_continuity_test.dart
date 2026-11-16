import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

class NativePair {
  final GlobalKey boundary;
  final GlobalKey production;
  const NativePair(this.boundary, this.production);
  Finder get stage =>
      find.descendant(of: find.byKey(production), matching: fixture.stackStage);
}

/// The production gallery mounted alone. The old card_swiper reference is gone
/// on purpose: the paper deck replaced that animation, so these tests
/// guard the new deck's own invariants instead of package pixel equality.
Future<NativePair> mountPair(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final photos = await fixture.makePhotos(tester);
  final production = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: RepaintBoundary(
            key: production,
            child: ImageStackGallery(
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
  );
  final context = tester.element(find.byType(ImageStackGallery));
  for (final photo in photos) {
    await tester.runAsync(() => precacheImage(photo, context));
  }
  await tester.pumpAndSettle();
  return NativePair(production, production);
}

Future<TestGesture> beginPairGestures(
  WidgetTester tester,
  NativePair pair,
) async => tester.startGesture(tester.getCenter(pair.stage));

/// Previous-frame slot centers, for the frame-to-frame continuity guard.
final Map<int, double> _prevX = {};

/// Per-frame guards: correct source bitmap, bounded live photo window,
/// continuous translation and uniform scaling even while the paper rotates.
Future<void> assertScene(
  WidgetTester tester,
  NativePair pair,
  int frame,
) async {
  final stageBox = tester.renderObject<RenderBox>(pair.stage);
  final decoded = <({int index, ui.Image image, Rect rect, Size size})>[];
  for (final element
      in find
          .descendant(
            of: find.byType(ImageStackGallery),
            matching: find.byType(RawImage),
          )
          .evaluate()) {
    final widget = element.widget as RawImage;
    if (widget.image == null) continue;
    int? index;
    element.visitAncestorElements((ancestor) {
      final key = ancestor.widget.key;
      if (key is ValueKey<String> &&
          key.value.startsWith('image-stack-photo-')) {
        index = int.parse(key.value.substring('image-stack-photo-'.length));
        return false;
      }
      return true;
    });
    if (index == null) continue;
    final box = element.findRenderObject()! as RenderBox;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(stageBox),
      Offset.zero & box.size,
    );
    final matrix = box.getTransformTo(stageBox).storage;
    decoded.add((
      index: index!,
      image: widget.image!.clone(),
      rect: rect,
      size: Size(
        box.size.width *
            math.sqrt(matrix[0] * matrix[0] + matrix[1] * matrix[1]),
        box.size.height *
            math.sqrt(matrix[4] * matrix[4] + matrix[5] * matrix[5]),
      ),
    ));
  }
  expect(decoded.length, inInclusiveRange(1, 5), reason: 'frame $frame');
  // Frame-to-frame continuity: every tracked slot moves on smoothly (drag
  // speed or spring speed), never teleporting — that is what keeps the deck
  // reading as one body. Outgoing slots slide off and get clipped by the
  // reveal line; new slots enter through the same line.
  final stageW = stageBox.size.width;
  for (final photo in decoded) {
    final prev = _prevX[photo.index];
    if (prev != null) {
      expect(
        (photo.rect.center.dx - prev).abs(),
        lessThanOrEqualTo(stageW / 2),
        reason:
            'frame $frame: slot ${photo.index} jumped '
            '${(photo.rect.center.dx - prev).abs().toStringAsFixed(1)}px in '
            'one tick',
      );
    }
    _prevX[photo.index] = photo.rect.center.dx;
  }
  _prevX.removeWhere((index, _) => decoded.every((p) => p.index != index));
  await tester.runAsync(() async {
    for (final photo in decoded) {
      final rgba = (await photo.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final center =
          ((photo.image.height ~/ 2) * photo.image.width +
              photo.image.width ~/ 2) *
          4;
      final pixel = Color.fromARGB(
        rgba.getUint8(center + 3),
        rgba.getUint8(center),
        rgba.getUint8(center + 1),
        rgba.getUint8(center + 2),
      );
      expect(
        pixel,
        isSameColorAs(fixture.photoColors[photo.index]),
        reason:
            'frame $frame: slot ${photo.index} displayed a different URL '
            'bitmap',
      );
      // The photo box may be uniformly scaled with the depth slot but never
      // stretched into a different ratio (long shots fill the frame).
      final sourceRatio = photo.image.width / photo.image.height;
      final boxRatio = photo.size.aspectRatio;
      final frameRatio = stageBox.size.width / stageBox.size.height;
      const eps = 0.04;
      final matchesSource =
          (boxRatio - sourceRatio).abs() < eps ||
          (boxRatio - frameRatio).abs() < eps;
      expect(
        matchesSource,
        isTrue,
        reason:
            'frame $frame: slot '
            '${photo.index} stretched to $boxRatio (source $sourceRatio)',
      );
      photo.image.dispose();
    }
  });
  // Rotation changes the screen-aligned bounding box. The transformed edge
  // lengths above still verify that the paper never stretches the photograph.
  expect(tester.takeException(), isNull);
}

Future<void> exerciseDeck(
  WidgetTester tester,
  NativePair pair, {
  required bool previous,
}) async {
  _prevX.clear();
  final gesture = await beginPairGestures(tester, pair);
  for (var frame = 1; frame <= 24; frame++) {
    final delta = Offset(previous ? 10 : -10, 0);
    final timestamp = Duration(milliseconds: frame * 8);
    await gesture.moveBy(delta, timeStamp: timestamp);
    await tester.pump(const Duration(milliseconds: 8));
    await assertScene(tester, pair, frame);
  }
  await gesture.up(timeStamp: const Duration(milliseconds: 200));
  for (var frame = 25; frame < 90; frame++) {
    await tester.pump(const Duration(milliseconds: 8));
    await assertScene(tester, pair, frame);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'every sampled frame keeps per-slot bitmaps and uniform photo scale',
    (tester) async {
      final pair = await mountPair(tester);
      await assertScene(tester, pair, 0);
      await exerciseDeck(tester, pair, previous: false);
      expect(fixture.storedIndex(tester), 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reverse and forward drags settle without looping at ends', (
    tester,
  ) async {
    final pair = await mountPair(tester);
    await exerciseDeck(tester, pair, previous: true);
    expect(fixture.storedIndex(tester), 0);
    await exerciseDeck(tester, pair, previous: false);
    expect(fixture.storedIndex(tester), 1);
    expect(tester.takeException(), isNull);
  });
}
