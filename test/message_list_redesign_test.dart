import 'dart:async';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/list_end_tokens.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/message_filters.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:chh_app/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'messages_ui_test.dart' show FakeMessages, notice;

class _ListRepository extends FakeMessages {
  List<Notice>? noticeRows;
  bool login = false;
  bool failPm = false;
  int noticeReads = 0;
  int pmReads = 0;
  Completer<Paged<Notice>>? loading;
  List<PmConversation> rows = List.generate(
    30,
    (i) => PmConversation(
      id: '$i',
      peer: '对方$i',
      preview: '内容$i',
      timeRaw: '2026-11-15 10:${(59 - i).toString().padLeft(2, '0')}',
      viewUrl:
          'https://www.chiphell.com/home.php?mod=space&do=pm&subop=view&plid=$i',
    ),
  );
  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) async {
    noticeReads++;
    if (login) throw const PageMessage(PageMessageKind.loginRequired, '请登录');
    if (loading != null) return loading!.future;
    return Paged(
      items: noticeRows ?? const [notice],
      page: const PageInfo(current: 1, hasNext: false),
    );
  }

  @override
  Future<Paged<PmConversation>> conversations({
    PmFilter filter = PmFilter.privatePm,
    int page = 1,
    bool refresh = false,
  }) async {
    pmReads++;
    if (failPm) throw StateError('offline');
    return Paged(
      items: filter == PmFilter.privatePm
          ? rows
          : const [
              PmConversation(
                id: 'public',
                peer: '公告',
                preview: '公共内容',
                timeRaw: '2026-11-15 18:00',
                viewUrl:
                    'https://www.chiphell.com/home.php?mod=space&do=pm&subop=viewg&pmid=9',
              ),
            ],
      page: PageInfo(current: 1, hasNext: false),
    );
  }
}

class _QueuedRepository extends _ListRepository {
  final nextPage = Completer<Paged<PmConversation>>();
  @override
  Future<Paged<PmConversation>> conversations({
    PmFilter filter = PmFilter.privatePm,
    int page = 1,
    bool refresh = false,
  }) async {
    if (page > 1) return nextPage.future;
    pmReads++;
    return Paged(items: rows, page: const PageInfo(current: 1, hasNext: true));
  }
}

