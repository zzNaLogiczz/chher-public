import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;
import 'image_stack_pixel_continuity_test.dart' as reference;

/// Boundary gestures rebound without wrapping; regular drags settle with
/// the selected photograph inside the stationary paper frame.
void main() {
  testWidgets(
    'boundary rubber-bands and regular drags settle inside the paper frame',
    (tester) async {
      final pair = await reference.mountPair(tester);
      await reference.assertScene(tester, pair, 0);

      // Leading edge: dragging back on the first photo stretches and returns
      // to the same slot — no wrap-around.
      final back = await reference.beginPairGestures(tester, pair);
      for (var i = 1; i <= 24; i++) {
        await back.moveBy(
          const Offset(10, 0),
          timeStamp: Duration(milliseconds: i * 8),
        );
        await tester.pump(const Duration(milliseconds: 8));
        await reference.assertScene(tester, pair, i);
      }
      await back.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(
        fixture.storedIndex(tester),
        0,
        reason: 'leading edge must not loop',
      );

      // Regular forward drag: the deck settles on the next slot.
      final next = await reference.beginPairGestures(tester, pair);
      for (var i = 1; i <= 24; i++) {
        await next.moveBy(
          Offset(-10, 0),
          timeStamp: Duration(milliseconds: i * 8),
        );
        await tester.pump(const Duration(milliseconds: 8));
        await reference.assertScene(tester, pair, 25 + i);
      }
      await next.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(fixture.storedIndex(tester), 1);

      // At rest, the selected photo is level. Paper edges carry the depth;
      // no next-photo content should protrude from the frame.
      final rect = fixture.photoRect(tester, 1);
      final stage = tester.getRect(fixture.stackStage);
      expect(rect.left, greaterThanOrEqualTo(stage.left));
      expect(rect.right, lessThanOrEqualTo(stage.right));
      expect(rect.top, greaterThanOrEqualTo(stage.top));
      expect(rect.bottom, lessThanOrEqualTo(stage.bottom));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
