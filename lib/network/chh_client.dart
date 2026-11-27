/// ChhClient:传输层门面 —— 获取器链(直连→WebView 降级)+ 短 TTL 缓存
///
/// 保留每次读取的响应序号，并把版块列表的模型与对应 HTML 一起缓存。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import '../core/chh_urls.dart';
import '../parser/background_parser.dart';
import '../parser/get_page_parser.dart';
import '../parser/header_parser.dart';
import '../parser/parser_worker.dart';
import 'chh_fetcher.dart';
import 'direct_fetcher.dart';
import 'file_fetcher.dart';
import 'webview_fetcher.dart';

typedef _ThreadAddress = ({int? tid, int? page});
typedef _HtmlPage = ({String html, int sequence, ParsedForumList? forumList});

class _CacheEntry {
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final _HtmlPage page;
  String get html => page.html;
  int get sequence => page.sequence;
  _ThreadAddress? thread;
  _CacheEntry(this.page, this.fetchedAt, this.expiresAt, this.thread);
  int get bytes => html.length * 2;
}

class _ReadFlight {
  _ReadFlight(this.sequence, this.latestSuccessfulSequence);
  final int sequence;
  int latestSuccessfulSequence;
  final readers = <bool Function()?>[];
  bool get canContinue => readers.any((reader) => reader?.call() ?? true);
  late final Future<_HtmlPage> future;
}

class ThreadReadCancelled implements Exception {
  const ThreadReadCancelled();
}

class ChhClient {
  /// Keep rapid reading responsive while bounding serial source requests.
  static const defaultThreadRequestInterval = Duration(milliseconds: 300);

  final List<ChhFetcher> fetchers;
  final Duration cacheTtl;
  final Duration threadRequestInterval;
  final int maxCacheEntries;
  final int maxCacheBytes;
  final DateTime Function() now;
  final ParserDispatch _dispatchParser;
  ParserDispatch? _parserOverride;
  ParserDispatch get dispatchParser => _parserOverride ?? _dispatchParser;

  @visibleForTesting
  void setParserDispatchForTesting(ParserDispatch? dispatch) {
    _parserOverride = dispatch;
  }

  final headerFreshness = ValueNotifier<DateTime?>(null);
  int _freshHeaderRevision = 0;
  int get freshHeaderRevision => _freshHeaderRevision;
  DateTime? get lastFreshHeaderAt => headerFreshness.value;
  final _inFlight = <(int, String, bool, int, bool), _ReadFlight>{};
  int _cacheBytes = 0;
  final _cache = <String, _CacheEntry>{};
  String? _lastFetcherName;
  int _cacheGeneration = 0;

  /// Derived caches must not reuse data across session/write invalidation.
  int get cacheGeneration => _cacheGeneration;
  int _requestSequence = 0;
  final _threadCacheRevisions = <int, int>{};
  int _lastObservedHeaderSequence = 0;
  Future<void>? _threadTail;
  DateTime? _lastThreadReadAt;

  ChhClient({
    List<ChhFetcher>? fetchers,
    this.cacheTtl = const Duration(seconds: 90),
    this.maxCacheEntries = 128,
    this.maxCacheBytes = 64 << 20,
    this.threadRequestInterval = defaultThreadRequestInterval,
    ParserDispatch? dispatchParser,
    DateTime Function()? now,
  }) : assert(maxCacheEntries >= 0 && maxCacheBytes >= 0),
       _dispatchParser = dispatchParser ?? dispatchParserInWorker,
       now = now ?? DateTime.now,
       fetchers = fetchers ?? [DirectFetcher(), WebViewFetcher()];

  /// 默认客户端:--dart-define=chh_source=file 走离线样本,否则直连+WebView
  static ChhClient createDefault({String source = liveSource}) {
    if (source == 'file') {
      return ChhClient(fetchers: [FileFetcher()]);
    }
    return ChhClient();
  }

  static const String liveSource = String.fromEnvironment(
    'chh_source',
    defaultValue: 'live',
  );

  String? get lastFetcherName => _lastFetcherName;

  /// 每次成功取到新页面时的回调（缓存不重放旧未读计数）
  ///
  /// 用来顺带读页头账号与未读计数；会话失效前发出的请求不再回调。
  /// 返回 true 表示识别到页头，用于拦截并发请求反序到达的旧计数。
  bool Function(HeaderObservation observation)? headerObserver;

