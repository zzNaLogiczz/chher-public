import 'dart:async';

import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fetcher extends ChhFetcher {
  final gets = <Uri>[];
  final headers = <Map<String, String>?>[];
  int posts = 0;
  String body = 'ok';
  Future<ChhResponse> Function()? read;
  @override
  String get name => 'fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) {
    gets.add(url);
    this.headers.add(headers);
    return read?.call() ?? Future.value(ChhResponse(200, body));
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts++;
    return const ChhResponse(200, 'accepted');
  }
}

Uri page(String id) => Uri.parse('https://www.chiphell.com/fixture/$id');

void main() {
  test(
    'LRU keeps recently read pages and evicts within the entry limit',
    () async {
      final fetcher = _Fetcher();
      final client = ChhClient(fetchers: [fetcher], maxCacheEntries: 2);
      await client.getHtml(page('a'));
      await client.getHtml(page('b'));
      await client.getHtml(page('a')); // a is now most recent.
      await client.getHtml(page('c'));
      await client.getHtml(page('a'));
      expect(fetcher.gets.length, 3);
      await client.getHtml(page('b'));
      expect(fetcher.gets.length, 4);
    },
  );

  test(
    'byte budget evicts and oversized pages are returned without caching',
    () async {
      final fetcher = _Fetcher()..body = 'aa';
      final client = ChhClient(fetchers: [fetcher], maxCacheBytes: 8);
      for (final id in ['a', 'b', 'c', 'b']) {
        await client.getHtml(page(id));
      }
      expect(fetcher.gets.length, 3);
      await client.getHtml(page('a'));
      expect(fetcher.gets.length, 4);
      fetcher.body = 'oversized';
      expect(await client.getHtml(page('large')), 'oversized');
      await client.getHtml(page('large'));
      expect(fetcher.gets.length, 6);
      // Oversized responses do not evict useful pages.
      await client.getHtml(page('a'));
      expect(fetcher.gets.length, 6);
    },
  );

  test(
    'TTL is based on network arrival and expires despite cache hits',
    () async {
      var now = DateTime.utc(2026);
      final fetcher = _Fetcher();
      final client = ChhClient(
        fetchers: [fetcher],
        cacheTtl: const Duration(seconds: 5),
        now: () => now,
      );
      await client.getHtml(page('a'));
      now = now.add(const Duration(seconds: 4));
      await client.getHtml(page('a'));
      expect(fetcher.gets.length, 1);
      now = now.add(const Duration(seconds: 1));
      await client.getHtml(page('a'));
      expect(fetcher.gets.length, 2);
    },
  );

  test(
    'refresh skips completed cache but joins an equivalent in-flight GET',
    () async {
      final fetcher = _Fetcher();
      final client = ChhClient(fetchers: [fetcher]);
      await client.getHtml(page('a'));
      final pending = Completer<ChhResponse>();
      fetcher.read = () => pending.future;
      final fresh = client.getHtml(page('a'), refresh: true);
      final joined = client.getHtml(page('a'), refresh: true);
      expect(
        await client.getHtml(page('a')),
        'ok',
      ); // Old cache is still usable.
      expect(fetcher.gets.length, 2);
      pending.complete(const ChhResponse(200, 'fresh'));
      expect(await Future.wait([fresh, joined]), ['fresh', 'fresh']);
      expect(await client.getHtml(page('a')), 'fresh');
    },
  );

  test(
    'cold parallel reads coalesce, and a failed flight can be retried',
    () async {
      final fetcher = _Fetcher();
      final client = ChhClient(fetchers: [fetcher]);
      final pending = Completer<ChhResponse>();
      fetcher.read = () => pending.future;
      final a = client.getHtml(page('a'));
      final b = client.getHtml(page('a'));
      expect(fetcher.gets.length, 1);
      final failed = Future.wait([
        expectLater(a, throwsA(isA<ChhAllBlockedError>())),
        expectLater(b, throwsA(isA<ChhAllBlockedError>())),
      ]);
      pending.complete(const ChhResponse(-1, ''));
      await failed;
      fetcher.read = null;
      expect(await client.getHtml(page('a')), 'ok');
      expect(fetcher.gets.length, 2);
    },
  );

  test('AJAX and fallback policy use independent flights', () async {
    final fetcher = _Fetcher();
    final client = ChhClient(fetchers: [fetcher]);
    final pending = Completer<ChhResponse>();
    fetcher.read = () => pending.future;
    final calls = [
      client.getHtml(page('a')),
      client.getHtml(page('a'), fallback: false),
      client.getAjaxHtml(page('a')),
    ];
    expect(fetcher.gets.length, 3);
    expect(fetcher.headers.last!['X-Requested-With'], 'XMLHttpRequest');
    pending.complete(const ChhResponse(200, 'ok'));
    await Future.wait(calls);
  });

  test(
    'clear prevents joining old auth work and stale work cannot refill cache',
    () async {
      final fetcher = _Fetcher();
      final client = ChhClient(fetchers: [fetcher]);
      final observed = <String>[];
      client.htmlObserver = (html) {
        observed.add(html);
        return true;
      };
      final pending = Completer<ChhResponse>();
      fetcher.read = () => pending.future;
      final old = client.getHtml(page('a'));
      client.clearCache();
      fetcher.read = null;
      fetcher.body = 'new-account';
      expect(await client.getHtml(page('a')), 'new-account');
      pending.complete(const ChhResponse(200, 'old-account'));
      await old;
      expect(await client.getHtml(page('a')), 'new-account');
      expect(fetcher.gets.length, 2);
      expect(observed, ['new-account']);
    },
  );

  for (final eviction in ['none', 'LRU', 'TTL']) {
    test(
      'cross-policy late responses cannot rewind cache after $eviction',
      () async {
        var now = DateTime.utc(2026);
        final fetcher = _Fetcher();
        final client = ChhClient(
          fetchers: [fetcher],
          maxCacheEntries: 1,
          cacheTtl: const Duration(seconds: 5),
          now: () => now,
        );
        final oldResponse = Completer<ChhResponse>();
        final freshResponse = Completer<ChhResponse>();
        fetcher.read = () => oldResponse.future;
        final old = client.getHtml(page('a'));
        fetcher.read = () => freshResponse.future;
        final fresh = client.getHtml(page('a'), fallback: false, refresh: true);
        expect(fetcher.gets.length, 2);
        freshResponse.complete(const ChhResponse(200, 'newer'));
        expect(await fresh, 'newer');
        fetcher.read = null;
        if (eviction != 'none') {
          if (eviction == 'TTL') now = now.add(const Duration(seconds: 6));
          await client.getHtml(page('other'));
        }
        oldResponse.complete(const ChhResponse(200, 'older'));
        expect(
          await old,
          'older',
        ); // Existing caller still receives its own read.
        fetcher.body = 'latest';
        expect(
          await client.getHtml(page('a')),
          eviction == 'none' ? 'newer' : 'latest',
        );
        expect(fetcher.gets.length, eviction == 'none' ? 2 : 4);
      },
    );
  }

  test(
    'eviction cannot make new readers join a superseded old flight',
    () async {
      final fetcher = _Fetcher();
      final client = ChhClient(fetchers: [fetcher], maxCacheEntries: 1);
      final pending = Completer<ChhResponse>();
      fetcher.read = () => pending.future;
      final old = client.getHtml(page('a'));
      fetcher.read = null;
      fetcher.body = 'newer';
      await client.getHtml(page('a'), fallback: false, refresh: true);
      await client.getHtml(page('other'));
      fetcher.body = 'latest';
      expect(await client.getHtml(page('a')), 'latest');
      pending.complete(const ChhResponse(200, 'older'));
      await old;
      expect(await client.getHtml(page('a')), 'latest');
      expect(fetcher.gets.length, 4);
    },
  );

  test('only accepted fresh network headers advance freshness', () async {
    var now = DateTime.utc(2026);
    final fetcher = _Fetcher()..body = 'header';
    final client = ChhClient(fetchers: [fetcher], now: () => now)
      ..htmlObserver = (html) => html == 'header';
    await client.getHtml(page('a'));
    final first = client.lastFreshHeaderAt;
    expect(first, now);
    now = now.add(const Duration(seconds: 3));
    await client.getHtml(page('a'));
    expect(client.lastFreshHeaderAt, first);
    fetcher.body = 'no-header';
    await client.getHtml(page('b'));
    expect(client.lastFreshHeaderAt, first);
    final pending = Completer<ChhResponse>();
    fetcher.read = () => pending.future;
    final old = client.getHtml(page('c'));
    client.clearCache();
    expect(client.lastFreshHeaderAt, isNull);
    pending.complete(const ChhResponse(200, 'header'));
    await old;
    expect(client.lastFreshHeaderAt, isNull);
  });

  test(
    'identical POSTs remain separate and invalidate completed GET cache',
    () async {
      final fetcher = _Fetcher();
      final client = ChhClient(fetchers: [fetcher]);
      await client.getHtml(page('a'));
      await Future.wait([
        client.postForm(page('send'), {'message': 'same'}),
        client.postForm(page('send'), {'message': 'same'}),
      ]);
      expect(fetcher.posts, 2);
      await client.getHtml(page('a'));
      expect(fetcher.gets.length, 2);
    },
  );
}
