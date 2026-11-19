import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/feed_page.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/chhers_loader.dart';
import 'package:chh_app/widgets/reading_list_end.dart';
import 'package:chh_app/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Portal extends PortalRepository {
  _Portal() : super(ChhClient(fetchers: []));

  @override
  Future<PortalHighlights> highlights({bool refresh = false}) async =>
      PortalHighlights.empty;
}

class _Discussion extends ForumRepository {
  _Discussion() : super(ChhClient(fetchers: []));

  @override
  Future<ThreadListPage> guide({
    String view = 'new',
    String? type,
    int page = 1,
    bool refresh = false,
  }) async => ThreadListPage(
    threads: [
      for (var i = 1; i <= 40; i++)
        ThreadSummary(
          tid: i,
          title: '主题 $i',
          author: '作者 $i',
          replies: 2,
          views: 0,
        ),
    ],
    page: const PageInfo(current: 1, hasNext: false),
  );
}

Future<void> _mount(WidgetTester tester, double bottomPadding) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: bottomPadding);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: HomePage(
        initialiseSession: () async {},
        screenBuilders: {
          AppDestination.feed: (_) => FeedPage(
            portalRepository: _Portal(),
            forumRepository: _Discussion(),
          ),
          AppDestination.forums: (_) => ForumIndexView(
            loadForums: (_) async => [
              ForumCategory(
                name: '硬件',
                forums: [
                  for (var i = 1; i <= 40; i++) Forum(fid: i, name: '测试版块 $i'),
                ],
              ),
            ],
          ),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _bottom(WidgetTester tester, Finder lastItem) async {
  final list = find.byType(CustomScrollView);
  await tester.scrollUntilVisible(
    lastItem,
    400,
    scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
  );
  final position = tester.widget<CustomScrollView>(list).controller!.position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
  expect(position.extentAfter, closeTo(0, .01));
}

double _cardBottom(WidgetTester tester, Finder finder) {
  final sliver = tester.renderObject<RenderSliver>(finder);
  return MatrixUtils.transformPoint(
    sliver.getTransformTo(null),
    sliver.paintBounds.bottomLeft,
  ).dy;
}

void main() {
  for (final footer in const [
    ListFooter(loading: true),
    ReadingListEnd(loading: true),
  ]) {
    testWidgets('${footer.runtimeType} centers the accessible M wordmark', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [footer],
            ),
          ),
        ),
      );
      await tester.pump(AppMotion.loadingDelay);
      await tester.pump(AppMotion.loadingIn);

      final loader = find.byType(ChhersLoader);
      final mark = tester.widget<ChhersLoader>(loader);
      expect(mark.size, ChhersLoaderSize.list);
      expect(mark.size.height, 14);
      expect(mark.size.stroke, 2);
      expect(
        tester.getCenter(loader).dx,
        tester.getCenter(find.byWidget(footer)).dx,
      );
      expect(find.text('正在加载'), findsNothing);
      expect(find.text('正在加载更多'), findsNothing);
      expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
      semantics.dispose();
    });
  }

  for (final bottom in [0.0, 34.0]) {
    testWidgets('community end spaces its label and navigation ($bottom)', (
      tester,
    ) async {
      await _mount(tester, bottom);
      final lastMetadata = find.text('作者 40');
      await _bottom(tester, lastMetadata);
      final cardBottom = _cardBottom(
        tester,
        find.byKey(const ValueKey('feed-discussion-card')),
      );
      final marker = tester.getRect(find.text('没有更多了'));
      final navigation = tester.getRect(find.byType(AppBottomNavigation));
      expect(
        marker.top - tester.getBottomLeft(lastMetadata).dy,
        closeTo(24, .01),
      );
      expect(cardBottom - marker.bottom, closeTo(24, .01));
      expect(navigation.top - cardBottom, closeTo(16, .01));
      expect(navigation.height, closeTo(68 + bottom, .01));
    });

    testWidgets('forum directory ends one gap above navigation ($bottom)', (
      tester,
    ) async {
      await _mount(tester, bottom);
      final navigationFinder = find.byType(AppBottomNavigation);
      await tester.tap(
        find.descendant(of: navigationFinder, matching: find.text('版块')),
      );
      await tester.pumpAndSettle();
      final lastRow = find.byKey(const ValueKey('forum-row-40'));
      await _bottom(tester, lastRow);
      final navigation = tester.getRect(navigationFinder);
      final cardBottom = _cardBottom(tester, find.byType(DecoratedSliver));
      expect(navigation.top - cardBottom, closeTo(16, .01));
      expect(tester.getBottomLeft(lastRow).dy, lessThanOrEqualTo(cardBottom));
      expect(navigation.height, closeTo(68 + bottom, .01));
    });
  }
}
