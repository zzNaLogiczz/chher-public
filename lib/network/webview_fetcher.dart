/// 隐藏 WebView 获取器:保底路线
///
/// 用 HeadlessInAppWebView 以真实浏览器引擎加载页面(WAF 对真浏览器直接放行,
/// 见 chh-prototype 验证结论),然后执行 JS 抽出整页 HTML。质询跳转场景轮询等待。
/// Cookie 由 WebView 全局存储自动保持,与未来登录态共用。
library;

import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import 'chh_fetcher.dart';
import 'serial_queue.dart';
import 'webview_trust.dart';

class WebViewFetcher implements ChhFetcher {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  Completer<void>? _loadCompleter;
  bool _disposed = false;
  final _queue = SerialQueue();
  String? _lastError;
  ChhResponse? _lastBlockedResponse;
  bool _navigationFailed = false;

  void _recordError(String reason) {
    _lastError = AppLog.failureReason(reason);
    AppLog.w('WEBVIEW', _lastError!);
  }

  /// 原因只属于当前队列任务，不能把上一次加载的失败带给下一次。
  Future<ChhResponse> _enqueue(Future<ChhResponse> Function() task) =>
      _queue.run(() async {
        _lastError = null;
        _lastBlockedResponse = null;
        _navigationFailed = false;
        try {
          return await task();
        } finally {
          _loadCompleter = null;
        }
      });

  ChhResponse _failedResponse() => ChhResponse(
    _lastBlockedResponse?.status ?? -1,
    _lastBlockedResponse?.body ?? '',
    error: _lastError ?? '未能加载页面',
  );

  @override
  String get name => 'webview';

