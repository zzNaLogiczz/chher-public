/// ChhClient:传输层门面 —— 获取器链(直连→WebView 降级)+ 短 TTL 缓存
///
/// 只负责「把 URL 变成 HTML」。页面解析与域编排在 lib/data/ 的各仓库里,
/// 这样换 UI 框架或上鸿蒙时这一层可以整体搬走。
library;

import '../core/app_log.dart';
import '../core/chh_urls.dart';
import 'chh_fetcher.dart';
import 'direct_fetcher.dart';
import 'file_fetcher.dart';
import 'webview_fetcher.dart';

class _CacheEntry {
  final DateTime at;
  final String html;
  _CacheEntry(this.html) : at = DateTime.now();
}

class ChhClient {
  final List<ChhFetcher> fetchers;
  final Duration cacheTtl;
  final _cache = <String, _CacheEntry>{};
  String? _lastFetcherName;

  ChhClient({
    List<ChhFetcher>? fetchers,
    this.cacheTtl = const Duration(seconds: 90),
  }) : fetchers = fetchers ?? [DirectFetcher(), WebViewFetcher()];

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

  /// 每次成功取到页面时的回调
  ///
  /// 用来顺带读页头的未读计数:走已有请求,不为了一个角标额外打扰站点。
  void Function(String html)? htmlObserver;

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
  }) async {
    final key = url.toString();
    if (!refresh) {
      final c = _cache[key];
      if (c != null && DateTime.now().difference(c.at) < cacheTtl) {
        htmlObserver?.call(c.html);
        return c.html;
      }
    }
    for (final f in fallback ? fetchers : fetchers.take(1)) {
      final resp = await f.getHtml(url, headers: {'Referer': ChhUrls.base});
      if (!resp.isBlocked) {
        _lastFetcherName = f.name;
        _cache[key] = _CacheEntry(resp.body);
        AppLog.i(
          'GET',
          '${f.name} ${AppLog.url(url)} '
              'status=${resp.status} len=${resp.body.length}',
        );
        htmlObserver?.call(resp.body);
        return resp.body;
      }
      AppLog.w(
        'GET',
        '${f.name} 被拦 ${AppLog.url(url)} '
            '${AppLog.response(resp.status, resp.body, head: 80)}',
      );
    }
    AppLog.e('GET', '所有通道都被拦 ${AppLog.url(url)}');
    throw ChhAllBlockedError(AppLog.url(url));
  }

  /// 表单提交:直连优先,被拦再降级 WebView
  ///
  /// 顺序和 GET 相反的理由:WebView 在安卓上会被站点防护当成移动端机器人,
  /// 回机器人挑战页,POST 体在挑战跳转中丢失。直连没有 Chromium 客户端提示,
  /// 反而能带着自洽的桌面请求头直达 PHP。
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    AppLog.i('POST', '${AppLog.url(url)} ${AppLog.fields(form)}');

    ChhResponse? last;
    for (final f in fetchers) {
      try {
        final resp = await f.postForm(url, form);
        last = resp;
        _lastFetcherName = f.name;
        // 写操作会改变站点状态,缓存里的旧页面全部作废
        _cache.clear();

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

  void clearCache() => _cache.clear();
}
