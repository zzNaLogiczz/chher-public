import 'dart:async';

import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:chh_app/widgets/chhers_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;

import 'package:flutter_test/flutter_test.dart';

const _viewportHeight = 480.0;
const _rowHeight = 56.0;

Widget _app(
  Future<void> Function() onRefresh, {
  ScrollPhysics physics = const ClampingScrollPhysics(),
}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        height: _viewportHeight,
        child: ChhersRefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            physics: physics,
            itemExtent: _rowHeight,
            itemCount: 40,
            itemBuilder: (context, index) => Text('行 $index'),
          ),
        ),
      ),
    ),
  ),
);

ChhersLoader _indicator(WidgetTester tester) =>
    tester.widget<ChhersLoader>(find.byType(ChhersLoader));

Future<TestGesture> _startDrag(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ListView)),
  );
  await gesture.moveBy(const Offset(0, kTouchSlop));
  await gesture.moveBy(const Offset(0, 1));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets(
    'pull distance is mapped to path progress and cancels below threshold',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(() async => calls++));
      final gesture = await _startDrag(tester);
      final initialProgress = _indicator(tester).progress!;
      await gesture.moveBy(
        Offset(0, (.5 - initialProgress) * _viewportHeight / 6),
      );
      await tester.pump();
      expect(_indicator(tester).size, ChhersLoaderSize.refresh);
      expect(_indicator(tester).progress, closeTo(.5, .02));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(_indicator(tester).progress, closeTo(.75, .02));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byType(ChhersLoader), findsNothing);
    },
  );

  testWidgets(
    'arming starts one refresh, fades and restores the reading position',
    (tester) async {
      var calls = 0;
      final completion = Completer<void>();
      await tester.pumpWidget(
        _app(() {
          calls++;
          return completion.future;
        }),
      );
      final origin = tester.getTopLeft(find.text('行 0'));

      final gesture = await _startDrag(tester);
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(_indicator(tester).progress, 1);
      expect(calls, 0);

      await gesture.up();
      await tester.pump();
      await tester.pump(AppMotion.scrollChrome.duration);
      expect(_indicator(tester).animate, isTrue);
      expect(_indicator(tester).progress, isNull);
      expect(calls, 1);

      final state = tester.state<ChhersRefreshIndicatorState>(
        find.byType(ChhersRefreshIndicator),
      );
      final first = state.show();
      final second = state.show();
      expect(second, same(first));
      expect(calls, 1);

      completion.complete();
      await tester.pump();
      expect(_indicator(tester).animate, isFalse);
      await tester.pump(AppMotion.loadingOut);
      await tester.pumpAndSettle();
      await first;
      expect(find.byType(ChhersLoader), findsNothing);
      expect(tester.getTopLeft(find.text('行 0')), origin);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('bouncing scroll triggers once on release', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        () async => calls++,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
      ),
    );
    final gesture = await _startDrag(tester);
    await gesture.moveBy(const Offset(0, 140));
    await tester.pump();
    expect(_indicator(tester).progress, 1);
    expect(calls, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(ChhersLoader), findsNothing);
  });
  for (final disabledTicker in [true, false]) {
    testWidgets(
      'refresh dismisses when ${disabledTicker ? 'TickerMode is off' : 'the app backgrounds'}',
      (tester) async {
        var calls = 0;
        final completion = Completer<void>();
        final enabled = ValueNotifier(true);
        addTearDown(enabled.dispose);
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        await tester.pumpWidget(
          ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, value, child) =>
                TickerMode(enabled: value, child: child!),
            child: _app(() {
              calls++;
              return calls == 1 ? completion.future : Future<void>.value();
            }),
          ),
        );
        final state = tester.state<ChhersRefreshIndicatorState>(
          find.byType(ChhersRefreshIndicator),
        );
        final first = state.show();
        await tester.pump();
        await tester.pump(AppMotion.scrollChrome.duration);
        expect(find.byType(ChhersLoader), findsOneWidget);

        completion.complete();
        await tester.pump();
        expect(_indicator(tester).animate, isFalse);
        if (disabledTicker) {
          enabled.value = false;
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        await tester.pump();
        await first;
        expect(find.byType(ChhersLoader), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);

        if (disabledTicker) {
          enabled.value = true;
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pump();
        await state.show();
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.byType(ChhersLoader), findsNothing);
      },
    );
  }
}
