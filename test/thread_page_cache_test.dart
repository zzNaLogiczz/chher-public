import 'dart:async';

import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fetcher extends ChhFetcher {
  final gets = <Uri>[];
  String body = 'cached floors';
  Future<ChhResponse> Function(Uri)? read;
  @override
  String get name => 'fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) {
    gets.add(url);
    return read?.call(url) ?? Future.value(ChhResponse(200, body));
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async =>
      const ChhResponse(200, 'accepted');
}

void main() {
  test(
    '30 large thread pages survive re-entry beyond the ordinary TTL',
    () async {
      var now = DateTime.utc(2026);
      final fetcher = _Fetcher()..body = 'x' * 300000;
      final client = ChhClient(
        fetchers: [fetcher],
        now: () => now,
        threadRequestInterval: Duration.zero,
      );
      final repo = ForumRepository(client);
      for (var page = 1; page <= 30; page++) {
        await client.getHtml(ChhUrls.thread(10, page: page));
      }
      await client.getHtml(ChhUrls.threadList(20));
      now = now.add(const Duration(minutes: 2));
      for (var page = 1; page <= 30; page++) {
        expect(repo.hasCachedThread(10, page: page), isTrue);
        await client.getHtml(ChhUrls.thread(10, page: page));
      }
      expect(fetcher.gets.length, 31);
      expect(client.hasCachedHtml(ChhUrls.threadList(20)), isFalse);
      now = now.add(const Duration(minutes: 28));
      expect(repo.hasCachedThread(10), isFalse);
      await client.getHtml(ChhUrls.thread(10));
      expect(fetcher.gets.length, 32);
    },
  );

  test(
    'page, author and thread keys stay separate; refresh and POST invalidate',
    () async {
      final fetcher = _Fetcher();
      final client = ChhClient(
        fetchers: [fetcher],
        threadRequestInterval: Duration.zero,
      );
      final urls = [
        ChhUrls.thread(10),
        ChhUrls.thread(10, page: 2),
        ChhUrls.thread(11),
        ChhUrls.threadByAuthor(10, '20'),
        ChhUrls.threadByAuthor(10, '21'),
      ];
      for (final url in urls) {
        await client.getHtml(url);
      }
      expect(fetcher.gets.length, 5);
      fetcher.body = 'new floors';
      expect(await client.getHtml(urls.first, refresh: true), 'new floors');
      expect(await client.getHtml(urls.first), 'new floors');
      expect(fetcher.gets.length, 6);
      await client.postForm(Uri.parse('${ChhUrls.base}/fixture/send'), {});
      expect(client.hasCachedHtml(urls.first), isFalse);
      await client.getHtml(urls.first);
      expect(fetcher.gets.length, 7);
    },
  );

  testWidgets(
    'thread reads serialize with 300ms after completion; cached reads do not wait',
    (tester) async {
      final first = Completer<ChhResponse>();
      final fetcher = _Fetcher()..read = (_) => first.future;
      final client = ChhClient(
        fetchers: [fetcher],
        now: tester.binding.clock.now,
      );
      final a = client.getHtml(ChhUrls.thread(10));
      final b = client.getHtml(ChhUrls.thread(10, page: 2));
      final joined = client.getHtml(ChhUrls.thread(10, page: 2));
      await tester.pump(const Duration(seconds: 5));
      expect(fetcher.gets.length, 1);
      first.complete(const ChhResponse(200, 'one'));
      fetcher.read = null;
      await tester.pump();
      expect(await a, 'one');
      expect(await client.getHtml(ChhUrls.thread(10)), 'one');
      await tester.pump(const Duration(milliseconds: 299));
      expect(fetcher.gets.length, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(await Future.wait([b, joined]), [
        'cached floors',
        'cached floors',
      ]);
      expect(fetcher.gets.length, 2);
    },
  );

  testWidgets(
    'leaving during cooldown cancels a page before transport starts',
    (tester) async {
      final fetcher = _Fetcher();
      final client = ChhClient(
        fetchers: [fetcher],
        now: tester.binding.clock.now,
      );
      await client.getHtml(ChhUrls.thread(10));
      var visible = true;
      final next = client.getHtml(
        ChhUrls.thread(10, page: 2),
        shouldContinue: () => visible,
      );
      final cancelled = expectLater(next, throwsA(isA<ThreadReadCancelled>()));
      visible = false;
      await tester.pump(const Duration(milliseconds: 300));
      await cancelled;
      expect(fetcher.gets.length, 1);
      expect(client.hasCachedHtml(ChhUrls.thread(10, page: 2)), isFalse);
    },
  );

  testWidgets(
    'a visible reader can join and keep a cancelled background read alive',
    (tester) async {
      final fetcher = _Fetcher();
      final client = ChhClient(
        fetchers: [fetcher],
        now: tester.binding.clock.now,
      );
      await client.getHtml(ChhUrls.thread(10));
      var visible = true;
      final background = client.getHtml(
        ChhUrls.thread(10, page: 2),
        shouldContinue: () => visible,
      );
      final foreground = client.getHtml(ChhUrls.thread(10, page: 2));
      visible = false;
      await tester.pump(const Duration(milliseconds: 300));
      await Future.wait([background, foreground]);
      expect(fetcher.gets.length, 2);
    },
  );

  test(
    'session replacement cancels queued reads and never caches old in-flight data',
    () async {
      final pending = Completer<ChhResponse>();
      final fetcher = _Fetcher()..read = (_) => pending.future;
      final client = ChhClient(
        fetchers: [fetcher],
        threadRequestInterval: Duration.zero,
      );
      final old = client.getHtml(ChhUrls.thread(10));
      final queued = client.getHtml(ChhUrls.thread(10, page: 2));
      final cancelled = expectLater(
        queued,
        throwsA(isA<ThreadReadCancelled>()),
      );
      client.clearCache();
      fetcher.read = null;
      fetcher.body = 'new account';
      final fresh = client.getHtml(ChhUrls.thread(10));
      pending.complete(const ChhResponse(200, 'old account'));
      expect(await old, 'old account');
      await cancelled;
      expect(await fresh, 'new account');
      expect(await client.getHtml(ChhUrls.thread(10)), 'new account');
      expect(fetcher.gets.length, 2);
    },
  );

  testWidgets(
    'failed reads release the queue and retain cooldown without automatic retry',
    (tester) async {
      final fetcher = _Fetcher()..read = (_) async => const ChhResponse(-1, '');
      final client = ChhClient(
        fetchers: [fetcher],
        now: tester.binding.clock.now,
      );
      await expectLater(
        client.getHtml(ChhUrls.thread(10)),
        throwsA(isA<ChhAllBlockedError>()),
      );
      fetcher.read = null;
      final retry = client.getHtml(ChhUrls.thread(10));
      await tester.pump(const Duration(milliseconds: 299));
      expect(fetcher.gets.length, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(await retry, 'cached floors');
      expect(fetcher.gets.length, 2);
    },
  );
}
