import 'dart:async';

import 'package:chh_app/data/space_repository.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/follow_block_page.dart';
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/account_widgets.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:chh_app/widgets/level_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _profile(String uid, {int? replies = 377, int? gid}) => UserProfile(
  uid: uid,
  name: '本地账号',
  group: '测试用户组',
  groupId: gid,
  credits: 3139,
  threads: 31,
  replies: replies,
);

class _Profiles extends SpaceRepository {
  _Profiles(DateTime Function() now) : super(ChhClient(fetchers: [], now: now));
  final requests = <(String, bool)>[];
  Future<UserProfile> Function(String)? respond;
  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) {
    requests.add((uid, refresh));
    return respond?.call(uid) ?? Future.value(_profile(uid));
  }
}

class _TrackedSpace extends SpaceRepository {
  _TrackedSpace(super.client);
  late Future<UserProfile> pending;

  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) =>
      pending = super.profile(uid, refresh: refresh);
}

TransitionRoute<void> _cover({required bool popup}) {
  const cover = Scaffold(body: Text('本地覆盖页'));
  if (popup) {
    return RawDialogRoute<void>(
      pageBuilder: (_, _, _) => cover,
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
  return _SlowCoverRoute();
}

class _SlowCoverRoute extends MaterialPageRoute<void> {
  _SlowCoverRoute()
    : super(builder: (_) => const Scaffold(body: Text('本地覆盖页')));

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 800);
}

class _Headers extends ChhFetcher {
  String html = '<div id="ct">本地资料</div>';
  int calls = 0;
  @override
  String get name => 'local-me-header';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    calls++;
    return ChhResponse(200, html);
  }
}

void _session({String? uid = '42', bool logged = true}) {
  chhSession.loggedIn = logged;
  chhSession.badges = HeaderBadges(
    notices: 0,
    messages: 0,
    uid: uid,
    userName: uid == null ? null : '本地账号 $uid',
  );
  // Simulate the existing session notification, with no cookie/device calls.
  // ignore: invalid_use_of_protected_member
  chhSession.notifyListeners();
}

late _Profiles _testProfiles;

Widget _app({
  Widget? page,
  AppearanceStyle style = AppearanceStyle.misty,
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool reduced = false,
}) => MaterialApp(
  theme: buildAppTheme(brightness, style),
  routes: {'/login': (_) => const Scaffold(body: Text('本地登录页'))},
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.only(top: 24),
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduced,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: page ?? MePage(repository: _testProfiles),
    bottomNavigationBar: const SizedBox(height: 84),
  ),
);

final _card = find.byKey(const ValueKey('me-identity-card'));
final _stats = find.byKey(const ValueKey('me-stats'));
final _placeholder = find.byKey(const ValueKey('me-stats-placeholder'));

