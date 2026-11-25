/// 登录会话:以 WebView Cookie 仓为唯一事实源
///
/// 登录在可见 WebView 里完成(处理"我不是人机"验证码),成功标志是
/// Discuz 的 auth Cookie(v2x4_48dd_auth)出现;本类负责:
///   - 轮询登录态 / 注入直连层 / 退出登录
///   - WebViewFetcher 与登录页共用同一 Cookie 仓,无需额外搬运
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/accounts.dart';
import '../core/app_log.dart';
import '../core/chh_urls.dart';
import '../models/models.dart';
import '../parser/header_parser.dart';
import 'account_header.dart';
import 'chh_client.dart';
import 'direct_fetcher.dart';

enum AccountSwitchResult { success, expired, failed }

enum _AccountLogin { pending, adopting }

class ChhSession extends ChangeNotifier {
  final ChhClient client;
  bool loggedIn = false;
  Map<String, String> cookies = const {};
  int _epoch = 0;
  int _identityRevision = 0;
  int _authenticationRevision = 0;

  /// Changes on logout, auth replacement or account change, even for the same UID.
  /// Draft keys still use the stable UID; only in-flight forms use this revision.
  int get identityRevision => _identityRevision;

  /// New account-backed lists reset on auth changes, not late header hydration.
  int get authenticationRevision => _authenticationRevision;
  bool _initialRefreshComplete = false;

  /// 首次 Cookie 恢复与后续显式登录使用不同的收藏同步时机。
  bool get initialRefreshComplete => _initialRefreshComplete;
  static const _channel = MethodChannel('chh/session');

  HeaderBadges _headerBadges = _emptyBadges;
  Set<String>? _unreadPmIds;
  int _pmRevision = 0;

  int get pmRevision => _pmRevision;
  bool get pmHasCount => _unreadPmIds != null;
  bool get needsPmSupplement =>
      _headerBadges.pmPrompt && (_unreadPmIds?.isEmpty ?? true);

  /// 提醒沿用页头，私信优先使用未读会话数。
  HeaderBadges get badges {
    final ids = _unreadPmIds;
    if (ids == null) return _headerBadges;
    return HeaderBadges(
      notices: _headerBadges.notices,
      messages: ids.length,
      userName: _headerBadges.userName,
      uid: _headerBadges.uid,
      avatarSrc: _headerBadges.avatarSrc,
      headerSample: _headerBadges.headerSample,
    );
  }

  set badges(HeaderBadges value) {
    _headerBadges = value;
    _unreadPmIds = null;
    _pmRevision++;
  }

  void setUnreadPmIds(Set<String>? ids) {
    _pmRevision++;
    if (setEquals(_unreadPmIds, ids)) return;
    _unreadPmIds = ids == null ? null : Set.of(ids);
    notifyListeners();
  }

  void updatePmList(
    Paged<PmConversation> result, {
    required int page,
    Set<String> locallyRead = const {},
  }) {
    final ids = <String>{
      if (page != 1 || result.page.hasNext) ...?_unreadPmIds,
    };
    // A partial page only establishes the state of the rows it returned.
    for (final item in result.items) {
      if (item.unread && !locallyRead.contains(item.id)) {
        ids.add(item.id);
      } else {
        ids.remove(item.id);
      }
    }
    setUnreadPmIds(ids);
  }

  void markPmRead(String plid) {
    final ids = _unreadPmIds;
    setUnreadPmIds(ids == null ? null : (Set.of(ids)..remove(plid)));
  }

  ChhSession(this.client, {this.accounts});

  final AccountStore? accounts;
  bool _accountOperation = false;
  bool get accountOperationInProgress =>
      _accountOperation || _accountLogin != null;
  bool _holdIdentity = false;
  _AccountLogin? _accountLogin;
  bool get adoptingAccountLogin => _accountLogin == _AccountLogin.adopting;
  String? _previousLoginUid;
  String? _expiredUid;
  bool _currentExpired = false;
  bool get currentExpired => _currentExpired;

  (int, String, String)? _savedIdentity;
  Future<void>? _identitySave;

  static const _emptyBadges = HeaderBadges(notices: 0, messages: 0);

  static const _authCookieSuffix = '_auth';

