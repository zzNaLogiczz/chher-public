import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const photoColors = [
  Color(0xffed2929),
  Color(0xff21b841),
  Color(0xff264be7),
  Color(0xffe9cb21),
  Color(0xffd02ad7),
  Color(0xff18babc),
];

Future<List<MemoryImage>> makePhotos(
  WidgetTester tester, {
  List<Size>? sizes,
}) async => (await tester.runAsync(() async {
  final result = <MemoryImage>[];
  for (var i = 0; i < (sizes?.length ?? photoColors.length); i++) {
    final size = sizes?[i] ?? const Size(96, 72);
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawColor(photoColors[i % photoColors.length], BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    result.add(MemoryImage(bytes!.buffer.asUint8List()));
    image.dispose();
    picture.dispose();
  }
  return result;
}))!;

Finder get stackStage => find.byKey(const ValueKey('image-stack-stage'));
Finder stackCard(int index) => find.byKey(ValueKey('image-stack-card-$index'));
Finder stackPhoto(int index) => find.byKey(ValueKey('image-stack-photo-$index'));

/// Mirror of the B-frame geometry: median ratio clamped, height capped.
({double fw, double fh}) frameOf(double stageW, double medianRatio) {
  const peek = 8.0;
  final fw = stageW - peek * 2;
  final cap = math.min(stageW * 1.25, 400.0);
  final fh = (fw / medianRatio.clamp(0.8, 16 / 9)).clamp(
    math.min(fw * 0.5625, cap).toDouble(),
    cap,
  );
  return (fw: fw, fh: fh);
}

/// Mirror of the in-frame photo placement: full display, long shots fill
/// the frame width from the top, everything else is centered contain.
Rect innerRectOf(double ratio, double w, double h) {
  final ih = w / ratio;
  if (ih <= h) return Rect.fromLTWH(0, (h - ih) / 2, w, ih);
  if (ratio >= 0.4) {
    final iw = h * ratio;
    return Rect.fromLTWH((w - iw) / 2, 0, iw, h);
  }
  return Rect.fromLTWH(0, 0, w, h);
}

Future<void> mountStack(
  WidgetTester tester, {
  int count = 6,
  Size viewport = const Size(390, 844),
  Brightness brightness = Brightness.light,
  bool reduced = false,
  bool compact = false,
  List<MemoryImage>? photos,
  Set<String>? requested,
  PageStorageBucket? bucket,
  bool show = true,
  bool? expanded,
  ValueChanged<bool>? onExpandedChanged,
  bool scrollable = true,
  double trailing = 0,
  EdgeInsets? mediaPadding,
  EdgeInsets? safePadding,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  photos ??= await makePhotos(tester);
  final images = photos;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          padding: mediaPadding,
          viewPadding: safePadding,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: PageStorage(
          bucket: bucket ?? PageStorageBucket(),
          child: _ScrollHost(
            scrollable: scrollable,
            trailing: trailing,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: show
                  ? ImageStackGallery(
                      key: const PageStorageKey('native-gallery'),
                      urls: List.generate(count, (i) => 'photo-$i'),
                      gallery: List.generate(count + 3, (i) => 'full-$i'),
                      galleryStartIndex: 2,
                      compact: compact,
                      expanded: expanded,
                      onExpandedChanged: onExpandedChanged,
                      imageProviderBuilder: (url, width) {
                        requested?.add(url);
                        return images[int.parse(url.split('-').last) %
                            images.length];
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
  if (show) {
    final context = tester.element(find.byType(ImageStackGallery));
    for (final image in images) {
      await tester.runAsync(() => precacheImage(image, context));
    }
  }
  await tester.pumpAndSettle();
}

class _ScrollHost extends StatelessWidget {
  final bool scrollable;
  final double trailing;
  final Widget child;
  const _ScrollHost({
    required this.scrollable,
    required this.trailing,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => scrollable
      ? SizedBox.expand(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                if (trailing > 0) SizedBox(height: trailing),
              ],
            ),
          ),
        )
      : Align(alignment: Alignment.topCenter, child: child);
}

Future<void> swipe(WidgetTester tester, {bool previous = false}) async {
  await tester.fling(
    stackStage,
    Offset(previous ? 240 : -240, 0),
    1000,
  );
  await tester.pumpAndSettle();
}

int storedIndex(WidgetTester tester) {
  final context = tester.element(find.byType(ImageStackGallery));
  return (PageStorage.of(context).readState(
    context,
    identifier: 'image-stack-state',
  ) as Map)['current'] as int;
}

Rect photoRect(WidgetTester tester, int index) {
  final image = tester.renderObject<RenderBox>(find.descendant(
    of: stackPhoto(index),
    matching: find.byType(RawImage),
  ));
  return MatrixUtils.transformRect(
    image.getTransformTo(null),
    Offset.zero & image.size,
  );
}

void main() {
  testWidgets('keeps the frame stage and exposes only the small mode toggle', (
    tester,
  ) async {
    await mountStack(tester);
    expect(stackStage, findsOneWidget);
    expect(find.byType(Text), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(ImageStackModeToggle), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
    final toggle = tester.getRect(find.byType(ImageStackModeToggle));
    final gallery = tester.getRect(find.byType(ImageStackGallery));
    expect(toggle.right, closeTo(gallery.right, 1));
    // B frame keeps its control row under the stage, aligned with the thumbs.
    final stageRect = tester.getRect(stackStage);
    expect(toggle.top, greaterThan(stageRect.bottom));
    expect(toggle.top, lessThan(gallery.bottom));
    expect(toggle.size, const Size(44, 44));
    // The frame stage keeps one fixed height: median ratio of 4:3 photos.
    final frame = frameOf(350, 4 / 3);
    expect(tester.getSize(stackStage).height, closeTo(frame.fh, 1));
    expect(tester.getSize(stackStage).width, closeTo(350, 1));
  });

  testWidgets('near-screen geometry keeps full median-ratio photos visible', (
    tester,
  ) async {
    final photos = await makePhotos(
      tester,
      sizes: [const Size(90, 160), const Size(90, 160), const Size(90, 160)],
    );
    await mountStack(tester, count: 3, photos: photos);
    final frame = frameOf(350, 9 / 16);
    expect(tester.getSize(stackStage).height, closeTo(frame.fh, 1));
    // Tall photos stay fully visible inside the frame (centered, unclipped).
    final bounds = photoRect(tester, 0);
    expect(bounds.size.aspectRatio, closeTo(9 / 16, .001));
    expect(bounds.size.height, closeTo(frame.fh, 1));
    expect(
      bounds.top,
      closeTo(tester.getTopLeft(stackStage).dy + (frame.fh - frame.fh) / 2, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mode expands to natural full photos and collapse preserves selection and viewer',
    (tester) async {
      final photos = await makePhotos(
        tester,
        sizes: [const Size(160, 80), const Size(80, 160), const Size(96, 96)],
      );
      await mountStack(tester, count: 3, photos: photos);
      await swipe(tester);
      expect(storedIndex(tester), 1);
      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pumpAndSettle();
      // Expanded list fills the full column width (same as the frame stage);
      // each photo keeps its own ratio, small photos included.
      final expanded = [const Size(350, 175), const Size(350, 700), const Size(350, 350)];
      for (var i = 0; i < 3; i++) {
        final box = tester.renderObject<RenderBox>(stackCard(i));
        final origin = tester.getTopLeft(find.byType(ImageStackGallery));
        final topLeft = tester.getTopLeft(stackCard(i));
        expect(box.size.width, closeTo(expanded[i].width, 1));
        expect(box.size.height, closeTo(expanded[i].height, 1));
        expect(topLeft.dx - origin.dx, closeTo(0, 1));
      }
      expect(find.byType(Text), findsNothing);
      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pumpAndSettle();
      expect(storedIndex(tester), 1);
      expect(stackStage, findsOneWidget);
      expect(
        tester
            .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
            .expanded,
        isFalse,
      );
      await tester.tapAt(tester.getCenter(stackStage));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ImageViewerPage>(find.byType(ImageViewerPage))
            .initialIndex,
        3,
      );
    },
  );

  for (final viewport in [
    const Size(390, 844),
    const Size(320, 568),
    const Size(844, 390),
  ]) {
    testWidgets(
      'frame stage follows the median ratio and stays stable at $viewport',
      (tester) async {
        final photos = await makePhotos(
          tester,
          sizes: [
            const Size(90, 160),
            const Size(160, 90),
            const Size(32, 640),
          ],
        );
        await mountStack(
          tester,
          count: 3,
          viewport: viewport,
          photos: photos,
          trailing: 1200,
        );
        final gallery = find.byType(ImageStackGallery);
        final context = tester.element(gallery);
        final scroll = Scrollable.maybeOf(
          context,
          axis: Axis.vertical,
        )!.position;
        final stageW = tester.getSize(gallery).width;
        final frame = frameOf(stageW, 9 / 16);
        final before = tester.getSize(stackStage);
        expect(before.height, closeTo(frame.fh, 1));
        final sourceRatios = [9 / 16, 16 / 9, 32 / 640];
        for (var i = 0; i < 3; i++) {
          final rect = photoRect(tester, i);
          // Uniform scale on stacked cards keeps the photo's aspect ratio;
          // exact placement is asserted only for the current (unscaled) card.
          // The long shot fills the frame width and shows its top, so its
          // displayed ratio is the frame's, not the source's.
          expect(
            rect.size.aspectRatio,
            closeTo(i == 2 ? frame.fw / frame.fh : sourceRatios[i], .01),
            reason: 'photo $i',
          );
          if (i == 0) {
            final inner = innerRectOf(sourceRatios[i], frame.fw, frame.fh);
            final stageOrigin = tester.getTopLeft(stackStage);
            expect(rect.size.width, closeTo(inner.width, 1.5));
            expect(rect.size.height, closeTo(inner.height, 1.5));
            expect(rect.left - stageOrigin.dx, closeTo(inner.left, 1.5));
            expect(rect.top - stageOrigin.dy, closeTo(inner.top, 1.5));
          }
        }
        scroll.jumpTo(180);
        await tester.pumpAndSettle();
        expect(tester.getSize(stackStage), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'safe areas and an extended-body reading overlay keep the frame stable',
    (tester) async {
      const padding = EdgeInsets.only(top: 24, bottom: 34 + 96);
      await mountStack(
        tester,
        count: 3,
        trailing: 1200,
        mediaPadding: padding,
        safePadding: const EdgeInsets.only(top: 24, bottom: 34),
      );
      final context = tester.element(find.byType(ImageStackGallery));
      final actualPadding = MediaQuery.paddingOf(context);
      expect(actualPadding, padding);
      final size = tester.getSize(stackStage);
      final frame = frameOf(350, 4 / 3);
      expect(size.height, closeTo(frame.fh, 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.getSize(stackStage), size);
      final scroll = Scrollable.maybeOf(
        context,
        axis: Axis.vertical,
      )!.position;
      scroll.jumpTo(120);
      await tester.pumpAndSettle();
      expect(tester.getSize(stackStage), size);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'orientation uses the updated width without losing selection',
    (tester) async {
      await mountStack(tester, count: 3);
      await swipe(tester);
      expect(storedIndex(tester), 1);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ImageStackGallery));
      final viewport = Scrollable.maybeOf(
        context,
        axis: Axis.vertical,
      )!.position.viewportDimension;
      expect(viewport, 390);
      final stageW = tester.getSize(find.byType(ImageStackGallery)).width;
      final frame = frameOf(stageW, 4 / 3);
      expect(tester.getSize(stackStage).height, closeTo(frame.fh, 1));
      expect(storedIndex(tester), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'without a reader Scrollable the gallery still lays out safely',
    (tester) async {
      await mountStack(tester, count: 3, scrollable: false);
      final context = tester.element(find.byType(ImageStackGallery));
      expect(Scrollable.maybeOf(context, axis: Axis.vertical), isNull);
      expect(tester.getSize(stackStage).height, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('horizontal gestures stop at the ends with rubber band', (
    tester,
  ) async {
    await mountStack(tester, count: 3);
    await swipe(tester);
    expect(storedIndex(tester), 1);
    await swipe(tester);
    expect(storedIndex(tester), 2);
    // The frame version bounces at the ends instead of looping around.
    await swipe(tester);
    expect(storedIndex(tester), 2);
    await swipe(tester, previous: true);
    expect(storedIndex(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection survives lazy unmount and restore', (tester) async {
    final bucket = PageStorageBucket();
    final photos = await makePhotos(tester);
    await mountStack(tester, bucket: bucket, photos: photos);
    await swipe(tester);
    await swipe(tester);
    expect(storedIndex(tester), 2);
    await mountStack(tester, bucket: bucket, photos: photos, show: false);
    await mountStack(tester, bucket: bucket, photos: photos);
    expect(storedIndex(tester), 2);
    expect(find.bySemanticsLabel('连续图片，第 3 张，共 6 张'), findsOneWidget);
  });

  testWidgets('shrinking a URL list clamps the saved selection safely', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final photos = await makePhotos(tester);
    await mountStack(tester, bucket: bucket, photos: photos);
    for (var i = 0; i < 4; i++) {
      await swipe(tester);
    }
    await mountStack(tester, bucket: bucket, photos: photos, count: 2);
    expect(storedIndex(tester), inInclusiveRange(0, 1));
    await swipe(tester);
    expect(storedIndex(tester), inInclusiveRange(0, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap opens the whole floor gallery at the selected offset', (
    tester,
  ) async {
    await mountStack(tester);
    await swipe(tester);
    await swipe(tester);
    await tester.tapAt(tester.getCenter(stackStage));
    await tester.pumpAndSettle();
    final viewer = tester.widget<ImageViewerPage>(find.byType(ImageViewerPage));
    expect(viewer.urls, List.generate(9, (i) => 'full-$i'));
    expect(viewer.initialIndex, 4);
  });

  testWidgets('a thousand-photo gallery keeps decode requests windowed', (
    tester,
  ) async {
    final requested = <String>{};
    await mountStack(tester, count: 1000, requested: requested);
    // Deck window: current card plus up to two behind and two ahead, one
    // frame ambience layer each, and a single live scrub thumb for long runs.
    int livePhotoCount() => find
        .descendant(
          of: find.byType(ImageStackGallery),
          matching: find.byWidgetPredicate(
            (w) => w is Image && (w.key ?? const Key('')).toString().contains(
                  'image-stack-photo',
                ),
          ),
        )
        .evaluate()
        .length;
    expect(livePhotoCount(), lessThanOrEqualTo(6));
    for (var i = 0; i < 10; i++) {
      await swipe(tester);
      expect(livePhotoCount(), lessThanOrEqualTo(6));
    }
    expect(requested.length, lessThanOrEqualTo(40));
  });

  testWidgets('screen reader and keyboard retain index and gallery access', (
    tester,
  ) async {
    await mountStack(tester);
    final semantics = tester.ensureSemantics();

    expect(find.bySemanticsLabel('连续图片，第 1 张，共 6 张'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(storedIndex(tester), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(storedIndex(tester), 0);
    semantics.dispose();
  });

  testWidgets('reduced motion has no residual animation after selection', (
    tester,
  ) async {
    await mountStack(tester, reduced: true);
    await swipe(tester);
    expect(storedIndex(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
