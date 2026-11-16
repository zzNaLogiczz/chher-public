import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messages_ui_test.dart' show FakeMessages;

class _Cookies extends PlatformCookieManager {
  _Cookies()
    : super.implementation(const PlatformCookieManagerCreationParams());
  List<Cookie> values = [];
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => List.of(values);
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
  _Platform(this.jar);
  final _Cookies jar;
  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => jar;
}

class _Messages extends FakeMessages {
  int noticeReads = 0;
  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) async {
    noticeReads++;
    if (!chhSession.loggedIn) {
      throw const PageMessage(PageMessageKind.loginRequired, '请登录');
    }
    return Paged(
      items: [
        for (var i = 0; i < 40; i++)
          Notice(
            id: '$i',
            category: 'post',
            actor: '读者$i',
            occurredAtText: '今天 10:30',
            summary: '回复了您的帖子',
            title: '本地帖子$i',
          ),
      ],
      page: const PageInfo(current: 1, hasNext: false),
    );
  }
}

void main() {
  testWidgets(
    'login and account replacement start at top; identity hydration and return retain scroll',
    (tester) async {
      final savedPlatform = InAppWebViewPlatform.instance;
      final savedLogin = chhSession.loggedIn;
      final savedCookies = chhSession.cookies;
      final savedBadges = chhSession.badges;
      final jar = _Cookies();
      InAppWebViewPlatform.instance = _Platform(jar);
      const channel = MethodChannel('chh/session');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      addTearDown(() {
        if (savedPlatform != null) {
          InAppWebViewPlatform.instance = savedPlatform;
        }
        chhSession.loggedIn = savedLogin;
        chhSession.cookies = savedCookies;
        chhSession.badges = savedBadges;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await chhSession.refresh();
      final repository = _Messages();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: HomePage(
            initialiseSession: () async {},
            screenBuilders: {
              AppDestination.feed: (_) => const Scaffold(body: Text('本地精选')),
              AppDestination.me: (_) => const Scaffold(body: Text('本地账号')),
              AppDestination.messages: (_) =>
                  MessagesTabPage(repository: repository),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tab(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(AppBottomNavigation),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      ScrollController scroll() => tester
          .widget<CustomScrollView>(find.byType(CustomScrollView).hitTestable())
          .controller!;
      await tab('消息');
      expect(find.text('登录后查看消息'), findsOneWidget);
      scroll().jumpTo(scroll().position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(scroll().offset, greaterThan(0));
      await tab('我的');
      jar.values = [Cookie(name: 'test_auth', value: 'account-a')];
      await chhSession.refresh();
      await tester.pumpAndSettle();
      await tab('消息');
      expect(repository.noticeReads, 2);
      expect(scroll().offset, 0);
      expect(find.text('本地帖子0').hitTestable(), findsOneWidget);

      scroll().jumpTo(500);
      await tester.pumpAndSettle();
      chhSession.observeHtml(
        '<div id="um"><strong class="vwmy"><a href="space-uid-12.html">本地账号</a></strong><a id="myprompt">提醒(0)</a><a id="pm_ntc">私信(0)</a></div>',
      );
      await tester.pumpAndSettle();
      expect(repository.noticeReads, 2);
      expect(scroll().offset, 500);
      await tab('我的');
      await tab('消息');
      expect(repository.noticeReads, 2);
      expect(scroll().offset, 500);

      jar.values = [Cookie(name: 'test_auth', value: 'account-b')];
      await chhSession.refresh();
      await tester.pumpAndSettle();
      expect(repository.noticeReads, 3);
      expect(scroll().offset, 0);
      scroll().jumpTo(500);
      await tester.pumpAndSettle();
      await chhSession.logout();
      await tester.pumpAndSettle();
      expect(repository.noticeReads, 4);
      expect(scroll().offset, 0);
      expect(find.text('登录后查看消息'), findsOneWidget);
      expect(find.text('本地帖子0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
