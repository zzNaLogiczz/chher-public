import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = ValueKey('first-content');

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: child!,
  ),
  home: child,
);

Widget _tab({
  ScrollController? controller,
  Future<void> Function()? onRefresh,
  List<Widget> actions = const [],
  GlobalKey? discussionAnchor,
}) => LacquerTabScaffold(
  title: '精选',
  header: const SizedBox(height: 80, child: Text('大标题')),
  controller: controller,
  onRefresh: onRefresh,
  actions: actions,
  discussionAnchor: discussionAnchor,
  compactAccessory: const Text('最新 / 热门'),
  slivers: [
    const SliverToBoxAdapter(child: SizedBox(key: _first, height: 400)),
    if (discussionAnchor != null)
      SliverToBoxAdapter(
        child: SizedBox(
          key: discussionAnchor,
          height: 60,
          child: const Text('讨论入口'),
        ),
      ),
    SliverFixedExtentList(
      itemExtent: 80,
      delegate: SliverChildBuilderDelegate(
        (_, i) => Text('本地内容 $i'),
        childCount: 100,
      ),
    ),
  ],
);

Future<void> _surface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<TestGesture> _pull(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(const Offset(160, 180));
  await gesture.moveBy(Offset(0, distance));
  await tester.pump();
  return gesture;
}

