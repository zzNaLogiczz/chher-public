import 'package:chh_app/design/theme.dart';
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
  testWidgets('thread row meta uses spacing, no separator dots or icons', (
    tester,
  ) async {
    await tester.pumpWidget(app(ThreadRow(thread: thread(1), onTap: () {})));
    expect(find.textContaining('·'), findsNothing);
    expect(
      find.descendant(of: find.byType(ThreadRow), matching: find.byType(Icon)),
      findsNothing,
    );
    expect(find.text('22 回复'), findsOneWidget);
    expect(find.text('电脑讨论(新)'), findsOneWidget);
    expect(find.text('测试主题作者'), findsOneWidget);
  });

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

  testWidgets('expanded pinned threads sit inside the grey card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(list(items: pinnedAndNormal));
    await tester.pumpAndSettle();
    final collapsed = tester.getSize(find.byType(PinnedGroupRow)).height;

    await tester.tap(find.text('置顶帖'));
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
    expect(find.descendant(of: card, matching: find.text('置顶')), findsNothing);
    final cardRect = tester.getRect(card);
    final firstPinned = tester.getRect(
      find.descendant(of: card, matching: find.byType(ThreadRow)).first,
    );
    expect(firstPinned.left, greaterThanOrEqualTo(cardRect.left));
    expect(firstPinned.right, lessThanOrEqualTo(cardRect.right));

    await tester.tap(find.text('置顶帖'));
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
