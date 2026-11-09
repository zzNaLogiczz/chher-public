import 'dart:async';

import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/network/chh_session.dart';
import 'package:chh_app/network/direct_fetcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cookies extends PlatformCookieManager {
  _Cookies()
    : super.implementation(const PlatformCookieManagerCreationParams());
  List<Cookie> values = [];
  Completer<List<Cookie>>? pending;
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => pending == null ? List.of(values) : await pending!.future;
  @override
  Future<bool> deleteCookies({
    required WebUri url,
    String? domain,
    String path = '/',
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    values.clear();
    return true;
  }

  @override
  Future<bool> deleteAllCookies() async {
    values.clear();
    return true;
  }
}

class _Platform extends InAppWebViewPlatform {
  final _Cookies jar;
  _Platform(this.jar);
  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => jar;
}

class _PageFetcher extends ChhFetcher {
  int calls = 0;
  @override
  String get name => 'session-fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    calls++;
    return const ChhResponse(200, '<p>local page</p>');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final jar = _Cookies();
  const channel = MethodChannel('chh/session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() => InAppWebViewPlatform.instance = _Platform(jar));
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    jar.values = [
      Cookie(name: 'test_auth', value: 'local-fixture'),
      Cookie(name: 'test_saltkey', value: 'local-salt'),
    ];
    jar.pending = null;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'login is persisted before notifying and a fresh session restores cookies',
    () async {
      final disk = Completer<void>();
      var flushes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'flushCookies');
        flushes++;
        await disk.future;
        return null;
      });
      final direct = DirectFetcher();
      final first = ChhSession(ChhClient(fetchers: [direct]));
      final refresh = first.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(flushes, 1);
      expect(first.loggedIn, isFalse);
      disk.complete();
      await refresh;
      expect(first.loggedIn, isTrue);
      expect(direct.sessionCookies?['test_auth'], 'local-fixture');
      final fresh = ChhSession(ChhClient(fetchers: [direct]));
      await fresh.refresh();
      expect(fresh.loggedIn, isTrue);
      await fresh.logout();
      final afterLogout = ChhSession(ChhClient(fetchers: [direct]));
      await afterLogout.refresh();
      expect(afterLogout.loggedIn, isFalse);
      expect(direct.sessionCookies, isNull);
      first.dispose();
      fresh.dispose();
      afterLogout.dispose();
      await direct.dispose();
    },
  );

  test(
    'initial restoration and later login expose distinct sync phases',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      jar.values = [];
      final session = ChhSession(ChhClient(fetchers: []));
      final phases = <bool>[];
      session.addListener(() => phases.add(session.initialRefreshComplete));
      await session.refresh();
      expect(session.initialRefreshComplete, isTrue);
      jar.values = [Cookie(name: 'test_auth', value: 'local-fixture')];
      await session.refresh();
      expect(phases, [true]);

      final restored = ChhSession(ChhClient(fetchers: []));
      final restorePhases = <bool>[];
      restored.addListener(
        () => restorePhases.add(restored.initialRefreshComplete),
      );
      await restored.refresh();
      expect(restorePhases, [false]);
      expect(restored.initialRefreshComplete, isTrue);
      session.dispose();
      restored.dispose();
    },
  );

  test(
    'a pending cookie read cannot resurrect an explicitly logged-out session',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final direct = DirectFetcher();
      final session = ChhSession(ChhClient(fetchers: [direct]));
      final pending = Completer<List<Cookie>>();
      jar.pending = pending;
      final read = session.refresh();
      await session.logout();
      pending.complete([Cookie(name: 'test_auth', value: 'stale')]);
      await read;
      expect(session.loggedIn, isFalse);
      expect(direct.sessionCookies, isNull);
      session.dispose();
      await direct.dispose();
    },
  );
  test('auth replacement at the same UID advances identity revision', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final session = ChhSession(ChhClient(fetchers: []));
    await session.refresh();
    final first = session.identityRevision;
    var changes = 0;
    session.addListener(() => changes++);
    jar.values = [
      Cookie(name: 'test_auth', value: 'new-local-auth'),
      Cookie(name: 'test_saltkey', value: 'local-salt'),
    ];
    await session.refresh();
    expect(session.identityRevision, greaterThan(first));
    expect(changes, 1);
    session.dispose();
  });

  test('auth rotation clears old direct cookies and cached pages', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final pages = _PageFetcher();
    final direct = DirectFetcher();
    final client = ChhClient(fetchers: [pages, direct]);
    final session = ChhSession(client);
    await session.refresh();
    final url = Uri.parse(
      'https://www.chiphell.com/forum.php?mod=viewthread&tid=10',
    );
    await client.getHtml(url);
    await client.getHtml(url);
    expect(pages.calls, 1);
    direct.jar.merge({'old_session': 'old-actor'});
    session.badges = const HeaderBadges(
      notices: 0,
      messages: 0,
      uid: '42',
      userName: 'old-user',
    );
    jar.values = [Cookie(name: 'test_auth', value: 'new-local-auth')];
    await session.refresh();
    expect(session.loggedIn, isTrue);
    expect(direct.sessionCookies?['test_auth'], 'new-local-auth');
    expect(direct.jar.all, isEmpty);
    expect(session.badges.uid, isNull);
    expect(session.badges.userName, isNull);
    await client.getHtml(url);
    expect(pages.calls, 2);
    session.dispose();
    await direct.dispose();
  });

  test('logout invalidates forms before cookie deletion completes', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final session = ChhSession(ChhClient(fetchers: []));
    await session.refresh();
    final before = session.identityRevision;
    final result = session.logout();
    expect(session.identityRevision, greaterThan(before));
    await result;
    session.dispose();
  });
}
