import 'dart:async';
import 'dart:io';

import 'package:chh_app/data/editorial_cover_cache.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/pages/feed_page.dart';
import 'package:chh_app/ui/section_header.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/editorial_article_route.dart';
import 'package:chh_app/widgets/editorial_cover.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editorial_feature_cover_test.dart' show seedImage;

const _feature = PortalArticle(
  aid: 931001,
  title: '首页主精选',
  coverUrl: 'https://example.invalid/feed-navigation-cover.jpg',
);
const _community = PortalArticle(aid: 931002, title: '社区卡片');
const _review = PortalArticle(aid: 931003, title: '更多评测卡片');

class _Portal extends PortalRepository {
  _Portal() : super(ChhClient(fetchers: []));
  final opened = <int>[];
  Completer<PortalHighlights>? pendingHighlights;

  @override
  Future<PortalHighlights> highlights({bool refresh = false}) =>
      pendingHighlights?.future ??
      Future.value(
        const PortalHighlights(
          banners: [_community],
          reviews: [_feature, _review],
          news: [],
        ),
      );

  @override
  Future<PortalContent> openArticle(
    int aid, {
    int page = 1,
    bool refresh = false,
    bool fallback = true,
  }) async {
    opened.add(aid);
    return ArticleContent(
      ArticleDetail(
        aid: aid,
        title: '离线详情 $aid',
        content: [TextBlock('离线正文 $aid')],
        page: const PageInfo(current: 1, hasNext: false),
      ),
    );
  }
}

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));

  @override
  Future<ThreadListPage> guide({
    String view = 'new',
    String? type,
    int page = 1,
    bool refresh = false,
  }) async => const ThreadListPage(
    threads: [],
    page: PageInfo(current: 1, hasNext: false),
  );
}

class _NavigationLog extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  int replacements = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      replacements++;
}

class _MemoryCovers extends EditorialCoverCache {
  @override
  Future<void> load() async {}
}

void main() {
  testWidgets('discussion sort aligns with section action on the page grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final covers = _MemoryCovers();
    addTearDown(covers.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: FeedPage(
          portalRepository: _Portal(),
          forumRepository: _Forums(),
          coverCache: covers,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder header(String title) => find.widgetWithText(SectionHeader, title);
    final chevron = find.descendant(
      of: header('更多评测'),
      matching: find.byIcon(AppIcons.forward),
    );
    final sort = find.descendant(
      of: header('社区讨论'),
      matching: find.byType(AppSegmented<String>),
    );
    final title = find.descendant(
      of: header('社区讨论'),
      matching: find.text('社区讨论'),
    );
    expect(tester.getTopLeft(title).dx, AppSpace.screen);
    expect(tester.getTopRight(sort).dx, 390 - AppSpace.screen);
    expect(tester.getTopRight(chevron).dx, tester.getTopRight(sort).dx);
  });

  testWidgets('feed publishes pending work a frame after the reader exits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final covers = _MemoryCovers();
    await tester.runAsync(() => seedImage(_feature.coverUrl!, 800, 1000));
    addTearDown(covers.dispose);
    final portal = _Portal();
    final observer = _NavigationLog();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        theme: buildAppTheme(Brightness.light),
        home: FeedPage(
          portalRepository: portal,
          forumRepository: _Forums(),
          coverCache: covers,
        ),
      ),
    );
    await tester.pumpAndSettle();

    portal.pendingHighlights = Completer<PortalHighlights>();
    var refreshReturned = false;
    final refresh = tester
        .widget<LacquerTabScaffold>(find.byType(LacquerTabScaffold))
        .onRefresh!();
    unawaited(refresh.then((_) => refreshReturned = true));
    await tester.pump();
    await tester.ensureVisible(find.text(_community.title));
    await tester.tap(find.text(_community.title));
    await tester.pumpAndSettle();

    var readerExited = false;
    final reader = observer.pushed.last as TransitionRoute<void>;
    unawaited(reader.completed.then((_) => readerExited = true));
    navigator.currentState!.pop();
    await tester.pump();
    const nextFeature = PortalArticle(aid: 931004, title: '更新后的本期精选');
    portal.pendingHighlights!.complete(
      const PortalHighlights(
        banners: [_community],
        reviews: [nextFeature],
        news: [],
      ),
    );

    for (var frame = 0; !readerExited && frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text(nextFeature.title), findsNothing);
      expect(portal.opened, isNot(contains(nextFeature.aid)));
    }
    expect(readerExited, isTrue);
    expect(refreshReturned, isFalse);
    expect(find.text(_feature.title), findsOneWidget);

    await tester.pump();
    expect(refreshReturned, isTrue);
    expect(find.text(_feature.title), findsOneWidget);
    expect(portal.opened, isNot(contains(nextFeature.aid)));

    await tester.pumpAndSettle();
    expect(find.text(nextFeature.title), findsOneWidget);
    expect(find.text(_feature.title), findsNothing);
    expect(portal.opened.where((aid) => aid == nextFeature.aid), hasLength(1));
  });

  for (final article in [_feature, _community, _review]) {
    testWidgets('${article.title} uses one matching route from the real feed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory directory;
      late EditorialCoverCache covers;
      await tester.runAsync(() async {
        await seedImage(_feature.coverUrl!, 800, 1000);
        directory = await Directory.systemTemp.createTemp('feed-nav-covers-');
        covers = EditorialCoverCache.forTesting(
          File('${directory.path}/covers.json'),
        );
        await covers.load();
      });
      addTearDown(() async {
        covers.dispose();
        await directory.delete(recursive: true);
      });
      final portal = _Portal();
      final observer = _NavigationLog();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          theme: buildAppTheme(Brightness.light),
          home: FeedPage(
            portalRepository: portal,
            forumRepository: _Forums(),
            coverCache: covers,
          ),
        ),
      );
      await tester.pumpAndSettle();
      portal.opened.clear();
      await tester.ensureVisible(find.text(article.title));
      await tester.pumpAndSettle();
      final feedState = tester.state(find.byType(FeedPage));
      await tester.tap(find.text(article.title));
      await tester.pumpAndSettle();

      expect(portal.opened, [article.aid]);
      expect(find.text('离线正文 ${article.aid}'), findsOneWidget);
      expect(observer.pushed, hasLength(2));
      expect(observer.replacements, 0);
      final page = tester.widget<ArticlePage>(find.byType(ArticlePage));
      if (article == _feature) {
        expect(observer.pushed.last, isA<EditorialArticleRoute>());
        expect(page.heroTag, 'feed-feature-${article.aid}');
        expect(page.preview, same(_feature));
      } else {
        expect(observer.pushed.last, isA<MaterialPageRoute<void>>());
        expect(observer.pushed.last, isNot(isA<EditorialArticleRoute>()));
      }
      if (article == _community) {
        expect(page.preview, isNull);
        expect(
          find.descendant(
            of: find.byType(ArticlePage),
            matching: find.byType(EditorialCover),
          ),
          findsNothing,
        );
      }
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(FeedPage), findsOneWidget);
      expect(tester.state(find.byType(FeedPage)), same(feedState));
      expect(find.byType(ArticlePage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
