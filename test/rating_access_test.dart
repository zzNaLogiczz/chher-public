import 'package:chh_app/data/post_interaction_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/post_interaction.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/post_action_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'post_interaction_test.dart' as fixture;

class _ReadOnly extends ChhFetcher {
  final String Function(Uri, int) response;
  final urls = <Uri>[];
  _ReadOnly(this.response);
  @override
  String get name => 'rating-fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    urls.add(url);
    expect(headers?['X-Requested-With'], 'XMLHttpRequest');
    return ChhResponse(200, response(url, urls.length));
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) =>
      throw StateError('Permission checks must never POST');
}

const _denial =
    '<root><![CDATA[<div id="messagetext">抱歉，您所在的用户组(能天使)无法进行此操作</div>]]></root>';

void main() {
  test(
    'target denial does not spread and explicit retry reads fresh form',
    () async {
      final transport = _ReadOnly(
        (url, count) => count == 1 ? _denial : fixture.rateForm(),
      );
      final repo = PostInteractionRepository(
        ChhClient(fetchers: [transport]),
        sessionIdentity: () => '42',
      );
      await expectLater(
        repo.rateForm(tid: 10, pid: 21),
        throwsA(
          isA<PostInteractionException>().having(
            (e) => e.result.kind,
            'kind',
            PostResultKind.permissionDenied,
          ),
        ),
      );
      expect((await repo.rateForm(tid: 10, pid: 20)).sessionIdentity, '42');
      expect((await repo.rateForm(tid: 10, pid: 21)).pid, 21);
      expect(transport.urls.length, 3);
    },
  );

  test(
    'authenticated cookies with pending UID are retryable, not logged out',
    () async {
      final transport = _ReadOnly((_, _) => fixture.rateForm());
      String? uid;
      final repo = PostInteractionRepository(
        ChhClient(fetchers: [transport]),
        loggedIn: () => true,
        sessionIdentity: () => uid,
      );
      await expectLater(
        repo.rateForm(tid: 10, pid: 20),
        throwsA(
          isA<PostInteractionException>().having(
            (e) => e.result.kind,
            'kind',
            PostResultKind.failed,
          ),
        ),
      );
      expect(transport.urls, isEmpty);
      uid = '42';
      expect((await repo.rateForm(tid: 10, pid: 20)).sessionIdentity, '42');
      expect(transport.urls.length, 1);
    },
  );

  test('guest is rejected before any GET', () async {
    final transport = _ReadOnly((_, _) => fixture.rateForm());
    final repo = PostInteractionRepository(
      ChhClient(fetchers: [transport]),
      sessionIdentity: () => null,
    );
    await expectLater(
      repo.rateForm(tid: 10, pid: 20),
      throwsA(
        isA<PostInteractionException>().having(
          (e) => e.result.kind,
          'kind',
          PostResultKind.loginRequired,
        ),
      ),
    );
    expect(transport.urls, isEmpty);
  });

  test(
    'missing form is a read failure rather than a permission denial',
    () async {
      final repo = PostInteractionRepository(
        ChhClient(
          fetchers: [
            _ReadOnly(
              (_, _) => '<root><![CDATA[<p>unknown template</p>]]></root>',
            ),
          ],
        ),
      );
      await expectLater(
        repo.rateForm(tid: 10, pid: 20),
        throwsA(
          isA<PostInteractionException>().having(
            (e) => e.result.kind,
            'kind',
            PostResultKind.failed,
          ),
        ),
      );
    },
  );

  test('AJAX CDATA and XML escaped HTML preserve the actual form', () {
    final plain = interactionHtml(fixture.rateForm());
    for (final raw in [
      plain,
      '<root><![CDATA[$plain]]></root>',
      '<root><![CDATA[${plain.substring(0, 100)}]]><![CDATA[${plain.substring(100)}]]></root>',
      '<root>${plain.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</root>',
    ]) {
      expect(
        parsePostRateForm(
          raw,
          tid: 10,
          pid: 20,
          pageUrl: interactionPageUrl(PostInteractionKind.rating, 10, 20),
        ),
        isNotNull,
      );
    }
  });

  test('ReSource document-scoped rating fragment remains usable', () async {
    final fragment = interactionHtml(
      fixture.rateForm(),
    ).replaceFirst(RegExp(r'<form[^>]*>'), '').replaceFirst('</form>', '');
    final transport = _ReadOnly((_, _) => '<root><![CDATA[$fragment]]></root>');
    final form = await PostInteractionRepository(
      ChhClient(fetchers: [transport]),
    ).rateForm(tid: 10, pid: 20);
    expect(form.formhash, 'fresh');
    expect(form.evilScoreType!.remaining, 4);
    expect(form.action.queryParameters['action'], 'rate');
    expect(
      transport.urls.single.queryParameters,
      containsPair('handlekey', 'rate'),
    );
    expect(
      transport.urls.single.queryParameters,
      containsPair('ajaxtarget', 'fwin_content_rate'),
    );
    expect(
      transport.urls.single.queryParameters.containsKey('formhash'),
      isFalse,
    );
  });

  test('fragment fallback cannot bypass an explicit invalid form action', () {
    for (final raw in [
      fixture.rateForm().replaceFirst(
        'action="forum.php?',
        'action="https://elsewhere.test/forum.php?',
      ),
      fixture.rateForm().replaceFirst('action=rate', 'action=rate&amp;pid=999'),
    ]) {
      expect(
        parsePostRateForm(
          raw,
          tid: 10,
          pid: 20,
          pageUrl: interactionPageUrl(PostInteractionKind.rating, 10, 20),
        ),
        isNull,
      );
    }
  });

  test(
    'login structure and temporary errors cannot become permission denial',
    () {
      expect(
        parseInteractionPageError(
          '<form id="loginform"></form><div class="alert_error">无权执行此操作</div>',
        )!.kind,
        PostResultKind.loginRequired,
      );
      expect(
        parseInteractionPageError(
          '<div class="alert_error">操作太频繁，暂时不能评分，请稍后再试</div>',
        )!.kind,
        PostResultKind.throttled,
      );
    },
  );

  test('login, self, quota, group denial remain distinct', () {
    for (final entry in {
      '<div id="messagelogin"></div>': PostResultKind.loginRequired,
      '<form id="loginform"></form>': PostResultKind.loginRequired,
      '<div class="alert_error">请先登录</div>': PostResultKind.loginRequired,
      '<div class="alert_error">抱歉，您不能给自己发表的帖子评分</div>':
          PostResultKind.selfRating,
      '<div class="alert_error">今日评分额度已用完</div>':
          PostResultKind.ratingQuotaExhausted,
      _denial: PostResultKind.permissionDenied,
    }.entries) {
      expect(parseInteractionPageError(entry.key)?.kind, entry.value);
    }
  });
}
