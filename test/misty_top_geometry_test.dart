import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/message_filters.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/account_widgets.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:chh_app/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messages_ui_test.dart' show FakeMessages;
import 'support/space_fixtures.dart';

const _statusHeight = 24.0;
final _large = find.byKey(const ValueKey('tab-large-title'));
final _tabHeader = find.byType(TabHeader);
final _identity = find.byKey(const ValueKey('me-identity-row'));
final _tools = find.byKey(const ValueKey('me-tools'));
final _largeSegment = find.byWidgetPredicate(
  (widget) => widget is AppSegmented<int> && !widget.compact,
);
final _smallSegment = find.byWidgetPredicate(
  (widget) => widget is AppSegmented<int> && widget.compact,
);

class _NoNetwork extends ChhFetcher {
  final requests = <Uri>[];
  @override
  String get name => 'misty-geometry-offline';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests.add(url);
    throw StateError('Unexpected request in geometry test: $url');
  }
}

class _GuestMessages extends FakeMessages {
  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) async => throw const PageMessage(PageMessageKind.loginRequired, '请登录');
}

Widget _app(
  Widget child, {
  required Brightness brightness,
  required double scale,
  AppearanceStyle style = AppearanceStyle.misty,
}) => MaterialApp(
  theme: buildAppTheme(brightness, style),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.only(top: _statusHeight),
      textScaler: TextScaler.linear(scale),
    ),
    child: child!,
  ),
  home: Scaffold(body: child, bottomNavigationBar: const SizedBox(height: 84)),
);

Widget _forums() => ForumIndexView(
  loadForums: (_) async => const [
    ForumCategory(
      name: '硬件',
      forums: [
        Forum(fid: 1, name: '电脑讨论', threadCount: 12),
        Forum(fid: 2, name: '摄影讨论', threadCount: 34),
      ],
    ),
  ],
);

Finder _headerText(String text) =>
    find.descendant(of: _large, matching: find.text(text));

Finder _firstDate() => find
    .descendant(
      of: find.byKey(const ValueKey('message-filter-row')),
      matching: find.byType(Text),
    )
    .first;

