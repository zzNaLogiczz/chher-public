import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/login_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/sheet_scaffold.dart';
import 'package:chh_app/widgets/account_row_parts.dart';
import 'package:chh_app/widgets/account_switcher_sheet.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:chh_app/widgets/level_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('chh/accounts');
const _sessionChannel = MethodChannel('chh/session');

class _Cookies extends PlatformCookieManager {
  _Cookies()
    : super.implementation(const PlatformCookieManagerCreationParams());

  String uid = '1001';

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => [
    Cookie(name: 'test_auth', value: 'fixture-$uid'),
    Cookie(name: 'test_saltkey', value: 'fixture-salt'),
  ];
}

class _Platform extends InAppWebViewPlatform {
  final jar = _Cookies();

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => jar;
}

class _Headers extends ChhFetcher {
  _Headers(this.cookies);

  final _Cookies cookies;

  @override
  String get name => 'local-fixture';

  @override
  Future<ChhResponse> getHtml(
    Uri url, {
    Map<String, String>? headers,
  }) async => ChhResponse(
    200,
    '<div id="um"><strong class="vwmy"><a href="space-uid-${cookies.uid}.html">'
    'Account ${cookies.uid}</a></strong></div>',
  );
}

Map<String, Object?> _account(
  int uid, {
  required int checkedAt,
  String state = 'ok',
  int notices = 0,
  int messages = 0,
  int failures = 0,
  int lastUsedAt = 0,
}) => {
  'uid': '$uid',
  'name': 'Account $uid',
  'state': state,
  'checkedAt': checkedAt,
  'notices': notices,
  'messages': messages,
  'failures': failures,
  'lastUsedAt': lastUsedAt,
};

class _Vault {
  _Vault(this.accounts, this.jar);

  final List<Map<String, Object?>> accounts;
  final _Cookies jar;
  final calls = <MethodCall>[];
  Future<void> Function(String)? onActivate;

  Future<Object?> call(MethodCall call) async {
    calls.add(call);
    if (call.method == 'beginLogin') {
      throw PlatformException(code: 'login_pending');
    }
    if (call.method == 'activate') {
      final uid = call.arguments['uid'] as String;
      await onActivate?.call(uid);
      jar.uid = uid;
    }
    return {'currentUid': jar.uid, 'max': 5, 'accounts': accounts};
  }
}

