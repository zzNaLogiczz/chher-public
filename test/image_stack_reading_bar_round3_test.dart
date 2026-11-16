import 'package:chh_app/design/image_stack_tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_integration_test.dart' as fixture;
import 'image_stack_gallery_test.dart' as gallery_fixture;

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '11 portrait collapse pill follows the reading bar: $style $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final urls = [for (var i = 0; i < 11; i++) fixture.photo(800 + i)];
          await fixture.primePhotos(tester, {
            for (final url in urls) url: const Size(80, 160),
          });
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness, style),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(bottom: 24),
                  viewPadding: const EdgeInsets.only(bottom: 24),
                ),
                child: child!,
              ),
              home: fixture.thread(
                fixture.post([
                  for (final url in urls) ImageBlock(url),
                  for (var i = 0; i < 50; i++) TextBlock('图片之后的本地正文 $i'),
                ]),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final pill = find.byType(ImageStackModeToggle);
          await tester.ensureVisible(pill);
          await tester.pumpAndSettle();
          await tester.tap(pill);
          await tester.pumpAndSettle();
          final scroll = Scrollable.of(
            tester.element(find.byType(ImageStackGallery)),
          ).position;
          void expectAttached() {
            expect(
              tester.getRect(find.byType(ComposeCapsule)).top -
                  tester.getRect(pill).bottom,
              closeTo(ImageStackTokens.collapseGap, .01),
            );
          }

          expectAttached();
          scroll.jumpTo(scroll.pixels + 500);
          await tester.pumpAndSettle();
          expectAttached();
          final hiddenTop = tester.getTopLeft(pill).dy;
          scroll.jumpTo(scroll.pixels + 100);
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(pill).dy, closeTo(hiddenTop, .01));
          await tester.dragFrom(const Offset(350, 400), const Offset(0, 180));
          await tester.pumpAndSettle();
          expectAttached();
          final initialTop = tester.getTopLeft(pill).dy;

          // Check while the finger is down: the toolbar and pill use the same progress.
          final drag = await tester.startGesture(const Offset(350, 500));
          await drag.moveBy(const Offset(0, -40));
          await tester.pump();
          await drag.moveBy(const Offset(0, -25));
          await tester.pump();
          expect(tester.getTopLeft(pill).dy, greaterThan(initialTop));
          expectAttached();
          await drag.up();
          await tester.pumpAndSettle();
          expectAttached();

          final stage = find.byKey(const ValueKey('image-stack-stage'));
          final afterImages = scroll.pixels + tester.getRect(stage).bottom + 1;
          scroll.jumpTo(afterImages);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));
          final fade = find
              .ancestor(of: pill, matching: find.byType(Opacity))
              .first;
          expect(
            tester.widget<Opacity>(fade).opacity,
            inExclusiveRange(0.0, 1.0),
          );
          await tester.pumpAndSettle();
          expect(pill, findsNothing);

          scroll.jumpTo(afterImages - 300);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));
          expect(
            tester.widget<Opacity>(fade).opacity,
            inExclusiveRange(0.0, 1.0),
          );
          await tester.pumpAndSettle();
          expectAttached();
          // The column now ends above the pill; its action must still hit.
          expect(
            tester.getRect(stage).bottom,
            lessThan(tester.getRect(pill).top),
          );
          await tester.tap(pill);
          await tester.pumpAndSettle();
          expect(tester.widget<ImageStackModeToggle>(pill).expanded, isFalse);
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('reduced motion switches the floating collapse pill directly', (
    tester,
  ) async {
    await gallery_fixture.mountStack(
      tester,
      count: 2,
      expanded: true,
      reduced: true,
      trailing: 2000,
    );
    final pill = find.byType(ImageStackModeToggle);
    expect(pill, findsOneWidget);
    final scroll = Scrollable.of(
      tester.element(find.byType(ImageStackGallery)),
    ).position;
    scroll.jumpTo(1000);
    await tester.pump();
    expect(pill, findsNothing);
    scroll.jumpTo(0);
    await tester.pump();
    expect(pill, findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
