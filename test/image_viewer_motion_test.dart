import 'dart:async';

import 'package:chh_app/design/image_tokens.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/system_ui.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/ui/image_viewer_chrome.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/anchored_reading_list.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://static.chiphell.com/local-viewer-fixture.jpeg';

Future<ImageProvider<Object>> _seedPhoto(
  WidgetTester tester,
  double width,
) async {
  final provider = boundedNetworkImage(
    _url,
    boundedImageDecodeWidth(width, tester.view.devicePixelRatio),
  );
  final key = await provider.obtainKey(ImageConfiguration.empty);
  final frame = (await tester.runAsync(
    () => createTestImage(width: 320, height: 200, cache: false),
  ))!;
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: frame))),
  );
  return provider;
}

Future<ImageProvider<Object>> _mount(
  WidgetTester tester, {
  bool reduced = false,
  Brightness brightness = Brightness.light,
}) async {
  final provider = await _seedPhoto(tester, 320);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          padding: const EdgeInsets.only(top: 24),
          viewPadding: const EdgeInsets.only(top: 24),
        ),
        child: child!,
      ),
      home: const ImageViewerChromeScope(
        child: Scaffold(
          body: Column(
            children: [
              ImageViewerReaderChrome(
                key: ValueKey('reader-chrome'),
                child: Text('阅读工具栏'),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 320,
                    child: InlineImageViewer(url: _url, gallery: [_url]),
                  ),
                ),
              ),
            ],
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

double _readerChrome(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('reader-chrome')),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

double _viewerChrome(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(
        of: find.text('1 / 1', skipOffstage: false),
        matching: find.byType(Opacity, skipOffstage: false),
      ),
    )
    .opacity;

double _scrim(WidgetTester tester) => tester
    .widget<ColoredBox>(find.byKey(const ValueKey('image-viewer-scrim')))
    .color
    .a;

SystemUiOverlayStyle _statusStyle(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(
        const ValueKey('image-viewer-status-style'),
        skipOffstage: false,
      ),
    )
    .value;

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
    'system Back keeps thread layout and prefetch out of the flight',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _seedPhoto(tester, 358);
      final pending = Completer<ThreadDetail>();
      final reads = <int>[];
      ThreadDetail detail(int number) => ThreadDetail(
        tid: 123,
        title: '图片主题',
        posts: [
          Post(
            pid: number,
            floor: number,
            author: '作者',
            timeRaw: '',
            content: [
              if (number == 1) const ImageBlock(_url),
              TextBlock(List.filled(120, '阅读内容').join('\n')),
            ],
          ),
        ],
        page: PageInfo(current: number, hasNext: number == 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: ThreadDetailPage(
            tid: 123,
            title: '图片主题',
            loadPage: (number, _, _) async {
              reads.add(number);
              return number == 1 ? detail(1) : pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(reads, [1, 2]);
      await _open(tester);
      final list = find.byType(AnchoredReadingList);
      final before = tester.widget<AnchoredReadingList>(list);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(AppMotion.viewerChromeOut);
      expect(find.byType(ImageViewerPage), findsOneWidget);
      expect(tester.widget<AnchoredReadingList>(list), same(before));

      pending.complete(detail(2));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.widget<AnchoredReadingList>(list), same(before));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
      expect(
        tester.widget<AnchoredReadingList>(list).itemCount,
        greaterThan(before.itemCount),
      );
      expect(reads, [1, 2]);
    },
  );

  testWidgets('a portal thread keeps the same reader during system Back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _seedPhoto(tester, 358);
    const detail = ThreadDetail(
      tid: 123,
      title: '门户主题',
      posts: [
        Post(
          pid: 1,
          floor: 1,
          author: '作者',
          timeRaw: '',
          content: [ImageBlock(_url)],
        ),
      ],
      page: PageInfo(current: 1, hasNext: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ArticlePage(
          aid: 1,
          title: '门户主题',
          loadPage: (_, _) async => ThreadContent(
            123,
            '门户主题',
            detail: detail,
            cacheGeneration: chhClient.cacheGeneration,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _open(tester);
    final reader = find.byType(ThreadDetailPage);
    final before = tester.widget<ThreadDetailPage>(reader);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(AppMotion.viewerChromeOut);
    expect(find.byType(ImageViewerPage), findsOneWidget);
    expect(tester.widget<ThreadDetailPage>(reader), same(before));
    await tester.pumpAndSettle();
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

  testWidgets('reader and viewer chrome never overlap across the Hero', (
    tester,
  ) async {
    await _mount(tester);
    final source = find.byType(InlineImageViewer);
    final sourceRect = tester.getRect(source);
    await tester.tap(source);
    // A single frame builds the destination and registers the Hero flight.
    await tester.pump();
    expect(find.byType(ImageViewerPage, skipOffstage: false), findsOneWidget);
    expect(_viewerChrome(tester), 0);
    expect(_statusStyle(tester), AppSystemUi.darkIcons);
    await tester.pump(const Duration(milliseconds: 16));
    final flight = find.byKey(const ValueKey('image-viewer-open-flight'));
    expect(flight, findsOneWidget);
    expect(tester.getRect(flight), isNot(sourceRect));
    expect(_readerChrome(tester), inExclusiveRange(0, 1));
    expect(_viewerChrome(tester), 0);

    final quarter = Duration(
      microseconds: AppMotion.heroDuration.inMicroseconds ~/ 4,
    );
    await tester.pump(quarter - const Duration(milliseconds: 16));
    final quarterAlpha = _scrim(tester);
    expect(
      quarterAlpha,
      closeTo(AppMotion.viewerScrimCurve.transform(.25), .01),
    );
    expect(_statusStyle(tester), AppSystemUi.darkIcons);
    await tester.pump(quarter);
    expect(_scrim(tester), greaterThan(.5));
    expect(_statusStyle(tester), AppSystemUi.lightIcons);
    expect(_readerChrome(tester), 0);
    expect(_viewerChrome(tester), 0);

    await tester.pump(AppMotion.heroDuration);
    expect(_viewerChrome(tester), 0);
    await tester.pump(const Duration(milliseconds: 75));
    expect(_viewerChrome(tester), inExclusiveRange(0, 1));
    expect(_readerChrome(tester), 0);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_viewerChrome(tester), closeTo(.5, .01));
    expect(_readerChrome(tester), 0);
    expect(_scrim(tester), 1);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_viewerChrome(tester), 0);
    expect(_scrim(tester), closeTo(1, .001));
    await tester.pump(AppMotion.reveal.duration * .75);
    expect(_scrim(tester), closeTo(quarterAlpha, .01));
    expect(_statusStyle(tester), AppSystemUi.darkIcons);
    expect(_viewerChrome(tester), 0);
    expect(_readerChrome(tester), 0);

    await tester.pump(AppMotion.reveal.duration);
    await tester.pump();
    expect(find.byType(ImageViewerPage), findsNothing);
    await tester.pump(const Duration(milliseconds: 75));
    expect(_readerChrome(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_readerChrome(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'predictive back can cancel and commit with the right status icons',
    (tester) async {
      await _mount(tester);
      await _open(tester);
      final route = ModalRoute.of(
        tester.element(find.byType(ImageViewerPage)),
      )!;
      route.handleStartBackGesture(progress: 1);
      route.handleUpdateBackGestureProgress(progress: .25);
      await tester.pump();
      expect(_scrim(tester), lessThan(.5));
      expect(_statusStyle(tester), AppSystemUi.darkIcons);
      expect(_viewerChrome(tester), closeTo(.25, .01));
      expect(_readerChrome(tester), 0);
      route.handleCancelBackGesture();
      await tester.pumpAndSettle();
      expect(_viewerChrome(tester), 1);
      expect(_statusStyle(tester), AppSystemUi.lightIcons);

      route.handleStartBackGesture(progress: 1);
      route.handleUpdateBackGestureProgress(progress: .25);
      await tester.pump();
      route.handleCommitBackGesture();
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
      expect(_readerChrome(tester), 1);
    },
  );

  testWidgets('dark body photo and viewer share one tinted decode provider', (
    tester,
  ) async {
    await _mount(tester, brightness: Brightness.dark);
    final source = tester.widget<Image>(find.byType(Image));
    expect(source.color, ImageTokens.darkTint);
    expect(source.colorBlendMode, BlendMode.modulate);
    await _open(tester);
    final viewer = tester.widget<Image>(
      find.descendant(
        of: find.byType(ImageViewerPage),
        matching: find.byType(Image),
      ),
    );
    expect(viewer.color, ImageTokens.darkTint);
    expect(viewer.colorBlendMode, BlendMode.modulate);
    expect(viewer.image, same(source.image));
  });

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
