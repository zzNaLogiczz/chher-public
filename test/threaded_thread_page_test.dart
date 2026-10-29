import 'dart:async';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post post(
  int n, {
  int? target,
  bool long = false,
  bool unknown = false,
  String? uid,
}) => Post(
  pid: n,
  floor: n,
  author: '用户$n',
  authorUid: uid ?? '$n',
  timeRaw: '10:00',
  content: [
    if (target != null || unknown)
      QuoteBlock(
        const [TextBlock('保留的原始引用')],
        source: '引用署名',
        reference: target == null
            ? null
            : PostReference(
                tid: 123,
                pid: target,
                url:
                    'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=123&pid=$target',
              ),
      ),
    TextBlock(long ? List.filled(28, '正文$n，连续阅读内容。').join('\n') : '正文$n'),
  ],
);
ThreadDetail page(List<Post> posts, {int n = 1, bool more = false}) =>
    ThreadDetail(
      tid: 123,
      fid: 290,
      title: '示例讨论',
      posts: posts,
      page: PageInfo(current: n, hasNext: more),
    );
Future<void> pump(WidgetTester tester, ThreadDetailPage child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(Brightness.light), home: child),
  );
  await tester.pumpAndSettle();
}

Future<void> bottom(WidgetTester tester) async {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  for (var n = 0; n < 10; n++) {
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    if (position.extentAfter < 1) break;
  }
}

Finder card(int pid) =>
    find.byWidgetPredicate((w) => w is PostCard && w.post.pid == pid);

Future<void> tapViewMode(WidgetTester tester, String label) async {
  final segment = find.descendant(
    of: find.byType(AppSegmented<ThreadViewMode>),
    matching: find.text(label),
  );
  await tester.ensureVisible(segment);
  await tester.pump();
  await tester.tap(segment);
}

