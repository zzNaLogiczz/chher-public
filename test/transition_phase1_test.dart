import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/network/chh_session.dart';
import 'package:chh_app/parser/get_page_parser.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/parser/misc_parser.dart';
import 'package:chh_app/parser/parser_worker.dart';
import 'package:chh_app/parser/thread_list_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

const _fid = 290;
const _tid = 900001;
const _header = '''
<div id="um">
  <strong class="vwmy"><a href="space-uid-1001.html">示例账号</a></strong>
  <img class="user_avatar" src="/avatar.jpg">
  <a id="myprompt"><em class="prompt_news_3"></em>提醒</a>
  <a id="pm_ntc">私信(2)</a>
</div>''';
const _types = '''
<div id="pt"><a href="forum-290-1.html">示例版块</a></div>
<ul id="thread_types">
  <li class="a"><a href="forum-290-1.html">全部</a></li>
  <li><a href="?mod=forumdisplay&amp;typeid=1">ITX 2<span class="num">13</span></a></li>
</ul>''';

class _Fetcher extends ChhFetcher {
  _Fetcher(this.html);
  String html;
  int calls = 0;

  @override
  String get name => 'transition-fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    calls++;
    return ChhResponse(200, html);
  }
}

class _ParserGate {
  _ParserGate({required this.forList});
  final bool forList;
  final entered = Completer<void>();
  final release = Completer<void>();

  Future<R> dispatch<M, R>(ComputeCallback<M, R> callback, M input) async {
    if (!entered.isCompleted && (input is GetPageInput) == forList) {
      entered.complete();
      await release.future;
    }
    return dispatchParserInWorker(callback, input);
  }
}

Object _summary(ThreadSummary item) => (
  item.tid,
  item.title,
  item.typeName,
  item.author,
  item.authorUid,
  item.createdAt,
  item.createdAtRaw,
  item.observedReplies,
  item.views,
  item.lastPostUser,
  item.lastPostTimeRaw,
  item.hasImages,
  item.sticky,
  item.forumName,
  item.forumFid,
  item.snippet,
);

List<Object> _categoryFields(List<ThreadType> types) => [
  for (final type in types) (type.typeid, type.name, type.active),
];

int _jobs = 0;
(String?, int) _workerProbe(String input) =>
    (Isolate.current.debugName, ++_jobs);

