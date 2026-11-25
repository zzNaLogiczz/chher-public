import 'dart:async';

import 'package:chh_app/core/display_time.dart';
import 'package:chh_app/data/follow_index.dart';
import 'package:chh_app/data/follow_poller.dart';
import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/follow_block_page.dart';
import 'package:chh_app/pages/follow_feed_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messages_ui_test.dart' show FakeMessages, phone;

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: child,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: child!,
  ),
);

ThreadSummary _topic(
  int tid,
  DateTime? at, {
  int fid = 22,
  String uid = '42',
}) => ThreadSummary(
  tid: tid,
  title: '主题 $tid',
  author: '山间小站',
  authorUid: uid,
  forumFid: fid,
  forumName: '电脑讨论',
  createdAt: at,
  replies: 8,
  views: 10,
);

Future<void> _pullFollowFeed(WidgetTester tester) async {
  final pull = await tester.startGesture(
    tester.getCenter(find.byType(ListView)),
  );
  await pull.moveBy(const Offset(0, 30));
  await pull.moveBy(const Offset(0, 180));
  await tester.pump();
  expect(tester.widget<ChhersLoader>(find.byType(ChhersLoader)).progress, 1);
  await pull.up();
  await tester.pump();
}

void main() {
  testWidgets('reminders only show the follow card with followed users', (
    tester,
  ) async {
    phone(tester);
    final index = FollowIndex.forTesting(null);
    addTearDown(index.dispose);
    final now = DateTime.now();
    final card = find.byKey(const ValueKey('follow-notice'));
    final activityRow = find.descendant(
      of: find.byKey(const ValueKey(501)),
      matching: find.byType(ThreadRow),
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: MessagesBody(repository: FakeMessages(), follows: index),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(card, findsNothing);

    await index.follow(
      uid: '42',
      name: '山间小站',
      at: now.subtract(const Duration(days: 1)),
    );
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(find.text('关注的人还没有发新帖'), findsOneWidget);
    final avatars = find.descendant(
      of: card,
      matching: find.byType(AvatarImage),
    );
    expect(avatars, findsOneWidget);
    expect(
      tester.getTopLeft(card).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('message-filter-row'))).dy,
      ),
    );

    await index.sightThreads([_topic(500, now), _topic(501, now)]);
    await index.recordThreadCheck(index.all.single, [
      _topic(499, null),
    ], at: now.add(const Duration(minutes: 1)));
    await index.follow(uid: '57', name: '另一位坛友');
    await tester.pumpAndSettle();
    expect(avatars, findsNWidgets(2));
    expect(index.activities.map((item) => item.thread.tid), [501, 500, 499]);
    final subtitle = find.descendant(
      of: card,
      matching: find.text('山间小站：主题 501'),
    );
    expect(subtitle, findsOneWidget);
    expect(find.text('山间小站：主题 499'), findsNothing);
    expect(find.text('+2'), findsOneWidget);

    await tester.tap(find.text('私信').hitTestable().first);
    await tester.pumpAndSettle();
    expect(card.hitTestable(), findsNothing);
    await tester.tap(find.text('提醒').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.byType(FollowFeedPage), findsOneWidget);
    expect(index.unseenCount, 0);
    expect(tester.widget<ThreadRow>(activityRow).followUnseen, isTrue);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(subtitle, findsOneWidget);
    expect(find.text('+2'), findsNothing);

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(tester.widget<ThreadRow>(activityRow).followUnseen, isFalse);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await index.setUid(null);
    await tester.pump();
    expect(card, findsNothing);
  });

  testWidgets('the flat follow feed includes trading and keeps row times', (
    tester,
  ) async {
    phone(tester);
    final index = FollowIndex.forTesting(null);
    addTearDown(index.dispose);
    final now = DateTime.now();
    final today = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour == 0 ? 12 : 0,
    );
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
    final earlier = DateTime(now.year, now.month, now.day - 3, 12);
    await index.follow(uid: '42', name: '山间小站', at: earlier);
    await index.sightThreads([
      _topic(10, earlier),
      _topic(11, yesterday),
      _topic(12, today),
      _topic(13, today, fid: 328),
      _topic(14, today, fid: 26),
    ]);
    await index.recordThreadCheck(index.all.single, [_topic(9, null)], at: now);
    expect(index.unseenCount, 4);
    await tester.pumpWidget(_app(FollowFeedPage(index: index), reduced: true));
    await tester.pumpAndSettle();

    final rows = tester.widgetList<ThreadRow>(find.byType(ThreadRow)).toList();
    expect(rows.map((row) => row.thread.tid), [14, 13, 12, 11, 10, 9]);
    expect(rows.take(2).map((row) => row.thread.forumFid), [26, 328]);
    expect(rows.map((row) => row.timeLabel), [
      for (final at in [today, today, today, yesterday, earlier])
        formatDisplayTime(at: at, style: DisplayTimeStyle.list),
      null,
    ]);
    expect(rows.map((row) => row.followUnseen), [
      true,
      true,
      true,
      true,
      false,
      false,
    ]);
    expect(find.text('还没有新动态'), findsNothing);
    expect(index.unseenCount, 0);
    await tester.tap(find.text('关注了 1 人'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowBlockPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LargeTitleHeader),
        matching: find.text('关注及黑名单'),
      ),
      findsOneWidget,
    );
    expect(find.text('山间小站'), findsOneWidget);
    expect(find.text('黑名单为空'), findsNothing);
  });

  testWidgets('S2 mixes dated and undated topics in descending tid order', (
    tester,
  ) async {
    phone(tester);
    final index = FollowIndex.forTesting(null);
    addTearDown(index.dispose);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final november22 = DateTime(now.year - 1, 11, 22, 12);
    await index.follow(uid: '42', name: '山间小站', at: november22);
    await index.follow(uid: '57', name: '另一位坛友', at: november22);
    await index.sightThreads([_topic(250, today), _topic(200, november22)]);
    await index.recordThreadCheck(
      index.all.singleWhere((user) => user.uid == '57'),
      [_topic(300, null, uid: '57'), _topic(100, null, uid: '57')],
      at: now,
    );

    await tester.pumpWidget(_app(FollowFeedPage(index: index), reduced: true));
    await tester.pumpAndSettle();

    final rows = tester.widgetList<ThreadRow>(find.byType(ThreadRow));
    expect(rows.map((row) => row.thread.tid), [300, 250, 200, 100]);
    expect(rows.map((row) => row.thread.authorUid), ['57', '42', '42', '57']);
    final datedRow = find.byKey(const ValueKey(200));
    final dateLabel = '${november22.year}年11月22日';
    expect(
      find.descendant(of: datedRow, matching: find.text(dateLabel)),
      findsOneWidget,
    );
    expect(
      rows.where((row) => row.timeLabel == null).map((row) => row.thread.tid),
      [300, 100],
    );
    for (final tid in [300, 100]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(tid)),
          matching: find.textContaining(
            RegExp(r'刚刚|\d+\s*分钟前|\d{2}:\d{2}|\d+月\d+日'),
          ),
        ),
        findsNothing,
      );
    }
    expect(find.text('今天'), findsNothing);
    expect(find.text('昨天'), findsNothing);
    expect(find.text('11月22日'), findsNothing);
    expect(find.text(dateLabel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.header == true,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('entering refreshes local activities even after a recent check', (
    tester,
  ) async {
    phone(tester);
    final index = FollowIndex.forTesting(null);
    final now = DateTime.now();
    await index.follow(
      uid: '42',
      name: '山间小站',
      at: now.subtract(const Duration(hours: 1)),
    );
    await index.sightThreads([_topic(10, now)]);
    await index.recordCheck('42', at: tester.binding.clock.now());
    final requests = <Completer<List<ThreadSummary>>>[];
    bool Function()? current;
    final poller = FollowPoller(
      index: index,
      now: tester.binding.clock.now,
      fetchThreads: (uid, shouldContinue) {
        expect(uid, '42');
        current = shouldContinue;
        final response = Completer<List<ThreadSummary>>();
        requests.add(response);
        return response.future;
      },
    );
    addTearDown(() {
      poller.dispose();
      index.dispose();
    });
    poller.update(foreground: true, loggedIn: true, sessionRevision: 1);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        navigatorKey: navigator,
        home: const Scaffold(),
      ),
    );
    void openFeed() => navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FollowFeedPage(index: index, poller: poller),
      ),
    );

    openFeed();
    await tester.pump();
    expect(requests, hasLength(1));
    await tester.pumpAndSettle();
    expect(find.text('主题 10'), findsOneWidget);
    expect(find.text('主题 11'), findsNothing);

    requests[0].complete([_topic(11, now, fid: 328)]);
    await tester.pumpAndSettle();
    expect(find.text('主题 10'), findsOneWidget);
    expect(find.text('主题 11'), findsOneWidget);
    expect(index.unseenCount, 1);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    openFeed();
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(find.text('主题 11'), findsOneWidget);

    await _pullFollowFeed(tester);
    expect(requests, hasLength(2));
    navigator.currentState!.pop();
    expect(current!(), isFalse);
    requests[1].complete([_topic(12, now)]);
    await tester.pumpAndSettle();
    expect(index.activities.map((item) => item.thread.tid), [11, 10]);

    openFeed();
    await tester.pumpAndSettle();
    expect(requests, hasLength(3));
    requests[2].completeError(StateError('read'));
    await tester.pumpAndSettle();
    expect(find.text('主题 11'), findsOneWidget);
  });

  for (final (loggedIn, hasFollows) in [
    (true, true),
    (false, true),
    (true, false),
  ]) {
    final scenario = !loggedIn
        ? 'signed out'
        : hasFollows
        ? 'with recent checks'
        : 'with no followed users';
    testWidgets('pulling an empty follow feed $scenario', (tester) async {
      phone(tester);
      final index = FollowIndex.forTesting(null);
      final now = DateTime.now();
      if (hasFollows) {
        await index.follow(
          uid: '42',
          name: '山间小站',
          at: now.subtract(const Duration(hours: 1)),
          lastTid: 10,
        );
        await index.recordCheck('42', at: tester.binding.clock.now());
      }
      final requests = <Completer<List<ThreadSummary>>>[];
      final poller = FollowPoller(
        index: index,
        now: tester.binding.clock.now,
        fetchThreads: (uid, _) {
          expect(uid, '42');
          final response = Completer<List<ThreadSummary>>();
          requests.add(response);
          return response.future;
        },
      );
      addTearDown(index.dispose);
      poller.update(foreground: true, loggedIn: loggedIn, sessionRevision: 1);
      await tester.pumpWidget(
        _app(FollowFeedPage(index: index, poller: poller)),
      );
      await tester.pumpAndSettle();
      final canCheck = loggedIn && hasFollows;
      if (canCheck) {
        expect(requests, hasLength(1));
        requests.single.complete([]);
        await tester.pumpAndSettle();
      }
      expect(find.text('还没有新动态'), findsOneWidget);
      final loader = find.byType(ChhersLoader);
      expect(loader, findsNothing);

      await _pullFollowFeed(tester);
      if (canCheck) {
        expect(requests, hasLength(2));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.widget<ChhersLoader>(loader).animate, isTrue);
        expect(find.text('还没有新动态'), findsOneWidget);
        requests.last.complete([_topic(11, now)]);
        await tester.pumpAndSettle();
        expect(find.text('主题 11'), findsOneWidget);
      } else {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 50),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 2),
        );
        expect(requests, isEmpty);
        expect(find.text('还没有新动态'), findsOneWidget);
      }
      expect(loader, findsNothing);
      expect(tester.takeException(), isNull);
      poller.dispose();
    });
  }

  testWidgets('following search matches UID and toggles the row in place', (
    tester,
  ) async {
    phone(tester);
    final index = FollowIndex.forTesting(null);
    addTearDown(index.dispose);
    final now = DateTime.now();
    await index.follow(
      uid: '42',
      name: '山间小站',
      at: now.subtract(const Duration(hours: 1)),
    );
    await index.follow(uid: '57', name: '另一位坛友', at: now);
    await index.sightThreads([_topic(500, now)]);
    await tester.pumpWidget(_app(FollowBlockPage(follows: index)));
    await tester.pumpAndSettle();

    final first = find.text('另一位坛友');
    final second = find.text('山间小站');
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(find.textContaining('最近发帖'), findsOneWidget);
    final search = find.byType(TextField);
    await tester.tap(search);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(search, '42');
    await tester.pumpAndSettle();
    expect(first, findsNothing);
    expect(second, findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(first, findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    final row = find.byKey(const ValueKey('42'));
    await tester.tap(find.descendant(of: row, matching: find.text('关注中')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('已取消关注'), findsOneWidget);
    expect(index.isFollowed('42'), isFalse);
    expect(
      find.descendant(of: row, matching: find.text('未关注')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: row, matching: find.text('未关注')));
    await tester.pumpAndSettle();
    expect(index.isFollowed('42'), isTrue);
    expect(
      find.descendant(of: row, matching: find.text('关注中')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));

    await index.setUid('901');
    await tester.pump();
    expect(find.text('还没有关注任何人'), findsOneWidget);
    expect(first, findsNothing);
    expect(second, findsNothing);
  });

  testWidgets('follow feed clears visit markers across accounts', (
    tester,
  ) async {
    phone(tester);
    final index = FollowIndex.forTesting(null);
    addTearDown(index.dispose);
    final now = DateTime.now();
    final followedAt = now.subtract(const Duration(hours: 1));
    await index.follow(uid: '42', name: '账号 A 的关注', at: followedAt);
    await index.sightThreads([_topic(500, now)]);
    await tester.pumpWidget(_app(FollowFeedPage(index: index)));
    await tester.pumpAndSettle();
    final row = find.byType(ThreadRow);
    expect(tester.widget<ThreadRow>(row).followUnseen, isTrue);

    await index.setUid('901');
    await tester.pump();
    expect(row, findsNothing);
    expect(find.text('还没有新动态'), findsOneWidget);

    await index.follow(uid: '42', name: '账号 B 的关注', at: followedAt);
    await index.sightThreads([_topic(500, now)]);
    await index.markAllSeen();
    await tester.pumpAndSettle();
    expect(tester.widget<ThreadRow>(row).followUnseen, isFalse);
  });

  testWidgets('follow and block tabs retain separate searches and scrolls', (
    tester,
  ) async {
    phone(tester);
    final follows = FollowIndex.forTesting(null);
    final blocks = UserBlockIndex.forTesting(null);
    addTearDown(follows.dispose);
    addTearDown(blocks.dispose);
    for (var i = 0; i < 20; i++) {
      await follows.follow(uid: '${100 + i}', name: '关注样例 $i');
      await blocks.block(uid: '${200 + i}', name: '黑名单样例 $i');
    }
    await tester.pumpWidget(
      _app(FollowBlockPage(follows: follows, blocks: blocks)),
    );
    await tester.pumpAndSettle();

    final search = find.byType(TextField);
    String query() => tester.widget<TextField>(search).controller!.text;
    final list = find.byType(ListView);
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find.descendant(
            of: list,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
            ),
          ),
        )
        .position;
    Future<void> select(String tab) async {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }

    expect(query(), isEmpty);
    expect(find.textContaining('关注样例'), findsWidgets);
    expect(find.textContaining('黑名单样例'), findsNothing);
    await tester.enterText(search, '关注样例');
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -270));
    await tester.pumpAndSettle();
    final followsOffset = position().pixels;
    expect(followsOffset, greaterThan(0));

    await select('黑名单');
    expect(query(), isEmpty);
    expect(position().pixels, 0);
    expect(find.textContaining('关注样例'), findsNothing);
    await tester.enterText(search, '黑名单样例');
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -360));
    await tester.pumpAndSettle();
    final blocksOffset = position().pixels;
    expect(blocksOffset, greaterThan(followsOffset));

    await select('关注');
    expect(position().pixels, followsOffset);
    expect(find.textContaining('黑名单样例'), findsNothing);
    position().jumpTo(0);
    await tester.pumpAndSettle();
    expect(query(), '关注样例');
    await select('黑名单');
    expect(position().pixels, blocksOffset);
    expect(find.textContaining('关注样例'), findsNothing);
    position().jumpTo(0);
    await tester.pumpAndSettle();
    expect(query(), '黑名单样例');
  });
}
