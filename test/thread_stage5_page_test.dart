import 'package:chh_app/widgets/expressive_controls.dart';
import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/widgets/comment_mode_bar.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post(int floor, {int lines = 1, String? uid}) => Post(
  pid: floor,
  floor: floor,
  author: '作者$floor',
  authorUid: uid ?? '$floor',
  timeRaw: '2026-11-15 10:00',
  content: [TextBlock(List.filled(lines, '正文$floor').join('\n'))],
);

ThreadDetail _page(
  List<Post> posts, {
  int number = 1,
  int? views,
  int? replies,
}) => ThreadDetail(
  tid: 123,
  fid: 290,
  forumName: '电脑讨论',
  title: '阶段五阅读样例',
  viewCount: views,
  replyCount: replies,
  posts: posts,
  page: PageInfo(current: number, hasNext: false),
);

Future<void> _mount(
  WidgetTester tester,
  ThreadDetailPage page, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness, style),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Finder _card(int pid) => find.byWidgetPredicate(
  (widget) => widget is PostCard && widget.post.pid == pid,
);

double _barPosition(WidgetTester tester) => tester
    .widget<FractionalTranslation>(
      find.byKey(const ValueKey('thread-reading-bar-position')),
    )
    .translation
    .dy;

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('thread header uses source counts in $style $brightness', (
        tester,
      ) async {
        await _mount(
          tester,
          ThreadDetailPage(
            tid: 123,
            title: '',
            loadPage: (_, _, _) async => _page(
              [_post(1, lines: 24), _post(2)],
              views: 8047,
              replies: 47,
            ),
          ),
          style: style,
          brightness: brightness,
        );
        expect(find.text('8047 查看　47 回复'), findsOneWidget);
        final bar = tester.widget<ReadingBar>(find.byType(ReadingBar));
        expect(bar.count, 47, reason: 'The loaded page has only one reply.');
        final heading = tester
            .widgetList<Text>(find.text('阶段五阅读样例'))
            .firstWhere((text) => text.style?.fontSize == 24);
        expect(heading.style!.height, 1.38);
        expect(heading.style!.color, tokensFor(brightness, style).text);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          tokensFor(brightness, style).bg,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'unavailable source counts are not inferred from loaded replies',
    (tester) async {
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '',
          loadPage: (_, _, _) async =>
              _page([_post(1, lines: 24), _post(2), _post(3)]),
        ),
      );
      expect(find.textContaining(' 查看'), findsNothing);
      expect(tester.widget<ReadingBar>(find.byType(ReadingBar)).count, isNull);
    },
  );

  testWidgets('reading bar follows drag, settles, returns upward and at end', (
    tester,
  ) async {
    await _mount(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '',
        loadPage: (_, _, _) async => _page([
          _post(1, lines: 80),
          for (var n = 2; n <= 12; n++) _post(n, lines: 3),
        ]),
      ),
    );
    expect(_barPosition(tester), 0);
    final drag = await tester.startGesture(const Offset(190, 600));
    await drag.moveBy(const Offset(0, -20));
    await tester.pump();
    await drag.moveBy(const Offset(0, -35));
    await tester.pump();
    final partial = _barPosition(tester);
    expect(partial, greaterThan(0));
    expect(partial, lessThan(1));
    await drag.moveBy(const Offset(0, -20));
    await tester.pump();
    expect(_barPosition(tester), greaterThan(partial));
    await drag.up();
    await tester.pumpAndSettle();
    expect(_barPosition(tester), anyOf(0.0, 1.0));
    expect(tester.binding.transientCallbackCount, 0);

    final down = await tester.startGesture(const Offset(190, 600));
    await down.moveBy(const Offset(0, -20));
    await tester.pump();
    await down.moveBy(const Offset(0, -160));
    await tester.pump();
    expect(_barPosition(tester), 1);
    await down.moveBy(const Offset(0, 24));
    await tester.pump();
    final returning = _barPosition(tester);
    expect(returning, greaterThan(0));
    expect(returning, lessThan(1));
    await down.up();
    await tester.pumpAndSettle();
    expect(_barPosition(tester), 1);

    for (var n = 0; n < 12; n++) {
      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      if (position.extentAfter < 1) break;
    }
    final position = _position(tester);
    expect(position.extentAfter, lessThan(1));
    final end = position.maxScrollExtent;
    position.jumpTo(end - 250);
    await tester.pumpAndSettle();
    position.jumpTo(end - 100);
    await tester.pumpAndSettle();
    expect(_barPosition(tester), 1);
    position.jumpTo(end);
    expect(_barPosition(tester), 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_barPosition(tester), greaterThan(0));
    expect(_barPosition(tester), lessThan(1));
    await tester.pumpAndSettle();
    expect(_barPosition(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion reading bar fades without moving', (
    tester,
  ) async {
    await _mount(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '',
        loadPage: (_, _, _) async => _page([_post(1, lines: 80), _post(2)]),
      ),
      reduced: true,
    );
    final anchor = tester.widget<ReadingBarAnchor>(
      find.byType(ReadingBarAnchor),
    );
    final position = _position(tester);
    position.jumpTo(400);
    await tester.pumpAndSettle();
    expect(anchor.hiddenProgress.value, 1);
    position.jumpTo(350);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(anchor.hiddenProgress.value, inExclusiveRange(0, 1));
    expect(_barPosition(tester), 0);
    await tester.pumpAndSettle();
    expect(anchor.hiddenProgress.value, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'compact title follows heading edge and progress follows scroll',
    (tester) async {
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '',
          loadPage: (_, _, _) async => _page([_post(1, lines: 80), _post(2)]),
        ),
      );
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == '阶段五阅读样例' &&
            widget.style?.fontSize == 24,
      );
      final threshold = tester.getBottomLeft(title).dy - NavOverlay.barHeight;
      final position = _position(tester);
      double opacity() =>
          tester.widget<Opacity>(find.byKey(NavOverlay.inlineTitleKey)).opacity;
      expect(opacity(), 0);
      position.jumpTo(threshold + 2);
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(
        find.byKey(const ValueKey('thread-reading-progress')),
        findsNothing,
      );
      position.jumpTo(
        position.minScrollExtent + position.viewportDimension + 20,
      );
      await tester.pumpAndSettle();
      final progress = tester.widget<Transform>(
        find.byKey(const ValueKey('thread-reading-progress')),
      );
      expect(progress.transform.entry(0, 0), greaterThan(0));
      expect(progress.transform.entry(0, 0), lessThan(.5));
      position.jumpTo(threshold - 2);
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'author mode dims old replies to 45 percent until response arrives',
    (tester) async {
      final author = Completer<ThreadDetail>();
      final requests = <String?>[];
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '',
          loadPage: (_, uid, _) {
            requests.add(uid);
            return uid == null
                ? Future.value(_page([_post(1), _post(2), _post(3), _post(4)]))
                : author.future;
          },
        ),
      );
      final mode = find.descendant(
        of: find.byType(CommentModeBar),
        matching: find.byKey(const ValueKey('comment-mode-2')),
      );
      await tester.ensureVisible(mode);
      await tester.pumpAndSettle();
      await tester.tap(mode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests, [null, '1']);
      expect(_card(2), findsOneWidget);
      for (final fade in tester.widgetList<ContentFade>(
        find.ancestor(of: _card(2), matching: find.byType(ContentFade)),
      )) {
        expect(
          fade.opacity.value,
          closeTo(.45, .001),
          reason: 'Pending reads retain old replies at the approved opacity.',
        );
      }
      author.complete(_page([_post(1), _post(12, uid: '1')]));
      await tester.pumpAndSettle();
      expect(_card(2), findsNothing);
      expect(_card(12), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'prepending variable-height replies keeps the visible reply anchored',
    (tester) async {
      final previous = Completer<ThreadDetail>();
      final requests = <int>[];
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '',
          initialPage: 3,
          initialThreaded: false,
          loadPage: (page, _, _) {
            requests.add(page);
            return page == 3
                ? Future.value(
                    _page([
                      for (var n = 21; n <= 27; n++) _post(n, lines: 3),
                    ], number: 3),
                  )
                : previous.future;
          },
        ),
      );
      final before = find.text('查看前面的回复');
      expect(before, findsOneWidget);
      await tester.ensureVisible(before);
      await tester.pumpAndSettle();
      final anchor = tester.getTopLeft(_card(21));
      await tester.tap(before);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getTopLeft(_card(21)), anchor);
      previous.complete(
        _page([
          for (var n = 11; n <= 20; n++) _post(n, lines: n.isEven ? 12 : 1),
        ], number: 2),
      );
      await tester.pump();
      expect(_card(21), findsOneWidget);
      expect(
        tester.getTopLeft(_card(21)).dy,
        closeTo(anchor.dy, 1),
        reason: 'The first inserted frame must preserve the visible reply.',
      );
      await tester.pumpAndSettle();
      expect(requests, [3, 2]);
      expect(_card(21), findsOneWidget);
      expect(tester.getTopLeft(_card(21)).dy, closeTo(anchor.dy, 1));
      tester.widget<ReadingBar>(find.byType(ReadingBar)).onBackToTop();
      await tester.pumpAndSettle();
      expect(_position(tester).extentBefore, lessThan(1));
      expect(find.text('查看前面的回复').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a thousand-block previous page is lazy and anchored on its first frame',
    (tester) async {
      final previous = Completer<ThreadDetail>();
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '',
          initialPage: 3,
          initialThreaded: false,
          loadPage: (page, _, _) => page == 3
              ? Future.value(
                  _page([
                    for (var n = 21; n <= 27; n++) _post(n, lines: 3),
                  ], number: 3),
                )
              : previous.future,
        ),
      );
      final before = find.text('查看前面的回复');
      await tester.ensureVisible(before);
      await tester.pumpAndSettle();
      final anchor = tester.getTopLeft(_card(21));
      await tester.tap(before);
      await tester.pump();
      previous.complete(
        _page([
          const Post(
            pid: 11,
            floor: 11,
            author: '前页作者',
            timeRaw: '',
            content: [],
          ),
          Post(
            pid: 12,
            floor: 12,
            author: '长回复作者',
            timeRaw: '',
            content: [for (var n = 0; n < 1000; n++) TextBlock('前页长段落$n')],
          ),
          for (var n = 13; n <= 20; n++) _post(n),
        ], number: 2),
      );
      await tester.pump();
      expect(_card(21), findsOneWidget);
      expect(tester.getTopLeft(_card(21)).dy, closeTo(anchor.dy, 1));
      expect(find.text('前页长段落0'), findsNothing);
      expect(find.byType(PostCard).evaluate().length, lessThan(30));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_card(21)).dy, closeTo(anchor.dy, 1));
      tester.widget<ReadingBar>(find.byType(ReadingBar)).onBackToTop();
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
      expect(find.text('查看前面的回复').hitTestable(), findsOneWidget);
      expect(find.text('前页长段落999'), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets(
    'jump to comments skips a thousand-block opening without building it',
    (tester) async {
      await _mount(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '',
          loadPage: (_, _, _) async => _page([
            Post(
              pid: 1,
              floor: 1,
              author: '楼主',
              timeRaw: '',
              content: [for (var n = 0; n < 1000; n++) TextBlock('千块正文$n')],
            ),
            for (var n = 2; n <= 8; n++) _post(n),
          ]),
        ),
      );
      expect(find.byType(ThreadCommentHeading), findsNothing);
      expect(find.byType(PostCard).evaluate().length, lessThan(30));
      await tester.tap(find.byKey(ReadingBar.actionKey));
      await tester.pump();
      expect(find.byType(PostCard).evaluate().length, lessThan(30));
      expect(find.text('千块正文500'), findsNothing);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('comment-mode-1')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byType(ThreadCommentHeading)).dy,
        greaterThanOrEqualTo(NavOverlay.barHeight),
      );
      expect(
        tester.widget<ReadingBar>(find.byType(ReadingBar)).inComments,
        isTrue,
      );
      expect(find.byTooltip('回到顶部'), findsOneWidget);
      expect(
        find.text('正文2', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('千块正文500'), findsNothing);
      expect(find.byType(PostCard).evaluate().length, lessThan(30));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('reduced motion keeps a 150ms opacity fade for arrived replies', (
    tester,
  ) async {
    final author = Completer<ThreadDetail>();
    await _mount(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '',
        loadPage: (_, uid, _) => uid == null
            ? Future.value(_page([_post(1), _post(2), _post(3)]))
            : author.future,
      ),
      reduced: true,
    );
    final mode = find.descendant(
      of: find.byType(CommentModeBar),
      matching: find.byKey(const ValueKey('comment-mode-2')),
    );
    await tester.ensureVisible(mode);
    await tester.pumpAndSettle();
    await tester.tap(mode);
    await tester.pump();
    author.complete(_page([_post(1), _post(12, uid: '1')]));
    await tester.pump();
    double opacity() => tester
        .widget<ContentFade>(
          find
              .ancestor(of: _card(12), matching: find.byType(ContentFade))
              .first,
        )
        .opacity
        .value;
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 75));
    expect(opacity(), greaterThan(0));
    expect(opacity(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 75));
    expect(opacity(), 1);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
