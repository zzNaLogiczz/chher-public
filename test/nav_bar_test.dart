import 'dart:io';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/large_title_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget home) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: home);

Widget rows() => ListView.builder(
  itemCount: 100,
  itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row$i')),
);

double opacityOf(WidgetTester tester, Key key) =>
    tester.widget<Opacity>(find.byKey(key)).opacity;

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));

  @override
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async =>
      const [];

  @override
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async => ThreadListPage(
    threads: [
      for (var i = 0; i < 30; i++)
        ThreadSummary(
          tid: 9000 + i,
          title: '本地主题 $i',
          author: '读者',
          replies: 2,
          views: 10,
        ),
    ],
    page: const PageInfo(current: 1, hasNext: false),
  );
}

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets(
      'forum inline title avoids all navigation controls at ${width}dp',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          app(
            ForumThreadsPage(
              fid: 80,
              title: '自由水世界2024',
              repository: _Forums(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<ChromeGroup>(find.byType(ChromeGroup)).items,
          hasLength(4),
        );

        final outer = tester
            .state<NestedScrollViewState>(find.byType(NestedScrollView))
            .outerController;
        outer.jumpTo(outer.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(opacityOf(tester, NavOverlay.inlineTitleKey), 1);
        final title = tester.getRect(find.byKey(NavOverlay.inlineTitleKey));
        final actions = tester.getRect(find.byType(ChromeGroup));
        final back = tester.getRect(find.byTooltip('返回'));
        expect(title.width, greaterThan(0));
        expect(title.overlaps(actions), isFalse);
        expect(title.overlaps(back), isFalse);
        expect(back.left, closeTo(10, 0.01));
        expect(actions.right, closeTo(width - 10, 0.01));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('thread inline title remains centered between single circles', (
    tester,
  ) async {
    const width = 360.0;
    await tester.binding.setSurfaceSize(const Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        ThreadDetailPage(
          tid: 123,
          title: '帖子标题',
          loadPage: (_, _, _) async => ThreadDetail(
            tid: 123,
            fid: 80,
            title: '帖子标题',
            posts: [
              Post(
                pid: 1,
                floor: 1,
                author: '作者',
                timeRaw: '2026-10-30',
                content: [
                  for (var i = 0; i < 50; i++) TextBlock('本地正文内容第 $i 段'),
                ],
              ),
            ],
            page: const PageInfo(current: 1, hasNext: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nav = find.byType(NavOverlay);
    expect(
      find.descendant(of: nav, matching: find.byType(ChromeButton)),
      findsNWidgets(2),
    );
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(200);
    await tester.pumpAndSettle();
    expect(opacityOf(tester, NavOverlay.inlineTitleKey), 1);
    final title = tester.getRect(find.byKey(NavOverlay.inlineTitleKey));
    expect(title.center.dx, closeTo(width / 2, 1));
    expect(title.overlaps(tester.getRect(find.byTooltip('返回'))), isFalse);
    expect(title.overlaps(tester.getRect(find.byTooltip('查看原页面'))), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'root destinations never show back even when the navigator can pop',
    (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const AppShell(
                title: '消息',
                current: AppDestination.messages,
                body: SizedBox(),
              ),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回'), findsNothing);
    },
  );

  testWidgets('pushed pages show back by default', (tester) async {
    await tester.pumpWidget(app(LargeTitleScaffold(title: '设置', body: rows())));
    expect(find.byTooltip('返回'), findsOneWidget);
  });

  testWidgets('grouped surface paints the grouped background', (tester) async {
    await tester.pumpWidget(
      app(
        LargeTitleScaffold(
          title: '我的',
          showBack: false,
          surface: AppSurface.grouped,
          body: rows(),
        ),
      ),
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppTokens.light.grouped,
    );
  });

  testWidgets('edge fade is clear at rest and opaque after 12dp', (
    tester,
  ) async {
    await tester.pumpWidget(app(LargeTitleScaffold(title: '设置', body: rows())));
    expect(opacityOf(tester, NavOverlay.edgeKey), 0);

    final outer = tester
        .state<NestedScrollViewState>(find.byType(NestedScrollView))
        .outerController;
    outer.jumpTo(6);
    await tester.pump();
    expect(opacityOf(tester, NavOverlay.edgeKey), closeTo(0.5, 0.01));

    outer.jumpTo(30);
    await tester.pump();
    expect(opacityOf(tester, NavOverlay.edgeKey), 1);
  });

  testWidgets('inline title appears once the large title scrolls away', (
    tester,
  ) async {
    await tester.pumpWidget(app(LargeTitleScaffold(title: '设置', body: rows())));
    expect(opacityOf(tester, NavOverlay.inlineTitleKey), 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row3')),
    );
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, NavOverlay.inlineTitleKey), 1);

    await gesture.moveBy(const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, NavOverlay.inlineTitleKey), 0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('title accessory sits on the large title row', (tester) async {
    await tester.pumpWidget(
      app(
        LargeTitleScaffold(
          title: '精选',
          showBack: false,
          titleAccessory: const SizedBox(
            key: ValueKey('accessory'),
            width: 44,
            height: 44,
          ),
          body: rows(),
        ),
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('accessory'))).dy,
      closeTo(tester.getCenter(find.text('精选').first).dy, 2),
    );
  });

  testWidgets('messages badge renders on the bottom navigation', (
    tester,
  ) async {
    Widget nav(int badge) => app(
      Scaffold(
        bottomNavigationBar: AppBottomNavigation(
          current: AppDestination.feed,
          onNavigate: (_) {},
          messagesBadge: badge,
        ),
      ),
    );
    await tester.pumpWidget(nav(3));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(nav(0));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('shell renders no notification bell', (tester) async {
    await tester.pumpWidget(
      app(
        const AppShell(
          title: '版块',
          current: AppDestination.forums,
          body: SizedBox(),
        ),
      ),
    );
    expect(find.byTooltip('消息'), findsNothing);
    expect(
      File('lib/pages/feed_page.dart').readAsStringSync(),
      isNot(contains('MessagesAction')),
    );
  });
}