  /// 已登录但还不知道账号时,主动补一次
  ///
  /// 正常情况下页头观察会在第一次取页面时就带出账号。
  /// 这里是兜底:请求会命中 90 秒缓存,通常不产生额外流量。
  Future<void> ensureIdentity({bool verify = false}) async {
    if (!loggedIn) return;
    if (!verify && badges.uid != null && badges.userName != null) {
      await _identitySave;
      return;
    }
    try {
      await client.getHtml(ChhUrls.forumIndex());
    } catch (e) {
      AppLog.w('BADGE', '补取账号失败 ${e.runtimeType}');
    }
    await _identitySave;
  }

  /// 从任意一次页面响应里顺带更新未读计数
  ///
  /// 页面没有登录态页头时返回 null,这时保持原值不动 ——
  /// 否则打开一个游客页就会把未读抹掉。
  bool _warnedNoUser = false;
  bool _loggedFirstObservation = false;

  /// 是否识别到页头；计数未变化也返回 true，阻止更旧的请求覆盖。
  bool observeHtml(String html) {
    if (_holdIdentity || _accountLogin == _AccountLogin.pending) return false;
    final next = parseHeaderBadges(html);
    if (loggedIn && next == null && isGuestAccountDocument(html)) {
      if (!_currentExpired) {
        _currentExpired = true;
        _savedIdentity = null;
        final uid = _expiredUid = badges.uid ?? accounts?.currentUid;
        if (uid != null && accounts != null) {
          unawaited(_tryVault(() => accounts!.markExpired(uid)));
        }
        notifyListeners();
      }
      return true;
    }

    // 第一次观察无论结果如何都记一笔,用来判断这条链路到底有没有跑起来
    if (!_loggedFirstObservation) {
      _loggedFirstObservation = true;
      AppLog.i('BADGE', '首次观察 ${next == null ? '页面无登录态页头' : next.toString()}');
    }
    if (next == null) return false;

    // 页头在但认不出账号:把页头摘要记一次,便于对照真实模板
    if (next.userName == null && !_warnedNoUser) {
      _warnedNoUser = true;
      AppLog.w('BADGE', '页头未识别出账号');
    }
    if (next.userName != null) _warnedNoUser = false;

    final recovered =
        _currentExpired &&
        next.uid != null &&
        (_expiredUid == null || next.uid == _expiredUid);
    if (_currentExpired && !recovered) return true;
    if (recovered) {
      _currentExpired = false;
      _expiredUid = null;
    }
    if (loggedIn &&
        !_currentExpired &&
        next.uid != null &&
        next.userName != null) {
      _saveIdentity(next);
    }
    if (next == _headerBadges) {
      if (recovered) notifyListeners();
      return true;
    }
    AppLog.i('BADGE', '页头变化 $_headerBadges → $next');
    if (_headerBadges.uid != next.uid) {
      _identityRevision++;
      if (_headerBadges.uid != null && next.uid != null) {
        _unreadPmIds = null;
        _pmRevision++;
      }
    }
    _headerBadges = next;
    notifyListeners();
    return true;
  }

  /// 从 WebView Cookie 仓同步登录态,并把登录 Cookie 注入直连层
  Future<void> refresh() async {
    if (_accountOperation || _accountLogin != null) return;
    await _refresh();
  }