Future<void> _surface(WidgetTester tester, double scale) async {
  await tester.binding.setSurfaceSize(Size(scale == 1 ? 390 : 320, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _expectCollapse(
  WidgetTester tester, {
  required Finder regionEnd,
  required Finder compact,
}) async {
  final scroll = tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!;
  expect(scroll.offset, 0, reason: 'First entry must start at the top');
  final collapse =
      tester.getBottomLeft(regionEnd).dy -
      (_statusHeight + NavOverlay.barHeight);
  expect(collapse, greaterThan(0));
  final smallOpacity = find
      .ancestor(of: compact, matching: find.byType(Opacity))
      .first;
  expect(tester.widget<Opacity>(smallOpacity).opacity, 0);
  scroll.jumpTo(collapse * .9);
  await tester.pumpAndSettle();
  expect(tester.widget<Opacity>(smallOpacity).opacity, closeTo(.75, .01));
  expect(tester.widget<Opacity>(_large).opacity, 0);
  scroll.jumpTo(collapse);
  await tester.pumpAndSettle();
  expect(
    tester.getBottomLeft(regionEnd).dy,
    closeTo(_statusHeight + NavOverlay.barHeight, .01),
  );
  expect(tester.widget<Opacity>(smallOpacity).opacity, 1);
  scroll.jumpTo(0);
  await tester.pumpAndSettle();
  expect(tester.widget<Opacity>(_large).opacity, 1);
  expect(tester.widget<Opacity>(smallOpacity).opacity, 0);
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('lacquer watermark stops at the paper seam and action column', (
    tester,
  ) async {
    await _surface(tester, 1);
    await tester.pumpWidget(
      _app(
        LacquerTabScaffold(
          title: '精选',
          actions: [
            ChromeButton(tooltip: '搜索', icon: Icons.search, onPressed: () {}),
          ],
          slivers: const [SliverToBoxAdapter(child: SizedBox(height: 500))],
        ),
        brightness: Brightness.light,
        style: AppearanceStyle.cinnabar,
        scale: 1,
      ),
    );
    await tester.pumpAndSettle();
    final mark = find.text('chh');
    final clip = find.ancestor(of: mark, matching: find.byType(ClipRect)).first;
    final visible = tester.getRect(clip);
    expect(visible.right, tester.getTopLeft(find.byTooltip('搜索')).dx);
    expect(
      visible.bottom,
      closeTo(
        tester.getBottomLeft(_large).dy +
            TabChromeTokens.editorialBottom +
            TabChromeTokens.seamOverlap,
        .1,
      ),
    );
    expect(tester.getBottomLeft(mark).dy, greaterThan(visible.bottom));
    expect(visible.height, closeTo(TabChromeTokens.watermarkVisibleHeight, 1));
  });

  late _NoNetwork network;
  setUp(() {
    final loggedIn = chhSession.loggedIn;
    final badges = chhSession.badges;
    final fetchers = List<ChhFetcher>.of(chhClient.fetchers);
    final uid = favoriteIndex.uid;
    final favorites = favoriteIndex.items;
    network = _NoNetwork();
    chhClient.fetchers
      ..clear()
      ..add(network);
    chhClient.clearCache();
    chhSession.loggedIn = true;
    chhSession.badges = const HeaderBadges(
      notices: 0,
      messages: 0,
      userName: '测试账号',
      uid: '100001',
    );
    favoriteIndex.setUid(100001);
    favoriteIndex.replace(const [
      FavoriteItem(
        type: FavoriteType.forum,
        targetId: 1,
        favid: '1',
        title: '电脑讨论',
        url: '',
      ),
    ]);
    addTearDown(() {
      expect(network.requests, isEmpty);
      chhSession.loggedIn = loggedIn;
      chhSession.badges = badges;
      chhClient.fetchers
        ..clear()
        ..addAll(fetchers);
      chhClient.clearCache();
      favoriteIndex.setUid(uid);
      favoriteIndex.replace(favorites);
    });
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('misty guest messages keeps card gap $brightness ${scale}x', (
        tester,
      ) async {
        chhSession.loggedIn = false;
        chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
        await _surface(tester, scale);
        final repo = _GuestMessages();
        await tester.pumpWidget(
          _app(
            MessagesTabPage(repository: repo),
            brightness: brightness,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final cardTop =
            tester.getTopLeft(find.byType(StateView)).dy -
            MessageListTokens.cardPadding;
        expect(
          cardTop - tester.getBottomLeft(_largeSegment).dy,
          closeTo(20, .01),
        );
        expect(find.byType(NoticeFilter), findsNothing);
        expect(find.byKey(const ValueKey('message-filter-row')), findsNothing);
        expect(find.text('登录后查看消息'), findsOneWidget);
        expect(find.text('登录').hitTestable(), findsOneWidget);
        expect(repo.sends, 0);
        expect(tester.takeException(), isNull);
      });
      testWidgets(
        'misty messages geometry and collapse $brightness ${scale}x',
        (tester) async {
          await _surface(tester, scale);
          final repo = FakeMessages();
          await tester.pumpWidget(
            _app(
              MessagesTabPage(repository: repo),
              brightness: brightness,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          final header = tester.getRect(_tabHeader);
          final segment = tester.getRect(_largeSegment);
          expect(header.top, _statusHeight);
          expect(tester.widget<Text>(_headerText('消息')).style!.fontSize, 32);
          expect(
            segment.top - header.bottom,
            closeTo(TabChromeTokens.mistySegmentGap, .01),
          );
          expect(segment.height, scale == 1 ? 44 : greaterThanOrEqualTo(44));
          expect(
            tester.getTopLeft(_firstDate()).dy - segment.bottom,
            closeTo(20, 1),
          );
          expect(find.text('chh'), findsNothing);
          await _expectCollapse(
            tester,
            regionEnd: _largeSegment,
            compact: _smallSegment,
          );
          expect(repo.sends, 0);
        },
      );

      testWidgets('misty forums geometry and collapse $brightness ${scale}x', (
        tester,
      ) async {
        await _surface(tester, scale);
        await tester.pumpWidget(
          _app(_forums(), brightness: brightness, scale: scale),
        );
        await tester.pumpAndSettle();
        final header = tester.getRect(_tabHeader);
        final section = find.byKey(const ValueKey('forum-section-0'));
        expect(_headerText('2 个版块'), findsOneWidget);
        expect(header.top, _statusHeight);
        expect(tester.widget<Text>(_headerText('版块')).style!.fontSize, 32);
        expect(tester.widget<Text>(section).data, '收藏');
        expect(tester.getTopLeft(section).dy - header.bottom, closeTo(20, .01));
        expect(find.text('chh'), findsNothing);
        await _expectCollapse(
          tester,
          regionEnd: _tabHeader,
          compact: find.byKey(const ValueKey('forum-directory-jump')),
        );
      });

      for (final logged in [true, false]) {
        testWidgets(
          'misty me logged=$logged geometry and collapse $brightness ${scale}x',
          (tester) async {
            chhSession.loggedIn = logged;
            if (!logged) {
              chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
            }
            await _surface(tester, scale);
            await tester.pumpWidget(
              _app(
                MePage(repository: FixtureSpace()),
                brightness: brightness,
                scale: scale,
              ),
            );
            await tester.pumpAndSettle();
            final header = tester.getRect(_tabHeader);
            final identity = tester.getRect(_identity);
            final card = find.byKey(const ValueKey('me-identity-card'));
            final cardRect = tester.getRect(card);
            final avatar = find.byKey(const ValueKey('me-identity-avatar'));
            expect(header.top, _statusHeight);
            expect(tester.widget<Text>(_headerText('我的')).style!.fontSize, 32);
            expect(cardRect.top - header.bottom, closeTo(16, .01));
            expect(identity.top - cardRect.top, closeTo(16, .01));
            expect(tester.getSize(avatar), const Size(56, 56));
            if (!logged) {
              final logo = find.descendant(
                of: avatar,
                matching: find.byKey(const ValueKey('avatar-logo')),
              );
              expect(
                (tester.widget<Image>(logo).image as ResizeImage).imageProvider,
                const AssetImage('assets/brand/chhers-logo.png'),
              );
            }
            expect(
              tester
                  .widget<Text>(
                    find.descendant(
                      of: card,
                      matching: find.text(logged ? '测试账号' : '未登录'),
                    ),
                  )
                  .style!
                  .fontSize,
              21,
            );
            if (logged) {
              final entries = tester.getRect(find.byType(LacEntryStrip));
              expect(entries.top - cardRect.bottom, closeTo(12, .01));
              await tester.scrollUntilVisible(_tools, 32);
              await tester.pumpAndSettle();
              expect(
                tester.getTopLeft(_tools).dy -
                    tester.getBottomLeft(find.byType(LacEntryStrip)).dy,
                closeTo(12, .01),
              );
              tester
                  .state<ScrollableState>(find.byType(Scrollable))
                  .position
                  .jumpTo(0);
              await tester.pumpAndSettle();
              expect(find.text('UID 100001'), findsOneWidget);
              expect(find.text('主页'), findsOneWidget);
            } else {
              expect(
                tester.getTopLeft(_tools).dy - cardRect.bottom,
                closeTo(12, .01),
              );
              expect(find.byType(LacEntryStrip), findsNothing);
              expect(find.text('登录'), findsOneWidget);
              expect(find.textContaining('UID '), findsNothing);
            }
            expect(find.text('chh'), findsNothing);
            await _expectCollapse(
              tester,
              regionEnd: card,
              compact: find.byType(SlidingCompactTitle),
            );
          },
        );
      }

      testWidgets(
        'cinnabar keeps original three tab seams $brightness ${scale}x',
        (tester) async {
          await _surface(tester, scale);
          Widget app(Widget child) => _app(
            child,
            brightness: brightness,
            scale: scale,
            style: AppearanceStyle.cinnabar,
          );
          await tester.pumpWidget(
            app(MessagesTabPage(repository: FakeMessages())),
          );
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(_tabHeader).dy, _statusHeight);
          final date = tester.getRect(_firstDate());
          expect(
            date.top - tester.getBottomLeft(_large).dy,
            closeTo(32 + 34 + 6 + 16 + (44 - date.height) / 2, .01),
          );
          expect(find.text('chh'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(app(_forums()));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(_tabHeader).dy, _statusHeight);
          expect(
            tester
                    .getTopLeft(find.byKey(const ValueKey('forum-section-0')))
                    .dy -
                tester.getBottomLeft(_large).dy,
            closeTo(12 + 34 + 6 + 26, .01),
          );
          expect(find.text('chh'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(app(MePage(repository: FixtureSpace())));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(_tabHeader).dy, _statusHeight);
          final entries = tester.getRect(find.byType(LacEntryStrip));
          expect(
            entries.top - tester.getBottomLeft(_identity).dy,
            closeTo(34 + 32, .01),
          );
          final markClip = find
              .ancestor(of: find.text('chh'), matching: find.byType(ClipRect))
              .first;
          expect(
            tester.getBottomLeft(markClip).dy - entries.top,
            MeTokens.overlap,
          );
          expect(
            tester.getTopLeft(_tools).dy - entries.bottom,
            closeTo(12, .01),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
