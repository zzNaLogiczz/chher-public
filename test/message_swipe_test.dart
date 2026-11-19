import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/message_pager.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness extends StatefulWidget {
  final ValueNotifier<double> position;
  final List<int> visits;
  final bool reduced;
  const _Harness(this.position, this.visits, {this.reduced = false});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: widget.reduced),
      child: Scaffold(
        body: Column(
          children: [
            AppSegmented<int>(
              messageStyle: true,
              position: widget.position,
              badgeCounts: const [3, 1],
              value: selected,
              onChanged: (value) => setState(() => selected = value),
              options: const [
                PickerOption(value: 0, label: '提醒'),
                PickerOption(value: 1, label: '私信'),
              ],
            ),
            Expanded(
              child: MessagePager(
                value: selected,
                position: widget.position,
                onVisit: widget.visits.add,
                onChanged: (value) => setState(() => selected = value),
                itemBuilder: (context, index) => ListView.builder(
                  key: PageStorageKey('list-$index'),
                  itemCount: 100,
                  itemBuilder: (context, row) =>
                      SizedBox(height: 60, child: Text('page $index row $row')),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('visited inactive page cannot receive keyboard focus', (
    tester,
  ) async {
    final position = ValueNotifier(0.0);
    final nodes = [FocusNode(), FocusNode()];
    addTearDown(() {
      position.dispose();
      for (final node in nodes) {
        node.dispose();
      }
    });
    var value = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: MessagePager(
                value: value,
                position: position,
                onChanged: (i) => setState(() => value = i),
                itemBuilder: (_, i) =>
                    Center(child: TextField(focusNode: nodes[i])),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => value = 1);
    await tester.pumpAndSettle();
    expect(nodes[0].canRequestFocus, isFalse);
    nodes[0].requestFocus();
    await tester.pump();
    expect(nodes[0].hasFocus, isFalse);
    expect(nodes[1].canRequestFocus, isTrue);
  });

  test(
    'one third threshold, strict flick threshold, and first/last bounds',
    () {
      int target(int start, double p, double v) =>
          messageSwipeTarget(start: start, position: p, velocity: v);
      expect(target(0, 1 / 3, 0), 0);
      expect(target(0, .334, 0), 1);
      expect(target(1, .667, 0), 1);
      expect(target(1, .666, 0), 0);
      expect(target(0, .1, -500), 0);
      expect(target(0, .1, -501), 1);
      expect(target(1, .9, 501), 0);
      expect(target(0, -.5, 1000), 0);
      expect(target(1, 1.5, -1000), 1);
    },
  );

  testWidgets(
    'horizontal drag is direct and pages settle without live tickers',
    (tester) async {
      final position = ValueNotifier(0.0);
      addTearDown(position.dispose);
      final visits = <int>[];
      await tester.pumpWidget(_Harness(position, visits));
      await tester.pumpAndSettle();
      expect(find.text('page 1 row 0'), findsNothing);
      final area = tester.getRect(find.byType(MessagePager));
      final gesture = await tester.startGesture(area.center);
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      final before = position.value;
      await gesture.moveBy(const Offset(-50, 0));
      await tester.pump();
      expect(position.value - before, closeTo(50 / area.width, .0001));
      expect(visits, [1]);
      await gesture.moveBy(Offset(-area.width / 2, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(position.value, 1);
      expect(find.text('page 1 row 0'), findsOneWidget);
      expect(find.text('page 0 row 0'), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('vertical scroll does not visit the other page', (tester) async {
    final position = ValueNotifier(0.0);
    addTearDown(position.dispose);
    final visits = <int>[];
    await tester.pumpWidget(_Harness(position, visits));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(MessagePager), const Offset(10, -250));
    await tester.pumpAndSettle();
    expect(position.value, 0);
    expect(visits, isEmpty);
    expect(find.text('page 0 row 0'), findsNothing);
  });

  testWidgets('a tap reverses an unfinished swipe in place', (tester) async {
    final position = ValueNotifier(0.0);
    addTearDown(position.dispose);
    await tester.pumpWidget(_Harness(position, []));
    await tester.pumpAndSettle();
    final pager = find.byType(MessagePager);
    final width = tester.getSize(pager).width;
    await tester.drag(pager, Offset(-.55 * width, 0));
    await tester.pump();
    final partial = position.value;
    expect(partial, inExclusiveRange(.33, 1));
    final incoming = find.text('page 1 row 0');
    final before = tester.getTopLeft(incoming);
    await tester.tap(find.text('提醒'));
    await tester.pump();
    expect(tester.getTopLeft(incoming), before);
    await tester.pumpAndSettle();
    expect(position.value, 0);
    expect(incoming, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('short slow drag returns, endpoints resist and settle', (
    tester,
  ) async {
    final position = ValueNotifier(0.0);
    addTearDown(position.dispose);
    await tester.pumpWidget(_Harness(position, []));
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byType(MessagePager),
      const Offset(-100, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(position.value, 0);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MessagePager)),
    );
    await gesture.moveBy(const Offset(250, 0));
    await tester.pump();
    expect(position.value, lessThan(0));
    expect(position.value, greaterThan(-.18));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(position.value, 0);
  });

  testWidgets(
    'selection spring can be grabbed and reduced motion settles now',
    (tester) async {
      final position = ValueNotifier(0.0);
      addTearDown(position.dispose);
      await tester.pumpWidget(_Harness(position, []));
      await tester.pumpAndSettle();
      await tester.tap(find.text('私信'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final partial = position.value;
      expect(partial, greaterThan(0));
      expect(partial, lessThan(1));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MessagePager)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(position.value, partial);
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      position.value = 0;
      await tester.pumpWidget(_Harness(position, [], reduced: true));
      await tester.tap(find.text('私信'));
      await tester.pump();
      expect(position.value, 1);
    },
  );

  testWidgets('message segment geometry and shared fractional position', (
    tester,
  ) async {
    final position = ValueNotifier(.5);
    addTearDown(position.dispose);
    for (final brightness in Brightness.values) {
      for (final style in AppearanceStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness, style),
            home: Scaffold(
              body: Column(
                children: [
                  for (final compact in [false, true])
                    AppSegmented<int>(
                      messageStyle: true,
                      compact: compact,
                      onLac: style == AppearanceStyle.cinnabar,
                      position: position,
                      badgeCounts: const [2, 0],
                      value: 0,
                      onChanged: (_) {},
                      options: const [
                        PickerOption(value: 0, label: '提醒'),
                        PickerOption(value: 1, label: '私信'),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final segments = find.byType(AppSegmented<int>);
        expect(tester.getSize(segments.first).height, 44);
        expect(tester.getSize(segments.last).height, 34);
        for (final segment in [segments.first, segments.last]) {
          final thumb = find.descendant(
            of: segment,
            matching: find.byKey(AppSegmented.thumbKey),
          );
          expect(
            tester.getCenter(thumb).dx,
            closeTo(tester.getCenter(segment).dx, 1),
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
}
