import 'dart:async';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/thread_sort.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:chh_app/widgets/chhers_refresh_indicator.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedForums extends ForumRepository {
  _DelayedForums({this.includePinned = false}) : super(ChhClient(fetchers: []));
  final bool includePinned;
  Completer<ThreadListPage>? pending;
  final requests = <({int? type, String? order, bool refresh})>[];

  ThreadListPage result(String prefix) => ThreadListPage(
    threads: [
      for (var i = 0; i < 80; i++)
        ThreadSummary(
          tid: i + 1,
          title: '$prefix $i',
          author: '本地读者',
          replies: i,
          views: i,
          sticky: includePinned && i == 0,
          lastPostTimeRaw: '今天 10:30',
        ),
    ],
    page: const PageInfo(current: 1, hasNext: false),
  );

  @override
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async =>
      const [ThreadType(typeid: 1, name: 'CPU')];

  @override
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async {
    requests.add((type: typeid, order: orderby, refresh: refresh));
    return pending == null ? result('原列表') : pending!.future;
  }
}

Future<NestedScrollViewState> _mount(
  WidgetTester tester,
  _DelayedForums repo, {
  required int fid,
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: ForumThreadsPage(fid: fid, title: '本地硬件讨论', repository: repo),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
}

Future<void> _pickCpu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('分类筛选'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('picker-option-1')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final reduced in [false, true]) {
    for (final action in ['filter', 'sort', 'clear']) {
      testWidgets(
        '$action resets both scroll positions only on arrival, reduced=$reduced',
        (tester) async {
          final repo = _DelayedForums();
          final nested = await _mount(
            tester,
            repo,
            fid:
                8000 +
                (reduced ? 10 : 0) +
                ['filter', 'sort', 'clear'].indexOf(action),
            reduced: reduced,
          );
          if (action == 'clear') {
            await _pickCpu(tester);
            await tester.pumpAndSettle();
          }
          final sort = tester.widget<PickerButton<ThreadSort>>(
            find.byType(PickerButton<ThreadSort>),
          );
          final clear = tester.widget<PressScale>(
            find.byKey(
              const ValueKey('forum-filter-clear'),
              skipOffstage: false,
            ),
          );
          nested.innerController.jumpTo(2500);
          await tester.pumpAndSettle();
          final before = nested.innerController.offset;
          expect(before, greaterThan(2000));
          repo.pending = Completer<ThreadListPage>();
          if (action == 'filter') {
            await _pickCpu(tester);
            expect(repo.requests.last.type, 1);
          } else if (action == 'sort') {
            sort.onChanged(ThreadSort.replies);
          } else {
            clear.onTap!();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(nested.innerController.offset, before);
          expect(find.textContaining('原列表').hitTestable(), findsWidgets);
          repo.pending!.complete(repo.result('新列表'));
          await tester.pump();
          await tester.pump();
          if (!reduced) {
            expect(
              nested.innerController.offset + nested.outerController.offset,
              closeTo(nested.outerController.position.viewportDimension, .1),
              reason:
                  'Distant replacements jump to one viewport before the spring',
            );
            expect(nested.innerController.offset, greaterThan(0));
          }
          await tester.pumpAndSettle();
          expect(nested.innerController.offset, 0);
          expect(nested.outerController.offset, 0);
          expect(find.text('新列表 0').hitTestable(), findsOneWidget);
          if (action == 'filter') {
            expect(
              find.byKey(const ValueKey('forum-filter-clear')).hitTestable(),
              findsOneWidget,
            );
          }
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('failed filter retains content and scroll', (tester) async {
    final repo = _DelayedForums();
    final nested = await _mount(tester, repo, fid: 8020);
    nested.innerController.jumpTo(2500);
    await tester.pumpAndSettle();
    repo.pending = Completer<ThreadListPage>();
    await _pickCpu(tester);
    final before = nested.innerController.offset;
    repo.pending!.completeError(StateError('local failure'));
    await tester.pumpAndSettle();
    expect(nested.innerController.offset, before);
    expect(find.textContaining('原列表').hitTestable(), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refresh retains content and reading position while waiting and after arrival',
    (tester) async {
      final repo = _DelayedForums();
      final nested = await _mount(tester, repo, fid: 8021);
      nested.innerController.jumpTo(2500);
      await tester.pumpAndSettle();
      final before = nested.innerController.offset;
      repo.pending = Completer<ThreadListPage>();
      final refresh = tester
          .widget<ChhersRefreshIndicator>(find.byType(ChhersRefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(find.textContaining('原列表').hitTestable(), findsWidgets);
      expect(nested.innerController.offset, before);
      repo.pending!.complete(repo.result('刷新列表'));
      await refresh;
      await tester.pumpAndSettle();
      expect(find.textContaining('刷新列表').hitTestable(), findsWidgets);
      expect(nested.innerController.offset, before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh keeps the pinned group and existing rows opaque', (
    tester,
  ) async {
    final repo = _DelayedForums(includePinned: true);
    await _mount(tester, repo, fid: 8023);
    final list = find.byType(BrowseThreadList);
    final row = find.byKey(const ValueKey('forum-card-2'));
    final pinned = find.byKey(const ValueKey('browse-pinned'));
    final reveal = find.descendant(
      of: list,
      matching: find.byType(ExpressivePageReveal),
    );
    final view = tester.state(reveal);
    final animation =
        tester
                .widget<AnimatedBuilder>(
                  find
                      .descendant(
                        of: reveal,
                        matching: find.byType(AnimatedBuilder),
                      )
                      .first,
                )
                .animation
            as Animation<double>;
    final rowElement = tester.element(row);
    final pinnedElement = tester.element(pinned);
    final rowPosition = tester.getTopLeft(row);
    final pinnedPosition = tester.getTopLeft(pinned);

    void expectRetained() {
      expect(tester.state(reveal), same(view));
      expect(tester.element(row), same(rowElement));
      expect(tester.element(pinned), same(pinnedElement));
      expect(tester.getTopLeft(row), rowPosition);
      expect(tester.getTopLeft(pinned), pinnedPosition);
      expect(animation.value, 1);
    }

    repo.pending = Completer<ThreadListPage>();
    final refresh = tester
        .widget<ChhersRefreshIndicator>(find.byType(ChhersRefreshIndicator))
        .onRefresh();
    await tester.pump();
    expectRetained();
    repo.pending!.complete(repo.result('刷新列表'));
    await refresh;
    await tester.pump();
    expect(find.text('刷新列表 1'), findsOneWidget);
    expectRetained();
    await tester.pump(const Duration(milliseconds: 90));
    expectRetained();
    await tester.pumpAndSettle();
  });

  testWidgets('directory refresh failure keeps the last successful content', (
    tester,
  ) async {
    final pending = Completer<List<ForumCategory>>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: ForumIndexView(
          loadForums: (refresh) async => refresh
              ? pending.future
              : const [
                  ForumCategory(
                    name: '互动区',
                    forums: [Forum(fid: 1, name: '本地讨论')],
                  ),
                ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(find.text('本地讨论'));
    final refresh = tester
        .widget<LacquerTabScaffold>(find.byType(LacquerTabScaffold))
        .onRefresh!();
    final failed = expectLater(refresh, throwsStateError);
    await tester.pump();
    expect(tester.getRect(find.text('本地讨论')), before);
    pending.completeError(StateError('local refresh failure'));
    await failed;
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('本地讨论')), before);
    expect(find.text('1 个版块'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$style $brightness directory uses its approved header gap', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness, style),
            home: ForumIndexView(
              loadForums: (_) async => const [
                ForumCategory(
                  name: '互动区',
                  forums: [Forum(fid: 1, name: '本地讨论')],
                ),
                ForumCategory(
                  name: '生活区',
                  forums: [Forum(fid: 2, name: '本地生活')],
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scaffold = tester.widget<LacquerTabScaffold>(
          find.byType(LacquerTabScaffold),
        );
        final scroll = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        final header = (scroll.slivers.first as SliverToBoxAdapter).child!;
        final misty = style == AppearanceStyle.misty;
        final headerBottom = tester.getBottomLeft(find.byWidget(header)).dy;
        final contentEdge = headerBottom + (misty ? 0 : scaffold.seamOverlap);
        final firstTop = tester
            .getTopLeft(find.byKey(const ValueKey('forum-section-0')))
            .dy;
        expect(
          firstTop - contentEdge,
          closeTo(misty ? 20 : 32, .01),
          reason: misty
              ? 'Misty starts 20dp below the title without a seam'
              : 'Cinnabar retains 6dp paper inset and 26dp section spacing',
        );
        for (var i = 0; i < 2; i++) {
          final section = find
              .ancestor(
                of: find.byKey(ValueKey('forum-section-$i')),
                matching: find.byType(SliverPadding),
              )
              .first;
          expect(
            tester.widget<SliverPadding>(section).padding,
            misty && i == 0
                ? ForumDirectoryTokens.sectionPadding.copyWith(top: 0)
                : ForumDirectoryTokens.sectionPadding,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
