import 'dart:ui' show Size;

import '../models/models.dart';
import 'editorial_cover_cache.dart';
import 'portal_repository.dart';

/// One attempt per featured article for this feed lifetime, including failures.
class FeaturedCoverPrefetch {
  final PortalRepository repository;
  final EditorialCoverCache cache;
  final Future<Size?> Function(String url) imageSize;
  final _attempted = <int>{};

  FeaturedCoverPrefetch({
    required this.repository,
    required this.cache,
    required this.imageSize,
  });

  static bool isPortrait(Size size) =>
      size.width.isFinite &&
      size.height.isFinite &&
      size.width > 0 &&
      size.height >= size.width * .9;

  Future<void> fetch(int aid) async {
    if (aid <= 0 || cache.lookup(aid) != null || !_attempted.add(aid)) return;
    try {
      await cache.load();
      if (cache.lookup(aid) != null) return;
      final content = await repository.openArticle(aid);
      if (content is! ArticleContent) return;
      final first = content.detail.content.whereType<ImageBlock>().firstOrNull;
      if (first == null) return;
      final size = await imageSize(first.url);
      if (size == null || !isPortrait(size)) return;
      // A foreground read can complete while the background request is pending.
      if (cache.lookup(aid) == null) await cache.remember(aid, first.url);
    } catch (_) {
      // Optional artwork never replaces content with an error or retries itself.
    }
  }
}
