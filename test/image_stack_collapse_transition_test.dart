import 'dart:math' as math;

import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

/// Mounted keyed cards of the deck in paint order: cardIndex -> stage rect.
Map<int, Rect> _cardRects(WidgetTester tester) {
  final stageBox = tester.renderObject<RenderBox>(fixture.stackStage);
  final stackElement = tester.element(
    find.descendant(of: fixture.stackStage, matching: find.byType(Stack)).first,
  );
  final rects = <int, Rect>{};
  Element? deckElement;
  stackElement.visitChildren((child) => deckElement = child);
  deckElement!.visitChildren((child) {
    final key = child.widget.key;
    if (key is! ValueKey<String> ||
        !key.value.startsWith('image-stack-card-')) {
      return;
    }
    final card = int.parse(key.value.substring('image-stack-card-'.length));
    final box = child.renderObject! as RenderBox;
    rects[card] = MatrixUtils.transformRect(
      box.getTransformTo(stageBox),
      Offset.zero & box.size,
    );
  });
  return rects;
}

/// Collapse (list -> stack) transition invariants reported from device QA:
/// 1. the floating row hugs the shrinking stage bottom (or holds still on
///    the sticky line) and never gets pulled into the picture;
/// 2. after settling, the row ends below the deck frame and never below its
///    tapped position;
/// 3. no gathering card ever paints over the anchor card.
void main() {
  testWidgets(
    'collapse without scroll keeps the row glued to the stage bottom',
    (tester) async {
      final photos = await fixture.makePhotos(tester);
      await fixture.mountStack(tester, count: 6, photos: photos);
      // Anchor on the first card: the scroll compensation has nothing to do
      // (anchor y starts at 0), so frames carry no deferred scroll jumps and
      // per-frame probes read the same layout the painter sees.
      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ImageStackModeToggle));

      var lineCandidate = double.infinity;
      for (var frame = 0; frame < 80; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        final stageHeight = tester.getSize(fixture.stackStage).height;
        final galleryTop = tester
            .getTopLeft(find.byType(ImageStackGallery))
            .dy;
        final rowTop = tester.getTopLeft(
          find.byType(ImageStackModeToggle),
        ).dy;
        final rowTopGallery = rowTop - galleryTop;
        final flowTop = stageHeight + 6;
        // The row either hugs the stage bottom exactly or holds the sticky
        // line (a constant while the scroll is idle). The old stage-bounds
        // clamp pulled it into the picture by rowTotal + 12 instead.
        lineCandidate = math.min(lineCandidate, rowTopGallery);
        final onFlow = (rowTopGallery - flowTop).abs();
        final onLine = (rowTopGallery - lineCandidate).abs();
        expect(
          onFlow < 1.0 || onLine < 1.0,
          isTrue,
          reason: 'frame $frame: row left both the flow position '
              '(delta $onFlow) and the sticky line (delta $onLine)',
        );
        // No gathering card paints over the anchor.
        final rects = _cardRects(tester);
        final anchorRect = rects[0];
        if (anchorRect != null) {
          final paintOrder = rects.keys.toList();
          for (final card in paintOrder) {
            if (card == 0) continue;
            if (!rects[card]!.overlaps(anchorRect)) continue;
            expect(
              paintOrder.indexOf(card),
              lessThan(paintOrder.indexOf(0)),
              reason: 'frame $frame: card $card paints over the anchor',
            );
          }
        }
      }
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(ImageStackModeToggle)).dy,
        greaterThanOrEqualTo(tester.getBottomRight(fixture.stackStage).dy - 2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scrolled collapse gathers behind the anchor and keeps the row put',
    (tester) async {
      final photos = await fixture.makePhotos(tester);
      await fixture.mountStack(tester, count: 6, photos: photos);
      // Anchor off the first card so the gather has cards on both sides.
      await fixture.swipe(tester);
      expect(fixture.storedIndex(tester), 1);

      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pumpAndSettle();
      // Scroll the expanded list so the collapse needs scroll compensation.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();

      final rowAtTap = tester.getTopLeft(
        find.byType(ImageStackModeToggle),
      ).dy;
      await tester.tap(find.byType(ImageStackModeToggle));
      // The collapse pins its anchor choice into storage synchronously.
      final anchor = fixture.storedIndex(tester);
      expect(anchor, inInclusiveRange(0, 5));

      for (var frame = 0; frame < 80; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        // Gathering cards must never paint over the anchor. Paint order is
        // state, not a mid-layout probe, so it reads cleanly per frame.
        final rects = _cardRects(tester);
        final anchorRect = rects[anchor];
        if (anchorRect != null) {
          final paintOrder = rects.keys.toList();
          for (final card in paintOrder) {
            if (card == anchor) continue;
            if (!rects[card]!.overlaps(anchorRect)) continue;
            expect(
              paintOrder.indexOf(card),
              lessThan(paintOrder.indexOf(anchor)),
              reason: 'frame $frame: card $card paints over the anchor',
            );
          }
        }
      }
      await tester.pumpAndSettle();
      expect(fixture.storedIndex(tester), anchor);
      // The row ends below the deck and never below its tapped position.
      final rowEnd = tester.getTopLeft(find.byType(ImageStackModeToggle)).dy;
      expect(
        rowEnd,
        greaterThanOrEqualTo(
          tester.getBottomRight(fixture.stackStage).dy - 2,
        ),
      );
      expect(rowEnd, lessThanOrEqualTo(rowAtTap + 2));
      expect(tester.takeException(), isNull);
    },
  );
}
