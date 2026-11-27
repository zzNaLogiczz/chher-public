import 'dart:async';
import 'dart:io';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/feedback.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/widgets/browse_thread_list.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inline_forum_parser.dart';

const _fid = 290;
final _fixture = File('test_data/thread_list_synthetic.html')
    .readAsStringSync()
    .replaceFirst('<body>', '''
<body>
<ul id="thread_types">
  <li><a href="?mod=forumdisplay&amp;typeid=1">ITX</a></li>
</ul>
''');

class _Transport extends ChhFetcher {
  final response = Completer<ChhResponse>();
  int requests = 0;

  @override
  String get name => 'phase-2-list-fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) {
    requests++;
    return response.future;
  }

  void deliver() => response.complete(ChhResponse(200, _fixture));
}

Future<PageRoute<void>> _open(
  WidgetTester tester,
  ForumRepository repository, {
  Duration? duration,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: buildAppTheme(Brightness.light),
      home: const Scaffold(),
    ),
  );
  final page = ForumThreadsPage(fid: _fid, title: '版块', repository: repository);
  final route = duration == null
      ? MaterialPageRoute<void>(builder: (_) => page)
      : PageRouteBuilder<void>(
          transitionDuration: duration,
          pageBuilder: (_, _, _) => page,
        );
  unawaited(navigator.currentState!.push(route));
  await tester.pump();
  // HeroController lays out the incoming page offstage before its first paint.
  await tester.pump();
  expect(find.byType(ForumThreadsPage), findsOneWidget);
  expect(
    ModalRoute.of(tester.element(find.byType(ForumThreadsPage))),
    same(route),
  );
  return route;
}

bool _categoriesEnabled(WidgetTester tester) =>
    tester
        .widget<ChromeGroup>(find.byType(ChromeGroup))
        .items
        .first
        .onPressed !=
    null;

Future<void> _finishEntry(WidgetTester tester, PageRoute<void> route) async {
  final animation = route.animation!;
  for (var frame = 0; frame < 60 && !animation.isCompleted; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(ThreadRow), findsNothing);
    expect(_categoriesEnabled(tester), isFalse);
  }
  expect(animation.isCompleted, isTrue);
}

