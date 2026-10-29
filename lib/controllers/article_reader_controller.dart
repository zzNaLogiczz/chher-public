/// Reads the source site's real pages as one serial, append-only document.
library;

import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

typedef ArticlePageLoader =
    Future<PortalContent> Function(int page, bool refresh);

class ArticleContinuationException implements Exception {
  const ArticleContinuationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ArticleReaderController extends ChangeNotifier {
  ArticleReaderController({required this.loadPage});
  final ArticlePageLoader loadPage;
  final List<ArticleDetail> _pages = [];
  late final List<ArticleDetail> _pagesView = UnmodifiableListView(_pages);
  final Set<String> _signatures = {};
  bool _disposed = false;
  bool _loading = false;
  bool _hasNext = true;
  Object? _error;
  ThreadContent? _thread;

  List<ArticleDetail> get pages => _pagesView;
  bool get isLoading => _loading;
  bool get hasNext => _hasNext;
  Object? get error => _error;
  ThreadContent? get thread => _thread;

  /// Repeated viewport notifications never create concurrent or duplicate GETs.
  Future<void> loadNext() async {
    if (_disposed ||
        _loading ||
        !_hasNext ||
        _error != null ||
        _thread != null) {
      return;
    }
    await _request(refresh: false);
  }

  /// A network failure pauses automatic fetching until an explicit retry.
  Future<void> retry() async {
    if (_disposed || _loading || _error == null) return;
    await _request(refresh: true);
  }

  Future<void> _request({required bool refresh}) async {
    final requested = _pages.isEmpty ? 1 : _pages.last.page.current + 1;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final content = await loadPage(requested, refresh);
      if (_disposed) return;
      if (content is ThreadContent) {
        if (_pages.isNotEmpty) {
          throw const ArticleContinuationException('后续内容暂时无法读取');
        }
        _thread = content;
        _hasNext = false;
      } else {
        final article = (content as ArticleContent).detail;
        if (article.page.current != requested) {
          throw const ArticleContinuationException('源站返回了重复页，请稍后重试');
        }
        if (article.content.isEmpty) {
          throw const ArticleContinuationException('文章正文暂时无法读取');
        }
        final signature = _signature(article.content);
        if (!_signatures.add(signature)) {
          throw const ArticleContinuationException('源站返回了重复内容，请稍后重试');
        }
        _pages.add(article);
        _hasNext = article.page.hasNext;
      }
    } catch (error) {
      if (!_disposed) _error = error;
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  String _signature(List<ContentBlock> blocks) => blocks
      .map(
        (block) => switch (block) {
          TextBlock(:final text) => 't:${text.length}:$text',
          ImageBlock(:final url) => 'i:${url.length}:$url',
          QuoteBlock(:final children) => 'q:${_signature(children)}',
          SiteLinkBlock(:final target) => 's:${target.key}',
          BilibiliBlock(:final video) => 'v:${video.key}',
        },
      )
      .join('\n');

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
