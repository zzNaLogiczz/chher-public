import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/network/chh_session.dart';
import 'package:chh_app/network/direct_fetcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _CookieStore extends PlatformCookieManager {
  _CookieStore()
    : super.implementation(const PlatformCookieManagerCreationParams());

  final values = <String, String>{};
  final events = <String>[];
  final writes = <({String name, String value, String path, int? expires})>[];
  bool acceptsWrites = true;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    expect(url.toString(), ChhUrls.base);
    events.add('read');
    return [
      for (final entry in values.entries)
        Cookie(name: entry.key, value: entry.value),
    ];
  }

  @override
  Future<bool> setCookie({
    required WebUri url,
    required String name,
    required String value,
    String path = '/',
    String? domain,
    int? expiresDate,
    int? maxAge,
    bool? isSecure,
    bool? isHttpOnly,
    HTTPCookieSameSitePolicy? sameSite,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    expect(url.toString(), ChhUrls.base);
    expect(isSecure, isTrue);
    events.add('write');
    writes.add((name: name, value: value, path: path, expires: expiresDate));
    if (acceptsWrites) values[name] = value;
    return acceptsWrites;
  }
}

class _Platform extends InAppWebViewPlatform {
  final _CookieStore store;
  _Platform(this.store);

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => store;
}

class _Transport extends ChhFetcher {
  String page = '<html>cached fixture</html>';
  ChhResponse response = const ChhResponse(
    200,
    '<div id="messagetext">密码验证成功</div>',
  );
  final gets = <Uri>[];
  final posts = <({Uri url, Map<String, String> form})>[];

  @override
  String get name => 'local-password-fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    gets.add(url);
    return ChhResponse(200, page);
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts.add((url: url, form: Map.of(form)));
    return response;
  }
}

