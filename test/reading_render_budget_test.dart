import 'package:chh_app/controllers/article_reader_controller.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:chh_app/widgets/article_image.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:chh_app/widgets/editorial_cover.dart';
import 'package:chh_app/widgets/editorial_article_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'decode widths are bounded physical pixels and preserve aspect by one dimension',
    () {
      expect(boundedImageDecodeWidth(96, 3), 320);
      expect(boundedImageDecodeWidth(36, 3), 128);
      expect(boundedImageDecodeWidth(10000, 4), 2048);
      final provider =
          boundedNetworkImage('https://static.chiphell.com/image.jpeg', 320)
              as ResizeImage;
      expect(provider.width, 320);
      expect(provider.height, isNull);
      expect(provider.allowUpscaling, isFalse);
    },
  );

  test(
    'reader exposes one immutable view instead of copying pages on each scroll query',
    () async {
      final reader = ArticleReaderController(
        loadPage: (page, _) async => ArticleContent(
          ArticleDetail(
            aid: 1,
            title: '长文',
            content: [TextBlock('正文$page')],
            page: PageInfo(current: page, hasNext: page < 2),
          ),
        ),
      );
      final view = reader.pages;
      await reader.loadNext();
      expect(reader.pages, same(view));
      expect(view, hasLength(1));
      await reader.loadNext();
      expect(reader.pages, same(view));
      expect(view, hasLength(2));
      expect(() => view.clear(), throwsUnsupportedError);
      reader.dispose();
    },
  );

  testWidgets(
    'an eighty-image opening post only builds images near the viewport',
    (tester) async {
      final urls = [
        for (var n = 0; n < 80; n++) 'https://static.chiphell.com/lazy-$n.jpeg',
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: ThreadDetailPage(
            tid: 1,
            title: '多图装机记录',
            loadPage: (page, _, _) async => ThreadDetail(
              tid: 1,
              fid: 290,
              title: '多图装机记录',
              posts: [
                Post(
                  pid: 10,
                  floor: 1,
                  author: '楼主',
                  authorUid: '10',
                  timeRaw: '',
                  content: [for (final url in urls) ImageBlock(url)],
                ),
              ],
              page: const PageInfo(current: 1, hasNext: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final visibleImages = tester
          .widgetList<ArticleImage>(find.byType(ArticleImage))
          .toList();
      expect(visibleImages, isNotEmpty);
      expect(visibleImages.length, lessThan(8));
      expect(visibleImages.any((image) => image.url == urls.last), isFalse);
      // Lazy construction still retains the full original gallery when opened.
      final first = find.byType(ArticleImage).first;
      await tester.ensureVisible(first);
      await tester.tapAt(tester.getTopLeft(first) + const Offset(20, 20));
      await tester.pumpAndSettle();
      final viewer = tester.widget<ImageViewerPage>(
        find.byType(ImageViewerPage),
      );
      expect(viewer.urls, orderedEquals(urls));
      expect(viewer.initialIndex, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the full-screen viewer defers original-size decoding until zoom',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ImageViewerPage(
            urls: ['https://static.chiphell.com/zoom-original.jpeg'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      Image image() => tester.widget<Image>(find.byType(Image).first);
      expect(image().image, isA<ResizeImage>());
      final target = find.byType(InteractiveViewer);
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(image().image, isA<ChhCachedImage>());
      expect(image().gaplessPlayback, isTrue);
      expect(find.text('双击还原'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Hero frames reuse a viewport-sized decode through cancellation and return',
    (tester) async {
      const article = PortalArticle(
        aid: 987655,
        title: '流畅展开评测',
        coverUrl: 'https://static.chiphell.com/stable-flight.jpeg',
      );
      late EditorialArticleRoute route;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: GestureDetector(
                  key: const ValueKey('open-editorial'),
                  onTap: () {
                    route = EditorialArticleRoute(
                      builder: (_) => const Scaffold(
                        body: SizedBox(
                          height: 500,
                          child: EditorialCover(
                            article: article,
                            heroTag: 'decode-flight',
                            expanded: true,
                          ),
                        ),
                      ),
                    );
                    Navigator.of(context).push(route);
                  },
                  child: const SizedBox(
                    width: 320,
                    height: 400,
                    child: EditorialCover(
                      article: article,
                      heroTag: 'decode-flight',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-editorial')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final decodedWidths = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .whereType<ResizeImage>()
          .map((provider) => provider.width)
          .toSet();
      expect(decodedWidths, hasLength(1));
      expect(decodedWidths.single, lessThanOrEqualTo(2048));
      await tester.pumpAndSettle();
      expect(route.beginDismiss(), isTrue);
      route.updateDismiss(.1);
      route.endDismiss(0);
      await tester.pumpAndSettle();
      expect(route.isCurrent, isTrue);
      expect(route.beginDismiss(), isTrue);
      route.updateDismiss(.35);
      route.endDismiss(1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-editorial')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
