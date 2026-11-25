import 'dart:async';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/loading_tokens.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:chh_app/widgets/chhers_refresh_indicator.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _tid = 900014;
const _title = '回填样例';
final _before = find.text('查看前面的回复');
final _heading = find.byType(ThreadCommentHeading);

class _PendingPages implements ChhFetcher {
  final requested = <int>[];
  final pending = <int, Completer<ChhResponse>>{};
  int peakInFlight = 0;

  @override
  String get name => 'previous-page fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    final page = int.parse(url.path.split('-')[2]);
    requested.add(page);
    final response = pending[page] = Completer<ChhResponse>();
    if (pending.length > peakInFlight) peakInFlight = pending.length;
    try {
      return await response.future;
    } finally {
      pending.remove(page);
    }
  }

  void finish(int page) {
    final html = StringBuffer('<h1 id="thread_subject">$_title</h1>');
    for (var n = (page - 1) * 30 + 1; n <= page * 30; n++) {
      html.write('''
<table id="pid$n"><tr><td><div class="authi"><strong>
<a href="space-uid-1.html">作者</a></strong></div>
<a id="postnum$n">$n#</a></td>
<td id="postmessage_$n"><p>回复 $n</p>${n.isEven ? '<p>附加段落</p>' : ''}</td>
</tr></table>
''');
    }
    pending[page]!.complete(ChhResponse(200, html.toString()));
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async =>
      throw UnsupportedError('Read-only fixture');

  @override
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async => throw UnsupportedError('Read-only fixture');
}

ThreadDetail _page(int page) => ThreadDetail(
  tid: _tid,
  title: _title,
  posts: [
    for (var n = (page - 1) * 4 + 1; n <= page * 4; n++)
      Post(
        pid: n,
        floor: n,
        author: '作者',
        authorUid: '1',
        timeRaw: '',
        content: [TextBlock('回复 $n')],
      ),
  ],
  page: PageInfo(current: page, hasNext: false),
);

Future<void> _mount(WidgetTester tester, ThreadDetailPage reader) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(Brightness.light), home: reader),
  );
}

Finder _card(int pid) => find.byWidgetPredicate(
  (widget) => widget is PostCard && widget.post.pid == pid,
);

int _loadedPosts(WidgetTester tester) {
  final dynamic reader = tester.state(find.byType(ThreadDetailPage));
  return reader.debugConversationIndex.loadedPostCount as int;
}