String _passwordForm({String prefix = 'fixture_', String? action}) =>
    '''
<script>var cookiepre = '$prefix';</script>
<div id="ct"><h3>本版块需要密码，您必须输入密码</h3>
<form method="post" action="${action ?? 'forum.php?mod=forumdisplay&amp;fid=316&amp;action=pwverify&amp;extra=site'}">
<input name="formhash" value="fresh-formhash" type="hidden">
<input type="password" name="pw">
<button name="loginsubmit" value="true">提交</button>
</form></div>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = _CookieStore();
  const channel = MethodChannel('chh/session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() => InAppWebViewPlatform.instance = _Platform(store));
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    store.values.clear();
    store.events.clear();
    store.writes.clear();
    store.acceptsWrites = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'flushCookies');
      store.events.add('flush');
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'post password is MD5, persisted before refresh and restored cold',
    () async {
      final fake = _Transport();
      final direct = DirectFetcher();
      final client = ChhClient(fetchers: [fake, direct]);
      final session = ChhSession(client);
      final repository = ForumRepository(client, session: session);
      final url = ChhUrls.thread(42);
      await client.getHtml(url);
      await client.getHtml(url);
      expect(fake.gets, hasLength(1));

      await repository.unlockPost(
        pid: 1001,
        password: 'abc',
        cookiePrefix: 'page_',
      );
      expect(store.events, ['write', 'flush', 'read']);
      expect(store.writes.single.name, 'page_postpw_1001');
      expect(store.writes.single.value, '900150983cd24fb0d6963f7d28e17f72');
      expect(store.writes.single.path, '/');
      expect(
        DateTime.fromMillisecondsSinceEpoch(store.writes.single.expires!),
        isA<DateTime>().having(
          (date) => date.difference(DateTime.now()).inDays,
          'days until expiry',
          inInclusiveRange(29, 30),
        ),
      );
      expect(
        direct.sessionCookies?['page_postpw_1001'],
        store.writes.single.value,
      );
      await client.getHtml(url);
      expect(fake.gets, hasLength(2));
      final restarted = ChhSession(client);
      await restarted.refresh();
      expect(restarted.cookies['page_postpw_1001'], store.writes.single.value);
      expect(
        direct.sessionCookies?['page_postpw_1001'],
        store.writes.single.value,
      );
      session.dispose();
      restarted.dispose();
      await direct.dispose();
    },
  );

  test(
    'failed Cookie write does not flush or publish the unlocked session',
    () async {
      store.acceptsWrites = false;
      final session = ChhSession(ChhClient(fetchers: []));
      await expectLater(
        session.setSiteCookie('fixture_postpw_1', 'value'),
        throwsStateError,
      );
      expect(store.events, ['write']);
      expect(session.cookies, isEmpty);
      session.dispose();
    },
  );

  test(
    'prefix uses saltkey then auth and never guesses from unrelated cookies',
    () {
      final session = ChhSession(ChhClient(fetchers: []));
      session.cookies = {'auth_auth': 'x', 'salt_saltkey': 'y'};
      expect(session.cookiePrefix, 'salt_');
      session.cookies = {'auth_auth': 'x'};
      expect(session.cookiePrefix, 'auth_');
      session.cookies = {'auth': 'x', 'saltkey': 'y', 'unrelated': 'z'};
      expect(session.cookiePrefix, isNull);
      session.dispose();
    },
  );

  test(
    'forum submit follows current form and persists exact Set-Cookie value',
    () async {
      final fake = _Transport()..page = _passwordForm();
      fake.response = const ChhResponse(
        200,
        '<div id="messagetext">密码验证成功</div>',
        setCookies: [
          'unrelated=x; Path=/',
          'fixture_fidpw316=%e6%b5%8b%20x; Path=/',
        ],
      );
      final client = ChhClient(fetchers: [fake]);
      final session = ChhSession(client)..cookies = {'session_saltkey': 'x'};
      final repository = ForumRepository(client, session: session);
      expect(await repository.verifyForumPassword(316, '测 x'), isTrue);
      expect(fake.gets.single, ChhUrls.threadList(316));
      expect(fake.posts.single.url.queryParameters, {
        'mod': 'forumdisplay',
        'fid': '316',
        'action': 'pwverify',
        'extra': 'site',
      });
      expect(fake.posts.single.form, {
        'formhash': 'fresh-formhash',
        'pw': '测 x',
        'loginsubmit': 'true',
      });
      expect(store.writes.single.name, 'fixture_fidpw316');
      expect(store.writes.single.value, '%e6%b5%8b%20x');
      final restarted = ChhSession(client);
      await restarted.refresh();
      expect(restarted.cookies['fixture_fidpw316'], '%e6%b5%8b%20x');
      session.dispose();
      restarted.dispose();
    },
  );

  test('forum falls back to UTF-8 URL encoding and session prefix', () async {
    final fake = _Transport()
      ..page = _passwordForm().replaceFirst(
        "<script>var cookiepre = 'fixture_';</script>",
        '',
      )
      ..response = const ChhResponse(200, '<div id="threadlist">内容</div>');
    store.values['session_saltkey'] = 'x';
    final client = ChhClient(fetchers: [fake]);
    final session = ChhSession(client);
    await session.refresh();
    final repository = ForumRepository(client, session: session);
    expect(await repository.verifyForumPassword(316, '中文 +%'), isTrue);
    expect(store.writes.single.name, 'session_fidpw316');
    expect(store.writes.single.value, Uri.encodeComponent('中文 +%'));
    session.dispose();
  });

  test(
    'wrong passwords and page failures never persist a forum password',
    () async {
      for (final response in [
        const ChhResponse(200, '<div id="messagetext">密码不正确</div>'),
        ChhResponse(200, _passwordForm()),
        const ChhResponse(200, '<div id="messagetext">请先登录</div>'),
        const ChhResponse(567, 'blocked'),
        const ChhResponse(500, '<html>failed</html>'),
      ]) {
        final fake = _Transport()
          ..page = _passwordForm()
          ..response = response;
        final repository = ForumRepository(ChhClient(fetchers: [fake]));
        expect(await repository.verifyForumPassword(316, 'wrong'), isFalse);
      }
      expect(store.writes, isEmpty);
    },
  );

  test(
    'unknown prefix reports failure instead of inventing a cookie name',
    () async {
      final fake = _Transport()
        ..page = _passwordForm().replaceFirst(
          "<script>var cookiepre = 'fixture_';</script>",
          '',
        );
      final repository = ForumRepository(ChhClient(fetchers: [fake]));
      await expectLater(
        repository.verifyForumPassword(316, 'fixture'),
        throwsStateError,
      );
      await expectLater(
        repository.unlockPost(pid: 1, password: 'fixture', cookiePrefix: ''),
        throwsStateError,
      );
      expect(store.writes, isEmpty);
    },
  );

  test('foreign or mismatched forum action is not submitted', () async {
    for (final action in [
      'https://other.invalid/forum.php?fid=316&amp;action=pwverify',
      'forum.php?fid=99&amp;action=pwverify',
    ]) {
      final fake = _Transport()..page = _passwordForm(action: action);
      final repository = ForumRepository(ChhClient(fetchers: [fake]));
      expect(await repository.verifyForumPassword(316, 'fixture'), isFalse);
      expect(fake.posts, isEmpty);
    }
    expect(store.writes, isEmpty);
  });
}
