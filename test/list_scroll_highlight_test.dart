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

Iterable<Color> _rowTints(WidgetTester tester) => tester
    .widgetList<ColoredBox>(
      find.descendant(
        of: find.byType(PressHighlight),
        matching: find.byType(ColoredBox),
      ),
    )
    .map((box) => box.color);

void _expectNoRowHighlight(WidgetTester tester) =>
    expect(_rowTints(tester).where((color) => color.a > 0), isEmpty);

void main() {
  testWidgets(
    'a confirmed thread tap opens once and its highlight fades back',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 500);
      addTearDown(controller.dispose);
      var taps = 0;
      await tester.pumpWidget(_threadList(controller, () => taps++));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 150));
      expect(taps, 0);
      _expectNoRowHighlight(tester);
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
    },
  );

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
