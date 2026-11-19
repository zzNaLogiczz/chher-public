import 'package:chh_app/design/icons.dart';
import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/pages/my_threads_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/account_widgets.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/space_fixtures.dart';

const _labels = ['我的帖子', '我的收藏', '积分记录', '勋章'];

class _ThreadsFetcher extends ChhFetcher {
  final requests = <Uri>[];
  String? response;

  @override
  String get name => 'offline-me-entries';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests.add(url);
    if (response case final html?) return ChhResponse(200, html);
    return const ChhResponse(
      200,
      '<div id="ct"><form id="delform"><table>'
      '<tr><th><a href="thread-900001-1-1.html">本地测试主题</a></th></tr>'
      '</table></form></div>',
    );
  }
}

Widget _app({
  Widget? page,
  Brightness brightness = Brightness.light,
  AppearanceStyle style = AppearanceStyle.cinnabar,
  double textScale = 1,
  bool reduced = false,
}) => MaterialApp(
  theme: buildAppTheme(brightness, style),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: reduced,
      padding: const EdgeInsets.only(top: 24),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: page ?? MePage(repository: FixtureSpace()),
    bottomNavigationBar: const SizedBox(height: 88),
  ),
);

void main() {
  late _ThreadsFetcher fetcher;

  setUp(() {
    final loggedIn = chhSession.loggedIn;
    final badges = chhSession.badges;
    final fetchers = List<ChhFetcher>.of(chhClient.fetchers);
    fetcher = _ThreadsFetcher();
    chhClient.fetchers
      ..clear()
      ..add(fetcher);
    chhClient.clearCache();
    chhSession.loggedIn = true;
    chhSession.badges = const HeaderBadges(
      notices: 0,
      messages: 0,
      userName: '测试账号',
      uid: '100001',
    );
    addTearDown(() {
      chhSession.loggedIn = loggedIn;
      chhSession.badges = badges;
      chhClient.fetchers
        ..clear()
        ..addAll(fetchers);
      chhClient.clearCache();
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'cinnabar mast paints its watermark below paper and cards $brightness',
      (tester) async {
        await tester.pumpWidget(_app(brightness: brightness));
        await tester.pumpAndSettle();
        final mast = find.byKey(const ValueKey('tab-mast-background'));
        final scrollContent = find.byKey(const ValueKey('tab-scroll-content'));
        final watermark = find.text('chh');
        final entries = find.byType(LacEntryStrip);
        final painter = find.ancestor(
          of: watermark,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.foregroundPainter != null,
          ),
        );

        expect(find.descendant(of: mast, matching: watermark), findsOneWidget);
        expect(find.descendant(of: mast, matching: painter), findsOneWidget);
        expect(
          find.descendant(of: scrollContent, matching: entries),
          findsOneWidget,
        );
        final layers = tester
            .widgetList<Stack>(find.byType(Stack))
            .singleWhere(
              (stack) => stack.children.contains(tester.widget(mast)),
            )
            .children;
        expect(
          layers.indexOf(tester.widget(mast)),
          lessThan(layers.indexOf(tester.widget(scrollContent))),
        );
      },
    );
  }

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.3, 2.0]) {
        testWidgets(
          'shared identity and floating entries fit $style $brightness ${scale}x',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(360, 640));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              _app(style: style, brightness: brightness, textScale: scale),
            );
            await tester.pumpAndSettle();
            final strip = find.byType(LacEntryStrip);
            final scaffold = tester.widget<LacquerTabScaffold>(
              find.byType(LacquerTabScaffold),
            );
            expect(scaffold.title, '我的');
            final compactAvatar = scaffold.compactLeading! as AccountAvatar;
            expect(compactAvatar.size, MeTokens.compactAvatar);
            expect(compactAvatar.name, '测试账号');
            expect(compactAvatar.url, chhSession.badges.avatarUrl);
            expect(scaffold.seamOverlap, MeTokens.overlap);
            expect(scaffold.onRefresh, isNotNull);
            expect(find.byType(EntryGrid), findsNothing);
            expect(find.text('UID 100001'), findsOneWidget);
            expect(find.text('主页'), findsOneWidget);
            // At 2x the tools start below the viewport; measure painted cards.
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('me-tools')),
              120,
            );
            await tester.pumpAndSettle();
            final rect = tester.getRect(strip);
            expect(rect.left, AppSpace.groupInset);
            expect(rect.right, 360 - AppSpace.groupInset);
            final tools = tester.getRect(
              find.byKey(const ValueKey('me-tools')),
            );
            expect(tools.top - rect.bottom, closeTo(MeTokens.cardGap, .01));
            expect(find.byType(Divider), findsNothing);
            final cells = find.byType(LacEntryCell);
            expect(cells, findsNWidgets(4));
            final first = tester.getRect(cells.first);
            final third = tester.getRect(cells.at(2));
            expect(first.height, greaterThanOrEqualTo(44));
            if (scale >= 1.5) {
              expect(third.top, greaterThan(first.top));
            } else {
              expect(third.top, first.top);
            }
            for (final label in _labels) {
              expect(
                find.descendant(of: strip, matching: find.text(label)),
                findsOneWidget,
              );
            }
            final icons = tester.widgetList<Icon>(
              find.descendant(of: strip, matching: find.byType(Icon)),
            );
            expect(
              icons.map((icon) => icon.size),
              everyElement(EntryIconTokens.glyphSize),
            );
            expect(
              icons.map((icon) => icon.color),
              everyElement(AppTokens.of(tester.element(strip)).accent),
            );
            expect(fetcher.requests, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(strip);
            await tester.pumpAndSettle();
            final position = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
            position.jumpTo(position.pixels - 48);
            await tester.pumpAndSettle();
            final initialTop = tester.getTopLeft(strip).dy;
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -64),
            );
            await tester.pumpAndSettle();
            expect(tester.getTopLeft(strip).dy, lessThan(initialTop));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('lacquer 我的帖子 opens the real route through fake transport', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的帖子'));
    await tester.pumpAndSettle();
    expect(find.byType(MyThreadsPage), findsOneWidget);
    expect(find.text('本地测试主题'), findsOneWidget);
    expect(fetcher.requests, hasLength(1));
    expect(fetcher.requests.single.queryParameters['do'], 'thread');
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh uses existing header observation through fake transport', (
    tester,
  ) async {
    final observer = chhClient.htmlObserver;
    chhClient.htmlObserver = chhSession.observeHtml;
    addTearDown(() => chhClient.htmlObserver = observer);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(fetcher.requests, isEmpty);
    fetcher.response =
        '<div id="um"><strong class="vwmy"><a href="space-uid-100001.html">更新后的账号</a></strong></div>';
    final scaffold = tester.widget<LacquerTabScaffold>(
      find.byType(LacquerTabScaffold),
    );
    await scaffold.onRefresh!();
    await tester.pumpAndSettle();
    expect(fetcher.requests, hasLength(1));
    expect(fetcher.requests.single.path, '/forum.php');
    expect(chhSession.badges.userName, '更新后的账号');
    expect(
      tester.widget<LacquerTabScaffold>(find.byType(LacquerTabScaffold)).title,
      '我的',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('me-identity-row')),
        matching: find.text('更新后的账号'),
      ),
      findsOneWidget,
    );
    expect(find.text('UID 100001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest header follows login, identity refresh and logout', (
    tester,
  ) async {
    chhSession.loggedIn = false;
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
    final observer = chhClient.htmlObserver;
    chhClient.htmlObserver = chhSession.observeHtml;
    addTearDown(() => chhClient.htmlObserver = observer);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(LacEntryStrip), findsNothing);

    // Local header fixture follows the source site's account and avatar links.
    chhSession.loggedIn = true;
    fetcher.response = '''
      <div id="um">
        <div class="avt y"><a href="space-uid-100002.html">
          <img class="user_avatar" src="/uc_server/avatar.php?uid=100002">
        </a></div>
        <strong class="vwmy"><a href="space-uid-100002.html">首次登录账号</a></strong>
      </div>
    ''';
    // Cookie refresh publishes login first; the subsequent identity response
    // must rebuild the already mounted header as well as the entry strip.
    // ignore: invalid_use_of_protected_member
    chhSession.notifyListeners();
    await tester.pump();
    expect(find.text('登录 CHH'), findsNothing);
    expect(find.text('登录'), findsNothing);
    await chhSession.ensureIdentity();
    await tester.pumpAndSettle();
    expect(find.text('登录 CHH'), findsNothing);
    expect(find.text('登录'), findsNothing);
    expect(find.text('首次登录账号'), findsWidgets);
    expect(find.text('UID 100002'), findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
    expect(find.byType(LacEntryStrip), findsOneWidget);
    final avatar = tester
        .widgetList<AccountAvatar>(find.byType(AccountAvatar))
        .singleWhere((avatar) => avatar.size == MeTokens.avatar);
    expect(avatar.name, '首次登录账号');
    expect(avatar.url, chhSession.badges.avatarUrl);
    expect(avatar.url, ChhUrls.avatar('100002'));

    chhSession.observeHtml('''
      <div id="um"><strong class="vwmy">
        <a href="space-uid-100002.html">更新后的名字</a>
      </strong></div>
    ''');
    await tester.pumpAndSettle();
    expect(find.text('首次登录账号'), findsNothing);
    expect(find.text('更新后的名字'), findsWidgets);

    chhSession.loggedIn = false;
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
    // Simulate the notification emitted after cookie removal, without a device.
    // ignore: invalid_use_of_protected_member
    chhSession.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('登录 CHH'), findsWidgets);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('更新后的名字'), findsNothing);
    expect(find.text('主页'), findsNothing);
    expect(find.textContaining('UID '), findsNothing);
    expect(find.byType(LacEntryStrip), findsNothing);
    expect(
      tester.widget<AccountAvatar>(find.byType(AccountAvatar)).url,
      isNull,
    );
    expect(fetcher.requests, [ChhUrls.forumIndex()]);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('watermark is cropped behind entries $brightness ${scale}x', (
        tester,
      ) async {
        await tester.pumpWidget(_app(brightness: brightness, textScale: scale));
        await tester.pumpAndSettle();
        final text = find.text('chh');
        final mark = tester.getRect(text);
        final visible = tester.getRect(
          find.ancestor(of: text, matching: find.byType(ClipRect)).first,
        );
        final entries = tester.getRect(find.byType(LacEntryStrip));
        final identity = tester.getRect(
          find.byKey(const ValueKey('me-identity-row')),
        );
        expect(mark.height, closeTo(TabChromeTokens.watermarkSize, .01));
        expect(visible.bottom - entries.top, closeTo(MeTokens.overlap, .01));
        expect(mark.bottom, greaterThan(visible.bottom));
        expect(
          entries.top - mark.top,
          closeTo(
            TabChromeTokens.watermarkVisibleHeight - MeTokens.overlap,
            .01,
          ),
        );
        expect(
          entries.top - identity.bottom,
          MeTokens.headerTail + TabChromeTokens.headerBottom,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('unknown identity does not invent uid or a profile target', (
    tester,
  ) async {
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('UID'), findsNothing);
    expect(find.textContaining('UID '), findsNothing);
    expect(find.text('主页'), findsNothing);
    for (final label in _labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(fetcher.requests, isEmpty);
  });

  testWidgets('guest lacquer mast hides all four entries', (tester) async {
    chhSession.loggedIn = false;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.byType(LacEntryStrip), findsNothing);
    for (final label in _labels) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('登录 CHH').first, findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(fetcher.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final style in AppearanceStyle.values) {
    testWidgets('fallback keeps matching identity and four entries in $style', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          page: MeFallbackPage(repository: FixtureSpace()),
          style: style,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LacquerTabScaffold), findsNothing);
      if (style == AppearanceStyle.misty) {
        expect(find.byType(LacEntryStrip), findsOneWidget);
        expect(find.byType(LacEntryCell), findsNWidgets(4));
        expect(find.byKey(const ValueKey('me-stats')), findsOneWidget);
      } else {
        expect(find.byType(LacEntryStrip), findsNothing);
        expect(find.byType(EntryGrid), findsOneWidget);
        expect(find.byType(EntryTile), findsNWidgets(4));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('misty guest keeps login identity without entries', (
    tester,
  ) async {
    chhSession.loggedIn = false;
    await tester.pumpWidget(_app(style: AppearanceStyle.misty));
    await tester.pumpAndSettle();
    expect(find.byType(LacquerTabScaffold), findsOneWidget);
    expect(find.byType(LacEntryStrip), findsNothing);
    expect(find.text('未登录'), findsWidgets);
    expect(find.text('登录 CHH'), findsNothing);
    expect(find.text('登录'), findsOneWidget);
    for (final label in _labels) {
      expect(find.text(label), findsNothing);
    }
    expect(fetcher.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final style in AppearanceStyle.values) {
    testWidgets('$style tools use themed icon tiles and no theme badge', (
      tester,
    ) async {
      await tester.pumpWidget(_app(style: style));
      await tester.pumpAndSettle();
      final settings = find.byKey(const ValueKey('me-settings'));
      expect(tester.widget<GroupedRow>(settings).value, isNull);
      expect(tester.widget<GroupedRow>(settings).subtitle, isNull);
      expect(find.text('薄暮'), findsNothing);
      expect(find.text('朱砂'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('me-tools')),
          matching: find.byType(IconTile),
        ),
        findsNWidgets(2),
      );
      expect(find.byType(Divider), findsNothing);
      final dot = find.descendant(
        of: settings,
        matching: find.byType(DotBadge),
      );
      final arrow = find.descendant(
        of: settings,
        matching: find.byIcon(AppIcons.forward),
      );
      expect(tester.getCenter(dot).dx, lessThan(tester.getCenter(arrow).dx));
      expect(find.text('Chhers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'entry button semantics and shared feedback, reduced=$reduced',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          var taps = 0;
          await tester.pumpWidget(
            _app(
              reduced: reduced,
              page: Center(
                child: SizedBox(
                  width: 80,
                  child: LacEntryCell(
                    icon: AppIcons.articleBold,
                    label: '我的帖子',
                    onTap: () => taps++,
                  ),
                ),
              ),
            ),
          );
          final cell = find.byType(LacEntryCell);
          final node = tester.getSemantics(cell);
          expect(node.flagsCollection.isButton, isTrue);
          expect(node.label, '我的帖子');
          final press = tester.widget<PressScale>(find.byType(PressScale));
          expect(press.scale, AppPressScale.control);
          expect(press.pressedColor, AppTokens.light.pressed);
          double scale() => tester
              .widget<Transform>(
                find
                    .descendant(of: cell, matching: find.byType(Transform))
                    .first,
              )
              .transform
              .storage[0];
          Color? fill() => tester
              .widgetList<DecoratedBox>(
                find.descendant(of: cell, matching: find.byType(DecoratedBox)),
              )
              .map((box) => box.decoration)
              .whereType<ShapeDecoration>()
              .single
              .color;
          final gesture = await tester.startGesture(tester.getCenter(cell));
          await tester.pumpAndSettle();
          expect(scale(), closeTo(reduced ? 1 : AppPressScale.control, .001));
          expect(fill(), press.pressedColor);
          await gesture.moveBy(const Offset(100, 0));
          await tester.pumpAndSettle();
          expect(scale(), 1);
          expect(fill()!.a, 0);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(taps, 0);
          await tester.tap(cell);
          await tester.pumpAndSettle();
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
