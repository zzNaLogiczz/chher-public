import 'dart:async';
import 'dart:io';

import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/ui/balanced_title.dart';
import 'package:chh_app/widgets/anchored_reading_list.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:chh_app/widgets/thread_landing.dart';
import 'package:chh_app/widgets/editorial_article_route.dart';
import 'package:chh_app/widgets/editorial_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'editorial_feature_cover_test.dart' show seedImage;

import 'support/inline_forum_parser.dart';

const _cover = PortalArticle(
  aid: 919001,
  title: '精选卡片',
  coverUrl: 'https://example.invalid/handoff-cover.jpg',
);
const _home = ValueKey('handoff-home');
const _open = ValueKey('handoff-open');

class _NavigationLog extends NavigatorObserver {
  int replacements = 0;
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      replacements++;
}

class _ThreadFetcher extends ChhFetcher {
  final source = File('test_data/thread_synthetic.html').readAsStringSync();
  final VoidCallback? onFetch;
  _ThreadFetcher([this.onFetch]);
  @override
  String get name => 'offline-thread-handoff';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    onFetch?.call();
    return ChhResponse(200, source);
  }
}

Future<GlobalKey<NavigatorState>> _mount(
  WidgetTester tester,
  Future<PortalContent> Function() load, {
  bool reduceMotion = false,
  bool mainFeature = false,
  bool directDetail = false,
  _NavigationLog? observer,
  VoidCallback? onThreadFetch,
}) async {
  if (mainFeature) {
    await tester.runAsync(() => seedImage(_cover.coverUrl!, 400, 600));
  }
  useInlineForumParser(chhClient);
  final previous = List<ChhFetcher>.of(chhClient.fetchers);
  chhClient.fetchers
    ..clear()
    ..add(_ThreadFetcher(onThreadFetch));
  chhClient.clearCache();
  addTearDown(() {
    chhClient.fetchers
      ..clear()
      ..addAll(previous);
    chhClient.clearCache();
  });
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      navigatorObservers: [?observer],
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        key: _home,
        body: Builder(
          builder: (context) => Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              key: _open,
              onTap: () {
                Widget destination(BuildContext context) => ArticlePage(
                  aid: _cover.aid,
                  title: _cover.title,
                  preview: directDetail ? null : _cover,
                  heroTag: 'handoff-cover',
                  eyebrow: mainFeature ? '本期精选' : null,
                  coverFit: mainFeature ? BoxFit.contain : BoxFit.cover,
                  loadPage: (_, _) => load(),
                );
                Navigator.of(context).push(
                  directDetail
                      ? MaterialPageRoute<void>(builder: destination)
                      : EditorialArticleRoute(
                          reduceMotion: reduceMotion,
                          builder: destination,
                        ),
                );
              },
              child: SizedBox(
                width: mainFeature ? 768 : 220,
                height: mainFeature ? HomeTokens.featureHeight(800) : 240,
                child: EditorialCover(
                  article: _cover,
                  heroTag: 'handoff-cover',
                  showText: mainFeature,
                  eyebrow: mainFeature ? '本期精选' : null,
                  fit: mainFeature ? BoxFit.contain : BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return key;
}

Future<void> _expectCleanHandoff(
  WidgetTester tester,
  GlobalKey<NavigatorState> nav,
) async {
  await tester.pumpAndSettle();
  expect(find.byType(ThreadDetailPage), findsOneWidget);
  expect(find.byType(ArticlePage), findsOneWidget);
  // The home card hides its text. This label exists only in the moving cover
  // and must disappear once the target thread takes over.
  expect(find.text('CHH 精选'), findsNothing);
  expect(tester.takeException(), isNull);
  nav.currentState!.pop();
  await tester.pumpAndSettle();
  expect(find.byKey(_home), findsOneWidget);
  expect(find.byType(ThreadDetailPage), findsNothing);
  expect(find.byType(ArticlePage), findsNothing);
  expect(find.text('CHH 精选'), findsNothing);
  expect(nav.currentState!.canPop(), isFalse);
}

void main() {
  testWidgets('A1 keeps the surface and back button across the landing fade', (
    tester,
  ) async {
    final result = Completer<PortalContent>();
    final detail = parseThread(
      File('test_data/thread_synthetic.html').readAsStringSync(),
      tid: 900001,
    );
    var threadRequests = 0;
    final log = _NavigationLog();
    await _mount(
      tester,
      () => result.future,
      directDetail: true,
      observer: log,
      onThreadFetch: () => threadRequests++,
    );
    await tester.tap(find.byKey(_open));
    await tester.pump();
    await tester.pump();

    final nav = find.byKey(const ValueKey('article-reader-nav'));
    final surface = find.byKey(const ValueKey('article-reader-surface'));
    final title = find.byType(BalancedTitle);
    final navWidget = tester.widget(nav);
    final navElement = tester.element(nav);
    final surfaceElement = tester.element(surface);
    final background = tester.widget<Scaffold>(surface).backgroundColor;
    expect(background, AppTokens.light.bg);
    expect(find.byIcon(AppIcons.back), findsOneWidget);
    expect(find.byIcon(AppIcons.dismiss), findsNothing);
    expect(tester.widget<BalancedTitle>(title).title, _cover.title);
    expect(
      tester
          .widget<ThreadLandingSkeleton>(find.byType(ThreadLandingSkeleton))
          .bars,
      isFalse,
    );

    await tester.pump(const Duration(milliseconds: 800));
    final titleOrigin = tester.getTopLeft(title);
    expect(
      tester
          .widget<ThreadLandingSkeleton>(find.byType(ThreadLandingSkeleton))
          .bars,
      isTrue,
    );
    result.complete(
      ThreadContent(
        detail.tid,
        detail.title,
        detail: detail,
        cacheGeneration: chhClient.cacheGeneration,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final fade = find
        .ancestor(
          of: find.byType(ThreadLandingSkeleton),
          matching: find.byType(FadeTransition),
        )
        .first;
    final firstContent = find
        .descendant(
          of: find.byType(AnchoredReadingList),
          matching: find.byType(ContentFade),
        )
        .first;
    final finalTitle = find.descendant(
      of: find.byType(AnchoredReadingList),
      matching: title,
    );
    expect(tester.getTopLeft(finalTitle), titleOrigin);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(tester.widget<ContentFade>(firstContent).opacity.value, 0);

    // A5 keeps the viewport lazy through the first arrival.
    final readingList = find.byType(AnchoredReadingList);
    expect(
      tester.widget<AnchoredReadingList>(readingList).scrollCacheExtent,
      isNotNull,
    );
    await tester.pump(AppMotion.skeletonFade);
    expect(tester.widget<FadeTransition>(fade).opacity.value, closeTo(0, .001));
    expect(tester.widget<ContentFade>(firstContent).opacity.value, lessThan(1));

    await tester.pumpAndSettle();
    expect(find.byType(ThreadLandingSkeleton), findsNothing);
    expect(
      tester.widget<AnchoredReadingList>(readingList).scrollCacheExtent,
      isNull,
    );
    expect(tester.widget(nav), same(navWidget));
    expect(tester.element(nav), same(navElement));
    expect(tester.element(surface), same(surfaceElement));
    expect(tester.widget<Scaffold>(surface).backgroundColor, background);
    expect(find.byIcon(AppIcons.back), findsOneWidget);
    expect(find.byIcon(AppIcons.dismiss), findsNothing);
    expect(log.pushes, 2);
    expect(log.replacements, 0);
    expect(threadRequests, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final delay in [Duration.zero, const Duration(milliseconds: 800)]) {
    testWidgets(
      'direct detail at $delay never mounts an article cover or replaces its route',
      (tester) async {
        final result = Completer<PortalContent>();
        final log = _NavigationLog();
        final nav = await _mount(
          tester,
          () => result.future,
          directDetail: true,
          observer: log,
        );
        await tester.tap(find.byKey(_open));
        await tester.pump();
        await tester.pump(delay);
        expect(
          find.descendant(
            of: find.byType(ArticlePage),
            matching: find.byType(EditorialCover),
          ),
          findsNothing,
        );
        result.complete(const ThreadContent(900001, '论坛原文'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(ThreadDetailPage), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ArticlePage),
            matching: find.byType(EditorialCover),
          ),
          findsNothing,
        );
        expect(log.replacements, 0);
        expect(log.pushes, 2);
        await _expectCleanHandoff(tester, nav);
      },
    );
  }

  testWidgets('cached thread redirect leaves no floating cover', (
    tester,
  ) async {
    final log = _NavigationLog();
    final nav = await _mount(
      tester,
      () async => const ThreadContent(900001, '论坛原文'),
      observer: log,
    );
    await tester.tap(find.byKey(_open));
    await tester.pump();
    await _expectCleanHandoff(tester, nav);
    expect(log.replacements, 0);
    expect(log.pushes, 2);
  });

  testWidgets('reduced motion redirect finishes without a cover overlay', (
    tester,
  ) async {
    final nav = await _mount(
      tester,
      () async => const ThreadContent(900001, '论坛原文'),
      reduceMotion: true,
    );
    await tester.tap(find.byKey(_open));
    await tester.pump();
    await _expectCleanHandoff(tester, nav);
  });

  for (final delay in [
    const Duration(milliseconds: 40),
    const Duration(milliseconds: 800),
  ]) {
    testWidgets('thread redirect at $delay cleans its Hero and route', (
      tester,
    ) async {
      final result = Completer<PortalContent>();
      final nav = await _mount(tester, () => result.future);
      await tester.tap(find.byKey(_open));
      await tester.pump();
      await tester.pump(delay);
      result.complete(const ThreadContent(900001, '论坛原文'));
      await tester.pump();
      await _expectCleanHandoff(tester, nav);
    });
  }

  testWidgets('reopening a redirected card never accumulates cover overlays', (
    tester,
  ) async {
    final nav = await _mount(
      tester,
      () async => const ThreadContent(900001, '论坛原文'),
    );
    for (var visit = 0; visit < 3; visit++) {
      await tester.tap(find.byKey(_open));
      await tester.pump();
      await _expectCleanHandoff(tester, nav);
    }
  });

  for (final delay in [
    Duration.zero,
    const Duration(milliseconds: 40),
    const Duration(milliseconds: 800),
  ]) {
    testWidgets(
      'main feature redirect after $delay leaves only the resting card',
      (tester) async {
        final result = Completer<PortalContent>();
        final nav = await _mount(
          tester,
          () => result.future,
          mainFeature: true,
        );
        expect(find.text('本期精选'), findsOneWidget);
        await tester.tap(find.byKey(_open));
        await tester.pump();
        await tester.pump(delay);
        result.complete(const ThreadContent(900001, '论坛原文'));
        await tester.pumpAndSettle();
        expect(find.text('本期精选'), findsNothing);
        await _expectCleanHandoff(tester, nav);
        expect(find.text('本期精选'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('editorial-feature-photo')),
          findsOneWidget,
        );
      },
    );
  }

  for (final delay in [
    const Duration(milliseconds: 40),
    const Duration(milliseconds: 800),
  ]) {
    testWidgets(
      'main feature normal article returns cleanly at $delay across repeated visits',
      (tester) async {
        final nav = await _mount(
          tester,
          () async => const ArticleContent(
            ArticleDetail(
              aid: 919001,
              title: '精选卡片',
              content: [TextBlock('离线文章正文')],
              page: PageInfo(current: 1, hasNext: false),
            ),
          ),
          mainFeature: true,
        );
        for (var visit = 0; visit < 3; visit++) {
          await tester.tap(find.byKey(_open));
          await tester.pump();
          await tester.pump(delay);
          nav.currentState!.pop();
          await tester.pumpAndSettle();
          expect(find.byKey(_home), findsOneWidget);
          expect(find.byType(ArticlePage), findsNothing);
          expect(find.byType(ThreadDetailPage), findsNothing);
          expect(find.text('本期精选'), findsOneWidget);
          expect(find.text('精选卡片'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('editorial-feature-photo')),
            findsOneWidget,
          );
          expect(nav.currentState!.canPop(), isFalse);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('main feature return flight keeps its decoded photo mounted', (
    tester,
  ) async {
    final nav = await _mount(
      tester,
      () async => const ArticleContent(
        ArticleDetail(
          aid: 919001,
          title: '精选卡片',
          content: [TextBlock('离线文章正文')],
          page: PageInfo(current: 1, hasNext: false),
        ),
      ),
      mainFeature: true,
    );
    await tester.tap(find.byKey(_open));
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump();
    final photos = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_FeaturePhoto',
    );
    expect(photos, findsOneWidget);
    final first = tester.state(photos);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.state(photos), same(first));
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
  });

  testWidgets('a redirect completing during back never reopens the thread', (
    tester,
  ) async {
    final result = Completer<PortalContent>();
    final nav = await _mount(tester, () => result.future);
    await tester.tap(find.byKey(_open));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    nav.currentState!.pop();
    result.complete(const ThreadContent(900001, '论坛原文'));
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
    expect(find.byType(ThreadDetailPage), findsNothing);
    expect(find.byType(ArticlePage), findsNothing);
    expect(find.text('CHH 精选'), findsNothing);
    expect(nav.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('covered article cannot replace an unrelated current route', (
    tester,
  ) async {
    final result = Completer<PortalContent>();
    final nav = await _mount(tester, () => result.future);
    await tester.tap(find.byKey(_open));
    await tester.pump();
    await tester.pumpAndSettle();
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('另一个页面')),
      ),
    );
    await tester.pumpAndSettle();
    result.complete(const ThreadContent(900001, '论坛原文'));
    await tester.pumpAndSettle();
    expect(find.text('另一个页面'), findsOneWidget);
    expect(find.byType(ThreadDetailPage), findsNothing);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    await _expectCleanHandoff(tester, nav);
  });
}
