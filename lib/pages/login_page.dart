/// Authentication stays entirely in the real source page and shared cookie jar.
library;

import 'dart:async';
import '../design/icons.dart';
import '../ui/chrome_button.dart';
import '../design/motion.dart';
import '../design/typography.dart';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../core/chh_urls.dart';
import '../design/tokens.dart';
import '../di.dart';
import '../network/login_preferences.dart';
import '../widgets/state_view.dart';
import '../widgets/expressive_controls.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Timer? _poll;
  InAppWebViewController? _controller;
  bool _closing = false;
  bool _checking = false;
  bool _failed = false;
  double _progress = 0;
  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _checkSession(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkSession() async {
    if (_closing || _checking || !mounted) return;
    _checking = true;
    try {
      await chhSession.refresh();
      if (!chhSession.loggedIn || !mounted || _closing) return;
      _closing = true;
      _poll?.cancel();
      chhClient.clearCache();
      Navigator.of(context).pop(true);
    } catch (_) {
      // A temporary cookie/platform error must not discard the source login page.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录 CHH'),
        leading: Navigator.canPop(context)
            ? ChromeButton(
                icon: AppIcons.back,
                tooltip: '返回',
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
        actions: [
          ChromeButton(
            tooltip: '重新加载登录页',
            onPressed: _reload,
            icon: AppIcons.refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
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
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                      forMainFrameOnly: true,
                    ),
                  ]),
                  onWebViewCreated: (controller) => _controller = controller,
                  onLoadStart: (_, _) {
                    if (mounted) {
                      setState(() {
                        _failed = false;
                        _progress = 0;
                      });
                    }
                  },
                  onProgressChanged: (_, progress) {
                    if (mounted) setState(() => _progress = progress / 100);
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

  void _reload() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _controller?.reload();
  }
}
