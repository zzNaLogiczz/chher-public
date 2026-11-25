import 'dart:async';
import 'dart:io';

import 'package:chh_app/core/accounts.dart';
import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/network/chh_session.dart';
import 'package:chh_app/network/direct_fetcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

const _accountsChannel = MethodChannel('chh/accounts');
const _sessionChannel = MethodChannel('chh/session');
final _now = DateTime(2026, 11, 23, 12);
final _forum = ChhUrls.forumIndex();
final _guest = File(
  'test_data/account_guest_synthetic.html',
).readAsStringSync();

String _member(String uid, {String? name, int notices = 0}) =>
    '<html><body><div id="hd"><div id="um"><strong class="vwmy">'
    '<a href="space-uid-$uid.html">${name ?? '用户 $uid'}</a></strong>'
    '<a id="myprompt">提醒 $notices</a></div></div></body></html>';

ResponseBody _response(
  String html, {
  int status = 200,
  List<String> cookies = const [],
}) => ResponseBody.fromString(html, status, headers: {'set-cookie': cookies});

class _Cookies extends PlatformCookieManager {
  _Cookies()
    : super.implementation(const PlatformCookieManagerCreationParams());

  String? auth;
  int reads = 0;
  final deletions = <(String, String?)>[];
  int allDeletions = 0;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    reads++;
    return [
      if (auth case final value?) ...[
        Cookie(name: 'test_auth', value: value),
        Cookie(name: 'test_saltkey', value: 'fixture-salt'),
      ],
    ];
  }

  @override
  Future<bool> deleteCookies({
    required WebUri url,
    String? domain,
    String path = '/',
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    deletions.add((url.toString(), domain));
    auth = null;
    return true;
  }

  @override
  Future<bool> deleteAllCookies() async {
    allDeletions++;
    auth = null;
    return true;
  }
}

class _WebStorage extends PlatformWebStorageManager {
  _WebStorage()
    : super.implementation(const PlatformWebStorageManagerCreationParams());

  int deletes = 0;

  @override
  Future<void> deleteAllData() async => deletes++;
}

class _Platform extends InAppWebViewPlatform {
  _Platform(this.cookies, this.storage);

  final _Cookies cookies;
  final _WebStorage storage;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => cookies;

  @override
  PlatformWebStorageManager createPlatformWebStorageManager(
    PlatformWebStorageManagerCreationParams params,
  ) => storage;
}

class _DirectAdapter implements HttpClientAdapter {
  late FutureOr<ResponseBody> Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

class _MemberFetcher extends ChhFetcher {
  _MemberFetcher(this.vault);

  final _VaultChannel vault;

  @override
  String get name => 'fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      ChhResponse(200, _member(vault.currentUid!));
}

class _SavedAccount {
  _SavedAccount(this.uid, {this.lastUsedAt = 0})
    : auth = 'fixture-$uid',
      name = '用户 $uid';

  final String uid;
  String name;
  String? auth;
  AccountState state = AccountState.unknown;
  int checkedAt = 0;
  int notices = 0;
  int messages = 0;
  int lastUsedAt;

  Map<String, Object> summary() => {
    'uid': uid,
    'name': name,
    'state': state.name,
    'checkedAt': checkedAt,
    'notices': notices,
    'messages': messages,
    'lastUsedAt': lastUsedAt,
  };
}

class _VaultChannel {
  _VaultChannel(this.cookies);
  final _Cookies cookies;
  final accounts = <String, _SavedAccount>{};
  final calls = <MethodCall>[];
  String? currentUid;
  String? previousUid;
  bool pendingLogin = false;
  int cookieReadsAtRecover = 0;
  FutureOr<void> Function(List<String>)? onCheck;

  _SavedAccount seed(String uid, {int lastUsedAt = 0, bool current = false}) {
    final account = accounts[uid] = _SavedAccount(uid, lastUsedAt: lastUsedAt);
    if (current) activate(uid);
    return account;
  }

  void activate(String uid) {
    currentUid = uid;
    cookies.auth = accounts[uid]!.auth;
  }

