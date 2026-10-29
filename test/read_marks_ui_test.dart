import 'package:chh_app/data/space_repository.dart';
import 'package:chh_app/data/thread_read_index.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/my_threads_page.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/widgets/search_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: child),
);

ThreadSummary thread(int tid, {int replies = 10, String title = '散热器评测'}) =>
    ThreadSummary(
      tid: tid,
      title: title,
      author: '作者',
      replies: replies,
      views: 100,
    );

AppTokens tokensOf(WidgetTester tester) =>
    AppTokens.of(tester.element(find.byType(Scaffold)));

TextStyle? styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style;

void main() {
  testWidgets('未看过:标题强色,无新回复文字', (tester) async {
    await tester.pumpWidget(app(ThreadRow(thread: thread(1))));
    expect(styleOf(tester, '散热器评测')!.color, tokensOf(tester).text);
    expect(find.textContaining('新回复'), findsNothing);
  });

  testWidgets('已看:标题降为 text2,元信息不变', (tester) async {
    await tester.pumpWidget(
      app(ThreadRow(thread: thread(1), readState: const ThreadReadSeen())),
    );
    expect(styleOf(tester, '散热器评测')!.color, tokensOf(tester).text2);
    expect(find.textContaining('新回复'), findsNothing);
    expect(find.text('10 回复'), findsOneWidget);
  });

  testWidgets('有新回复:标题回强色且元信息行出现 +3 新回复', (tester) async {
    await tester.pumpWidget(
      app(
        ThreadRow(thread: thread(1), readState: const ThreadReadNewReplies(3)),
      ),
    );
    final t = tokensOf(tester);
    expect(styleOf(tester, '散热器评测')!.color, t.text);
    expect(find.text('+3 新回复'), findsOneWidget);
    expect(styleOf(tester, '+3 新回复')!.color, t.accent);
    // 仍无分隔符与图标
    expect(find.textContaining('·'), findsNothing);
    expect(
      find.descendant(of: find.byType(ThreadRow), matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets('语义标签显式带出已看与新回复数,颜色不是唯一线索', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        Column(
          children: [
            ThreadRow(thread: thread(1), readState: const ThreadReadSeen()),
            ThreadRow(
              thread: thread(2),
              readState: const ThreadReadNewReplies(3),
            ),
            ThreadRow(thread: thread(3)),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('已看')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('有 3 条新回复')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('320dp + 2 倍字号下 +N 新回复不撑破元信息行', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ThreadRow(
            thread: thread(1),
            readState: const ThreadReadNewReplies(123),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.text('+123 新回复'));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
  });

  testWidgets('搜索行置灰后关键词高亮仍可辨', (tester) async {
    await tester.pumpWidget(
      app(
        SearchResultRow(
          title: '风冷散热器评测',
          query: '散热',
          meta: const ['版块'],
          readState: const ThreadReadSeen(),
        ),
      ),
    );
    final t = tokensOf(tester);
    final rich = tester.widget<RichText>(
      find.descendant(
        of: find.byType(SearchResultRow),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == '风冷散热器评测',
        ),
      ),
    );
    final root = rich.text as TextSpan;
    // 基础色挂在 Text 的样式上,高亮段自带 accent
    final spans = <TextSpan>[];
    root.visitChildren((span) {
      if (span is TextSpan) spans.add(span);
      return true;
    });
    final hit = spans.firstWhere((s) => s.text == '散热');
    expect(root.style!.color, t.text2);
    expect(hit.style!.color, t.accent);
    expect(hit.style!.color, isNot(root.style!.color));
  });

  testWidgets('SearchResultCard 随 threadReadIndex 变色', (tester) async {
    await tester.pumpWidget(
      app(
        SearchResultCard(
          thread: thread(7, replies: 4),
          keyword: '散热',
          onTap: () {},
        ),
      ),
    );
    expect(find.textContaining('新回复'), findsNothing);
    threadReadIndex.markRead(7, 1);
    await tester.pump();
    expect(find.text('+3 新回复'), findsOneWidget);
  });

  testWidgets('我的主题:replies 为 null 只分已看/未看,有数值才追加 +N 新回复', (tester) async {
    // 全局索引跨用例保留,这里用独占 tid 避免串扰
    threadReadIndex.markRead(9001, 5);
    threadReadIndex.markRead(9002, 5);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: MyThreadsPage(repository: _FakeSpace()),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTokens.of(tester.element(find.byType(Scaffold).first));
    // replies 为 null:已看降色,绝不出现 +0 新回复
    expect(tester.widget<Text>(find.text('未知回复数')).style!.color, t.text2);
    // replies 8 对 5:新回复 +3,标题保持强色
    expect(find.text('+3 新回复'), findsOneWidget);
    expect(find.textContaining('新回复'), findsOneWidget);
    expect(tester.widget<Text>(find.text('回复变多的帖')).style!.color, t.text);
    expect(styleOf(tester, '+3 新回复')!.color, t.accent);
  });

  /// 30 行列表,每行记录 builder 调用次数;回复数统一为 10
  Future<Map<int, int>> pumpRows(WidgetTester tester, int base) async {
    tester.view.physicalSize = const Size(400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final builds = <int, int>{};
    await tester.pumpWidget(
      app(
        ListView.builder(
          itemCount: 30,
          itemBuilder: (context, i) => ReadStateBuilder(
            tid: base + i,
            replies: 10,
            builder: (context, state) {
              builds[i] = (builds[i] ?? 0) + 1;
              return ThreadRow(
                thread: thread(base + i, replies: 10),
                readState: state,
              );
            },
          ),
        ),
      ),
    );
    expect(builds.length, 30);
    return builds;
  }

  List<int> changedRows(Map<int, int> builds, Map<int, int> before) => [
    for (final e in builds.entries)
      if (e.value != before[e.key]) e.key,
  ];

  testWidgets('markRead 只重建对应行,不重建整个列表', (tester) async {
    final builds = await pumpRows(tester, 1000);
    final before = Map<int, int>.of(builds);

    threadReadIndex.markRead(1012, 10);
    await tester.pump();

    expect(changedRows(builds, before), [12]);
    expect(builds[12], before[12]! + 1);
  });

  testWidgets('新回复数变化会重建该行;别的行更新时它不重建', (tester) async {
    final builds = await pumpRows(tester, 2000);
    threadReadIndex.markRead(2005, 7); // 未看 -> 新回复 3
    await tester.pump();
    expect(find.text('+3 新回复'), findsOneWidget);

    // 同为新回复但数量变了:走 count 比较,必须重建
    var before = Map<int, int>.of(builds);
    threadReadIndex.markRead(2005, 6); // 新回复 4
    await tester.pump();
    expect(find.text('+4 新回复'), findsOneWidget);
    expect(changedRows(builds, before), [5]);

    // 另一行变化时,数量未变的这一行不重建
    before = Map<int, int>.of(builds);
    threadReadIndex.markRead(2006, 10);
    await tester.pump();
    expect(changedRows(builds, before), [6]);
  });
}

class _FakeSpace extends SpaceRepository {
  _FakeSpace() : super(ChhClient(fetchers: []));

  @override
  Future<Paged<MyThread>> threads({
    String? uid,
    String view = 'me',
    String? type,
    String? filter,
    int page = 1,
    bool refresh = false,
  }) async => const Paged(
    page: PageInfo(current: 1, hasNext: false),
    items: [
      MyThread(tid: 9001, title: '未知回复数'),
      MyThread(tid: 9002, title: '回复变多的帖', replies: 8),
    ],
  );
}
