import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/get_page_parser.dart';
import 'package:chh_app/parser/parser_worker.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/ui/reading_bar.dart';
import 'package:chh_app/widgets/anchored_reading_list.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:chh_app/widgets/chhers_loading_transition.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/reading_list_end.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inline_forum_parser.dart';

const _tid = 900001;
const _frame = Duration(milliseconds: 8);
final _reader = find.byType(ThreadDetailPage, skipOffstage: false);
final _cards = find.descendant(
  of: _reader,
  matching: find.byType(PostCard, skipOffstage: false),
  skipOffstage: false,
);

class _ProbePost extends Post {
  _ProbePost(int floor, this.prepared)
    : super(
        pid: floor,
        floor: floor,
        author: '本地样例作者',
        timeRaw: '',
        content: [TextBlock('离线楼层 $floor')],
      );

  final Set<int> prepared;

  @override
  Post copyWith({
    List<ContentBlock>? content,
    List<PostComment>? comments,
    PostRating? rating,
  }) {
    prepared.add(this.pid);
    return super.copyWith(content: content, comments: comments, rating: rating);
  }
}

ThreadDetail _detail(Set<int> prepared) => ThreadDetail(
  tid: _tid,
  title: '离线帖子',
  replyCount: 59,
  posts: [
    for (var floor = 1; floor <= 60; floor++) _ProbePost(floor, prepared),
  ],
  page: const PageInfo(current: 1, hasNext: false),
);

class _Fixture extends ChhFetcher {
  _Fixture([this.html]);

  final String? html;
  int requests = 0;
  @override
  String get name => 'offline-thread';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests++;
    return ChhResponse(
      200,
      html ?? File('test_data/thread_synthetic.html').readAsStringSync(),
    );
  }
}

class _EntryProbeRepository extends ForumRepository {
  _EntryProbeRepository(super.client);

  final coveragePhases = <SchedulerPhase>[];

  @override
  ({int lastPage, bool recent, int? replyCount, int? verifiedCountSequence})?
  cachedThreadCoverage(int tid, {int? observedReplies}) {
    coveragePhases.add(SchedulerBinding.instance.schedulerPhase);
    return super.cachedThreadCoverage(tid, observedReplies: observedReplies);
  }
}

Future<PageRoute<void>> _push(
  WidgetTester tester,
  ThreadDetailPage reader, {
  Duration? duration,
}) async {
  tester.view.physicalSize = const Size(390, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      navigatorKey: navigator,
      home: const Scaffold(body: Text('起始页')),
    ),
  );
  final route = duration == null
      ? MaterialPageRoute<void>(builder: (_) => reader)
      : PageRouteBuilder<void>(
          transitionDuration: duration,
          pageBuilder: (_, _, _) => reader,
        );
  unawaited(navigator.currentState!.push(route));
  await tester.pump();
  expect(_reader, findsOneWidget);
  return route;
}

ThreadDetailPage _cold(Completer<ThreadDetail> result) => ThreadDetailPage(
  tid: _tid,
  title: '离线帖子',
  preloadPages: 1,
  loadPage: (_, _, _) => result.future,
);

Post _post(int floor, {int? replyTo, int paragraphs = 1, PostRating? rating}) =>
    Post(
      pid: floor,
      floor: floor,
      author: '样例作者$floor',
      authorUid: '$floor',
      timeRaw: '',
      rating: rating,
      content: [
        if (replyTo != null)
          QuoteBlock(
            const [TextBlock('本地引用')],
            reference: PostReference(
              tid: _tid,
              pid: replyTo,
              url: 'https://example.invalid/?pid=$replyTo',
            ),
          ),
        for (var paragraph = 0; paragraph < paragraphs; paragraph++)
          TextBlock('楼层 $floor 的正文 $paragraph'),
      ],
    );

ThreadDetail _page(List<Post> posts, {int number = 1, bool next = false}) =>
    ThreadDetail(
      tid: _tid,
      title: '离线帖子',
      posts: posts,
      page: PageInfo(current: number, hasNext: next),
    );

