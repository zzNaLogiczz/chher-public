import 'dart:async';

import 'package:chh_app/core/message_notifications.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/pages/login_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform extends InAppWebViewPlatform {
  _Platform(this.currentUid);

  final String Function() currentUid;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _CookieManager(currentUid);
}

class _CookieManager extends PlatformCookieManager {
  _CookieManager(this.currentUid)
    : super.implementation(const PlatformCookieManagerCreationParams());

  final String Function() currentUid;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => [Cookie(name: 'test_auth', value: 'fixture-${currentUid()}')];
}

class _Headers extends ChhFetcher {
  _Headers(this.currentUid);

  final String Function() currentUid;

  @override
  String get name => 'local notification fixture';

  @override
  Future<ChhResponse> getHtml(
    Uri url, {
    Map<String, String>? headers,
  }) async => ChhResponse(
    200,
    '<div id="um"><strong class="vwmy"><a href="space-uid-${currentUid()}.html">'
    '本地账号</a></strong></div>',
  );
}

void main() {
  testWidgets(
    'notification tap leaves the covered route and opens fresh messages',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      var messageBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: buildAppTheme(Brightness.light),
          home: HomePage(
            initialiseSession: () async {},
            screenBuilders: {
              AppDestination.feed: (_) => const Scaffold(body: Text('精选内容')),
              AppDestination.messages: (_) {
                messageBuilds++;
                return Scaffold(body: Text('消息内容$messageBuilds'));
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('帖子详情')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('帖子详情'), findsOneWidget);
      const openMessages = NotificationOpenRequest(NotificationAction.messages);
      messageNotifications.openRequests.value = openMessages;
      await tester.pumpAndSettle();
      expect(find.text('帖子详情'), findsNothing);
      expect(find.text('消息内容1'), findsOneWidget);
      final busy = ValueNotifier<bool>(true);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder: (_, submitting, _) => PopScope(
              canPop: !submitting,
              child: const Scaffold(body: Text('正在提交')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      messageNotifications.openRequests.value = openMessages;
      await tester.pumpAndSettle();
      expect(find.text('正在提交'), findsOneWidget);
      expect(messageBuilds, 1);
      busy.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('正在提交'), findsNothing);
      expect(find.text('消息内容2'), findsOneWidget);
      busy.dispose();
      await tester.pumpWidget(const SizedBox());
      messageNotifications.openRequests.value = null;
    },
  );

  testWidgets('account notification switches, relogs or leaves the tab alone', (
    tester,
  ) async {
    const channel = MethodChannel('chh/accounts');
    final messenger = tester.binding.defaultBinaryMessenger;
    final navigator = GlobalKey<NavigatorState>();
    final oldPlatform = InAppWebViewPlatform.instance;
    final oldFetchers = chhClient.fetchers.toList();
    final oldObserver = chhClient.htmlObserver;
    final oldCookies = chhSession.cookies;
    final oldBadges = chhSession.badges;
    final oldLoggedIn = chhSession.loggedIn;
    var current = '1001';
    var emptyVault = true;
    final switching = Completer<void>();
    final checks = <String>[];
    final relogins = <String>[];
    InAppWebViewPlatform.instance = _Platform(() => current);
    chhClient.fetchers
      ..clear()
      ..add(_Headers(() => current));
    chhClient.htmlObserver = chhSession.observeHtml;
    chhSession
      ..loggedIn = true
      ..cookies = {'test_auth': 'fixture-legacy'}
      ..badges = const HeaderBadges(notices: 0, messages: 0);
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      if (oldPlatform != null) InAppWebViewPlatform.instance = oldPlatform;
      chhClient.fetchers
        ..clear()
        ..addAll(oldFetchers);
      chhClient.htmlObserver = oldObserver;
      chhClient.clearCache();
      chhSession
        ..cookies = oldCookies
        ..badges = oldBadges
        ..loggedIn = oldLoggedIn;
      messageNotifications.openRequests.value = null;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'check':
          final uid =
              ((call.arguments as Map)['uids'] as List).single as String;
          checks.add(uid);
          if (uid == '1002') await switching.future;
        case 'activate':
          final uid = (call.arguments as Map)['uid'] as String;
          if (uid == '1001') throw PlatformException(code: 'fixture_failure');
          current = uid;
        case 'beginLogin':
          relogins.add((call.arguments as Map)['uid'] as String);
          // Keep the platform view offline while testing the real route.
          throw PlatformException(code: 'fixture_relogin');
      }
      return {
        'currentUid': emptyVault ? null : current,
        'max': 5,
        'accounts': [
          for (final uid in emptyVault ? <String>[] : ['1001', '1002', '1003'])
            {
              'uid': uid,
              'name': '本地账号',
              'state': uid == '1003' ? 'expired' : 'ok',
              'checkedAt': 0,
              'notices': 0,
              'messages': 0,
              'lastUsedAt': 0,
            },
        ],
      };
    });

    await accountStore.reload();
    messageNotifications.openRequests.value = const NotificationOpenRequest(
      NotificationAction.messages,
      uid: '1001',
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAppTheme(Brightness.light),
        home: HomePage(
          initialiseSession: () async {},
          screenBuilders: {
            AppDestination.feed: (_) => const Scaffold(body: Text('精选内容')),
            AppDestination.messages: (_) => const Scaffold(body: Text('消息内容')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(chhSession.badges.uid, '1001');
    expect(find.text('消息内容'), findsOneWidget);
    expect(checks, isEmpty);
    emptyVault = false;
    tester
        .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
        .onNavigate(AppDestination.feed);
    await tester.pumpAndSettle();
    Future<void> tap(NotificationAction action, String uid) async {
      messageNotifications.openRequests.value = NotificationOpenRequest(
        action,
        uid: uid,
      );
      await tester.pumpAndSettle();
    }

    await tap(NotificationAction.messages, '9999');
    expect(find.text('精选内容'), findsOneWidget);
    expect(checks, isEmpty);

    await tap(NotificationAction.messages, '1002');
    expect(checks, ['1002']);
    expect(find.text('精选内容'), findsOneWidget);
    await tap(NotificationAction.relogin, '1003');
    expect(relogins, isEmpty);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('切换期间打开的帖子')),
      ),
    );
    await tester.pumpAndSettle();
    switching.complete();
    await tester.pumpAndSettle();
    expect(chhSession.badges.uid, '1002');
    expect(find.text('切换期间打开的帖子'), findsNothing);
    expect(find.text('消息内容'), findsOneWidget);

    await tap(NotificationAction.messages, '1003');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(relogins, ['1003']);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    await tap(NotificationAction.relogin, '1001');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(relogins, ['1003', '1001']);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    messageNotifications.openRequests.value = const NotificationOpenRequest(
      NotificationAction.messages,
      uid: '1001',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('暂时无法切换账号'), findsOneWidget);
    expect(chhSession.badges.uid, '1002');
    expect(find.text('消息内容'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });
}