Future<void> _backToStart(WidgetTester tester) async {
  tester.widget<ReadingBar>(find.byType(ReadingBar)).onBackToTop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('15 sequential reads commit 450 replies in one anchored frame', (
    tester,
  ) async {
    final transport = _PendingPages();
    final client = ChhClient(
      fetchers: [transport],
      threadRequestInterval: Duration.zero,
    );
    await _mount(
      tester,
      ThreadDetailPage(
        tid: _tid,
        title: _title,
        initialPage: 17,
        initialThreaded: false,
        preloadPages: 1,
        repository: ForumRepository(client),
      ),
    );
    transport.finish(17);
    await tester.pumpAndSettle();

    final anchor = tester.getTopLeft(_card(481));
    final heading = tester.getTopLeft(_heading);
    final button = tester.getCenter(_before);
    await tester.tap(_before);
    await tester.pump();
    final loader = find.byType(ChhersLoader);
    expect(loader, findsOneWidget);
    expect(tester.widget<ChhersLoader>(loader).delayed, isFalse);
    expect(
      tester.widget<ChhersLoader>(loader).size.height,
      LoadingTokens.listHeight,
    );
    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    expect(_before.hitTestable(), findsNothing);
    expect(tester.getTopLeft(_heading), heading);
    expect(tester.getTopLeft(_card(481)), anchor);
    await tester.tapAt(button);
    await tester.pump();
    await tester.pump(AppMotion.loadingOut);
    expect(_before, findsNothing);

    for (var page = 16; page >= 2; page--) {
      expect(transport.pending.keys, [page]);
      expect(_loadedPosts(tester), 30);
      expect(find.text('已加载 30'), findsOneWidget);
      transport.finish(page);
      await tester.pump();
    }

    expect(transport.pending, isEmpty);
    expect(transport.requested, [for (var page = 17; page >= 2; page--) page]);
    expect(transport.peakInFlight, 1);
    expect(_loadedPosts(tester), 480);
    expect(tester.getTopLeft(_card(481)).dy, closeTo(anchor.dy, 1));
    expect(tester.getTopLeft(_card(481)).dx, anchor.dx);
    expect(find.byType(PostCard).evaluate().length, lessThan(30));
    await _backToStart(tester);
    expect(_before.hitTestable(), findsOneWidget);
    expect(find.text('已加载 480'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final mode in ThreadViewMode.values) {
    testWidgets('four earlier pages reach page 1 in $mode', (tester) async {
      final requests = <(int, String?)>[];
      var needsAuthorLanding = mode == ThreadViewMode.author;
      await _mount(
        tester,
        ThreadDetailPage(
          tid: _tid,
          title: _title,
          initialPage: 5,
          initialThreaded: mode == ThreadViewMode.threaded,
          loadPage: (page, author, _) async {
            requests.add((page, author));
            // Simulate a filtered landing past page 1.
            if (author != null && needsAuthorLanding) {
              needsAuthorLanding = false;
              return _page(5);
            }
            return _page(page);
          },
        ),
      );
      await tester.pumpAndSettle();
      if (mode == ThreadViewMode.author) {
        tester.widget<ThreadCommentHeading>(_heading).onModeChanged(mode);
        await tester.pumpAndSettle();
        expect(tester.widget<ThreadCommentHeading>(_heading).mode, mode);
      }
      requests.clear();
      await tester.tap(_before);
      await tester.pumpAndSettle();
      final author = mode == ThreadViewMode.author ? '1' : null;
      expect(requests, [for (var page = 4; page >= 1; page--) (page, author)]);
      expect(_loadedPosts(tester), 20);
      await _backToStart(tester);
      expect(_heading, findsOneWidget);
      expect(tester.widget<ThreadCommentHeading>(_heading).loadedCount, 19);
      expect(_before, findsNothing);
    });
  }

  testWidgets('the sixth read fails, commits five pages and retries from it', (
    tester,
  ) async {
    final requests = <(int, bool)>[];
    await _mount(
      tester,
      ThreadDetailPage(
        tid: _tid,
        title: _title,
        initialPage: 25,
        loadPage: (page, _, refresh) async {
          requests.add((page, refresh));
          if (page == 19 && !refresh) throw StateError('fixture failure');
          return _page(page);
        },
      ),
    );
    await tester.pumpAndSettle();
    final anchor = tester.getTopLeft(_card(97));
    await tester.tap(_before);
    await tester.pumpAndSettle();
    expect(requests, [for (var page = 25; page >= 19; page--) (page, false)]);
    expect(_loadedPosts(tester), 24);
    expect(tester.getTopLeft(_card(97)).dy, closeTo(anchor.dy, 1));

    await _backToStart(tester);
    expect(find.text('已加载 24'), findsOneWidget);
    await tester.tap(find.text('加载失败，重试'));
    await tester.pumpAndSettle();
    expect(requests.skip(7), [
      for (var page = 19; page >= 5; page--) (page, page == 19),
    ]);
    expect(_loadedPosts(tester), 84);
    await _backToStart(tester);
    expect(_before.hitTestable(), findsOneWidget);
    expect(find.text('已加载 84'), findsOneWidget);
  });

  for (final interruption in ['dispose', 'leave route', 'refresh', 'mode']) {
    testWidgets('$interruption discards completed pages and stops the batch', (
      tester,
    ) async {
      final inFlight = Completer<ThreadDetail>();
      final requests = <(int, bool)>[];
      await _mount(
        tester,
        ThreadDetailPage(
          tid: _tid,
          title: _title,
          initialPage: 5,
          loadPage: (page, _, refresh) {
            requests.add((page, refresh));
            return page == 3 ? inFlight.future : Future.value(_page(page));
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_before);
      await tester.pump();
      expect(requests, [(5, false), (4, false), (3, false)]);
      expect(_loadedPosts(tester), 4);

      final navigator = Navigator.of(tester.element(_heading));
      switch (interruption) {
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
        case 'leave route':
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('另一页')),
              ),
            ),
          );
        case 'refresh':
          unawaited(
            tester
                .state<ChhersRefreshIndicatorState>(
                  find.byType(ChhersRefreshIndicator),
                )
                .show(),
          );
        case 'mode':
          tester
              .widget<ThreadCommentHeading>(_heading)
              .onModeChanged(ThreadViewMode.floors);
      }
      await tester.pump();
      inFlight.complete(_page(3));
      await tester.pumpAndSettle();
      if (interruption == 'leave route') {
        navigator.pop();
        await tester.pumpAndSettle();
      }
      expect(requests, [
        (5, false),
        (4, false),
        (3, false),
        if (interruption == 'refresh') (1, true),
      ]);
      if (interruption != 'dispose') {
        expect(_loadedPosts(tester), 4);
        if (interruption == 'refresh') {
          expect(find.text('回复 1'), findsOneWidget);
          expect(_before, findsNothing);
        } else {
          expect(_before.hitTestable(), findsOneWidget);
        }
        expect(find.byType(ChhersLoader), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
