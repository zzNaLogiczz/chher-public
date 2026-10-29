import 'dart:async';

import 'package:chh_app/network/chh_client.dart';
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
}
