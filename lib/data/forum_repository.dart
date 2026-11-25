/// 论坛域读操作:版块目录、帖子列表、帖子详情、导读流、搜索、标签
library;

import 'dart:async';

import 'package:html/parser.dart' as html;

import '../core/chh_urls.dart';
import '../core/md5.dart';
import '../network/chh_session.dart';
import '../network/cookie_jar.dart';
import '../parser/dom_utils.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/forum_index_parser.dart';
import '../parser/guide_parser.dart';
import '../parser/misc_parser.dart';
import '../parser/search_result_parser.dart';
import '../parser/thread_list_parser.dart';
import '../parser/background_parser.dart';
import 'follow_index.dart';

class ForumRepository {
  // Keep const repositories and let discarded clients release their parsed pages.
  static final _parsedThreads = Expando<_ParsedThreadPages>();
  final ChhClient client;
  final ChhSession? session;
  final FollowIndex? follows;
  const ForumRepository(this.client, {this.session, this.follows});

  void _sight(int? epoch, Iterable<ThreadSummary> threads) {
    final index = follows;
    if (index != null && index.epoch == epoch) {
      unawaited(index.sightThreads(threads));
    }
  }

  String? get cookiePrefix => session?.cookiePrefix;

  Future<void> unlockPost({
    required int pid,
    required String password,
    required String cookiePrefix,
  }) async {
    if (cookiePrefix.isEmpty) throw StateError('缺少 Cookie 前缀');
    await (session ?? ChhSession(client)).setSiteCookie(
      '${cookiePrefix}postpw_$pid',
      md5(password),
    );
  }

  Future<bool> verifyForumPassword(int fid, String password) async {
    final url = ChhUrls.threadList(fid);
    final page = await client.getHtml(url, refresh: true);
    final doc = html.parse(page);
    final form = doc.querySelector('form[action*="action=pwverify"]');
    if (form == null) return false;
    final action = url.resolve(form.attributes['action'] ?? '');
    // 密码只提交给站点实际给出的同站表单。
    if (action.origin != url.origin ||
        action.queryParameters['fid'] != '$fid') {
      return false;
    }
    final response = await client.postForm(action, {
      'formhash':
          form.querySelector('input[name="formhash"]')?.attributes['value'] ??
          '',
      'pw': password,
      'loginsubmit': 'true',
    });
    if (response.isBlocked || response.status >= 400) return false;
    final result = html.parse(response.body);
    if (result.querySelector('form[action*="action=pwverify"]') != null) {
      return false;
    }
    final message = detectPageMessage(result);
    if (message != null &&
        (message.kind != PageMessageKind.message ||
            !message.text.contains('成功'))) {
      return false;
    }
    final prefixes = [
      RegExp(r"cookiepre\s*=\s*'([^']*)'").firstMatch(page)?.group(1),
      RegExp(r"cookiepre\s*=\s*'([^']*)'").firstMatch(response.body)?.group(1),
      cookiePrefix,
    ];
    final prefix = prefixes
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .firstOrNull;
    if (prefix == null) throw StateError('缺少 Cookie 前缀');
    final name = '${prefix}fidpw$fid';
    String? value;
    for (final raw in response.setCookies) {
      final cookie = CookieJar.parseSetCookie(raw);
      if (cookie?.name == name) value = cookie!.value;
    }
    await (session ?? ChhSession(client)).setSiteCookie(
      name,
      value ?? Uri.encodeComponent(password),
    );
    return true;
  }

  Future<List<ForumCategory>> forumIndex({bool refresh = false}) async {
    return parseForumIndex(
      await client.getHtml(ChhUrls.forumIndex(), refresh: refresh),
    );
  }

  /// 版块帖子列表。typeid 走分类筛选,filter 走精华与排序。
  ///
  /// 越界页码会被站点静默回落到第 1 页,所以解析结果里的 current 才是真相。
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async {
    final followEpoch = follows?.epoch;
    final url = ChhUrls.threadListFiltered(
      fid,
      page: page,
      typeid: typeid,
      filter: filter,
      orderby: orderby,
    );
    final result = parseThreadList(
      await client.getHtml(url, refresh: refresh),
      forumFid: fid,
    );
    _sight(followEpoch, result.threads);
    return result;
  }

  /// 版块的分类标签。与帖子列表同一个页面,这里单独取一次供筛选条使用。
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async {
    final html = await client.getHtml(
      ChhUrls.threadList(fid),
      refresh: refresh,
    );
    return parseThreadTypes(html);
  }

