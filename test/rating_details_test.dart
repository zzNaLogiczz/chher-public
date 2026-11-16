import 'dart:async';
import 'dart:io';

import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/blocked_post_projection.dart';
import 'package:chh_app/data/rating_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/rating_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';

final fixture = File(
  'test_data/rating_details_synthetic.html',
).readAsStringSync();
const rating = PostRating(tid: 10, pid: 20, summary: [], entries: []);
const entry = RatingEntry(user: '合成用户甲', score: '+10', reason: '在用 ...');

class _Fake extends ChhFetcher {
  final FutureOr<ChhResponse> Function(Uri) reply;
  final requests = <Uri>[];
  final requestHeaders = <Map<String, String>>[];
  _Fake(this.reply);
  @override
  String get name => 'rating-fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests.add(url);
    requestHeaders.add({...?headers});
    expect(headers?['Referer'], ChhUrls.base);
    return reply(url);
  }
}

String threadHtml(String href, {bool adjacent = false}) =>
    '''
<div id="post_20"><table id="pid20"><tr><td>
<div class="authi"><strong><a href="space-uid-1.html">作者</a></strong></div>
<td id="postmessage_20">正文</td></tr></table>
<dl id="ratelog_20"><table class="ratl"><thead><tr><th>邪恶指数 +10</th></tr></thead>
<tbody class="ratl_l"><tr><td><a href="space-uid-101.html">合成用户甲</a></td><td>+10</td><td>在用 ...</td></tr></tbody></table>
${adjacent ? '' : '<a href="$href">查看全部评分</a>'}</dl>
${adjacent ? '<a href="$href">查看全部评分</a>' : ''}</div>''';