void main() {
  testWidgets('forum response and categories wait for the frame after entry', (
    tester,
  ) async {
    final transport = _Transport();
    final repository = ForumRepository(
      ChhClient(fetchers: [transport], dispatchParser: parseForumInline),
    );
    final route = await _open(tester, repository);
    expect(route.animation!.status, AnimationStatus.forward);

    expect(transport.requests, 1);
    transport.deliver();
    await tester.pump(const Duration(milliseconds: 80));
    expect(route.animation!.status, AnimationStatus.forward);
    expect(find.byType(ThreadRow), findsNothing);
    expect(_categoriesEnabled(tester), isFalse);
    expect(transport.requests, 1);

    await _finishEntry(tester, route);
    final skeleton = find.byType(SkeletonList);
    final outgoing = tester.element(skeleton);
    await tester.pump();
    expect(find.byType(ThreadRow), findsWidgets);
    expect(_categoriesEnabled(tester), isTrue);
    expect(tester.element(skeleton), same(outgoing));
    final reveal = find.byType(ExpressivePageReveal);
    final fade =
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
    final initial = fade.value;
    expect(initial, allOf(greaterThan(0), lessThan(1)));
    final list = find.byType(ListView);
    int? rowCount() =>
        tester.widget<ListView>(list).childrenDelegate.estimatedChildCount;
    expect(rowCount(), 3);
    await tester.pump(AppMotion.loadingOut ~/ 2);
    expect(skeleton, findsOneWidget);
    expect(fade.value, greaterThan(initial));
    expect(rowCount(), 7);
    await tester.pumpAndSettle();
    expect(skeleton, findsNothing);
    expect(fade.value, 1);
  });

  testWidgets('quick forum entry fades rows without showing a skeleton', (
    tester,
  ) async {
    final transport = _Transport();
    final repository = ForumRepository(
      ChhClient(fetchers: [transport], dispatchParser: parseForumInline),
    );
    final route = await _open(
      tester,
      repository,
      duration: const Duration(milliseconds: 100),
    );
    expect(route.animation!.isAnimating, isTrue);
    await _finishEntry(tester, route);
    transport.deliver();
    await tester.pump();
    expect(find.byType(ThreadRow), findsWidgets);
    expect(find.byType(SkeletonList), findsNothing);
    final reveal = find.byType(ExpressivePageReveal);
    final fade =
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
    var progress = fade.value;
    expect(progress, allOf(greaterThan(0), lessThan(1)));
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(fade.value, greaterThanOrEqualTo(progress));
      expect(find.byType(SkeletonList), findsNothing);
      progress = fade.value;
    }
    expect(progress, 1);
  });

  testWidgets(
    'forum response after entry commits on its first available frame',
    (tester) async {
      final transport = _Transport();
      final repository = ForumRepository(
        ChhClient(fetchers: [transport], dispatchParser: parseForumInline),
      );
      final route = await _open(tester, repository);
      // The default spring used to keep the gate closed until about 750 ms.
      await tester.pump(const Duration(milliseconds: 480));
      expect(route.animation!.status, AnimationStatus.completed);
      final skeleton = find.byType(SkeletonList);
      final outgoing = tester.element(skeleton);
      expect(find.byType(ThreadRow), findsNothing);

      transport.deliver();
      await tester.pump();
      expect(find.byType(ThreadRow), findsWidgets);
      expect(tester.element(skeleton), same(outgoing));
      expect(_categoriesEnabled(tester), isTrue);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('forum response on the settle frame waits one frame', (
    tester,
  ) async {
    final transport = _Transport();
    final repository = ForumRepository(
      ChhClient(fetchers: [transport], dispatchParser: parseForumInline),
    );
    final route = await _open(tester, repository);
    route.animation!.addStatusListener((status) {
      if (status == AnimationStatus.completed) transport.deliver();
    });

    await _finishEntry(tester, route);
    await tester.pump();
    expect(find.byType(ThreadRow), findsWidgets);
    expect(_categoriesEnabled(tester), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'parsed forum cache shows rows and categories on route frame one',
    (tester) async {
      final transport = _Transport()..deliver();
      final repository = ForumRepository(
        ChhClient(fetchers: [transport], dispatchParser: parseForumInline),
      );
      final list = await repository.threadList(_fid);
      expect(repository.cachedThreadList(_fid), same(list));

      final route = await _open(tester, repository);
      expect(route.animation!.status, AnimationStatus.forward);
      expect(find.byType(ThreadRow), findsWidgets);
      expect(_categoriesEnabled(tester), isTrue);
      expect(transport.requests, 1);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'first list frame uses prepared groups and builds viewport rows only',
    (tester) async {
      final models = [
        for (var id = 0; id < 500; id++)
          ThreadSummary(
            tid: id,
            title: 'row-$id',
            author: 'author',
            replies: 0,
            views: 0,
            sticky: id < 2,
          ),
      ];
      final response = Paged(
        items: models,
        page: const PageInfo(current: 1, hasNext: false),
      );
      final firstPage = Completer<Paged<ThreadSummary>>();
      final labels = <int>[];
      final built = <int>{};
      var reopen = false;
      Widget list() => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 350,
            child: BrowseThreadList(
              collapsePinned: true,
              sectionLayoutKey: 'fixture-sections',
              cachedFirstPage: () => reopen ? response : null,
              loader: (page, {bool refresh = false}) => firstPage.future,
              sectionLabel: (row) {
                labels.add(row.tid);
                return row.tid < 20 ? '今天' : '更早';
              },
              itemBuilder: (_, row) {
                built.add(row.tid);
                return SizedBox(height: 100, child: Text(row.title));
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(list());
      expect(built, isEmpty);
      firstPage.complete(response);
      await tester.pump();
      expect(labels, [for (var id = 2; id < models.length; id++) id]);
      expect(find.byType(PinnedGroupRow), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      expect(built, {2, 3, 4});

      final view = tester.getRect(find.byType(ListView));
      for (final id in built) {
        expect(view.overlaps(tester.getRect(find.text('row-$id'))), isTrue);
      }

      await tester.pump();
      expect(built.length, greaterThan(3));
      expect(labels.length, 498);
      await tester.scrollUntilVisible(
        find.text('更早'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(find.text('更早').hitTestable(), findsWidgets);
      expect(labels.length, 498);

      await tester.pumpWidget(const SizedBox.shrink());
      reopen = true;
      built.clear();
      await tester.pumpWidget(list());
      expect(built, {2, 3, 4});
      expect(labels.length, 498);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'remembered expanded pins build viewport rows and collapse in place',
    (tester) async {
      final built = <int>{};
      final response = Paged(
        items: [
          for (var id = 0; id < 20; id++)
            ThreadSummary(
              tid: id,
              title: 'pinned-fixture-$id',
              author: 'author',
              replies: 0,
              views: 0,
              sticky: id < 12,
            ),
        ],
        page: const PageInfo(current: 1, hasNext: false),
      );
      Widget list() => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 350,
            child: BrowseThreadList(
              collapsePinned: true,
              pinnedMemoryKey: 'phase2-fixture',
              cachedFirstPage: () => response,
              loader: (page, {bool refresh = false}) async => response,
              itemBuilder: (_, row) {
                built.add(row.tid);
                return SizedBox(
                  height: 100,
                  child: Text(row.title, key: ValueKey('actual-${row.tid}')),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(list());
      await tester.tap(find.text('置顶'));
      await tester.pumpAndSettle();
      expect(built, contains(11));

      await tester.pumpWidget(const SizedBox.shrink());
      built.clear();
      await tester.pumpWidget(list());
      expect(built, {0, 1, 2, 3});
      final view = tester.getRect(find.byType(ListView));
      for (final id in built) {
        expect(
          view.overlaps(tester.getRect(find.byKey(ValueKey('actual-$id')))),
          isTrue,
        );
      }
      final first = find.byKey(const ValueKey('actual-0'));
      final firstRow = tester.element(first);
      final firstRect = tester.getRect(first);
      final group = find.byType(PinnedGroupRow);
      expect(tester.widget<PinnedGroupRow>(group).expanded, isTrue);

      await tester.tap(find.text('置顶'));
      await tester.pump();
      expect(tester.element(first), same(firstRow));
      expect(tester.getRect(first), firstRect);
      final startingHeight = tester.getSize(group).height;
      await tester.pump(const Duration(milliseconds: 120));
      final midwayHeight = tester.getSize(group).height;
      expect(midwayHeight, lessThan(startingHeight));
      await tester.pumpAndSettle();
      expect(tester.getSize(group).height, lessThan(midwayHeight));
      expect(first, findsNothing);
      expect(find.text('pinned-fixture-12'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
