import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

Widget _app({
  required ReadingPrefsController prefs,
  required ScrollController scroll,
  required List<MemoryImage> photos,
  double leading = 0,
  int groups = 1,
  int generation = 0,
  bool reduced = false,
  bool active = true,
}) => ReadingScope(
  controller: prefs,
  child: MaterialApp(
    theme: buildAppTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: TickerMode(
        enabled: active,
        child: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              SizedBox(height: leading),
              for (var group = 0; group < groups; group++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ImageStackGallery(
                    key: PageStorageKey('hint-$generation-$group'),
                    urls: const ['photo-0', 'photo-1'],
                    aspectRatios: const [4 / 3, 4 / 3],
                    gallery: const ['photo-0', 'photo-1'],
                    galleryStartIndex: 0,
                    imageProviderBuilder: (url, _) =>
                        photos[int.parse(url.split('-').last)],
                  ),
                ),
                const SizedBox(height: 300),
              ],
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    ),
  ),
);

int _motions(WidgetTester tester, int group) {
  final dynamic state = tester.state(find.byType(ImageStackGallery).at(group));
  return state.debugActiveCardMotions as int;
}

void main() {
  testWidgets(
    'hint waits for entry and does not repeat for another group or remount',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = ReadingPrefsController(directory: () async => null);
      final scroll = ScrollController();
      addTearDown(prefs.dispose);
      addTearDown(scroll.dispose);
      await prefs.load();
      final photos = await fixture.makePhotos(tester);
      await tester.pumpWidget(
        _app(
          prefs: prefs,
          scroll: scroll,
          photos: photos,
          leading: 1000,
          groups: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(prefs.prefs.imagesStackHintSeen, isFalse);
      expect(_motions(tester, 0), 0);
      expect(_motions(tester, 1), 0);

      scroll.jumpTo(1000);
      await tester.pump();
      expect(prefs.prefs.imagesStackHintSeen, isTrue);
      expect(_motions(tester, 0), greaterThan(0));
      expect(_motions(tester, 1), 0);
      await tester.pumpAndSettle();
      expect(_motions(tester, 0), 0);

      final secondTop = tester
          .getTopLeft(find.byType(ImageStackGallery).at(1))
          .dy;
      scroll.jumpTo(scroll.offset + secondTop - 20);
      await tester.pump();
      expect(_motions(tester, 1), 0);
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(prefs: prefs, scroll: scroll, photos: photos, generation: 1),
      );
      scroll.jumpTo(0);
      await tester.pump();
      expect(_motions(tester, 0), 0);
      await tester.pumpAndSettle();
      expect(prefs.prefs.imagesStackHintSeen, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion suppresses the hint without consuming it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = ReadingPrefsController(directory: () async => null);
    final scroll = ScrollController();
    addTearDown(prefs.dispose);
    addTearDown(scroll.dispose);
    await prefs.load();
    final photos = await fixture.makePhotos(tester);
    await tester.pumpWidget(
      _app(prefs: prefs, scroll: scroll, photos: photos, reduced: true),
    );
    await tester.pumpAndSettle();
    expect(prefs.prefs.imagesStackHintSeen, isFalse);
    expect(_motions(tester, 0), 0);

    await tester.pumpWidget(_app(prefs: prefs, scroll: scroll, photos: photos));
    expect(prefs.prefs.imagesStackHintSeen, isTrue);
    expect(_motions(tester, 0), greaterThan(0));
    await tester.pumpAndSettle();
    expect(_motions(tester, 0), 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an inactive retained tab leaves its first hint unclaimed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = ReadingPrefsController(directory: () async => null);
    final scroll = ScrollController();
    addTearDown(prefs.dispose);
    addTearDown(scroll.dispose);
    await prefs.load();
    final photos = await fixture.makePhotos(tester);
    await tester.pumpWidget(
      _app(prefs: prefs, scroll: scroll, photos: photos, active: false),
    );
    await tester.pumpAndSettle();
    expect(prefs.prefs.imagesStackHintSeen, isFalse);
    expect(_motions(tester, 0), 0);

    await tester.pumpWidget(_app(prefs: prefs, scroll: scroll, photos: photos));
    expect(prefs.prefs.imagesStackHintSeen, isTrue);
    expect(_motions(tester, 0), greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an overlaid route delays the hint until the gallery is current',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = ReadingPrefsController(directory: () async => null);
      final scroll = ScrollController();
      addTearDown(prefs.dispose);
      addTearDown(scroll.dispose);
      final photos = await fixture.makePhotos(tester);
      await tester.pumpWidget(
        _app(prefs: prefs, scroll: scroll, photos: photos),
      );
      await tester.pumpAndSettle();
      final navigator = Navigator.of(
        tester.element(find.byType(ImageStackGallery)),
      );
      navigator.push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => const Center(child: Text('浮层')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(prefs.load);
      await tester.pumpAndSettle();
      expect(prefs.prefs.imagesStackHintSeen, isFalse);
      expect(_motions(tester, 0), 0);

      navigator.pop();
      await tester.pump();
      expect(prefs.prefs.imagesStackHintSeen, isTrue);
      expect(_motions(tester, 0), greaterThan(0));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
