import 'dart:async';
import 'dart:io';

import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fetcher extends ChhFetcher {
  _Fetcher(this.name, this.response);
  @override
  final String name;
  ChhResponse response;
  int gets = 0;
  int posts = 0;
  Future<ChhResponse>? pending;

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    gets++;
    if (pending != null) return pending!;
    return response;
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts++;
    return response;
  }
}

String document(String content, {String title = 'fixture'}) =>
    '<!doctype html><html><head><title>$title</title></head>'
    '<body>$content</body></html>';

void main() {
  final url = Uri.parse('https://www.chiphell.com/forum.php?token=SECRET');
  final good = ChhResponse(200, document('<div id="ct">正常论坛</div>'));

  for (final content in [
    '<script>document.cookie="EO_Bot_Ssid=BODY_COOKIE";</script>',
    '<p>含有非法字符</p>',
    '<p>browser verification BODY_SENTINEL</p>',
    '<p>论坛维护中，请稍后访问</p>',
  ]) {
    test(
      'GET challenge is not cached or observed and falls back: $content',
      () async {
        AppLog.instance.clear();
        final direct = _Fetcher(
          'direct',
          ChhResponse(
            200,
            document(
              content,
              title: 'Checking https://example.test/?cookie=TITLE_SECRET',
            ),
          ),
        );
        final fallback = _Fetcher('fallback', good);
        var observations = 0;
        final client = ChhClient(fetchers: [direct, fallback])
          ..htmlObserver = (_) {
            observations++;
            return true;
          };
        await expectLater(
          client.getHtml(url, fallback: false),
          throwsA(isA<ChhAllBlockedError>()),
        );
        expect(fallback.gets, 0);
        expect(observations, 0);
        expect(await client.getHtml(url), good.body);
        expect(direct.gets, 2);
        expect(fallback.gets, 1);
        expect(observations, 1);
      },
    );
  }

  test(
    'unknown document falls back and only the usable response enters cache',
    () async {
      AppLog.instance.clear();
      final direct = _Fetcher(
        'direct',
        ChhResponse(
          200,
          document(
            '<script>const cookie="BODY_COOKIE";</script><p>BODY_SENTINEL</p>',
            title: 'Checking https://example.test/?cookie=TITLE_SECRET',
          ),
        ),
      );
      final fallback = _Fetcher('fallback', good);
      final observed = <String>[];
      final client = ChhClient(fetchers: [direct, fallback])
        ..htmlObserver = (html) {
          observed.add(html);
          return true;
        };
      await expectLater(
        client.getHtml(url, fallback: false),
        throwsA(isA<ChhAllBlockedError>()),
      );
      expect(fallback.gets, 0);
      expect(await client.getHtml(url), good.body);
      expect(
        direct.gets,
        2,
        reason: 'failed direct-only checks must not poison cache',
      );
      expect(fallback.gets, 1);
      expect(observed, [good.body]);
      expect(await client.getHtml(url), good.body);
      expect(direct.gets, 2);
      expect(fallback.gets, 1);
      final logs = AppLog.instance.dump();
      expect(logs, contains('title=Checking [URL]'));
      for (final secret in [
        'SECRET',
        'TITLE_SECRET',
        'BODY_COOKIE',
        'BODY_SENTINEL',
      ]) {
        expect(logs, isNot(contains(secret)));
      }
    },
  );

  for (final content in [
    '<div id="ct">游客或空列表</div>',
    '<div id="messagetext">没有权限</div>',
    '<div id="messagelogin">请先登录</div>',
    '<form id="loginform_LFixture"></form>',
    '<div class="fl bm">论坛</div>',
    '<table><tbody id="normalthread_1"><tr><td>标题</td></tr></tbody></table>',
  ]) {
    test('short legitimate Discuz document remains usable: $content', () async {
      final direct = _Fetcher('direct', ChhResponse(403, document(content)));
      final fallback = _Fetcher('fallback', good);
      final client = ChhClient(fetchers: [direct, fallback]);
      expect(await client.getHtml(url), direct.response.body);
      expect(fallback.gets, 0);
    });
  }

  test(
    'AJAX fragments and unrelated HTML keep their existing protocol',
    () async {
      final response = ChhResponse(200, document('<p>AJAX result</p>'));
      final fetcher = _Fetcher('direct', response);
      final client = ChhClient(fetchers: [fetcher]);
      expect(await client.getAjaxHtml(url), response.body);
      expect(
        await client.getHtml(Uri.parse('https://example.test/forum.php')),
        response.body,
      );
      expect(
        await client.getHtml(Uri.parse('https://www.chiphell.com/fixture')),
        response.body,
      );
      fetcher.response = const ChhResponse(200, '<div>fragment</div>');
      expect(await client.getHtml(url), '<div>fragment</div>');
    },
  );

  test(
    'late HTTP 200 maintenance document cannot replace a recovered page',
    () async {
      final maintenance = Completer<ChhResponse>();
      final direct = _Fetcher('direct', good)..pending = maintenance.future;
      final observed = <String>[];
      final client = ChhClient(fetchers: [direct])
        ..htmlObserver = (html) {
          observed.add(html);
          return true;
        };
      final old = client.getHtml(url, fallback: false);
      final rejected = expectLater(old, throwsA(isA<ChhAllBlockedError>()));
      direct.pending = null;
      expect(await client.getHtml(url, refresh: true), good.body);
      maintenance.complete(
        ChhResponse(200, document('<p>论坛维护中，请稍后访问</p>', title: '系统维护')),
      );
      await rejected;
      expect(await client.getHtml(url), good.body);
      expect(direct.gets, 2);
      expect(observed, [good.body]);
    },
  );

  test('normal posts can quote bot and validation error strings', () async {
    for (final marker in ['ct', 'postlist']) {
      final response = ChhResponse(
        200,
        document('<div id="$marker">EO_Bot_Ssid 含有非法字符</div>'),
      );
      final client = ChhClient(fetchers: [_Fetcher('direct', response)]);
      expect(await client.getHtml(url), response.body);
    }
  });

  test('existing full-page fixtures keep their normal structures', () {
    for (final name in [
      'forum_index',
      'guide',
      'search',
      'thread_list',
      'thread',
      'login',
    ]) {
      final body = File('test_data/${name}_synthetic.html').readAsStringSync();
      expect(
        ChhResponse(200, body).getPageRejection(url),
        isNull,
        reason: name,
      );
    }
  });

  test(
    'unknown full documents do not change accepted POST retry semantics',
    () async {
      final direct = _Fetcher(
        'direct',
        ChhResponse(200, document('<p>accepted</p>')),
      );
      final fallback = _Fetcher('fallback', good);
      final client = ChhClient(fetchers: [direct, fallback]);
      expect(
        (await client.postForm(url, {'message': 'fixture'})).body,
        direct.response.body,
      );
      expect(direct.posts, 1);
      expect(fallback.posts, 0);
    },
  );
}
