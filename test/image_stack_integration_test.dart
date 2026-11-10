import 'dart:async';
import 'dart:io';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/article_image.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String photo(int n) => 'https://example.invalid/stack-integration-$n.png';
Post post(List<ContentBlock> blocks, {int floor = 1}) => Post(
  pid: floor,
  floor: floor,
  author: '本地作者',
  timeRaw: '',
  content: blocks,
);
Future<void> mount(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: body is ThreadDetailPage
          ? body
          : Scaffold(body: SingleChildScrollView(child: body)),
    ),
  );
  await tester.pumpAndSettle();
}

ThreadDetailPage thread(Post value) => ThreadDetailPage(
  tid: 123,
  title: '本地图片讨论',
  loadPage: (_, _, _) async => ThreadDetail(
    tid: 123,
    fid: 290,
    title: '本地图片讨论',
    posts: [value],
    page: const PageInfo(current: 1, hasNext: false),
  ),
);
Finder semantic(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);
Future<void> openAndCheck(
  WidgetTester tester,
  Finder target,
  List<String> urls,
  int index,
) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  final viewer = tester.widget<ImageViewerPage>(find.byType(ImageViewerPage));
  expect(viewer.urls, urls);
  expect(viewer.initialIndex, index);
  await tester.tap(find.byTooltip('关闭图片'));
  await tester.pumpAndSettle();
}

Finder photoPixels(int index) => find.descendant(
  of: find.byKey(ValueKey('image-stack-photo-$index')),
  matching: find.byType(RawImage),
);

Rect photoBounds(WidgetTester tester, int index, Finder stage) {
  final image = tester.renderObject<RenderBox>(photoPixels(index));
  final panel = tester.renderObject<RenderBox>(stage);
  return MatrixUtils.transformRect(
    image.getTransformTo(panel),
    Offset.zero & image.size,
  );
}

Future<void> toggleGroup(WidgetTester tester, Finder group) async {
  final control = find.descendant(
    of: group,
    matching: find.byType(ImageStackModeToggle),
  );
  expect(control, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(control), alignment: .2);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> primePhotos(WidgetTester tester, Map<String, Size> sizes) async {
  // Extreme fixtures (240x4800) reach ~4.6MB per cached decode; the default
  // 100MB budget evicts the small probe keys first. Raise it for the test.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 512 << 20;
  for (final entry in sizes.entries) {
    final image = (await tester.runAsync(
      () => createTestImage(
        width: entry.value.width.toInt(),
        height: entry.value.height.toInt(),
        cache: false,
      ),
    ))!;
    // Probe / ambience / scrub thumb use small fixed two-dimensional keys.
    for (final (w, h) in [(64, 128), (18, 48), (128, 128)]) {
      final key = await boundedNetworkImageBox(
        entry.key,
        w,
        h,
      ).obtainKey(ImageConfiguration.empty);
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())),
        ),
      );
    }
    // Main photos decode at twice the layout width for the 390dp viewport:
    // frame 358 -> 716, expanded column 374 -> 748.
    for (final width in [
      128,
      192,
      256,
      320,
      384,
      448,
      512,
      640,
      716,
      748,
      768,
      1024,
    ]) {
      final key = await boundedNetworkImageBox(
        entry.key,
        width,
        2048,
      ).obtainKey(ImageConfiguration.empty);
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())),
        ),
      );
    }
    final viewerKey = await boundedNetworkImage(
      entry.key,
      448,
    ).obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.putIfAbsent(
      viewerKey,
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: image.clone())),
      ),
    );
    image.dispose();
  }
}

Future<void> actualPanel(WidgetTester tester, {bool extreme = false}) async {
  final urls = [for (var i = 0; i < 6; i++) photo(100 + i)];
  await primePhotos(tester, {
    for (var i = 0; i < urls.length; i++)
      urls[i]: extreme && i == 0
          ? const Size(240, 4800)
          : i.isOdd
          ? const Size(240, 450)
          : const Size(640, 360),
  });
  await mount(tester, thread(post([for (final url in urls) ImageBlock(url)])));
}

