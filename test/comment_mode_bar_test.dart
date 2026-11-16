import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/comment_mode_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final track = find.byKey(const ValueKey('comment-mode-track'));
  final thumb = find.byKey(const ValueKey('comment-mode-thumb'));
  Finder segment(int i) => find.byKey(ValueKey('comment-mode-$i'));
  late ValueNotifier<CommentViewMode> mode;
  late List<CommentViewMode> changes;
  Future<void> mount(
    WidgetTester tester, {
    double width = 300,
    double scale = 1,
    bool reduced = false,
    bool showAuthor = true,
    Brightness brightness = Brightness.light,
    AppearanceStyle style = AppearanceStyle.cinnabar,
  }) async {
    mode = ValueNotifier(CommentViewMode.threaded);
    changes = [];
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness, style),
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: ValueListenableBuilder<CommentViewMode>(
                  valueListenable: mode,
                  builder: (context, value, _) => CommentModeBar(
                    mode: value,
                    showAuthor: showAuthor,
                    onChanged: (value) {
                      changes.add(value);
                      mode.value = value;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void bounded(WidgetTester tester) {
    final rail = tester.getRect(track).deflate(CommentModeTokens.inset);
    final box = tester.getRect(thumb);
    expect(box.left, greaterThanOrEqualTo(rail.left - .001));
    expect(box.right, lessThanOrEqualTo(rail.right + .001));
  }

  testWidgets(
    'all selections keep one frame width and expose selected semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await mount(tester);
      final width = tester.getSize(track).width;
      expect(tester.getSize(track).height, 32);
      expect(tester.getSize(segment(0)).height, 44);
      for (var i = 0; i < 3; i++) {
        await tester.tap(segment(i));
        await tester.pumpAndSettle();
        expect(tester.getSize(track).width, width);
        expect(
          tester.getSemantics(find.bySemanticsLabel(['评论', '原楼层', '只看楼主'][i])),
          matchesSemantics(
            label: ['评论', '原楼层', '只看楼主'][i],
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
        bounded(tester);
      }
      semantics.dispose();
      expect(changes, [CommentViewMode.floors, CommentViewMode.author]);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'insufficient width shows icons with semantic labels and tooltips',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await mount(tester, width: 150, scale: 2);
      expect(tester.getSize(track).width, 124);
      expect(find.text('评论'), findsNothing);
      expect(find.bySemanticsLabel('只看楼主'), findsOneWidget);
      expect(find.byTooltip('只看楼主'), findsOneWidget);
      await tester.longPress(segment(2));
      await tester.pumpAndSettle();
      expect(find.text('只看楼主'), findsOneWidget);
      semantics.dispose();
      expect(changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown author offers two working segments', (tester) async {
    await mount(tester, showAuthor: false);
    expect(segment(2), findsNothing);
    final width = tester.getSize(track).width;
    await tester.tap(segment(1));
    await tester.pumpAndSettle();
    expect(changes, [CommentViewMode.floors]);
    expect(tester.getSize(track).width, width);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('two segment icon fallback uses 40 per segment', (tester) async {
    await mount(tester, width: 90, showAuthor: false, scale: 2);
    expect(tester.getSize(track).width, 84);
    expect(find.text('原楼层'), findsNothing);
    await tester.tap(segment(1));
    await tester.pumpAndSettle();
    expect(changes.single, CommentViewMode.floors);
  });

  testWidgets('slow drag chooses nearest but fast drag projects velocity', (
    tester,
  ) async {
    await mount(tester, width: 124, scale: 2);
    final start = tester.getCenter(segment(0));
    var gesture = await tester.startGesture(start);
    await gesture.moveBy(
      const Offset(21, 0),
      timeStamp: const Duration(milliseconds: 200),
    );
    await gesture.moveBy(
      const Offset(3, 0),
      timeStamp: const Duration(milliseconds: 600),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(mode.value, CommentViewMode.floors);
    mode.value = CommentViewMode.threaded;
    await tester.pumpAndSettle();
    changes.clear();
    gesture = await tester.startGesture(start);
    await gesture.moveBy(
      const Offset(21, 0),
      timeStamp: const Duration(milliseconds: 2020),
    );
    await gesture.moveBy(
      const Offset(12, 0),
      timeStamp: const Duration(milliseconds: 2030),
    );
    await gesture.moveBy(
      const Offset(7, 0),
      timeStamp: const Duration(milliseconds: 2040),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 2041));
    await tester.pumpAndSettle();
    // p = 1, capped velocity = 6: round(1 + 6 * .12) = 2.
    expect(mode.value, CommentViewMode.author);
    expect(changes, [CommentViewMode.author]);
  });

  testWidgets(
    'drag follows pointer, both overshoots stay inside and shrink at most 14%',
    (tester) async {
      await mount(tester, width: 124, scale: 2);
      final start = tester.getCenter(segment(0));
      final initial = tester.getRect(thumb);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(tester.getRect(thumb).left, closeTo(initial.left + 25, .001));
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();
      bounded(tester);
      expect(tester.getSize(thumb).width, closeTo(40 * .86, .001));
      await gesture.moveBy(const Offset(900, 0));
      await tester.pump();
      bounded(tester);
      expect(tester.getSize(thumb).width, closeTo(40 * .86, .001));
      await gesture.up();
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        bounded(tester);
      }
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('reduced motion jumps geometry and fades label for 180ms', (
    tester,
  ) async {
    await mount(tester, reduced: true);
    await tester.tap(segment(2));
    await tester.pump();
    final right = tester.getBottomRight(thumb).dx;
    expect(right, closeTo(tester.getBottomRight(track).dx - 2, .001));
    final text = tester.widget<Text>(find.text('只看楼主'));
    expect(text.style!.color!.a, 0);
    await tester.pump(AppMotion.fade);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<Text>(find.text('只看楼主')).style!.color!.a, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'parent rollback interrupts selection and settles with no ticker',
    (tester) async {
      await mount(tester);
      await tester.tap(segment(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final moving = tester.getRect(thumb).left;
      mode.value = CommentViewMode.threaded;
      await tester.pump();
      expect(tester.getRect(thumb).left, closeTo(moving, .001));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(thumb).left,
        closeTo(tester.getRect(track).left + 2, .001),
      );
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'fading labels stay whole inside the track on intermediate frames',
    (tester) async {
      await mount(tester);
      await tester.tap(segment(2));
      await tester.pump();
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        final bounds = tester.getRect(track).deflate(CommentModeTokens.inset);
        for (final label in ['评论', '原楼层', '只看楼主']) {
          final finder = find.text(label);
          if (tester.widget<Text>(finder).style!.color!.a == 0) continue;
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(bounds.left - .001));
          expect(rect.right, lessThanOrEqualTo(bounds.right + .001));
        }
      }
      await tester.pumpAndSettle();
    },
  );

  testWidgets('catching an edge spring does not apply resistance twice', (
    tester,
  ) async {
    await mount(tester, width: 124, scale: 2);
    var gesture = await tester.startGesture(tester.getCenter(segment(0)));
    await gesture.moveBy(
      const Offset(-27, 0),
      timeStamp: const Duration(milliseconds: 200),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final over =
        (1 - tester.getSize(thumb).width / 40) /
        CommentModeTokens.overscrollShrink;
    expect(over, greaterThan(0));
    gesture = await tester.startGesture(tester.getCenter(segment(0)));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    final shrink = ((over + 20 / 40 * .3) * .35).clamp(0.0, .14);
    expect(tester.getSize(thumb).width, closeTo(40 * (1 - shrink), .001));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('keyboard activation uses the same selection callback', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changes, [CommentViewMode.floors]);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$style $brightness retains geometry without overflow', (
        tester,
      ) async {
        await mount(tester, style: style, brightness: brightness);
        await tester.tap(segment(2));
        await tester.pumpAndSettle();
        bounded(tester);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}