Future<ThreadViewMode> currentViewMode(WidgetTester tester) async {
  final segmented = find.byType(AppSegmented<ThreadViewMode>);
  await tester.scrollUntilVisible(
    segmented,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  return tester.widget<AppSegmented<ThreadViewMode>>(segmented).value;
}

void main() {
  testWidgets('a deep reply expands inline and quotes its own PID on send', (
    tester,
  ) async {
    final sent = <int?>[];
    final data = page([
      post(1),
      post(2),
      post(3, target: 2),
      post(4, target: 3),
      post(5, unknown: true),
    ]);
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '示例讨论',
        loadPage: (_, _, _) async => data,
        submitReply:
            ({
              required tid,
              required fid,
              required message,
              quotePid,
              page = 1,
            }) async {
              sent.add(quotePid);
              return const PostResult(PostResultKind.success, '成功');
            },
      ),
    );
    await bottom(tester);
    expect(card(3), findsNothing);
    expect(card(4), findsNothing);
    expect(card(5), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('展开 2 条回复'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('展开 2 条回复'));
    await tester.pumpAndSettle();
    final reply = find.byKey(const ValueKey('comment-reply-4'));
    for (var n = 0; n < 12 && reply.hitTestable().evaluate().isEmpty; n++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -140));
      await tester.pumpAndSettle();
    }
    expect(reply.hitTestable(), findsOneWidget);
    await tester.tap(reply.hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(ComposerSheet), findsOneWidget);
    await tester.enterText(find.byType(TextField), '本地模拟回复');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(sent, [4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification of a grouped child opens and locates that child', (
    tester,
  ) async {
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '通知',
        focusPid: 4,
        gotoUrl: 'fake://goto',
        loadGoto: (_) async =>
            page([post(1), post(2), post(3, target: 2), post(4, target: 3)]),
        loadPage: (_, _, _) async => throw StateError('Must use supplied goto'),
      ),
    );
    expect(find.text('回复 用户3：正文4').hitTestable(), findsOneWidget);
    expect(find.text('回复 用户3：正文4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raw floor mode restores every post including grouped replies', (
    tester,
  ) async {
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '模式',
        loadPage: (_, _, _) async =>
            page([post(1), post(2), post(3, target: 2), post(4, target: 3)]),
      ),
    );
    await tapViewMode(tester, '原楼层');
    await tester.pumpAndSettle();
    await bottom(tester);
    expect(card(3), findsWidgets);
    expect(card(4), findsWidgets);
    expect(find.text('正文4'), findsOneWidget);
    expect(find.text('保留的原始引用'), findsNothing);
    expect(find.byType(ThreadReplyContext), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raw long reply keeps its jump context without a second quote', (
    tester,
  ) async {
    final reply = Post(
      pid: 3,
      floor: 3,
      author: '用户3',
      timeRaw: '10:00',
      content: [
        ...post(3, target: 2).content,
        for (var i = 0; i < 13; i++) TextBlock('长回复段落 $i'),
      ],
    );
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '长回复',
        initialThreaded: false,
        loadPage: (_, _, _) async => page([post(1), post(2), reply]),
      ),
    );
    final context = find.byKey(const ValueKey('thread-reply-context-123-2'));
    await tester.scrollUntilVisible(
      context,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('保留的原始引用'), findsNothing);
    expect(find.text('正文3'), findsOneWidget);
    await tester.tap(context);
    await tester.pumpAndSettle();
    expect(find.text('正文2').hitTestable(), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raw unlinked quotation remains readable', (tester) async {
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '未关联引文',
        initialThreaded: false,
        loadPage: (_, _, _) async => page([post(1), post(2, unknown: true)]),
      ),
    );
    await bottom(tester);
    expect(find.text('保留的原始引用'), findsOneWidget);
    expect(find.byType(ThreadReplyContext), findsNothing);
  });

  testWidgets(
    'a page containing only grouped children never drains further pages automatically',
    (tester) async {
      final reads = <int>[];
      await pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '增量',
          loadPage: (n, _, _) async {
            reads.add(n);
            return n == 1
                ? page([post(1, long: true), post(2, long: true)], more: true)
                : page([post(n + 1, target: 2)], n: n, more: n < 10);
          },
        ),
      );
      expect(reads, [1]);
      await bottom(tester);
      expect(reads, [1, 2]);
      await tester.pumpAndSettle();
      expect(reads, [1, 2]);
      await tester.drag(find.byType(ListView).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(reads, [1, 2, 3]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'only-author reading keeps the authors continuation and normal replies in source order',
    (tester) async {
      final reads = <String?>[];
      final opening = post(1, uid: 'owner');
      final continuation = post(2, uid: 'owner');
      final normalReply = post(4, target: 2, uid: 'owner');
      await pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '楼主续篇',
          loadPage: (_, author, _) async {
            reads.add(author);
            return page([
              opening,
              continuation,
              if (author == null) post(3, target: 2),
              normalReply,
            ]);
          },
        ),
      );
      await tapViewMode(tester, '只看楼主');
      await tester.pumpAndSettle();
      await bottom(tester);
      expect(reads, [null, 'owner']);
      expect(card(2), findsWidgets);
      expect(card(4), findsWidgets);
      expect(card(3), findsNothing);
      expect(find.text('正文4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('new mode choice cancels a pending opening-author lookup', (
    tester,
  ) async {
    final first = Completer<ThreadDetail>();
    final reads = <(int, String?)>[];
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '中段',
        initialPage: 4,
        initialThreaded: false,
        loadPage: (n, author, _) async {
          reads.add((n, author));
          return n == 1 ? first.future : page([post(40)], n: n);
        },
      ),
    );
    await tapViewMode(tester, '只看楼主');
    await tester.pump();
    await tapViewMode(tester, '评论');
    await tester.pump();
    first.complete(page([post(1, uid: 'owner')]));
    await tester.pumpAndSettle();
    expect(reads, [(4, null), (1, null)]);
    expect(await currentViewMode(tester), ThreadViewMode.threaded);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching view mode keeps the comment heading where it was', (
    tester,
  ) async {
    final opening = post(1, long: true, uid: 'owner');
    final all = page([
      opening,
      post(2),
      post(3, target: 2),
      post(4, uid: 'owner'),
      post(5),
      post(6),
    ]);
    final reads = <String?>[];
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '示例讨论',
        loadPage: (_, author, _) async {
          reads.add(author);
          return author == null ? all : page([opening, post(4, uid: 'owner')]);
        },
      ),
    );
    final heading = find.byType(ThreadCommentHeading);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(heading, 300, scrollable: scrollable);
    final position = tester.state<ScrollableState>(scrollable).position;
    // 标题停在屏幕中部:切换前已经向下读过首楼
    position.jumpTo(position.pixels + tester.getTopLeft(heading).dy - 420);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    Future<void> switchTo(String label, ThreadViewMode mode) async {
      final before = tester.getTopLeft(heading).dy;
      await tester.tap(
        find.descendant(
          of: find.byType(AppSegmented<ThreadViewMode>),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(heading).dy, closeTo(before, 1), reason: label);
      expect(
        tester
            .widget<AppSegmented<ThreadViewMode>>(
              find.byType(AppSegmented<ThreadViewMode>),
            )
            .value,
        mode,
      );
    }

    await switchTo('原楼层', ThreadViewMode.floors);
    expect(card(3), findsWidgets);
    // 只看楼主内容不足一屏,标题仍停在原处
    await switchTo('只看楼主', ThreadViewMode.author);
    expect(card(2), findsNothing);
    expect(card(4), findsWidgets);
    // 退出只看楼主还原已读楼层,不重新读取
    await switchTo('评论', ThreadViewMode.threaded);
    expect(reads, [null, 'owner']);
    expect(card(2), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('author mode shows progress, and a failed read changes nothing', (
    tester,
  ) async {
    final author = Completer<ThreadDetail>();
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '示例讨论',
        loadPage: (_, uid, _) async =>
            uid == null ? page([post(1), post(2), post(3)]) : author.future,
      ),
    );
    await tapViewMode(tester, '只看楼主');
    await tester.pump();
    final heading = tester.widget<ThreadCommentHeading>(
      find.byType(ThreadCommentHeading),
    );
    // 控件先选中目标并显示等待,旧评论仍在
    expect(heading.mode, ThreadViewMode.author);
    expect(heading.busy, isTrue);
    expect(card(2), findsWidgets);

    author.completeError(Exception('offline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('暂时无法读取楼主的楼层，请稍后重试'), findsOneWidget);
    final reverted = tester.widget<ThreadCommentHeading>(
      find.byType(ThreadCommentHeading),
    );
    expect(reverted.mode, ThreadViewMode.threaded);
    expect(reverted.busy, isFalse);
    expect(card(2), findsWidgets);
    expect(card(3), findsWidgets);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('one inline expansion reads at most one sparse source page', (
    tester,
  ) async {
    final reads = <int>[];
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '按需读取',
        loadPage: (n, _, _) async {
          reads.add(n);
          if (n == 1) {
            return page([
              post(1, long: true),
              post(2),
              post(3, target: 2),
            ], more: true);
          }
          return page([post(10 + n, long: true)], n: n, more: true);
        },
      ),
    );
    final action = find.byKey(const ValueKey('thread-expand-replies-2'));
    await tester.scrollUntilVisible(
      action,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final before = reads.length;
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(reads.length, before + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replying to an early floor revalidates the last loaded page and loaded counts',
    (tester) async {
      final reads = <(int, bool)>[];
      var sent = false;
      await pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '提交后续载',
          initialThreaded: false,
          loadPage: (n, _, refresh) async {
            reads.add((n, refresh));
            if (n == 1) return page([post(1), post(2)], more: true);
            return page([post(n + 2)], n: n, more: n < 3 || (sent && n == 3));
          },
          submitReply:
              ({
                required tid,
                required fid,
                required message,
                quotePid,
                page = 1,
              }) async {
                expect(quotePid, 2);
                expect(page, 1);
                sent = true;
                return const PostResult(PostResultKind.success, '成功');
              },
        ),
      );
      await bottom(tester);
      expect(reads, contains((3, false)));
      await tester.scrollUntilVisible(
        find.text('回复 #2'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('回复 #2'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '本地模拟');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(reads, containsAll([(1, true), (3, true)]));
      expect(sent, isTrue);
      await tester.scrollUntilVisible(
        find.byType(ThreadCommentHeading),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<ThreadCommentHeading>(find.byType(ThreadCommentHeading))
            .complete,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account identity change empties the old conversation before reloading',
    (tester) async {
      final oldLoggedIn = chhSession.loggedIn;
      final oldBadges = chhSession.badges;
      addTearDown(() {
        chhSession.loggedIn = oldLoggedIn;
        chhSession.badges = oldBadges;
      });
      chhSession.loggedIn = true;
      chhSession.badges = const HeaderBadges(
        notices: 0,
        messages: 0,
        uid: '111',
        userName: 'A',
      );
      final reload = Completer<ThreadDetail>();
      var calls = 0;
      await pump(
        tester,
        ThreadDetailPage(
          tid: 123,
          title: '账号隔离',
          loadPage: (_, _, _) async {
            if (++calls > 1) return reload.future;
            return page([post(1), post(2), post(3, target: 2)]);
          },
        ),
      );
      await bottom(tester);
      await tester.tap(find.text('展开 1 条回复'));
      await tester.pumpAndSettle();
      chhSession.observeHtml(
        '<div id="um"><strong class="vwmy"><a href="space-uid-222.html">B</a></strong></div>',
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('正文2'), findsNothing);
      expect(find.text('正文3'), findsNothing);
      reload.complete(page([post(1), post(9)]));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(1));
      expect(find.text('正文2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inline retry reaches the page reader after an append error', (
    tester,
  ) async {
    final reads = <int>[];
    var attempts = 0;
    await pump(
      tester,
      ThreadDetailPage(
        tid: 123,
        title: '重试',
        loadPage: (n, _, _) async {
          reads.add(n);
          if (n == 1) {
            return page([
              post(1, long: true),
              post(2),
              post(3, target: 2),
            ], more: true);
          }
          if (attempts++ == 0) throw StateError('offline');
          return page([post(4, target: 2)], n: 2);
        },
      ),
    );
    await bottom(tester);
    expect(reads, [1, 2]);
    final retry = find.byKey(const ValueKey('thread-expand-replies-2'));
    await tester.scrollUntilVisible(
      retry,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(reads, [1, 2, 2]);
    expect(find.text('后续回复暂时没有加载出来'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
