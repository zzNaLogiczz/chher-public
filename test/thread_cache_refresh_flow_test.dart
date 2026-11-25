import 'dart:async';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/chhers_refresh_indicator.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _tid = 123;

class _Forum extends ChhFetcher {
  List<List<int>> pages = [
    [1, 2],
    [3],
  ];
  bool unavailable = false;
  bool omitLaterCounts = false;
  Completer<void>? tailResponse;
  final requests = <int>[];
  late final repository = ForumRepository(
    ChhClient(fetchers: [this], threadRequestInterval: Duration.zero),
  );

  @override
  String get name => 'fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    final page = int.parse(url.path.split('-')[2]);
    requests.add(page);
    if (page == pages.length) await tailResponse?.future;
    if (unavailable) return ChhResponse.timeout;
    final replies = pages.expand((floors) => floors).length - 1;
    return ChhResponse(200, '''
<html><body><div id="wp"><h1 id="thread_subject">分页测试</h1>
<div id="postlist">${page == 1 || !omitLaterCounts ? '<div class="hm">查看: 24 回复: $replies</div>' : ''}
${pages[page - 1].map(_post).join()}
</div><div class="pg"><strong>$page</strong>
${page < pages.length ? '<a class="nxt" href="thread-$_tid-${page + 1}-1.html">下一页</a>' : ''}
</div></div></body></html>''');
  }
}

String _post(int floor) =>
    '''
<table id="pid$floor"><tr><td>
<div class="authi"><strong><a href="space-uid-$floor.html">用户$floor</a></strong></div>
<a id="postnum$floor">${floor == 1 ? '楼主' : '$floor#'}</a>
</td><td id="postmessage_$floor">${floor == 1 ? List.filled(30, '首楼正文').join('<br>') : '第$floor楼的回复'}</td></tr></table>''';

Future<void> _mount(WidgetTester tester, _Forum forum, {int? replies}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: ThreadDetailPage(
        tid: _tid,
        title: '分页测试',
        repository: forum.repository,
        observedReplies: replies,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _preload(tester);
}

Future<void> _preload(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _topRefresh(WidgetTester tester) async {
  final refresh = tester
      .widget<ChhersRefreshIndicator>(find.byType(ChhersRefreshIndicator))
      .onRefresh();
  await tester.pumpAndSettle();
  await refresh;
  await _preload(tester);
}

Future<void> _bottom(WidgetTester tester) async {
  final position = _position(tester);
  for (var attempt = 0; attempt < 10; attempt++) {
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    if (position.extentAfter < 1) return;
  }
  fail('Reader did not reach the end');
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets(
    'a larger list count revalidates the old tail with a warm prefix',
    (tester) async {
      final forum = _Forum()..omitLaterCounts = true;
      await _mount(tester, forum, replies: 2);
      expect(forum.requests, [1, 2]);
      await tester.pumpWidget(const SizedBox());

      await _mount(tester, forum, replies: 2);
      expect(forum.requests, [1, 2]);
      await tester.pumpWidget(const SizedBox());

      forum.pages.last.add(4);
      await _mount(tester, forum, replies: 3);
      expect(find.text('24 查看　3 回复'), findsOneWidget);
      await _bottom(tester);

      expect(forum.requests, [1, 2, 2]);
      expect(find.text('第4楼的回复'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _mount(tester, forum, replies: 3);
      expect(find.text('24 查看　3 回复'), findsOneWidget);
      expect(forum.requests, [1, 2, 2]);
    },
  );

  testWidgets('a confirmed lower count drops pages beyond the new end', (
    tester,
  ) async {
    final forum = _Forum();
    await _mount(tester, forum, replies: 2);
    await tester.pumpWidget(const SizedBox());

    forum.pages.removeLast();
    await _mount(tester, forum, replies: 1);
    await _bottom(tester);

    expect(forum.requests, [1, 2, 1]);
    expect(find.text('第2楼的回复'), findsOneWidget);
    expect(find.text('第3楼的回复'), findsNothing);
  });

  testWidgets('top refresh reopens every page from the source', (tester) async {
    final forum = _Forum();
    await _mount(tester, forum, replies: 2);
    expect(forum.requests, [1, 2]);
    forum.pages.last.add(4);

    await _topRefresh(tester);
    await _bottom(tester);

    expect(forum.requests, [1, 2, 1, 2]);
    expect(find.text('第4楼的回复'), findsOneWidget);
  });

  testWidgets('a failed top refresh keeps the existing discussion', (
    tester,
  ) async {
    final forum = _Forum();
    await _mount(tester, forum, replies: 2);
    forum.unavailable = true;

    await _topRefresh(tester);
    await _bottom(tester);

    expect(forum.requests, [1, 2, 1]);
    expect(find.text('第3楼的回复'), findsOneWidget);
  });

  testWidgets('end pull lifts the footer only while checking for replies', (
    tester,
  ) async {
    final forum = _Forum();
    await _mount(tester, forum, replies: 2);
    await _bottom(tester);
    final marker = find.text('已读到这里');
    final restingY = tester.getTopLeft(marker).dy;
    final response = forum.tailResponse = Completer<void>();

    await tester.dragFrom(const Offset(350, 380), const Offset(0, -300));
    await tester.pump();
    await tester.pump(AppMotion.scrollChrome.duration);

    expect(forum.requests, [1, 2, 2]);
    expect(tester.getTopLeft(marker).dy, lessThan(restingY - 20));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ChhersLoader &&
            widget.size == ChhersLoaderSize.refresh &&
            widget.animate,
      ),
      findsOneWidget,
    );

    response.complete();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(marker).dy, closeTo(restingY, 1));
  });

  testWidgets(
    'a new tail pull rechecks through the end',
    (tester) async {
      final forum = _Forum();
      await _mount(tester, forum, replies: 2);
      await _bottom(tester);
      expect(forum.requests, [1, 2]);

      forum.pages.last.add(4);
      forum.pages.add([5]);
      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent - 80);
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(350, 380), const Offset(0, -280));
      await tester.pumpAndSettle();
      expect(position.extentAfter, lessThan(1));
      expect(forum.requests, [1, 2]);

      final oldTail = find.text('第3楼的回复');
      final oldTop = tester.getTopLeft(oldTail).dy;
      await tester.dragFrom(const Offset(350, 380), const Offset(0, -280));
      await tester.pumpAndSettle();
      await _preload(tester);
      expect(tester.getTopLeft(oldTail).dy, closeTo(oldTop, 1));
      await _bottom(tester);

      expect(forum.requests, [1, 2, 2, 3]);
      expect(find.text('第4楼的回复'), findsOneWidget);
      expect(find.text('第5楼的回复'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
