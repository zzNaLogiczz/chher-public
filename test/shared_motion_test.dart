import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/scroll_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ScrollController> mountScroll(WidgetTester tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ListView.builder(
            controller: scroll,
            itemExtent: 100,
            itemCount: 200,
            itemBuilder: (_, i) => Text('row $i'),
          ),
        ),
      ),
    );
    addTearDown(scroll.dispose);
    return scroll;
  }

  testWidgets('long scroll jumps to one viewport from target before spring', (
    tester,
  ) async {
    final scroll = await mountScroll(tester);
    final viewport = scroll.position.viewportDimension;
    final target = viewport * 5;
    final done = AppMotion.scrollTo(scroll.position, target);
    expect(scroll.offset, target - viewport);
    await tester.pumpAndSettle();
    await done;
    expect(scroll.offset, closeTo(target, .01));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('short scroll does not jump and a user drag interrupts it', (
    tester,
  ) async {
    final scroll = await mountScroll(tester);
    final target = scroll.position.viewportDimension;
    final done = AppMotion.scrollTo(scroll.position, target);
    expect(scroll.offset, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final gesture = await tester.startGesture(const Offset(300, 300));
    await gesture.moveBy(const Offset(0, 50));
    await gesture.up();
    await tester.pumpAndSettle();
    await done;
    expect(scroll.offset, lessThan(target));
  });

  testWidgets('reduced motion scroll and gesture settlement are immediate', (
    tester,
  ) async {
    final scroll = await mountScroll(tester);
    await AppMotion.scrollTo(scroll.position, 3000, reduced: true);
    expect(scroll.offset, 3000);
    final controller = AnimationController.unbounded(vsync: tester, value: .4);
    AppMotion.settle(
      controller,
      target: 1,
      motion: AppMotion.sheet,
      velocity: 8,
      reduced: true,
    );
    expect(controller.value, 1);
    expect(controller.isAnimating, isFalse);
    controller.dispose();
  });

  testWidgets('gesture settlement carries release velocity and rests exactly', (
    tester,
  ) async {
    final slow = AnimationController.unbounded(vsync: tester, value: .4);
    final fast = AnimationController.unbounded(vsync: tester, value: .4);
    AppMotion.settle(slow, target: 1, motion: AppMotion.reveal, velocity: 0);
    AppMotion.settle(fast, target: 1, motion: AppMotion.reveal, velocity: 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(fast.value, greaterThan(slow.value));
    await tester.pumpAndSettle();
    expect(slow.value, 1);
    expect(fast.value, 1);
    expect(slow.isAnimating || fast.isAnimating, isFalse);
    slow.dispose();
    fast.dispose();
  });

  testWidgets('compact progress snaps only the middle band to nearest end', (
    tester,
  ) async {
    final scroll = await mountScroll(tester);
    final progress = ScrollLinkedProgress(
      position: scroll.position,
      start: 0,
      end: 200,
    );
    scroll.jumpTo(30);
    await progress.snapIfIdle();
    expect(scroll.offset, 30);
    scroll.jumpTo(60);
    final first = progress.snapIfIdle();
    await tester.pumpAndSettle();
    await first;
    expect(progress.value, 0);
    scroll.jumpTo(140);
    final second = progress.snapIfIdle();
    await tester.pumpAndSettle();
    await second;
    expect(progress.value, 1);
    progress.dispose();
  });

  testWidgets('compact progress waits for inertial scroll to end', (
    tester,
  ) async {
    final scroll = await mountScroll(tester);
    final progress = ScrollLinkedProgress(
      position: scroll.position,
      start: 0,
      end: 2000,
    );
    scroll.jumpTo(500);
    await tester.fling(find.byType(ListView), const Offset(0, -80), 500);
    expect(scroll.position.isScrollingNotifier.value, isTrue);
    final pixels = scroll.offset;
    await progress.snapIfIdle();
    expect(scroll.offset, pixels);
    await tester.pumpAndSettle();
    expect(progress.value, anyOf(0.0, 1.0));
    progress.dispose();
  });
}
