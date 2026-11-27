import 'dart:async';

import 'package:chh_app/data/history_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/pages/history_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/portal_parser.dart';
import 'package:chh_app/widgets/chhers_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inline_forum_parser.dart';

const _thread = ThreadDetail(
  tid: 1125,
  title: '正文里的帖子标题',
  fid: 55,
  forumName: '电脑讨论',
  posts: [
    Post(
      pid: 1,
      floor: 1,
      author: '楼主甲',
      timeRaw: '',
      content: [TextBlock('帖子正文')],
    ),
  ],
  page: PageInfo(current: 1, hasNext: false),
);

const _articleMarkup = '''
<div id="pt"><a href="portal.php?mod=list&catid=12">电脑评测</a></div>
<div class="vw"><div class="h">
  <h1 class="ph">正文里的文章标题</h1>
  <p class="xg1">2026-11-25 12:00 | 发布者: 编辑甲 | 原作者：作者乙</p>
</div></div>
''';

class _HistoryRouteFetcher extends ChhFetcher {
  @override
  String get name => 'offline-history';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    if (url.path.endsWith('/article-25-1.html')) {
      return const ChhResponse(
        200,
        '$_articleMarkup<div id="article_content">文章正文</div>',
      );
    }
    return const ChhResponse(503, '');
  }
}

Future<void> _mount(WidgetTester tester, Widget page) => tester.pumpWidget(
  MaterialApp(theme: buildAppTheme(Brightness.light), home: page),
);

void _recordAnotherVisit() => historyIndex.record(
  type: HistoryType.thread,
  id: 1126,
  title: '另一个帖子',
  author: '楼主乙',
);

void main() {
  setUp(() async => historyIndex.clear());
  tearDown(() async => historyIndex.clear());

  test('the article publisher is used when the original byline is blank', () {
    final content =
        parsePortalContent(
              _articleMarkup.replaceFirst('作者乙', '    | '),
              aid: 25,
            )
            as ArticleContent;
    expect(content.detail.author, '编辑甲');
  });

  testWidgets(
    'a history row reorders only after its real route reads content',
    (tester) async {
      useInlineForumParser(chhClient);
      final transports = List<ChhFetcher>.of(chhClient.fetchers);
      chhClient.fetchers
        ..clear()
        ..add(_HistoryRouteFetcher());
      chhClient.clearCache();
      addTearDown(() {
        chhClient.fetchers
          ..clear()
          ..addAll(transports);
        chhClient.clearCache();
      });

      historyIndex.record(
        type: HistoryType.article,
        id: 25,
        title: '之前打开的文章',
        author: '作者乙',
      );
      _recordAnotherVisit();
      final oldThread = historyIndex.all.first;
      await _mount(tester, const HistoryPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('之前打开的文章'));
      await tester.pumpAndSettle();
      expect(find.byType(ArticlePage), findsOneWidget);
      await tester.tap(find.byTooltip('返回').first);
      await tester.pumpAndSettle();
      expect(historyIndex.all.map((entry) => entry.id), [25, 1126]);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('article:25'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('thread:1126'))).dy,
        ),
      );

      await tester.tap(find.text('另一个帖子'));
      await tester.pumpAndSettle();
      expect(find.byType(ThreadDetailPage), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(historyIndex.all.map((entry) => entry.id), [25, 1126]);
      expect(historyIndex.all.last, same(oldThread));
    },
  );

  testWidgets('thread records after successful retry and reopens at the top', (
    tester,
  ) async {
    final firstAttempt = Completer<ThreadDetail>();
    final readModes = <bool>[];
    Future<ThreadDetail> loadPage(int page, String? authorUid, bool refresh) {
      readModes.add(refresh);
      return readModes.length == 1
          ? firstAttempt.future
          : Future.value(_thread);
    }

    Widget reader() =>
        ThreadDetailPage(tid: _thread.tid, title: '入口标题', loadPage: loadPage);

    await _mount(tester, reader());
    expect(historyIndex.all, isEmpty);
    firstAttempt.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(historyIndex.all, isEmpty);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    final visit = historyIndex.all.single;
    expect(visit.type, HistoryType.thread);
    expect(visit.id, _thread.tid);
    expect(visit.title, _thread.title);
    expect(visit.fid, _thread.fid);
    expect(visit.forumName, _thread.forumName);
    expect(visit.author, '楼主甲');

    _recordAnotherVisit();
    final refresh = tester
        .widget<ChhersRefreshIndicator>(find.byType(ChhersRefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    await refresh;
    expect(historyIndex.all.map((entry) => entry.id), [1126, _thread.tid]);
    expect(historyIndex.all.last, same(visit));

    await tester.pumpWidget(const SizedBox());
    await _mount(tester, reader());
    await tester.pumpAndSettle();
    expect(historyIndex.all.map((entry) => entry.id), [_thread.tid, 1126]);
    expect(readModes, [false, true, true, false]);
  });

  testWidgets('thread response without readable posts is not recorded', (
    tester,
  ) async {
    await _mount(
      tester,
      ThreadDetailPage(
        tid: _thread.tid,
        title: _thread.title,
        loadPage: (_, _, _) async => ThreadDetail(
          tid: _thread.tid,
          title: _thread.title,
          posts: const [],
          page: _thread.page,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(historyIndex.all, isEmpty);
  });

  testWidgets('article records the first valid body and ignores continuation', (
    tester,
  ) async {
    const aid = 25;
    final secondPage = Completer<PortalContent>();
    final calls = <(int, bool)>[];
    await _mount(
      tester,
      ArticlePage(
        aid: aid,
        title: '入口标题',
        loadPage: (page, refresh) async {
          calls.add((page, refresh));
          if (page == 2) return secondPage.future;
          return parsePortalContent(
            _articleMarkup +
                (refresh
                    ? '<div id="article_content">文章正文</div>'
                          '<div class="pg"><strong>1</strong>'
                          '<a class="nxt" href="article-25-2.html">下一页</a></div>'
                    : ''),
            aid: aid,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(historyIndex.all, isEmpty);
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    final visit = historyIndex.all.single;
    expect(visit.type, HistoryType.article);
    expect(visit.id, aid);
    expect(visit.title, '正文里的文章标题');
    expect(visit.column, '电脑评测');
    expect(visit.author, '作者乙');

    _recordAnotherVisit();
    secondPage.complete(
      const ArticleContent(
        ArticleDetail(
          aid: aid,
          title: '后续页',
          content: [TextBlock('后续页正文')],
          page: PageInfo(current: 2, hasNext: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [(1, false), (1, true), (2, false)]);
    expect(historyIndex.all.map((entry) => entry.id), [1126, aid]);
    expect(historyIndex.all.last, same(visit));
  });

  testWidgets('portal redirects record the loaded forum thread only', (
    tester,
  ) async {
    await _mount(
      tester,
      ArticlePage(
        aid: 25,
        title: '门户入口',
        loadPage: (_, _) async => ThreadContent(
          _thread.tid,
          _thread.title,
          detail: _thread,
          cacheGeneration: chhClient.cacheGeneration,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(historyIndex.all.single.type, HistoryType.thread);
    expect(historyIndex.all.single.id, _thread.tid);
  });
}
