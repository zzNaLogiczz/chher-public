import 'dart:ui' as ui;

import 'package:chh_app/design/motion.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://static.chiphell.com/return-clip-fixture.jpeg';

Future<void> _open(
  WidgetTester tester, {
  bool reduced = false,
  bool fromList = false,
}) async {
  final frame = (await tester.runAsync(
    () => createTestImage(width: 320, height: 600, cache: false),
  ))!;
  for (final provider in <ImageProvider<Object>>[
    boundedNetworkImage(
      _url,
      boundedImageDecodeWidth(320, tester.view.devicePixelRatio),
    ),
    const ChhCachedImage(_url, headers: chhImageHeaders),
  ]) {
    final key = await provider.obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: frame.clone())),
      ),
    );
  }
  frame.dispose();
  const reader = Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        child: InlineImageViewer(url: _url, gallery: [_url]),
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: fromList
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => reader)),
                  child: const Text('打开帖子'),
                ),
              ),
            )
          : reader,
    ),
  );
  if (fromList) {
    await tester.tap(find.text('打开帖子'));
    await tester.pumpAndSettle();
  }
  await tester.pumpAndSettle();
  await tester.tap(find.byType(InlineImageViewer));
  await tester.pumpAndSettle();
}

TransformationController _transform(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

Rect _globalRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Rect _flightClip(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('image-viewer-flight-clip'));
  final widget = tester.widget<ClipRect>(finder);
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    widget.clipper!.getClip(box.size),
  );
}

void _sameRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, .01));
  expect(actual.top, closeTo(expected.top, .01));
  expect(actual.right, closeTo(expected.right, .01));
  expect(actual.bottom, closeTo(expected.bottom, .01));
}

Future<void> _doubleTap(WidgetTester tester) async {
  final photo = find.byType(InteractiveViewer);
  await tester.tap(photo);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(photo);
}

