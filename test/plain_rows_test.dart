import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/forum_tokens.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: child),
);

ThreadSummary thread(int tid, {bool sticky = false}) => ThreadSummary(
  tid: tid,
  title: sticky ? '置顶公告 $tid' : '普通帖子 $tid',
  author: '测试主题作者',
  replies: 22,
  views: 1558,
  sticky: sticky,
  typeName: '电脑讨论(新)',
);

Widget list({required List<ThreadSummary> items, Object? memory, Key? key}) =>
    app(
      BrowseThreadList(
        key: key,
        collapsePinned: true,
        pinnedMemoryKey: memory,
        loader: (page, {bool refresh = false}) async => Paged(
          items: items,
          page: const PageInfo(current: 1, hasNext: false),
        ),
        itemBuilder: (context, t) => ThreadRow(thread: t, onTap: () {}),
      ),
    );

final pinnedAndNormal = [
  for (var i = 1; i <= 5; i++) thread(i, sticky: true),
  for (var i = 6; i <= 8; i++) thread(i),
];

void main() {
  testWidgets('notice unread dot shrinks away without removing row actions', (
    tester,
  ) async {
    var taps = 0;
    Widget row(bool unread) => app(
      NoticeRow(
        avatar: const SizedBox.square(dimension: 44),
        name: 'Alice',
        time: '10:00',
        text: 'hello',
        unread: unread,
        onTap: () => taps++,
      ),
    );
    await tester.pumpWidget(row(true));
    await tester.pumpAndSettle();
    expect(find.byKey(NoticeRow.unreadDotKey), findsOneWidget);
    await tester.pumpWidget(row(false));
    expect(find.byKey(NoticeRow.unreadDotKey), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(NoticeRow.unreadDotKey), findsNothing);
    await tester.tap(find.textContaining('Alice', findRichText: true));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('thread row shows category, avatar and inline reply count', (
    tester,
  ) async {
    await tester.pumpWidget(app(ThreadRow(thread: thread(1), onTap: () {})));
    expect(find.textContaining('·'), findsNothing);
    expect(find.byIcon(AppIcons.comments), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    expect(find.text('回复'), findsNothing);
    expect(find.text('电脑讨论'), findsOneWidget);
    expect(find.text('电脑讨论(新)'), findsNothing);
    expect(find.text('测试主题作者'), findsOneWidget);
    expect(tester.widget<PlainRow>(find.byType(PlainRow)).verticalPadding, 12);
    expect(
      tester.getSize(find.byKey(const ValueKey('thread-avatar-1'))).width,
      16,
    );
  });

  testWidgets('zero replies hide icon and count; account rows omit author', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        ThreadRow.entry(
          tid: 33,
          title: '我的帖子',
          category: '电脑讨论（新）',
          timeRaw: '无法解析的时间',
          replies: 0,
        ),
      ),
    );
    expect(find.byIcon(AppIcons.comments), findsNothing);
    expect(find.byKey(const ValueKey('thread-count-33')), findsNothing);
    expect(find.byKey(const ValueKey('thread-avatar-33')), findsNothing);
    expect(find.text('电脑讨论'), findsOneWidget);
    expect(find.text('无法解析的时间'), findsOneWidget);
  });

  testWidgets('forum and community rows differ only in board metadata', (
    tester,
  ) async {
    const summary = ThreadSummary(
      tid: 9,
      title: '同一个帖子',
      author: '同一作者',
      forumName: '这个版块名字很长这个版块名字很长这个版块名字很长(新)',
      hasImages: true,
      replies: 18,
      views: 1,
    );
    const board = '这个版块名字很长这个版块名字很长这个版块名字很长';
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        const Column(
          children: [
            ThreadRow(
              key: ValueKey('local-forum'),
              thread: summary,
              showCategory: false,
              forumStyle: true,
              timeLabel: '昨天 12:34',
            ),
            ThreadRow(
              key: ValueKey('community'),
              thread: summary,
              timeLabel: '昨天 12:34',
            ),
          ],
        ),
      ),
    );

    Finder inRow(String row, Finder item) =>
        find.descendant(of: find.byKey(ValueKey(row)), matching: item);
    expect(inRow('local-forum', find.text(board)), findsNothing);
    final communityBoard = inRow('community', find.text(board));
    expect(tester.widget<Text>(communityBoard).maxLines, 1);
    expect(tester.widget<Text>(communityBoard).overflow, TextOverflow.ellipsis);
    final time = inRow('community', find.text('昨天 12:34'));
    expect(tester.widget<Text>(time).maxLines, 1);
    expect(
      tester.getCenter(time).dy,
      closeTo(tester.getCenter(communityBoard).dy, .01),
    );
    expect(find.byIcon(AppIcons.image), findsNWidgets(2));
    expect(find.text('18'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('time follows a short author with a ten dp gap', (tester) async {
    await tester.pumpWidget(
      app(
        const ThreadRow(
          thread: ThreadSummary(
            tid: 88,
            title: '测试',
            author: '作者',
            replies: 3,
            views: 1,
          ),
          timeLabel: '12:34',
        ),
      ),
    );
    final author = tester.getRect(find.text('作者'));
    final time = tester.getRect(find.text('12:34'));
    expect(time.left - author.right, closeTo(10, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short and long titles take exactly one line', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        Column(
          children: [
            ThreadRow(thread: thread(1), timeLabel: '12:34'),
            const ThreadRow(
              thread: ThreadSummary(
                tid: 2,
                title: '非常长的帖子标题反复出现直到占据第二行并以省略号结束非常长的帖子标题',
                author: '另一位作者',
                replies: 1,
                views: 1,
                typeName: '讨论',
              ),
              timeLabel: '12:35',
              showCategory: false,
            ),
          ],
        ),
      ),
    );
    final first = tester.getRect(find.byType(ThreadRow).first);
    final second = tester.getRect(find.byType(ThreadRow).last);
    expect(second.height, closeTo(first.height, .01));
    final titles = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ThreadRow),
            matching: find.byType(Text),
          ),
        )
        .where(
          (text) =>
              text.data == thread(1).title ||
              text.data?.startsWith('非常长的帖子标题') == true,
        );
    expect(titles.every((text) => text.maxLines == 1), isTrue);
    expect(first.height, lessThan(78));
    expect(
      find.textContaining('讨论', findRichText: true),
      findsOneWidget,
    ); // first row category only
    expect(find.text('12:34'), findsOneWidget);
    expect(find.text('12:35'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow large type row preserves image semantics, excerpt and full counts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: const ThreadRow(
                    thread: ThreadSummary(
                      tid: 9,
                      title: '大字号测试标题',
                      author: '很长的作者名',
                      replies: 123456,
                      views: 1,
                      hasImages: true,
                      typeName: '很长的分类名称',
                    ),
                    excerpt: '原有摘要继续可见',
                    timeLabel: '昨天 12:00',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('原有摘要继续可见'), findsOneWidget);
      expect(find.byIcon(AppIcons.image), findsOneWidget);
      expect(find.bySemanticsLabel('含图'), findsOneWidget);
      expect(find.bySemanticsLabel('123456 回复'), findsOneWidget);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collapsed pinned header previews its first title without building rows',
    (tester) async {
      var built = 0;
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.topCenter,
            child: PinnedGroupRow(
              count: 4,
              firstTitle: '论坛发帖须知',
              expanded: false,
              onToggle: () {},
              itemBuilder: (_, i) {
                built++;
                return Text('展开$i');
              },
            ),
          ),
        ),
      );
      expect(find.text('论坛发帖须知'), findsOneWidget);
      expect(find.text('4 条'), findsOneWidget);
      expect(built, 0);
      expect(
        tester.getSize(find.byType(PinnedGroupRow)).height,
        AppSizes.singleLineHeight + 2 * ForumTokens.groupInset,
      );
    },
  );

  testWidgets('leading sticky threads collapse into one pinned row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(list(items: pinnedAndNormal));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedGroupRow), findsOneWidget);
    expect(find.text('5 条'), findsOneWidget);
    expect(find.byType(ThreadRow), findsNWidgets(3));
    final firstRow = tester.widget<ThreadRow>(find.byType(ThreadRow).first);
    expect(firstRow.thread.tid, 6);

    await tester.tap(find.byType(PinnedGroupRow));
    await tester.pumpAndSettle();
    expect(find.byType(ThreadRow), findsNWidgets(8));
  });

  testWidgets('expanded pinned threads sit inside the lightweight card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(list(items: pinnedAndNormal));
    await tester.pumpAndSettle();
    final collapsed = tester.getSize(find.byType(PinnedGroupRow)).height;

    await tester.tap(find.text('置顶'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // 展开途中卡片在长高,置顶帖已在卡片内
    final midway = tester.getSize(find.byType(PinnedGroupRow)).height;
    expect(midway, greaterThan(collapsed));
    await tester.pumpAndSettle();
    final card = find.byType(PinnedGroupRow);
    expect(
      find.descendant(of: card, matching: find.byType(ThreadRow)),
      findsNWidgets(5),
    );
    expect(tester.getSize(card).height, greaterThan(midway));
    // 卡片标题已说明是置顶,行内不再重复"置顶"
    expect(
      find.descendant(of: card, matching: find.text('置顶')),
      findsOneWidget,
    );
    final cardRect = tester.getRect(card);
    final firstPinned = tester.getRect(
      find.descendant(of: card, matching: find.byType(ThreadRow)).first,
    );
    expect(firstPinned.left, greaterThanOrEqualTo(cardRect.left));
    expect(firstPinned.right, lessThanOrEqualTo(cardRect.right));

    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, collapsed);
    expect(
      find.descendant(of: card, matching: find.byType(ThreadRow)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no pinned row without sticky threads', (tester) async {
    await tester.pumpWidget(list(items: [thread(1), thread(2)]));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedGroupRow), findsNothing);
    expect(find.byType(ThreadRow), findsNWidgets(2));
  });

  testWidgets('pinned expansion is remembered for the same forum', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      list(items: pinnedAndNormal, memory: 'fid-7', key: const ValueKey(1)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PinnedGroupRow));
    await tester.pumpAndSettle();
    expect(find.byType(ThreadRow), findsNWidgets(8));

    await tester.pumpWidget(
      list(items: pinnedAndNormal, memory: 'fid-7', key: const ValueKey(2)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ThreadRow), findsNWidgets(8));

    await tester.pumpWidget(
      list(items: pinnedAndNormal, memory: 'fid-8', key: const ValueKey(3)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ThreadRow), findsNWidgets(3));
  });

  testWidgets('locked rows offer login', (tester) async {
    var logins = 0;
    await tester.pumpWidget(
      app(ThreadRow(thread: thread(1), locked: true, onLogin: () => logins++)),
    );
    expect(find.text('需登录'), findsOneWidget);
    await tester.tap(find.text('登录'));
    expect(logins, 1);
  });
}
