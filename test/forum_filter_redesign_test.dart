import 'dart:async';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/scroll_progress.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/thread_sort.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/widgets/browse_controls.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));
  final requests = <({int? type, String? order})>[];
  Completer<ThreadListPage>? filtered;
  Completer<ThreadListPage>? sorted;
  List<ThreadType> types = const [
    ThreadType(typeid: 0, name: '全部'),
    ThreadType(typeid: 1, name: 'CPU'),
    ThreadType(typeid: 2, name: '显卡'),
    ThreadType(typeid: 3, name: '内存'),
  ];

  ThreadListPage result({String prefix = '原列表'}) => ThreadListPage(
    threads: [
      for (final (index, last) in [
        '今天 10:30',
        '今天 09:30',
        '昨天 10:30',
        '2020-01-01',
        null,
      ].indexed)
        ThreadSummary(
          tid: index + 1,
          title: '$prefix ${index + 1}',
          author: '读者',
          replies: index,
          views: index * 10,
          typeName: 'CPU',
          lastPostTimeRaw: last,
        ),
    ],
    page: const PageInfo(current: 1, hasNext: false),
  );

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
    requests.add((type: typeid, order: orderby));
    if (typeid != null && filtered != null) return filtered!.future;
    if (orderby != null && sorted != null) return sorted!.future;
    return result(prefix: typeid == null ? '原列表' : '筛选列表');
  }
}

class _PinnedForums extends _Forums {
  @override
  ThreadListPage result({String prefix = '原列表'}) => ThreadListPage(
    threads: [
      const ThreadSummary(
        tid: 900,
        title: '本地置顶样例',
        author: '读者',
        replies: 1,
        views: 10,
        sticky: true,
      ),
      ...super.result(prefix: prefix).threads,
    ],
    page: const PageInfo(current: 1, hasNext: false),
  );
}

