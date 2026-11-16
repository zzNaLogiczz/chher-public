import 'package:chh_app/design/theme.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

void main() {
  for (final reduced in [false, true]) {
    testWidgets('gallery stagger settles without timers reduced=$reduced', (
      tester,
    ) async {
      await fixture.mountStack(tester, reduced: reduced);
      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pump();
      // The floating control is attached after the expanded column is measured;
      // advance its first select frame without settling the FLIP being tested.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final dynamic state = tester.state(find.byType(ImageStackGallery));
      final collapse = find.byWidgetPredicate(
        (widget) => widget is ImageStackModeToggle && widget.expanded,
      );
      final expand = find.byWidgetPredicate(
        (widget) => widget is ImageStackModeToggle && !widget.expanded,
      );
      expect(collapse, findsOneWidget);
      expect(expand, findsNothing);
      expect(state.debugActiveCardMotions, reduced ? 0 : greaterThan(0));
      if (!reduced) {
        await tester.pump(const Duration(milliseconds: 45));
        // Collapse interrupts the shared FLIP timeline before it settles.
        await tester.tap(collapse);
        await tester.pump();
        expect(expand, findsOneWidget);
        expect(collapse.hitTestable(), findsNothing);
      } else {
        await tester.tap(collapse);
        await tester.pump();
        expect(expand, findsOneWidget);
        expect(collapse, findsNothing);
      }
      await tester.pumpAndSettle();
      expect(state.debugActiveCardMotions, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion picker does not wait to return selection', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = (await showPickerSheet<int>(
                  context,
                  title: '选择',
                  options: const [
                    PickerOption(value: 0, label: '全部'),
                    PickerOption(value: 1, label: '收藏'),
                  ],
                  value: 0,
                ))?.value;
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pump();
    expect(picked, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('disposing a picker during selection cancels completion', (
    tester,
  ) async {
    var reported = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: PickerButton<int>(
            sheetTitle: '选择',
            options: const [
              PickerOption(value: 0, label: '全部'),
              PickerOption(value: 1, label: '收藏'),
            ],
            value: 0,
            onChanged: (_) => reported++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(reported, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back interrupts picker completion without popping its host', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: Text('首页')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: PickerButton<int>(
            sheetTitle: '选择',
            options: const [
              PickerOption(value: 0, label: '全部'),
              PickerOption(value: 1, label: '收藏'),
            ],
            value: 0,
            onChanged: (_) => fail('Dismissal must not commit selection'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(PickerButton<int>), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('visited background destinations mute their tickers', (
    tester,
  ) async {
    final ticks = <AppDestination, int>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: HomePage(
          initialiseSession: () async {},
          screenBuilders: {
            for (final destination in AppDestination.values)
              destination: (_) => _TickProbe(
                onTick: () => ticks.update(
                  destination,
                  (value) => value + 1,
                  ifAbsent: () => 1,
                ),
              ),
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks[AppDestination.feed], greaterThan(0));
    await tester.tap(find.text('版块'));
    await tester.pump();
    final previous = ticks[AppDestination.feed];
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks[AppDestination.feed], previous);
    expect(ticks[AppDestination.forums], greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });
}

class _TickProbe extends StatefulWidget {
  final VoidCallback onTick;
  const _TickProbe({required this.onTick});

  @override
  State<_TickProbe> createState() => _TickProbeState();
}

class _TickProbeState extends State<_TickProbe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(widget.onTick);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
