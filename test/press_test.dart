import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {bool reduced = false}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: Center(child: child)),
  ),
);

double scaleOf(WidgetTester t) => t
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(PressScale),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .storage[0];

Color tintOf(WidgetTester t) => t
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(PressHighlight),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

const box = SizedBox(width: 100, height: 50);

void main() {
  testWidgets('block press reacts on the first frame and settles at 0.96', (
    tester,
  ) async {
    await tester.pumpWidget(app(PressScale(onTap: () {}, child: box)));
    final g = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(scaleOf(tester), lessThan(1));
    await tester.pumpAndSettle();
    expect(scaleOf(tester), closeTo(0.96, 0.001));
    await g.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
  });

  testWidgets('moving past touch slop cancels the press and the tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(app(PressScale(onTap: () => taps++, child: box)));
    final g = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(scaleOf(tester), lessThan(1));
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(scaleOf(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    await g.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(scaleOf(tester), 1);
  });

  testWidgets(
    'row highlight paints pressed color at once, fades back, no scale',
    (tester) async {
      await tester.pumpWidget(app(PressHighlight(onTap: () {}, child: box)));
      final g = await tester.startGesture(
        tester.getCenter(find.byType(PressHighlight)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tintOf(tester), AppTokens.light.pressed);
      expect(
        find.descendant(
          of: find.byType(PressHighlight),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tintOf(tester).a, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tintOf(tester).a, 0);
    },
  );

  testWidgets('row slop cancellation clears immediately without fade', (
    tester,
  ) async {
    await tester.pumpWidget(app(PressHighlight(onTap: () {}, child: box)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressHighlight)),
    );
    await tester.pump();
    expect(tintOf(tester), AppTokens.light.pressed);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(tintOf(tester).a, 0);
    expect(tester.binding.transientCallbackCount, 0);
    await gesture.up();
  });

  testWidgets('starting ancestor scroll clears held row without fade', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      app(
        ListView(
          controller: scroll,
          children: [
            PressHighlight(onTap: () {}, child: box),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressHighlight)),
    );
    await tester.pump();
    expect(tintOf(tester), AppTokens.light.pressed);
    final scrolling = scroll.animateTo(
      100,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
    await tester.pump();
    expect(tintOf(tester).a, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    await scrolling;
  });

  for (final scale in [
    AppPressScale.control,
    AppPressScale.card,
    AppPressScale.content,
  ]) {
    testWidgets('press settles at named scale $scale', (tester) async {
      await tester.pumpWidget(
        app(PressScale(onTap: () {}, scale: scale, child: box)),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressScale)),
      );
      await tester.pumpAndSettle();
      expect(scaleOf(tester), closeTo(scale, .001));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('reduced motion keeps scale at 1 and still taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      app(PressScale(onTap: () => taps++, child: box), reduced: true),
    );
    final g = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(scaleOf(tester), 1);
    await g.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('Enter activates a focused press target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(PressScale(onTap: () => taps++, child: box)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 1);
  });
}
