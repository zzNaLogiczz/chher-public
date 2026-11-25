import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _AccountPlatform extends InAppWebViewPlatform {
  _AccountPlatform(this.currentUid);

  final String Function() currentUid;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _AccountCookies(currentUid);
}

class _AccountCookies extends PlatformCookieManager {
  _AccountCookies(this.currentUid)
    : super.implementation(const PlatformCookieManagerCreationParams());

  final String Function() currentUid;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => [Cookie(name: 'fixture_auth', value: 'local-${currentUid()}')];
}

class _AccountMessages extends ChhFetcher {
  final noticeAccounts = <String>[];

  @override
  String get name => 'local account notices';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    final uid = chhSession.cookies['fixture_auth']!.split('-').last;
    final header =
        '<div id="um"><strong class="vwmy"><a href="space-uid-$uid.html">'
        '账号 $uid</a></strong></div>';
    if (url.queryParameters['do'] != 'notice') return ChhResponse(200, header);
    noticeAccounts.add(uid);
    return ChhResponse(200, '''
      $header
      <dl id="notice_12">
        <dt><span class="xg1">2026-11-15 17:40</span></dt>
        <dd class="ntc_body">
          <a href="space-uid-17.html">合成用户</a> 回复了你的主题
          <a class="lit" href="thread-25-1-1.html">提醒主题 $uid</a>
        </dd>
      </dl>
      ''');
  }
}

Widget _app({Future<void> Function()? initialiseSession}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: HomePage(
    initialiseSession: initialiseSession ?? () async {},
    screenBuilders: {
      AppDestination.feed: (_) => const Scaffold(body: Text('本地首页')),
      AppDestination.me: (_) => const Scaffold(body: Text('本地个人页')),
    },
  ),
);

Finder _bottomLabel(String label) => find.descendant(
  of: find.byType(AppBottomNavigation),
  matching: find.text(label),
);

void main() {
  testWidgets('消息强调色圆点由数字角标优先覆盖', (tester) async {
    Future<void> show({bool dot = false, int count = 0, int epoch = 0}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            bottomNavigationBar: AppBottomNavigation(
              current: AppDestination.messages,
              onNavigate: (_) {},
              messagesDot: dot,
              messagesDotEpoch: epoch,
              messagesBadge: count,
            ),
          ),
        ),
      );
    }

    final dot = find.byKey(DotBadge.surfaceKey);
    final badge = find.byKey(CountBadge.surfaceKey);
    await show(dot: true);
    await tester.pumpAndSettle();
    expect(dot, findsOneWidget);
    expect(badge, findsNothing);
    final decoration =
        tester.widget<DecoratedBox>(dot).decoration as ShapeDecoration;
    expect(decoration.color, AppTokens.of(tester.element(dot)).accent);

    await show(epoch: 1);
    await tester.pump();
    expect(dot, findsNothing);

    await show(dot: true, count: 2, epoch: 1);
    await tester.pumpAndSettle();
    expect(dot, findsNothing);
    expect(badge, findsOneWidget);
    await show(epoch: 1);
    await tester.pumpAndSettle();
    expect(dot, findsNothing);
    expect(badge, findsNothing);
  });

  testWidgets('guest Me hold leaves the current destination intact', (
    tester,
  ) async {
    expect(chhSession.loggedIn, isFalse);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.longPress(_bottomLabel('我的'));
    await tester.pumpAndSettle();
    expect(find.text('切换账号'), findsNothing);
    expect(find.text('本地首页'), findsOneWidget);
    expect(find.text('本地个人页'), findsNothing);

    await tester.tap(_bottomLabel('我的'));
    await tester.pumpAndSettle();
    expect(find.text('本地个人页'), findsOneWidget);
  });

  testWidgets('400ms Me hold switches accounts without leaving Messages', (
    tester,
  ) async {
    const accountsChannel = MethodChannel('chh/accounts');
    const sessionChannel = MethodChannel('chh/session');
    final messenger = tester.binding.defaultBinaryMessenger;
    final originalPlatform = InAppWebViewPlatform.instance;
    final originalFetchers = chhClient.fetchers.toList();
    final originalObserver = chhClient.htmlObserver;
    final originalCookies = chhSession.cookies;
    final originalBadges = chhSession.badges;
    final originalLogin = chhSession.loggedIn;
    var currentUid = '1001';
    final fetcher = _AccountMessages();
    final haptics = <String>[];

    InAppWebViewPlatform.instance = _AccountPlatform(() => currentUid);
    chhClient.fetchers
      ..clear()
      ..add(fetcher);
    chhClient.htmlObserver = chhSession.observeHtml;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(accountsChannel, null)
        ..setMockMethodCallHandler(sessionChannel, null)
        ..setMockMethodCallHandler(SystemChannels.platform, null);
      if (originalPlatform != null) {
        InAppWebViewPlatform.instance = originalPlatform;
      }
      chhClient.fetchers
        ..clear()
        ..addAll(originalFetchers);
      chhClient
        ..htmlObserver = originalObserver
        ..clearCache();
      chhSession
        ..cookies = originalCookies
        ..badges = originalBadges
        ..loggedIn = originalLogin;
    });
    messenger.setMockMethodCallHandler(accountsChannel, (call) async {
      if (call.method == 'activate') {
        currentUid = (call.arguments as Map)['uid'] as String;
      }
      return {
        'currentUid': currentUid,
        'max': 5,
        'accounts': [
          for (final uid in ['1001', '1002'])
            {
              'uid': uid,
              'name': '账号 $uid',
              'state': 'ok',
              'checkedAt': chhClient.now().millisecondsSinceEpoch,
              'notices': 0,
              'messages': 0,
              'lastUsedAt': 0,
            },
        ],
      };
    });
    messenger.setMockMethodCallHandler(sessionChannel, (_) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });

    await accountStore.reload();
    await tester.pumpWidget(_app(initialiseSession: chhSession.refresh));
    await tester.pumpAndSettle();
    await tester.tap(_bottomLabel('消息'));
    await tester.pumpAndSettle();

    expect(find.text('《提醒主题 1001》'), findsOneWidget);
    final before = chhSession.authenticationRevision;
    final hold = await tester.startGesture(
      tester.getCenter(_bottomLabel('我的')),
    );
    const beforeDeadline = Duration(milliseconds: 1);
    await tester.pump(AppMotion.longPress - beforeDeadline);
    expect(find.text('切换账号'), findsNothing);
    expect(haptics, isEmpty);
    await tester.pump(beforeDeadline);
    await tester.pump();
    expect(find.text('切换账号'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    await hold.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('账号 1002'));
    await tester.pumpAndSettle();
    expect(find.text('切换账号'), findsNothing);
    expect(chhSession.authenticationRevision, greaterThan(before));
    expect(fetcher.noticeAccounts, ['1001', '1002']);
    expect(find.text('《提醒主题 1001》'), findsNothing);
    expect(find.text('《提醒主题 1002》'), findsOneWidget);
    expect(find.text('本地个人页'), findsNothing);
    expect(
      tester
          .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
          .current,
      AppDestination.messages,
    );
  });
}