  Future<void> _refresh({
    AccountSummary? activated,
    bool forceIdentityChange = false,
    bool alreadyFlushed = false,
  }) async {
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
    if (!alreadyFlushed && hasAuth && !mapEquals(map, cookies)) {
      await _flushCookies();
    }
    if (epoch != _epoch) return;
    final direct = client.fetchers.whereType<DirectFetcher>().firstOrNull;
    if (direct != null) {
      // 游客态的会话 Cookie 同样要带:登录提交要求 formhash 与同会话 Cookie 配套,
      // 这里如果按登录态过滤,直连提交就会只带 formhash 而被判成 CSRF。
      direct.sessionCookies = map.isEmpty ? null : map;
    }
    Map<String, String> authOnly(Map<String, String> source) => {
      for (final entry in source.entries)
        if (entry.key.endsWith(_authCookieSuffix)) entry.key: entry.value,
    };
    final identityChanged =
        forceIdentityChange || !mapEquals(authOnly(map), authOnly(cookies));
    if (hasAuth != loggedIn || identityChanged) _authenticationRevision++;
    if (identityChanged) {
      _identityRevision++;
      // A new auth cookie may belong to another user. Do not infer self-rating
      // or bind a form using the previous account's header identity.
      _currentExpired = false;
      _expiredUid = null;
      _savedIdentity = null;
      _identitySave = null;
      badges = activated != null && hasAuth
          ? HeaderBadges(
              uid: activated.uid,
              userName: activated.name,
              notices: activated.notices,
              messages: activated.messages,
            )
          : _emptyBadges;
    }
    if (hasAuth != loggedIn ||
        map.length != cookies.length ||
        identityChanged) {
      // auth 轮换也会让旧会话作废，即使前后均为已登录。
      if (hasAuth != loggedIn || identityChanged) {
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
    if (_accountOperation || _accountLogin != null) throw StateError('会话正在切换');
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

  void _saveIdentity(HeaderBadges identity) {
    final store = accounts;
    if (store == null ||
        !cookies.keys.any((name) => name.endsWith(_authCookieSuffix))) {
      return;
    }
    final key = (authenticationRevision, identity.uid!, identity.userName!);
    final state = store.currentUid == key.$2 ? store.find(key.$2)?.state : null;
    if (_savedIdentity == key &&
        (_identitySave != null || state == null || state == AccountState.ok)) {
      return;
    }
    _savedIdentity = key;
    late final Future<void> pending;
    pending = _saveSnapshot(store, identity, observed: true).then((saved) {
      if (_identitySave != pending) return;
      _identitySave = null;
      if (!saved) _savedIdentity = null;
    });
    _identitySave = pending;
  }

  Future<bool> _tryVault(Future<bool> Function() method) async {
    try {
      return await method();
    } on PlatformException catch (error) {
      AppLog.w('SESSION', '账号库操作失败 ${error.code}');
      return false;
    }
  }

  Future<bool> _saveSnapshot(
    AccountStore store,
    HeaderBadges identity, {
    bool observed = false,
  }) => _tryVault(
    () => store.save(
      identity.uid!,
      identity.userName!,
      notices: identity.notices,
      messages: identity.uid == _headerBadges.uid
          ? _unreadPmIds?.length ?? identity.messages
          : identity.messages,
      observed: observed,
    ),
  );

  Future<void> captureCurrent() async {
    final store = accounts;
    if (store == null ||
        !loggedIn ||
        _accountOperation ||
        _accountLogin != null) {
      return;
    }
    final identity = badges;
    if (identity.uid != null && identity.userName != null) {
      await _saveSnapshot(store, identity);
    }
  }

  void _invalidateForms() {
    _epoch++;
    _identityRevision++;
    notifyListeners();
  }

  Future<AccountSwitchResult> switchAccount(String uid) async {
    final store = accounts;
    if (store == null || _accountOperation || _accountLogin != null) {
      return AccountSwitchResult.failed;
    }
    var target = store.find(uid);
    if (target == null) return AccountSwitchResult.failed;
    if (uid == badges.uid && !_currentExpired) {
      return AccountSwitchResult.success;
    }
    _accountOperation = true;
    _holdIdentity = true;
    _invalidateForms();
    store.setSwitchingUid(uid);
    try {
      var confirmationTimedOut = false;
      final age = client.now().millisecondsSinceEpoch - target.checkedAt;
      if (target.state != AccountState.ok || age < 0 || age >= 300000) {
        try {
          await _tryVault(
            () => store.check(uids: [uid], force: true),
          ).timeout(const Duration(seconds: 6));
        } on TimeoutException {
          // The native check can still update the vault after switching.
          confirmationTimedOut = true;
        }
        target = store.find(uid);
        if (target == null) return AccountSwitchResult.failed;
      }
      if (!confirmationTimedOut && target.state == AccountState.expired) {
        return AccountSwitchResult.expired;
      }
      final identity = badges;
      if (loggedIn && identity.uid != null && identity.userName != null) {
        await _saveSnapshot(store, identity);
      }
      if (!await _activate(store, target)) return AccountSwitchResult.failed;
      _holdIdentity = false;
      await ensureIdentity(verify: true);
      return AccountSwitchResult.success;
    } on PlatformException catch (error) {
      if (error.code == 'account_expired') return AccountSwitchResult.expired;
      AppLog.w('SESSION', '切换账号失败 ${error.code}');
      return AccountSwitchResult.failed;
    } catch (error) {
      AppLog.w('SESSION', '切换账号失败 ${error.runtimeType}');
      return AccountSwitchResult.failed;
    } finally {
      _holdIdentity = false;
      _accountOperation = false;
      store.setSwitchingUid(null);
      notifyListeners();
    }
  }

  Future<bool> _activate(AccountStore store, AccountSummary target) async {
    client.clearCache();
    if (!await store.activate(target.uid)) return false;
    await _refresh(
      activated: target,
      forceIdentityChange: true,
      alreadyFlushed: true,
    );
    return loggedIn;
  }

  Future<bool> beginAccountLogin({String? reloginUid}) async {
    final store = accounts;
    if (store == null) return false;
    if (_accountOperation || _accountLogin != null) {
      throw PlatformException(code: 'login_pending');
    }
    if (reloginUid == null && store.isFull) {
      throw PlatformException(code: 'account_limit');
    }
    _accountOperation = true;
    _holdIdentity = true;
    _epoch++; // Ignore cookie reads started before the vault takes ownership.
    try {
      final identity = badges;
      if (loggedIn &&
          !_currentExpired &&
          identity.uid != null &&
          identity.userName != null &&
          store.currentUid != identity.uid) {
        await _saveSnapshot(store, identity);
      }
      if (reloginUid == null && store.isFull) {
        throw PlatformException(code: 'account_limit');
      }
      final previous = store.currentUid;
      if (!await store.beginLogin(reloginUid: reloginUid)) return false;
      _previousLoginUid = previous;
      _accountLogin = _AccountLogin.pending;
      return true;
    } finally {
      _holdIdentity = false;
      _accountOperation = false;
    }
  }

  Future<bool> finishAccountLogin({required bool restore}) async {
    final store = accounts;
    final phase = _accountLogin;
    if (store == null || phase == null || _accountOperation) return false;
    final revision = _identityRevision;
    _accountOperation = true;
    _holdIdentity = true;
    try {
      if (phase == _AccountLogin.pending) {
        if (!await store.endLogin(restore: restore)) return false;
        _accountLogin = restore ? null : _AccountLogin.adopting;
        if (!restore) _invalidateForms();
        await _refresh(forceIdentityChange: !restore, alreadyFlushed: true);
      } else if (restore) {
        final previous = store.find(_previousLoginUid ?? '');
        if (previous == null || !await _activate(store, previous)) {
          await _clearSession();
        }
      } else {
        // Native has accepted the cookies. Retry identity lookup if its first
        // request or snapshot write did not complete successfully.
        await _refresh(alreadyFlushed: true);
        client.clearCache();
      }
      _holdIdentity = false;
      if (restore) {
        client.clearCache();
      } else {
        await ensureIdentity(verify: true);
        if (badges.uid == null || badges.uid != store.currentUid) return false;
      }
      _accountLogin = null;
      _previousLoginUid = null;
      return true;
    } finally {
      _holdIdentity = false;
      _accountOperation = false;
      if (_accountLogin == null &&
          (phase == _AccountLogin.adopting || revision != _identityRevision)) {
        notifyListeners();
      }
    }
  }

  /// 清除当前账号及其 Web 存储，有其他账号时恢复最近使用的会话。
  Future<void> logout() async {
    if (_accountOperation || _accountLogin != null) return;
    _accountOperation = true;
    _holdIdentity = true;
    _invalidateForms();
    var activated = false;
    try {
      final store = accounts;
      final uid = badges.uid ?? store?.currentUid;
      if (store != null && (uid == null || await store.remove(uid))) {
        final others = [...store.accounts]
          ..sort((a, b) {
            final byRecency = b.lastUsedAt.compareTo(a.lastUsedAt);
            return byRecency == 0 ? a.uid.compareTo(b.uid) : byRecency;
          });
        for (final target in others) {
          try {
            if (await _activate(store, target)) {
              activated = true;
              break;
            }
          } on PlatformException {
            // Continue to the next stored account with usable cookies.
          }
        }
      }
      if (!activated) await _clearSession();
      _holdIdentity = false;
      if (activated) await ensureIdentity(verify: true);
    } finally {
      _holdIdentity = false;
      _accountOperation = false;
      notifyListeners();
    }
  }

  Future<void> _clearSession() async {
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

    _authenticationRevision++;
    loggedIn = false;
    cookies = const {};
    badges = _emptyBadges;
    _currentExpired = false;
    _expiredUid = null;
    _savedIdentity = null;
    _identitySave = null;
    AppLog.i('SESSION', '已退出,Cookie 与 Web 存储已清空');
    notifyListeners();
  }
}
