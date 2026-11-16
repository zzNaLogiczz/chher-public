import 'dart:ui' as ui;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/image_stack_group.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/content_walker.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

class _Photo extends ImageProvider<_Photo> {
  final stream = _Frames();
  @override
  Future<_Photo> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Photo key, ImageDecoderCallback decode) =>
      stream;
}

class _Frames extends ImageStreamCompleter {
  void complete(ui.Image image) => setImage(ImageInfo(image: image.clone()));
}

Future<void> _mount(
  WidgetTester tester,
  List<_Photo> photos, {
  List<double?>? ratios,
  PageStorageBucket? bucket,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: PageStorage(
          bucket: bucket ?? PageStorageBucket(),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ImageStackGallery(
                    key: const PageStorageKey('late-stack'),
                    urls: List.generate(photos.length, (i) => '$i'),
                    aspectRatios: ratios,
                    gallery: List.generate(photos.length, (i) => '$i'),
                    galleryStartIndex: 0,
                    imageProviderBuilder: (url, _) => photos[int.parse(url)],
                  ),
                ),
                const SizedBox(key: ValueKey('after-stack'), height: 300),
                const Text('正在阅读的正文', key: ValueKey('reading-anchor')),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test(
    'Discuz lazy images retain HTML and attachment dimensions in groups',
    () {
      final doc = html.parse('''
      <div id="postmessage_1">
        <img width="1080" height="2400" src="loading.gif" zoomfile="https://example.invalid/one.jpg">
        <img style="width: 360px; height: 800px" file="https://example.invalid/two.jpg" src="loading.gif">
        <img id="aimg_3" zoomfile="https://example.invalid/three.jpg" src="loading.gif">
        <div id="aimg_3_menu" class="aimg_tip" style="display:none">手机截屏.jpg (1080 × 2400)</div>
      </div>
      <div><img id="aimg_4" width="900" height="1800" file="https://example.invalid/four.jpg"></div>
    ''');
      final blocks = parseContentBlocks(doc.getElementById('postmessage_1')!);
      final images = blocks.whereType<ImageBlock>().toList();
      expect(images.map((p) => p.url), [
        for (final n in ['one', 'two', 'three'])
          'https://example.invalid/$n.jpg',
      ]);
      expect(images.map((p) => p.aspectRatio), everyElement(.45));
      expect(groupPostImages(blocks).single.imageStack!.aspectRatios, [
        .45,
        .45,
        .45,
      ]);
      expect(
        parseAttachmentImage(doc.getElementById('aimg_4')!)!.aspectRatio,
        .5,
      );
    },
  );

  test('missing, relative and invalid dimensions remain unknown', () {
    final root = html
        .parseFragment('''
      <div><img src="https://example.invalid/a.jpg" width="100%" height="auto">
      <img src="https://example.invalid/b.jpg" width="0" height="10">
      <img src="https://example.invalid/c.jpg" width="NaN" height="10">
      <img src="https://example.invalid/d.jpg" style="width:50%;height:100px"></div>
    ''')
        .children
        .single;
    expect(
      parseContentBlocks(
        root,
      ).whereType<ImageBlock>().map((p) => p.aspectRatio),
      everyElement(isNull),
    );
  });

  testWidgets(
    'HTML portrait dimensions establish the final frame before decoding',
    (tester) async {
      final photos = List.generate(11, (_) => _Photo());
      await _mount(tester, photos, ratios: List.filled(11, .45));
      final stage = find.byKey(const ValueKey('image-stack-stage'));
      expect(tester.getSize(stage).height, 496);
      expect(find.byKey(const ValueKey('image-stack-loading')), findsNothing);
      final before = tester
          .getTopLeft(find.byKey(const ValueKey('after-stack')))
          .dy;
      final image = (await tester.runAsync(
        () => createTestImage(width: 90, height: 200),
      ))!;
      for (final photo in photos) {
        photo.stream.complete(image);
      }
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('after-stack'))).dy,
        before,
      );
      image.dispose();
    },
  );

  testWidgets(
    'late portrait sample locks once and keeps following content still',
    (tester) async {
      final photos = List.generate(11, (_) => _Photo());
      await _mount(tester, photos);
      final stage = find.byKey(const ValueKey('image-stack-stage'));
      final following = find.byKey(const ValueKey('after-stack'));
      final before = tester.getTopLeft(following).dy;
      expect(find.byKey(const ValueKey('image-stack-loading')), findsOneWidget);
      final portrait = (await tester.runAsync(
        () => createTestImage(width: 90, height: 200),
      ))!;
      final landscape = (await tester.runAsync(
        () => createTestImage(width: 200, height: 90),
      ))!;
      for (var i = 0; i < 3; i++) {
        photos[i].stream.complete(portrait);
        await tester.pump();
        await tester.pump();
        expect(tester.getTopLeft(following).dy, before);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('image-stack-loading')), findsNothing);
      expect(tester.getSize(stage).height, 496);
      for (var i = 3; i < photos.length; i++) {
        photos[i].stream.complete(landscape);
        await tester.pumpAndSettle();
        expect(tester.getSize(stage).height, 496);
        expect(tester.getTopLeft(following).dy, before);
      }
      await tester.fling(stage, const Offset(-240, 0), 1000);
      await tester.pumpAndSettle();
      expect(tester.getSize(stage).height, 496);
      expect(tester.getTopLeft(following).dy, before);
      expect(tester.binding.hasScheduledFrame, isFalse);
      portrait.dispose();
      landscape.dispose();
    },
  );

  testWidgets(
    'late landscape frame removes loading space while the deck is visible',
    (tester) async {
      final photos = List.generate(3, (_) => _Photo());
      await _mount(tester, photos);
      final following = find.byKey(const ValueKey('after-stack'));
      final before = tester.getTopLeft(following).dy;
      final landscape = (await tester.runAsync(
        () => createTestImage(width: 200, height: 90),
      ))!;
      for (final photo in photos) {
        photo.stream.complete(landscape);
      }
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('image-stack-stage'))).height,
        216,
      );
      expect(tester.getTopLeft(following).dy, before - 280);
      expect(
        tester.getTopLeft(following).dy -
            tester
                .getBottomRight(find.byKey(const ValueKey('image-stack-stage')))
                .dy,
        70, // Caption and bottom padding, with no loading spacer.
      );
      final scroll = Scrollable.of(
        tester.element(find.byType(ImageStackGallery)),
      ).position;
      scroll.jumpTo(700);
      final anchor = find.byKey(const ValueKey('reading-anchor'));
      await tester.pump();
      final screenY = tester.getTopLeft(anchor).dy;
      await tester.pump();
      expect(tester.getTopLeft(anchor).dy, screenY);
      expect(scroll.pixels, 700);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, screenY);
      landscape.dispose();
    },
  );
  testWidgets(
    'late landscape resolution above the viewport preserves the reading anchor',
    (tester) async {
      final photos = List.generate(3, (_) => _Photo());
      await _mount(tester, photos);
      final scroll = Scrollable.of(
        tester.element(find.byType(ImageStackGallery)),
      ).position;
      scroll.jumpTo(700);
      await tester.pumpAndSettle();
      final anchor = find.byKey(const ValueKey('reading-anchor'));
      final screenY = tester.getTopLeft(anchor).dy;
      final landscape = (await tester.runAsync(
        () => createTestImage(width: 200, height: 90),
      ))!;
      for (final photo in photos) {
        photo.stream.complete(landscape);
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, screenY);
      expect(scroll.pixels, 420);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      landscape.dispose();
    },
  );
  testWidgets(
    'resolved frame survives lazy unmount with a different decoded sample',
    (tester) async {
      final bucket = PageStorageBucket();
      final photos = List.generate(11, (_) => _Photo());
      await _mount(tester, photos, bucket: bucket);
      final portrait = (await tester.runAsync(
        () => createTestImage(width: 90, height: 200),
      ))!;
      final landscape = (await tester.runAsync(
        () => createTestImage(width: 200, height: 90),
      ))!;
      for (final photo in photos.take(3)) {
        photo.stream.complete(portrait);
      }
      await tester.pumpAndSettle();
      for (final photo in photos.skip(3)) {
        photo.stream.complete(landscape);
      }
      await tester.pumpAndSettle();
      final stage = find.byKey(const ValueKey('image-stack-stage'));
      await tester.fling(stage, const Offset(-240, 0), 1000);
      await tester.pumpAndSettle();
      expect(tester.getSize(stage).height, 496);
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, photos, bucket: bucket);
      await tester.pumpAndSettle();
      expect(tester.getSize(stage).height, 496);
      expect(find.byKey(const ValueKey('image-stack-loading')), findsNothing);
      portrait.dispose();
      landscape.dispose();
    },
  );
}
