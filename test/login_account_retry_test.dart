import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cookies extends PlatformCookieManager {
  _Cookies()
    : super.implementation(const PlatformCookieManagerCreationParams());

  String? auth = 'fixture-previous';

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => [
    if (auth case final value?) Cookie(name: 'test_auth', value: value),
  ];
}

class _WebView extends PlatformInAppWebViewWidget {
  _WebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  int stops = 0;

  @override
  Future<void> stopLoading() async => stops++;
}

class _Platform extends InAppWebViewPlatform {
  final cookies = _Cookies();
  late _WebView webView;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => cookies;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => webView = _WebView(params);
}

class _HeaderlessForum extends ChhFetcher {
  int requests = 0;

  @override
  String get name => 'local fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests++;
    return const ChhResponse(
      200,
      '<html><body><div id="hd"></div></body></html>',
    );
  }
}

void main() {
  testWidgets('account adoption backs off to 30s and cancels on page exit', (
    tester,
  ) async {
    const accounts = MethodChannel('chh/accounts');
    const session = MethodChannel('chh/session');
    final messenger = tester.binding.defaultBinaryMessenger;
    final oldPlatform = InAppWebViewPlatform.instance;
    final oldFetchers = List<ChhFetcher>.of(chhClient.fetchers);
    final oldObserver = chhClient.htmlObserver;
    final platform = _Platform();
    final fetcher = _HeaderlessForum();
    InAppWebViewPlatform.instance = platform;
    chhClient.fetchers
      ..clear()
      ..add(fetcher);
    chhClient.htmlObserver = chhSession.observeHtml;
    addTearDown(() {
      messenger.setMockMethodCallHandler(accounts, null);
      messenger.setMockMethodCallHandler(session, null);
      if (oldPlatform != null) InAppWebViewPlatform.instance = oldPlatform;
      chhClient.fetchers
        ..clear()
        ..addAll(oldFetchers);
      chhClient.htmlObserver = oldObserver;
      chhClient.clearCache();
    });

    String? currentUid = '1001';
    final calls = <String>[];
    messenger.setMockMethodCallHandler(session, (_) async => null);
    messenger.setMockMethodCallHandler(accounts, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'list':
          break;
        case 'beginLogin':
          platform.cookies.auth = null;
        case 'peekAuth':
          return platform.cookies.auth != null;
        case 'endLogin':
          currentUid = null;
        case 'activate':
          currentUid = '1001';
          platform.cookies.auth = 'fixture-previous';
        default:
          throw MissingPluginException(call.method);
      }
      return {
        'currentUid': currentUid,
        'max': 5,
        'accounts': [
          {
            'uid': '1001',
            'name': '本地测试账号',
            'state': 'ok',
            'checkedAt': 0,
            'notices': 0,
            'messages': 0,
            'lastUsedAt': 0,
          },
        ],
      };
    });

    await accountStore.reload();
    await chhSession.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const LoginPage.addAccount(),
      ),
    );
    await tester.pump();
    final fakeController = _Controller();
    final controller = InAppWebViewController.fromPlatform(
      platform: fakeController,
    );
    final params = platform.webView.params;
    params.onWebViewCreated!(controller);
    await tester.pump(const Duration(milliseconds: 799));
    expect(calls, ['list', 'beginLogin']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls.last, 'peekAuth');
    expect(fetcher.requests, 0);

    platform.cookies.auth = 'fixture-added';
    await tester.pump(const Duration(milliseconds: 800));
    expect(calls.last, 'endLogin');
    expect(fetcher.requests, 1);

    for (final seconds in [2, 4, 8, 16, 30, 30]) {
      final before = fetcher.requests;
      await tester.pump(const Duration(milliseconds: 800));
      params.onLoadStop!(controller, null);
      await tester.pump(Duration(milliseconds: seconds * 1000 - 801));
      expect(fetcher.requests, before, reason: 'retry due after ${seconds}s');
      await tester.pump(const Duration(milliseconds: 1));
      expect(fetcher.requests, before + 1);
    }
    expect(calls.where((method) => method == 'peekAuth'), hasLength(2));
    expect(calls.where((method) => method == 'endLogin'), hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    expect(fetcher.requests, 7);
    expect(fakeController.stops, 1);
    expect(calls.last, 'activate');
    expect(accountStore.currentUid, '1001');
  });
}