  /// 缓存页可直接追加，无需等待下一次预加载时机。
  bool hasCachedThread(int tid, {int page = 1, String? authorUid}) =>
      client.hasCachedHtml(
        authorUid == null
            ? ChhUrls.thread(tid, page: page)
            : ChhUrls.threadByAuthor(tid, authorUid, page: page),
      );

  /// Only consecutive, unfiltered pages backed by live HTML cache entries
  /// can be used to decide where an incremental refresh starts.
  ({int lastPage, bool recent, int? replyCount, int? verifiedCountSequence})?
  cachedThreadCoverage(int tid, {int? observedReplies}) {
    final cache = _parsedThreads[client];
    if (cache == null || cache.generation != client.cacheGeneration) {
      return null;
    }
    ThreadDetail? last;
    var boundarySequence = 0;
    final counts = <int, int>{};
    final postIds = <int>{};
    var startsWithOpening = false;
    for (var page = 1; last?.page.hasNext ?? true; page++) {
      final url = ChhUrls.thread(tid, page: page);
      final entry = cache.pages[(url, tid, page)];
      final sequence = client.cachedHtmlSequence(url);
      if (entry == null || sequence == null || entry.$3 != sequence) break;
      final detail = entry.$2;
      if (detail.page.current != page || detail.posts.isEmpty) break;
      last = detail;
      boundarySequence = sequence;
      if (detail.replyCount case final count?) counts[sequence] = count;
      postIds.addAll(detail.posts.map((post) => post.pid));
      if (page == 1) {
        startsWithOpening = detail.posts.any(
          (post) => post.floorIsKnown && post.floor == 1,
        );
      }
    }
    if (last == null) return null;
    final countSequence = counts.keys
        .where((sequence) => sequence <= boundarySequence)
        .fold<int>(
          0,
          (latest, sequence) => sequence > latest ? sequence : latest,
        );
    final reportedCount = counts[countSequence];
    final loadedReplies = postIds.length - 1;
    // A tail page may omit statistics. A complete, unfiltered series can
    // confirm a newer list count or prove that an older total is too low.
    final confirmedCount =
        startsWithOpening &&
        !last.page.hasNext &&
        (reportedCount != null || observedReplies == loadedReplies) &&
        loadedReplies > (reportedCount ?? -1);
    return (
      lastPage: last.page.current,
      recent: client.isRecentHtml(ChhUrls.thread(tid, page: last.page.current)),
      replyCount: confirmedCount ? loadedReplies : reportedCount,
      verifiedCountSequence: confirmedCount ? boundarySequence : null,
    );
  }

  ThreadDetail? cachedThreadPage(int tid, int page) {
    final cache = _parsedThreads[client];
    if (cache == null || cache.generation != client.cacheGeneration) {
      return null;
    }
    final url = ChhUrls.thread(tid, page: page);
    final entry = cache.pages[(url, tid, page)];
    final sequence = client.cachedHtmlSequence(url);
    return entry != null && sequence != null && entry.$3 == sequence
        ? entry.$2
        : null;
  }

  int? cachedPageSequence(ThreadDetail page, {String? authorUid}) {
    final tid = page.tid;
    final number = page.page.current;
    final url = authorUid == null
        ? ChhUrls.thread(tid, page: number)
        : ChhUrls.threadByAuthor(tid, authorUid, page: number);
    final cache = _parsedThreads[client];
    if (cache == null || cache.generation != client.cacheGeneration) {
      return null;
    }
    final entry = cache.pages[(url, tid, number)];
    return entry != null && identical(entry.$2, page) ? entry.$3 : null;
  }

  void invalidateThread(int tid, {int fromPage = 1}) {
    client.invalidateThread(tid, fromPage: fromPage);
    _parsedThreads[client]?.pages.removeWhere((key, _) {
      final (url, cachedTid, page) = key;
      return cachedTid == tid &&
          (page >= fromPage || url != ChhUrls.thread(tid, page: page));
    });
  }

  /// 帖子详情。authorUid 非空即「只看作者」,页面结构与常规详情页全同构。
  Future<ThreadDetail> thread(
    int tid, {
    int page = 1,
    String? authorUid,
    bool refresh = false,
    bool Function()? shouldContinue,
  }) async {
    final url = authorUid == null
        ? ChhUrls.thread(tid, page: page)
        : ChhUrls.threadByAuthor(tid, authorUid, page: page);
    return _readThread(
      url,
      tid: tid,
      fallbackPage: page,
      refresh: refresh,
      shouldContinue: shouldContinue,
    );
  }

