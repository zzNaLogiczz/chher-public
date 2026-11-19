import 'dart:async';
import 'package:chh_app/design/list_end_tokens.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:chh_app/widgets/search_workspace.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadSummary _thread(int id, {String? title, String? snippet}) =>
    ThreadSummary(
      tid: id,
      title: title ?? '搜索结果 $id',
      author: 'reader',
      replies: id,
      views: 22,
      createdAtRaw: '2020-10-18 12:00',
      forumName: '电脑讨论',
      forumFid: 146,
      snippet: snippet,
    );
SearchResultPage _result(
  List<ThreadSummary> rows, {
  int page = 1,
  String? next,
}) => SearchResultPage(
  rows: rows,
  page: PageInfo(current: page, hasNext: next != null),
  nextUrl: next,
);
Widget _app(Widget page, {double scale = 1}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);
Future<void> _phone(WidgetTester tester, {double width = 390}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _submit(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

void main() {
  setUp(searchSessionHistory.clear);
  tearDown(searchSessionHistory.clear);

  for (final (bottomInset, sparse) in [(0.0, false), (34.0, true)]) {
    testWidgets(
      'search result end respects the marker gap and inset $bottomInset',
      (tester) async {
        await _phone(tester);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(bottom: bottomInset);
        tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await tester.pumpWidget(
          _app(
            SearchPage(
              initialQuery: '论坛',
              search: (_) async => _result([
                for (var i = 0; i < 13; i++) _thread(i),
                if (sparse)
                  const ThreadSummary(
                    tid: 13,
                    title: '搜索结果 13',
                    author: '',
                    replies: 0,
                    views: 0,
                  )
                else
                  _thread(13),
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final marker = find.text('没有更多结果');
        final scroll = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(marker, 500, scrollable: scroll);
        final position = tester.state<ScrollableState>(scroll).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();

        final title = find.text('搜索结果 13');
        final row = find.ancestor(
          of: title,
          matching: find.byType(SearchResultCard),
        );
        final lastText = sparse
            ? title
            : find.descendant(of: row, matching: find.text('reader'));
        final markerRect = tester.getRect(marker);
        expect(
          markerRect.top - tester.getRect(lastText).bottom,
          closeTo(ListEndTokens.markerGap, 1),
        );
        expect(
          844 - bottomInset - markerRect.bottom,
          closeTo(ListEndTokens.markerGap, .01),
        );
      },
    );
  }

  testWidgets('entry autofocus waits for its route transition to complete', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Hero(
                tag: 'search-entry-test',
                child: ChromeButton(
                  icon: AppIcons.search,
                  tooltip: '打开搜索',
                  onPressed: () => Navigator.push(
                    context,
                    PageRouteBuilder<void>(
                      transitionDuration: const Duration(milliseconds: 500),
                      pageBuilder: (_, _, _) => const SearchPage(
                        entryHeroTag: 'search-entry-test',
                        autofocus: true,
                      ),
                      transitionsBuilder: (_, animation, _, child) =>
                          FadeTransition(opacity: animation, child: child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开搜索'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back button and the search capsule share one row', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final back = tester.getRect(find.byTooltip('返回'));
    final field = tester.getRect(find.byType(TextField));
    expect(back.center.dy, moreOrLessEquals(field.center.dy, epsilon: 2));
    expect(back.right, lessThanOrEqualTo(field.left));
    expect(find.text('搜索'), findsNothing);
  });

  testWidgets('the compact workspace exposes only real session history', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(_app(const SearchPage()));
    await tester.pumpAndSettle();
    expect(find.text('全站帖子'), findsNothing);
    expect(find.text('建议关键词'), findsNothing);
    expect(find.text('最近搜索'), findsNothing);
    expect(find.text('还没有搜索记录'), findsOneWidget);
    for (final keyword in ['装机', '显示器', '摄影', 'NAS']) {
      expect(find.text(keyword), findsNothing);
    }
    expect(find.textContaining('热搜'), findsNothing);
    // 没有顶栏标题,输入框就是头部
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('搜索'), findsNothing);
    expect(tester.getRect(find.byType(TextField)).top, lessThan(125));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search results align at 20dp and omit the count and scope', (
    tester,
  ) async {
    await _phone(tester);
    final queries = <String>[];
    await tester.pumpWidget(
      _app(
        SearchPage(
          search: (query) async {
            queries.add(query);
            return _result([
              _thread(3, title: '装机散热记录', snippet: '这是一段装机经验的真实搜索摘要'),
            ]);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _submit(tester, '装机');
    await tester.pumpAndSettle();
    expect(queries, ['装机']);
    expect(find.textContaining('已加载'), findsNothing);
    expect(find.text('全站帖子'), findsNothing);
    expect(find.byType(ThreadRow), findsOneWidget);
    final title = find.text('装机散热记录');
    final summary = find.text('这是一段装机经验的真实搜索摘要');
    final replies = find.text('3');
    expect(tester.widget<Text>(title).maxLines, 1);
    expect(tester.widget<Text>(summary).maxLines, 2);
    expect(tester.getTopLeft(title).dx, 20);
    expect(tester.getTopRight(replies).dx, moreOrLessEquals(370, epsilon: 1));
    expect(find.text('电脑讨论'), findsOneWidget);
    expect(find.text('reader'), findsOneWidget);
    expect(find.text('2020年10月18日'), findsOneWidget);
    expect(find.text('3 回复'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search skeleton and results share row geometry at large type', (
    tester,
  ) async {
    await _phone(tester, width: 320);
    final pending = Completer<SearchResultPage>();
    await tester.pumpWidget(
      _app(
        SearchPage(initialQuery: '散热', search: (_) => pending.future),
        scale: 2,
      ),
    );
    await tester.pump();
    await tester.pump(AppMotion.skeletonDelay);
    final row = find.byType(SearchThreadRowLayout);
    final placeholderRect = tester.getRect(row.first);
    final nextPlaceholderRect = tester.getRect(row.at(1));
    final bars = find.descendant(
      of: row.first,
      matching: find.byType(DecoratedBox),
    );
    expect(bars, findsNWidgets(4));
    for (final bar in bars.evaluate()) {
      expect(
        (bar.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
        20,
      );
    }
    final field = tester.element(find.byType(TextField));
    final fieldRect = tester.getRect(find.byType(TextField));

    pending.complete(
      _result([
        _thread(1, title: '散热改装', snippet: '一段简短摘要'),
        _thread(2, title: '风扇更换'),
      ]),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.getRect(row.first), placeholderRect);
    expect(tester.getRect(row.at(1)), nextPlaceholderRect);
    expect(tester.getTopLeft(find.text('散热改装')).dx, 20);
    expect(tester.getTopRight(find.text('1')).dx, closeTo(300, 1));
    expect(tester.element(find.byType(TextField)), same(field));
    expect(tester.getRect(find.byType(TextField)), fieldRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'only submitted queries enter session history and can be searched again',
    (tester) async {
      await _phone(tester);
      final queries = <String>[];
      await tester.pumpWidget(
        _app(
          SearchPage(
            search: (query) async {
              queries.add(query);
              return _result([_thread(1)]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '未提交内容');
      expect(searchSessionHistory.queries, isEmpty);
      await _submit(tester, '液冷配置');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(searchSessionHistory.queries, ['液冷配置']);
      expect(find.text('最近搜索'), findsOneWidget);
      await tester.tap(find.text('液冷配置'));
      await tester.pumpAndSettle();
      expect(queries, ['液冷配置', '液冷配置']);
      expect(searchSessionHistory.queries, ['液冷配置']);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(searchSessionHistory.queries, isEmpty);
      expect(find.text('最近搜索'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear prevents an old request restoring results and preserves useful history',
    (tester) async {
      await _phone(tester);
      final pending = Completer<SearchResultPage>();
      await tester.pumpWidget(
        _app(SearchPage(initialQuery: '旧查询', search: (_) => pending.future)),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('清除搜索'));
      pending.complete(_result([_thread(9, title: '过期搜索结果')]));
      await tester.pumpAndSettle();
      expect(find.text('过期搜索结果'), findsNothing);
      expect(find.text('建议关键词'), findsNothing);
      expect(find.text('最近搜索'), findsOneWidget);
      expect(find.text('旧查询'), findsOneWidget);
      expect(searchSessionHistory.queries, ['旧查询']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a newly submitted keyword wins even if the previous query finishes later',
    (tester) async {
      await _phone(tester);
      final responses = <String, Completer<SearchResultPage>>{};
      await tester.pumpWidget(
        _app(
          SearchPage(
            search: (query) =>
                (responses[query] = Completer<SearchResultPage>()).future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _submit(tester, '旧查询');
      await _submit(tester, '新查询');
      responses['新查询']!.complete(_result([_thread(2, title: '新的结果')]));
      await tester.pump();
      responses['旧查询']!.complete(_result([_thread(1, title: '旧的结果')]));
      await tester.pumpAndSettle();
      expect(find.text('新的结果'), findsOneWidget);
      expect(find.text('旧的结果'), findsNothing);
      expect(find.textContaining('已加载'), findsNothing);
    },
  );

  testWidgets(
    'the primary action submits and a result opens its original thread identity',
    (tester) async {
      await _phone(tester);
      ThreadSummary? opened;
      await tester.pumpWidget(
        _app(
          SearchPage(
            search: (query) async => _result([
              _thread(42, title: 'C++ 配置讨论', snippet: '关于 C++ 的配置经验'),
            ]),
            onOpenThread: (thread) => opened = thread,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'C++');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('C++ 配置讨论'));
      await tester.pumpAndSettle();
      expect(opened?.tid, 42);
      expect(opened?.forumFid, 146);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow large-type search cards and input remain usable', (
    tester,
  ) async {
    await _phone(tester, width: 320);
    await tester.pumpWidget(
      _app(
        SearchPage(
          initialQuery: '主板配置',
          search: (_) async => _result([
            _thread(
              1,
              title: '主板配置与日常使用讨论',
              snippet: '长一些的真实摘要，包含主板配置与实际使用背景。',
            ),
          ]),
        ),
        scale: 1.6,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已加载'), findsNothing);
    expect(find.text('主板配置与日常使用讨论'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duplicate next-page responses terminate continuation without duplicating topics',
    (tester) async {
      await _phone(tester);
      var continuations = 0;
      await tester.pumpWidget(
        _app(
          SearchPage(
            initialQuery: '分页',
            search: (_) async => _result([
              for (var i = 0; i < 8; i++) _thread(i),
            ], next: 'https://www.chiphell.com/search.php?searchid=1&page=2'),
            searchNext: (_) async {
              continuations++;
              return _result([
                for (var i = 0; i < 8; i++) _thread(i),
              ], next: 'https://www.chiphell.com/search.php?searchid=1&page=2');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(ListView).last;
      final scrollable = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        find.text('没有更多结果'),
        600,
        scrollable: scrollable,
        maxScrolls: 15,
      );
      await tester.pumpAndSettle();
      expect(continuations, 1);
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      await tester.pumpAndSettle();
      expect(find.byType(ThreadRow), findsNWidgets(8));
      expect(tester.takeException(), isNull);
    },
  );
}