void main() {
  test(
    'missing details link requests the forum ratings page without AJAX',
    () async {
      final fake = _Fake((_) => ChhResponse(200, fixture));
      final repo = RatingRepository(ChhClient(fetchers: [fake]));
      await repo.load(rating);
      expect(
        fake.requests.single.toString(),
        'https://www.chiphell.com/forum.php?mod=misc&action=viewratings&tid=10&pid=20',
      );
      expect(fake.requestHeaders.single, {'Referer': ChhUrls.base});
    },
  );

  for (final text in ['在用 ...', '在用...', '在用…', '在用 ...  ']) {
    test('recognizes server marker: $text', () {
      expect(isRatingReasonTruncated(text), isTrue);
    });
  }
  test('does not treat ordinary long text or internal dots as truncated', () {
    for (final text in [null, '', '很长的完整附言不会触发请求', '... 后面还有全文', '两个点..']) {
      expect(isRatingReasonTruncated(text), isFalse);
    }
  });

  test(
    'synthetic X3 viewratings extracts identity, credit, score, time and reason',
    () {
      final rows = parseRatingDetails(fixture);
      expect(rows, hasLength(3));
      expect(rows.first.user, '合成用户甲');
      expect(rows.first.uid, '101');
      expect(rows.first.score, '+ 10');
      expect(rows.first.credit, '邪恶指数 分');
      expect(rows.first.timeRaw, '2026-11-15 09:12');
      expect(rows.first.reason, contains('。\n第二行'));
      expect(rows[1].reason, '另一条完整理由 & 本地数据。');
      expect(rows[2].reason, isEmpty);
      expect(RatingDetails(rows).reasonFor(entry), rows.first.reason);
    },
  );

  test('tolerates username first, refuses malformed rows and login pages', () {
    final html = '''<table class="list"><tr>
<td><a href="space-uid-101.html">合成用户甲</a></td><td>+10 邪恶指数</td>
<td>2026-11-15 10:00</td><td>全文</td></tr>
<tr><td>邪恶指数 +5</td><td>没有用户名链接</td><td>2026-11-15 10:00</td><td>错误</td></tr>
<tr><td>未知分数</td><td><a href="space-uid-101.html">合成用户甲</a></td><td>2026-11-15 10:00</td><td>错误</td></tr></table>''';
    expect(parseRatingDetails(html), hasLength(1));
    expect(RatingDetails(parseRatingDetails(html)).reasonFor(entry), '全文');
    expect(
      parseRatingDetails('<div id="messagetext">请先登录</div>$fixture'),
      isEmpty,
    );
    expect(parseRatingDetails('<p>changed template</p>'), isEmpty);
  });

  test('pairs only unique username plus value, never guesses a reason', () {
    final rows = parseRatingDetails(fixture);
    expect(
      RatingDetails(
        rows,
      ).reasonFor(const RatingEntry(user: '合成用户甲', score: '+5')),
      isNull,
    );
    expect(
      RatingDetails(
        rows,
      ).reasonFor(const RatingEntry(user: '其他用户', score: '+10')),
      isNull,
    );
    expect(RatingDetails([...rows, rows.first]).reasonFor(entry), isNull);
  });

  for (final reason in ['在用 ...', '仍然 ...', '很短', '不同前缀的理由…', '']) {
    test('standard table returns the unique row reason unchanged: $reason', () {
      final html = '''<table class="list"><tbody><tr>
<td>邪恶指数 +10</td><td><a href="space-uid-101.html">合成用户甲</a></td>
<td>2026-11-13 10:00</td><td>$reason</td></tr></tbody></table>''';
      expect(RatingDetails(parseRatingDetails(html)).reasonFor(entry), reason);
    });
  }

  test('reason matching preserves even whitespace without validation', () {
    const reason = '  原文 ...  ';
    expect(
      const RatingDetails([
        RatingEntry(user: '合成用户甲', score: '10', reason: reason),
      ]).reasonFor(entry),
      reason,
    );
  });

  test(
    'thread parser keeps observed floor URL, constructs missing or untrusted fallback',
    () {
      for (final path in [
        'misc.php?mod=viewratings',
        'forum.php?mod=misc&amp;action=viewratings',
      ]) {
        final url = '$path&amp;tid=10&amp;pid=20&amp;extra=kept';
        for (final adjacent in [true, false]) {
          final parsed = parseThread(
            threadHtml(url, adjacent: adjacent),
            tid: 10,
          ).posts.single.rating!;
          expect(parsed.tid, 10);
          expect(parsed.pid, 20);
          expect(parsed.detailsUrl!.queryParameters['extra'], 'kept');
        }
      }
      for (final url in [
        '',
        'https://example.com/misc.php?mod=viewratings&amp;tid=10&amp;pid=20',
        'misc.php?mod=viewratings&amp;tid=10&amp;pid=99',
      ]) {
        final parsed = parseThread(
          threadHtml(url),
          tid: 10,
        ).posts.single.rating!;
        expect(parsed.detailsUrl, ChhUrls.viewRatings(10, 20));
      }
    },
  );

  test('blocked display projection preserves rating source identity', () {
    final post = parseThread(threadHtml(''), tid: 10).posts.single;
    final projected = projectBlockedPost(
      post,
      tid: 10,
      knownPosts: {20: post},
      isBlocked: (_) => true,
    );
    expect(projected.rating!.entries, isEmpty);
    expect(projected.rating!.tid, 10);
    expect(projected.rating!.pid, 20);
    expect(projected.rating!.detailsUrl, ChhUrls.viewRatings(10, 20));
  });

  test(
    'demand loading shares one floor request and session cache after client TTL',
    () async {
      final gate = Completer<ChhResponse>();
      final fake = _Fake((_) => gate.future);
      final client = ChhClient(fetchers: [fake]);
      final repo = RatingRepository(client);
      expect(repo.cached(rating), isNull);
      expect(repo.hasAttempted(rating), isFalse);
      expect(fake.requests, isEmpty);
      final first = repo.load(rating);
      final second = repo.load(rating);
      expect(identical(first, second), isTrue);
      expect(repo.isLoading(rating), isTrue);
      gate.complete(ChhResponse(200, fixture));
      final result = await first;
      expect(result!.reasonFor(entry), contains('合成的完整附言'));
      expect(await second, same(result));
      expect(repo.cached(rating), same(result));
      expect(repo.isLoading(rating), isFalse);
      client.clearCache();
      expect(await repo.load(rating), same(result));
      expect(fake.requests, hasLength(1));
    },
  );

  test(
    'client HTML cache is reused and valid observed URL is preferred',
    () async {
      final url = Uri.parse(
        '${ChhUrls.base}/forum.php?mod=misc&action=viewratings&tid=10&pid=20&extra=keep',
      );
      final fake = _Fake((_) => ChhResponse(200, fixture));
      final client = ChhClient(fetchers: [fake]);
      await client.getHtml(url);
      final repo = RatingRepository(client);
      await repo.load(
        PostRating(
          tid: 10,
          pid: 20,
          detailsUrl: url,
          summary: const [],
          entries: const [],
        ),
      );
      expect(fake.requests, [url]);
    },
  );

  for (final response in [
    const ChhResponse(500, ''),
    const ChhResponse(200, '<div id="messagetext">请先登录</div>'),
    const ChhResponse(200, '<p>unrecognized details</p>'),
  ]) {
    test(
      'failed/unparseable floor stays in cooldown: ${response.body}',
      () async {
        final fake = _Fake((_) => response);
        final client = ChhClient(fetchers: [fake]);
        final repo = RatingRepository(client);
        expect(await repo.load(rating), isNull);
        expect(repo.hasAttempted(rating), isTrue);
        expect(repo.isLoading(rating), isFalse);
        client.clearCache();
        expect(await repo.load(rating), isNull);
        expect(fake.requests, hasLength(1));
      },
    );
  }

  test(
    'session change clears results and drops late old-account responses',
    () async {
      var revision = 0;
      final old = Completer<ChhResponse>();
      final fresh = Completer<ChhResponse>();
      final fake = _Fake((_) => revision == 0 ? old.future : fresh.future);
      final client = ChhClient(fetchers: [fake]);
      final repo = RatingRepository(client, sessionRevision: () => revision);
      final oldRequest = repo.load(rating);
      revision++;
      client
          .clearCache(); // ChhSession clears transport cache when auth changes.
      expect(repo.hasAttempted(rating), isFalse);
      final newRequest = repo.load(rating);
      old.complete(ChhResponse(200, fixture));
      expect(await oldRequest, isNull);
      expect(repo.cached(rating), isNull);
      expect(repo.isLoading(rating), isTrue);
      fresh.complete(ChhResponse(200, fixture.replaceAll('完整附言', '新会话附言')));
      expect((await newRequest)!.reasonFor(entry), contains('新会话附言'));
      expect(fake.requests, hasLength(2));
    },
  );
  test(
    'invalid links fall back to the same floor and unknown IDs have no URL',
    () async {
      final fake = _Fake((_) => ChhResponse(200, fixture));
      final repo = RatingRepository(ChhClient(fetchers: [fake]));
      for (final raw in [
        'https://example.com/misc.php?mod=viewratings&tid=10&pid=20',
        '${ChhUrls.base}/misc.php?mod=viewratings&tid=10&pid=21',
        '${ChhUrls.base}:1234/misc.php?mod=viewratings&tid=10&pid=20',
        '${ChhUrls.base}/forum.php?mod=misc&action=rate&tid=10&pid=20',
      ]) {
        final value = PostRating(
          tid: 10,
          pid: 20,
          summary: const [],
          entries: const [],
          detailsUrl: Uri.parse(raw),
        );
        expect(repo.detailsUrl(value), ChhUrls.viewRatings(10, 20));
      }
      const missing = PostRating(summary: [], entries: []);
      expect(repo.detailsUrl(missing), isNull);
      expect(await repo.load(missing), isNull);
      expect(fake.requests, isEmpty);
    },
  );

  test(
    'each floor is independent and opening one does not prefetch another',
    () async {
      final fake = _Fake((_) => ChhResponse(200, fixture));
      final repo = RatingRepository(ChhClient(fetchers: [fake]));
      const other = PostRating(tid: 10, pid: 21, summary: [], entries: []);
      await repo.load(rating);
      expect(repo.hasAttempted(other), isFalse);
      expect(fake.requests, hasLength(1));
      await repo.load(other);
      expect(fake.requests, [
        ChhUrls.viewRatings(10, 20),
        ChhUrls.viewRatings(10, 21),
      ]);
    },
  );
  test('malformed decimal or multiple scores cannot match an integer row', () {
    for (final score in ['+10.5', '+10 +5']) {
      final html = fixture.replaceFirst('+ 10', score);
      expect(RatingDetails(parseRatingDetails(html)).reasonFor(entry), isNull);
    }
  });
}
