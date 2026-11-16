import 'dart:async';

import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/data/rating_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/rating_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const target = RatingEntry(
  user: '没前途的孩子',
  score: '+10',
  reason: '在用，审美很在线 ...',
);
const reason = '在用，审美很在线，更新得也很勤。这是本地合成的完整理由。';
const user = '<a href="space-uid-123.html"><span>没前途的孩子</span></a>';
const score = '<b>邪恶指数 + 10</b>';
const date = '<time>2026-1-5 9:02</time>';
const text = '<span class="reason">$reason</span>';
const rows = {
  'table': '<tr><td>$user</td><td>$score</td><td>$date</td><td>$text</td></tr>',
  'ul/li': '<li>$user $score $date $text</li>',
  'dl/dt/dd': '<dl><dt>$user</dt><dd>$score $date</dd><dd>$text</dd></dl>',
  'dd row': '<dd>$user $score $date $text</dd>',
  'div': '<div class="entry">$user $score $date $text</div>',
  'p': '<p>$user $score $date $text</p>',
};
String page(String kind, String content) {
  final wrapped = switch (kind) {
    'table' => '<table>$content</table>',
    'ul/li' => '<ul>$content</ul>',
    'dd row' => '<dl>$content</dl>',
    _ => content,
  };
  return '<html><head><title>本地评分明细</title></head><body><div id="ct">$wrapped</div></body></html>';
}

PostRating rating({int tid = 10, int pid = 20}) => PostRating(
  tid: tid,
  pid: pid,
  summary: const ['邪恶指数 +10'],
  entries: const [target],
);

class Fake extends ChhFetcher {
  final FutureOr<ChhResponse> Function() reply;
  int calls = 0;
  Fake(this.reply);
  @override
  String get name => 'synthetic-rating-content';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    calls++;
    return reply();
  }
}

List<LogEntry> get logs =>
    AppLog.instance.entries.where((e) => e.tag == 'RATING').toList();

