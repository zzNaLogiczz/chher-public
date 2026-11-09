import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

void main() {
  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(390, 844),
      const Size(320, 568),
      const Size(844, 390),
    ]) {
      testWidgets(
        'the frame stage preserves complete mixed photos in $brightness $size',
        (tester) async {
          final sizes = [
            const Size(32, 640),
            const Size(160, 80),
            const Size(96, 96),
          ];
          final photos = await fixture.makePhotos(tester, sizes: sizes);
          await fixture.mountStack(
            tester,
            count: 3,
            viewport: size,
            brightness: brightness,
            photos: photos,
          );
          final stage = tester.getRect(fixture.stackStage);
          // The B frame bounds the stage height by content (cap 400), and
          // the reading host scrolls; it is never unbounded or viewport-torn.
          expect(stage.height, lessThanOrEqualTo(400));
          // Median ratio of [1:20, 2:1, 1:1] is 1:1 after the clamp floor.
          final frame = fixture.frameOf(stage.width, 1.0);
          expect(stage.height, closeTo(frame.fh, 1));
          final seen = <int>{};
          for (final element in find.byType(RawImage).evaluate()) {
            final widget = element.widget as RawImage;
            if (widget.image == null) continue;
            int? index;
            element.visitAncestorElements((ancestor) {
              final key = ancestor.widget.key;
              if (key is ValueKey<String> &&
                  key.value.startsWith('image-stack-photo-')) {
                index = int.parse(
                  key.value.substring('image-stack-photo-'.length),
                );
                return false;
              }
              return true;
            });
            if (index == null) continue;
            final i = index!;
            seen.add(i);
            final box = element.findRenderObject()! as RenderBox;
            final ratio = sizes[i].aspectRatio;
            // Long shots fill the frame width from the top; every other
            // photo keeps its own ratio inside the frame, uncropped.
            final inner = fixture.innerRectOf(ratio, frame.fw, frame.fh);
            expect(box.size.width / box.size.height, closeTo(
              inner.width / inner.height,
              .001,
            ), reason: 'photo $i');
            expect(
              widget.image!.width / widget.image!.height,
              closeTo(ratio, .001),
              reason: 'photo $i decode',
            );
            // Each actual photo sits in a natural-ratio slot, not a white
            // fixed box.
            final natural = find.ancestor(
              of: find.byWidget(widget),
              matching: find.byWidgetPredicate(
                (w) => w.key == ValueKey('image-stack-photo-$i'),
              ),
            );
            expect(natural, findsOneWidget);
          }
          expect(seen, {0, 1, 2});
          // No counter text anywhere; the only allowed label is the long-shot
          // chip that marks a cropped tall photo.
          final labels = find
              .descendant(
                of: find.byType(ImageStackGallery),
                matching: find.byType(Text),
              )
              .evaluate()
              .map((e) => (e.widget as Text).data ?? '');
          expect(labels, everyElement('长图'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