  /// Raw-response hook for transport and legacy session tests.
  @visibleForTesting
  bool Function(String html)? htmlObserver;

  /// WebView 引擎(登录 POST 等需要 Cookie 自动落仓的写操作专用)
  WebViewFetcher? get webviewFetcher =>
      fetchers.whereType<WebViewFetcher>().firstOrNull;

  /// 取页面。所有仓库与登录流程都走这里,缓存与降级在这一处收口。
  ///
  /// [fallback] 为 false 时只走第一条通道(直连),被拦即失败:后台预览这类可有可无的请求
  /// 不能去占用唯一的 WebView,也不该为它触发站点质询。
  Future<String> getHtml(
    Uri url, {
    bool refresh = false,
    bool fallback = true,
    bool Function()? shouldContinue,
  }) async => (await _getHtml(
    url,
    refresh: refresh,
    fallback: fallback,
    shouldContinue: shouldContinue,
  )).html;

  /// Both forum-list readers use the model attached to this exact response.
  Future<ParsedForumList> getForumList(Uri url, {bool refresh = false}) async {
    final page = await _getHtml(url, refresh: refresh);
    return page.forumList!;
  }

  ParsedForumList? cachedForumList(Uri url) {
    _pruneCache();
    final key = '$url';
    final entry = _cache[key];
    if (entry?.page.forumList == null) return null;
    _cache[key] = _cache.remove(key)!;
    return entry!.page.forumList;
  }

  Future<({String html, int sequence})> getThreadHtml(
    Uri url, {
    required bool refresh,
    bool Function()? shouldContinue,
  }) async {
    final page = await _getHtml(
      url,
      refresh: refresh,
      shouldContinue: shouldContinue,
      threadPage: true,
    );
    return (html: page.html, sequence: page.sequence);
  }

  bool hasCachedHtml(Uri url) => cachedHtmlSequence(url) != null;

  int? cachedHtmlSequence(
    Uri url, {
    String? matchingHtml,
    bool touch = false,
  }) {
    _pruneCache();
    final key = '$url';
    final entry = _cache[key];
    if (entry == null || (matchingHtml != null && entry.html != matchingHtml)) {
      return null;
    }
    if (touch) _cache[key] = _cache.remove(key)!;
    return entry.sequence;
  }

  bool isRecentHtml(Uri url) {
    final fetchedAt = _cache['$url']?.fetchedAt;
    return fetchedAt != null && now().difference(fetchedAt) < cacheTtl;
  }

  int threadCacheRevision(int tid) => _threadCacheRevisions[tid] ?? 0;

  void invalidateThread(int tid, {int fromPage = 1}) {
    _threadCacheRevisions[tid] = ++_requestSequence;
    final expired = _cache.entries
        .where((entry) {
          final thread = entry.value.thread;
          return thread != null &&
              thread.tid == tid &&
              (thread.page ?? fromPage) >= fromPage;
        })
        .map((entry) => entry.key)
        .toList();
    for (final key in expired) {
      _removeCached(key);
    }
  }

  void registerThreadAlias(Uri url, int tid, {String? matchingHtml}) {
    _pruneCache();
    final entry = _cache['$url'];
    if (entry == null || (matchingHtml != null && entry.html != matchingHtml)) {
      return;
    }
    if (entry.sequence <= threadCacheRevision(tid)) {
      _removeCached('$url');
    } else {
      entry.thread = (tid: tid, page: null);
    }
  }

  static final _threadPath = RegExp(r'^/thread-(\d+)-(\d+)-(\d+)\.html$');

  _ThreadAddress? _threadAddress(Uri url) {
    if (url.host != 'www.chiphell.com' && url.host != 'chiphell.com') {
      return null;
    }
    if (_threadPath.firstMatch(url.path) case final match?) {
      return (
        tid: int.tryParse(match[1]!),
        page: match[3] == '1' ? int.tryParse(match[2]!) : null,
      );
    }
    if (url.path != '/forum.php') return null;
    final params = url.queryParameters;
    final viewThread = params['mod'] == 'viewthread';
    final redirect =
        params['goto'] == 'findpost' || params['goto'] == 'lastpost';
    if (!viewThread && !redirect) return null;
    return (
      tid: int.tryParse(params['tid'] ?? params['ptid'] ?? ''),
      page: viewThread && !redirect && !params.containsKey('authorid')
          ? int.tryParse(params['page'] ?? '1')
          : null,
    );
  }

