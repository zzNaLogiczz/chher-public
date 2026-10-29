import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:flutter/services.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double cardScale(WidgetTester tester) => tester
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

void main() {
  testWidgets(
    'keyboard traversal exposes focus and activates both control families',
    (tester) async {
      final previous = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = previous);
      var cards = 0;
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PressScale(
                  onTap: () => cards++,
                  child: const SizedBox(
                    width: 100,
                    height: 100,
                    child: Text('卡片'),
                  ),
                ),
                PressScale(
                  onTap: () => actions++,
                  child: const SizedBox(
                    width: 100,
                    height: 100,
                    child: Text('操作'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      var rings = tester
          .widgetList<ActionFocusRing>(find.byType(ActionFocusRing))
          .toList();
      expect(rings[0].visible, isTrue);
      expect(rings[1].visible, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(cards, 1);
      expect(actions, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      rings = tester
          .widgetList<ActionFocusRing>(find.byType(ActionFocusRing))
          .toList();
      expect(rings[0].visible, isFalse);
      expect(rings[1].visible, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(cards, 1);
      expect(actions, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'press feedback is visible before tap recognizer deadline, drag still cancels action',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                PressScale(
                  onTap: () => taps++,
                  child: const SizedBox(height: 150, child: Text('card')),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      final touch = await tester.startGesture(
        tester.getCenter(find.text('card')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 8));
      expect(cardScale(tester), lessThan(1));
      expect(taps, 0);
      await touch.moveBy(const Offset(0, -80));
      await tester.pump();
      await touch.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(cardScale(tester), 1);
      expect(tester.takeException(), isNull);
    },
  );
}
