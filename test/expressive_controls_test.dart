import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/search_entry_route.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildAppTheme(brightness),
      home: Scaffold(body: child),
    );

double scaleOf(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(PressScale),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .storage[0];

void main() {
  testWidgets(
    'content transitions preserve mounted state and honor reduced motion immediately',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var revision = 0;
      var reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: ExpressivePageReveal(
                  active: true,
                  revision: revision,
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: 100,
                    itemBuilder: (_, index) =>
                        SizedBox(height: 80, child: Text('row$index')),
                  ),
                ),
              );
            },
          ),
        ),
      );
      scroll.jumpTo(400);
      await tester.pump();
      final state = tester.state(find.byType(Scrollable));
      update(() => revision++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final opacity = find
          .descendant(
            of: find.byType(ExpressivePageReveal),
            matching: find.byType(Opacity),
          )
          .first;
      expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
      expect(scroll.offset, 400);
      expect(tester.state(find.byType(Scrollable)), same(state));
      update(() => reduced = true);
      await tester.pump();
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      update(() => revision++);
      await tester.pump();
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(scroll.offset, 400);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collapsing controls animate their space and disable interaction immediately',
    (tester) async {
      var visible = true;
      var taps = 0;
      late StateSetter update;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Center(
                child: ExpressiveVisibility(
                  visible: visible,
                  axis: Axis.horizontal,
                  child: SizedBox(
                    width: 100,
                    height: 44,
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('清除'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      update(() => visible = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final control = find.byType(ExpressiveVisibility);
      expect(tester.getSize(control).width, inExclusiveRange(0, 100));
      await tester.tapAt(tester.getCenter(control));
      expect(taps, 0);
      await tester.pumpAndSettle();
      expect(tester.getSize(control).width, 0);
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(tester.getSize(control).width, 100);
      await tester.tap(find.text('清除'));
      expect(taps, 1);
    },
  );

  testWidgets('press responds before release and a drag cancels activation', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        Center(
          child: PressScale(
            onTap: () => taps++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    final touch = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(scaleOf(tester), lessThan(1));
    await touch.moveBy(const Offset(0, 70));
    await touch.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(scaleOf(tester), 1);
    await tester.tap(find.byType(PressScale));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a control disabled during a press releases its scale', (
    tester,
  ) async {
    var enabled = true;
    late StateSetter update;
    var taps = 0;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return Center(
              child: PressScale(
                onTap: enabled ? () => taps++ : null,
                child: const SizedBox(width: 100, height: 100),
              ),
            );
          },
        ),
      ),
    );
    final touch = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(scaleOf(tester), lessThan(1));
    update(() => enabled = false);
    await tester.pump();
    await touch.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
    expect(taps, 0);
  });

  testWidgets('navigation selection moves through intermediate positions', (
    tester,
  ) async {
    var current = AppDestination.feed;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (_, setState) => Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomNavigation(
              current: current,
              onNavigate: (value) => setState(() => current = value),
            ),
          ),
        ),
      ),
    );
    final backdrop = find
        .descendant(
          of: find.byType(AppBottomNavigation),
          matching: find.byType(Positioned),
        )
        .first;
    final start = tester.widget<Positioned>(backdrop).left!;
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final intermediate = tester.widget<Positioned>(backdrop).left!;
    await tester.pumpAndSettle();
    final end = tester.widget<Positioned>(backdrop).left!;
    expect(intermediate, greaterThan(start));
    expect(intermediate, lessThan(end));
    expect(current, AppDestination.me);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search reversal keeps opacity continuous while opening', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    const pageKey = ValueKey('search-route-content');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: Text('首页')),
      ),
    );
    navigator.currentState!.push(
      SearchEntryRoute(
        builder: (_) => const Scaffold(key: pageKey, body: Text('搜索内容')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final fade = find
        .ancestor(
          of: find.byKey(pageKey),
          matching: find.byType(FadeTransition),
        )
        .first;
    final before = tester.widget<FadeTransition>(fade).opacity.value;
    expect(before, inExclusiveRange(0, 1));
    navigator.currentState!.pop();
    await tester.pump();
    final after = tester.widget<FadeTransition>(fade).opacity.value;
    expect(after, closeTo(before, .001));
    await tester.pumpAndSettle();
    expect(find.byKey(pageKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filled dark actions keep legible text contrast', (tester) async {
    await tester.pumpWidget(
      app(
        AppButton(label: '发送', onPressed: () {}),
        brightness: Brightness.dark,
      ),
    );
    final text = tester.widget<Text>(find.text('发送'));
    final tokens = AppTokens.of(tester.element(find.byType(AppButton)));
    final foreground = text.style!.color!.computeLuminance();
    final background = tokens.accent.computeLuminance();
    final ratio = (background + .05) / (foreground + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
  });
}