  /// Discuz interaction forms require an XMLHttpRequest-shaped GET.
  /// Keep its cached response separate from ordinary full-page HTML.
  Future<String> getAjaxHtml(Uri url, {bool refresh = false}) async =>
      (await _getHtml(url, refresh: refresh, ajax: true)).html;

  /// Read a standalone AJAX payload with the current transport cookies, without
  /// caching it, observing the header or recording response details in GET logs.
  Future<String?> readAjaxPayload(Uri url) async {
    final response = await fetchers.first.getHtml(
      url,
      headers: {'Referer': ChhUrls.base, 'X-Requested-With': 'XMLHttpRequest'},
    );
    return response.status == 200 ? response.body : null;
  }

  Future<_HtmlPage> _getHtml(
    Uri url, {
    bool refresh = false,
    bool fallback = true,
    bool ajax = false,
    bool threadPage = false,
    bool Function()? shouldContinue,
  }) {
    if (shouldContinue?.call() == false) {
      return Future.error(const ThreadReadCancelled());
    }
    final generation = _cacheGeneration;
    final key = '${ajax ? 'ajax:' : ''}$url';
    _pruneCache();
    final entry = _cache[key];
    if (!refresh && entry != null) {
      _cache.remove(key);
      _cache[key] = entry;
      return Future.value(entry.page);
    }
    final directThread = ajax ? null : _threadAddress(url);
    final thread = directThread ?? entry?.thread;
    final tid = thread?.tid;
    final revision = tid == null ? 0 : threadCacheRevision(tid);
    bool isCurrentThread() =>
        tid == null || threadCacheRevision(tid) == revision;
    final refreshThread = refresh && thread != null;
    final request = (generation, key, fallback, revision, refreshThread);
    final existing = _inFlight[request];
    if (existing != null &&
        existing.sequence >= existing.latestSuccessfulSequence) {
      existing.readers.add(shouldContinue);
      return existing.future;
    }
    final flight = _ReadFlight(++_requestSequence, entry?.sequence ?? 0);
    flight.readers.add(shouldContinue);
    _inFlight[request] = flight;
    Future<_HtmlPage> read() => _fetchHtml(
      url,
      key: key,
      generation: generation,
      fallback: fallback,
      ajax: ajax,
      threadPage: threadPage,
      thread: thread,
      threadTtl: directThread != null,
      refreshThread: refreshThread,
      isCurrentThread: isCurrentThread,
      flight: flight,
    );
    flight.future =
        (thread != null
                ? _readThread(
                    read,
                    key: key,
                    generation: generation,
                    refresh: refresh,
                    isCurrentThread: isCurrentThread,
                    flight: flight,
                  )
                : read())
            .whenComplete(() {
              if (identical(_inFlight[request], flight)) {
                _inFlight.remove(request);
              }
            });
    return flight.future;
  }

  Future<_HtmlPage> _readThread(
    Future<_HtmlPage> Function() read, {
    required String key,
    required int generation,
    required bool refresh,
    required bool Function() isCurrentThread,
    required _ReadFlight flight,
  }) async {
    final previous = _threadTail;
    final completed = Completer<void>();
    _threadTail = completed.future;
    var started = false;
    void checkActive() {
      if (generation != _cacheGeneration ||
          !isCurrentThread() ||
          !flight.canContinue) {
        throw const ThreadReadCancelled();
      }
    }

    try {
      if (previous != null) await previous;
      checkActive();
      _pruneCache();
      // Another transport policy may have filled this page while it queued.
      final cached = _cache[key];
      if (!refresh && cached != null) return cached.page;
      if (_lastThreadReadAt case final last?) {
        final remaining = threadRequestInterval - now().difference(last);
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      }
      checkActive();
      started = true;
      return await read();
    } finally {
      if (started) _lastThreadReadAt = now();
      completed.complete();
      if (identical(_threadTail, completed.future)) _threadTail = null;
    }
  }

  void _removeCached(String key) {
    final removed = _cache.remove(key);
    if (removed != null) _cacheBytes -= removed.bytes;
  }

  void _pruneCache() {
    final expired = _cache.entries
        .where((e) => !now().isBefore(e.value.expiresAt))
        .map((e) => e.key)
        .toList();
    for (final key in expired) {
      _removeCached(key);
    }
  }

