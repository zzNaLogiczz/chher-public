import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/articles_view.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:chh_app/widgets/browse_controls.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:chh_app/widgets/paged_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget body) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: BrowseScaffold(title: '列表', body: body),
);

Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _reachLast(WidgetTester tester, String label) async {
  final list = find.byType(ListView).last;
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    find.text(label),
    1000,
    scrollable: scrollable,
    maxScrolls: 120,
  );
  await tester.pumpAndSettle();
}

ThreadSummary _thread(int id, String prefix) => ThreadSummary(
  tid: id,
  title: '$prefix$id',
  author: 'reader',
  replies: 1,
  views: 2,
);

class _Residency {
  final mounted = <int>{};
  int builds = 0;
}

class _TrackedRow extends StatefulWidget {
  final int id;
  final _Residency residency;
  const _TrackedRow({super.key, required this.id, required this.residency});
  @override
  State<_TrackedRow> createState() => _TrackedRowState();
}

class _TrackedRowState extends State<_TrackedRow> {
  @override
  void initState() {
    super.initState();
    widget.residency.mounted.add(widget.id);
  }

  @override
  void dispose() {
    widget.residency.mounted.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.residency.builds++;
    return SizedBox(height: 100, child: Text('row-${widget.id}'));
  }
}

void main() {
  testWidgets(
    'lazy generic paging keeps loaded content and retries the failed page once',
    (tester) async {
      await _phone(tester);
      final requests = <int>[];
      var failed = false;
      await tester.pumpWidget(
        _app(
          PagedList<int>(
            loader: (page, {bool refresh = false}) async {
              requests.add(page);
              if (page == 2 && !failed) {
                failed = true;
                throw StateError('one-off transport failure');
              }
              return Paged(
                items: page == 1 ? List.generate(7, (i) => i) : [7, 8],
                page: PageInfo(current: page, hasNext: page == 1),
              );
            },
            itemBuilder: (_, id) =>
                SizedBox(height: 140, child: Text('retry-row-$id')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(requests, [1, 2]);
      await tester.tap(find.text('加载失败，重试'));
      await tester.pumpAndSettle();
      await _reachLast(tester, 'retry-row-8');
      expect(requests, [1, 2, 2]);
      expect(find.text('retry-row-8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '1000 browse topics keep row residency bounded while every topic stays reachable',
    (tester) async {
      await _phone(tester);
      final residency = _Residency();
      await tester.pumpWidget(
        _app(
          BrowseThreadList(
            loader: (page, {bool refresh = false}) async => Paged(
              items: [for (var i = 0; i < 1000; i++) _thread(i, 'topic-')],
              page: const PageInfo(current: 1, hasNext: false),
            ),
            itemBuilder: (_, thread) => _TrackedRow(
              key: ValueKey(thread.tid),
              id: thread.tid,
              residency: residency,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(residency.builds, lessThan(30));
      expect(residency.mounted.length, lessThan(30));
      expect(find.text('row-999'), findsNothing);
      await _reachLast(tester, 'row-999');
      expect(find.text('row-999'), findsOneWidget);
      expect(residency.mounted.length, lessThan(30));
      expect(residency.mounted.contains(0), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'generic account paging virtualizes 1000 rows and releases scrolled-out content',
    (tester) async {
      await _phone(tester);
      final residency = _Residency();
      await tester.pumpWidget(
        _app(
          PagedList<int>(
            loader: (page, {bool refresh = false}) async => Paged(
              items: List.generate(1000, (i) => i),
              page: const PageInfo(current: 1, hasNext: false),
            ),
            itemBuilder: (_, id) =>
                _TrackedRow(key: ValueKey(id), id: id, residency: residency),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(residency.builds, lessThan(30));
      expect(find.text('row-999'), findsNothing);
      await _reachLast(tester, 'row-999');
      expect(find.text('row-999'), findsOneWidget);
      expect(residency.mounted.length, lessThan(30));
      expect(residency.mounted.contains(0), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large search results mount nearby topics without hiding later results',
    (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: SearchPage(
            initialQuery: '性能',
            search: (_) async => SearchResultPage(
              rows: [for (var i = 0; i < 1000; i++) _thread(i, 'search-')],
              page: const PageInfo(current: 1, hasNext: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('search-').evaluate().length, lessThan(30));
      expect(find.text('search-999'), findsNothing);
      await _reachLast(tester, 'search-999');
      expect(find.text('search-999'), findsOneWidget);
      expect(find.textContaining('search-').evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'article discovery keeps later articles unbuilt until scrolled into view',
    (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          ArticlesView(
            loadCategories: () async => const [],
            loadArticles: (category, page, refresh) async => Paged(
              items: [
                for (var i = 0; i < 1000; i++)
                  PortalArticle(aid: i, title: 'article-$i'),
              ],
              page: const PageInfo(current: 1, hasNext: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('article-').evaluate().length, lessThan(30));
      expect(find.text('article-999'), findsNothing);
      await _reachLast(tester, 'article-999');
      expect(find.text('article-999'), findsOneWidget);
      expect(find.textContaining('article-').evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('forum directory keeps large categories lazy', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        ForumIndexView(
          loadForums: (_) async => [
            ForumCategory(
              name: '硬件',
              forums: [
                for (var i = 0; i < 1000; i++) Forum(fid: i, name: 'forum-$i'),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('forum-').evaluate().length, lessThan(30));
    expect(find.text('forum-999'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
