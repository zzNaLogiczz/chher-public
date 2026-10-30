/// 直连获取器:dart:io TLS 栈(dio)
///
/// 注意:CHH 的 WAF 按 TLS/客户端指纹拦截(实测 curl 被拦、Node undici 通过)。
/// Dart HttpClient 的指纹能否通过需要真机实测 —— 被拦时由 ChhClient 自动降级到
/// WebViewFetcher,不需要手动切换。
library;

import 'package:dio/dio.dart';

import 'chh_fetcher.dart';
import 'cookie_jar.dart';
import '../core/app_log.dart';
import '../core/chh_urls.dart';

class DirectFetcher implements ChhFetcher {
  final Dio _dio;

  /// 登录态 Cookie(由 ChhSession 从 WebView Cookie 仓注入);为空时游客直连
  Map<String, String>? sessionCookies;

  /// 本通道自己的 Cookie 罐
  ///
  /// 之前没有这个罐,取登录页拿到的会话 Cookie 被直接丢掉,
  /// 提交时只带 formhash 不带会话,被站点判成 CSRF 并拒绝。
  final CookieJar jar = CookieJar();

  DirectFetcher({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              // 567 拦截页也要拿到 body 供判定
              validateStatus: (_) => true,
              headers: {
                'User-Agent': ChhUrls.chromeUa,
                'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
                'Accept-Language': 'zh-CN,zh;q=0.9',
                // 客户端提示必须与桌面 UA 自洽。实测站点的 EdgeOne 防护按请求头分流:
                // 提示说 Android 就回机器人挑战页,说 macOS 才放行到 PHP。
                // 这也是 WebView 做不到的事 —— Chromium 的提示由真实平台生成,改不掉。
                'sec-ch-ua': '"Chromium";v="155", "Not=A?Brand";v="24"',
                'sec-ch-ua-mobile': '?0',
                'sec-ch-ua-platform': '"macOS"',
              },
            ),
          );

  @override
  String get name => 'direct';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    try {
      final h = <String, String>{...?headers};
      _attachCookies(h);
      final r = await _dio.get<String>(
        url.toString(),
        options: h.isEmpty ? null : Options(headers: h),
      );
      // 会话 Cookie 就是在取页面时下发的,必须收下,后续提交要用
      final set = r.headers.map['set-cookie'] ?? const <String>[];
      jar.absorb(set);
      return ChhResponse(r.statusCode ?? 0, r.data ?? '', setCookies: set);
    } on DioException catch (e) {
      return ChhResponse(-1, '', error: _failureReason(e));
    }
  }

  /// 把 Cookie 罐与注入的登录态拼进请求头
  void _attachCookies(Map<String, String> h) {
    final merged = CookieJar()
      ..merge(jar.all)
      ..merge(sessionCookies ?? const {});
    final value = merged.header();
    if (value != null) h['Cookie'] = value;
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    try {
      final h = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': url.toString(),
      };
      _attachCookies(h);
      // 自己处理重定向:Discuz 写操作成功后常以 3xx 跳转,
      // 自动跟随会吃掉中间的 Set-Cookie,不跟随又只能拿到空响应。
      final r = await _dio.post<String>(
        url.toString(),
        data: form,
        options: Options(headers: h, followRedirects: false),
      );
      final set = r.headers.map['set-cookie'] ?? const <String>[];
      jar.absorb(set);

      final status = r.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        return await _followRedirect(
          url,
          r.headers.value('location'),
          set,
          status,
        );
      }
      return ChhResponse(status, r.data ?? '', setCookies: set);
    } on DioException catch (e) {
      return ChhResponse(-1, '', error: _failureReason(e));
    }
  }

  @override
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async {
    try {
      final h = <String, String>{'Referer': '${ChhUrls.base}/'};
      _attachCookies(h);
      final data = FormData.fromMap({
        ...fields,
        file.field: MultipartFile.fromBytes(
          file.bytes,
          filename: file.filename,
          contentType: DioMediaType.parse(file.contentType),
        ),
      });
      final r = await _dio.post<String>(
        url.toString(),
        data: data,
        options: Options(
          headers: h,
          followRedirects: false,
          // 大图在慢网络上要比读页面久
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 1),
        ),
      );
      final set = r.headers.map['set-cookie'] ?? const <String>[];
      jar.absorb(set);
      return ChhResponse(r.statusCode ?? 0, r.data ?? '', setCookies: set);
    } on DioException catch (e) {
      return ChhResponse(-1, '', error: _failureReason(e));
    }
  }

  String _failureReason(DioException e) {
    // 不调用 DioException.toString,它可能包含请求头与表单。
    var reason = '${e.type.name}: ${e.error ?? e.message}';
    final secrets = <String>{...jar.all.values, ...?sessionCookies?.values};
    for (final header in e.requestOptions.headers.entries) {
      if (header.key.toLowerCase() == 'cookie') {
        final cookie = header.value.toString();
        secrets.add(cookie);
        for (final entry in cookie.split(';')) {
          final equal = entry.indexOf('=');
          if (equal >= 0) secrets.add(entry.substring(equal + 1).trim());
        }
      }
    }
    final data = e.requestOptions.data;
    if (data is Map) secrets.addAll(data.values.map((value) => '$value'));
    if (data is FormData) {
      secrets.addAll(data.fields.map((entry) => entry.value));
    }
    // 先替换长值,避免子串替换留下敏感值的后半截。
    final ordered = secrets.where((value) => value.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final value in ordered) {
      reason = reason.replaceAll(value, '<redacted>');
    }
    return AppLog.failureReason(reason);
  }

  /// 跟随写操作后的跳转,把落地页当作这次提交的结果
  ///
  /// 跳转目标常是帖子页本身,正好用来判断提交是否生效。
  Future<ChhResponse> _followRedirect(
    Uri origin,
    String? location,
    List<String> set,
    int acceptedStatus,
  ) async {
    if (location == null || location.isEmpty) {
      // 有跳转但没给地址:已被受理,只是拿不到落地页
      return ChhResponse(acceptedStatus, '', setCookies: set);
    }
    final target = origin.resolve(location);
    final h = <String, String>{'Referer': origin.toString()};
    _attachCookies(h);
    final Response<String> r;
    try {
      r = await _dio.get<String>(
        target.toString(),
        options: Options(headers: h),
      );
    } on DioException catch (e) {
      // POST 已被受理,落地 GET 失败不能触发换通道重复提交。
      return ChhResponse(
        acceptedStatus,
        '',
        setCookies: set,
        error: _failureReason(e),
      );
    }
    final more = r.headers.map['set-cookie'] ?? const <String>[];
    jar.absorb(more);
    return ChhResponse(
      r.statusCode ?? 0,
      r.data ?? '',
      setCookies: [...set, ...more],
    );
  }

  @override
  Future<void> dispose() async {
    _dio.close();
  }
}