Future<_Vault> _open(
  WidgetTester tester,
  List<Map<String, Object?>> accounts,
) async {
  final previous = InAppWebViewPlatform.instance;
  final fetchers = List<ChhFetcher>.of(chhClient.fetchers);
  final observer = chhClient.htmlObserver;
  final badges = chhSession.badges;
  final cookies = chhSession.cookies;
  final loggedIn = chhSession.loggedIn;
  final platform = _Platform();
  final vault = _Vault(accounts, platform.jar);
  final messenger = tester.binding.defaultBinaryMessenger;
  InAppWebViewPlatform.instance = platform;
  chhClient.fetchers
    ..clear()
    ..add(_Headers(platform.jar));
  chhClient.htmlObserver = chhSession.observeHtml;
  chhClient.clearCache();
  messenger.setMockMethodCallHandler(_channel, vault.call);
  messenger.setMockMethodCallHandler(_sessionChannel, (_) async => null);
  addTearDown(() async {
    // Discard the fake list before removing the channel.
    vault.accounts.clear();
    await accountStore.reload();
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(_sessionChannel, null);
    if (previous != null) InAppWebViewPlatform.instance = previous;
    chhClient.fetchers
      ..clear()
      ..addAll(fetchers);
    chhClient.htmlObserver = observer;
    chhClient.clearCache();
    chhSession.badges = badges;
    chhSession.cookies = cookies;
    chhSession.loggedIn = loggedIn;
  });
  await accountStore.reload();
  await chhSession.refresh();
  chhSession.badges = const HeaderBadges(
    notices: 0,
    messages: 0,
    uid: '1001',
    userName: 'Account 1001',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      routes: {
        '/settings': (_) => const Scaffold(body: Text('Settings destination')),
      },
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAccountSwitcher(context),
            child: const Text('Open accounts'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open accounts'));
  await tester.pumpAndSettle();
  return vault;
}

Finder _row(int uid) => find.widgetWithText(AccountListRow, 'Account $uid');

void main() {
  testWidgets('add account marks paint equal strokes on the accent circle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: Column(
            children: [AddAccountMark.switcher(), AddAccountMark.settings()],
          ),
        ),
      ),
    );
    final marks = find.byType(AddAccountMark);
    final tokens = AppTokens.of(tester.element(marks.first));
    for (final (index, size, length, width) in [
      (0, 44.0, 18.0, 2.0),
      (1, 32.0, 14.0, 1.8),
    ]) {
      final mark = marks.at(index);
      final background = find.descendant(
        of: mark,
        matching: find.byType(DecoratedBox),
      );
      expect(
        tester.widget<DecoratedBox>(background).decoration,
        BoxDecoration(color: tokens.accentFill, shape: BoxShape.circle),
      );
      final center = Size.square(size).center(Offset.zero);
      final halfSpan = (length - width) / 2;
      final horizontal = Offset(halfSpan, 0);
      final vertical = Offset(0, halfSpan);
      // Paint stores stroke widths at single precision.
      final expectedWidth = (Paint()..strokeWidth = width).strokeWidth;
      expect(
        find.descendant(of: mark, matching: find.byType(CustomPaint)),
        paints
          ..line(
            p1: center - horizontal,
            p2: center + horizontal,
            strokeWidth: expectedWidth,
            color: tokens.accent,
          )
          ..line(
            p1: center - vertical,
            p2: center + vertical,
            strokeWidth: expectedWidth,
            color: tokens.accent,
          ),
      );
    }
  });

  testWidgets(
    'account sheet sorts rows, shows states and checks only stale accounts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final now = chhClient.now().millisecondsSinceEpoch;
      final past = now - const Duration(minutes: 16).inMilliseconds;
      final fresh = now - const Duration(minutes: 2).inMilliseconds;
      spaceRepo.meCache
        ..select('1001')
        ..put(
          const UserProfile(uid: '1001', name: 'Account 1001', groupId: 38),
        );
      addTearDown(() => spaceRepo.meCache.select(null));
      final vault = await _open(tester, [
        _account(
          1003,
          checkedAt: past,
          state: 'expired',
          failures: 4,
          notices: 1,
          lastUsedAt: 20,
        ),
        _account(1001, checkedAt: past),
        _account(
          1002,
          checkedAt: fresh,
          notices: 2,
          messages: 3,
          lastUsedAt: 30,
        ),
        _account(
          1004,
          checkedAt: past,
          failures: 4,
          notices: 1,
          lastUsedAt: 10,
        ),
        _account(1005, checkedAt: fresh, lastUsedAt: 40),
      ]);
      expect(
        tester
            .widgetList<AccountListRow>(find.byType(AccountListRow))
            .map((row) => row.account.uid),
        ['1001', '1005', '1002', '1003', '1004'],
      );
      expect(find.text('UID 1001'), findsOneWidget);
      expect(
        find.descendant(of: _row(1001), matching: find.text('当前')),
        findsOneWidget,
      );
      final highlight = find.byKey(const ValueKey('account-current-highlight'));
      final ring = find
          .descendant(
            of: find.byKey(const ValueKey('account-current-ring')),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final tokens = AppTokens.of(tester.element(highlight));
      expect(
        (tester.widget<DecoratedBox>(highlight).decoration as BoxDecoration)
            .color,
        tokens.surface2,
      );
      expect(
        (tester.widget<DecoratedBox>(ring).decoration as BoxDecoration).color,
        tokens.accent,
      );
      expect(tester.getSize(ring), const Size.square(56));
      expect(
        find.descendant(of: _row(1001), matching: find.byType(LevelBadge)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row(1002), matching: find.text('5')),
        findsOneWidget,
      );
      expect(find.text('登录已失效'), findsOneWidget);
      expect(find.text('UID 1003'), findsNothing);
      expect(find.text('重新登录'), findsOneWidget);
      expect(find.text('未能检查'), findsOneWidget);
      expect(find.byType(CountBadge), findsOneWidget);
      expect(find.text('最多 5 个'), findsOneWidget);
      final mark = find.descendant(
        of: find.byType(AddAccountRow),
        matching: find.byType(AddAccountMark),
      );
      expect(tester.getSize(mark), const Size.square(44));
      expect(
        find.descendant(of: mark, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(
                    of: find.byType(AddAccountRow),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        .5,
      );
      expect(find.bySemanticsLabel(RegExp('当前账号')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Account 1003 登录已失效，重新登录')),
        findsOneWidget,
      );
      expect(
        tester.widget<AddAccountRow>(find.byType(AddAccountRow)).onPressed,
        isNull,
      );
      expect(
        vault.calls.singleWhere((call) => call.method == 'check').arguments,
        {
          'uids': ['1003', '1004'],
          'force': true,
        },
      );
      semantics.dispose();
    },
  );

  testWidgets('account sheet waits on one row and closes after switching', (
    tester,
  ) async {
    final now = chhClient.now().millisecondsSinceEpoch;
    final vault = await _open(tester, [
      _account(1001, checkedAt: now),
      _account(1002, checkedAt: now, notices: 3),
      _account(1003, checkedAt: now),
    ]);
    final activate = Completer<void>();
    vault.onActivate = (_) => activate.future;

    await tester.tap(_row(1002));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.descendant(of: _row(1002), matching: find.byType(ChhersSpinner)),
      findsOneWidget,
    );
    expect(find.byType(CountBadge), findsNothing);
    expect(tester.widget<AccountListRow>(_row(1003)).onPressed, isNull);

    activate.complete();
    await tester.pumpAndSettle();
    expect(find.text('切换账号'), findsNothing);
    expect(chhSession.badges.uid, '1002');
  });

  testWidgets('account sheet keeps expiry and switch failure inline', (
    tester,
  ) async {
    final now = chhClient.now().millisecondsSinceEpoch;
    final vault = await _open(tester, [
      _account(1001, checkedAt: now),
      _account(1002, checkedAt: now),
      _account(1003, checkedAt: now),
    ]);
    vault.onActivate = (uid) async {
      throw PlatformException(
        code: uid == '1002' ? 'account_expired' : 'account_not_found',
      );
    };

    await tester.tap(_row(1002));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _row(1002), matching: find.text('登录已失效')),
      findsOneWidget,
    );
    await tester.tap(_row(1003));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _row(1003), matching: find.text('未能切换，点按重试')),
      findsOneWidget,
    );
    expect(find.text('切换账号'), findsOneWidget);
    expect(chhSession.badges.uid, '1001');

    await tester.tap(_row(1002));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(vault.calls.last.method, 'beginLogin');
    expect(vault.calls.last.arguments, {'uid': '1002'});
  });

  testWidgets('account sheet opens add login below the limit', (tester) async {
    final vault = await _open(tester, [
      _account(1001, checkedAt: chhClient.now().millisecondsSinceEpoch),
    ]);
    await tester.tap(find.text('添加账号'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(vault.calls.last.method, 'beginLogin');
    expect(vault.calls.last.arguments, isEmpty);
  });

  testWidgets('manage dismisses the account sheet and opens settings', (
    tester,
  ) async {
    await _open(tester, []);
    expect(find.byTooltip('关闭'), findsNothing);
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    expect(find.text('Settings destination'), findsOneWidget);
    expect(find.text('切换账号', skipOffstage: false), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open accounts'), findsOneWidget);
    expect(find.text('切换账号'), findsNothing);
  });

  testWidgets('account sheet still dismisses by drag, back or scrim', (
    tester,
  ) async {
    await _open(tester, []);
    await tester.drag(find.text('切换账号'), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(find.text('切换账号'), findsNothing);

    await tester.tap(find.text('Open accounts'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('切换账号'), findsNothing);

    await tester.tap(find.text('Open accounts'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('切换账号'), findsNothing);
  });

  testWidgets('other sheet headers retain the default close button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) => const SheetScaffold(
                  title: 'Other sheet',
                  body: Text('Panel'),
                ),
              ),
              child: const Text('Open other sheet'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open other sheet'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('Other sheet'), findsNothing);
  });
}
