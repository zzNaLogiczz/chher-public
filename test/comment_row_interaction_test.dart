import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/comment_row_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('assistive long-press action opens without a pointer gesture', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var opens = 0;
    await tester.pumpWidget(
      _app(
        CommentRowInteraction(
          onLongPress: () => opens++,
          child: const Text('回复内容'),
        ),
      ),
    );
    final node = tester.getSemantics(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.onLongPress != null,
      ),
    );
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.longPress,
        nodeId: node.id,
        viewId: tester.view.viewId,
      ),
    );
    expect(opens, 1);
    semantics.dispose();
  });
  testWidgets('more has a 34 by 28 hit area and three 3px dots', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(_app(CommentMoreButton(onPressed: () => opens++)));
    expect(tester.getSize(find.byType(CommentMoreButton)), const Size(34, 28));
    final dots = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).shape == BoxShape.circle,
        );
    expect(dots.length, 3);
    for (final dot in dots) {
      expect((dot.decoration as BoxDecoration).color, AppTokens.light.text3);
      expect((dot.child as SizedBox).width, 3);
    }
    final rect = tester.getRect(find.byType(CommentMoreButton));
    await tester.tapAt(rect.topLeft + const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('hold tints at 150ms and opens once at 400ms without row tap', (
    tester,
  ) async {
    var opens = 0;
    final highlight = ValueNotifier(false);
    addTearDown(highlight.dispose);
    await tester.pumpWidget(
      _app(
        CommentRowInteraction(
          highlight: highlight,
          onLongPress: () => opens++,
          child: const SizedBox(width: 300, height: 100, child: Text('回复内容')),
        ),
      ),
    );
    await tester.tap(find.text('回复内容'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opens, 0);
    expect(highlight.value, isFalse);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CommentRowInteraction)),
    );
    await tester.pump(const Duration(milliseconds: 149));
    expect(highlight.value, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(highlight.value, isTrue);
    expect(opens, 0);
    await tester.pump(const Duration(milliseconds: 249));
    expect(opens, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(opens, 1);
    expect(highlight.value, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('moving and cancelling clear tint and prevent the menu', (
    tester,
  ) async {
    var opens = 0;
    final highlight = ValueNotifier(false);
    addTearDown(highlight.dispose);
    await tester.pumpWidget(
      _app(
        CommentRowInteraction(
          highlight: highlight,
          onLongPress: () => opens++,
          child: const SizedBox(width: 300, height: 100),
        ),
      ),
    );
    final row = find.byType(CommentRowInteraction);
    final drag = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 150));
    expect(highlight.value, isTrue);
    await drag.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(highlight.value, isFalse);
    expect(opens, 0);
    await drag.up();
    final cancelled = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 150));
    await cancelled.cancel();
    await tester.pump(const Duration(milliseconds: 500));
    expect(highlight.value, isFalse);
    expect(opens, 0);
  });

  testWidgets(
    'shared highlight paints every fragment and leaves content visible',
    (tester) async {
      final highlight = ValueNotifier(false);
      addTearDown(highlight.dispose);
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 2; i++)
                CommentRowInteraction(
                  highlight: highlight,
                  onLongPress: () {},
                  child: ColoredBox(
                    color: AppTokens.light.surface,
                    child: SizedBox(
                      width: 300,
                      height: 50,
                      child: Text('片段 $i'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      final hold = await tester.startGesture(
        tester.getCenter(find.text('片段 0')),
      );
      await tester.pump(const Duration(milliseconds: 150));
      final overlays = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((box) => box.color.a > 0 && box.color.a < .1);
      expect(overlays.length, 2);
      await hold.cancel();
      await tester.pumpAndSettle();
    },
  );
}