  Map<String, Object?> _summary() => {
    'currentUid': currentUid,
    'max': 5,
    'accounts': accounts.values.map((account) => account.summary()).toList(),
  };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final args = call.arguments as Map<Object?, Object?>?;
    final uid = args?['uid'] as String?;
    switch (call.method) {
      case 'list':
        break;
      case 'check':
        await onCheck?.call((args!['uids'] as List<Object?>).cast<String>());
      case 'save':
        if (pendingLogin) throw PlatformException(code: 'login_pending');
        if (accounts.length >= 5 && !accounts.containsKey(uid)) {
          throw PlatformException(code: 'account_limit');
        }
        final account = accounts[uid] ?? seed(uid!);
        account.auth = cookies.auth;
        account.name = args!['name'] as String;
        account.notices = args['notices'] as int? ?? account.notices;
        account.messages = args['messages'] as int? ?? account.messages;
        if (args['observed'] == true) {
          account.state = AccountState.ok;
          account.checkedAt = _now.millisecondsSinceEpoch;
        }
        currentUid = uid;
      case 'activate':
        activate(uid!);
      case 'remove':
        accounts.remove(uid);
        if (currentUid == uid) currentUid = null;
      case 'beginLogin':
        previousUid = cookies.auth == null ? null : currentUid;
        if (previousUid case final previous?) {
          accounts[previous]!.auth = cookies.auth;
        }
        pendingLogin = true;
        cookies.auth = null;
      case 'peekAuth':
        return cookies.auth != null;
      case 'endLogin':
        if (args?['restore'] == true && previousUid != null) {
          activate(previousUid!);
        } else {
          currentUid = null;
        }
        pendingLogin = false;
      case 'recover':
        cookieReadsAtRecover = cookies.reads;
        if (pendingLogin) {
          if (cookies.auth == null && previousUid != null) {
            activate(previousUid!);
          } else {
            currentUid = null;
          }
          pendingLogin = false;
        }
      case 'markExpired':
        accounts[uid]!.state = AccountState.expired;
      default:
        throw MissingPluginException();
    }
    return _summary();
  }

  Iterable<String> get methods => calls.map((call) => call.method);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cookies = _Cookies();
  final storage = _WebStorage();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _VaultChannel vault;
  late AccountStore store;
  late _DirectAdapter adapter;
  late DirectFetcher direct;
  late ChhClient client;
  late ChhSession session;

