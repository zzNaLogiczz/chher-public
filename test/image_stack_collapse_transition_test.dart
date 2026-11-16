import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

void main() {
  testWidgets(
    'expansion lays out its final column once and keeps the action usable',
    (tester) async {
      await fixture.mountStack(tester, count: 6);
      final before = tester.getTopLeft(fixture.stackCard(0));
      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pump();
      final finalHeight = tester.getSize(fixture.stackStage).height;
      expect(finalHeight, closeTo(6 * 350 / (4 / 3) + 5 * 10, 1));
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        expect(tester.getSize(fixture.stackStage).height, finalHeight);
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(fixture.stackCard(0)).dy, closeTo(before.dy, 1));
      expect(find.text('收起'), findsOneWidget);
      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(ImageStackModeToggle)).dy,
        greaterThanOrEqualTo(tester.getBottomRight(fixture.stackStage).dy),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scrolled collapse selects the photo nearest the screen middle', (
    tester,
  ) async {
    await fixture.mountStack(tester, count: 6, trailing: 1000);
    await tester.tap(find.byType(ImageStackModeToggle));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    var selected = 0;
    var distance = double.infinity;
    for (var i = 0; i < 6; i++) {
      if (fixture.stackCard(i).evaluate().isEmpty) continue;
      final d = (tester.getCenter(fixture.stackCard(i)).dy - 422).abs();
      if (d < distance) {
        distance = d;
        selected = i;
      }
    }
    await tester.tap(find.byType(ImageStackModeToggle));
    await tester.pumpAndSettle();
    expect(fixture.storedIndex(tester), selected);
    expect(
      tester
          .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
          .expanded,
      isFalse,
    );
    expect(
      tester.getTopLeft(find.byType(ImageStackModeToggle)).dy,
      greaterThanOrEqualTo(tester.getBottomRight(fixture.stackStage).dy),
    );
    final dynamic state = tester.state(find.byType(ImageStackGallery));
    expect(state.debugActiveCardMotions, 0);
    expect(tester.takeException(), isNull);
  });
}