void main() {
  late _Profiles profiles;
  late _Headers headers;
  late DateTime now;
  setUp(() {
    final oldBadges = chhSession.badges;
    final oldLogged = chhSession.loggedIn;
    final oldFetchers = List<ChhFetcher>.of(chhClient.fetchers);
    final oldObserver = chhClient.htmlObserver;
    now = DateTime.utc(2026, 11, 23);
    profiles = _Profiles(() => now);
    headers = _Headers();
    _testProfiles = profiles;
    chhClient.fetchers
      ..clear()
      ..add(headers);
    chhClient.clearCache();
    chhClient.htmlObserver = chhSession.observeHtml;
    _session();
    addTearDown(() {
      chhSession.badges = oldBadges;
      chhSession.loggedIn = oldLogged;
      chhClient.fetchers
        ..clear()
        ..addAll(oldFetchers);
      chhClient.htmlObserver = oldObserver;
      chhClient.clearCache();
    });
  });

  for (final style in AppearanceStyle.values) {
    testWidgets(
      'my level uses the shared badge and colophon stays at bottom $style',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        profiles.respond = (uid) async => _profile(uid, gid: 41);
        await tester.pumpWidget(_app(style: style));
        await tester.pumpAndSettle();
        final badge = tester.widget<LevelBadge>(find.byType(LevelBadge));
        expect(badge.gid, 41);
        expect(badge.onLacquer, style == AppearanceStyle.cinnabar);
        expect(find.text('能天使'), findsOneWidget);
        expect(find.text('测试用户组'), findsNothing);
        expect(tester.getBottomLeft(find.text('Chhers')).dy, 844 - 84 - 28);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('misty B real profile fields and geometry $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<UserProfile>();
      profiles.respond = (_) => pending.future;
      await tester.pumpWidget(_app(brightness: brightness));
      final before = tester.getRect(_card);
      expect(tester.getSize(_placeholder).height, 44);
      expect(find.text('积分'), findsNothing);
      pending.complete(_profile('42'));
      await tester.pumpAndSettle();
      expect(_placeholder, findsNothing);
      expect(tester.getRect(_card), before);
      for (final text in [
        'UID 42',
        '测试用户组',
        '3139',
        '31',
        '377',
        '积分',
        '主题',
        '回帖',
      ]) {
        expect(
          find.descendant(of: _card, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(profiles.requests, [('42', false)]);
      expect(tester.getSize(_stats).height, 44);
      expect(tester.getSize(find.byType(LacEntryStrip)).height, 90);
      final avatar = find.descendant(
        of: _card,
        matching: find.byType(AccountAvatar),
      );
      expect(tester.getSize(avatar), const Size(56, 56));
      for (final row in tester.widgetList<GroupedRow>(
        find.byType(GroupedRow),
      )) {
        expect(tester.getSize(find.byWidget(row)).height, 52);
      }
      expect(tester.getBottomLeft(find.text('Chhers')).dy, 844 - 84 - 28);
      final scroll = tester
          .widget<LacquerTabScaffold>(find.byType(LacquerTabScaffold))
          .controller;
      // Owned scrolling remains available; no data fetch is driven by scroll.
      expect(scroll, isNull);
      expect(headers.calls, 0);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.tap(find.text('3139'));
      // Only the route target matters here. Its profile parses on a real isolate.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UserPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('misty B guest login and three tools $brightness', (
      tester,
    ) async {
      _session(uid: null, logged: false);
      await tester.pumpWidget(_app(brightness: brightness));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _card, matching: find.text('未登录')),
        findsOneWidget,
      );
      expect(find.text('登录'), findsOneWidget);
      expect(find.text('登录 CHH'), findsNothing);
      expect(find.byType(LacEntryStrip), findsNothing);
      expect(find.byType(GroupedRow), findsNWidgets(3));
      final followBlock = find.text('关注及黑名单');
      expect(followBlock, findsOneWidget);
      expect(find.text('黑名单'), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('支持开发'), findsOneWidget);
      expect(_stats, findsNothing);
      expect(_placeholder, findsNothing);
      expect(profiles.requests, isEmpty);
      await tester.tap(followBlock);
      await tester.pumpAndSettle();
      expect(find.byType(FollowBlockPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LargeTitleHeader),
          matching: find.text('关注及黑名单'),
        ),
        findsOneWidget,
      );
      expect(find.text('还没有关注任何人'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(find.text('本地登录页'), findsOneWidget);
    });
  }

  for (final missing in [false, true]) {
    testWidgets(
      'profile ${missing ? 'missing field' : 'failure'} removes whole stat row',
      (tester) async {
        final pending = Completer<UserProfile>();
        profiles.respond = (_) => pending.future;
        await tester.pumpWidget(_app());
        expect(_placeholder, findsOneWidget);
        final height = tester.getSize(_card).height;
        if (missing) {
          pending.complete(_profile('42', replies: null));
        } else {
          pending.completeError(StateError('offline failure'));
        }
        await tester.pumpAndSettle();
        expect(_stats, findsNothing);
        expect(_placeholder, findsNothing);
        for (final label in ['积分', '主题', '回帖']) {
          expect(find.text(label), findsNothing);
        }
        expect(tester.getSize(_card).height, height - 60);
        expect(find.text('UID 42'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'first login waits for UID and loads profile after header hydration',
    (tester) async {
      _session(uid: null, logged: false);
      await tester.pumpWidget(_app());
      _session(uid: null);
      await tester.pump();
      expect(profiles.requests, isEmpty);
      headers.html =
          '<div id="um"><strong class="vwmy"><a href="space-uid-43.html">首次登录账号</a></strong></div>';
      await chhSession.ensureIdentity();
      await tester.pumpAndSettle();
      expect(find.text('首次登录账号'), findsWidgets);
      expect(find.text('UID 43'), findsOneWidget);
      expect(_stats, findsOneWidget);
      expect(profiles.requests, [('43', true)]);
      expect(headers.calls, 1);
    },
  );

  testWidgets(
    'cached stats render immediately and background data waits for re-entry',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final pending = Completer<UserProfile>();
      profiles.respond = (_) => pending.future;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app());
      expect(find.text('3139'), findsOneWidget);
      expect(_placeholder, findsNothing);
      pending.complete(
        const UserProfile(
          uid: '42',
          name: '本地账号',
          credits: 9999,
          threads: 41,
          replies: 400,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3139'), findsOneWidget);
      expect(find.text('9999'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      profiles.respond = (_) => Completer<UserProfile>().future;
      await tester.pumpWidget(_app());
      expect(find.text('9999'), findsOneWidget);
      expect(_placeholder, findsNothing);
    },
  );

  testWidgets(
    'logged-in UID hydration preserves but does not expose the cached identity',
    (tester) async {
      profiles.meCache.select('42');
      profiles.meCache.put(_profile('42'));
      _session(uid: null);
      profiles.respond = (_) => Completer<UserProfile>().future;
      await tester.pumpWidget(_app());
      expect(_stats, findsNothing);
      expect(find.text('UID 42'), findsNothing);
      expect(profiles.requests, isEmpty);
      expect(profiles.meCache.forUser('42')?.credits, 3139);
      _session(uid: '42');
      await tester.pump();
      expect(find.text('3139'), findsOneWidget);
      expect(_placeholder, findsNothing);
    },
  );

  testWidgets(
    'disposed older cache generation cannot replace a newer snapshot',
    (tester) async {
      final old = Completer<UserProfile>();
      profiles.respond = (_) => old.future;
      await tester.pumpWidget(_app());
      await tester.pumpWidget(const SizedBox.shrink());
      profiles.client.clearCache();
      profiles.respond = (_) async => const UserProfile(
        uid: '42',
        name: '本地账号',
        credits: 9999,
        threads: 41,
        replies: 400,
      );
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('9999'), findsOneWidget);
      old.complete(_profile('42'));
      await tester.pumpAndSettle();
      expect(profiles.meCache.forUser('42')?.credits, 9999);
    },
  );

  testWidgets(
    'rejected current generation releases loading for the next activation',
    (tester) async {
      final old = Completer<UserProfile>();
      profiles.respond = (_) => old.future;
      Widget view(bool active) => _app(
        page: TickerMode(
          enabled: active,
          child: MePage(repository: profiles),
        ),
      );
      await tester.pumpWidget(view(true));
      profiles.client.clearCache();
      old.complete(_profile('42'));
      await tester.pumpAndSettle();
      expect(_stats, findsNothing);
      expect(_placeholder, findsNothing);
      await tester.pumpWidget(view(false));
      profiles.respond = (_) async => _profile('42');
      await tester.pumpWidget(view(true));
      await tester.pumpAndSettle();
      expect(_stats, findsOneWidget);
      expect(profiles.requests.length, 2);
    },
  );

  testWidgets(
    'returning to a retained tab adopts the last background snapshot',
    (tester) async {
      Widget view(bool active) => _app(
        page: TickerMode(
          enabled: active,
          child: MePage(repository: profiles),
        ),
      );
      await tester.pumpWidget(view(true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(view(false));
      final pending = Completer<UserProfile>();
      profiles.respond = (_) => pending.future;
      now = now.add(const Duration(seconds: 60));
      await tester.pumpWidget(view(true));
      expect(find.text('3139'), findsOneWidget);
      expect(profiles.requests, [('42', false), ('42', true)]);
      pending.complete(
        const UserProfile(
          uid: '42',
          name: '本地账号',
          credits: 9999,
          threads: 41,
          replies: 400,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3139'), findsOneWidget);
      await tester.pumpWidget(view(false));
      profiles.respond = (_) => Completer<UserProfile>().future;
      await tester.pumpWidget(view(true));
      await tester.pumpAndSettle();
      expect(find.text('9999'), findsOneWidget);
      expect(profiles.requests, [('42', false), ('42', true)]);
    },
  );

  testWidgets('failed background refresh retains the cached counters', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    profiles.respond = (_) async => throw StateError('offline');
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('3139'), findsOneWidget);
    expect(_placeholder, findsNothing);
  });

  for (final popup in [false, true]) {
    testWidgets('Me stays built and throttles re-entry with popup=$popup', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.byType(MePage)));
      final body = find.byType(LacquerTabScaffold, skipOffstage: false);
      final original = tester.widget(body);
      void expectUnchanged() => expect(tester.widget(body), same(original));

      now = now.add(const Duration(seconds: 59));
      unawaited(navigator.push(_cover(popup: popup)));
      await tester.pump();
      expectUnchanged();
      await tester.pumpAndSettle();
      expectUnchanged();
      navigator.pop();
      await tester.pump();
      expectUnchanged();
      await tester.pumpAndSettle();
      await tester.pump(AppMotion.sheetDuration);
      expectUnchanged();
      expect(profiles.requests, [('42', false)]);

      final cover = _cover(popup: popup);
      unawaited(navigator.push(cover));
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 1));
      final exitStatusAtRequest = <AnimationStatus?>[];
      profiles.respond = (uid) async {
        exitStatusAtRequest.add(cover.animation?.status);
        return _profile(uid);
      };
      navigator.pop();
      await tester.pump();
      await tester.pump(
        popup ? const Duration(milliseconds: 200) : AppMotion.sheetDuration,
      );
      expect(cover.animation?.status, AnimationStatus.reverse);
      expectUnchanged();
      expect(profiles.requests, [('42', false)]);
      await tester.pumpAndSettle();
      await tester.pump(AppMotion.sheetDuration);
      await tester.pumpAndSettle();
      expect(profiles.requests, [('42', false), ('42', true)]);
      expect(exitStatusAtRequest, [AnimationStatus.dismissed]);
    });
  }

  testWidgets('an expired popup refresh is cancelled when covered again', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(MePage)));
    now = now.add(const Duration(seconds: 60));
    unawaited(navigator.push(_cover(popup: true)));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pump();
    final halfway = AppMotion.sheetDuration ~/ 2;
    await tester.pump(halfway);
    unawaited(navigator.push(_cover(popup: true)));
    await tester.pumpAndSettle();
    await tester.pump(AppMotion.sheetDuration);
    expect(profiles.requests, [('42', false)]);
    navigator.pop();
    await tester.pump();
    await tester.pump(AppMotion.sheetDuration);
    await tester.pumpAndSettle();
    expect(profiles.requests, [('42', false), ('42', true)]);
  });

  testWidgets('tab activation during popup exit waits for the exit', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      _app(
        page: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, enabled, child) =>
              TickerMode(enabled: enabled, child: child!),
          child: MePage(repository: profiles),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(MePage)));
    now = now.add(const Duration(seconds: 60));
    active.value = false;
    unawaited(navigator.push(_cover(popup: true)));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    active.value = true;
    await tester.pump();
    expect(profiles.requests, [('42', false)]);
    await tester.pump(AppMotion.sheetDuration);
    await tester.pumpAndSettle();
    expect(profiles.requests, [('42', false), ('42', true)]);
  });

  testWidgets('only a successful profile refresh restarts the cooldown', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(MePage)));
    Future<void> reenter() async {
      unawaited(navigator.push(_cover(popup: true)));
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pump();
      await tester.pump(AppMotion.sheetDuration);
      await tester.pumpAndSettle();
    }

    now = now.add(const Duration(seconds: 60));
    profiles.respond = (_) async => throw StateError('offline');
    await reenter();
    expect(profiles.requests, [('42', false), ('42', true)]);
    profiles.respond = (uid) async => _profile(uid);
    await reenter();
    expect(profiles.requests, [('42', false), ('42', true), ('42', true)]);
    await reenter();
    expect(profiles.requests, hasLength(3));
  });

  testWidgets('account switch and disposal cancel deferred popup refreshes', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(MePage)));
    Future<void> popAfterSuccessExpires() async {
      now = now.add(const Duration(seconds: 60));
      unawaited(navigator.push(_cover(popup: true)));
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    await popAfterSuccessExpires();
    _session(uid: '43');
    expect(profiles.requests, [('42', false), ('43', true)]);
    await tester.pumpAndSettle();
    await tester.pump(AppMotion.sheetDuration);
    expect(profiles.requests, [('42', false), ('43', true)]);

    await popAfterSuccessExpires();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(AppMotion.sheetDuration);
    expect(profiles.requests, [('42', false), ('43', true)]);
  });

  testWidgets('account replacement and logout discard late profile responses', (
    tester,
  ) async {
    final old = Completer<UserProfile>();
    final next = Completer<UserProfile>();
    profiles.respond = (uid) => uid == '42' ? old.future : next.future;
    await tester.pumpWidget(_app());
    _session(uid: '43');
    expect(profiles.requests, [('42', false), ('43', true)]);
    await tester.pump();
    expect(find.text('UID 42'), findsNothing);
    expect(find.text('UID 43'), findsOneWidget);
    old.complete(_profile('42'));
    await tester.pumpAndSettle();
    expect(_stats, findsNothing);
    expect(_placeholder, findsOneWidget);
    _session(uid: null, logged: false);
    next.complete(_profile('43'));
    await tester.pumpAndSettle();
    expect(_stats, findsNothing);
    expect(_placeholder, findsNothing);
    expect(find.text('测试用户组'), findsNothing);
    expect(find.byType(LacEntryStrip), findsNothing);
    expect(profiles.requests, [('42', false), ('43', true)]);
  });

  testWidgets(
    'pull refresh reloads profile and preserves stats until completion',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final pending = Completer<UserProfile>();
      profiles.respond = (_) => pending.future;
      final refresh = tester
          .widget<LacquerTabScaffold>(find.byType(LacquerTabScaffold))
          .onRefresh!();
      await tester.pump();
      expect(_stats, findsOneWidget);
      expect(_placeholder, findsNothing);
      expect(find.text('3139'), findsOneWidget);
      pending.complete(
        const UserProfile(
          uid: '42',
          name: '本地账号',
          credits: 0,
          threads: 0,
          replies: 0,
        ),
      );
      await refresh;
      await tester.pumpAndSettle();
      expect(profiles.requests, [('42', false), ('42', true)]);
      expect(headers.calls, 1);
      expect(
        find.descendant(of: _stats, matching: find.text('0')),
        findsNWidgets(3),
      );
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('entry shadow and settings row height $style $brightness', (
        tester,
      ) async {
        await tester.pumpWidget(_app(style: style, brightness: brightness));
        await tester.pumpAndSettle();
        final strip = find.byType(LacEntryStrip);
        final box = tester.widget<DecoratedBox>(
          find.descendant(of: strip, matching: find.byType(DecoratedBox)).first,
        );
        final t = AppTokens.of(tester.element(strip));
        expect(
          (box.decoration as ShapeDecoration).shadows,
          style == AppearanceStyle.misty
              ? MeTokens.cardShadow(t)
              : MeTokens.floatingShadow(t),
        );
        if (style == AppearanceStyle.cinnabar) {
          expect(_card, findsNothing);
          expect(_stats, findsNothing);
          expect(profiles.requests, [('42', false)]);
          expect(find.text('chh'), findsOneWidget);
        }
        await tester.pumpWidget(
          _app(
            page: const SettingsPage(),
            style: style,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        for (final label in ['图片缓存', '运行日志', '关于 Chhers']) {
          final row = find.byWidgetPredicate(
            (w) => w is PressHighlight && w.semanticLabel == label,
          );
          await tester.scrollUntilVisible(
            row,
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.getSize(row).height, 52);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('switching styles retains the Me scroll position', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position().jumpTo(24);
    await tester.pumpAndSettle();
    expect(position().pixels, 24);
    await tester.pumpWidget(_app(style: AppearanceStyle.cinnabar));
    await tester.pumpAndSettle();
    expect(position().pixels, 24);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(position().pixels, 24);
  });

  testWidgets(
    're-entry refreshes behind the cached profile and manual refresh bypasses it',
    (tester) async {
      headers.html =
          '''<div id="ct"><div class="u_profile"><h2 class="mbn">本地账号</h2>
      <ul><li><em>统计信息</em><a>主题数 31</a><a>回帖数 377</a></li></ul>
      <div><h2>活跃概况</h2><ul><li><em>用户组</em><a>测试用户组</a></li></ul></div>
      <ul id="psts"><li><em>积分</em>3139</li></ul></div></div>''';
      final repository = _TrackedSpace(chhClient);
      Widget app() => _app(page: MePage(repository: repository));
      Future<void> mount() async {
        await tester.runAsync(() async {
          await tester.pumpWidget(app());
          await repository.pending;
        });
        await tester.pumpAndSettle();
      }

      await mount();
      expect(find.text('3139'), findsOneWidget);
      expect(headers.calls, 1);
      await tester.pumpWidget(_app(page: const SizedBox()));
      await mount();
      expect(headers.calls, 2);
      final refresh = tester
          .widget<LacquerTabScaffold>(find.byType(LacquerTabScaffold))
          .onRefresh!;
      await tester.runAsync(refresh);
      await tester.pumpAndSettle();
      expect(headers.calls, 4);
      expect(_stats, findsOneWidget);
    },
  );

  testWidgets('misty card fits 320dp and double text with reduced motion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(scale: 2, reduced: true));
    await tester.pumpAndSettle();
    expect(_stats, findsOneWidget);
    expect(find.text('测试用户组'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
