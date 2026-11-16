import 'dart:async';

import 'package:chh_app/design/scroll_behavior.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/lac_scaffold.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:chh_app/widgets/large_title_scaffold.dart';
import 'package:chh_app/widgets/paged_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget child, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  scrollBehavior: const AppScrollBehavior(),
  theme: buildAppTheme(
    brightness,
    style,
  ).copyWith(platform: TargetPlatform.android),
  home: child,
);

void _expectNoIndicator() {
  expect(find.byType(StretchingOverscrollIndicator), findsNothing);
  expect(find.byType(GlowingOverscrollIndicator), findsNothing);
}

void _expectNoScale(WidgetTester tester, Finder row) {
  // Include render transforms as well as widgets: layout size alone would miss
  // the Material 3 stretch applied above the viewport.
  final matrix = tester.renderObject(row).getTransformTo(null);
  expect(matrix.entry(0, 0), closeTo(1, 1e-9));
  expect(matrix.entry(1, 1), closeTo(1, 1e-9));
  for (final transform in tester.widgetList<Transform>(
    find.ancestor(of: row, matching: find.byType(Transform)),
  )) {
    expect(transform.transform.entry(0, 0), closeTo(1, 1e-9));
    expect(transform.transform.entry(1, 1), closeTo(1, 1e-9));
  }
}

Future<TestGesture> _pull(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(tester.getCenter(target));
  for (var i = 0; i < 5; i++) {
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Android list stays clamped without scaling $style $brightness',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: ListView.builder(
                  controller: scroll,
                  itemExtent: 60,
                  itemCount: 40,
                  itemBuilder: (_, i) => SizedBox(key: ValueKey('row-$i')),
                ),
              ),
              style: style,
              brightness: brightness,
            ),
          );
          await tester.pumpAndSettle();
          expect(scroll.position.physics, isA<ClampingScrollPhysics>());
          final rows = [
            find.byKey(const ValueKey('row-0')),
            find.byKey(const ValueKey('row-5')),
          ];
          final origins = rows.map(tester.getTopLeft).toList();
          final gesture = await _pull(tester, rows.first);
          _expectNoIndicator();
          expect(scroll.offset, 0);
          for (var i = 0; i < rows.length; i++) {
            _expectNoScale(tester, rows[i]);
            expect(tester.getTopLeft(rows[i]), origins[i]);
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(scroll.offset, 0);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );

      testWidgets(
        'custom header pull only translates content $style $brightness',
        (tester) async {
          final done = Completer<void>();
          var refreshes = 0;
          final first = find.byKey(const ValueKey('content-0'));
          final second = find.byKey(const ValueKey('content-1'));
          await tester.pumpWidget(
            _app(
              LacquerTabScaffold(
                title: '本地页头',
                header: const SizedBox(height: 80),
                onRefresh: () {
                  refreshes++;
                  return done.future;
                },
                slivers: [
                  SliverFixedExtentList(
                    itemExtent: 80,
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => SizedBox(key: ValueKey('content-$i')),
                      childCount: 30,
                    ),
                  ),
                ],
              ),
              style: style,
              brightness: brightness,
            ),
          );
          await tester.pumpAndSettle();
          final origin = tester.getTopLeft(first);
          final spacing = tester.getTopLeft(second).dy - origin.dy;
          final gesture = await _pull(tester, first);
          expect(tester.getTopLeft(first).dy, greaterThan(origin.dy));
          expect(
            tester.getTopLeft(second).dy - tester.getTopLeft(first).dy,
            spacing,
          );
          _expectNoScale(tester, first);
          _expectNoScale(tester, second);
          _expectNoIndicator();
          expect(refreshes, 0);
          await gesture.up();
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(refreshes, 1);
          expect(
            tester.getTopLeft(first).dy - origin.dy,
            closeTo(TabChromeTokens.refreshHold, .01),
          );
          done.complete();
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(first).dy, closeTo(origin.dy, .01));
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final shell in ['plain', 'large-title', 'lac']) {
    for (final count in [1, 40]) {
      testWidgets(
        'fake refresh keeps its spinner and content $shell rows=$count',
        (tester) async {
          final done = Completer<Paged<int>>();
          final calls = <(int, bool)>[];
          final result = Paged(
            items: List.generate(count, (i) => i),
            page: const PageInfo(current: 1, hasNext: false),
          );
          final list = PagedList<int>(
            loader: (page, {bool refresh = false}) async {
              calls.add((page, refresh));
              return refresh ? done.future : result;
            },
            itemBuilder: (_, i) => SizedBox(
              height: 60,
              key: ValueKey('item-$i'),
              child: Text('本地条目 $i'),
            ),
          );
          await tester.pumpWidget(
            _app(switch (shell) {
              'large-title' => LargeTitleScaffold(title: '本地列表', body: list),
              'lac' => LacScaffold(title: '本地列表', body: list),
              _ => Scaffold(body: list),
            }),
          );
          await tester.pumpAndSettle();
          final first = find.byKey(const ValueKey('item-0'));
          if (shell != 'plain' && count > 1) {
            // Exercise the real nested outer/inner controllers before refreshing.
            final nested = tester.state<NestedScrollViewState>(
              find.byType(NestedScrollView),
            );
            await tester.drag(find.byType(ListView), const Offset(0, -400));
            await tester.pumpAndSettle();
            expect(nested.outerController.offset, greaterThan(0));
            expect(nested.innerController.offset, greaterThan(0));
            await tester.drag(find.byType(ListView), const Offset(0, 400));
            await tester.pumpAndSettle();
            nested.innerController.jumpTo(0);
            nested.outerController.jumpTo(0);
            await tester.pumpAndSettle();
          }
          final gesture = await _pull(tester, first);
          _expectNoIndicator();
          _expectNoScale(tester, first);
          expect(calls, [(1, false)]);
          await gesture.up();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(calls, [(1, false), (1, true)]);
          expect(find.byType(RefreshProgressIndicator), findsOneWidget);
          expect(first, findsOneWidget);
          done.complete(result);
          await tester.pumpAndSettle();
          expect(find.byType(RefreshProgressIndicator), findsNothing);
          expect(first, findsOneWidget);
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
