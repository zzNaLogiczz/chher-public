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
  Future<void> Function()? onRefreshAtEnd,
  ScrollPhysics physics = const ClampingScrollPhysics(),
  int itemCount = 40,
}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        height: _viewportHeight,
        child: ChhersRefreshIndicator(
          onRefresh: onRefresh,
          onRefreshAtEnd: onRefreshAtEnd,
          child: ListView.builder(
            physics: physics,
            itemExtent: _rowHeight,
            itemCount: itemCount,
            itemBuilder: (context, index) => Text('行 $index'),
          ),
        ),
      ),
    ),
  ),
);

ChhersLoader _indicator(WidgetTester tester) =>
    tester.widget<ChhersLoader>(find.byType(ChhersLoader));

Future<TestGesture> _startDrag(
  WidgetTester tester, {
  bool upward = false,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ListView)),
  );
  final sign = upward ? -1.0 : 1.0;
  await gesture.moveBy(Offset(0, sign * kTouchSlop));
  await gesture.moveBy(Offset(0, sign));
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

  for (final physics in const [
    ClampingScrollPhysics(),
    BouncingScrollPhysics(),
  ]) {
    testWidgets('the end refresh is compact with ${physics.runtimeType}', (
      tester,
    ) async {
      var topCalls = 0;
      var endCalls = 0;
      final completion = Completer<void>();
      await tester.pumpWidget(
        _app(
          () async => topCalls++,
          onRefreshAtEnd: () {
            endCalls++;
            return completion.future;
          },
          physics: physics,
        ),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(position.maxScrollExtent - _rowHeight);
      await tester.pumpAndSettle();
      final crossing = await _startDrag(tester, upward: true);
      await crossing.moveBy(const Offset(0, -200));
      await crossing.up();
      await tester.pumpAndSettle();
      expect(endCalls, 0);

      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final inside = await _startDrag(tester);
      await inside.moveBy(const Offset(0, 180));
      await inside.moveBy(const Offset(0, -80));
      await inside.up();
      await tester.pumpAndSettle();
      expect(endCalls, 0);

      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lastRow = find.text('行 39');
      final origin = tester.getTopLeft(lastRow);
      final pull = await _startDrag(tester, upward: true);
      await pull.moveBy(const Offset(0, -250));
      await tester.pump();
      expect(_indicator(tester).progress, 1);
      expect(origin.dy - tester.getTopLeft(lastRow).dy, closeTo(56, 1));
      expect(endCalls, 0);
      await pull.up();
      for (var frame = 0; frame < 50 && endCalls == 0; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump();
      await tester.pump(AppMotion.scrollChrome.duration);
      expect(topCalls, 0);
      expect(endCalls, 1);
      expect(_indicator(tester).animate, isTrue);
      expect(origin.dy - tester.getTopLeft(lastRow).dy, closeTo(44, 1));

      completion.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ChhersLoader), findsNothing);
      expect(tester.getTopLeft(lastRow), origin);
    });
  }

  testWidgets('a short list selects the refresh edge by drag direction', (
    tester,
  ) async {
    var topCalls = 0;
    var endCalls = 0;
    await tester.pumpWidget(
      _app(
        () async => topCalls++,
        onRefreshAtEnd: () async => endCalls++,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 1,
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(endCalls, 1);
    expect(topCalls, 0);
    await tester.drag(find.byType(ListView), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(topCalls, 1);
    expect(endCalls, 1);
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
