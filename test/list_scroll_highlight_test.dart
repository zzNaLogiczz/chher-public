import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _threadList(ScrollController controller, VoidCallback onTap) =>
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: PrimaryScrollController(
          controller: controller,
          child: BrowseThreadList(
            groupCards: true,
            loader: (page, {bool refresh = false}) async => Paged(
              items: [
                for (var i = 0; i < 60; i++)
                  ThreadSummary(
                    tid: i + 1,
                    title: '滚动测试帖子 $i',
                    author: '测试作者',
                    replies: 12,
                    views: 345,
                  ),
              ],
              page: const PageInfo(current: 1, hasNext: false),
            ),
            itemBuilder: (_, thread) =>
                ThreadRow(thread: thread, forumStyle: true, onTap: onTap),
          ),
        ),
      ),
    );

Iterable<Color> _rowTints(WidgetTester tester) sync* {
  for (final row in tester.widgetList(find.byType(PressHighlight))) {
    final tint = find
        .descendant(of: find.byWidget(row), matching: find.byType(ColoredBox))
        .first;
    yield tester.widget<ColoredBox>(tint).color;
  }
}

void _expectNoRowHighlight(WidgetTester tester) =>
    expect(_rowTints(tester).where((color) => color.a > 0), isEmpty);

void main() {
  testWidgets('a held row highlights at 70ms without changing its size', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 500);
    addTearDown(controller.dispose);
    var taps = 0;
    await tester.pumpWidget(_threadList(controller, () => taps++));
    await tester.pumpAndSettle();
    final row = find.byType(PressHighlight).hitTestable().first;
    final position = tester.getCenter(row);
    final size = tester.getSize(row);
    final gesture = await tester.startGesture(position);
    await tester.pump(const Duration(milliseconds: 69));
    expect(taps, 0);
    _expectNoRowHighlight(tester);
    expect(tester.getSize(row), size);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_rowTints(tester).where((color) => color.a > 0), hasLength(1));
    expect(tester.getSize(row), size);
    await gesture.up();
    expect(taps, 1);
    await tester.pump();
    expect(_rowTints(tester).where((color) => color.a > 0), hasLength(1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      _rowTints(tester).where((color) => color.a > 0).single.a,
      inExclusiveRange(0, 1),
    );
    await tester.pumpAndSettle();
    _expectNoRowHighlight(tester);
    expect(taps, 1);
  });

  testWidgets('movement past 8dp cancels before and after the delay', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 500);
    addTearDown(controller.dispose);
    var taps = 0;
    await tester.pumpWidget(_threadList(controller, () => taps++));
    await tester.pumpAndSettle();

    for (final delay in [20, 70]) {
      final gesture = await tester.startGesture(const Offset(400, 300));
      await tester.pump(Duration(milliseconds: delay));
      expect(_rowTints(tester).any((color) => color.a > 0), delay == 70);
      await gesture.moveBy(const Offset(0, 9));
      await tester.pump(const Duration(milliseconds: 70));
      _expectNoRowHighlight(tester);
      await gesture.up();
      expect(taps, 0);
    }
  });

  testWidgets('a quick row tap fires on release before the highlight delay', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 500);
    addTearDown(controller.dispose);
    var taps = 0;
    await tester.pumpWidget(_threadList(controller, () => taps++));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 20));
    _expectNoRowHighlight(tester);
    await gesture.up();
    expect(taps, 1);
    await tester.pump();
    expect(_rowTints(tester).where((color) => color.a > 0), hasLength(1));
    await tester.pumpAndSettle();
    _expectNoRowHighlight(tester);
  });

  testWidgets('thread rows still activate from Enter and Space', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var taps = 0;
    await tester.pumpWidget(_threadList(controller, () => taps++));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 2);
    await tester.pumpAndSettle();
  });

  for (final direction in [-1.0, 1.0]) {
    testWidgets('thread scroll $direction never paints a startup grey stripe', (
      tester,
    ) async {
      final controller = ScrollController(initialScrollOffset: 500);
      addTearDown(controller.dispose);
      var taps = 0;
      await tester.pumpWidget(_threadList(controller, () => taps++));
      await tester.pumpAndSettle();
      controller.jumpTo(500);
      await tester.pump();
      final before = controller.offset;
      final gesture = await tester.startGesture(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 8));
      _expectNoRowHighlight(tester);
      await gesture.moveBy(Offset(0, direction * 8));
      await tester.pump(const Duration(milliseconds: 16));
      _expectNoRowHighlight(tester);
      await gesture.moveBy(Offset(0, direction * 40));
      await tester.pump(const Duration(milliseconds: 16));
      _expectNoRowHighlight(tester);
      await gesture.moveBy(Offset(0, direction * 80));
      await tester.pump(const Duration(milliseconds: 16));
      _expectNoRowHighlight(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.offset, isNot(before));
      expect(taps, 0);
      _expectNoRowHighlight(tester);
    });
  }

  testWidgets('touching an already scrolling thread list adds no grey stripe', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 500);
    addTearDown(controller.dispose);
    var taps = 0;
    await tester.pumpWidget(_threadList(controller, () => taps++));
    await tester.pumpAndSettle();
    final motion = controller.animateTo(
      1000,
      duration: const Duration(seconds: 1),
      curve: Curves.linear,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 8));
    _expectNoRowHighlight(tester);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await motion;
    expect(taps, 0);
    _expectNoRowHighlight(tester);
  });
}
