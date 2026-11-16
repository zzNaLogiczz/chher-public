import 'package:chh_app/design/image_tokens.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://static.chiphell.com/local-viewer-fixture.jpeg';

Future<ImageProvider<Object>> _mount(
  WidgetTester tester, {
  bool reduced = false,
}) async {
  final provider = boundedNetworkImage(
    _url,
    boundedImageDecodeWidth(320, tester.view.devicePixelRatio),
  );
  final key = await provider.obtainKey(ImageConfiguration.empty);
  final frame = (await tester.runAsync(
    () => createTestImage(width: 320, height: 200, cache: false),
  ))!;
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: frame))),
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: InlineImageViewer(url: _url, gallery: [_url]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(InlineImageViewer));
  await tester.pumpAndSettle();
}

double _offset(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('image-viewer-drag')))
    .transform
    .getTranslation()
    .y;

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
    'inline photo keeps its decode provider through Hero and return',
    (tester) async {
      final provider = await _mount(tester);
      final press = tester.widget<PressScale>(find.byType(PressScale).first);
      expect(press.scale, AppPressScale.content);
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect(clip.borderRadius, BorderRadius.circular(ImageTokens.radius));
      final tag = tester.widget<Hero>(find.byType(Hero)).tag;
      final sourceProvider = tester.widget<Image>(find.byType(Image)).image;
      await tester.tap(find.byType(InlineImageViewer));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final viewer = tester.widget<ImageViewerPage>(
        find.byType(ImageViewerPage),
      );
      expect(viewer.heroTag, same(tag));
      expect(viewer.previewImage, same(sourceProvider));
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images, isNotEmpty);
      final sourceKey = await provider.obtainKey(ImageConfiguration.empty);
      for (final image in images) {
        expect(
          await image.image.obtainKey(ImageConfiguration.empty),
          sourceKey,
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭图片'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
      expect(tester.widget<Hero>(find.byType(Hero)).tag, same(tag));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pull follows pixels, cancels, and can be caught during rebound',
    (tester) async {
      await _mount(tester);
      await _open(tester);
      final start = tester.getCenter(find.byType(InteractiveViewer));
      final drag = await tester.startGesture(start);
      await drag.moveBy(const Offset(0, 90));
      await tester.pump();
      expect(_offset(tester), closeTo(90, .01));
      final scale = tester
          .widget<Transform>(
            find.byKey(const ValueKey('image-viewer-drag-scale')),
          )
          .transform
          .entry(0, 0);
      expect(scale, lessThan(1));
      final backgrounds = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      );
      expect(
        backgrounds.any((box) => box.color.a > 0 && box.color.a < 1),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(_offset(tester), closeTo(90, .01));
      await drag.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final before = _offset(tester);
      expect(before, inExclusiveRange(0, 90));
      final retry = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_offset(tester), closeTo(before, .01));
      await retry.moveBy(const Offset(0, 25));
      await tester.pump();
      expect(_offset(tester), closeTo(before + 25, .01));
      await retry.cancel();
      await tester.pumpAndSettle();
      expect(_offset(tester), 0);
      expect(find.byType(ImageViewerPage), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('fast downward release closes while a horizontal move does not', (
    tester,
  ) async {
    await _mount(tester);
    await _open(tester);
    final target = find.byType(InteractiveViewer);
    await tester.drag(target, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(_offset(tester), 0);
    expect(find.byType(ImageViewerPage), findsOneWidget);
    await tester.fling(target, const Offset(0, 120), 1400);
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion disables photo flight and settles immediately', (
    tester,
  ) async {
    await _mount(tester, reduced: true);
    expect(tester.widget<HeroMode>(find.byType(HeroMode)).enabled, isFalse);
    await _open(tester);
    expect(
      find.descendant(
        of: find.byType(ImageViewerPage),
        matching: find.byType(Hero),
      ),
      findsNothing,
    );
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(InteractiveViewer)),
    );
    await drag.moveBy(const Offset(0, 80));
    await tester.pump();
    await drag.cancel();
    await tester.pump();
    expect(_offset(tester), 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('double tap zoom keeps the original save action reachable', (
    tester,
  ) async {
    await _mount(tester);
    final original = await const ChhCachedImage(
      _url,
      headers: chhImageHeaders,
    ).obtainKey(ImageConfiguration.empty);
    final frame = (await tester.runAsync(
      () => createTestImage(width: 320, height: 200, cache: false),
    ))!;
    PaintingBinding.instance.imageCache.putIfAbsent(
      original,
      () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: frame))),
    );
    await _open(tester);
    final photo = find.byType(InteractiveViewer);
    await tester.tap(photo);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InteractiveViewer>(photo)
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      closeTo(2, .01),
    );
    expect(find.byTooltip('保存图片').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('group paging synchronizes the return Hero before dismissal', (
    tester,
  ) async {
    final provider = await _mount(tester);
    var current = 0;
    final tags = [Object(), Object()];
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => openImageViewer(
                  context,
                  urls: const [_url, _url],
                  previewImage: provider,
                  heroTagForIndex: (index) => tags[index],
                  previewImageForIndex: (_) => provider,
                  onPageChanged: (index) => setState(() => current = index),
                ),
                child: Hero(
                  tag: tags[current],
                  child: SizedBox(
                    width: 320,
                    height: 200,
                    child: Image(image: provider),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byTooltip('保存图片'), findsOneWidget);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(current, 1);
    expect(find.text('2 / 2'), findsOneWidget);
    final viewer = tester.widget<ImageViewerPage>(find.byType(ImageViewerPage));
    expect(viewer.heroTagForIndex!(1), tags[1]);
    await tester.fling(
      find.byType(InteractiveViewer).last,
      const Offset(0, 120),
      1400,
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsNothing);
    expect(tester.widget<Hero>(find.byType(Hero)).tag, tags[1]);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