  Future<InAppWebViewController> _ensure() async {
    if (_disposed) throw StateError('WebViewFetcher disposed');
    final existing = _controller;
    if (existing != null) return existing;

    final created = Completer<InAppWebViewController>();
    final headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        incognito: false,
        // 桌面 UA:实测桌面 Chrome UA + 真浏览器 = 直接放行
        userAgent:
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36',
      ),
      onWebViewCreated: (c) {
        _controller = c;
        if (!created.isCompleted) created.complete(c);
      },
      // 重定向会多次触发 onLoadStop,重复 complete 会抛异常
      onLoadStop: (_, _) {
        final c = _loadCompleter;
        if (c != null && !c.isCompleted) c.complete();
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame == false) return;
        _navigationFailed = true;
        _recordError('${error.type}: ${error.description}');
        final c = _loadCompleter;
        if (c != null && !c.isCompleted) c.complete();
      },
      onReceivedHttpError: (_, request, response) {
        if (request.isForMainFrame == false) return;
        _recordError('HTTP ${response.statusCode}');
        if (response.statusCode == 567) {
          _lastBlockedResponse = const ChhResponse(567, '');
        }
      },
      onReceivedServerTrustAuthRequest: (_, challenge) =>
          handleServerTrustChallenge(challenge, onResult: _recordError),
    );
    _headless = headless;
    await headless.run();
    return created.future.timeout(const Duration(seconds: 10));
  }

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) =>
      _enqueue(() => _getHtml(url));

  Future<ChhResponse> _getHtml(Uri url) async {
    final controller = await _ensure();

    for (var attempt = 0; attempt < 2; attempt++) {
      _navigationFailed = false;
      _loadCompleter = Completer<void>();
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(url)));
      try {
        await _loadCompleter!.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        _recordError('页面加载超时');
        continue;
      }
      if (_navigationFailed) return _failedResponse();

      // WAF 质询页(标题"Loading …"/"请求已被拦截")会自动跳转,轮询等待稳定
      for (var i = 0; i < 6; i++) {
        final title =
            (await controller.evaluateJavascript(
              source: 'document.title',
            ))?.toString() ??
            '';
        final html =
            (await controller.evaluateJavascript(
              source: 'document.documentElement.outerHTML',
            ))?.toString() ??
            '';
        final resp = ChhResponse(200, html);
        // 质询标题本身不够判定拦截，仍须保留页面里的 WAF 特征。
        if (resp.hasWafFeatures) _lastBlockedResponse = resp;
        if (title.isNotEmpty &&
            !title.toLowerCase().contains('loading') &&
            !title.contains('拦截')) {
          if (!resp.isBlocked) return resp;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }
    return _failedResponse();
  }

  /// 把隐藏 WebView 的文档落到目标站点域上
  ///
  /// postForm 里的 fetch 必须是**同源**请求:从 about:blank 发出的跨域带凭证请求
  /// 会被浏览器直接拒掉(Discuz 不返回 CORS 头),表现为提交永远失败。
  /// 之前能登录纯属偶然——只有当 GET 因为直连被拦而降级到 WebView 时,
  /// 文档才顺带落在了站点域上。
  Future<void> _ensureOrigin(InAppWebViewController controller, Uri url) async {
    final target = '${url.scheme}://${url.host}';
    final current =
        (await controller.evaluateJavascript(
          source: 'location.origin',
        ))?.toString() ??
        '';
    if (current == target) return;

    _loadCompleter = Completer<void>();
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri('$target/')));
    try {
      await _loadCompleter!.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _recordError('页面加载超时');
      // 落不到站点域就让 fetch 自己报错,错误原因会带回调用方
    }
  }

  /// 隐藏页面拿不到本地文件,上传只能走直连
  @override
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async {
    throw UnsupportedError('$name 不支持上传文件');
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) =>
      _enqueue(() => _postForm(url, form));

  Future<ChhResponse> _postForm(Uri url, Map<String, String> form) async {
    final controller = await _ensure();
    await _ensureOrigin(controller, url);
    if (_navigationFailed) return _failedResponse();

    // 用真表单提交到隐藏 iframe,而不是 fetch
    //
    // 站点自己的登录表单 onsubmit 走 Discuz 的 ajaxpost:把 target 指向隐藏 iframe,
    // action 追加 inajax=1,再 form.submit() —— 是一次**导航**请求。
    // 换成 fetch 后请求形态变了(带 Origin、Sec-Fetch-Mode: cors),站点防护会判成可疑,
    // 回 Discuz 的 request_tainting(503「含有非法字符」),字段再干净也没用。
    // 这里完全照抄浏览器的做法,同源所以能直接读回 iframe 文档。
    final result = await controller.callAsyncJavaScript(
      arguments: {'url': url.toString(), 'fields': form},
      functionBody: r"""
        const name = 'chhpost_' + Date.now();
        const frame = document.createElement('iframe');
        frame.name = name;
        frame.style.display = 'none';
        document.body.appendChild(frame);

        const f = document.createElement('form');
        f.method = 'POST';
        f.action = url;
        f.target = name;
        f.acceptCharset = 'utf-8';
        for (const k in fields) {
          const i = document.createElement('input');
          i.type = 'hidden';
          i.name = k;
          i.value = fields[k];
          f.appendChild(i);
        }
        document.body.appendChild(f);

        const done = new Promise((resolve) => {
          frame.onload = () => {
            let href = '';
            try { href = frame.contentWindow.location.href; } catch (e) { href = 'cross'; }
            // 新建 iframe 会先为 about:blank 触发一次 load,要跳过
            if (href === 'about:blank') return;
            try {
              resolve(frame.contentDocument.documentElement.outerHTML);
            } catch (e) {
              resolve('');
            }
          };
          setTimeout(() => resolve(''), 20000);
        });

        f.submit();
        const html = await done;
        f.remove();
        frame.remove();
        return {status: html ? 200 : 0, text: html};
      """,
    );

    final value = result?.value;
    if (value is Map) {
      final text = (value['text'] ?? '').toString();
      if (text.isNotEmpty) {
        return ChhResponse((value['status'] as num?)?.toInt() ?? 200, text);
      }
      _lastError ??= '提交后没有读到响应文档';
      return _failedResponse();
    }
    // 引擎内异常要把原文带回去,不能吞成空响应
    final err = result?.error;
    if (err != null && err.isNotEmpty) _recordError(err);
    _lastError ??= '引擎未返回响应';
    return _failedResponse();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _controller = null;
    await _headless?.dispose();
    _headless = null;
  }
}