  void _cacheHtml(
    String key,
    _HtmlPage page,
    DateTime fetchedAt, {
    required _ThreadAddress? thread,
    required bool threadTtl,
  }) {
    _pruneCache();
    _removeCached(key);
    final ttl = threadTtl ? const Duration(minutes: 30) : cacheTtl;
    final entry = _CacheEntry(page, fetchedAt, fetchedAt.add(ttl), thread);
    // UTF-16 is a conservative payload budget without allocating encoded copies.
    if (maxCacheEntries == 0 || entry.bytes > maxCacheBytes) return;
    _cache[key] = entry;
    _cacheBytes += entry.bytes;
    while (_cache.length > maxCacheEntries || _cacheBytes > maxCacheBytes) {
      _removeCached(_cache.keys.first);
    }
  }

  Future<_HtmlPage> _fetchHtml(
    Uri url, {
    required String key,
    required int generation,
    required bool fallback,
    required bool ajax,
    required bool threadPage,
    required _ThreadAddress? thread,
    required bool threadTtl,
    required bool refreshThread,
    required bool Function() isCurrentThread,
    required _ReadFlight flight,
  }) async {
    final sequence = flight.sequence;
    final fid =
        !ajax &&
            url.path == '/forum.php' &&
            url.queryParameters['mod'] == 'forumdisplay'
        ? int.tryParse(url.queryParameters['fid'] ?? '')
        : null;
    final failures = <String>[];
    var wafDetected = false;
    for (final f in fallback ? fetchers : fetchers.take(1)) {
      if (!flight.canContinue ||
          !isCurrentThread() ||
          (thread != null && generation != _cacheGeneration)) {
        throw const ThreadReadCancelled();
      }
      final resp = await f.getHtml(
        url,
        headers: {
          'Referer': ChhUrls.base,
          if (ajax) 'X-Requested-With': 'XMLHttpRequest',
          if (refreshThread) 'Cache-Control': 'no-cache',
        },
      );
      if (generation == _cacheGeneration && !isCurrentThread()) {
        throw const ThreadReadCancelled();
      }
      final fetchedAt = now();
      final input = (
        html: resp.body,
        status: resp.status,
        url: url,
        ajax: ajax,
        forumFid: fid,
        observeHeader:
            headerObserver != null &&
            resp.status == 200 &&
            generation == _cacheGeneration &&
            sequence >= _lastObservedHeaderSequence,
      );
      final inspected =
          fid != null || threadPage || thread != null || input.observeHeader
          ? await inspectGetPageAsync(input, dispatch: dispatchParser)
          : inspectGetPage(input);
      if (generation == _cacheGeneration && !isCurrentThread()) {
        throw const ThreadReadCancelled();
      }
      if (!inspected.blocked && inspected.rejection == null) {
        final page = (
          html: resp.body,
          sequence: sequence,
          forumList: inspected.forumList,
        );
        _lastFetcherName = f.name;
        if (generation == _cacheGeneration &&
            sequence >= flight.latestSuccessfulSequence &&
            sequence >= (_cache[key]?.sequence ?? 0)) {
          // Keep the ordering watermark on live readers, even after TTL/LRU eviction.
          for (final entry in _inFlight.entries) {
            if (entry.key.$1 == generation && entry.key.$2 == key) {
              entry.value.latestSuccessfulSequence = sequence;
            }
          }
          _cacheHtml(
            key,
            page,
            fetchedAt,
            thread: thread,
            threadTtl: threadTtl,
          );
        }
        AppLog.i(
          'GET',
          '${f.name} ${AppLog.url(url)} '
              'status=${resp.status} len=${resp.body.length} title=${AppLog.failureReason(inspected.title)}',
        );
        final header = inspected.header;
        if (resp.status == 200 &&
            generation == _cacheGeneration &&
            sequence >= _lastObservedHeaderSequence &&
            (header == null
                ? htmlObserver?.call(resp.body) == true
                : headerObserver?.call(header) == true)) {
          _lastObservedHeaderSequence = sequence;
          if (generation == _cacheGeneration) {
            _freshHeaderRevision++;
            headerFreshness.value = now();
          }
        }
        return page;
      }
      wafDetected = wafDetected || inspected.waf;
      final reason = resp.error == null ? '' : AppLog.failureReason(resp.error);
      failures.add('${f.name} status=${resp.status} error=$reason');
      AppLog.w(
        'GET',
        '${f.name} 被拦 ${AppLog.url(url)} '
            'status=${resp.status} len=${resp.body.length} '
            'title=${AppLog.failureReason(inspected.title)} reason=${inspected.rejection ?? 'blocked'} error=$reason',
      );
    }
    AppLog.e('GET', '所有通道失败 ${AppLog.url(url)} ${failures.join('; ')}');
    throw ChhAllBlockedError(
      AppLog.url(url),
      isConnectionFailure: !wafDetected,
    );
  }