void main() {
  setUp(() => AppLog.instance.clear());
  for (final entry in rows.entries) {
    test('content locates ${entry.key} without a template', () {
      final html = page(entry.key, entry.value);
      expect(parseRatingDetails(html), isEmpty);
      expect(RatingContentPage(html).reasonFor(target), reason);
    });
    test(
      'duplicate same name/score in ${entry.key} is ambiguous even with different prefixes',
      () {
        final duplicate = entry.value.replaceAll(reason, '不同前缀但同名同分值也不能猜测。');
        expect(
          RatingContentPage(
            page(entry.key, '${entry.value}$duplicate'),
          ).reasonFor(target),
          isNull,
        );
      },
    );
  }
  test(
    'separate element preserves inline text, breaks and metadata in reason',
    () {
      const full = '在用，审美很在线，2026-1-5 的版本我也给 +10。\n第二行也要保留。';
      final row = rows['div']!.replaceAll(
        text,
        '<p class="reason">在用，<strong>审美很在线</strong>，2026-1-5 的版本我也给 +10。<br>第二行也要保留。</p>',
      );
      expect(RatingContentPage(page('div', row)).reasonFor(target), full);
    },
  );
  test('mixed text strips observed credit, score and several date formats', () {
    for (final time in [
      '2026-1-5 9:02',
      '2026/01/05 09:02:03',
      '2026.1.5',
      '2026年1月5日 9:02',
    ]) {
      final row = '<li>$user 邪恶指数 + 10 $time $reason</li>';
      expect(RatingContentPage(page('ul/li', row)).reasonFor(target), reason);
    }
  });
  test(
    'header username and different scores do not contaminate matching row',
    () {
      final html = page(
        'div',
        '<nav>$user</nav>${rows['div']} '
            '${rows['div']!.replaceAll('+ 10', '+5')}',
      );
      expect(RatingContentPage(html).reasonFor(target), reason);
    },
  );
  test('negative and unicode minus scores match exactly', () {
    const negative = RatingEntry(
      user: '没前途的孩子',
      score: '-10',
      reason: '在用，审美很在线 ...',
    );
    expect(
      RatingContentPage(
        page('div', rows['div']!.replaceAll('+ 10', '− 10')),
      ).reasonFor(negative),
      reason,
    );
  });
  test('reason dates, scores and breaks survive after the timestamp', () {
    for (final parsedReason in [
      '2026-11-15',
      '2026-11-15 的更新不错，邪恶指数 +10\n保留第二行 ...',
    ]) {
      final row = rows['div']!.replaceAll(reason, parsedReason);
      expect(
        RatingContentPage(page('div', row)).reasonFor(target),
        parsedReason,
      );
    }
  });
  test('split score markup still identifies the reason', () {
    final row = rows['div']!.replaceAll(score, '<b>邪恶指数 <i>+</i><i>10</i></b>');
    expect(RatingContentPage(page('div', row)).reasonFor(target), reason);
  });
  for (final parsedReason in [
    '不同前缀的理由。',
    '在用，审美很在线 ...',
    '在用，审美很在线，很长但仍然…',
    '在用，审美很在线',
    '短',
    '',
  ]) {
    for (final entry in rows.entries) {
      test('${entry.key} returns parsed reason unchanged: $parsedReason', () {
        expect(
          RatingContentPage(
            page(entry.key, entry.value.replaceAll(reason, parsedReason)),
          ).reasonFor(target),
          parsedReason,
        );
      });
    }
  }
  test('preserves outer reason including dots after a nested fragment', () {
    final row = rows['div']!.replaceAll(reason, '<strong>$reason</strong> ...');
    expect(
      RatingContentPage(page('div', row)).reasonFor(target),
      '$reason ...',
    );
  });
  test('keeps truncated text without appending the full-reason link', () {
    final row = rows['div']!.replaceAll(
      text,
      '<div><p>在用，审美很在线 ...</p><a href="details">查看全部</a></div>',
    );
    expect(
      RatingContentPage(page('div', row)).reasonFor(target),
      target.reason,
    );
  });
  test('diagnostics redact echoed URL and hidden field values', () {
    final html = page(
      'div',
      '<input type="hidden" value="hiddenValue">'
          '<input id="token" value="idValue">'
          '<a href="/?token=urlValue">link</a>'
          '<div>$user $score <span>urlValue hiddenValue idValue</span></div>',
    );
    final log = RatingContentPage(html).diagnostics(target).join();
    for (final secret in ['hiddenValue', 'idValue', 'urlValue']) {
      expect(log, isNot(contains(secret)));
    }
  });
  for (final wrongScore in ['+100', '+10.5', '-10', '+1', '+ 105']) {
    test('rejects different/decimal score $wrongScore', () {
      expect(
        RatingContentPage(
          page('div', rows['div']!.replaceAll('+ 10', wrongScore)),
        ).reasonFor(target),
        isNull,
      );
    });
  }
  test('never borrows a score from the adjacent physical row', () {
    expect(
      RatingContentPage(
        page('ul/li', '<li>$user $text</li><li>$score $text</li>'),
      ).reasonFor(target),
      isNull,
    );
  });
  test('never borrows a score/reason from another user in a div list', () {
    for (final link in [
      '<a href="space-uid-456.html">其他用户</a>',
      '<a>其他用户</a>',
    ]) {
      final html = page(
        'div',
        '<div>$user<span>无分值</span></div>'
            '<div>$link $score $text</div>',
      );
      expect(RatingContentPage(html).reasonFor(target), isNull);
    }
  });
  test('message pages and absent identity fail closed', () {
    expect(
      RatingContentPage(
        page('div', '<div id="messagetext">请先登录</div>${rows['div']}'),
      ).reasonFor(target),
      isNull,
    );
    expect(
      RatingContentPage(
        page('div', rows['div']!.replaceAll('没前途的孩子', '其他用户')),
      ).reasonFor(target),
      isNull,
    );
  });
  test(
    'diagnostics have bounded structure and redact secrets before excerpts',
    () {
      final html = page(
        'div',
        '<input name="formhash" value="privateValue">'
            '<script>scriptSecret</script><div class="entry" id="rate">$user $score'
            '<span class="reason">privateValue 敏感值</span>'
            '<span>Cookie: shortSecret</span><span>token=shortToken</span>'
            '<span>https://example.invalid/?formhash=linkSecret</span>'
            '${List.generate(20, (i) => '<i class="extra">child$i</i>').join()}'
            '</div>',
      );
      final messages = RatingContentPage(html).diagnostics(target);
      expect(messages, hasLength(4));
      expect(messages.join().length, lessThanOrEqualTo(1500));
      expect(
        messages[0],
        contains('len=${html.length} title=本地评分明细 user=true score=true'),
      );
      expect(
        messages[1],
        contains('body(1) > div#ct(1) > div.entry#rate(26) > a(1) > span(0)'),
      );
      expect(messages[2], contains('div.entry#rate a:没前途的孩子 | b:邪恶指数 + 10'));
      for (final secret in [
        'privateValue',
        'scriptSecret',
        'shortSecret',
        'shortToken',
        'linkSecret',
        '<input',
        'child19',
      ]) {
        expect(messages.join(), isNot(contains(secret)));
      }
      final huge = page(
        'div',
        '${'<div class="large">' * 100}${rows['div']}${'</div>' * 100}',
      );
      expect(
        RatingContentPage(huge).diagnostics(target).join().length,
        lessThanOrEqualTo(1500),
      );
      expect(
        RatingContentPage('<p>无匹配</p>').diagnostics(target)[0],
        contains('user=false score=false'),
      );
    },
  );
  test(
    'repository keeps standard path first and content success is cached without warnings',
    () async {
      for (final html in [
        page('div', rows['div']!),
        '<table class="list"><tr><td>$user</td><td>$score</td><td>2026-1-5 9:02</td><td>$reason</td></tr></table>',
      ]) {
        final fake = Fake(() => ChhResponse(200, html));
        final repo = RatingRepository(ChhClient(fetchers: [fake]));
        final result = await repo.load(rating());
        expect(result!.reasonFor(target), reason);
        expect(await repo.load(rating()), same(result));
        expect(fake.calls, 1);
        expect(logs, isEmpty);
      }
    },
  );
  for (final linkedUser in [user, '<span>没前途的孩子</span>']) {
    for (final parsedReason in [target.reason!, '改过的短理由', '']) {
      test(
        'four-column table accepts $parsedReason for $linkedUser without logs',
        () async {
          final html =
              '''<table class="list"><tbody><tr>
<td>邪恶指数 +10</td><td>$linkedUser</td><td>2026-11-13 10:00</td>
<td>$parsedReason</td></tr></tbody></table>''';
          expect(parseRatingDetails(html).length, linkedUser == user ? 1 : 0);
          final fake = Fake(() => ChhResponse(200, html));
          final repo = RatingRepository(ChhClient(fetchers: [fake]));
          final result = await repo.load(rating());
          expect(result!.reasonFor(target), parsedReason);
          expect(await repo.load(rating()), same(result));
          expect(fake.calls, 1);
          expect(logs, isEmpty);
        },
      );
    }
  }
  test('an ellipsis-only excerpt does not constrain the parsed reason', () {
    const dots = RatingEntry(user: '没前途的孩子', score: '+10', reason: '...');
    expect(
      RatingContentPage(page('div', rows['div']!)).reasonFor(dots),
      reason,
    );
  });
  test(
    'a standard row plus a nonstandard duplicate remains ambiguous',
    () async {
      final html =
          '''<table class="list"><tbody>
<tr><td>邪恶指数 +10</td><td>$user</td><td>2026-11-13 10:00</td><td>$reason</td></tr>
<tr><td>邪恶指数 +10</td><td><span>没前途的孩子</span></td><td>2026-11-13 10:01</td><td>不同理由 ...</td></tr>
</tbody></table>''';
      expect(parseRatingDetails(html), hasLength(1));
      final repo = RatingRepository(
        ChhClient(fetchers: [Fake(() => ChhResponse(200, html))]),
      );
      expect((await repo.load(rating()))?.reasonFor(target), isNull);
      expect(logs, hasLength(4));
      expect(logs.last.message, contains('rows=2'));
    },
  );
  test('a longer username is not a match for the requested username', () {
    expect(
      RatingContentPage(
        page('div', rows['div']!.replaceAll('没前途的孩子', '没前途的孩子甲')),
      ).reasonFor(target),
      isNull,
    );
  });
  test(
    'same name and score ambiguity is diagnosed without choosing a reason',
    () async {
      final html = page('div', '${rows['div']}${rows['div']}');
      final repo = RatingRepository(
        ChhClient(fetchers: [Fake(() => ChhResponse(200, html))]),
      );
      expect((await repo.load(rating()))?.reasonFor(target), isNull);
      expect(logs, hasLength(4));
      expect(logs.last.message, contains('rows=2'));
    },
  );
  test('login and intercepted message pages have no row diagnostics', () async {
    for (final message in ['请先登录', '访问受限']) {
      final repo = RatingRepository(
        ChhClient(
          fetchers: [
            Fake(
              () => ChhResponse(
                200,
                '<div id="messagetext">$message</div>${rows['div']}',
              ),
            ),
          ],
        ),
      );
      expect((await repo.load(rating()))?.reasonFor(target), isNull);
      expect(logs, isEmpty);
    }
  });
  test(
    'a login page does not consume the thread diagnostic allowance',
    () async {
      var html = '<div id="messagetext">请先登录</div>';
      final repo = RatingRepository(
        ChhClient(fetchers: [Fake(() => ChhResponse(200, html))]),
      );
      await repo.load(rating());
      expect(logs, isEmpty);
      html = '<p>找不到评分行</p>';
      await repo.load(rating(pid: 21));
      expect(logs, hasLength(4));
    },
  );
  test(
    'unresolved diagnostics are WARN once per thread per session, including concurrent floors',
    () async {
      var revision = 0;
      final fake = Fake(
        () => const ChhResponse(
          200,
          '<html><title>未知结构</title><body><div id="ct"><p>无匹配</p></div></body></html>',
        ),
      );
      final client = ChhClient(fetchers: [fake]);
      final repo = RatingRepository(client, sessionRevision: () => revision);
      await Future.wait([repo.load(rating()), repo.load(rating(pid: 21))]);
      expect(logs, hasLength(4));
      expect(logs.every((e) => e.level == LogLevel.warn), isTrue);
      expect(logs.map((e) => e.message.split(' ').first), [
        '1/4',
        '2/4',
        '3/4',
        '4/4',
      ]);
      await repo.load(rating());
      expect(logs, hasLength(4));
      await repo.load(rating(tid: 11));
      expect(logs, hasLength(8));
      revision++;
      client.clearCache();
      await repo.load(rating());
      expect(logs, hasLength(12));
    },
  );
  test(
    'late responses from a prior session emit no diagnostic and do not consume its allowance',
    () async {
      var revision = 0;
      final gate = Completer<ChhResponse>();
      final fake = Fake(() => gate.future);
      final client = ChhClient(fetchers: [fake]);
      final repo = RatingRepository(client, sessionRevision: () => revision);
      final pending = repo.load(rating());
      revision++;
      gate.complete(const ChhResponse(200, '<p>无匹配</p>'));
      expect(await pending, isNull);
      expect(logs, isEmpty);
      client.clearCache();
      await repo.load(rating());
      expect(logs, hasLength(4));
    },
  );
  test('transport errors never produce page diagnostics', () async {
    final fake = Fake(() => const ChhResponse(500, ''));
    final repo = RatingRepository(ChhClient(fetchers: [fake]));
    expect(await repo.load(rating()), isNull);
    expect(logs, isEmpty);
  });
}
