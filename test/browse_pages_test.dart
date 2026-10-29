import 'dart:async';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/articles_view.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:chh_app/widgets/browse_controls.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadSummary _thread(int id, String title) => ThreadSummary(
  tid: id,
  title: title,
  author: 'reader',
  replies: 2,
  views: 12,
);

SearchResultPage _result(int id, String title) => SearchResultPage(
  rows: [_thread(id, title)],
  page: const PageInfo(current: 1, hasNext: false),
);

Widget _app(Widget child) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: child);

Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('a login wall retries its list when returning from login', (
    tester,
  ) async {
    await _phone(tester);
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        routes: {
          '/login': (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完成登录'),
            ),
          ),
        },
        home: BrowseScaffold(
          title: '讨论',
          body: BrowseThreadList(
            loader: (page, {bool refresh = false}) async {
              loads++;
              if (loads == 1) {
                throw const PageMessage(PageMessageKind.loginRequired, '请先登录');
              }
              expect(refresh, isTrue);
              return Paged(
                items: [_thread(42, '登录后可见的帖子')],
                page: const PageInfo(current: 1, hasNext: false),
              );
            },
            itemBuilder: (_, thread) => Text(thread.title),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成登录'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('登录后可见的帖子'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root search starts with the capsule at the screen inset', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(_app(const SearchPage()));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    final field = tester.getRect(find.byType(EditableText));
    expect(field.top, lessThan(125));
    expect(find.text('全站帖子'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forum rows remain readable with large text on a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ForumIndexView(
              loadForums: (_) async => const [
                ForumCategory(
                  name: '硬件',
                  forums: [
                    Forum(fid: 1, name: '电脑硬件与装机讨论', threadCount: 12567),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('电脑硬件与装机讨论'), findsOneWidget);
    expect(tester.widget<Text>(find.text('电脑硬件与装机讨论')).maxLines, isNull);
    expect(
      tester.getSize(find.byType(PickerButton<int>)).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'directory uses short category navigation and keeps source names searchable',
    (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ForumIndexView(
              loadForums: (_) async => const [
                ForumCategory(
                  name: '互动区-勋章和活动的会场',
                  forums: [
                    Forum(fid: 1, name: 'iGame Mini 桌搭小钢炮装机赛', threadCount: 15),
                  ],
                ),
                ForumCategory(
                  name: '分享区-产品开箱与用户体验的分享',
                  forums: [Forum(fid: 2, name: '产品开箱')],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('勋章和活动的会场'), findsOneWidget);
      // 分区导航收进选择面板,面板里用可区分的短名
      await tester.tap(find.text('全部分区'));
      await tester.pumpAndSettle();
      Finder option(int i, String label) => find.descendant(
        of: find.byKey(ValueKey('picker-option-$i')),
        matching: find.text(label),
      );
      expect(option(1, '互动区'), findsOneWidget);
      expect(option(2, '分享区'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsNothing);
      await tester.enterText(find.byType(EditableText), '会场');
      await tester.pumpAndSettle();
      expect(find.text('iGame Mini 桌搭小钢炮装机赛'), findsOneWidget);
      expect(find.text('产品开箱'), findsNothing);
      expect(find.text('15 个主题'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forum directory filters actual forums locally and clears the query',
    (tester) async {
      await _phone(tester);
      var loads = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ForumIndexView(
              loadForums: (_) async {
                loads++;
                return const [
                  ForumCategory(
                    name: '硬件',
                    forums: [Forum(fid: 1, name: '电脑讨论', threadCount: 7)],
                  ),
                  ForumCategory(
                    name: '生活',
                    forums: [Forum(fid: 2, name: '摄影讨论')],
                  ),
                ];
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('电脑讨论'), findsOneWidget);
      expect(find.text('摄影讨论'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '摄影');
      await tester.pump();
      expect(find.text('电脑讨论'), findsNothing);
      expect(find.text('摄影讨论'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部分区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('硬件').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('电脑讨论'), findsOneWidget);
      expect(find.text('摄影讨论'), findsNothing);
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clearing an in-flight search prevents its response restoring results',
    (tester) async {
      await _phone(tester);
      final response = Completer<SearchResultPage>();
      await tester.pumpWidget(_app(SearchPage(search: (_) => response.future)));
      await tester.enterText(find.byType(EditableText), '主板');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The request stays pending while the clear control animates into view.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pump();
      response.complete(_result(1, '已经失效的结果'));
      await tester.pumpAndSettle();
      expect(find.text('已经失效的结果'), findsNothing);
      expect(find.text('最近搜索'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a new submitted keyword wins over a slow previous search', (
    tester,
  ) async {
    await _phone(tester);
    final responses = <String, Completer<SearchResultPage>>{};
    await tester.pumpWidget(
      _app(
        SearchPage(
          search: (keyword) =>
              (responses[keyword] = Completer<SearchResultPage>()).future,
        ),
      ),
    );
    await tester.enterText(find.byType(EditableText), '旧关键词');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(EditableText), '新关键词');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    responses['新关键词']!.complete(_result(2, '新的搜索结果'));
    await tester.pump();
    responses['旧关键词']!.complete(_result(1, '旧的搜索结果'));
    await tester.pumpAndSettle();
    expect(find.text('新的搜索结果'), findsOneWidget);
    expect(find.text('旧的搜索结果'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more reviews open on the real review category, not all', (
    tester,
  ) async {
    await _phone(tester);
    final requested = <int>[];
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ArticlesView(
            initialCategoryName: '评测',
            loadCategories: () async => const [
              PortalCategory(catid: 3, name: '摄影'),
              PortalCategory(catid: 1, name: '评测'),
            ],
            loadArticles: (category, page, refresh) async {
              requested.add(category);
              return const Paged(
                items: [PortalArticle(aid: 9, title: '评测栏目文章')],
                page: PageInfo(current: 1, hasNext: false),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 先解析出真实 catid 再读,不先读一遍全部
    expect(requested, [1]);
    expect(
      tester.widget<PickerButton<int>>(find.byType(PickerButton<int>)).value,
      1,
    );
    expect(find.text('评测'), findsOneWidget);
    expect(find.text('评测栏目文章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown initial category falls back to all articles', (
    tester,
  ) async {
    await _phone(tester);
    final requested = <int>[];
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ArticlesView(
            initialCategoryName: '评测',
            loadCategories: () async => throw Exception('offline'),
            loadArticles: (category, page, refresh) async {
              requested.add(category);
              return const Paged(
                items: [],
                page: PageInfo(current: 1, hasNext: false),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requested, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing article category while loading cannot mix the old category',
    (tester) async {
      await _phone(tester);
      final responses = <int, Completer<Paged<PortalArticle>>>{};
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ArticlesView(
              loadCategories: () async => const [
                PortalCategory(catid: 3, name: '摄影'),
              ],
              loadArticles: (category, page, refresh) =>
                  (responses[category] = Completer<Paged<PortalArticle>>())
                      .future,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(PickerButton<int>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('摄影').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 600));
      responses[3]!.complete(
        const Paged(
          items: [PortalArticle(aid: 3, title: '摄影栏目新文章')],
          page: PageInfo(current: 1, hasNext: false),
        ),
      );
      await tester.pump();
      responses[0]!.complete(
        const Paged(
          items: [PortalArticle(aid: 1, title: '全部栏目旧回包')],
          page: PageInfo(current: 1, hasNext: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('摄影栏目新文章'), findsOneWidget);
      expect(find.text('全部栏目旧回包'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'primary browse list appends the next real page and removes duplicate topics',
    (tester) async {
      await _phone(tester);
      final requested = <int>[];
      await tester.pumpWidget(
        _app(
          BrowseScaffold(
            title: '讨论',
            body: BrowseThreadList(
              loader: (page, {bool refresh = false}) async {
                requested.add(page);
                return Paged(
                  items: page == 1
                      ? [for (var i = 1; i <= 7; i++) _thread(i, '帖子 $i')]
                      : [_thread(7, '帖子 7'), _thread(8, '帖子 8')],
                  page: PageInfo(current: page, hasNext: page == 1),
                );
              },
              itemBuilder: (_, thread) =>
                  SizedBox(height: 140, child: Text(thread.title)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(requested, [1, 2]);
      expect(find.text('帖子 7'), findsOneWidget);
      expect(find.text('帖子 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
