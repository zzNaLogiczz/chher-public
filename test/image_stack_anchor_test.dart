import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

void main() {
  testWidgets('collapse chooses the long photo crossing the screen middle', (
    tester,
  ) async {
    final photos = await fixture.makePhotos(
      tester,
      sizes: [const Size(80, 60), const Size(40, 400), const Size(80, 60)],
    );
    await fixture.mountStack(tester, count: 3, photos: photos, trailing: 1200);
    await tester.tap(find.byType(ImageStackModeToggle));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ImageStackGallery));
    final scroll = Scrollable.of(context).position;
    scroll.jumpTo(200);
    await tester.pumpAndSettle();
    final longPhoto = fixture.photoRect(tester, 1);
    final middle = tester.view.physicalSize.height / 2;
    expect(longPhoto.top, lessThan(middle));
    expect(longPhoto.bottom, greaterThan(middle));
    await tester.tap(find.byType(ImageStackModeToggle));
    await tester.pumpAndSettle();
    expect(fixture.storedIndex(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapse pill remains above the reading bar while scrolling', (
    tester,
  ) async {
    await fixture.mountStack(tester, count: 6, trailing: 2000);
    await tester.tap(find.byType(ImageStackModeToggle));
    await tester.pumpAndSettle();
    final scroll = Scrollable.of(
      tester.element(find.byType(ImageStackGallery)),
    ).position;
    final before = tester.getTopLeft(find.byType(ImageStackModeToggle)).dy;
    for (var step = 0; step < 3; step++) {
      scroll.jumpTo(scroll.pixels + 20);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(ImageStackModeToggle)).dy,
        closeTo(before, 1),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('expansion starts at the mounted photo and preserves its top', (
    tester,
  ) async {
    final photos = await fixture.makePhotos(
      tester,
      sizes: [const Size(80, 160), const Size(160, 80), const Size(80, 160)],
    );
    await fixture.mountStack(tester, count: 3, photos: photos, trailing: 2000);
    await fixture.swipe(tester);
    expect(fixture.storedIndex(tester), 1);
    final before = fixture.photoRect(tester, 1);
    await tester.tap(find.byType(ImageStackModeToggle));
    await tester.pump();
    final first = fixture.photoRect(tester, 1);
    expect(first.top, closeTo(before.top, 1));
    expect(first.left, closeTo(before.left, 1));
    expect(first.width, closeTo(before.width, 1));
    expect(first.height, closeTo(before.height, 1));
    final finalHeight = tester.getSize(fixture.stackStage).height;
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(fixture.photoRect(tester, 1).top, closeTo(before.top, 1));
      expect(tester.getSize(fixture.stackStage).height, finalHeight);
    }
    await tester.pumpAndSettle();
    expect(fixture.photoRect(tester, 1).top, closeTo(before.top, 1));
    expect(fixture.photoRect(tester, 1).width, closeTo(350, 1));
    expect(fixture.photoRect(tester, 1).size.aspectRatio, closeTo(2, .01));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