typedef _VisibleLayout = ({
  List<(String, Rect)> rows,
  List<(int, bool)> cards,
  List<String> entryLabels,
  List<(int, int?, bool)> counts,
});

_VisibleLayout _visibleLayout(WidgetTester tester, {bool includeTail = true}) {
  final list = find.byType(AnchoredReadingList);
  final viewport = tester.getRect(list);
  final visible = <(Widget, Rect)>[];
  for (final element
      in find
          .descendant(
            of: list,
            matching: find.byWidgetPredicate((widget) {
              final key = widget.key;
              return widget is PostCard ||
                  widget is ThreadCommentHeading ||
                  (includeTail && widget is ReadingListEnd) ||
                  (key is ValueKey<String> &&
                      switch (widget) {
                        PressScale() => key.value.startsWith(
                          'thread-expand-replies-',
                        ),
                        Padding() || KeyedSubtree() =>
                          key.value.startsWith('post-') ||
                              key.value == 'comments-heading',
                        _ => false,
                      });
            }),
          )
          .evaluate()) {
    final box = element.findRenderObject()! as RenderBox;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    if (bounds.height > 0 && bounds.overlaps(viewport)) {
      visible.add((element.widget, bounds));
    }
  }
  visible.sort((first, second) => first.$2.top.compareTo(second.$2.top));
  return (
    rows: [
      for (final (widget, bounds) in visible)
        if (widget is Padding ||
            widget is KeyedSubtree ||
            widget is ReadingListEnd)
          (
            widget is ReadingListEnd
                ? 'tail'
                : (widget.key! as ValueKey<String>).value,
            bounds,
          ),
    ],
    cards: {
      for (final (widget, _) in visible)
        if (widget is PostCard) (widget.post.pid, widget.nested),
    }.toList(),
    entryLabels: [
      for (final (widget, _) in visible)
        if (widget is PressScale) widget.semanticLabel!,
    ],
    counts: [
      for (final (widget, _) in visible)
        if (widget is ThreadCommentHeading)
          (widget.loadedCount, widget.totalCount, widget.complete),
    ],
  );
}

void _expectSameLayout(_VisibleLayout first, _VisibleLayout later) {
  expect(later.cards, first.cards);
  expect(later.entryLabels, first.entryLabels);
  expect(later.counts, first.counts);
  expect(later.rows.map((row) => row.$1), first.rows.map((row) => row.$1));
  for (var i = 0; i < first.rows.length; i++) {
    final (key, before) = first.rows[i];
    final (_, after) = later.rows[i];
    expect(after.left, closeTo(before.left, .001), reason: key);
    expect(after.top, closeTo(before.top, .001), reason: key);
    expect(after.width, closeTo(before.width, .001), reason: key);
    expect(after.height, closeTo(before.height, .001), reason: key);
  }
}

Future<void> _pumpFirstContent(WidgetTester tester) async {
  for (var frame = 0; frame < 100 && _cards.evaluate().isEmpty; frame++) {
    await tester.pump(_frame);
  }
  expect(_cards, findsWidgets);
}

String _parserFixture() =>
    '''
<html><head><title>离线帖子</title></head><body>
<div class="bm"></div><h1 id="thread_subject">离线帖子</h1>
<div id="postlist">
${List.generate(4, (index) {
      final floor = index + 1;
      return '''
    <div id="post_$floor"><table id="pid$floor"><tr><td>
    <a href="space-uid-$floor.html">样例作者$floor</a>
    <a id="postnum$floor">$floor#</a></td>
    <td id="postmessage_$floor">
    ${floor > 2 ? '<div class="quote"><blockquote><a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=$_tid&amp;pid=2">样例作者2 发表于 2026-01-02 03:04</a><br>本地引用</blockquote></div>' : ''}
    <p>离线正文$floor</p></td></tr></table></div>''';
    }).join()}
</div><div class="pg"><strong>1</strong></div></body></html>
''';

