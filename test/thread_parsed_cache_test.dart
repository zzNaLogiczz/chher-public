import 'dart:async';

import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _html = '''
<html><body><div id="wp"><h1 id="thread_subject">本地讨论</h1>
<table id="pid101"><tr><td>
<div class="authi"><strong><a href="space-uid-10.html">示例作者</a></strong></div>
<a id="postnum101">楼主</a><em id="authorposton101">发表于 2026-11-16 10:00</em>
</td><td id="postmessage_101">正文内容</td></tr></table>
</div></body></html>''';

class _Fetcher extends ChhFetcher {
  String body = _html;
  int reads = 0;
  Future<ChhResponse> Function()? pending;
  @override
  String get name => 'fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) {
    reads++;
    return pending?.call() ?? Future.value(ChhResponse(200, body));
  }
}

ChhClient _client(_Fetcher fetcher, {DateTime Function()? now}) => ChhClient(
  fetchers: [fetcher],
  now: now,
  threadRequestInterval: Duration.zero,
);

void main() {
  test('30 cached pages reuse parsed objects after re-entry', () async {
    final fetcher = _Fetcher()..body = '$_html<!--${'x' * 300000}-->';
    final client = _client(fetcher);
    final firstRepo = ForumRepository(client);
    final pages = <ThreadDetail>[];
    for (var page = 1; page <= 30; page++) {
      pages.add(await firstRepo.thread(123, page: page));
    }
    final reopened = ForumRepository(client);
    for (var page = 1; page <= 30; page++) {
      expect(await reopened.thread(123, page: page), same(pages[page - 1]));
    }
    expect(fetcher.reads, 30);
    expect(
      pages.first.posts.single.content.whereType<TextBlock>().single.text,
      '正文内容',
    );
  });

  test(
    'refresh, TTL and session clearing still pass through the HTML reader',
    () async {
      var now = DateTime.utc(2026, 11, 16);
      final fetcher = _Fetcher();
      final client = _client(fetcher, now: () => now);
      final repo = ForumRepository(client);
      final first = await repo.thread(123);
      expect(await repo.thread(123), same(first));
      final refreshed = await repo.thread(123, refresh: true);
      expect(refreshed, isNot(same(first)));
      expect(fetcher.reads, 2);
      client.clearCache();
      final nextSession = await repo.thread(123);
      expect(
        nextSession,
        isNot(same(refreshed)),
        reason: 'Even identical HTML belongs to a new generation',
      );
      fetcher.body = _html.replaceFirst('本地讨论', '更新标题');
      now = now.add(const Duration(minutes: 30));
      final expired = await repo.thread(123);
      expect(expired.title, '更新标题');
      expect(expired, isNot(same(nextSession)));
      expect(fetcher.reads, 4);
    },
  );

  test(
    'client, thread, page, author and fallback page remain separate',
    () async {
      final fetcher = _Fetcher();
      final client = _client(fetcher);
      final repo = ForumRepository(client);
      final first = await repo.thread(123);
      expect(
        await ForumRepository(_client(_Fetcher())).thread(123),
        isNot(same(first)),
      );
      final otherThread = await repo.thread(456);
      expect(otherThread.tid, 456);
      expect(otherThread, isNot(same(first)));
      final later = await repo.thread(123, page: 4);
      expect(later.page.current, 4);
      expect(await repo.thread(123, authorUid: '10'), isNot(same(first)));
      expect(await repo.thread(123, authorUid: '20'), isNot(same(first)));
      final url = ChhUrls.thread(123, page: 4).toString();
      final redirected = await repo.threadAtUrl(url, tid: 123);
      expect(
        redirected.page.current,
        1,
        reason: 'The same HTML still uses the caller fallback',
      );
      expect(redirected, isNot(same(later)));
      expect(await repo.threadAtUrl(url, tid: 123), same(redirected));
    },
  );

  test(
    'late old-session responses cannot replace the new parsed cache',
    () async {
      final pending = Completer<ChhResponse>();
      final fetcher = _Fetcher()..pending = () => pending.future;
      final client = _client(fetcher);
      final repo = ForumRepository(client);
      final old = repo.thread(123);
      client.clearCache();
      fetcher.pending = null;
      fetcher.body = _html.replaceFirst('本地讨论', '新会话');
      final current = repo.thread(123);
      pending.complete(const ChhResponse(200, _html));
      expect((await old).title, '本地讨论');
      final fresh = await current;
      expect(fresh.title, '新会话');
      expect(await repo.thread(123), same(fresh));
      expect(fetcher.reads, 2);
    },
  );

  test(
    'cancelled network results stay as HTML until reading resumes',
    () async {
      final pending = Completer<ChhResponse>();
      final fetcher = _Fetcher()..pending = () => pending.future;
      final client = _client(fetcher);
      final repo = ForumRepository(client);
      var active = true;
      final read = repo.thread(123, shouldContinue: () => active);
      final cancelled = expectLater(read, throwsA(isA<ThreadReadCancelled>()));
      active = false;
      pending.complete(const ChhResponse(200, _html));
      await cancelled;
      expect(client.hasCachedHtml(ChhUrls.thread(123)), isTrue);
      active = true;
      final resumed = await repo.thread(123, shouldContinue: () => active);
      expect(resumed.title, '本地讨论');
      expect(await repo.thread(123), same(resumed));
      expect(fetcher.reads, 1);
    },
  );

  test(
    'LRU evicts old parsed pages without fetching their cached HTML again',
    () async {
      final fetcher = _Fetcher();
      final repo = ForumRepository(_client(fetcher));
      final first = await repo.thread(123, page: 1);
      final second = await repo.thread(123, page: 2);
      for (var page = 3; page <= 32; page++) {
        await repo.thread(123, page: page);
      }
      expect(await repo.thread(123, page: 1), same(first));
      await repo.thread(123, page: 33);
      expect(await repo.thread(123, page: 1), same(first));
      expect(await repo.thread(123, page: 2), isNot(same(second)));
      expect(fetcher.reads, 33);
    },
  );

  test(
    'source byte budget evicts large pages before the entry count limit',
    () async {
      final fetcher = _Fetcher()..body = '$_html<!--${'x' * 900000}-->';
      final repo = ForumRepository(_client(fetcher));
      final first = await repo.thread(123);
      for (var page = 2; page <= 20; page++) {
        await repo.thread(123, page: page);
      }
      expect(await repo.thread(123), isNot(same(first)));
      expect(fetcher.reads, 20);
    },
  );

  test(
    'permission errors and cancelled reads never return a cached success',
    () async {
      final fetcher = _Fetcher();
      final client = _client(fetcher);
      final repo = ForumRepository(client);
      final first = await repo.thread(123);
      await expectLater(
        repo.thread(123, shouldContinue: () => false),
        throwsA(isA<ThreadReadCancelled>()),
      );
      fetcher.body =
          '<html><body><div id="messagetext">请先登录</div><div id="messagelogin"></div></body></html>';
      await expectLater(
        repo.thread(123, refresh: true),
        throwsA(isA<PageMessage>()),
      );
      await expectLater(repo.thread(123), throwsA(isA<PageMessage>()));
      fetcher.body = _html;
      final recovered = await repo.thread(123, refresh: true);
      expect(recovered, isNot(same(first)));
      expect(await repo.thread(123), same(recovered));
    },
  );
}
