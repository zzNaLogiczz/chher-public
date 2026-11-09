import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;
import 'image_stack_pixel_continuity_test.dart' as reference;

/// Edges and depth slots of the reveal-line deck:
/// the boundary drag rubber-bands back instead of looping, a regular drag
/// settles on the next slot, and the settled formation keeps the B-frame
/// geometry with every live slot on one baseline.
void main() {
  testWidgets(
    'boundary rubber-bands, regular drags settle, slots keep one baseline',
    (tester) async {
      final pair = await reference.mountPair(tester);
      await reference.assertScene(tester, pair, 0);

      // Leading edge: dragging back on the first photo stretches and returns
      // to the same slot — no wrap-around.
      final back = await reference.beginPairGestures(tester, pair);
      for (var i = 1; i <= 24; i++) {
        await back.moveBy(const Offset(10, 0), timeStamp: Duration(milliseconds: i * 8));
        await tester.pump(const Duration(milliseconds: 8));
        await reference.assertScene(tester, pair, i);
      }
      await back.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(fixture.storedIndex(tester), 0, reason: 'leading edge must not loop');

      // Regular forward drag: the deck settles on the next slot.
      final next = await reference.beginPairGestures(tester, pair);
      for (var i = 1; i <= 24; i++) {
        await next.moveBy(Offset(-10, 0), timeStamp: Duration(milliseconds: i * 8));
        await tester.pump(const Duration(milliseconds: 8));
        await reference.assertScene(tester, pair, 25 + i);
      }
      await next.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(fixture.storedIndex(tester), 1);

      // Settled depth formation: live slots stay windowed around the current
      // photo and sit on one shared baseline under the reveal line. Only the
      // keyed photo slots count; the ambience layer fills the whole card.
      final stageBox = tester.renderObject(fixture.stackStage) as RenderBox;
      final ys = <double>{};
      final widths = <double>{};
      for (final element
          in find
              .descendant(
                of: find.byType(ImageStackGallery),
                matching: find.byType(RawImage),
              )
              .evaluate()) {
        if ((element.widget as RawImage).image == null) continue;
        int? index;
        element.visitAncestorElements((ancestor) {
          final key = ancestor.widget.key;
          if (key is ValueKey<String> &&
              key.value.startsWith('image-stack-photo-')) {
            index = int.parse(key.value.substring('image-stack-photo-'.length));
            return false;
          }
          return true;
        });
        if (index == null) continue;
        final box = element.findRenderObject()! as RenderBox;
        final rect = MatrixUtils.transformRect(
          box.getTransformTo(stageBox),
          Offset.zero & box.size,
        );
        ys.add(rect.center.dy);
        widths.add(rect.width);
      }
      final ladder = widths.toList()..sort();
      // Current card plus up to two depth slots, each uniformly scaled down;
      // widths collapse to the discrete slot ladder, never arbitrary values.
      expect(ladder.length, inInclusiveRange(1, 5));
      expect(ladder.toSet().length, lessThanOrEqualTo(3));
      final sortedYs = ys.toList()..sort();
      var lines = 1;
      for (var i = 1; i < sortedYs.length; i++) {
        if (sortedYs[i] - sortedYs[i - 1] > 0.5) lines++;
      }
      expect(lines, 1, reason: 'settled slots must share one baseline');
      expect(tester.takeException(), isNull);
    },
  );
}
