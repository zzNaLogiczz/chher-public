import 'dart:async';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/thread_list_time.dart';
import 'package:chh_app/models/thread_sort.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/widgets/browse_controls.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadSummary _thread(int id, {String? last}) => ThreadSummary(
  tid: id,
  title: '本地帖子 $id',
  author: '测试读者',
  replies: 12,
  views: 120,
  typeName: '硬件',
  lastPostTimeRaw: last,
);

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));
  Completer<ThreadListPage>? pendingSort;
  int reads = 0;
  List<ThreadType> types = const [ThreadType(typeid: 101, name: '硬件')];
  @override
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async =>
      types;
  @override
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async {
    reads++;
    if (orderby == 'dateline' && pendingSort != null) {
      return pendingSort!.future;
    }
    return result;
  }

  ThreadListPage get result => ThreadListPage(
    threads: [for (var n = 0; n < 80; n++) _thread(n)],
    page: const PageInfo(current: 1, hasNext: false),
  );
}

Future<void> _phone(WidgetTester tester, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _forum(
  WidgetTester tester,
  _Forums repo,
  int fid, {
  double width = 390,
  double textScale = 1,
}) async {
  await _phone(tester, width: width);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ForumThreadsPage(fid: fid, title: '硬件讨论', repository: repo),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, Finder control, String value) async {
  await tester.tap(control);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'category keeps blue text without background and sort stays in navigation',
    (tester) async {
      await _forum(tester, _Forums(), 2103);
      final category = find.byType(PickerButton<int>);
      expect(tester.getSize(category).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(category).width, greaterThanOrEqualTo(44));
      final label = tester.widget<Text>(
        find.descendant(of: category, matching: find.text('全部分类')),
      );
      expect(label.style?.color, AppTokens.light.accent);
      final paintedBackgrounds = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: category, matching: find.byType(DecoratedBox)),
          )
          .where(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).color != null,
          );
      expect(paintedBackgrounds, isEmpty);
      expect(
        tester
            .widget<ChromeGroup>(find.byType(ChromeGroup))
            .items
            .map((item) => item.tooltip),
        ['排序', '搜索帖子', '收藏版块'],
      );
      expect(find.byType(PickerButton<ThreadSort>), findsNothing);
      final sort = find.byTooltip('排序');
      expect(tester.getSize(sort).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(sort).width, greaterThanOrEqualTo(44));
      await tester.tap(sort);
      await tester.pumpAndSettle();
      expect(find.text('排序方式'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('forums without categories do not reserve a filter header', (
    tester,
  ) async {
    await _forum(tester, _Forums()..types = const [], 2107);
    expect(find.byKey(const ValueKey('forum-filters')), findsNothing);
    expect(find.byType(PickerButton<int>), findsNothing);
    expect(find.byTooltip('排序').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320dp and 2x retains reachable category and navigation sorting',
    (tester) async {
      await _forum(tester, _Forums(), 2104, width: 320, textScale: 2);
      for (final control in [
        find.byType(PickerButton<int>),
        find.byTooltip('排序'),
      ]) {
        expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
        expect(control.hitTestable(), findsOneWidget);
      }
      await _pick(tester, find.byType(PickerButton<int>), '硬件');
      expect(
        tester.widget<PickerButton<int>>(find.byType(PickerButton<int>)).value,
        101,
      );
      await _pick(tester, find.byTooltip('排序'), '最新发布');
      expect(
        tester
            .widget<ChromeGroup>(find.byType(ChromeGroup))
            .items
            .firstWhere((item) => item.tooltip == '排序')
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 320.0]) {
    testWidgets(
      'short and long categories keep filter and sort geometry at $width',
      (tester) async {
        final repo = _Forums()
          ..types = const [
            ThreadType(typeid: 101, name: '硬件'),
            ThreadType(typeid: 102, name: '机箱风道与水冷散热深度讨论区'),
          ];
        await _forum(tester, repo, width == 390 ? 2105 : 2106, width: width);
        final bar = find.byKey(const ValueKey('forum-filters'));
        final sort = find.byTooltip('排序');
        final originalBar = tester.getRect(bar);
        final originalSort = tester.getRect(sort);
        for (final category in ['机箱风道与水冷散热深度讨论区', '硬件', '全部分类']) {
          await _pick(tester, find.byType(PickerButton<int>), category);
          expect(tester.getRect(bar).height, closeTo(originalBar.height, .1));
          expect(tester.getRect(sort).top, closeTo(originalSort.top, .1));
          expect(tester.getRect(sort).left, closeTo(originalSort.left, .1));
          expect(tester.getRect(sort).size, originalSort.size);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('user scroll hides compose and reverse scroll restores it', (
    tester,
  ) async {
    await _forum(tester, _Forums(), 2101);
    final opacity = find.byKey(const ValueKey('forum-compose-visibility'));
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    await tester.drag(find.byType(ListView), const Offset(0, -550));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    expect(find.byTooltip('发主题').hitTestable(), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    expect(find.byTooltip('发主题').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filters stay pinned during scrolling and sort/category replacement',
    (tester) async {
      final repo = _Forums();
      await _forum(tester, repo, 2102);
      await tester.drag(find.byType(ListView), const Offset(0, -550));
      await tester.pumpAndSettle();
      final filters = find.byKey(const ValueKey('forum-filters'));
      final pinned = tester.getRect(filters);
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.getRect(filters).top, closeTo(pinned.top, .01));
      repo.pendingSort = Completer<ThreadListPage>();
      await _pick(tester, find.byTooltip('排序'), '最新发布');
      expect(tester.getRect(filters).top, closeTo(pinned.top, .01));
      repo.pendingSort!.complete(repo.result);
      await tester.pumpAndSettle();
      expect(tester.getRect(filters).top, closeTo(pinned.top, .01));
      await _pick(tester, find.byType(PickerButton<int>), '硬件');
      expect(tester.getRect(filters).top, closeTo(pinned.top, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date sections continue across pagination without inventing unknown dates',
    (tester) async {
      await _phone(tester);
      final now = DateTime(2026, 11, 4, 12);
      final reads = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: BrowseScaffold(
            title: '分组列表',
            body: BrowseThreadList(
              loader: (page, {bool refresh = false}) async {
                reads.add(page);
                return Paged(
                  items: page == 1
                      ? [
                          _thread(1, last: '2026-11-04 10:30'),
                          _thread(2, last: '2026-11-04 09:30'),
                        ]
                      : [
                          _thread(3, last: '2026-11-04 08:30'),
                          _thread(4, last: '2026-11-03 18:30'),
                          _thread(5),
                        ],
                  page: PageInfo(current: page, hasNext: page == 1),
                );
              },
              sectionLabel: (thread) => ThreadListTime.of(
                thread,
                ThreadSort.latest,
                now: now,
              ).section,
              itemBuilder: (_, thread) => ThreadRow(thread: thread),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var n = 0; n < 4 && !reads.contains(2); n++) {
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      expect(reads, [1, 2]);
      // This small fixture remains entirely laid out in the viewport/cache.
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('昨天'), findsOneWidget);
      expect(find.text('更早'), findsNothing);
      expect(find.text('本地帖子 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a thousand rows remain lazy while scrolling', (tester) async {
    await _phone(tester);
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: BrowseScaffold(
          title: '长列表',
          body: BrowseThreadList(
            loader: (page, {bool refresh = false}) async => Paged(
              items: [for (var n = 0; n < 1000; n++) _thread(n)],
              page: const PageInfo(current: 1, hasNext: false),
            ),
            itemBuilder: (_, thread) {
              built.add(thread.tid);
              return ThreadRow(thread: thread);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built.length, lessThan(40));
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(built.length, lessThan(60));
    expect(built.length, greaterThan(5));
    expect(tester.takeException(), isNull);
  });
}
