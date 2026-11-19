import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/widgets/chhers_refresh_indicator.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post(int floor, {int blocks = 1, bool known = true}) => Post(
  pid: floor,
  floor: floor,
  floorIsKnown: known,
  author: '本地样例',
  timeRaw: '',
  content: [for (var i = 0; i < blocks; i++) TextBlock('第 $floor 楼，第 $i 段正文')],
);

Future<void> _show(WidgetTester tester, ThreadDetailPage page) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light, AppearanceStyle.cinnabar),
      home: page,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

double _progress(WidgetTester tester) =>
    tester.widget<NavOverlay>(find.byType(NavOverlay)).readingProgress!.value;

void main() {
  for (final appendedCount in <int?>[null, 199]) {
    testWidgets(
      'append keeps visible progress with reply count $appendedCount',
      (tester) async {
        final next = Completer<ThreadDetail>();
        await _show(
          tester,
          ThreadDetailPage(
            tid: 1,
            title: '长帖',
            loadPage: (page, _, _) async => page == 1
                ? ThreadDetail(
                    tid: 1,
                    title: '长帖',
                    replyCount: 99,
                    posts: [_post(1, blocks: 100)],
                    page: const PageInfo(current: 1, hasNext: true),
                  )
                : next.future,
          ),
        );
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        position.jumpTo(600);
        await tester.pump();
        final before = _progress(tester);
        expect(before, greaterThan(0));
        expect(before, lessThan(.01));
        next.complete(
          ThreadDetail(
            tid: 1,
            title: '长帖',
            replyCount: appendedCount,
            posts: [for (var floor = 2; floor <= 30; floor++) _post(floor)],
            page: const PageInfo(current: 2, hasNext: false),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(_progress(tester), closeTo(before, .000001));
        position.jumpTo(1200);
        await tester.pump();
        expect(_progress(tester), greaterThan(before));
        position.jumpTo(300);
        await tester.pump();
        expect(_progress(tester), lessThan(before));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a middle-page landing uses its real floor and global total', (
    tester,
  ) async {
    await _show(
      tester,
      ThreadDetailPage(
        tid: 1,
        initialPage: 5,
        title: '中段',
        preloadPages: 1,
        loadPage: (_, _, _) async => ThreadDetail(
          tid: 1,
          title: '中段',
          replyCount: 99,
          posts: [_post(41, blocks: 40), _post(42)],
          page: const PageInfo(current: 5, hasNext: true),
        ),
      ),
    );
    expect(_progress(tester), closeTo(.4, .001));
  });

  for (final hasNext in [false, true]) {
    testWidgets('bottom is complete only on the real last page: $hasNext', (
      tester,
    ) async {
      await _show(
        tester,
        ThreadDetailPage(
          tid: 1,
          title: '原楼层',
          initialThreaded: false,
          preloadPages: 1,
          loadPage: (_, _, _) async => ThreadDetail(
            tid: 1,
            title: '原楼层',
            replyCount: 9,
            posts: [for (var floor = 1; floor <= 10; floor++) _post(floor)],
            page: PageInfo(current: 1, hasNext: hasNext),
          ),
        ),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      for (var i = 0; i < 3; i++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
      }
      expect(_progress(tester), hasNext ? lessThan(1) : 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('prepended reverse sliver follows the top visible floor upward', (
    tester,
  ) async {
    await _show(
      tester,
      ThreadDetailPage(
        tid: 1,
        title: '补前文',
        initialPage: 3,
        initialThreaded: false,
        preloadPages: 1,
        loadPage: (page, _, _) async => ThreadDetail(
          tid: 1,
          title: '补前文',
          replyCount: 99,
          posts: [
            for (
              var floor = page == 3 ? 21 : 11;
              floor <= (page == 3 ? 27 : 20);
              floor++
            )
              _post(floor),
          ],
          page: PageInfo(current: page, hasNext: false),
        ),
      ),
    );
    final before = find.text('查看前面的回复');
    await tester.ensureVisible(before);
    await tester.pumpAndSettle();
    await tester.tap(before);
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    var previous = _progress(tester);
    final initial = previous;
    var checked = 0;
    for (var i = 0; i < 8; i++) {
      position.jumpTo(
        (position.pixels - 120).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
      final cards = find
          .byType(PostCard)
          .evaluate()
          .map((element) {
            final finder = find.byWidget(element.widget);
            return (
              post: (element.widget as PostCard).post,
              rect: tester.getRect(finder),
            );
          })
          .where(
            (row) =>
                row.rect.bottom > NavOverlay.barHeight &&
                row.rect.top <= NavOverlay.barHeight,
          )
          .toList();
      if (cards.isNotEmpty) {
        final floor = cards.single.post.floor;
        expect(
          _progress(tester),
          inInclusiveRange((floor - 1) / 100, floor / 100),
          reason: 'visible floor $floor',
        );
        checked++;
      }
      expect(_progress(tester), lessThanOrEqualTo(previous));
      previous = _progress(tester);
    }
    expect(checked, greaterThan(3));
    expect(previous, lessThan(initial - .03));
  });

  testWidgets(
    'jump to comments after a lone opening keeps its completed share',
    (tester) async {
      await _show(
        tester,
        ThreadDetailPage(
          tid: 1,
          title: '仅首楼已加载',
          preloadPages: 1,
          loadPage: (_, _, _) async => ThreadDetail(
            tid: 1,
            title: '仅首楼已加载',
            replyCount: 99,
            posts: [_post(1, blocks: 100)],
            page: const PageInfo(current: 1, hasNext: true),
          ),
        ),
      );
      tester.view.physicalSize = const Size(390, 250);
      await tester.pumpAndSettle();
      tester.widget<ReadingBar>(find.byType(ReadingBar)).onShowComments();
      await tester.pumpAndSettle();
      final heading = find.byKey(const ValueKey('comments-heading'));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(
        position.pixels +
            tester.getTopLeft(heading).dy -
            NavOverlay.barHeight +
            10,
      );
      await tester.pump();
      final rect = tester.getRect(heading);
      expect(rect.top, lessThan(NavOverlay.barHeight));
      expect(rect.bottom, greaterThan(NavOverlay.barHeight));
      expect(_progress(tester), closeTo(.01, .0001));
    },
  );

  testWidgets('refresh without a total clears the previous progress', (
    tester,
  ) async {
    await _show(
      tester,
      ThreadDetailPage(
        tid: 1,
        title: '刷新',
        preloadPages: 1,
        loadPage: (_, _, refresh) async => ThreadDetail(
          tid: 1,
          title: '刷新',
          replyCount: refresh ? null : 99,
          posts: [_post(1, blocks: 100)],
          page: const PageInfo(current: 1, hasNext: true),
        ),
      ),
    );
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(600);
    await tester.pump();
    expect(_progress(tester), greaterThan(0));
    await tester
        .widget<ChhersRefreshIndicator>(find.byType(ChhersRefreshIndicator))
        .onRefresh();
    await tester.pump();
    await tester.pump();
    expect(_progress(tester), 0);
  });

  testWidgets('unknown totals and local page ordinals do not invent progress', (
    tester,
  ) async {
    await _show(
      tester,
      ThreadDetailPage(
        tid: 1,
        initialPage: 5,
        title: '未知楼层',
        preloadPages: 1,
        loadPage: (_, _, _) async => ThreadDetail(
          tid: 1,
          title: '未知楼层',
          posts: [_post(1, blocks: 40, known: false)],
          page: const PageInfo(current: 5, hasNext: true),
        ),
      ),
    );
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(600);
    await tester.pump();
    expect(_progress(tester), 0);
  });
}
