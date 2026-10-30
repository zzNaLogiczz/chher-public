/// 登录会话:以 WebView Cookie 仓为唯一事实源
///
/// 登录在可见 WebView 里完成(处理"我不是人机"验证码),成功标志是
/// Discuz 的 auth Cookie(v2x4_48dd_auth)出现;本类负责:
///   - 轮询登录态 / 注入直连层 / 退出登录
///   - WebViewFetcher 与登录页共用同一 Cookie 仓,无需额外搬运
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import '../core/chh_urls.dart';
import '../parser/header_parser.dart';
import 'chh_client.dart';
import 'direct_fetcher.dart';

class ChhSession extends ChangeNotifier {
  final ChhClient client;
  bool loggedIn = false;
  Map<String, String> cookies = const {};
  int _epoch = 0;
  bool _initialRefreshComplete = false;

  /// 首次 Cookie 恢复与后续显式登录使用不同的收藏同步时机。
  bool get initialRefreshComplete => _initialRefreshComplete;
  static const _channel = MethodChannel('chh/session');

  /// 页头给出的未读计数
  ///
  /// 这是唯一可信的未读来源:站点自己算的数字。
  /// 不从列表 DOM 的类名推断未读,那个在文档里明确记载不可靠。
  HeaderBadges badges = const HeaderBadges(notices: 0, messages: 0);

  ChhSession(this.client);

  static const _authCookieSuffix = '_auth';

  /// 已登录但还不知道账号时,主动补一次
  ///
  /// 正常情况下页头观察会在第一次取页面时就带出账号。
  /// 这里是兜底:请求会命中 90 秒缓存,通常不产生额外流量。
  Future<void> ensureIdentity() async {
    if (!loggedIn || badges.userName != null) return;
    try {
      await client.getHtml(ChhUrls.forumIndex());
    } catch (e) {
      AppLog.w('BADGE', '补取账号失败 $e');
    }
  }

  /// 从任意一次页面响应里顺带更新未读计数
  ///
  /// 页面没有登录态页头时返回 null,这时保持原值不动 ——
  /// 否则打开一个游客页就会把未读抹掉。
  bool _warnedNoUser = false;
  bool _loggedFirstObservation = false;

  void observeHtml(String html) {
    final next = parseHeaderBadges(html);

    // 第一次观察无论结果如何都记一笔,用来判断这条链路到底有没有跑起来
    if (!_loggedFirstObservation) {
      _loggedFirstObservation = true;
      AppLog.i('BADGE', '首次观察 ${next == null ? '页面无登录态页头' : next.toString()}');
    }
    if (next == null) return;

    // 页头在但认不出账号:把页头摘要记一次,便于对照真实模板
    if (next.userName == null && !_warnedNoUser) {
      _warnedNoUser = true;
      AppLog.w('BADGE', '页头未识别出账号 ${next.headerSample ?? ''}');
    }
    if (next.userName != null) _warnedNoUser = false;

    if (next == badges) return;
    AppLog.i('BADGE', '页头变化 $badges → $next');
    badges = next;
    notifyListeners();
  }

  /// 从 WebView Cookie 仓同步登录态,并把登录 Cookie 注入直连层
  Future<void> refresh() async {
    final epoch = _epoch;
    final list = await CookieManager.instance().getCookies(
      url: WebUri(ChhUrls.base),
    );
    final map = <String, String>{};
    for (final c in list) {
      final v = c.value.toString();
      if (c.name.isNotEmpty && v.isNotEmpty) map[c.name] = v;
    }
    final hasAuth = map.keys.any(
      (k) => k.endsWith(_authCookieSuffix) && (map[k]?.isNotEmpty ?? false),
    );
    if (epoch != _epoch) return;
    if (hasAuth && !mapEquals(map, cookies)) await _flushCookies();
    if (epoch != _epoch) return;
    final direct = client.fetchers.whereType<DirectFetcher>().firstOrNull;
    if (direct != null) {
      // 游客态的会话 Cookie 同样要带:登录提交要求 formhash 与同会话 Cookie 配套,
      // 这里如果按登录态过滤,直连提交就会只带 formhash 而被判成 CSRF。
      direct.sessionCookies = map.isEmpty ? null : map;
    }
    if (hasAuth != loggedIn || map.length != cookies.length) {
      // 登录态变化时游客期的会话作废,清掉直连罐避免新旧会话混用
      if (hasAuth != loggedIn) {
        direct?.jar.clear();
        client.clearCache();
        AppLog.i('SESSION', hasAuth ? '登录态建立' : '登录态消失');
      }
      loggedIn = hasAuth;
      cookies = map;
      notifyListeners();
    } else {
      cookies = map;
    }
    _initialRefreshComplete = true;
  }

  /// 只从已知站点 Cookie 推断前缀，未建会话时不猜。
  String? get cookiePrefix {
    for (final suffix in ['saltkey', 'auth']) {
      for (final name in cookies.keys) {
        if (name.endsWith(suffix) && name.length > suffix.length) {
          return name.substring(0, name.length - suffix.length);
        }
      }
    }
    return null;
  }

  /// 解锁 Cookie 与登录共用持久仓，写入后立即同步到直连通道。
  Future<void> setSiteCookie(String name, String value) async {
    final epoch = _epoch;
    final written = await CookieManager.instance().setCookie(
      url: WebUri(ChhUrls.base),
      name: name,
      value: value,
      path: '/',
      expiresDate: DateTime.now()
          .add(const Duration(days: 30))
          .millisecondsSinceEpoch,
      isSecure: true,
    );
    if (!written || epoch != _epoch) {
      throw StateError('Cookie 未写入');
    }
    await _flushCookies();
    if (epoch != _epoch) throw StateError('会话已改变');
    client.clearCache();
    await refresh();
  }

  Future<void> _flushCookies() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod<void>('flushCookies');
    }
  }

  /// 退出登录
  ///
  /// 必须清得足够干净:只删 www.chiphell.com 下的 Cookie 不够,
  /// 站点还在 .chiphell.com 以及 localStorage 里留了账号痕迹,
  /// 残留会让下次登录自动填上一个账号,想换号都换不掉。
  Future<void> logout() async {
    _epoch++;
    final cm = CookieManager.instance();
    // 覆盖两种域写法,再兜底全量删除
    for (final url in [WebUri(ChhUrls.base), WebUri('https://chiphell.com')]) {
      await cm.deleteCookies(url: url);
      await cm.deleteCookies(url: url, domain: '.chiphell.com');
    }
    await cm.deleteAllCookies();
    await _flushCookies();

    // 站点把上次登录的账号留在 Web 存储里,不清就会自动回填
    try {
      await WebStorageManager.instance().deleteAllData();
    } catch (_) {
      // 平台不支持就算了,Cookie 已经清掉
    }

    client.clearCache();
    final direct = client.fetchers.whereType<DirectFetcher>().firstOrNull;
    direct
      ?..sessionCookies = null
      ..jar.clear();

    loggedIn = false;
    cookies = const {};
    badges = const HeaderBadges(notices: 0, messages: 0);
    AppLog.i('SESSION', '已退出,Cookie 与 Web 存储已清空');
    notifyListeners();
  }
}
