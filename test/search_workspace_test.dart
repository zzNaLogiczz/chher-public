import 'dart:async';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:chh_app/widgets/search_workspace.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadSummary _thread(int id, {String? title, String? snippet}) =>
    ThreadSummary(
      tid: id,
      title: title ?? '搜索结果 $id',
      author: 'reader',
      replies: id,
      views: 22,
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

  testWidgets(
    'the compact workspace exposes scope and only real session history',
    (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_app(const SearchPage()));
      await tester.pumpAndSettle();
      // 范围标签只在结果计数行出现,搜索前不占位
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
    },
  );

  testWidgets('a submitted keyword shows loaded count and matching context', (
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
    expect(find.text('已加载 1 条'), findsOneWidget);
    // 范围放在结果计数行右侧
    expect(
      tester.getCenter(find.text('全站帖子')).dy,
      moreOrLessEquals(tester.getCenter(find.text('已加载 1 条')).dy, epsilon: 2),
    );
    expect(
      tester.getCenter(find.text('全站帖子')).dx,
      greaterThan(tester.getCenter(find.text('已加载 1 条')).dx),
    );
    expect(find.text('装机散热记录'), findsOneWidget);
    expect(find.text('这是一段装机经验的真实搜索摘要'), findsOneWidget);
    expect(find.text('电脑讨论'), findsOneWidget);
    expect(find.text('3 回复'), findsOneWidget);
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
      expect(find.text('已加载 1 条'), findsOneWidget);
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
    expect(find.text('已加载 1 条'), findsOneWidget);
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
      expect(find.text('已加载 8 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