Future<void> _close(WidgetTester tester, {bool button = false}) async {
  if (button) {
    await tester.tap(find.byTooltip('关闭图片'));
  } else {
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
  }
  // Hero measures at end of frame and paints its overlay on the next frame.
  await tester.pump();
  await tester.pump();
}

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
    'returning a partly scrolled long photo never covers reader bars',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final hidden = ValueNotifier<double>(0);
      final scroll = ScrollController(initialScrollOffset: 400);
      addTearDown(hidden.dispose);
      addTearDown(scroll.dispose);
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 320, 1200),
          Paint()..color = Colors.red,
        )
        ..drawRect(
          const Rect.fromLTWH(0, 0, 16, 1200),
          Paint()..color = Colors.yellow,
        );
      final picture = recorder.endRecording();
      final frame = (await tester.runAsync(() => picture.toImage(320, 1200)))!;
      picture.dispose();
      for (final provider in <ImageProvider<Object>>[
        boundedNetworkImage(_url, boundedImageDecodeWidth(320, 1)),
        const ChhCachedImage(_url, headers: chhImageHeaders),
      ]) {
        final key = await provider.obtainKey(ImageConfiguration.empty);
        PaintingBinding.instance.imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: frame.clone())),
          ),
        );
      }
      frame.dispose();
      final screen = GlobalKey();
      const top = 24 + NavOverlay.barHeight;
      const bottomPadding = 20.0;
      final reader = ReadingBarAnchor(
        hiddenProgress: hidden,
        bottomPadding: bottomPadding,
        child: Scaffold(
          body: Stack(
            children: [
              SingleChildScrollView(
                controller: scroll,
                child: const Center(
                  child: SizedBox(
                    width: 320,
                    child: InlineImageViewer(url: _url, gallery: [_url]),
                  ),
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: top,
                child: ColoredBox(color: Color(0xff1234aa)),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 100,
                child: ColoredBox(color: Color(0xff1234aa)),
              ),
            ],
          ),
        ),
      );
      final bottom = 844 - reader.height;
      await tester.pumpWidget(
        RepaintBoundary(
          key: screen,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24, bottom: bottomPadding),
                viewPadding: const EdgeInsets.only(
                  top: 24,
                  bottom: bottomPadding,
                ),
              ),
              child: child!,
            ),
            home: reader,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final source = _globalRect(tester, find.byType(Hero));
      expect(source.top, lessThan(top));
      expect(source.bottom, greaterThan(bottom));
      final arrival = source.intersect(Rect.fromLTRB(0, top, 390, bottom));
      await tester.tapAt(const Offset(195, 300));
      await tester.pumpAndSettle();
      await _doubleTap(tester);
      await tester.pumpAndSettle();
      final animation = ModalRoute.of(
        tester.element(find.byType(ImageViewerPage)),
      )!.animation!;
      await _close(tester);
      var nearEnd = false;
      var pixelFrames = 0;
      for (var tick = 0; tick < 90; tick++) {
        if (find
            .byKey(const ValueKey('image-viewer-flight-clip'))
            .evaluate()
            .isEmpty) {
          break;
        }
        final clip = _flightClip(tester);
        expect(clip.top, greaterThanOrEqualTo(top - .01));
        expect(clip.bottom, lessThanOrEqualTo(824));
        if (animation.value < .005) {
          expect(clip.top, closeTo(arrival.top, 2));
          expect(clip.bottom, closeTo(arrival.bottom, 2));
          expect(clip.left, closeTo(arrival.left, 2));
          expect(clip.right, closeTo(arrival.right, 2));
          nearEnd = true;
        }
        if (tick % 4 == 0 || animation.value < .005) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(screen),
          );
          final image = (await tester.runAsync(() => boundary.toImage()))!;
          final rgba = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          // The solid red photo must not paint over either blue reader bar.
          for (final y in [10, 834]) {
            final red = rgba.getUint8((y * image.width + 100) * 4);
            expect(
              red,
              lessThan(80),
              reason: 'toolbar pixel at y=$y, frame $tick',
            );
          }
          image.dispose();
          pixelFrames++;
        }
        await tester.pump(
          Duration(milliseconds: animation.value < .08 ? 1 : 16),
        );
      }
      expect(nearEnd, isTrue);
      expect(pixelFrames, greaterThan(4));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('return rounds the photo before it lands', (tester) async {
    await _open(tester);
    await _close(tester);
    final flight = find.byKey(const ValueKey('image-viewer-flight-clip'));
    final corners = find.descendant(
      of: flight,
      matching: find.byType(ClipRRect),
    );
    Radius radius() => tester
        .widget<ClipRRect>(corners.first)
        .borderRadius
        .resolve(TextDirection.ltr)
        .topLeft;
    expect(radius(), Radius.zero);
    await tester.pump(
      AppMotion.viewerChromeOut + const Duration(milliseconds: 230),
    );
    expect(radius().x, greaterThan(10));
    await tester.pumpAndSettle();
    expect(flight, findsNothing);
  });

  testWidgets('a second Back stops the photo painting above the list', (
    tester,
  ) async {
    await _open(tester, fromList: true);
    await _close(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_flightClip(tester).isEmpty, isFalse);
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      find.descendant(
        of: find.byType(InlineImageViewer),
        matching: find.byType(ClipRRect),
      ),
      findsWidgets,
    );
    final flight = find.byKey(const ValueKey('image-viewer-flight-clip'));
    if (flight.evaluate().isNotEmpty) {
      expect(_flightClip(tester).isEmpty, isTrue);
    }
    await tester.pumpAndSettle();
    expect(flight, findsNothing);
    expect(find.text('打开帖子'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'zoomed and panned return starts with the same visible photo crop',
    (tester) async {
      await _open(tester);
      await _doubleTap(tester);
      await tester.pumpAndSettle();
      final transform = _transform(tester);
      expect(transform.value.getMaxScaleOnAxis(), closeTo(2, .01));
      transform.value = Matrix4.copy(transform.value)
        ..translateByDouble(40, 30, 0, 1);
      await tester.pump();
      final photo = _globalRect(
        tester,
        find.descendant(
          of: find.byType(ImageViewerPage),
          matching: find.byType(Hero),
        ),
      );
      final viewport = _globalRect(tester, find.byType(PageView));
      final expected = photo.intersect(viewport);
      expect(photo.height, greaterThan(viewport.height));
      expect(photo.top, lessThan(viewport.top));
      await _close(tester);
      _sameRect(_flightClip(tester), expected);
      await tester.pump(AppMotion.viewerChromeOut);
      _sameRect(_flightClip(tester), expected);
      await tester.pump(const Duration(milliseconds: 80));
      expect(_flightClip(tester), isNot(expected));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final button in [false, true]) {
    testWidgets('return freezes an unfinished zoom: close button $button', (
      tester,
    ) async {
      await _open(tester);
      await _doubleTap(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      final transform = _transform(tester);
      final presented = Matrix4.copy(transform.value);
      expect(presented.getMaxScaleOnAxis(), inExclusiveRange(1, 2));
      await _close(tester, button: button);
      expect(transform.value.storage, orderedEquals(presented.storage));
      await tester.pump(const Duration(milliseconds: 32));
      expect(transform.value.storage, orderedEquals(presented.storage));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unzoomed pull return keeps the released translated crop', (
    tester,
  ) async {
    await _open(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InteractiveViewer)),
    );
    await gesture.moveBy(const Offset(0, 260));
    await tester.pump();
    final photo = _globalRect(
      tester,
      find.descendant(
        of: find.byType(ImageViewerPage),
        matching: find.byType(Hero),
      ),
    );
    final viewport = _globalRect(tester, find.byType(PageView));
    await gesture.up();
    await tester.pump();
    await tester.pump();
    _sameRect(_flightClip(tester), photo.intersect(viewport));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion returns without creating a photo flight', (
    tester,
  ) async {
    await _open(tester, reduced: true);
    await _doubleTap(tester);
    await tester.pump();
    expect(_transform(tester).value.getMaxScaleOnAxis(), 2);
    await _close(tester);
    expect(
      find.byKey(const ValueKey('image-viewer-flight-clip')),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
