import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/search_entry_route.dart';
import 'package:chh_app/widgets/search_workspace.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/ui/app_button.dart';
import 'dart:math' as math;

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
  testWidgets('comment fades only paint and retain child layout and state', (
    tester,
  ) async {
    final opacity = AnimationController(vsync: tester, value: 0);
    var builds = 0;
    await tester.pumpWidget(
      app(
        ContentFade(
          opacity: opacity,
          background: AppTokens.light.bg,
          child: Builder(
            builder: (_) {
              builds++;
              return const SizedBox(height: 400, child: Text('existing reply'));
            },
          ),
        ),
      ),
    );
    final before = tester.getRect(find.text('existing reply'));
    opacity.value = .5;
    await tester.pump();
    expect(tester.getRect(find.text('existing reply')), before);
    expect(builds, 1);
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(FadeTransition), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    opacity.dispose();
  });

  testWidgets(
    'search arrival fades a cover without moving or compositing results',
    (tester) async {
      await tester.pumpWidget(
        app(
          SearchStateReveal(
            child: ListView.builder(
              itemCount: 1000,
              itemExtent: 80,
              itemBuilder: (_, i) => Text('result $i'),
            ),
          ),
        ),
      );
      final before = tester.getTopLeft(find.text('result 0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(find.text('result 0')), before);
      expect(
        find.descendant(
          of: find.byType(SearchStateReveal),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(find.text('result 999'), findsNothing);
      await tester.pump(const Duration(milliseconds: 91));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

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
      expect(
        find.descendant(
          of: find.byType(ExpressivePageReveal),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(scroll.offset, 400);
      expect(tester.state(find.byType(Scrollable)), same(state));
      update(() => reduced = true);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      update(() => revision++);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 151));
      expect(tester.binding.transientCallbackCount, 0);
      expect(scroll.offset, 400);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sliver arrival preserves geometry and does not rebuild rows', (
    tester,
  ) async {
    final revision = ValueNotifier(0);
    var builds = 0;
    final scroll = ScrollController();
    await tester.pumpWidget(
      app(
        ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (_, value, _) => CustomScrollView(
            controller: scroll,
            slivers: [
              ExpressivePageReveal(
                active: true,
                sliver: true,
                revision: value,
                child: SliverList.builder(
                  itemCount: 1000,
                  itemBuilder: (_, i) {
                    builds++;
                    return SizedBox(height: 80, child: Text('sliver row $i'));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    scroll.jumpTo(400);
    await tester.pump();
    final before = tester.getTopLeft(find.text('sliver row 6'));
    revision.value++;
    await tester.pump();
    final startBuilds = builds;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getTopLeft(find.text('sliver row 6')), before);
    expect(scroll.offset, 400);
    expect(builds, startBuilds);
    await tester.pump(const Duration(milliseconds: 91));
    expect(tester.binding.transientCallbackCount, 0);
    expect(builds, lessThan(1000));
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    revision.dispose();
  });

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

  testWidgets(
    'search reversal keeps its shared spring position while opening',
    (tester) async {
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
      final before = tester.getTopLeft(find.byKey(pageKey)).dx;
      expect(before, inExclusiveRange(0, 800));
      navigator.currentState!.pop();
      await tester.pump();
      final after = tester.getTopLeft(find.byKey(pageKey)).dx;
      expect(after, closeTo(before, .001));
      await tester.pumpAndSettle();
      expect(find.byKey(pageKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filled dark actions keep legible text contrast', (tester) async {
    await tester.pumpWidget(
      app(
        AppButton(label: '发送', onPressed: () {}),
        brightness: Brightness.dark,
      ),
    );
    final text = tester.widget<Text>(find.text('发送'));
    final tokens = AppTokens.of(tester.element(find.byType(AppButton)));
    // 主按钮 v2 是漆面渐变底,最浅端 btnTop,按它取最坏对比
    final foreground = text.style!.color!.computeLuminance();
    final background = tokens.btnTop.computeLuminance();
    final lighter = math.max(background, foreground);
    final darker = math.min(background, foreground);
    final ratio = (lighter + .05) / (darker + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
  });
}
