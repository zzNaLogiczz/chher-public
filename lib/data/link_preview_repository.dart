/// 正文站内卡片的标题与时间
///
/// 卡片出现时才读,只读请求;同一页面里卡片可能有几十张(门户索引帖一楼 40 多个链接),
/// 所以限制并发、合并重复请求、缓存结果,失败也缓存一段时间,避免反复撞登录墙。
library;

import 'dart:async';
import 'dart:collection' show Queue;

import '../core/chh_urls.dart';
import '../core/link_target.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/archiver_parser.dart';
import 'portal_repository.dart';

class LinkPreview {
  final String title;
  final DateTime? time;

  /// 文章落到论坛帖时也是 true,卡片按帖子显示
  final bool isThread;

  const LinkPreview({required this.title, this.time, required this.isThread});
}

class LinkPreviewRepository {
  final Future<String> Function(Uri uri) fetchHtml;
  final Future<PortalContent> Function(int aid) openArticle;
  final DateTime Function() now;
  final int maxConcurrent;
  final int capacity;
  final Duration failureTtl;

  LinkPreviewRepository({
    required this.fetchHtml,
    required this.openArticle,
    DateTime Function()? now,
    this.maxConcurrent = 2,
    this.capacity = 200,
    this.failureTtl = const Duration(minutes: 5),
  }) : now = now ?? DateTime.now;

  factory LinkPreviewRepository.live(
    ChhClient client,
    PortalRepository portal,
  ) => LinkPreviewRepository(
    // 只走直连:被拦就算失败,不和正文争用 WebView,也不触发站点质询
    fetchHtml: (uri) => client.getHtml(uri, fallback: false),
    openArticle: (aid) => portal.openArticle(aid, fallback: false),
  );

  // Map 字面量按插入顺序迭代;命中时删掉重插,最久没用的就在最前面
  final _cache = <String, LinkPreview>{};
  final _failedAt = <String, DateTime>{};
  final _inFlight = <String, Future<LinkPreview?>>{};
  final _waiting = Queue<Completer<void>>();
  var _active = 0;

  /// 已缓存的结果,卡片首帧直接用,不闪读取态
  LinkPreview? cached(LinkTarget target) {
    final hit = _cache.remove(target.key);
    if (hit != null) _cache[target.key] = hit;
    return hit;
  }

  /// 最近失败过且还在冷却期内
  bool hasFailed(LinkTarget target) {
    final at = _failedAt[target.key];
    return at != null && now().difference(at) < failureTtl;
  }

  /// 取不到时返回 null(登录墙、无权限、已删除、网络失败都算)
  Future<LinkPreview?> preview(LinkTarget target) {
    final hit = cached(target);
    if (hit != null) return Future.value(hit);
    if (hasFailed(target)) return Future.value(null);
    final key = target.key;
    return _inFlight[key] ??=
        _load(
          target,
          // 块体回调:remove 返回的就是这个 Future,箭头函数会让它等待自己而永不完成
        ).whenComplete(() {
          _inFlight.remove(key);
        });
  }

  Future<LinkPreview?> _load(LinkTarget target) async {
    await _acquire();
    try {
      final result = await _read(target);
      // 读取成功清掉失败记录;结构不对与异常一样记为失败
      if (result == null) {
        _failedAt[target.key] = now();
      } else {
        _failedAt.remove(target.key);
        _remember(target.key, result);
      }
      return result;
    } catch (_) {
      _failedAt[target.key] = now();
      return null;
    } finally {
      _release();
    }
  }

  Future<LinkPreview?> _read(LinkTarget target) async {
    switch (target) {
      case ThreadLink(:final tid):
        final meta = parseArchiverThread(
          await fetchHtml(ChhUrls.archiverThread(tid)),
        );
        return meta == null
            ? null
            : LinkPreview(title: meta.title, time: meta.time, isThread: true);
      case ArticleLink(:final aid):
        return switch (await openArticle(aid)) {
          ArticleContent(:final detail) => LinkPreview(
            title: detail.title,
            time: ChhUrls.parseTime(detail.metaRaw ?? ''),
            isThread: false,
          ),
          // 落到论坛帖的文章只拿得到标题
          ThreadContent(:final title) => LinkPreview(
            title: title,
            isThread: true,
          ),
        };
      case BilibiliVideo() || OtherSiteLink() || ExternalLink():
        return null;
    }
  }

  void _remember(String key, LinkPreview value) {
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final slot = Completer<void>();
    _waiting.add(slot);
    await slot.future;
  }

  /// 有人排队就把名额直接交给下一个,否则归还
  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }
}
