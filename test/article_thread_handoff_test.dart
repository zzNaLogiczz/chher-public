import 'dart:async';
import 'dart:io';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/editorial_article_route.dart';
import 'package:chh_app/widgets/editorial_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'editorial_feature_cover_test.dart' show seedImage;

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
  @override
  String get name => 'offline-thread-handoff';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      ChhResponse(200, source);
}

Future<GlobalKey<NavigatorState>> _mount(
  WidgetTester tester,
  Future<PortalContent> Function() load, {
  bool reduceMotion = false,
  bool mainFeature = false,
  bool directDetail = false,
  _NavigationLog? observer,
}) async {
  if (mainFeature) {
    await tester.runAsync(() => seedImage(_cover.coverUrl!, 400, 600));
  }
  final previous = List<ChhFetcher>.of(chhClient.fetchers);
  chhClient.fetchers
    ..clear()
    ..add(_ThreadFetcher());
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