void main() {
  testWidgets('a mounted gallery adopts late restored expansion', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('late-images-');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/reading-v1.json').writeAsStringSync(
      '{"version":1,"fontSize":"m","lineHeight":"standard","layout":"comfy","imagesExpanded":true}',
    );
    final pending = Completer<Directory?>();
    final controller = ReadingPrefsController(directory: () => pending.future);
    addTearDown(controller.dispose);
    late Future<void> loading;
    await tester.runAsync(() async {
      loading = controller.load();
    });
    await primePhotos(tester, {
      photo(850): const Size(240, 160),
      photo(851): const Size(240, 160),
    });
    await mount(
      tester,
      ReadingScope(
        controller: controller,
        child: SingleChildScrollView(
          child: ImageStackGallery(
            urls: [photo(850), photo(851)],
            gallery: [photo(850), photo(851)],
            galleryStartIndex: 0,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
          .expanded,
      isFalse,
    );
    await tester.runAsync(() async {
      pending.complete(directory);
      await loading;
    });
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
          .expanded,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('image choice applies to a new gallery across threads', (
    tester,
  ) async {
    final controller = ReadingPrefsController(directory: () async => null);
    addTearDown(controller.dispose);
    Widget gallery(int id) => ReadingScope(
      controller: controller,
      child: SingleChildScrollView(
        child: ImageStackGallery(
          key: ValueKey(id),
          urls: [photo(id), photo(id + 1)],
          gallery: [photo(id), photo(id + 1)],
          galleryStartIndex: 0,
        ),
      ),
    );
    await primePhotos(tester, {
      for (var i = 800; i < 804; i++) photo(i): const Size(240, 160),
    });
    await mount(tester, gallery(800));
    expect(
      tester
          .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
          .expanded,
      isFalse,
    );
    await toggleGroup(tester, find.byType(ImageStackGallery));
    expect(controller.prefs.imagesExpanded, isTrue);
    await mount(tester, gallery(802));
    expect(
      tester
          .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
          .expanded,
      isTrue,
    );
    await toggleGroup(tester, find.byType(ImageStackGallery));
    expect(controller.prefs.imagesExpanded, isFalse);
    expect(tester.takeException(), isNull);
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  for (final mode in ['opening', 'floor', 'comment', 'nested']) {
    testWidgets(
      '$mode preserves separated groups, standalone image and full gallery',
      (tester) async {
        final urls = [for (var i = 0; i < 5; i++) photo(i)];
        final value = post([
          const TextBlock('图片之前'),
          ImageBlock(urls[0]),
          ImageBlock(urls[1]),
          const TextBlock('第一段说明'),
          ImageBlock(urls[2]),
          const TextBlock('独立图片之后'),
          ImageBlock(urls[3]),
          ImageBlock(urls[4]),
        ], floor: mode == 'opening' ? 1 : 2);
        await mount(
          tester,
          PostCard(
            post: value,
            isOpening: mode == 'opening',
            commentStyle: mode == 'comment' || mode == 'nested',
            nested: mode == 'nested',
          ),
        );
        final stacks = tester
            .widgetList<ImageStackGallery>(find.byType(ImageStackGallery))
            .toList();
        expect(stacks, hasLength(2));
        expect(
          find.descendant(
            of: find.byType(ImageStackGallery),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
        expect(find.textContaining('连续图片'), findsNothing);
        expect(find.text('1 / 2'), findsNothing);
        expect(find.byType(ListView), findsNothing);
        expect(
          find.descendant(
            of: find.byType(ImageStackGallery),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Icon &&
                  [
                    AppIcons.back,
                    AppIcons.forward,
                    AppIcons.search,
                  ].contains(w.icon),
            ),
          ),
          findsNothing,
        );
        expect(stacks.map((s) => s.urls), [
          [urls[0], urls[1]],
          [urls[3], urls[4]],
        ]);
        expect(stacks.map((s) => s.galleryStartIndex), [0, 3]);
        expect(
          stacks.every((s) => s.gallery.join('|') == urls.join('|')),
          isTrue,
        );
        expect(stacks.every((s) => s.compact == (mode != 'opening')), isTrue);
        expect(tester.widget<ImageGrid>(find.byType(ImageGrid)).urls, [
          urls[2],
        ]);
        final first = find.byType(ImageStackGallery).first;
        final second = find.byType(ImageStackGallery).last;
        expect(
          tester.getTopLeft(first).dy,
          lessThan(tester.getTopLeft(find.text('第一段说明')).dy),
        );
        expect(
          tester.getTopLeft(find.text('独立图片之后')).dy,
          lessThan(tester.getTopLeft(second).dy),
        );
        await openAndCheck(tester, semantic('查看第 3 张图片'), urls, 2);
        // Advancing the second group must open the fifth full-floor image.
        final secondStage = find.descendant(
          of: second,
          matching: find.byKey(const ValueKey('image-stack-stage')),
        );
        await tester.ensureVisible(secondStage);
        await tester.pumpAndSettle();
        await tester.fling(secondStage, const Offset(-220, 0), 1000);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: second, matching: semantic('连续图片，第 2 张，共 2 张')),
          findsOneWidget,
        );
        await openAndCheck(
          tester,
          find.descendant(
            of: second,
            matching: find.byKey(const ValueKey('image-stack-stage')),
          ),
          urls,
          4,
        );
        await toggleGroup(tester, second);
        // Expanded list renders every photo of the group as a native card.
        final expandedCards = find.descendant(
          of: second,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label?.startsWith('查看连续图片') ?? false),
          ),
        );
        expect(expandedCards, findsNWidgets(2));
        await openAndCheck(tester, semantic('查看连续图片第 2 张，共 2 张'), urls, 4);
        await toggleGroup(tester, second);
        expect(expandedCards, findsNothing);
        expect(
          find.descendant(of: second, matching: semantic('连续图片，第 2 张，共 2 张')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('repeated URLs keep their position in the full-floor gallery', (
    tester,
  ) async {
    final urls = [photo(0), photo(1), photo(0), photo(2)];
    await mount(
      tester,
      PostCard(
        post: post([
          ImageBlock(urls[0]),
          ImageBlock(urls[1]),
          const TextBlock('两组之间'),
          ImageBlock(urls[2]),
          ImageBlock(urls[3]),
        ]),
        isOpening: true,
      ),
    );
    final second = find.byType(ImageStackGallery).last;
    expect(tester.widget<ImageStackGallery>(second).galleryStartIndex, 2);
    await openAndCheck(
      tester,
      find.descendant(
        of: second,
        matching: find.byKey(const ValueKey('image-stack-stage')),
      ),
      urls,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'appending a group with repeated URLs keeps the selected positional gallery index',
    (tester) async {
      final initial = [photo(0), photo(1), photo(0), photo(2)];
      Widget card(List<String> urls) => PostCard(
        post: post([for (final url in urls) ImageBlock(url)]),
        isOpening: true,
      );
      await mount(tester, card(initial));
      final gallery = find.byType(ImageStackGallery);
      final state = tester.state(gallery);
      final stage = find.descendant(
        of: gallery,
        matching: find.byKey(const ValueKey('image-stack-stage')),
      );
      await tester.fling(stage, const Offset(-200, 0), 800);
      await tester.pumpAndSettle();
      await tester.fling(stage, const Offset(-200, 0), 800);
      await tester.pumpAndSettle();
      expect(semantic('连续图片，第 3 张，共 4 张'), findsOneWidget);
      final appended = [...initial, photo(3)];
      await mount(tester, card(appended));
      expect(identical(tester.state(gallery), state), isTrue);
      expect(semantic('连续图片，第 3 张，共 5 张'), findsOneWidget);
      await openAndCheck(
        tester,
        find.byKey(const ValueKey('image-stack-stage')),
        appended,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'omitted quote still separates images in whole comment rendering',
    (tester) async {
      await mount(
        tester,
        PostCard(
          post: post([
            ImageBlock(photo(0)),
            const QuoteBlock([TextBlock('不展示的引用')]),
            ImageBlock(photo(1)),
          ], floor: 2),
          isOpening: false,
          commentStyle: true,
        ),
      );
      expect(find.byType(ImageStackGallery), findsNothing);
      expect(find.byType(ImageGrid), findsNWidgets(2));
      expect(find.text('不展示的引用'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final floor in [1, 2]) {
    testWidgets(
      'floor $floor retains one frame gallery for a thousand consecutive photos',
      (tester) async {
        final urls = [for (var i = 0; i < 1000; i++) photo(i)];
        await mount(
          tester,
          thread(
            post([
              for (final url in urls) ImageBlock(url),
              const TextBlock('图组之后的正文'),
            ], floor: floor),
          ),
        );
        final galleries = find.byType(ImageStackGallery);
        expect(galleries, findsOneWidget);
        final gallery = tester.widget<ImageStackGallery>(galleries);
        expect(gallery.urls, urls);
        expect(gallery.gallery, urls);
        expect(gallery.galleryStartIndex, 0);
        final stage = find.descendant(
          of: galleries,
          matching: find.byKey(const ValueKey('image-stack-stage')),
        );
        expect(stage, findsOneWidget);
        expect(
          find.descendant(of: galleries, matching: find.byType(Text)),
          findsNothing,
        );
        // Deck keeps a bounded window of live photos and ambience layers,
        // plus one live scrub thumb for long runs.
        int liveImageCount() => find
            .descendant(of: galleries, matching: find.byType(Image))
            .evaluate()
            .length;
        expect(liveImageCount(), lessThanOrEqualTo(13));
        expect(
          find.byType(ArticleImage),
          findsNothing,
          reason:
              'Collapsed groups never append a vertical list of large images',
        );
        final retained = tester.state(galleries);
        await tester.fling(stage, const Offset(-200, 0), 800);
        await tester.pumpAndSettle();
        expect(identical(tester.state(galleries), retained), isTrue);
        expect(semantic('连续图片，第 2 张，共 1000 张'), findsOneWidget);
        expect(find.byType(ImageStackGallery), findsOneWidget);
        expect(liveImageCount(), lessThanOrEqualTo(13));
        await toggleGroup(tester, galleries);
        expect(
          tester
              .widget<ImageStackModeToggle>(
                find.descendant(
                  of: galleries,
                  matching: find.byType(ImageStackModeToggle),
                ),
              )
              .expanded,
          isTrue,
        );
        // The expanded list only mounts cards near the viewport (±1.5 screens).
        final expandedCards = find.descendant(
          of: galleries,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label?.startsWith('查看连续图片') ?? false),
          ),
        );
        expect(expandedCards, findsWidgets);
        expect(expandedCards.evaluate().length, lessThan(12));
        expect(find.byType(ArticleImage).evaluate().length, lessThan(12));
        expect(
          find.descendant(of: galleries, matching: find.byType(Text)),
          findsNothing,
        );
        await toggleGroup(tester, galleries);
        expect(expandedCards, findsNothing);
        expect(
          tester
              .widget<ImageStackModeToggle>(
                find.descendant(
                  of: galleries,
                  matching: find.byType(ImageStackModeToggle),
                ),
              )
              .expanded,
          isFalse,
        );
        expect(semantic('连续图片，第 2 张，共 1000 张'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'lazy comment quote filtering does not merge the runs on its sides',
    (tester) async {
      await mount(
        tester,
        thread(
          post([
            ImageBlock(photo(0)),
            ImageBlock(photo(1)),
            const QuoteBlock([TextBlock('被隐藏的引文')]),
            ImageBlock(photo(2)),
            ImageBlock(photo(3)),
          ], floor: 2),
        ),
      );
      expect(
        tester
            .widget<ImageStackGallery>(find.byType(ImageStackGallery).first)
            .galleryStartIndex,
        0,
      );
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byWidgetPredicate(
          (w) => w is ImageStackGallery && w.galleryStartIndex == 2,
        ),
        150,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      final stacks = tester.widgetList<ImageStackGallery>(
        find.byType(ImageStackGallery),
      );
      expect(stacks.map((s) => s.galleryStartIndex), contains(2));
      expect(find.text('被隐藏的引文'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'blank stage in an actual thread ListView accepts horizontal paging',
    (tester) async {
      await actualPanel(tester);
      final stage = find.byKey(const ValueKey('image-stack-stage'));
      final panelRect = tester.getRect(stage);
      final point = Offset(panelRect.left + 14, panelRect.top + 14);
      final imageBounds = photoBounds(tester, 0, stage);
      expect(
        imageBounds.contains(const Offset(14, 14)),
        isFalse,
        reason: 'The gesture begins in panel space outside the current photo',
      );
      await tester.timedDragFrom(
        point,
        const Offset(-200, 0),
        const Duration(milliseconds: 350),
      );
      await tester.pumpAndSettle();
      expect(semantic('连续图片，第 2 张，共 6 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the frame gallery has a single mode glyph without captions or arrows',
    (tester) async {
      await actualPanel(tester);
      final gallery = find.byType(ImageStackGallery);
      expect(
        find.descendant(
          of: gallery,
          matching: find.byType(ImageStackModeToggle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: gallery, matching: find.byType(Text)),
        findsNothing,
      );
      expect(
        find.descendant(of: gallery, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an extreme 1-to-20 photo fills the frame width from the top', (
    tester,
  ) async {
    await actualPanel(tester, extreme: true);
    final stage = find.byKey(const ValueKey('image-stack-stage'));
    final current = photoPixels(0);
    expect(current, findsOneWidget);
    expect(tester.widget<RawImage>(current).image, isNotNull);
    // Long shots (ratio < 0.4) fill the frame width and show their top,
    // marked with a chip; the full photo is one tap away.
    final bounds = photoBounds(tester, 0, stage);
    final size = tester.getSize(stage);
    expect(bounds.left, closeTo(0, .5));
    // The current card spans the frame width (stage minus the two 8dp peeks).
    expect(bounds.right, closeTo(size.width - 16, .5));
    expect(bounds.top, closeTo(0, .5));
    expect(find.text('长图'), findsOneWidget);
    expect(size.height, lessThan(844 - 120));
    await openAndCheck(tester, stage, [
      for (var i = 0; i < 6; i++) photo(100 + i),
    ], 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'actual thread widens only lazy image rows to 8dp and fills the readable viewport for phone photos',
    (tester) async {
      final urls = [for (var i = 0; i < 6; i++) photo(200 + i)];
      await primePhotos(tester, {
        for (var i = 0; i < 6; i++)
          urls[i]: i == 0 ? const Size(450, 900) : const Size(640, 360),
      });
      await mount(
        tester,
        thread(
          post([
            const TextBlock('图片行之前的正文'),
            for (final url in urls) ImageBlock(url),
            const TextBlock('图片行之后的正文'),
          ]),
        ),
      );
      final gallery = find.byType(ImageStackGallery);
      final galleryRect = tester.getRect(gallery);
      expect(galleryRect.left, closeTo(8, .01));
      expect(galleryRect.right, closeTo(390 - 8, .01));
      final text = find.text('图片行之前的正文');
      final gutter = ReadingMetrics.of(tester.element(text)).gutter;
      expect(tester.getTopLeft(text).dx, closeTo(gutter, .01));
      final stage = find.byKey(const ValueKey('image-stack-stage'));
      final stageSize = tester.getSize(stage);
      // B frame: five landscape photos set the median ratio (16:9), the 1:2
      // lead photo is centered inside the frame without cropping.
      final frameW = stageSize.width - 16;
      final expectedFrameH = frameW / (16 / 9);
      expect(stageSize.height, closeTo(expectedFrameH, 2));
      final bounds = photoBounds(tester, 0, stage);
      expect(bounds.width / bounds.height, closeTo(.5, .001));
      expect(bounds.top, greaterThanOrEqualTo(-.5));
      expect(bounds.left, greaterThan(0));
      expect(bounds.bottom, lessThanOrEqualTo(stageSize.height + .5));
      expect(bounds.right, lessThanOrEqualTo(stageSize.width + .5));
      final mode = find.byType(ImageStackModeToggle);
      expect(
        tester.getRect(mode).right,
        lessThanOrEqualTo(galleryRect.right + .5),
      );
      final position = Scrollable.of(
        tester.element(gallery),
        axis: Axis.vertical,
      ).position;
      final galleryMedia = MediaQuery.of(tester.element(gallery));
      final navigationBottom = galleryMedia.padding.top + NavOverlay.barHeight;
      final target =
          position.pixels + tester.getRect(gallery).top - navigationBottom;
      position.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      final visibleGallery = tester.getRect(gallery);
      final readingBar = tester.getRect(find.byType(ReadingBar));
      expect(visibleGallery.top, greaterThanOrEqualTo(navigationBottom - .5));
      expect(
        visibleGallery.bottom,
        lessThanOrEqualTo(readingBar.top + .5),
        reason:
            'The photograph and mode control together fit above the real reply toolbar',
      );
      expect(
        tester.getRect(mode).top,
        greaterThanOrEqualTo(navigationBottom - .5),
      );
      final stageRender = tester.renderObject<RenderBox>(stage);
      final visiblePhone = bounds.shift(stageRender.localToGlobal(Offset.zero));
      expect(visiblePhone.top, greaterThanOrEqualTo(navigationBottom - .5));
      expect(visiblePhone.bottom, lessThanOrEqualTo(readingBar.top + .5));
      await toggleGroup(tester, gallery);
      // The second photo of the expanded list keeps the full column width.
      final next = semantic('查看连续图片第 2 张，共 6 张');
      await tester.scrollUntilVisible(
        next,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(next).left, closeTo(8, .01));
      expect(tester.getRect(next).right, closeTo(390 - 8, .01));
      await tester.scrollUntilVisible(
        find.text('图片行之后的正文'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('图片行之后的正文')).dx, closeTo(gutter, .01));
      expect(tester.takeException(), isNull);
    },
  );
  for (final count in [2, 3]) {
    testWidgets(
      'short reply with $count adjacent images uses a full-width lazy carousel and a single author header',
      (tester) async {
        final urls = [for (var i = 0; i < count; i++) photo(300 + i)];
        await primePhotos(tester, {
          for (final url in urls) url: const Size(640, 360),
        });
        await mount(
          tester,
          thread(post([for (final url in urls) ImageBlock(url)], floor: 2)),
        );
        final gallery = find.byType(ImageStackGallery);
        expect(gallery, findsOneWidget);
        final rect = tester.getRect(gallery);
        expect(rect.left, closeTo(8, .01));
        expect(rect.right, closeTo(390 - 8, .01));
        expect(find.text('本地作者'), findsOneWidget);
        final reply = find.byKey(const ValueKey('comment-reply-2'));
        await tester.scrollUntilVisible(
          reply,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(reply, findsOneWidget);
        final model = tester.widget<ImageStackGallery>(gallery);
        expect(model.compact, isTrue);
        expect(model.gallery, urls);
        expect(model.galleryStartIndex, 0);
        final stage = find.descendant(
          of: gallery,
          matching: find.byKey(const ValueKey('image-stack-stage')),
        );
        await tester.fling(stage, const Offset(-200, 0), 800);
        await tester.pumpAndSettle();
        expect(semantic('连续图片，第 2 张，共 $count 张'), findsOneWidget);
        await openAndCheck(
          tester,
          find.byKey(const ValueKey('image-stack-stage')),
          urls,
          1,
        );
        await tester.scrollUntilVisible(
          find.text('本地作者'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('本地作者'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'short reply with separated single photos keeps its original whole layout',
    (tester) async {
      await mount(
        tester,
        thread(
          post([
            ImageBlock(photo(400)),
            const TextBlock('单图之间的正文'),
            ImageBlock(photo(401)),
          ], floor: 2),
        ),
      );
      expect(find.byType(ImageStackGallery), findsNothing);
      expect(
        tester
            .widgetList<PostCard>(find.byType(PostCard))
            .where((card) => card.post.pid == 2),
        hasLength(1),
      );
      expect(find.byType(ImageGrid), findsNWidgets(2));
      expect(find.text('单图之间的正文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