void main() {
  final source = File(
    'test_data/thread_list_synthetic.html',
  ).readAsStringSync().replaceFirst('<body>', '<body>$_types$_header');
  final thread = File('test_data/thread_synthetic.html').readAsStringSync();

  test(
    'parallel list, types and header parse one DOM; warm reads reuse it',
    () async {
      final fetcher = _Fetcher(source);
      var parses = 0;
      var jobs = 0;
      var observations = 0;
      Future<R> countParse<M, R>(
        ComputeCallback<M, R> callback,
        M input,
      ) async {
        jobs++;
        return inspectGetPage(
              input as GetPageInput,
              parseDocument: (source, {required generateSpans}) {
                parses++;
                return html_parser.parse(source, generateSpans: generateSpans);
              },
            )
            as R;
      }

      final client = ChhClient(fetchers: [fetcher], dispatchParser: countParse);
      final session = ChhSession(client);
      client.headerObserver = (header) {
        observations++;
        expect(header.badges, parseHeaderBadges(source));
        expect(header.badges?.avatarSrc, parseHeaderBadges(source)?.avatarSrc);
        return session.observeHeader(header);
      };
      final repo = ForumRepository(client);
      final listRead = repo.threadList(_fid);
      final typeRead = repo.threadTypes(_fid);
      final htmlRead = client.getHtml(ChhUrls.threadList(_fid));
      final list = await listRead;
      final types = await typeRead;
      expect(await htmlRead, source);
      expect(session.badges.notices, 3);
      expect(session.badges.messages, 2);
      expect(session.badges.uid, '1001');

      final reopened = ForumRepository(client);
      expect(await reopened.threadList(_fid), same(list));
      expect(await reopened.threadTypes(_fid), same(types));
      expect((fetcher.calls, jobs, parses, observations), (1, 1, 1, 1));
    },
  );

  for (final large in [false, true]) {
    test(
      'list, categories and header match legacy field by field large=$large',
      () async {
        // The later badge exercises the prior header parser's full-DOM fallback.
        final html = large
            ? source
                  .replaceFirst('id="pm_ntc"', 'id="old_pm"')
                  .replaceFirst(
                    '</body>',
                    '<!--${'x' * 90000}--><a id="pm_ntc">私信(5)</a></body>',
                  )
            : source;
        final client = ChhClient(fetchers: [_Fetcher(html)]);
        HeaderObservation? observation;
        client.headerObserver = (header) {
          observation = header;
          return true;
        };
        final repo = ForumRepository(client);
        final legacy = parseThreadList(html, forumFid: _fid);
        final list = await repo.threadList(_fid);
        expect(list.threads.map(_summary), legacy.threads.map(_summary));
        expect(list.page.current, legacy.page.current);
        expect(list.page.hasNext, legacy.page.hasNext);
        final types = _categoryFields(await repo.threadTypes(_fid));
        expect(types, _categoryFields(parseThreadTypes(html)));
        expect(types, [(0, '全部', true), (1, 'ITX 2', false)]);
        final badges = parseHeaderBadges(html)!;
        expect(observation!.badges, badges);
        expect(observation!.badges!.avatarSrc, badges.avatarSrc);
        expect(observation!.badges!.headerSample, badges.headerSample);
        expect(observation!.guest, isFalse);
      },
    );
  }

  test('site message rejects only list and retains category output', () async {
    final html =
        '<html><body>$_types<div id="messagetext">请先登录</div>'
        '<div id="messagelogin"></div></body></html>';
    final fetcher = _Fetcher(html);
    final repo = ForumRepository(ChhClient(fetchers: [fetcher]));
    await expectLater(
      repo.threadList(_fid),
      throwsA(
        isA<PageMessage>().having(
          (e) => e.kind,
          'kind',
          PageMessageKind.loginRequired,
        ),
      ),
    );
    expect(
      _categoryFields(await repo.threadTypes(_fid)),
      _categoryFields(parseThreadTypes(html)),
    );
    expect(fetcher.calls, 1);
  });

  test(
    'list refresh, URL, TTL and session boundaries replace the model',
    () async {
      final fetcher = _Fetcher(source);
      var time = DateTime.utc(2026);
      final client = ChhClient(fetchers: [fetcher], now: () => time);
      final repo = ForumRepository(client);
      final first = await repo.threadList(_fid);
      expect(await repo.threadList(_fid, typeid: 1), isNot(same(first)));
      expect(await repo.threadList(_fid), same(first));
      final fresh = await repo.threadList(_fid, refresh: true);
      expect(fresh, isNot(same(first)));
      final types = await repo.threadTypes(_fid);
      time = time.add(client.cacheTtl);
      final afterTtl = await repo.threadList(_fid);
      expect(afterTtl, isNot(same(fresh)));
      expect(await repo.threadTypes(_fid), isNot(same(types)));
      client.clearCache();
      expect(await repo.threadList(_fid), isNot(same(afterTtl)));
      expect(fetcher.calls, 5);
    },
  );

  for (final clearSession in [false, true]) {
    test(
      'delayed list parse cannot overwrite newer model or header session=$clearSession',
      () async {
        final fetcher = _Fetcher(source);
        final gate = _ParserGate(forList: true);
        final client = ChhClient(
          fetchers: [fetcher],
          dispatchParser: gate.dispatch,
        );
        final notices = <int>[];
        client.headerObserver = (header) {
          notices.add(header.badges!.notices);
          return true;
        };
        final repo = ForumRepository(client);
        final old = repo.threadList(_fid);
        await gate.entered.future;
        if (clearSession) client.clearCache();
        fetcher.html = source
            .replaceFirst('示例主题1', '新列表')
            .replaceFirst('prompt_news_3', 'prompt_news_8');
        // Without a generation change, independent fallback policies may finish
        // out of sequence but still share the resulting completed-cache entry.
        await client.getHtml(
          ChhUrls.threadList(_fid),
          fallback: false,
          refresh: true,
        );
        final fresh = await repo.threadList(_fid);
        gate.release.complete();
        expect((await old).threads.first.title, '示例主题1');
        expect(fresh.threads.first.title, '新列表');
        expect(await repo.threadList(_fid), same(fresh));
        expect(notices, [8]);
        expect(fetcher.calls, 2);
      },
    );
  }

  for (final invalidate in [false, true]) {
    test(
      'detail parser completion respects cancellation or invalidation revision=$invalidate',
      () async {
        final fetcher = _Fetcher(thread);
        final gate = _ParserGate(forList: false);
        final client = ChhClient(
          fetchers: [fetcher],
          threadRequestInterval: Duration.zero,
          dispatchParser: gate.dispatch,
        );
        final repo = ForumRepository(client);
        var active = true;
        final pending = repo.thread(_tid, shouldContinue: () => active);
        final cancelled = expectLater(
          pending,
          throwsA(isA<ThreadReadCancelled>()),
        );
        await gate.entered.future;
        if (invalidate) {
          repo.invalidateThread(_tid);
        } else {
          active = false;
        }
        gate.release.complete();
        await cancelled;
        expect(repo.cachedThreadPage(_tid, 1), isNull);
        expect(client.hasCachedHtml(ChhUrls.thread(_tid)), !invalidate);
        final resumed = await repo.thread(_tid);
        expect(await repo.thread(_tid), same(resumed));
        expect(fetcher.calls, invalidate ? 2 : 1);
      },
    );
  }

  test(
    'detail isolate completion cannot replace a refreshed identical HTML sequence',
    () async {
      final fetcher = _Fetcher(thread);
      final gate = _ParserGate(forList: false);
      final client = ChhClient(
        fetchers: [fetcher],
        threadRequestInterval: Duration.zero,
        dispatchParser: gate.dispatch,
      );
      final repo = ForumRepository(client);
      final old = repo.thread(_tid);
      await gate.entered.future;
      final fresh = await repo.thread(_tid, refresh: true);
      gate.release.complete();
      expect(await old, isNot(same(fresh)));
      expect(await repo.thread(_tid), same(fresh));
      expect(fetcher.calls, 2);
    },
  );

  test('prewarmed native parser reuses a non-UI isolate across jobs', () async {
    await prewarmParserWorker();
    final first = await dispatchParserInWorker(_workerProbe, 'small page');
    final second = await dispatchParserInWorker(_workerProbe, 'next page');
    expect(first.$1, isNot(Isolate.current.debugName));
    expect(second, (first.$1, first.$2 + 1));
    expect(_jobs, 0);
  });
}
