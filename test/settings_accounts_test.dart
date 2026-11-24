import 'package:chh_app/core/appearance.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/login_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:chh_app/widgets/account_row_parts.dart';
import 'package:chh_app/widgets/account_widgets.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:chh_app/widgets/level_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cookies extends PlatformCookieManager {
  _Cookies()
    : super.implementation(const PlatformCookieManagerCreationParams());

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => [Cookie(name: 'test_auth', value: 'fixture-auth')];
}

class _Platform extends InAppWebViewPlatform {
  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _Cookies();
}

class _HeaderlessPage extends ChhFetcher {
  @override
  String get name => 'settings-fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      const ChhResponse(200, '<html><body><div id="hd"></div></body></html>');
}

Map<String, Object> _account(
  String uid,
  String name, {
  int lastUsedAt = 0,
  String state = 'ok',
  int notices = 0,
  int messages = 0,
  int failures = 0,
}) => {
  'uid': uid,
  'name': name,
  'state': state,
  'checkedAt': DateTime.now().millisecondsSinceEpoch,
  'notices': notices,
  'messages': messages,
  'lastUsedAt': lastUsedAt,
  'failures': failures,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chh/accounts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AppearanceController appearance;
  late List<Map<String, Object>> accounts;
  late String? currentUid;
  late List<(String, Object?)> calls;

  setUp(() {
    final oldPlatform = InAppWebViewPlatform.instance;
    final oldFetchers = chhClient.fetchers.toList();
    final oldObserver = chhClient.htmlObserver;
    final oldCookies = chhSession.cookies;
    final oldBadges = chhSession.badges;
    final oldLoggedIn = chhSession.loggedIn;
    InAppWebViewPlatform.instance = _Platform();
    chhClient.fetchers
      ..clear()
      ..add(_HeaderlessPage());
    chhClient.htmlObserver = null;
    chhClient.clearCache();

    appearance = AppearanceController(directory: () async => null);
    currentUid = null;
    accounts = [];
    calls = [];
    chhSession.loggedIn = false;
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
    messenger.setMockMethodCallHandler(channel, (call) async {
      final uid = (call.arguments as Map?)?['uid'];
      calls.add((call.method, uid));
      switch (call.method) {
        case 'beginLogin':
          throw PlatformException(code: 'test_webview_disabled');
        case 'remove':
          accounts.removeWhere((account) => account['uid'] == uid);
          if (uid == currentUid) currentUid = null;
        case 'activate':
          currentUid = uid as String;
      }
      return {'currentUid': currentUid, 'max': 5, 'accounts': accounts};
    });

    addTearDown(() async {
      accounts.clear();
      currentUid = null;
      await accountStore.reload();
      messenger.setMockMethodCallHandler(channel, null);
      if (oldPlatform != null) InAppWebViewPlatform.instance = oldPlatform;
      chhClient.fetchers
        ..clear()
        ..addAll(oldFetchers);
      chhClient.htmlObserver = oldObserver;
      chhClient.clearCache();
      chhSession.cookies = oldCookies;
      chhSession.badges = oldBadges;
      chhSession.loggedIn = oldLoggedIn;
      appearance.dispose();
    });
  });

  void setCurrent(String uid, String name) {
    currentUid = uid;
    chhSession.loggedIn = true;
    chhSession.badges = HeaderBadges(
      uid: uid,
      userName: name,
      notices: 0,
      messages: 0,
    );
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await accountStore.reload();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(appearanceController: appearance),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> openAccount(WidgetTester tester, String uid) async {
    await tester.tap(row(uid));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheetSurface), findsOneWidget);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(AppSheetSurface))).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('settings separates the current identity from standard rows', (
    tester,
  ) async {
    setCurrent('1001', '甲');
    accounts.addAll([
      _account('1001', '甲'),
      _account('1002', '乙', notices: 2, messages: 1),
      _account('1003', '丙', notices: 9, failures: 4),
      _account('1004', '丁', state: 'expired', notices: 7, failures: 4),
    ]);
    final cache = spaceRepo.meCache;
    cache.select('1001');
    cache.put(const UserProfile(uid: '1001', name: '甲', groupId: 40));
    addTearDown(() => cache.select(null));
    await openSettings(tester);

    final current = row('1001');
    final avatar = inside(current, find.byType(AccountAvatar));
    expect(tester.getSize(avatar), const Size.square(52));
    expect(inside(current, find.text('UID 1001')), findsOneWidget);
    expect(
      tester.widget<LevelBadge>(inside(current, find.byType(LevelBadge))).gid,
      40,
    );
    expect(inside(current, find.byIcon(AppIcons.forward)), findsOneWidget);

    final unread = row('1002');
    expect(
      tester.getSize(inside(unread, find.byType(AccountAvatar))),
      const Size.square(EntryIconTokens.size),
    );
    expect(tester.getSize(unread).height, SettingsTokens.rowHeight);
    expect(find.text('UID 1002'), findsNothing);
    expect(inside(unread, find.text('3')), findsOneWidget);
    expect(inside(unread, find.byIcon(AppIcons.forward)), findsOneWidget);
    expect(inside(row('1003'), find.text('未能检查')), findsOneWidget);
    final expired = row('1004');
    expect(inside(expired, find.text('已失效')), findsOneWidget);
    expect(inside(expired, find.text('未能检查')), findsNothing);
    expect(
      inside(
        find.byKey(const ValueKey('settings-accounts')),
        find.byType(CountBadge),
      ),
      findsOneWidget,
    );

    accountStore.setSwitchingUid('1004');
    addTearDown(() => accountStore.setSwitchingUid(null));
    await tester.pump();
    expect(inside(expired, find.byType(ChhersSpinner)), findsOneWidget);
    expect(inside(expired, find.text('已失效')), findsNothing);
    accountStore.setSwitchingUid(null);
    await tester.pumpAndSettle();

    final add = find.byKey(const ValueKey('settings-add-account'));
    final addMark = inside(add, find.byType(AddAccountMark));
    expect(tester.getSize(addMark), const Size.square(EntryIconTokens.size));
    expect(inside(addMark, find.byType(CustomPaint)), findsOneWidget);
    expect(inside(addMark, find.byType(Icon)), findsNothing);
    expect(inside(add, find.byIcon(AppIcons.forward)), findsOneWidget);

    accounts[0]['state'] = 'expired';
    await accountStore.reload();
    await tester.pumpAndSettle();
    expect(inside(current, find.text('登录已失效')), findsOneWidget);
    expect(inside(current, find.text('UID 1001')), findsNothing);
    expect(inside(current, find.byType(LevelBadge)), findsNothing);
    await openAccount(tester, '1001');
    final sheet = find.byType(AppSheetSurface);
    expect(inside(sheet, find.text('登录已失效')), findsOneWidget);
    expect(inside(sheet, find.text('UID 1001')), findsOneWidget);
    expect(inside(sheet, find.byType(LevelBadge)), findsNothing);
    expect(inside(sheet, find.text('当前账号')), findsNothing);
    expect(find.text('重新登录'), findsOneWidget);
    expect(find.text('移除账号'), findsOneWidget);
    expect(find.text('切换到此账号'), findsNothing);
    await closeSheet(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'account action sheet shows one identity state and full-width actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      setCurrent('1001', '甲');
      accounts.addAll([
        _account('1001', '甲', notices: 1),
        _account('1002', '乙'),
        _account('1003', '丙', notices: 2, messages: 1),
        _account('1004', '丁', state: 'expired', notices: 1),
      ]);
      final cache = spaceRepo.meCache;
      cache.select('1001');
      cache.put(const UserProfile(uid: '1001', name: '甲', groupId: 40));
      addTearDown(() => cache.select(null));
      await openSettings(tester);

      final sheet = find.byType(AppSheetSurface);
      for (final (uid, name, status, primary) in [
        ('1001', '甲', '当前账号', null),
        ('1002', '乙', null, '切换到此账号'),
        ('1003', '丙', '3 条未读', '切换到此账号'),
        ('1004', '丁', '登录已失效', '重新登录'),
      ]) {
        await openAccount(tester, uid);
        final tokens = AppTokens.of(tester.element(sheet));
        expect(inside(sheet, find.byType(SheetHeader)), findsNothing);
        expect(inside(sheet, find.byTooltip('关闭')), findsNothing);
        expect(
          tester.getSize(inside(sheet, find.byType(AccountAvatar))),
          const Size.square(64),
        );
        expect(inside(sheet, find.text(name)), findsOneWidget);
        expect(inside(sheet, find.text('UID $uid')), findsOneWidget);
        expect(
          find.bySemanticsLabel([name, 'UID $uid', ?status].join('，')),
          findsOneWidget,
        );
        for (final label in ['当前账号', '3 条未读', '登录已失效', '1 条未读']) {
          expect(
            inside(sheet, find.text(label)),
            label == status ? findsOneWidget : findsNothing,
          );
        }
        if (uid == '1001') {
          final ring = inside(sheet, find.byType(CurrentAccountAvatar));
          expect(
            tester.widget<CurrentAccountAvatar>(ring).gapColor,
            tokens.surface,
          );
          expect(tester.getSize(ring), const Size.square(72));
          expect(inside(sheet, find.byType(LevelBadge)), findsOneWidget);
        }
        final buttons = inside(sheet, find.byType(PressScale));
        expect(buttons, findsNWidgets(primary == null ? 1 : 2));
        final bounds = tester.getRect(sheet);
        for (final label in [?primary, '移除账号']) {
          final button = find.ancestor(
            of: inside(sheet, find.text(label)),
            matching: buttons,
          );
          final rect = tester.getRect(button);
          expect(rect.height, SettingsTokens.confirmationButtonHeight);
          expect(rect.left, bounds.left + 16);
          expect(rect.right, bounds.right - 16);
          expect(find.bySemanticsLabel(label), findsOneWidget);
        }
        if (primary != null) {
          expect(
            tester.getRect(buttons.last).top -
                tester.getRect(buttons.first).bottom,
            8,
          );
        }
        await closeSheet(tester);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );

  testWidgets('account action sheet dismisses by drag, back or scrim', (
    tester,
  ) async {
    setCurrent('1001', '甲');
    accounts.add(_account('1001', '甲'));
    await openSettings(tester);
    final sheet = find.byType(AppSheetSurface);

    await openAccount(tester, '1001');
    final bounds = tester.getRect(sheet);
    await tester.dragFrom(
      bounds.topCenter + const Offset(0, 14),
      const Offset(0, 350),
    );
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await openAccount(tester, '1001');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await openAccount(tester, '1001');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings shows accounts for a session or a nonempty vault', (
    tester,
  ) async {
    await openSettings(tester);
    expect(find.text('账号'), findsNothing);

    accounts.add(_account('1001', '甲'));
    await accountStore.reload();
    await tester.pumpAndSettle();
    expect(find.text('账号'), findsOneWidget);
    expect(inside(row('1001'), find.text('甲')), findsOneWidget);
    expect(find.text('UID 1001'), findsNothing);
    expect(
      tester.getTopLeft(find.text('账号')).dy,
      lessThan(tester.getTopLeft(find.text('外观')).dy),
    );

    accounts.clear();
    chhSession.loggedIn = true;
    await accountStore.reload();
    await tester.pumpAndSettle();
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('添加账号'), findsOneWidget);
    expect(row('1001'), findsNothing);
    await tap(tester, '添加账号');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(calls, contains(('beginLogin', null)));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'settings account options follow status and disable add at capacity',
    (tester) async {
      setCurrent('1001', '甲');
      accounts.addAll([
        _account('1001', '甲'),
        _account('1002', '乙', lastUsedAt: 40),
        _account('1003', '丙', lastUsedAt: 30, state: 'expired'),
        _account('1004', '丁', lastUsedAt: 20),
        _account('1005', '戊', lastUsedAt: 10),
      ]);
      await openSettings(tester);
      final add = find.byKey(const ValueKey('settings-add-account'));
      expect(find.text('最多 5 个'), findsOneWidget);
      expect(inside(add, find.byIcon(AppIcons.forward)), findsNothing);
      expect(
        tester.widget<Opacity>(inside(add, find.byType(Opacity))).opacity,
        .5,
      );
      await tap(tester, '添加账号');
      expect(find.byType(LoginPage), findsNothing);

      await openAccount(tester, '1001');
      expect(find.text('移除账号'), findsOneWidget);
      expect(find.text('切换到此账号'), findsNothing);
      expect(find.text('重新登录'), findsNothing);
      await closeSheet(tester);

      await openAccount(tester, '1002');
      expect(find.text('切换到此账号'), findsOneWidget);
      expect(find.text('移除账号'), findsOneWidget);
      expect(find.text('重新登录'), findsNothing);
      await tap(tester, '切换到此账号');
      expect(calls, contains(('activate', '1002')));
      expect(chhSession.badges.uid, '1002');

      await openAccount(tester, '1003');
      expect(find.text('重新登录'), findsOneWidget);
      expect(find.text('移除账号'), findsOneWidget);
      expect(find.text('切换到此账号'), findsNothing);
      await tap(tester, '重新登录');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(calls, contains(('beginLogin', '1003')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('settings confirms removals and logs out the current account', (
    tester,
  ) async {
    setCurrent('1001', '甲');
    accounts.addAll([
      _account('1001', '甲'),
      _account('1002', '乙', lastUsedAt: 30),
      _account('1003', '丙', lastUsedAt: 20),
      _account('1004', '丁', lastUsedAt: 10),
    ]);
    await openSettings(tester);
    await openAccount(tester, '1002');
    await tap(tester, '移除账号');
    expect(find.text('移除 乙？'), findsOneWidget);
    expect(find.text('移除后需重新登录'), findsOneWidget);
    expect(calls, isNot(contains(('remove', '1002'))));
    await tap(tester, '取消');
    expect(calls, isNot(contains(('remove', '1002'))));

    await openAccount(tester, '1002');
    await tap(tester, '移除账号');
    await tap(tester, '移除');
    expect(calls, contains(('remove', '1002')));
    expect(calls.where((call) => call.$1 == 'activate'), isEmpty);
    expect(chhSession.badges.uid, '1001');
    expect(row('1002'), findsNothing);

    await openAccount(tester, '1001');
    await tap(tester, '移除账号');
    expect(find.text('移除 甲？'), findsOneWidget);
    expect(calls, isNot(contains(('remove', '1001'))));
    await tap(tester, '移除');
    expect(
      calls,
      containsAllInOrder([('remove', '1001'), ('activate', '1003')]),
    );
    expect(chhSession.badges.uid, '1003');
    expect(accountStore.currentUid, '1003');
    expect(find.text('UID 1001'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'settings logout confirmation names the most recent other account',
    (tester) async {
      setCurrent('1001', '甲');
      accounts.addAll([
        _account('1001', '甲'),
        _account('1002', '乙', lastUsedAt: 10),
        _account('1003', '丙', lastUsedAt: 20),
      ]);
      await openSettings(tester);
      await tester.scrollUntilVisible(
        find.text('退出登录'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('退出登录'));
      await tester.pumpAndSettle();
      await tap(tester, '退出登录');
      expect(find.text('退出当前账号？'), findsOneWidget);
      expect(find.text('将切换到 丙'), findsOneWidget);
      await tap(tester, '取消');
      expect(calls.where((call) => call.$1 == 'remove'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Finder row(String uid) => find.byKey(ValueKey('settings-account-$uid'));

Finder inside(Finder root, Finder matching) =>
    find.descendant(of: root, matching: matching);