Future<void> _mount(
  WidgetTester tester,
  _Forums repo,
  int fid, {
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness, style),
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

Future<void> _pick(WidgetTester tester, String tooltip, String label) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

ForumThreadCardSlice _card(WidgetTester tester, int tid) => tester
    .widget<ForumThreadCardSlice>(find.byKey(ValueKey('forum-card-$tid')));

void main() {
  testWidgets(
    'sort picker keeps its state when replacement removes the pinned group',
    (tester) async {
      final repo = _PinnedForums()..sorted = Completer<ThreadListPage>();
      await _mount(tester, repo, 3052);
      final picker = find.byType(PickerButton<ThreadSort>);
      final pickerElement = picker.evaluate().single;
      final pickerState = tester.state(picker);
      expect(find.byType(PinnedGroupRow), findsOneWidget);
      await _pick(tester, '排序', '回复最多');
      expect(picker.evaluate().single, same(pickerElement));
      final result = repo.result(prefix: '无置顶排序');
      repo.sorted!.complete(
        ThreadListPage(
          threads: result.threads.where((thread) => !thread.sticky).toList(),
          page: result.page,
        ),
      );
      await tester.pump();
      expect(find.byType(PinnedGroupRow), findsNothing);
      expect(picker.evaluate().single, same(pickerElement));
      expect(tester.state(picker), same(pickerState));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PickerButton<ThreadSort>>(picker).value,
        ThreadSort.replies,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'FAB follows the first scroll pixels while the large title is still visible',
    (tester) async {
      await _mount(tester, _Forums(), 3050);
      final transform = find.byKey(const ValueKey('forum-compose-visibility'));
      double fabOffset() =>
          tester.widget<Transform>(transform).transform.storage[13];
      final outer = tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController;
      expect(outer.offset, 0);
      expect(fabOffset(), 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      final before = fabOffset();
      final beforeOuter = outer.offset;
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump();
      expect(outer.offset, lessThan(outer.position.maxScrollExtent));
      expect(outer.offset - beforeOuter, closeTo(12, .01));
      expect(fabOffset() - before, closeTo(12, .01));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fabOffset(), 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320dp at 2x keeps a long selected category clearable without overflow',
    (tester) async {
      const longCategory = '机箱风道与水冷散热深度讨论区';
      final repo = _Forums()
        ..types = const [
          ThreadType(typeid: 0, name: '全部'),
          ThreadType(typeid: 1, name: longCategory),
        ];
      await _mount(tester, repo, 3051, width: 320, textScale: 2);
      await _pick(tester, '分类筛选', longCategory);
      final clear = find.byKey(const ValueKey('forum-filter-clear'));
      expect(clear.hitTestable(), findsOneWidget);
      expect(repo.requests.last.type, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(repo.requests.last.type, isNull);
      expect(clear.hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pinned expansion survives recreation and is isolated by forum', (
    tester,
  ) async {
    final repo = _PinnedForums();
    final pins = find.byType(PinnedGroupRow);
    Future<void> recreate(int fid) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, repo, fid);
    }

    bool expanded() => tester.widget<PinnedGroupRow>(pins).expanded;
    Finder pinnedRow() => find.byWidgetPredicate(
      (widget) => widget is ThreadRow && widget.thread.tid == 900,
    );

    await recreate(3040);
    expect(expanded(), isFalse);
    expect(pinnedRow(), findsNothing);
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(expanded(), isTrue);
    expect(pinnedRow(), findsOneWidget);
    await recreate(3040);
    expect(expanded(), isTrue);
    expect(pinnedRow(), findsOneWidget);
    await recreate(3041);
    expect(expanded(), isFalse);
    expect(pinnedRow(), findsNothing);
    await recreate(3040);
    expect(expanded(), isTrue);
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(expanded(), isFalse);
    await recreate(3040);
    expect(expanded(), isFalse);
    expect(pinnedRow(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filter and sort replacements keep pinned rows expanded without replaying height',
    (tester) async {
      final repo = _PinnedForums();
      await _mount(tester, repo, 3042);
      final pins = find.byType(PinnedGroupRow);
      await tester.tap(find.text('置顶'));
      await tester.pumpAndSettle();
      final expandedHeight = tester.getSize(pins).height;
      final listState = tester.state(find.byType(BrowseThreadList));
      final row = find.byWidgetPredicate(
        (widget) => widget is ThreadRow && widget.thread.tid == 900,
      );
      final rowElement = row.evaluate().single;
      void expectRetained() {
        expect(tester.widget<PinnedGroupRow>(pins).expanded, isTrue);
        expect(tester.getSize(pins).height, expandedHeight);
        expect(tester.state(find.byType(BrowseThreadList)), same(listState));
        expect(row.evaluate().single, same(rowElement));
      }

      repo.filtered = Completer<ThreadListPage>();
      await _pick(tester, '分类筛选', 'CPU');
      expectRetained();
      repo.filtered!.complete(repo.result(prefix: '筛选列表'));
      await tester.pump();
      expectRetained();
      await tester.pump(const Duration(milliseconds: 60));
      expectRetained();
      await tester.pumpAndSettle();
      repo.filtered = null;
      repo.sorted = Completer<ThreadListPage>();
      await _pick(tester, '排序', '回复最多');
      expectRetained();
      repo.sorted!.complete(repo.result(prefix: '排序列表'));
      await tester.pump();
      expectRetained();
      await tester.pump(const Duration(milliseconds: 60));
      expectRetained();
      await tester.pumpAndSettle();
      expectRetained();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forum list keeps reading position through cancelled and completed back drag',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            Brightness.light,
          ).copyWith(platform: TargetPlatform.android),
          home: BrowseScaffold(
            title: '硬件讨论',
            body: BrowseThreadList(
              key: const PageStorageKey('reading-position-forum'),
              groupCards: true,
              loader: (page, {bool refresh = false}) async {
                loads++;
                return Paged(
                  items: [
                    for (var i = 0; i < 80; i++)
                      ThreadSummary(
                        tid: i,
                        title: '位置样例 $i',
                        author: '读者',
                        replies: i,
                        views: i,
                      ),
                  ],
                  page: const PageInfo(current: 1, hasNext: false),
                );
              },
              itemBuilder: (context, thread) => ThreadRow(
                thread: thread,
                forumStyle: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('本地正文')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -680));
      await tester.pumpAndSettle();
      final title = tester
          .widgetList<ThreadRow>(find.byType(ThreadRow).hitTestable())
          .skip(1)
          .first
          .thread
          .title;
      final before = tester.getRect(find.text(title));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text('本地正文'), findsOneWidget);
      await tester.dragFrom(const Offset(1, 250), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(find.text('本地正文'), findsOneWidget);
      await tester.dragFrom(const Offset(1, 250), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(find.text('本地正文'), findsNothing);
      expect(tester.getRect(find.text(title)), before);
      expect(loads, 1);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '$style $brightness filter grid and clear preserve pending content',
        (tester) async {
          final repo = _Forums()..filtered = Completer<ThreadListPage>();
          await _mount(
            tester,
            repo,
            3010 + style.index * 2 + brightness.index,
            style: style,
            brightness: brightness,
          );
          final clear = find.byKey(
            const ValueKey('forum-filter-clear'),
            skipOffstage: false,
          );
          double clearHeaderHeight() => tester
              .getSize(
                find.byWidget(
                  tester
                      .widget<BrowseScaffold>(find.byType(BrowseScaffold))
                      .header!,
                  skipOffstage: false,
                ),
              )
              .height;
          expect(clear.hitTestable(), findsNothing);
          expect(clearHeaderHeight(), 0);
          await tester.tap(find.byTooltip('分类筛选'));
          await tester.pumpAndSettle();
          final rects = [
            for (var i = 0; i < 4; i++)
              tester.getRect(find.byKey(ValueKey('picker-option-$i'))),
          ];
          expect(rects.take(3).map((r) => r.top).toSet(), hasLength(1));
          expect(rects[1].left, greaterThan(rects[0].right));
          expect(rects[2].left, greaterThan(rects[1].right));
          expect(rects[3].top, greaterThan(rects[0].bottom));
          expect(rects.map((r) => r.height), everyElement(44));
          await tester.tap(find.text('CPU').last);
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(repo.requests.last.type, 1);
          expect(find.text('原列表 1'), findsOneWidget);
          expect(find.text('筛选列表 1'), findsNothing);
          expect(
            find.descendant(
              of: find.byType(ThreadRow),
              matching: find.text('CPU'),
            ),
            findsNothing,
          );
          expect(
            tester
                .widget<ChromeGroup>(find.byType(ChromeGroup))
                .items
                .first
                .dot,
            isTrue,
          );
          expect(clear.hitTestable(), findsOneWidget);
          expect(clearHeaderHeight(), greaterThanOrEqualTo(44));
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(repo.requests.last.type, isNull);
          expect(
            tester
                .widget<ChromeGroup>(find.byType(ChromeGroup))
                .items
                .first
                .selected,
            isFalse,
          );
          expect(clear.hitTestable(), findsNothing);
          expect(clearHeaderHeight(), 0);
          repo.filtered!.complete(repo.result(prefix: '过期筛选'));
          await tester.pumpAndSettle();
          expect(find.text('原列表 1'), findsOneWidget);
          expect(find.text('过期筛选 1'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'filter failure retains rows and explicit retry replaces on arrival',
    (tester) async {
      final repo = _Forums()..filtered = Completer<ThreadListPage>();
      await _mount(tester, repo, 3020);
      await _pick(tester, '分类筛选', 'CPU');
      repo.filtered!.completeError(StateError('local fixture failure'));
      await tester.pumpAndSettle();
      expect(find.text('原列表 1'), findsOneWidget);
      expect(find.text('继续加载'), findsOneWidget);
      final requests = repo.requests.length;
      await tester.pump(const Duration(seconds: 2));
      expect(repo.requests, hasLength(requests));
      repo.filtered = Completer<ThreadListPage>();
      await tester.tap(find.text('继续加载'));
      await tester.pump();
      expect(repo.requests, hasLength(requests + 1));
      expect(repo.requests.last.type, 1);
      expect(find.text('原列表 1'), findsOneWidget);
      repo.filtered!.complete(repo.result(prefix: '筛选列表'));
      await tester.pumpAndSettle();
      expect(find.text('原列表 1'), findsNothing);
      expect(find.text('筛选列表 1'), findsOneWidget);
      expect(
        tester
            .widgetList<ThreadRow>(find.byType(ThreadRow))
            .every((r) => !r.showCategory),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('date cards remain committed until count sort arrives', (
    tester,
  ) async {
    final repo = _Forums()..sorted = Completer<ThreadListPage>();
    await _mount(tester, repo, 3021);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('更早'), findsOneWidget);
    expect((_card(tester, 1).first, _card(tester, 1).last), (true, false));
    expect((_card(tester, 2).first, _card(tester, 2).last), (false, true));
    expect((_card(tester, 3).first, _card(tester, 3).last), (true, true));
    expect((_card(tester, 4).first, _card(tester, 4).last), (true, true));
    // An unknown date does not acquire the preceding card's date label.
    expect((_card(tester, 5).first, _card(tester, 5).last), (true, false));
    await _pick(tester, '排序', '回复最多');
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('原列表 1'), findsOneWidget);
    expect(
      tester
          .widget<PickerButton<ThreadSort>>(
            find.byType(PickerButton<ThreadSort>),
          )
          .value,
      ThreadSort.replies,
    );
    repo.sorted!.complete(repo.result(prefix: '按回复排序'));
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsNothing);
    expect(find.text('昨天'), findsNothing);
    expect(find.text('更早'), findsNothing);
    expect((_card(tester, 1).first, _card(tester, 1).last), (true, false));
    expect((_card(tester, 3).first, _card(tester, 3).last), (false, false));
    expect((_card(tester, 5).first, _card(tester, 5).last), (false, false));
    expect(find.text('按回复排序 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scroll progress follows pixels, snaps, and accepts interruption',
    (tester) async {
      final progress = ScrollDeltaProgress(vsync: tester, travel: 100);
      addTearDown(progress.dispose);
      progress.drag(24);
      expect(progress.value, .24);
      await tester.pump(const Duration(milliseconds: 80));
      expect(progress.value, .24);
      expect(tester.hasRunningAnimations, isFalse);
      progress.drag(42);
      expect(progress.value, closeTo(.66, .0001));
      progress.settle(velocity: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(progress.value, greaterThan(.66));
      final interrupted = progress.value;
      progress.drag(-10);
      expect(progress.value, closeTo(interrupted - .1, .0001));
      await tester.pump(const Duration(milliseconds: 100));
      expect(progress.value, closeTo(interrupted - .1, .0001));
      progress.settle();
      await tester.pumpAndSettle();
      expect(progress.value, 1);
      progress.drag(-70);
      progress.settle();
      await tester.pumpAndSettle();
      expect(progress.value, 0);
      expect(tester.hasRunningAnimations, isFalse);
      progress.drag(20, reduced: true);
      expect(progress.value, 0);
      await tester.pumpAndSettle();
      expect(progress.value, 1);
      progress.drag(-1, reduced: true);
      expect(progress.value, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(progress.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(progress.value, 0);
    },
  );
}
