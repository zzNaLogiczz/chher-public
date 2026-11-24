/// Authentication stays entirely in the real source page and shared cookie jar.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/chh_urls.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../network/login_preferences.dart';
import '../network/webview_trust.dart';
import '../ui/chrome_button.dart';
import '../widgets/compact_scaffold.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/state_view.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key})
    : _extraAccount = false,
      _uid = null,
      _name = null;
  const LoginPage.addAccount({super.key})
    : _extraAccount = true,
      _uid = null,
      _name = null;
  const LoginPage.relogin(String uid, String name, {super.key})
    : _extraAccount = true,
      _uid = uid,
      _name = name;

  final bool _extraAccount;
  final String? _uid;
  final String? _name;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _adoptionRetrySeconds = [2, 4, 8, 16, 30];

  Timer? _poll;
  Timer? _adoptionRetry;
  int _adoptionFailures = 0;
  InAppWebViewController? _controller;
  Future<void>? _opening;
  Future<void>? _checking;
  bool _accountLogin = false;
  bool _ready = false;
  bool _disposed = false;
  bool _closing = false;
  String? _openingError;
  bool _failed = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    if (widget._extraAccount) {
      _opening = _openAccountLogin();
    } else {
      _ready = true;
      _startPoll();
    }
  }

  Future<void> _openAccountLogin() async {
    try {
      _accountLogin = await chhSession.beginAccountLogin(
        reloginUid: widget._uid,
      );
      if (!_disposed) {
        setState(() => _ready = true);
        _startPoll();
      }
    } on PlatformException catch (error) {
      if (!_disposed) {
        setState(() {
          _openingError = error.code == 'account_limit'
              ? '最多保存 ${accountStore.max} 个账号'
              : '暂时无法打开登录页';
        });
      }
    }
  }

  void _startPoll() {
    _poll = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _checkSession(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _adoptionRetry?.cancel();
    if (widget._extraAccount) unawaited(_restoreAccount());
    super.dispose();
  }

  Future<void> _restoreAccount() async {
    final controller = _controller;
    if (controller != null && !_closing) {
      try {
        await controller.stopLoading();
      } catch (_) {
        // The platform view may already have been destroyed.
      }
    }
    await _opening;
    await _checking;
    if (_accountLogin) {
      try {
        await chhSession.finishAccountLogin(restore: true);
      } catch (_) {
        // The native pending record is recovered on the next startup.
      }
    }
  }

  Future<void> _checkSession() async {
    if (_closing ||
        _checking != null ||
        _adoptionRetry != null ||
        _disposed ||
        !_ready) {
      return;
    }
    final check = _completeLogin();
    _checking = check;
    try {
      await check;
    } finally {
      _checking = null;
      if (!_disposed && _accountLogin && chhSession.adoptingAccountLogin) {
        _scheduleAdoptionRetry();
      }
    }
  }

  void _scheduleAdoptionRetry() {
    _poll?.cancel();
    final seconds = _adoptionRetrySeconds[_adoptionFailures];
    if (_adoptionFailures < _adoptionRetrySeconds.length - 1) {
      _adoptionFailures++;
    }
    _adoptionRetry = Timer(Duration(seconds: seconds), () {
      _adoptionRetry = null;
      unawaited(_checkSession());
    });
  }

  Future<void> _completeLogin() async {
    try {
      if (_accountLogin) {
        if (!chhSession.adoptingAccountLogin &&
            !await accountStore.peekAuth()) {
          return;
        }
        if (_disposed) return;
        if (!await chhSession.finishAccountLogin(restore: false)) return;
        _accountLogin = false;
      } else {
        await chhSession.refresh();
        if (!chhSession.loggedIn || _disposed) return;
        chhClient.clearCache();
        unawaited(chhSession.ensureIdentity());
      }
      if (!mounted || _disposed) return;
      _closing = true;
      _poll?.cancel();
      Navigator.of(context).pop(true);
    } catch (_) {
      // A temporary cookie/platform error must not discard the source login page.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return CompactScaffold(
      title: widget._uid != null ? '重新登录' : '登录 CHH',
      showBack: Navigator.canPop(context),
      actions: [
        ChromeButton(
          tooltip: '重新加载登录页',
          onPressed: _reload,
          icon: AppIcons.refresh,
        ),
        const SizedBox(width: 8),
      ],
      body: !_ready
          ? _openingState()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.accentFill,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Icon(AppIcons.lock, color: t.accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'chiphell.com',
                              style: TextStyle(
                                fontSize: AppType.sizeBody,
                                fontWeight: FontWeight.w600,
                                color: t.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 2,
                  child: AnimatedOpacity(
                    opacity: _progress < 1 && !_failed ? 1 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppMotion.fade,
                    child: LinearProgressIndicator(
                      value: _failed ? 1 : (_progress > 0 ? _progress : null),
                      minHeight: 2,
                      color: t.accent,
                      backgroundColor: t.fill,
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      InAppWebView(
                        initialUrlRequest: URLRequest(
                          url: WebUri(
                            '${ChhUrls.base}/member.php?mod=logging&action=login&mobile=2',
                          ),
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          preferredContentMode: UserPreferredContentMode.MOBILE,
                          incognito: false,
                        ),
                        initialUserScripts: UnmodifiableListView([
                          UserScript(
                            source: rememberLoginScript,
                            injectionTime:
                                UserScriptInjectionTime.AT_DOCUMENT_END,
                            forMainFrameOnly: true,
                          ),
                          if (widget._name case final name?)
                            UserScript(
                              source: _prefillUsername(name),
                              injectionTime:
                                  UserScriptInjectionTime.AT_DOCUMENT_END,
                              forMainFrameOnly: true,
                            ),
                        ]),
                        onReceivedServerTrustAuthRequest: (_, challenge) =>
                            handleServerTrustChallenge(challenge),
                        onWebViewCreated: (controller) =>
                            _controller = controller,
                        onLoadStart: (_, _) {
                          if (mounted) {
                            setState(() {
                              _failed = false;
                              _progress = 0;
                            });
                          }
                        },
                        onProgressChanged: (_, progress) {
                          if (mounted) {
                            setState(() => _progress = progress / 100);
                          }
                        },
                        onLoadStop: (_, _) => _checkSession(),
                        onReceivedError: (_, request, error) {
                          if (request.isForMainFrame == true && mounted) {
                            setState(() => _failed = true);
                          }
                        },
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_failed,
                          child: ExcludeSemantics(
                            excluding: !_failed,
                            child: AnimatedOpacity(
                              opacity: _failed ? 1 : 0,
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : AppMotion.revealDuration,
                              child: ColoredBox(
                                color: t.bg,
                                child: StateView(
                                  icon: AppIcons.warning,
                                  message: '登录页暂时无法加载',
                                  actionLabel: '重新加载',
                                  onAction: _reload,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _openingState() {
    final error = _openingError;
    if (error == null) return const SizedBox.shrink();
    return StateView(icon: AppIcons.warning, message: error);
  }

  void _reload() {
    if (!_ready) {
      if (_openingError == null) return;
      setState(() => _openingError = null);
      _opening = _openAccountLogin();
      return;
    }
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _controller?.reload();
  }
}

String _prefillUsername(String name) =>
    """
(() => {
  const url = new URL(location.href);
  if (url.protocol !== 'https:' || url.hostname !== 'www.chiphell.com' ||
      url.pathname !== '/member.php' || url.searchParams.get('mod') !== 'logging' ||
      url.searchParams.get('action') !== 'login') return;
  const apply = () => {
    const input = document.querySelector('input[name="username"]:not([type="password"])');
    if (!input || input.disabled || input.dataset.chhUsernameDefault) return;
    input.dataset.chhUsernameDefault = '1';
    if (input.value === '') input.value = ${jsonEncode(name)};
  };
  apply();
  new MutationObserver(apply).observe(document.documentElement, {childList: true, subtree: true});
})();
""";
