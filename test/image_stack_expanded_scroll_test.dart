import 'dart:ui' as ui;

import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;
import 'image_stack_integration_test.dart' as integration;

class _PendingPhoto extends ImageProvider<_PendingPhoto> {
  final stream = _PhotoFrames();
  @override
  Future<_PendingPhoto> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _PendingPhoto key,
    ImageDecoderCallback decode,
  ) => stream;
}

class _PhotoFrames extends ImageStreamCompleter {
  void complete(ui.Image image) => setImage(ImageInfo(image: image.clone()));
}

Future<ReadingPrefsController> _prefs() async {
  final result = ReadingPrefsController(directory: () async => null);
  await result.set(const ReadingPrefs(imagesStackHintSeen: true));
  return result;
}

Widget _app(
  ReadingPrefsController prefs,
  Widget child, {
  PageStorageBucket? bucket,
}) => ReadingScope(
  controller: prefs,
  child: MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: bucket == null
        ? child
        : Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: SingleChildScrollView(
                child: Padding(padding: const EdgeInsets.all(20), child: child),
              ),
            ),
          ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
    'a saved collapsed group ignores another group changing the default',
    (tester) async {
      _phone(tester);
      final prefs = await _prefs();
      addTearDown(prefs.dispose);
      final bucket = PageStorageBucket();
      final photos = await fixture.makePhotos(tester);
      Widget group(String name, int count) => ImageStackGallery(
        key: PageStorageKey(name),
        urls: List.generate(count, (i) => '$name-$i'),
        aspectRatios: List.filled(count, 4 / 3),
        gallery: List.generate(count, (i) => '$name-$i'),
        galleryStartIndex: 0,
        imageProviderBuilder: (url, _) =>
            photos[int.parse(url.split('-').last) % photos.length],
      );
      await tester.pumpWidget(_app(prefs, group('groupA', 20), bucket: bucket));
      await tester.pumpAndSettle();
      final height = tester.getSize(fixture.stackStage).height;
      await tester.pumpWidget(_app(prefs, group('groupB', 3), bucket: bucket));
      await tester.pumpAndSettle();
      tester
          .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
          .onPressed();
      await tester.pumpAndSettle();
      expect(prefs.prefs.imagesExpanded, isTrue);
      await tester.pumpWidget(_app(prefs, group('groupA', 20), bucket: bucket));
      await tester.pump();
      expect(tester.getSize(fixture.stackStage).height, height);
      expect(find.text('展开全部'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a restored expanded group keeps decoded ratios before new frames arrive',
    (tester) async {
      _phone(tester);
      final prefs = await _prefs();
      addTearDown(prefs.dispose);
      final bucket = PageStorageBucket();
      var photos = List.generate(20, (_) => _PendingPhoto());
      ImageProvider<Object> provider(String url, int _) =>
          photos[int.parse(url)];
      Widget gallery() => ImageStackGallery(
        key: const PageStorageKey('restored-long-group'),
        urls: List.generate(20, (i) => '$i'),
        gallery: List.generate(20, (i) => '$i'),
        galleryStartIndex: 0,
        imageProviderBuilder: provider,
      );
      await tester.pumpWidget(_app(prefs, gallery(), bucket: bucket));
      final frame = (await tester.runAsync(
        () => createTestImage(width: 80, height: 160, cache: false),
      ))!;
      for (final photo in photos) {
        photo.stream.complete(frame);
      }
      frame.dispose();
      await tester.pumpAndSettle();
      tester
          .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
          .onPressed();
      await tester.pumpAndSettle();
      final position = Scrollable.of(
        tester.element(find.byType(ImageStackGallery)),
      ).position;
      for (var i = 0; i < 3; i++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      final height = tester.getSize(fixture.stackStage).height;
      expect(height, closeTo(20 * 700 + 19 * 10, 1));
      await tester.pumpWidget(
        _app(prefs, const SizedBox(height: 10), bucket: bucket),
      );
      await tester.pump();
      photos = List.generate(20, (_) => _PendingPhoto());
      await tester.pumpWidget(_app(prefs, gallery(), bucket: bucket));
      // New providers intentionally have no pixels yet: geometry must come from
      // the same group's saved dimensions, not another network/decode cycle.
      expect(tester.getSize(fixture.stackStage).height, height);
      await tester.pump();
      expect(tester.getSize(fixture.stackStage).height, height);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded later group allows reading back across a recycled twenty-photo group',
    (tester) async {
      _phone(tester);
      final prefs = await _prefs();
      addTearDown(prefs.dispose);
      final a = List.generate(20, (i) => integration.photo(600 + i));
      final b = List.generate(3, (i) => integration.photo(700 + i));
      await integration.primePhotos(tester, {
        for (final url in [...a, ...b]) url: const Size(96, 192),
      });
      await tester.pumpWidget(
        _app(
          prefs,
          ThreadDetailPage(
            tid: 123,
            title: '展开后回看前文',
            loadPage: (_, _, _) async => ThreadDetail(
              tid: 123,
              title: '展开后回看前文',
              posts: [
                Post(
                  pid: 1,
                  floor: 1,
                  author: '本地样例',
                  timeRaw: '',
                  content: [
                    const TextBlock('原帖前文锚点'),
                    for (final url in a)
                      ImageBlock(url, width: 96, height: 192),
                    const TextBlock('两个图组之间的说明'),
                    for (final url in b)
                      ImageBlock(url, width: 96, height: 192),
                    const TextBlock('图组之后的文字'),
                  ],
                ),
              ],
              page: const PageInfo(current: 1, hasNext: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder group(String first) => find.byWidgetPredicate(
        (w) => w is ImageStackGallery && w.urls.first == first,
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      for (var i = 0; i < 8 && group(b.first).evaluate().isEmpty; i++) {
        position.jumpTo(
          (position.pixels + 500).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(group(b.first), findsOneWidget);
      await tester.ensureVisible(group(b.first));
      await tester.pumpAndSettle();
      tester
          .widget<ImageStackModeToggle>(
            find.descendant(
              of: group(b.first),
              matching: find.byType(ImageStackModeToggle),
            ),
          )
          .onPressed();
      await tester.pumpAndSettle();
      position.jumpTo(
        (position.pixels + 1200).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
      var reached = false;
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 500));
        await tester.pumpAndSettle();
        final first = group(a.first);
        if (first.evaluate().isNotEmpty) {
          final stage = find.descendant(
            of: first,
            matching: fixture.stackStage,
          );
          expect(tester.getSize(stage).height, lessThanOrEqualTo(500));
        }
        final intro = find.text('原帖前文锚点', findRichText: true);
        if (intro.evaluate().isNotEmpty &&
            tester
                .getRect(intro)
                .overlaps(const Rect.fromLTWH(0, 80, 390, 700))) {
          reached = true;
          break;
        }
      }
      expect(reached, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