  setUpAll(() => InAppWebViewPlatform.instance = _Platform(cookies, storage));
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    cookies
      ..auth = null
      ..reads = 0
      ..deletions.clear()
      ..allDeletions = 0;
    storage.deletes = 0;
    vault = _VaultChannel(cookies);
    messenger.setMockMethodCallHandler(_accountsChannel, vault.handle);
    messenger.setMockMethodCallHandler(_sessionChannel, (_) async => null);
    store = AccountStore();
    adapter = _DirectAdapter()
      ..respond = (options) {
        final auth = options.headers['Cookie'] as String? ?? '';
        final account = vault.accounts.values
            .where((account) => auth.contains('test_auth=${account.auth};'))
            .firstOrNull;
        return _response(account == null ? _guest : _member(account.uid));
      };
    direct = DirectFetcher(
      dio: Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter,
    );
    client = ChhClient(fetchers: [direct], now: () => _now);
    session = ChhSession(client, accounts: store);
    client.htmlObserver = session.observeHtml;
  });

  tearDown(() async {
    session.dispose();
    store.dispose();
    await direct.dispose();
    messenger.setMockMethodCallHandler(_sessionChannel, null);
    messenger.setMockMethodCallHandler(_accountsChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> establish() async {
    await store.reload();
    await session.refresh();
    await session.ensureIdentity();
    vault.calls.clear();
  }

  test(
    'switches through the existing identity and request invalidation',
    () async {
      const previous = '1001';
      const target = '1002';
      vault.seed(previous, current: true);
      final saved = vault.seed(target)..notices = 8;
      await establish();

      final cached = ChhUrls.threadList(1);
      final delayed = ChhUrls.threadList(2);
      await client.getHtml(cached);
      expect(client.hasCachedHtml(cached), isTrue);
      direct.jar.merge({'test_sid': 'fixture-old'});

      final oldStarted = Completer<void>();
      final oldResponse = Completer<ResponseBody>();
      final verificationStarted = Completer<void>();
      final verificationResponse = Completer<ResponseBody>();
      adapter.respond = (request) {
        final uri = request.uri;
        if (uri == delayed && !oldStarted.isCompleted) {
          oldStarted.complete();
          return oldResponse.future;
        }
        if (uri == _forum) {
          verificationStarted.complete();
          return verificationResponse.future;
        }
        return _response(_member(target));
      };

      final stale = client.getHtml(delayed);
      await oldStarted.future;
      final originalIdentity = session.identityRevision;
      final originalAuth = session.authenticationRevision;
      final operationStates = <bool>[];
      session.addListener(
        () => operationStates.add(session.accountOperationInProgress),
      );
      final switching = session.switchAccount(target);

      expect(store.switchingUid, target);
      expect(operationStates.first, isTrue);
      expect(session.identityRevision, greaterThan(originalIdentity));
      expect(await session.switchAccount(previous), AccountSwitchResult.failed);

      await verificationStarted.future;
      expect(session.loggedIn, isTrue);
      expect(session.badges.uid, target);
      expect(session.badges.userName, saved.name);
      expect(session.badges.notices, 8);
      expect(session.authenticationRevision, greaterThan(originalAuth));
      expect(client.hasCachedHtml(cached), isFalse);
      expect(direct.jar.isEmpty, isTrue);

      oldResponse.complete(
        _response(
          _member(previous, name: '迟到的页头'),
          cookies: ['test_sid=fixture-late; Path=/'],
        ),
      );
      await stale;
      expect(session.badges.uid, target);
      expect(client.hasCachedHtml(delayed), isFalse);
      expect(direct.jar.isEmpty, isTrue);

      verificationResponse.complete(_response(_member(target, notices: 4)));
      expect(await switching, AccountSwitchResult.success);
      expect(store.switchingUid, isNull);
      expect(operationStates.last, isFalse);
      expect(session.badges.notices, 4);
      expect(await client.getHtml(delayed), _member(target));
      expect(vault.methods, ['check', 'save', 'activate', 'save']);
      expect(vault.calls.first.arguments, {
        'uids': [target],
        'force': true,
      });
    },
  );

  test(
    'an expired check result refuses activation and keeps the old session',
    () async {
      vault.seed('1001', current: true);
      final target = vault.seed('1002');
      await establish();
      vault.onCheck = (uids) {
        expect(uids, [target.uid]);
        target.state = AccountState.expired;
      };
      final auth = session.authenticationRevision;
      final cache = client.cacheGeneration;
      expect(
        await session.switchAccount(target.uid),
        AccountSwitchResult.expired,
      );
      expect(vault.methods, ['check']);
      expect(store.find(target.uid)?.state, AccountState.expired);
      expect(store.currentUid, '1001');
      expect(session.badges.uid, '1001');
      expect(session.authenticationRevision, auth);
      expect(client.cacheGeneration, cache);
    },
  );

  testWidgets(
    'switch proceeds after a six-second check and accepts late updates',
    (tester) async {
      debugDefaultTargetPlatformOverride = null;
      client.fetchers
        ..clear()
        ..add(_MemberFetcher(vault));
      final previous = vault.seed('1001', current: true);
      final target = vault.seed('1002')..state = AccountState.expired;
      await establish();

      final pendingCheck = Completer<void>();
      vault.onCheck = (uids) async {
        expect(uids, [target.uid]);
        await pendingCheck.future;
        target.notices = 9;
      };
      final switching = session.switchAccount(target.uid);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 5999));
      expect(store.currentUid, previous.uid);
      expect(vault.methods, ['check']);

      await tester.pump(const Duration(milliseconds: 1));
      expect(store.currentUid, target.uid);
      expect(await switching, AccountSwitchResult.success);
      expect(session.badges.uid, target.uid);
      expect(store.find(target.uid)?.notices, 0);

      pendingCheck.complete();
      await tester.pump();
      expect(store.find(target.uid)?.notices, 9);
      expect(store.currentUid, target.uid);
    },
  );

  test('recent successful check skips checking again when switching', () async {
    vault.seed('1001', current: true);
    vault.seed('1002')
      ..state = AccountState.ok
      ..checkedAt = _now
          .subtract(const Duration(minutes: 4))
          .millisecondsSinceEpoch;
    await establish();

    expect(await session.switchAccount('1002'), AccountSwitchResult.success);
    expect(vault.methods, ['save', 'activate', 'save']);
  });

  test(
    'member header repairs background expiry for the same identity',
    () async {
      final saved = vault.seed('1001', current: true);
      await establish();
      expect(saved.state, AccountState.ok);
      final revision = session.authenticationRevision;
      saved.state = AccountState.expired;
      await store.reload();
      vault.calls.clear();

      expect(session.currentExpired, isFalse);
      session.observeHtml(_member(saved.uid));
      session.observeHtml(_member(saved.uid));
      await session.ensureIdentity();
      session.observeHtml(_member(saved.uid));

      expect(vault.methods, ['save']);
      expect((vault.calls.single.arguments as Map)['observed'], isTrue);
      expect(store.find(saved.uid)?.state, AccountState.ok);
      expect(session.authenticationRevision, revision);
      expect(session.currentExpired, isFalse);
    },
  );

  test(
    'add cancellation restores WebView cookies without a background identity change',
    () async {
      vault.seed('1001', current: true);
      await establish();
      final backgroundAuth = direct.sessionCookies?['test_auth'];
      final identity = session.identityRevision;
      final authentication = session.authenticationRevision;
      final badge = session.badges;
      var notifications = 0;
      session.addListener(() => notifications++);

      expect(await session.beginAccountLogin(), isTrue);
      expect(vault.pendingLogin, isTrue);
      expect(await store.peekAuth(), isFalse);
      final reads = cookies.reads;
      await session.refresh();
      expect(cookies.reads, reads);
      expect(direct.sessionCookies?['test_auth'] == backgroundAuth, isTrue);
      expect(session.observeHtml(_guest), isFalse);
      expect(session.observeHtml(_member('1002')), isFalse);
      expect(session.badges, badge);
      expect(session.loggedIn, isTrue);
      expect(session.currentExpired, isFalse);

      await session.captureCurrent();
      expect(vault.methods, ['beginLogin', 'peekAuth']);
      await expectLater(
        store.save('1001', '用户 1001'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'login_pending',
          ),
        ),
      );
      final guestPage = ChhUrls.threadList(3);
      adapter.respond = (_) => _response(_guest);
      await client.getHtml(guestPage);
      expect(client.hasCachedHtml(guestPage), isTrue);

      expect(await session.finishAccountLogin(restore: true), isTrue);
      expect(vault.pendingLogin, isFalse);
      expect(cookies.auth == backgroundAuth, isTrue);
      expect(direct.sessionCookies?['test_auth'] == backgroundAuth, isTrue);
      expect(client.hasCachedHtml(guestPage), isFalse);
      expect(session.badges, badge);
      expect(session.identityRevision, identity);
      expect(session.authenticationRevision, authentication);
      expect(notifications, 0);
    },
  );

  test(
    'relogin with the same UID replaces its snapshot and saves it once',
    () async {
      final saved = vault.seed('1001', current: true);
      await establish();
      final originalAuth = saved.auth;
      final revision = session.authenticationRevision;

      expect(await session.beginAccountLogin(reloginUid: saved.uid), isTrue);
      expect((vault.calls.single.arguments as Map)['uid'], saved.uid);
      cookies.auth = 'fixture-new-login';
      expect(await store.peekAuth(), isTrue);
      adapter.respond = (_) => _response(_member(saved.uid));
      expect(await session.finishAccountLogin(restore: false), isTrue);
      expect(session.authenticationRevision, greaterThan(revision));
      expect(saved.auth == originalAuth, isFalse);
      expect(saved.auth == cookies.auth, isTrue);
      expect(store.accounts.map((account) => account.uid), [saved.uid]);
      expect(store.currentUid, saved.uid);

      session.observeHtml(_member(saved.uid, notices: 3));
      await session.ensureIdentity();
      expect(vault.methods.where((method) => method == 'save'), hasLength(1));
      session.observeHtml(_member(saved.uid, name: '更改后的用户名'));
      await session.ensureIdentity();
      expect(vault.methods.where((method) => method == 'save'), hasLength(2));
      expect(store.find(saved.uid)?.name, '更改后的用户名');
    },
  );

  test(
    'a sixth account is blocked while the full vault still permits relogin',
    () async {
      for (var uid = 1001; uid <= 1005; uid++) {
        vault.seed('$uid', current: uid == 1001);
      }
      await establish();
      expect(store.isFull, isTrue);
      expect(store.max, 5);
      expect(() => store.accounts.clear(), throwsUnsupportedError);

      await expectLater(
        session.beginAccountLogin(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'account_limit',
          ),
        ),
      );
      expect(vault.methods, isEmpty);
      expect(await session.beginAccountLogin(reloginUid: '1001'), isTrue);
      expect(await session.finishAccountLogin(restore: true), isTrue);
      expect(store.accounts, hasLength(5));
    },
  );

  test('logout selects the most recently used remaining account', () async {
    vault.seed('1001', current: true);
    vault.seed('1002', lastUsedAt: 20);
    vault.seed('1003', lastUsedAt: 30);
    await establish();

    await session.logout();
    expect(vault.methods, ['remove', 'activate', 'save']);
    expect(store.find('1001'), isNull);
    expect(store.currentUid, '1003');
    expect(session.badges.uid, '1003');
    expect(session.loggedIn, isTrue);
    expect(cookies.allDeletions, 0);
  });

  for (final finished in [false, true]) {
    test(
      'cold recovery ${finished ? 'adopts the new auth' : 'restores the prior account'} before reading cookies',
      () async {
        vault.seed('1001', current: true);
        vault.pendingLogin = true;
        vault.previousUid = '1001';
        cookies.auth = finished ? 'fixture-adopted' : null;
        if (finished) adapter.respond = (_) => _response(_member('1002'));

        await store.recover();
        await session.refresh();
        await session.ensureIdentity();

        final uid = finished ? '1002' : '1001';
        expect(vault.methods.first, 'recover');
        expect(vault.cookieReadsAtRecover, 0);
        expect(vault.pendingLogin, isFalse);
        expect(session.initialRefreshComplete, isTrue);
        expect(session.loggedIn, isTrue);
        expect(session.badges.uid, uid);
        expect(store.currentUid, uid);
        expect(vault.accounts[uid]?.auth == cookies.auth, isTrue);
      },
    );
  }

  test('missing accounts channel keeps normal login and full logout', () async {
    messenger.setMockMethodCallHandler(_accountsChannel, null);
    cookies.auth = 'fixture-single';
    adapter.respond = (_) => _response(_member('1001'));

    await store.recover();
    await session.refresh();
    await session.ensureIdentity();
    expect(session.loggedIn, isTrue);
    expect(session.badges.uid, '1001');
    expect(store.accounts, isEmpty);
    expect(await session.beginAccountLogin(), isFalse);
    expect(session.loggedIn, isTrue);

    await session.logout();
    expect(cookies.deletions, hasLength(4));
    expect(cookies.allDeletions, 1);
    expect(storage.deletes, 1);
    expect(session.loggedIn, isFalse);
    expect(direct.sessionCookies, isNull);
  });

  for (final (label, page) in [
    ('lsform', _guest),
    ('escaped ampersands', _guest.replaceFirst(' id="lsform"', '')),
    (
      'literal ampersands',
      _guest.replaceFirst(' id="lsform"', '').replaceAll('&amp;', '&'),
    ),
  ]) {
    test(
      'a complete guest page with $label expires until its own header returns',
      () async {
        vault.seed('1001', current: true);
        await establish();
        var notifications = 0;
        session.addListener(() => notifications++);
        adapter.respond = (_) => _response(page);

        await client.getHtml(_forum, refresh: true);
        expect(session.currentExpired, isTrue);
        expect(session.loggedIn, isTrue);
        expect(session.badges.uid, '1001');
        // Persisting the state goes through a separate native channel call.
        await Future<void>.delayed(Duration.zero);
        expect(store.find('1001')?.state, AccountState.expired);
        expect(notifications, 1);

        session.observeHtml(page);
        session.observeHtml(_member('1002'));
        expect(vault.methods, ['markExpired']);
        expect(session.currentExpired, isTrue);
        expect(session.badges.uid, '1001');
        expect(notifications, 1);

        session.observeHtml(_member('1001'));
        await session.ensureIdentity();
        expect(session.currentExpired, isFalse);
        expect(store.find('1001')?.state, AccountState.ok);
        expect(notifications, 2);
      },
    );
  }

  for (final (label, page, status) in [
    ('redirect', _guest, 302),
    ('forbidden', _guest, 403),
    ('partial document', _guest.replaceFirst('</html>', ''), 200),
    ('HTML fragment', '<div id="hd"><form id="lsform"></form></div>', 200),
    (
      'truncated document with a quoted closing tag',
      _guest.replaceFirst('</html>', '<script>const tag = "</html>";</script>'),
      200,
    ),
    ('missing site header', _guest.replaceFirst('id="hd"', 'id="other"'), 200),
    (
      'missing guest login form',
      '<html><body><div id="hd"></div></body></html>',
      200,
    ),
    (
      'non-login form',
      '<html><body><div id="hd"><form action="search.php"></form></div></body></html>',
      200,
    ),
    (
      'challenge',
      '<html><head><title>正在验证</title></head><body><p>等待验证</p></body></html>',
      200,
    ),
    (
      'signed-in marker',
      _guest.replaceFirst('id="hd">', 'id="hd"><div id="um"></div>'),
      200,
    ),
  ]) {
    test('$label does not mark the account expired', () async {
      vault.seed('1001', current: true);
      await establish();
      adapter.respond = (_) => _response(page, status: status);

      // Use a fixture route to ensure structurally ambiguous pages reach the
      // observer without changing the normal forum transport's fallback rules.
      await client.getHtml(
        Uri.parse('${ChhUrls.base}/synthetic-account-check'),
      );
      expect(session.currentExpired, isFalse);
      expect(vault.methods, isNot(contains('markExpired')));
    });
  }

  test('a guest session does not mark any saved account expired', () async {
    vault.seed('1001');
    await establish();

    expect(session.loggedIn, isFalse);
    expect(session.observeHtml(_guest), isFalse);
    expect(session.currentExpired, isFalse);
    expect(vault.methods, isEmpty);
  });
}