Widget _app(
  Widget child, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: buildAppTheme(brightness, style),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('message footers clear the system inset inside the final card', (
    tester,
  ) async {
    const size = Size(390, 680);
    const safeBottom = 34.0;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: safeBottom);
    addTearDown(tester.view.reset);
    final repo = _ListRepository()
      ..noticeRows = [
        for (var i = 0; i < 20; i++)
          Notice(
            id: 'notice-$i',
            category: 'post',
            title: '测试主题 $i',
            occurredAtText: '2026-11-15 10:00',
            summary: '回复了您的帖子',
            replyText: i == 19 ? '末条提醒正文' : null,
          ),
      ];
    await tester.pumpWidget(_app(MessagesPage(repository: repo)));
    await tester.pumpAndSettle();

    Future<void> checkTail() async {
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(100000);
      await tester.pumpAndSettle();
      final marker = find.text('已显示全部消息');
      final footer = find.byType(ListFooter);
      expect(marker, findsOneWidget);
      expect(
        find.ancestor(of: footer, matching: find.byType(DecoratedSliver)),
        findsOneWidget,
      );
      final cardBottom =
          tester.getBottomLeft(footer).dy + MessageListTokens.cardPadding;
      expect(
        cardBottom - tester.getBottomLeft(marker).dy,
        ListEndTokens.markerGap,
      );
      expect(
        size.height - safeBottom - cardBottom,
        ListEndTokens.navigationGap,
      );
    }

    await checkTail();
    expect(
      tester.getTopLeft(find.text('已显示全部消息')).dy -
          tester.getBottomLeft(find.text('末条提醒正文')).dy,
      ListEndTokens.markerGap,
    );
    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pumpAndSettle();
    await checkTail();
  });

  testWidgets('replies to the same thread stay separate with plain titles', (
    tester,
  ) async {
    final repo = _ListRepository()
      ..noticeRows = [
        for (var index = 0; index < 3; index++)
          Notice(
            id: 'notice-$index',
            category: 'post',
            actor: '坛友$index',
            occurredAtText: '2026-11-15 10:00',
            summary: '回复了您的帖子',
            action: '回复了您的帖子',
            title: index == 2 ? '《同一个帖子》' : '同一个帖子',
            replyText: index == 0 ? '独立的回复正文' : null,
            tid: 123,
            pid: 456 + index,
            unread: index == 0,
          ),
      ];
    await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.byType(NoticeRow), findsNWidgets(3));
    final titles = find.text('《同一个帖子》');
    expect(titles, findsNWidgets(3));
    expect(find.byIcon(AppIcons.reply), findsNothing);
    expect(find.byIcon(AppIcons.comments), findsNWidgets(3));
    final quote = find.byKey(const ValueKey('notice-quote'));
    expect(quote, findsOneWidget);
    expect(find.descendant(of: quote, matching: titles), findsNothing);
    expect(
      find.descendant(of: quote, matching: find.text('独立的回复正文')),
      findsOneWidget,
    );
    final tokens = AppTokens.of(tester.element(titles.first));
    for (final title in tester.widgetList<Text>(titles)) {
      expect(title.maxLines, 1);
      expect(title.style?.color, tokens.text2);
    }
    final sentences = tester.widgetList<Text>(
      find.byKey(const ValueKey('notice-sentence')),
    );
    for (final sentence in sentences) {
      final name = (sentence.textSpan! as TextSpan).children!.first as TextSpan;
      expect(name.style?.color, tokens.text);
      expect(name.style?.fontWeight, FontWeight.w600);
      expect(sentence.style?.color, tokens.text2);
    }
  });

  testWidgets('failed refresh can retry even without a next page', (
    tester,
  ) async {
    final previous = chhSession.badges;
    addTearDown(() => chhSession.badges = previous);
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
    final repo = _ListRepository();
    repo.rows = repo.rows.take(1).toList();
    await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pumpAndSettle();
    repo.failPm = true;
    chhSession.observeHtml(
      '<div id="um"><strong class="vwmy"><a href="space-uid-1001.html">fixture</a></strong><a id="myprompt">提醒(0)</a><a id="pm_ntc">私信(1)</a></div>',
    );
    await tester.pumpAndSettle();
    final reads = repo.pmReads;
    repo.failPm = false;
    await tester.tap(find.text('未能刷新，轻点重试'));
    await tester.pumpAndSettle();
    expect(repo.pmReads, reads + 1);
    expect(find.text('对方0'), findsOneWidget);
  });
  testWidgets('explicit public filter replaces private rows immediately', (
    tester,
  ) async {
    final repo = _ListRepository();
    await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('私人消息'));
    await tester.pumpAndSettle();
    // A scroll position can change while the anchored selector is open.
    final list = find.byType(CustomScrollView, skipOffstage: false).last;
    tester.widget<CustomScrollView>(list).controller!.jumpTo(300);
    await tester.tap(find.text('公共消息'));
    await tester.pumpAndSettle();
    expect(find.text('公告'), findsOneWidget);
    expect(find.text('对方0'), findsNothing);
    expect(
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .offset,
      0,
    );
  });
  testWidgets('read notice stays read after its row is recycled', (
    tester,
  ) async {
    final repo = _ListRepository()
      ..noticeRows = List.generate(
        40,
        (i) => Notice(
          id: 'n$i',
          category: 'post',
          actor: '坛友$i',
          occurredAtText: '2026-11-15 10:00',
          summary: '新提醒$i',
          action: '回复了你的帖子',
          title: '主题$i',
          unread: true,
        ),
      );
    await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
    await tester.pumpAndSettle();
    final row = find.byType(NoticeRow).first;
    expect(tester.widget<NoticeRow>(row).unread, isTrue);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    scroll.jumpTo(2200);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NoticeRow>(find.byType(NoticeRow).first).unread,
      isFalse,
    );
  });
  testWidgets(
    'loading keeps three skeleton rows aligned with arriving content',
    (tester) async {
      final repo = _ListRepository()..loading = Completer<Paged<Notice>>();
      await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('message-skeleton-avatar-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('message-skeleton-avatar-3')),
        findsNothing,
      );
      final before = tester.getTopLeft(
        find.byKey(const ValueKey('message-skeleton-avatar-0')),
      );
      repo.loading!.complete(
        const Paged(
          items: [notice],
          page: PageInfo(current: 1, hasNext: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(AvatarImage).first), before);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets(
    'standalone messages route uses shared lacquer and compact selector',
    (tester) async {
      await tester.pumpWidget(
        _app(MessagesPage(repository: _ListRepository())),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LacquerTabScaffold), findsOneWidget);
      expect(find.byTooltip('返回'), findsOneWidget);
      await tester.tap(find.text('私信').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('私人消息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('message sections crossfade below a single retained mast', (
    tester,
  ) async {
    final repo = _ListRepository();
    await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
    await tester.pumpAndSettle();

    final mast = find.byKey(const ValueKey('tab-shared-header'));
    final selector = find.byWidgetPredicate(
      (widget) => widget is AppSegmented<int> && !widget.compact,
    );
    final mastElement = tester.element(mast);
    final selectorElement = tester.element(selector);
    final mastRect = tester.getRect(mast);
    final selectorRect = tester.getRect(selector);
    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pump();
    await tester.pump(AppMotion.fade ~/ 2);

    for (var section = 0; section < 2; section++) {
      final viewport = find.descendant(
        of: find.byKey(ValueKey('message-page-$section')),
        matching: find.byType(CustomScrollView),
      );
      final opacity = tester
          .widget<Opacity>(
            find.ancestor(of: viewport, matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(opacity, inExclusiveRange(0, 1));
      expect(tester.getTopLeft(viewport).dx, 0);
    }
    expect(tester.element(mast), same(mastElement));
    expect(tester.element(selector), same(selectorElement));
    expect(tester.getRect(mast), mastRect);
    expect(tester.getRect(selector), selectorRect);

    await tester.pump(AppMotion.fade ~/ 2);
    expect(
      find.byKey(const ValueKey('message-page-0')).hitTestable(),
      findsNothing,
    );
    expect(find.text('私人消息').hitTestable(), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('swipes keep the collapsed mast and both section offsets', (
    tester,
  ) async {
    final repo = _ListRepository()
      ..noticeRows = List.generate(
        40,
        (i) => Notice(
          id: 'shared-$i',
          category: 'post',
          actor: '坛友$i',
          occurredAtText: '2026-11-15 10:00',
          summary: '提醒$i',
          action: '回复了你的帖子',
        ),
      );
    await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
    await tester.pumpAndSettle();

    ScrollController activeScroll() => tester
        .widget<CustomScrollView>(find.byType(CustomScrollView).hitTestable())
        .controller!;
    final notices = activeScroll();
    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pumpAndSettle();
    final messages = activeScroll();
    expect(messages.offset, 0);
    await tester.tap(find.text('提醒').hitTestable().first);
    await tester.pumpAndSettle();

    notices.jumpTo(350);
    await tester.pumpAndSettle();
    final mast = find.byKey(const ValueKey('tab-shared-header'));
    final compact = find.byWidgetPredicate(
      (widget) => widget is AppSegmented<int> && widget.compact,
    );
    final compactElement = tester.element(compact);
    final compactRect = tester.getRect(compact);
    final mastRect = tester.getRect(mast);
    final viewport = find.byType(CustomScrollView).hitTestable();
    final area = tester.getRect(viewport);
    final cancelled = await tester.startGesture(area.center);
    await cancelled.moveBy(Offset(-area.width / 6, 0));
    await tester.pump();
    expect(tester.getTopLeft(viewport.first).dx, lessThan(0));
    expect(messages.offset, greaterThan(0));
    expect(messages.offset, lessThan(notices.offset));
    final collapseExtent = messages.offset;
    expect(tester.getRect(mast), mastRect);
    expect(tester.getRect(compact), compactRect);
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(messages.offset, 0);
    expect(notices.offset, 350);

    await tester.drag(viewport, Offset(-area.width / 2, 0));
    await tester.pumpAndSettle();
    expect(activeScroll(), same(messages));
    expect(messages.offset, collapseExtent);
    expect(tester.getRect(mast), mastRect);
    expect(tester.getRect(compact), compactRect);
    expect(tester.element(compact), same(compactElement));

    messages.jumpTo(500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('提醒').hitTestable().first);
    await tester.pumpAndSettle();
    expect(activeScroll(), same(notices));
    expect(notices.offset, 350);
    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pumpAndSettle();
    expect(activeScroll(), same(messages));
    expect(messages.offset, 500);

    messages.jumpTo(0);
    await tester.pumpAndSettle();
    final expanded = tester.getRect(mast);
    await tester.tap(find.text('提醒').hitTestable().first);
    await tester.pumpAndSettle();
    expect(activeScroll(), same(notices));
    expect(notices.offset, 350);
    expect(tester.getRect(mast), expanded);
    notices.jumpTo(500);
    await tester.pumpAndSettle();
    expect(tester.getRect(mast), isNot(expanded));
    expect(repo.noticeReads, 1);
    expect(repo.pmReads, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a badge arriving during pagination queues one refresh', (
    tester,
  ) async {
    final previous = chhSession.badges;
    addTearDown(() => chhSession.badges = previous);
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
    final repo = _QueuedRepository();
    await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pumpAndSettle();
    final controller = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    repo.rows = [
      const PmConversation(
        id: 'queued',
        peer: '排队来信',
        preview: '内容',
        timeRaw: '2026-11-15 18:00',
        viewUrl:
            'https://www.chiphell.com/home.php?mod=space&do=pm&subop=view&plid=99',
      ),
      ...repo.rows,
    ];
    chhSession.observeHtml(
      '<div id="um"><strong class="vwmy"><a href="space-uid-1001.html">fixture</a></strong><a id="myprompt">提醒(0)</a><a id="pm_ntc">私信(1)</a></div>',
    );
    await tester.pump();
    expect(repo.pmReads, 1);
    repo.nextPage.complete(
      const Paged(items: [], page: PageInfo(current: 2, hasNext: false)),
    );
    await tester.pumpAndSettle();
    expect(repo.pmReads, 2);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('排队来信'), findsOneWidget);
  });
  testWidgets('logged out list hides filter and offers login', (tester) async {
    await tester.pumpWidget(
      _app(MessagesTabPage(repository: _ListRepository()..login = true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NoticeFilter), findsNothing);
    expect(find.text('登录后查看消息'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
  testWidgets('all four appearances share lacquer chrome and borderless rows', (
    tester,
  ) async {
    for (final style in AppearanceStyle.values) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _app(
            MessagesTabPage(
              key: ValueKey((style, brightness)),
              repository: _ListRepository(),
            ),
            style: style,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LacquerTabScaffold), findsOneWidget);
        expect(find.byType(NoticeRow), findsOneWidget);
        expect(find.byType(Divider), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets('new PM waits until stationary top without moving reading position', (
    tester,
  ) async {
    final previous = chhSession.badges;
    addTearDown(() => chhSession.badges = previous);
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
    final repo = _ListRepository();
    await tester.pumpWidget(_app(MessagesTabPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pumpAndSettle();
    final scrolling = find.byType(CustomScrollView).hitTestable();
    await tester.drag(scrolling, const Offset(0, -500));
    await tester.pumpAndSettle();
    final controller = tester.widget<CustomScrollView>(scrolling).controller!;
    final before = controller.offset;
    repo.rows = [
      const PmConversation(
        id: 'fresh',
        peer: '新来信',
        preview: '新内容',
        timeRaw: '2026-11-15 18:00',
        viewUrl:
            'https://www.chiphell.com/home.php?mod=space&do=pm&subop=view&plid=99',
      ),
      ...repo.rows,
    ];
    chhSession.observeHtml(
      '<div id="um"><strong class="vwmy"><a href="space-uid-1001.html">fixture</a></strong><a id="myprompt">提醒(0)</a><a id="pm_ntc">私信(1)</a></div>',
    );
    await tester.pumpAndSettle();
    expect(controller.offset, before);
    expect(find.text('新来信'), findsNothing);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('新来信'), findsOneWidget);
    expect(controller.offset, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
