import 'dart:io';
import 'dart:ui';

import 'package:chh_app/data/editorial_cover_cache.dart';
import 'package:chh_app/data/featured_cover_prefetch.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePortalRepository extends PortalRepository {
  FakePortalRepository(this.result) : super(ChhClient(fetchers: []));
  final Future<PortalContent> Function() result;
  final calls = <(int, int)>[];
  @override
  Future<PortalContent> openArticle(
    int aid, {
    int page = 1,
    bool refresh = false,
    bool fallback = true,
  }) {
    calls.add((aid, page));
    return result();
  }
}

void main() {
  late Directory directory;
  late EditorialCoverCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('featured-cover-');
    cache = EditorialCoverCache.forTesting(
      File('${directory.path}/covers.json'),
    );
  });
  tearDown(() async {
    cache.dispose();
    await directory.delete(recursive: true);
  });
  const url = 'https://static.chiphell.com/portrait.jpg';
  const article = ArticleContent(
    ArticleDetail(
      aid: 42,
      title: '本地样例',
      content: [ImageBlock(url)],
      page: PageInfo(current: 1, hasNext: false),
    ),
  );

  test('cached cover does not request the article or image', () async {
    await cache.remember(42, url);
    final repo = FakePortalRepository(() async => article);
    final prefetch = FeaturedCoverPrefetch(
      repository: repo,
      cache: cache,
      imageSize: (_) => throw StateError('must not request image'),
    );
    await prefetch.fetch(42);
    expect(repo.calls, isEmpty);
  });

  test('persisted cover is loaded before making a request', () async {
    await File(
      '${directory.path}/covers.json',
    ).writeAsString('{"version":1,"covers":{"42":"$url"}}');
    final repo = FakePortalRepository(() async => article);
    final prefetch = FeaturedCoverPrefetch(
      repository: repo,
      cache: cache,
      imageSize: (_) => throw StateError('must not request image'),
    );
    await prefetch.fetch(42);
    expect(repo.calls, isEmpty);
    expect(cache.lookup(42), url);
  });

  test(
    'requests only page one once and adopts the first portrait image',
    () async {
      final repo = FakePortalRepository(() async => article);
      var images = 0;
      final prefetch = FeaturedCoverPrefetch(
        repository: repo,
        cache: cache,
        imageSize: (requested) async {
          images++;
          expect(requested, url);
          return const Size(1000, 900);
        },
      );
      await Future.wait([prefetch.fetch(42), prefetch.fetch(42)]);
      await prefetch.fetch(42);
      expect(repo.calls, [(42, 1)]);
      expect(images, 1);
      expect(cache.lookup(42), url);
    },
  );

  test(
    'landscape first image is rejected without looking for later images',
    () async {
      final repo = FakePortalRepository(
        () async => const ArticleContent(
          ArticleDetail(
            aid: 42,
            title: '本地样例',
            content: [
              ImageBlock(url),
              ImageBlock('https://static.chiphell.com/second.jpg'),
            ],
            page: PageInfo(current: 1, hasNext: false),
          ),
        ),
      );
      final prefetch = FeaturedCoverPrefetch(
        repository: repo,
        cache: cache,
        imageSize: (requested) async {
          expect(requested, url);
          return const Size(1000, 899);
        },
      );
      await prefetch.fetch(42);
      await prefetch.fetch(42);
      expect(cache.lookup(42), isNull);
      expect(repo.calls, [(42, 1)]);
      expect(FeaturedCoverPrefetch.isPortrait(const Size(0, 500)), isFalse);
    },
  );

  test('failure, login, no image and forum landing do not retry', () async {
    for (final result in <Future<PortalContent> Function()>[
      () async => throw StateError('offline'),
      () async =>
          throw const PageMessage(PageMessageKind.loginRequired, '请先登录'),
      () async => const ThreadContent(1, '帖子'),
      () async => const ArticleContent(
        ArticleDetail(
          aid: 42,
          title: '无图',
          content: [],
          page: PageInfo(current: 1, hasNext: false),
        ),
      ),
    ]) {
      final repo = FakePortalRepository(result);
      final prefetch = FeaturedCoverPrefetch(
        repository: repo,
        cache: cache,
        imageSize: (_) => throw StateError('no image request'),
      );
      await prefetch.fetch(42);
      await prefetch.fetch(42);
      expect(repo.calls, [(42, 1)]);
      expect(cache.lookup(42), isNull);
    }
  });
}
