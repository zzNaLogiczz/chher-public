import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _header = ValueKey('fixture-header');
const _content = ValueKey('fixture-content');

Widget _app({
  required ScrollController scroll,
  required Brightness brightness,
  bool compact = true,
  bool reduced = false,
  Future<void> Function()? refresh,
}) => MaterialApp(
  theme: buildAppTheme(brightness, AppearanceStyle.misty),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.only(top: 44),
      disableAnimations: reduced,
    ),
    child: child!,
  ),
  home: LacquerTabScaffold(
    title: '本地页头',
    mistyCompact: compact,
    controller: scroll,
    contentOnPaper: true,
    header: const SizedBox(key: _header, height: 100),
    onRefresh: refresh,
    slivers: const [
      SliverToBoxAdapter(child: SizedBox(key: _content, height: 1200)),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    for (final reduced in [false, true]) {
      testWidgets(
        'misty partial scroll stays and refresh settles without tickers $brightness reduced=$reduced',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          var requests = 0;
          final done = Completer<void>();
          await tester.pumpWidget(
            _app(
              scroll: scroll,
              brightness: brightness,
              reduced: reduced,
              refresh: () {
                requests++;
                return done.future;
              },
            ),
          );
          await tester.pumpAndSettle();
          final origin = tester.getTopLeft(find.byKey(_content)).dy;
          final collapse =
              tester.getBottomLeft(find.byKey(_header)).dy -
              44 -
              NavOverlay.barHeight;
          expect(collapse, 56);
          for (final fraction in [.35, .65]) {
            scroll.jumpTo(collapse * fraction);
            await tester.pumpAndSettle();
            expect(scroll.offset, closeTo(collapse * fraction, .01));
          }
          scroll.jumpTo(0);
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(const Offset(160, 240));
          await gesture.moveBy(const Offset(0, 220));
          await tester.pump();
          final expectedPull =
              TabChromeTokens.maxPull *
              220 /
              (TabChromeTokens.pullResistance + 220);
          expect(
            tester.getTopLeft(find.byKey(_content)).dy - origin,
            closeTo(expectedPull, .01),
          );
          expect(requests, 0);
          await gesture.up();
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(requests, 1);
          expect(
            tester.getTopLeft(find.byKey(_content)).dy - origin,
            closeTo(TabChromeTokens.refreshHold, .01),
          );
          done.complete();
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(find.byKey(_content)).dy,
            closeTo(origin, .01),
          );
          expect(scroll.offset, 0);
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'misty featured-style mast remains unchanged when not opted in $brightness',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          _app(scroll: scroll, brightness: brightness, compact: false),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(_header)).dy,
          44 + TabChromeTokens.headerTop,
        );
        expect(
          tester.getTopLeft(find.byKey(_content)).dy,
          44 +
              TabChromeTokens.headerTop +
              100 +
              TabChromeTokens.headerBottom +
              TabChromeTokens.seamOverlap +
              TabChromeTokens.paperTopInset,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
