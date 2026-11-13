import 'package:chh_app/design/icons.dart';
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
import 'package:chh_app/widgets/lac_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _labels = ['我的帖子', '我的收藏', '积分记录', '勋章'];

class _ThreadsFetcher extends ChhFetcher {
  final requests = <Uri>[];

  @override
  String get name => 'offline-me-entries';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests.add(url);
    return const ChhResponse(
      200,
      '<div id="ct"><form id="delform"><table>'
      '<tr><th><a href="thread-900001-1-1.html">本地测试主题</a></th></tr>'
      '</table></form></div>',
    );
  }
}

Widget _app({
  Widget page = const MePage(),
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
    body: page,
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
    testWidgets('lacquer entries stay above paper at 360x640, 1.3x, $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(brightness: brightness, textScale: 1.3));
      await tester.pumpAndSettle();
      final strip = find.byType(LacEntryStrip);
      final paper = find.byType(PaperSheet);
      final scaffold = tester.widget<LacScaffold>(find.byType(LacScaffold));
      expect(scaffold.pinned, isTrue);
      expect(scaffold.markFade, isTrue);
      expect(find.byType(EntryGrid), findsNothing);
      final rect = tester.getRect(strip);
      expect(rect.left, AppSpace.screen);
      expect(rect.right, 360 - AppSpace.screen);
      expect(
        rect.top - tester.getBottomLeft(find.byType(AccountIdentityRow)).dy,
        closeTo(22, .01),
      );
      expect(tester.getTopLeft(paper).dy - rect.bottom, closeTo(24, .01));
      for (final label in _labels) {
        expect(find.text(label), findsOneWidget);
        expect(
          find.descendant(of: strip, matching: find.text(label)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: paper, matching: find.text(label)),
          findsNothing,
        );
        expect(tester.getBottomLeft(find.text(label)).dy, lessThan(rect.bottom));
      }
      final rows = find.descendant(of: paper, matching: find.byType(GroupedRow));
      expect(
        tester.widgetList<GroupedRow>(rows).map((row) => row.title),
        ['黑名单', '设置'],
      );
      expect(fetcher.requests, isEmpty);
      await tester.drag(find.text('黑名单'), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.getRect(strip), rect);
      expect(tester.takeException(), isNull);
    });
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

  testWidgets('guest lacquer mast hides all four entries', (tester) async {
    chhSession.loggedIn = false;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.byType(LacEntryStrip), findsNothing);
    for (final label in _labels) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('登录 CHH'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(fetcher.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final style in AppearanceStyle.values) {
    testWidgets('fallback keeps its paper EntryGrid in $style', (tester) async {
      await tester.pumpWidget(_app(page: const MeFallbackPage(), style: style));
      await tester.pumpAndSettle();
      expect(find.byType(LacScaffold), findsNothing);
      expect(find.byType(LacEntryStrip), findsNothing);
      expect(find.byType(EntryGrid), findsOneWidget);
      expect(find.byType(EntryTile), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.3, 2.0]) {
      testWidgets(
        'misty hub fits 360x640, $brightness, ${scale}x and opens threads',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _app(
              style: AppearanceStyle.misty,
              brightness: brightness,
              textScale: scale,
            ),
          );
          await tester.pumpAndSettle();
          final hub = find.byType(MistyAccountHub);
          expect(hub, findsOneWidget);
          expect(find.byType(LacScaffold), findsNothing);
          expect(find.byType(EntryGrid), findsNothing);
          for (final label in ['测试账号', 'UID 100001', ..._labels]) {
            expect(
              find.descendant(of: hub, matching: find.text(label)),
              findsOneWidget,
            );
          }
          final entries = find.byType(MistyAccountEntry);
          expect(entries, findsNWidgets(4));
          final first = tester.getRect(entries.at(0));
          final third = tester.getRect(entries.at(2));
          expect(first.height, greaterThanOrEqualTo(44));
          if (scale >= 1.5) {
            expect(third.top, greaterThan(first.top));
          } else {
            expect(third.top, first.top);
          }
          expect(fetcher.requests, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('我的帖子'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('我的帖子'));
          await tester.pumpAndSettle();
          expect(find.byType(MyThreadsPage), findsOneWidget);
          expect(find.text('本地测试主题'), findsOneWidget);
          expect(fetcher.requests, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('misty guest keeps login identity without entry tray', (
    tester,
  ) async {
    chhSession.loggedIn = false;
    await tester.pumpWidget(_app(style: AppearanceStyle.misty));
    await tester.pumpAndSettle();
    expect(find.byType(MistyAccountHub), findsOneWidget);
    expect(find.byType(MistyAccountEntry), findsNothing);
    expect(find.text('登录 CHH'), findsOneWidget);
    expect(find.text('收藏内容，参与讨论'), findsOneWidget);
    for (final label in _labels) {
      expect(find.text(label), findsNothing);
    }
    expect(fetcher.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final style in AppearanceStyle.values) {
    testWidgets('$style tools have soft wells and no theme badge', (tester) async {
      await tester.pumpWidget(_app(style: style));
      await tester.pumpAndSettle();
      final settings = find.byKey(const ValueKey('me-settings'));
      expect(tester.widget<GroupedRow>(settings).value, isNull);
      expect(tester.widget<GroupedRow>(settings).subtitle, isNull);
      expect(find.text('薄暮'), findsNothing);
      expect(find.text('朱砂'), findsNothing);
      expect(find.byType(AccountToolWell), findsNWidgets(2));
      expect(find.text('CHHER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final reduced in [false, true]) {
    testWidgets('entry button semantics and shared feedback, reduced=$reduced', (
      tester,
    ) async {
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
        expect(press.scale, .94);
        expect(press.pressedColor, AppTokens.light.onLac.withValues(alpha: .08));
        double scale() => tester
            .widget<Transform>(
              find.descendant(of: cell, matching: find.byType(Transform)).first,
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
        expect(scale(), closeTo(reduced ? 1 : .94, .001));
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
    });
  }
}
