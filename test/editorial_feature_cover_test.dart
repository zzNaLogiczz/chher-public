import 'dart:ui' as ui;

import 'package:chh_app/data/editorial_cover_cache.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/editorial_cover.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> seedImage(String url, int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xff8899aa),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  final provider = boundedNetworkImage(url, boundedImageDecodeWidth(800, 1));
  final key = await provider.obtainKey(ImageConfiguration.empty);
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image))),
  );
  await Future<void>.delayed(Duration.zero);
}

Widget cover(
  PortalArticle article,
  ValueNotifier<double> offset, {
  bool reduced = false,
}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(800, 600),
    ).copyWith(disableAnimations: reduced),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          height: 400,
          child: EditorialCover(
            article: article,
            heroTag: 'feature-test',
            eyebrow: '本期精选',
            fit: BoxFit.contain,
            scrollOffset: offset,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test(
    'portrait threshold includes 0.9 and excludes invalid or wide images',
    () {
      expect(isEditorialPortrait(const Size(100, 90)), isTrue);
      expect(isEditorialPortrait(const Size(100, 89)), isFalse);
      expect(isEditorialPortrait(const Size(0, 100)), isFalse);
      expect(isEditorialPortrait(const Size(100, 150)), isTrue);
    },
  );

  test('parallax follows 0.85 speed and stops at 24', () {
    expect(editorialParallaxOffset(100), 15);
    expect(editorialParallaxOffset(1000), 24);
    expect(editorialParallaxOffset(-100), 0);
  });

  testWidgets(
    'feature paints fallback once and reveals portrait without resizing',
    (tester) async {
      const wide = 'https://static.chiphell.com/feature-test-wide.jpg';
      const portrait = 'https://static.chiphell.com/feature-test-portrait.jpg';
      const article = PortalArticle(
        aid: 918722,
        title: '封面测试',
        categoryName: '散热器',
        summary: '真实摘要',
        coverUrl: wide,
      );
      final offset = ValueNotifier<double>(0);
      await tester.runAsync(() async {
        await seedImage(wide, 400, 160);
        await seedImage(portrait, 400, 600);
      });
      await tester.pumpWidget(cover(article, offset));
      await tester.pumpAndSettle();
      final photoFinder = find.byKey(const ValueKey('editorial-feature-photo'));
      dynamic painter() => tester.widget<CustomPaint>(photoFinder).painter;
      expect(painter().blur, isNotNull);
      final blurred = painter().blur;
      final initialSize = tester.getSize(find.byType(EditorialCover));
      expect(
        tester.getTopLeft(find.text('本期精选')).dy,
        greaterThan(tester.getTopLeft(find.byType(EditorialCover)).dy + 240),
      );
      expect(find.text('散热器'), findsOneWidget);
      offset.value = 100;
      await tester.pump();
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('editorial-parallax')),
      );
      expect(transform.transform.getTranslation().y, 15);
      expect(identical(painter().blur, blurred), isTrue);
      await tester.runAsync(
        () => editorialCoverCache.remember(article.aid, portrait),
      );
      await tester.pump();
      expect(painter().portrait, isNotNull);
      expect(painter().fade.duration, HomeCoverTokens.portraitFade);
      await tester.pump(const Duration(milliseconds: 300));
      expect(painter().fade.value, closeTo(.5, .03));
      await tester.pumpAndSettle();
      expect(painter().fade.value, 1);
      expect(tester.getSize(find.byType(EditorialCover)), initialSize);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      offset.dispose();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    },
  );
  testWidgets(
    'wide remembered images retain fallback and reduced motion fixes parallax',
    (tester) async {
      const wide = 'https://static.chiphell.com/feature-wide-existing.jpg';
      const remembered = 'https://static.chiphell.com/feature-wide-body.jpg';
      const article = PortalArticle(aid: 918723, title: '横图缓存', coverUrl: wide);
      final offset = ValueNotifier<double>(160);
      await tester.runAsync(() async {
        await seedImage(wide, 400, 160);
        await seedImage(remembered, 400, 300);
        await editorialCoverCache.remember(article.aid, remembered);
      });
      await tester.pumpWidget(cover(article, offset, reduced: true));
      await tester.pumpAndSettle();
      final dynamic painter = tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('editorial-feature-photo')),
          )
          .painter;
      expect(painter.portrait, isNull);
      expect(painter.wide, isNotNull);
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('editorial-parallax')),
      );
      expect(transform.transform.getTranslation().y, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      offset.dispose();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    },
  );
  testWidgets(
    'feature title balances a short last line and stays inside at double text size',
    (tester) async {
      const title = '甲乙丙丁戊己庚辛壬癸甲乙丙丁戊';
      const article = PortalArticle(aid: 918724, title: title);
      const titleKey = ValueKey('editorial-balanced-title');
      for (final scale in [1.0, 2.0]) {
        for (final viewport in [392.0, 320.0]) {
          final cardWidth = viewport - HomeTokens.inset * 2;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(Brightness.light),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(viewport, 700),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: cardWidth,
                      height: 400,
                      child: const EditorialCover(
                        article: article,
                        heroTag: 'balanced',
                        fit: BoxFit.contain,
                        eyebrow: '本期精选',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final titleWidget = tester.widget<Text>(find.text(title));
          final available = cardWidth - HomeCoverTokens.inset * 2;
          final original = TextPainter(
            text: TextSpan(text: title, style: titleWidget.style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout(maxWidth: available);
          final balancedWidth = tester.getSize(find.byKey(titleKey)).width;
          final balanced = TextPainter(
            text: TextSpan(text: title, style: titleWidget.style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout(maxWidth: balancedWidth);
          if (scale == 1 && viewport == 392) {
            final before = original.computeLineMetrics();
            final after = balanced.computeLineMetrics();
            expect(after.length, before.length);
            expect(after.last.width, greaterThan(before.last.width));
            expect(balancedWidth, lessThan(available * .8));
          }
          expect(balancedWidth, lessThanOrEqualTo(available));
          final titleRect = tester.getRect(find.byKey(titleKey));
          final coverRect = tester.getRect(find.byType(EditorialCover));
          expect(titleRect.left, greaterThanOrEqualTo(coverRect.left));
          expect(titleRect.right, lessThanOrEqualTo(coverRect.right));
          expect(titleRect.top, greaterThanOrEqualTo(coverRect.top));
          expect(tester.takeException(), isNull);
          original.dispose();
          balanced.dispose();
        }
      }
    },
  );
}