  /// 按站点给出的跳转地址取帖子
  ///
  /// 提醒里的 `goto=findpost&ptid=X&pid=Y` 会跳到目标楼层所在的那一页。
  /// 不要假设回复在第一页,也不能自己算页码 —— 跟随跳转,再以落地页的分页为准。
  Future<ThreadDetail> threadAtUrl(
    String url, {
    required int tid,
    bool refresh = false,
    bool Function()? shouldContinue,
  }) => _readThread(
    Uri.parse(url),
    tid: tid,
    fallbackPage: 1,
    refresh: refresh,
    shouldContinue: shouldContinue,
  );

  Future<ThreadDetail> _readThread(
    Uri url, {
    required int tid,
    required int fallbackPage,
    required bool refresh,
    bool Function()? shouldContinue,
  }) async {
    final generation = client.cacheGeneration;
    final threadRevision = client.threadCacheRevision(tid);
    final source = await client.getHtml(
      url,
      refresh: refresh,
      shouldContinue: shouldContinue,
    );
    if (shouldContinue?.call() == false) throw const ThreadReadCancelled();
    if (threadRevision != client.threadCacheRevision(tid)) {
      throw const ThreadReadCancelled();
    }
    // An old in-flight response must neither read nor replace the new session's cache.
    if (generation != client.cacheGeneration) {
      return parseThreadAsync(source, tid: tid, fallbackPage: fallbackPage);
    }
    var cache = _parsedThreads[client];
    if (cache == null || cache.generation != generation) {
      _parsedThreads[client] = cache = _ParsedThreadPages(generation);
    }
    final key = (url, tid, fallbackPage);
    final sequence = client.cachedHtmlSequence(url, matchingHtml: source);
    final previous = cache.pages[key];
    if (!refresh &&
        previous != null &&
        previous.$1 == source &&
        previous.$3 == sequence) {
      cache.pages.remove(key);
      cache.pages[key] = previous;
      return previous.$2;
    }
    final detail = await parseThreadAsync(
      source,
      tid: tid,
      fallbackPage: fallbackPage,
    );
    if (threadRevision != client.threadCacheRevision(tid)) {
      throw const ThreadReadCancelled();
    }
    if (generation == client.cacheGeneration &&
        sequence == client.cachedHtmlSequence(url)) {
      cache.remember(key, source, detail, sequence);
    }
    return detail;
  }

  /// 导读流。view=new / hot 游客可用,view=my 需登录,否则站点返回登录提示页。
  Future<ThreadListPage> guide({
    String view = 'new',
    String? type,
    int page = 1,
    bool refresh = false,
  }) async {
    final followEpoch = follows?.epoch;
    final html = await client.getHtml(
      ChhUrls.guide(view: view, type: type, page: page),
      refresh: refresh,
    );
    final result = parseGuide(html);
    _sight(followEpoch, result.threads);
    return result;
  }

  /// 搜索。站点先 302 到 searchid 页,由 fetcher 自动跟随。
  Future<SearchResultPage> search(
    String keyword, {
    bool refresh = false,
  }) async {
    final followEpoch = follows?.epoch;
    final result = parseSearchResult(
      await client.getHtml(ChhUrls.search(keyword), refresh: refresh),
    );
    _sight(followEpoch, result.rows);
    return result;
  }

  /// 翻页必须沿用站点给出的 nextUrl,它带着 searchid 与排序参数
  Future<SearchResultPage> searchNext(
    SearchResultPage prev, {
    bool refresh = false,
  }) async {
    final next = prev.nextUrl;
    if (next == null) return prev;
    final followEpoch = follows?.epoch;
    final result = parseSearchResult(
      await client.getHtml(Uri.parse(next), refresh: refresh),
    );
    _sight(followEpoch, result.rows);
    return result;
  }

  Future<Paged<ThreadSummary>> tag(int id, {bool refresh = false}) async {
    final followEpoch = follows?.epoch;
    final result = parseTagThreads(
      await client.getHtml(ChhUrls.tag(id), refresh: refresh),
    );
    _sight(followEpoch, result.items);
    return result;
  }
}

class _ParsedThreadPages {
  _ParsedThreadPages(this.generation);
  final int generation;
  final pages = <(Uri, int, int), (String, ThreadDetail, int?)>{};

  void remember(
    (Uri, int, int) key,
    String source,
    ThreadDetail detail,
    int? sequence,
  ) {
    if (source.length * 2 > (32 << 20)) return;
    pages.remove(key);
    pages[key] = (source, detail, sequence);
    var sourceBytes = pages.values.fold(
      0,
      (sum, entry) => sum + entry.$1.length * 2,
    );
    // Bound both ordinary 30-page reads and unusually large source documents.
    while (pages.length > 32 || sourceBytes > (32 << 20)) {
      sourceBytes -= pages.remove(pages.keys.first)!.$1.length * 2;
    }
  }
}
