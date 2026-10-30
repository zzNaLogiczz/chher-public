import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/ui/favorite_action.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post(int floor, {String? uid}) => Post(
  pid: 1000 + floor,
  floor: floor,
  author: '作者 $floor',
  authorUid: uid ?? '$floor',
  timeRaw: '2026-10-26',
  content: [TextBlock(List.filled(22, '第 $floor 层的真实阅读内容。').join('\n'))],
);

ThreadDetail _page(int page, {bool next = false, List<Post>? posts}) =>
    ThreadDetail(
      tid: 123,
      fid: 290,
      title: '连续讨论',
      posts: posts ?? [for (var n = 1; n <= 3; n++) _post((page - 1) * 3 + n)],
      page: PageInfo(current: page, hasNext: next),
    );

Future<void> _pump(WidgetTester tester, ThreadDetailPage page) async {
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(Brightness.light), home: page),
  );
  await tester.pumpAndSettle();
}

Future<void> _bottom(WidgetTester tester) async {
  final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
  // 懒列表的初次 maxScrollExtent 是估计值，继续布局直到抵达真实尾部。
  for (var n = 0; n < 8; n++) {
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    if (scroll.position.extentAfter < 1) break;
  }
}

Future<void> tapViewMode(WidgetTester tester, String label) async {
  final segment = find.descendant(
    of: find.byType(AppSegmented<ThreadViewMode>),
    matching: find.text(label),
  );
  await tester.ensureVisible(segment);
  await tester.pump();
  await tester.tap(segment);
}

Future<ThreadViewMode> currentViewMode(WidgetTester tester) async {
  final segmented = find.byType(AppSegmented<ThreadViewMode>);
  await tester.scrollUntilVisible(
    segmented,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  return tester.widget<AppSegmented<ThreadViewMode>>(segmented).value;
}

void main() {
  for (final title in ['', '链接中的旧标题']) {
    testWidgets('收藏使用已加载的帖子标题,入口标题为「$title」', (tester) async {
      await _pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: title,
          loadPage: (_, _, _) async => _page(1),
        ),
      );
      final action = tester.widget<FavoriteActionBuilder>(
        find.byType(FavoriteActionBuilder),
      );
      expect(action.target.title, '连续讨论');
    });
  }

  testWidgets('scroll appends the next page and suppresses duplicate pids', (
    tester,
  ) async {
    final reads = <int>[];
    await _pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '连续讨论',
        loadPage: (page, _, _) async {
          reads.add(page);
          return page == 1
              ? _page(1, next: true)
              : _page(2, posts: [_post(3), _post(4)]);
        },
      ),
    );
    expect(reads, [1]);
    await _bottom(tester);
    expect(reads, [1, 2]);
    await _bottom(tester);
    expect(find.byKey(const ValueKey('post-1004')), findsOneWidget);
    final visibleIds = tester
        .widgetList<PostCard>(find.byType(PostCard))
        .map((card) => card.post.pid)
        .toList();
    expect(visibleIds.toSet().length, visibleIds.length);
    expect(find.text('第 1 页'), findsNothing);
  });

  testWidgets('append failure keeps content and retries only after a tap', (
    tester,
  ) async {
    final reads = <int>[];
    var failures = 0;
    await _pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '连续讨论',
        loadPage: (page, _, _) async {
          reads.add(page);
          if (page == 1) return _page(1, next: true);
          if (failures++ == 0) throw StateError('offline');
          return _page(2);
        },
      ),
    );
    await _bottom(tester);
    expect(reads, [1, 2]);
    expect(find.text('后面的讨论暂时没有加载出来'), findsOneWidget);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    await _bottom(tester);
    expect(reads, [1, 2]);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(reads, [1, 2, 2]);
    expect(find.text('后面的讨论暂时没有加载出来'), findsNothing);
  });

  testWidgets('silent page-one fallback terminates instead of looping', (
    tester,
  ) async {
    final reads = <int>[];
    await _pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '连续讨论',
        loadPage: (page, _, _) async {
          reads.add(page);
          return _page(page, next: true, posts: [_post(1), _post(2), _post(3)]);
        },
      ),
    );
    await _bottom(tester);
    await _bottom(tester);
    expect(reads, [1, 2]);
    expect(find.text('已读到这里'), findsOneWidget);
  });

  testWidgets(
    'notification follows its URL once and continues from response page',
    (tester) async {
      final gotos = <String>[];
      final reads = <int>[];
      const targetUrl =
          'https://www.chiphell.com/forum.php?mod=redirect&pid=1011';
      await _pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '通知进入',
          initialPage: 2,
          gotoUrl: targetUrl,
          focusPid: 1011,
          loadGoto: (url) async {
            gotos.add(url);
            return _page(4, next: true);
          },
          loadPage: (page, _, _) async {
            reads.add(page);
            return _page(page);
          },
        ),
      );
      expect(gotos, [targetUrl]);
      // Compact comments may reach the prefetch threshold during focus scroll.
      expect(reads, everyElement(5));
      expect(reads.length, lessThanOrEqualTo(1));
      expect(find.byType(PostCard), findsWidgets);
      await _bottom(tester);
      expect(reads, [5]);
      expect(gotos, hasLength(1));
    },
  );

  testWidgets(
    'author filter from a middle-page entry uses the actual opening author',
    (tester) async {
      final reads = <(int, String?)>[];
      await _pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '中段进入',
          initialPage: 4,
          loadPage: (page, author, _) async {
            reads.add((page, author));
            return page == 1
                ? _page(1, posts: [_post(1, uid: 'opening-author')])
                : _page(page);
          },
        ),
      );
      await tapViewMode(tester, '只看楼主');
      await tester.pumpAndSettle();
      expect(reads, [(4, null), (1, null), (1, 'opening-author')]);
      expect(await currentViewMode(tester), ThreadViewMode.author);
    },
  );
}