void main() {
  test('compact title ranges clamp independently', () {
    expect(CompactBarProgress.largeTitle(-.2), 1);
    expect(CompactBarProgress.largeTitle(0), 1);
    expect(CompactBarProgress.largeTitle(.225), closeTo(.5, 1e-9));
    expect(CompactBarProgress.largeTitle(.45), 0);
    expect(CompactBarProgress.background(.3), 0);
    expect(CompactBarProgress.background(.5), closeTo(.5, 1e-9));
    expect(CompactBarProgress.background(.7), closeTo(1, 1e-9));
    expect(CompactBarProgress.smallTitle(.6), 0);
    expect(CompactBarProgress.smallTitle(.8), closeTo(.5, 1e-9));
    expect(CompactBarProgress.smallTitle(1), 1);
    expect(CompactBarProgress.smallTitle(2), 1);
  });

  testWidgets('idle partial header keeps the released scroll position', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(_tab(controller: scroll)));
    await tester.pumpAndSettle();
    final collapse =
        tester.getTopLeft(find.byKey(_first)).dy +
        TabChromeTokens.seamOverlap -
        NavOverlay.barHeight;
    for (final fraction in [.35, .65]) {
      scroll.jumpTo(collapse * fraction);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(collapse * fraction, .01));
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final style in AppearanceStyle.values) {
    testWidgets('small held drag stays where released in $style', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light, style),
          home: _tab(controller: scroll),
        ),
      );
      await tester.pumpAndSettle();
      final collapse =
          tester.getTopLeft(find.byKey(_first)).dy +
          TabChromeTokens.seamOverlap -
          NavOverlay.barHeight;
      scroll.jumpTo(collapse * .4);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(250, 400));
      await gesture.moveBy(const Offset(0, 35));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 150));
      final released = scroll.offset;
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(released, .1));
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
  testWidgets(
    'compact title moves upward into discussion and downward on return',
    (tester) async {
      Widget title(bool discussion) => _app(
        Center(
          child: SizedBox(
            width: 300,
            child: SlidingCompactTitle(title: '精选', discussion: discussion),
          ),
        ),
      );
      double y(String title) => tester.getTopLeft(find.text(title)).dy;
      await tester.pumpWidget(title(false));
      await tester.pumpAndSettle();
      final initial = y('精选');
      expect(y('社区讨论'), greaterThan(initial));
      await tester.pumpWidget(title(true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(y('精选'), lessThan(initial));
      expect(y('社区讨论'), greaterThan(initial));
      await tester.pumpAndSettle();
      expect(y('社区讨论'), closeTo(initial, .01));
      await tester.pumpWidget(title(false));
      await tester.pump(const Duration(milliseconds: 50));
      expect(y('精选'), lessThan(initial));
      expect(y('社区讨论'), greaterThan(initial));
      await tester.pumpAndSettle();
      expect(y('精选'), closeTo(initial, .01));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'discussion anchor changes the compact title and search stays tappable',
    (tester) async {
      await _surface(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final discussion = GlobalKey();
      var searches = 0;
      await tester.pumpWidget(
        _app(
          _tab(
            controller: scroll,
            discussionAnchor: discussion,
            actions: [
              IconButton(
                tooltip: '搜索',
                onPressed: () => searches++,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byTooltip('搜索');
      final startY = tester.getTopLeft(search).dy;
      await tester.tap(search);
      final anchor =
          tester.getTopLeft(find.byKey(discussion)).dy - NavOverlay.barHeight;
      scroll.jumpTo(anchor + 20);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SlidingCompactTitle>(find.byType(SlidingCompactTitle))
            .discussion,
        isTrue,
      );
      expect(tester.getTopLeft(search).dy, lessThan(startY));
      final pinnedY = tester.getTopLeft(search).dy;
      await tester.tap(search);
      scroll.jumpTo(anchor + 500);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(search).dy, pinnedY);
      await tester.tap(search);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SlidingCompactTitle>(find.byType(SlidingCompactTitle))
            .discussion,
        isFalse,
      );
      expect(tester.getTopLeft(search).dy, startY);
      await tester.tap(search);
      expect(searches, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search follows viewport corrections in the same layout frame', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var correct = false;
    const action = ValueKey('search-action');
    await tester.pumpWidget(
      _app(
        LacquerTabScaffold(
          title: '精选',
          controller: scroll,
          header: const SizedBox(height: 100),
          actions: const [SizedBox(key: action, width: 44, height: 44)],
          slivers: [
            SliverLayoutBuilder(
              builder: (_, constraints) {
                if (correct) {
                  correct = false;
                  scroll.position.correctPixels(scroll.offset + 8);
                }
                return const SliverToBoxAdapter(child: SizedBox(height: 2000));
              },
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initial = tester.getTopLeft(find.byKey(action)).dy;
    correct = true;
    scroll.jumpTo(10);
    await tester.pump();
    expect(scroll.offset, 18);
    expect(tester.getTopLeft(find.byKey(action)).dy, initial - 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary scroll release never starts a refresh pull spring', (
    tester,
  ) async {
    await _surface(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const search = ValueKey('pinned-search');
    var refreshes = 0;
    await tester.pumpWidget(
      _app(
        _tab(
          controller: scroll,
          onRefresh: () async => refreshes++,
          actions: const [SizedBox(key: search, width: 44, height: 44)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(1000);
    await tester.pumpAndSettle();
    final pinnedY = tester.getTopLeft(find.byKey(search)).dy;
    final row = find.text('本地内容 10');
    final contentY = tester.getTopLeft(row).dy + scroll.offset;
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 150),
      1500,
    );
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, greaterThan(500));
      expect(tester.getTopLeft(find.byKey(search)).dy, pinnedY);
      expect(tester.getTopLeft(row).dy + scroll.offset, closeTo(contentY, .01));
    }
    await tester.pumpAndSettle();
    expect(refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull below threshold returns without requesting data', (
    tester,
  ) async {
    await _surface(tester);
    var requests = 0;
    await tester.pumpWidget(_app(_tab(onRefresh: () async => requests++)));
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byKey(_first));
    final gesture = await _pull(tester, 60);
    expect(tester.getTopLeft(find.byKey(_first)).dy, greaterThan(origin.dy));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.getTopLeft(find.byKey(_first)).dy, closeTo(origin.dy, .01));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('grabbing a returning pull keeps its position and settles', (
    tester,
  ) async {
    await _surface(tester);
    var refreshes = 0;
    await tester.pumpWidget(_app(_tab(onRefresh: () async => refreshes++)));
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byKey(_first)).dy;
    final pull = await _pull(tester, 100);
    await pull.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    final returning = tester.getTopLeft(find.byKey(_first)).dy;
    expect(returning, greaterThan(origin));
    final grabbed = await tester.startGesture(const Offset(160, 240));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.getTopLeft(find.byKey(_first)).dy, returning);
    await grabbed.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_first)).dy, closeTo(origin, .01));
    expect(refreshes, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'refresh holds until completion, one haptic per pull reduced=$reduced',
      (tester) async {
        await _surface(tester);
        final haptics = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final done = Completer<void>();
        var requests = 0;
        await tester.pumpWidget(
          _app(
            _tab(
              onRefresh: () {
                requests++;
                return done.future;
              },
            ),
            reduced: reduced,
          ),
        );
        await tester.pumpAndSettle();
        final origin = tester.getTopLeft(find.byKey(_first)).dy;
        final gesture = await _pull(tester, 220);
        await gesture.moveBy(const Offset(0, -120));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 120));
        await tester.pump();
        expect(haptics.map((e) => e.arguments), [
          'HapticFeedbackType.selectionClick',
        ]);
        expect(requests, 0);
        await gesture.up();
        await tester.pump();
        // Let the loader's viewport check start the static wordmark entrance.
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(requests, 1);
        expect(
          tester.getTopLeft(find.byKey(_first)).dy - origin,
          closeTo(TabChromeTokens.refreshHold, .01),
        );
        if (reduced) expect(tester.binding.transientCallbackCount, 0);
        done.complete();
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(_first)).dy, closeTo(origin, .01));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('cancelled armed pull does not turn a later tap into refresh', (
    tester,
  ) async {
    await _surface(tester);
    var requests = 0;
    await tester.pumpWidget(_app(_tab(onRefresh: () async => requests++)));
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byKey(_first)).dy;
    final gesture = await _pull(tester, 220);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.getTopLeft(find.byKey(_first)).dy, closeTo(origin, .01));
    await tester.tapAt(const Offset(160, 180));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('failed refresh preserves content and permits another pull', (
    tester,
  ) async {
    await _surface(tester);
    var requests = 0;
    await tester.pumpWidget(
      _app(
        _tab(
          onRefresh: () async {
            requests++;
            if (requests == 1) throw StateError('offline fixture');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byKey(_first)).dy;
    await (await _pull(tester, 220)).up();
    await tester.pump();
    expect(find.text('刷新失败，请重试'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_first)).dy, closeTo(origin, .01));
    await (await _pull(tester, 220)).up();
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching tabs preserves feed offset and reselecting feed springs to top',
    (tester) async {
      await _surface(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var builds = 0;
      await tester.pumpWidget(
        _app(
          HomePage(
            initialiseSession: () async {},
            screenBuilders: {
              AppDestination.feed: (_) {
                builds++;
                return _tab(controller: scroll);
              },
              AppDestination.forums: (_) => const Scaffold(body: Text('本地版块')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder tab(String text) => find.descendant(
        of: find.byType(AppBottomNavigation),
        matching: find.text(text),
      );
      scroll.jumpTo(3000);
      await tester.pumpAndSettle();
      await tester.tap(tab('版块'));
      await tester.pumpAndSettle();
      await tester.tap(tab('精选'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 3000);
      expect(builds, 1);
      await tester.tap(tab('精选'));
      expect(scroll.offset, closeTo(scroll.position.viewportDimension, .01));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(builds, 1);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