  /// 表单提交:直连优先,被拦再降级 WebView
  ///
  /// 顺序和 GET 相反的理由:WebView 在安卓上会被站点防护当成移动端机器人,
  /// 回机器人挑战页,POST 体在挑战跳转中丢失。直连没有 Chromium 客户端提示,
  /// 反而能带着自洽的桌面请求头直达 PHP。
  Future<ChhResponse> postForm(
    Uri url,
    Map<String, String> form, {
    bool retryTransportFailures = true,
  }) => _postForm(url, form, retryTransportFailures: retryTransportFailures);

  Future<ChhResponse> postFormFields(
    Uri url,
    List<MapEntry<String, String>> fields, {
    bool retryTransportFailures = true,
  }) => _postForm(
    url,
    Map.fromEntries(fields),
    fields: fields,
    retryTransportFailures: retryTransportFailures,
  );

  Future<ChhResponse> postAjaxForm(
    Uri url,
    Map<String, String> form, {
    bool retryTransportFailures = true,
  }) => _postForm(
    url,
    form,
    ajax: true,
    retryTransportFailures: retryTransportFailures,
  );

  Future<ChhResponse> _postForm(
    Uri url,
    Map<String, String> form, {
    bool ajax = false,
    List<MapEntry<String, String>>? fields,
    bool retryTransportFailures = true,
  }) async {
    AppLog.i('POST', '${AppLog.url(url)} ${AppLog.fields(form)}');

    ChhResponse? last;
    for (final f in fetchers) {
      try {
        if (fields != null && f is! FormFieldsFetcher) continue;
        final resp = fields != null
            ? await (f as FormFieldsFetcher).postFormFields(url, fields)
            : ajax && f is AjaxFormFetcher
            ? await (f as AjaxFormFetcher).postAjaxForm(url, form)
            : await f.postForm(url, form);
        last = resp;
        _lastFetcherName = f.name;
        // 写操作会改变站点状态,缓存里的旧页面全部作废
        clearCache();

        if ((ajax || fields != null) &&
            resp.status >= 300 &&
            resp.status < 400) {
          return resp;
        }

        // 点评/评分无法确定超时请求是否已被受理，禁止换通道重放。
        if (!retryTransportFailures && resp.status <= 0) {
          return resp;
        }

        // 只有在**确定没被站点处理**时才换通道重试。
        // 拿到真实业务响应却重试,会造成重复发帖(站点回「两次发表间隔少于 N 秒」)。
        if (!resp.rejectedBeforeApp) {
          AppLog.i(
            'POST',
            '${f.name} ${AppLog.response(resp.status, resp.body)}',
          );
          return resp;
        }
        AppLog.w(
          'POST',
          '${f.name} 未进入站点逻辑,可安全换通道 '
              '${AppLog.response(resp.status, resp.body, head: 80)}',
        );
      } on UnsupportedError {
        // 这个通道不支持 POST,换下一个才是安全的
        continue;
      }
    }
    AppLog.e('POST', '提交未被受理 ${AppLog.url(url)}');
    return last ?? const ChhResponse(-1, '', error: '没有可用的提交通道');
  }

  /// 文件上传:只走支持 multipart 的通道,同样只在请求没进入站点时才换通道
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async {
    AppLog.i(
      'UPLOAD',
      '${AppLog.url(url)} ${file.filename} ${file.bytes.length}B ${file.contentType}',
    );
    ChhResponse? last;
    for (final f in fetchers) {
      try {
        final resp = await f.postMultipart(url, fields, file);
        last = resp;
        if (!resp.rejectedBeforeApp) {
          AppLog.i(
            'UPLOAD',
            '${f.name} ${AppLog.response(resp.status, resp.body)}',
          );
          return resp;
        }
        AppLog.w('UPLOAD', '${f.name} 未进入站点逻辑 ${resp.status}');
      } on UnsupportedError {
        continue;
      }
    }
    return last ?? const ChhResponse(-1, '', error: '没有可用的上传通道');
  }

  void clearCache() {
    _cacheGeneration++;
    _threadCacheRevisions.clear();
    _cache.clear();
    _cacheBytes = 0;
    _inFlight.clear();
    headerFreshness.value = null;
  }
}