Future<R> _holdWorker<M, R>((ComputeCallback<M, R>, M, SendPort) job) async {
  final result = await job.$1(job.$2);
  final release = ReceivePort();
  job.$3.send(release.sendPort);
  await release.first;
  return result;
}

void main() {
  testWidgets('cold detail first laid out on the frame after route entry', (
    tester,
  ) async {
    final prepared = <int>{};
    final result = Completer<ThreadDetail>();
    final route = await _push(tester, _cold(result));
    result.complete(_detail(prepared));
    await tester.pump(_frame);
    expect(route.animation!.status, AnimationStatus.forward);
    expect(_cards, findsNothing);
    expect(prepared, isEmpty);

    for (var i = 0; i < 100 && !route.animation!.isCompleted; i++) {
      await tester.pump(_frame);
      expect(_cards, findsNothing);
    }
    expect(route.animation!.status, AnimationStatus.completed);
    expect(_cards, findsNothing);
    expect(prepared, isEmpty);

    await tester.pump(_frame);
    final state = tester.state(_reader) as dynamic;
    expect(state.debugConversationIndex.loadedPostCount, 60);
    expect(state.debugPreparingEntries, isTrue);
    final firstCards = tester.widgetList<PostCard>(_cards).toList();
    final laidOut = firstCards.map((card) => card.post.pid).toSet();
    expect(laidOut, containsAll([1, 2]));
    expect(laidOut, hasLength(lessThan(10)));
    expect(prepared, containsAll(laidOut));
    expect(prepared.length, lessThanOrEqualTo(laidOut.length + 1));
    expect(
      tester
          .widget<AnchoredReadingList>(find.byType(AnchoredReadingList))
          .scrollCacheExtent,
      isNotNull,
    );

    await tester.pumpAndSettle(_frame);
    expect(state.debugConversationIndex.loadedPostCount, 60);
    expect(state.debugPreparingEntries, isFalse);
    expect(state.debugPreparedEntryCount, greaterThan(60));
    expect(prepared, hasLength(60));
  });

  testWidgets('cold detail fades in on the same frame as the wordmark exits', (
    tester,
  ) async {
    final result = Completer<ThreadDetail>();
    final route = await _push(tester, _cold(result));
    await tester.pump(AppMotion.skeletonDelay + route.transitionDuration);
    await tester.pump(AppMotion.fade);
    final loader = find.descendant(
      of: _reader,
      matching: find.byType(ChhersLoader),
    );
    expect(loader, findsOneWidget);
    final mark = tester.element(loader);
    expect(route.animation!.isCompleted, isTrue);

    result.complete(_detail({}));
    await tester.pump(_frame);
    expect(_cards, findsWidgets);
    expect(tester.element(loader), same(mark));
    final reveal = find.descendant(
      of: _reader,
      matching: find.byType(ExpressivePageReveal),
    );
    expect(reveal, findsOneWidget);
    final revealElement = tester.element(reveal);
    final openingElement = tester.element(_cards.first);
    final fade =
        tester
                .widget<AnimatedBuilder>(
                  find
                      .descendant(
                        of: reveal,
                        matching: find.byType(AnimatedBuilder),
                      )
                      .first,
                )
                .animation
            as Animation<double>;
    final initial = fade.value;
    expect(initial, allOf(greaterThan(0), lessThan(1)));

    await tester.pump(AppMotion.loadingOut ~/ 2);
    final duringExit = fade.value;
    expect(duringExit, allOf(greaterThan(initial), lessThan(1)));
    expect(loader, findsOneWidget);
    await tester.pump(AppMotion.loadingOut);
    expect(loader, findsNothing);
    expect(fade.value, greaterThanOrEqualTo(duringExit));
    await tester.pumpAndSettle(_frame);
    expect(fade.value, 1);
    expect(tester.element(reveal), same(revealElement));
    expect(tester.element(_cards.first), same(openingElement));
  });

  testWidgets('late detail fades on the next frame before the wordmark shows', (
    tester,
  ) async {
    final result = Completer<ThreadDetail>();
    final route = await _push(
      tester,
      _cold(result),
      duration: const Duration(milliseconds: 100),
    );
    for (var frame = 0; frame < 30 && !route.animation!.isCompleted; frame++) {
      await tester.pump(_frame);
      expect(_cards, findsNothing);
    }
    expect(route.animation!.isCompleted, isTrue);
    result.complete(_detail({}));
    await tester.pump(_frame);
    expect(_cards, findsWidgets);
    expect(find.byType(ChhersLoader), findsNothing);
    final reveal = find.byType(ExpressivePageReveal);
    final fade =
        tester
                .widget<AnimatedBuilder>(
                  find
                      .descendant(
                        of: reveal,
                        matching: find.byType(AnimatedBuilder),
                      )
                      .first,
                )
                .animation
            as Animation<double>;
    var progress = fade.value;
    expect(progress, allOf(greaterThan(0), lessThan(1)));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(_frame);
      expect(fade.value, greaterThanOrEqualTo(progress));
      expect(find.byType(ChhersLoader), findsNothing);
      progress = fade.value;
    }
    expect(progress, 1);
  });

  testWidgets('cold detail route paints before coverage and request setup', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);
    final transport = _Fixture();
    final repo = _EntryProbeRepository(
      ChhClient(fetchers: [transport], dispatchParser: parseForumInline),
    );
    final route = await _push(
      tester,
      ThreadDetailPage(
        tid: _tid,
        title: '离线帖子',
        repository: repo,
        preloadPages: 1,
      ),
    );
    expect(repo.coveragePhases, isEmpty);
    expect(transport.requests, 0);
    var requestCountOnPaint = -1;
    tester.binding.addPostFrameCallback((_) {
      requestCountOnPaint = transport.requests;
    });
    await tester.pump(_frame);
    expect(requestCountOnPaint, 0);
    expect(repo.coveragePhases, [SchedulerPhase.idle]);
    expect(transport.requests, 1);
    expect(route.animation!.isAnimating, isTrue);
    expect(_cards, findsNothing);
    for (var frame = 0; frame < 150 && !route.animation!.isCompleted; frame++) {
      await tester.pump(_frame);
    }
    await tester.pump(_frame);
    final list = find.byType(AnchoredReadingList);
    expect(tester.widget<AnchoredReadingList>(list).initialItemLimit, 3);
    final body = find.byType(ChhersLoadingTransition);
    double bottomInset() => MediaQuery.paddingOf(tester.element(body)).bottom;
    final initialInset = bottomInset();
    expect(
      initialInset,
      ReadingBar.heightFor(bottomPadding: 24, threadStyle: true),
    );
    expect(find.byType(ReadingBar), findsNothing);
    final opening = tester.element(_cards.first);
    final initialPosition = tester.getRect(_cards.first);
    await tester.pump(_frame);
    expect(tester.widget<AnchoredReadingList>(list).initialItemLimit, isNull);
    expect(bottomInset(), initialInset);
    expect(find.byType(ReadingBar), findsOneWidget);
    expect(tester.element(_cards.first), same(opening));
    expect(tester.getRect(_cards.first), initialPosition);
    await tester.pumpAndSettle(_frame);
  });

  testWidgets('cold image-first detail defers its picture to the next frame', (
    tester,
  ) async {
    final transport = _Fixture(
      _parserFixture().replaceFirst(
        '离线正文1',
        '<img src="https://example.invalid/phase4.jpg" width="400" height="300">',
      ),
    );
    final repository = ForumRepository(
      ChhClient(fetchers: [transport], dispatchParser: parseForumInline),
    );
    await _push(
      tester,
      ThreadDetailPage(
        tid: _tid,
        title: '离线帖子',
        repository: repository,
        preloadPages: 1,
      ),
    );

    await _pumpFirstContent(tester);
    expect(find.byType(InlineImageViewer), findsNothing);
    final opening = tester.element(_cards.first);
    final initialPosition = tester.getRect(_cards.first);
    await tester.pump(_frame);
    expect(find.byType(InlineImageViewer), findsOneWidget);
    expect(tester.element(_cards.first), same(opening));
    expect(tester.getRect(_cards.first), initialPosition);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final ({String name, bool long, bool blocked}) scenario in [
    (name: 'short quoted thread', long: false, blocked: false),
    (name: 'long thread', long: true, blocked: false),
    (
      name: 'blocked root with visible grouped reply',
      long: false,
      blocked: true,
    ),
  ]) {
    testWidgets('${scenario.name} keeps its first viewport after preparation', (
      tester,
    ) async {
      final blocks = UserBlockIndex.forTesting(null);
      addTearDown(blocks.dispose);
      if (scenario.blocked) await blocks.block(uid: '2', name: '样例作者2');
      final result = Completer<ThreadDetail>();
      await _push(
        tester,
        ThreadDetailPage(
          tid: _tid,
          title: '离线帖子',
          preloadPages: 1,
          blockIndex: blocks,
          loadPage: (_, _, _) => result.future,
        ),
      );
      result.complete(
        _page([
          _post(1, paragraphs: scenario.long ? 45 : 1),
          _post(2),
          _post(3, replyTo: 2),
          if (scenario.long)
            for (var floor = 4; floor <= 60; floor++) _post(floor),
        ]),
      );
      await _pumpFirstContent(tester);
      final state = tester.state(_reader) as dynamic;
      expect(state.debugConversationIndex.rootPidFor(3), 2);
      final first = _visibleLayout(tester);
      if (scenario.long) {
        expect(state.debugPreparingEntries, isTrue);
        expect(state.debugPreparedEntryCount, lessThan(45));
        expect(first.rows.length, greaterThan(5));
        expect(first.cards, everyElement((1, false)));
      } else {
        expect(first.rows.map((row) => row.$1), contains('post-2-replies--1'));
        expect(
          first.cards,
          scenario.blocked ? [(1, false)] : [(1, false), (2, false)],
        );
        expect(first.entryLabels, ['展开 1 条回复']);
        expect(first.counts, [
          (scenario.blocked ? 1 : 2, null, !scenario.blocked),
        ]);
      }
      await tester.pumpAndSettle(_frame);
      expect(state.debugPreparingEntries, isFalse);
      _expectSameLayout(first, _visibleLayout(tester));
    });
  }

  testWidgets(
    'continuation page keeps its first viewport while next page waits',
    (tester) async {
      final initial = Completer<ThreadDetail>();
      final next = Completer<ThreadDetail>();
      final requests = <int>[];
      await _push(
        tester,
        ThreadDetailPage(
          tid: _tid,
          title: '离线续页',
          initialPage: 2,
          preloadPages: 1,
          loadPage: (number, _, _) {
            requests.add(number);
            return number == 2 ? initial.future : next.future;
          },
        ),
      );
      initial.complete(
        _page([_post(10), _post(11, replyTo: 10)], number: 2, next: true),
      );
      await _pumpFirstContent(tester);
      final state = tester.state(_reader) as dynamic;
      expect(state.debugConversationIndex.rootPidFor(11), 10);
      final first = _visibleLayout(tester, includeTail: false);
      expect(first.cards, [(10, false)]);
      expect(first.entryLabels, ['展开 1 条回复']);
      expect(first.counts, [(2, null, false)]);
      for (var frame = 0; frame < 100 && requests.length == 1; frame++) {
        await tester.pump(_frame);
      }
      expect(requests, [2, 3]);
      expect(state.debugPreparingEntries, isFalse);
      await tester.pump(_frame);
      _expectSameLayout(first, _visibleLayout(tester, includeTail: false));
      next.complete(_page([_post(12, replyTo: 10), _post(13)], number: 3));
      await tester.pumpAndSettle(_frame);
      expect(state.debugConversationIndex.rootPidFor(12), 10);
      expect(find.text('展开 2 条回复'), findsOneWidget);
    },
  );

  testWidgets('grouped goto anchors its child on the first viewport', (
    tester,
  ) async {
    final result = Completer<ThreadDetail>();
    await _push(
      tester,
      ThreadDetailPage(
        tid: _tid,
        title: '离线定位',
        gotoUrl: 'https://example.invalid/?goto=findpost&pid=27',
        focusPid: 27,
        preloadPages: 1,
        loadGoto: (_) => result.future,
        loadPage: (_, _, _) => throw StateError('Expected goto only'),
      ),
    );
    result.complete(
      _page([
        for (var floor = 10; floor <= 26; floor++) _post(floor),
        _post(27, replyTo: 24),
        _post(28, replyTo: 27),
        for (var floor = 29; floor <= 60; floor++) _post(floor),
      ], number: 2),
    );
    await _pumpFirstContent(tester);
    final state = tester.state(_reader) as dynamic;
    expect(state.debugConversationIndex.rootPidFor(27), 24);
    expect(state.debugConversationIndex.rootPidFor(28), 24);
    expect(state.debugPreparingEntries, isTrue);
    final first = _visibleLayout(tester);
    expect(first.cards, containsAllInOrder([(24, false), (27, true)]));
    expect(first.cards, isNot(contains((28, true))));
    expect(first.entryLabels, contains('展开 1 条回复'));
    await tester.pumpAndSettle(_frame);
    expect(state.debugPreparingEntries, isFalse);
    _expectSameLayout(first, _visibleLayout(tester));
  });

  testWidgets(
    'opening feedback goto anchors the footer on the first viewport',
    (tester) async {
      final result = Completer<ThreadDetail>();
      await _push(
        tester,
        ThreadDetailPage(
          tid: _tid,
          title: '离线反馈',
          gotoUrl: 'https://example.invalid/?goto=findpost&pid=1',
          focusOpeningFeedback: true,
          preloadPages: 1,
          loadGoto: (_) => result.future,
        ),
      );
      result.complete(
        _page([
          _post(
            1,
            paragraphs: 45,
            rating: const PostRating(summary: ['邪恶指数 +1'], entries: []),
          ),
          for (var floor = 2; floor <= 60; floor++) _post(floor),
        ]),
      );
      await _pumpFirstContent(tester);
      expect(find.text('+1 邪恶指数'), findsOneWidget);
      expect(find.text('楼层 1 的正文 0'), findsNothing);
      final first = _visibleLayout(tester);
      expect(first.rows.map((row) => row.$1), contains('post-1-footer--1'));
      await tester.pumpAndSettle(_frame);
      expect(find.text('+1 邪恶指数').hitTestable(), findsOneWidget);
      _expectSameLayout(first, _visibleLayout(tester));
    },
  );

  testWidgets('hidden goto target adds no late expansion entry', (
    tester,
  ) async {
    final blocks = UserBlockIndex.forTesting(null);
    addTearDown(blocks.dispose);
    await blocks.block(uid: '11', name: '样例作者11');
    final initial = Completer<ThreadDetail>();
    final next = Completer<ThreadDetail>();
    await _push(
      tester,
      ThreadDetailPage(
        tid: _tid,
        title: '离线定位',
        gotoUrl: 'https://example.invalid/?goto=findpost&pid=11',
        focusPid: 11,
        blockIndex: blocks,
        preloadPages: 1,
        loadGoto: (_) => initial.future,
        loadPage: (_, _, _) => next.future,
      ),
    );
    initial.complete(
      _page([_post(10), _post(11, replyTo: 10)], number: 2, next: true),
    );
    await _pumpFirstContent(tester);
    final first = _visibleLayout(tester, includeTail: false);
    expect(first.cards, [(10, false)]);
    expect(first.entryLabels, isEmpty);
    expect(first.counts, [(1, null, false)]);
    // The continuation can start loading while the hidden-target notice is
    // shown. Its pending data cannot change the current conversation.
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(_frame);
    }
    _expectSameLayout(first, _visibleLayout(tester, includeTail: false));
    expect(find.text('该楼层已被黑名单隐藏'), findsOneWidget);
  });

  testWidgets('block revision during worker parse reaches the first viewport', (
    tester,
  ) async {
    final blocks = UserBlockIndex.forTesting(null);
    addTearDown(blocks.dispose);
    await blocks.block(uid: '3', name: '样例作者3');
    final fetcher = _Fixture(_parserFixture());
    Future<void> Function()? runHeldParse;
    Future<R> dispatch<M, R>(ComputeCallback<M, R> callback, M input) async {
      if (input is GetPageInput) return callback(input);
      final result = Completer<R>();
      runHeldParse = () async {
        await tester.runAsync(() async {
          final entered = ReceivePort();
          final pending = dispatchParserInWorker(_holdWorker<M, R>, (
            callback,
            input,
            entered.sendPort,
          ));
          final release = (await entered.first) as SendPort;
          final revision = blocks.visibilityRevision;
          await blocks.block(uid: '2', name: '样例作者2');
          await blocks.unblock('3');
          expect(blocks.visibilityRevision, greaterThan(revision));
          release.send(null);
          result.complete(await pending);
        });
      };
      return result.future;
    }

    final repo = ForumRepository(
      ChhClient(
        fetchers: [fetcher],
        dispatchParser: dispatch,
        threadRequestInterval: Duration.zero,
      ),
    );
    await _push(
      tester,
      ThreadDetailPage(
        tid: _tid,
        title: '离线帖子',
        preloadPages: 1,
        blockIndex: blocks,
        repository: repo,
      ),
    );
    await tester.pump(const Duration(milliseconds: 8));
    expect(runHeldParse, isNotNull);
    expect(_cards, findsNothing);
    await runHeldParse!();
    await _pumpFirstContent(tester);
    final state = tester.state(_reader) as dynamic;
    expect(state.debugConversationIndex.rootPidFor(3), 2);
    expect(state.debugConversationIndex.rootPidFor(4), 2);
    final first = _visibleLayout(tester);
    expect(first.cards, [(1, false)]);
    expect(first.entryLabels, ['展开 2 条回复']);
    expect(first.counts, [(2, null, false)]);
    expect(find.text('已屏蔽用户的发言'), findsOneWidget);
    expect(find.text('离线正文2'), findsNothing);
    await tester.pumpAndSettle(_frame);
    _expectSameLayout(first, _visibleLayout(tester));
    expect(fetcher.requests, 1);
  });

  for (final goto in [
    null,
    'https://www.chiphell.com/forum.php?goto=findpost',
  ]) {
    testWidgets(
      'cached detail paints on its first frame goto=${goto != null}',
      (tester) async {
        final fetcher = _Fixture();
        final repo = ForumRepository(
          ChhClient(
            fetchers: [fetcher],
            dispatchParser: parseForumInline,
            threadRequestInterval: Duration.zero,
          ),
        );
        if (goto == null) {
          await repo.thread(_tid);
        } else {
          await repo.threadAtUrl(goto, tid: _tid);
        }
        final route = await _push(
          tester,
          ThreadDetailPage(
            tid: _tid,
            title: '离线帖子',
            repository: repo,
            gotoUrl: goto,
            preloadPages: 1,
          ),
        );
        expect(route.animation!.isAnimating || route.offstage, isTrue);
        expect(_cards, findsWidgets);
        final reveal = tester.widget<ExpressivePageReveal>(
          find.descendant(
            of: _reader,
            matching: find.byType(ExpressivePageReveal, skipOffstage: false),
            skipOffstage: false,
          ),
        );
        expect(reveal.active, isTrue);
        expect(reveal.animateOnMount, isFalse);
        expect(fetcher.requests, 1);
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('popping a route discards its held detail', (tester) async {
    final result = Completer<ThreadDetail>();
    final prepared = <int>{};
    final route = await _push(tester, _cold(result));
    await tester.pump(const Duration(milliseconds: 80));
    result.complete(_detail(prepared));
    await tester.pump(_frame);
    route.navigator!.pop();
    await tester.pumpAndSettle(_frame);
    expect(_reader, findsNothing);
    expect(prepared, isEmpty);
  });
}
