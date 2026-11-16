import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'shared_sheet_back_test.dart' show mountRoute, predictive;

void main() {
  testWidgets(
    'moving system back books every frame, rests on pause and resumes directly',
    (tester) async {
      final nav = await mountRoute(tester);
      final route = ModalRoute.of(tester.element(find.text('detail')))!;
      await predictive(tester, 'startBackGesture');
      for (final p in [.1, .13, .21, .2, .19, .4]) {
        await predictive(tester, 'updateBackGestureProgress', p);
        await tester.pump(const Duration(milliseconds: 8));
        expect(route.animation!.value, closeTo(1 - p, .000001));
        expect(tester.binding.transientCallbackCount, 1);
        expect(tester.binding.hasScheduledFrame, isTrue);
      }
      for (var i = 0; i < 12; i++) {
        await predictive(tester, 'updateBackGestureProgress', .4);
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(tester.binding.transientCallbackCount, 0);
      expect(route.animation!.value, .6);
      await predictive(tester, 'updateBackGestureProgress', .45);
      await tester.pump(const Duration(milliseconds: 8));
      expect(route.animation!.value, .55);
      expect(tester.binding.transientCallbackCount, 1);
      await predictive(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(nav.currentState!.userGestureInProgress, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('disposing an active system back leaves no frame driver', (
    tester,
  ) async {
    await mountRoute(tester);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .2);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion never starts the system gesture frame driver', (
    tester,
  ) async {
    await mountRoute(tester, reduced: true);
    await predictive(tester, 'startBackGesture');
    await predictive(tester, 'updateBackGestureProgress', .4);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
