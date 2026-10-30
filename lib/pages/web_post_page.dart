/// 需要人机验证的发布:在站点手机版真实页面里完成
///
/// 腾讯滑块的票据离开出题页面就失效,取出来改由直连提交,站点一律判「验证码填写错误」。
/// 所以这里打开站点手机版的发帖/回复页(与登录页同一路线),把用户写好的内容填进表单后
/// 原样展示:能找到验证按钮就替用户打开滑块,通过后点页面自己的发表按钮;找不到时用户
/// 也能直接在页面里操作。结果按落地页判定。不替用户解题,也不保存票据。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import '../core/web_post_diagnostics.dart';
import '../core/chh_urls.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/models.dart';
import '../parser/post_form_parser.dart';
import '../ui/app_button.dart';
import '../widgets/state_view.dart';
import '../network/webview_trust.dart';

/// 结果需要验证时转到真实页面完成;否则原样返回
Future<PostResult> completeOnWeb(
  BuildContext context,
  PostResult result,
) async {
  final web = result.web;
  if (web == null || !context.mounted) return result;
  final done = await Navigator.of(context).push<PostResult>(
    MaterialPageRoute(builder: (_) => WebPostPage(submission: web)),
  );
  return done ?? const PostResult(PostResultKind.failed, '已取消验证，内容已保留');
}

/// 手机版页面:与登录页一致,用 WebView 自身的手机 UA
Uri mobilePage(Uri page) =>
    page.replace(queryParameters: {...page.queryParameters, 'mobile': '2'});

enum _Phase { loading, ready, submitting, failed }

class WebPostPage extends StatefulWidget {
  final WebSubmission submission;

  const WebPostPage({super.key, required this.submission});

  @override
  State<WebPostPage> createState() => _WebPostPageState();
}

class _WebPostPageState extends State<WebPostPage> {
  late final Uri _page = mobilePage(widget.submission.page);
  InAppWebViewController? _controller;
  Timer? _poll;
  Timer? _deadline;
  _Phase _phase = _Phase.loading;
  String? _error;
  bool _filled = false;
  String _lastState = '';

  @override
  void initState() {
    super.initState();
    WebPostDiagnostics.opened(_page, widget.submission.fields);
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _deadline?.cancel();
    super.dispose();
  }

  void _set(_Phase phase, {String? error}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _error = error;
    });
  }

  /// 轮询页面:填表 → 打开滑块 → 拿到票据后点页面的发表按钮。
  /// 站点的防护跳转和验证控件都是异步出现的,轮询比挂在某次加载完成上更稳。
  Future<void> _tick() async {
    final c = _controller;
    if (c == null || _phase == _Phase.failed) return;
    try {
      if (!_filled) {
        final report = await c.evaluateJavascript(
          source: _fillScript(widget.submission.fields),
        );
        if (report is! Map) return;
        _filled = true;
        WebPostDiagnostics.filled(report);
        _set(_Phase.ready);
      }
      if (_phase == _Phase.submitting) return;
      final state = '${await c.evaluateJavascript(source: _captchaScript)}';
      if (state != _lastState) {
        _lastState = state;
        AppLog.i('WEBPOST', '验证状态 $state');
      }
      if (state == 'ticket') await _submit();
    } catch (e) {
      // 页面正在跳转时执行脚本会失败,下一轮再试
    }
  }

  Future<void> _submit() async {
    final c = _controller;
    if (c == null || _phase == _Phase.submitting) return;
    _set(_Phase.submitting);
    _armDeadline();
    final how = await c.evaluateJavascript(source: _submitScript);
    AppLog.i('WEBPOST', '提交 $how');
  }

  /// 落地页迟迟不来:不猜结果,交给用户回帖子确认
  void _armDeadline() {
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 40), () {
      if (mounted) {
        Navigator.of(
          context,
        ).pop(const PostResult(PostResultKind.unknown, '提交状态未知，请返回帖子确认'));
      }
    });
  }

  /// 每次加载完成:还是发帖页就(重新)填表;离开了发帖页就是提交的结果
  Future<void> _onLoaded(InAppWebViewController c, WebUri? url) async {
    final page = url?.toString() ?? '';
    final title = (await c.getTitle()) ?? '';
    WebPostDiagnostics.loaded(page, title);
    // 防护跳转的中间页不算结果
    if (title.toLowerCase().contains('loading')) return;
    final onForm = await c.evaluateJavascript(source: _hasFormScript) == true;
    if (onForm) {
      if (_phase == _Phase.submitting) {
        // 提交后又回到表单页:多半是页面校验没通过,让用户看着页面处理
        _deadline?.cancel();
        _set(_Phase.ready);
      }
      return;
    }
    if (!_filled) return;
    final html = await c.getHtml() ?? '';
    var result = parsePostResult(html);
    final tid = ChhUrls.tidFromUrl(page);
    if (!result.isSuccess && page.contains('mod=viewthread') && tid != null) {
      result = PostResult(PostResultKind.success, '已发布', tid: tid);
    } else if (result.isSuccess && result.tid == null) {
      result = PostResult(
        result.kind,
        result.message,
        tid: tid,
        pid: result.pid,
      );
    }
    AppLog.i('WEBPOST', '结果 ${result.kind.name} ${result.message}');
    _deadline?.cancel();
    if (!mounted) return;
    if (result.isSuccess || result.kind == PostResultKind.unknown) {
      Navigator.of(context).pop(result);
    } else {
      _set(_Phase.failed, error: result.message);
    }
  }

  /// 失败后重来:重新加载页面,重新填表
  void _restart() {
    _filled = false;
    _lastState = '';
    _set(_Phase.loading);
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(_page)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final covered = _phase == _Phase.loading || _phase == _Phase.failed;
    return PopScope(
      canPop: _phase != _Phase.submitting,
      child: Scaffold(
        backgroundColor: t.surface,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: Row(
                children: [
                  AppButton(
                    label: '取消',
                    variant: AppButtonVariant.quiet,
                    onPressed: _phase == _Phase.submitting
                        ? null
                        : () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '人机验证',
                          style: AppType.headline.copyWith(color: t.text),
                        ),
                        Text(
                          _phase == _Phase.submitting
                              ? '正在发表'
                              : '内容已填好，完成验证后发表',
                          style: AppType.footnote.copyWith(color: t.text3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 64),
                ],
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri.uri(_page)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                incognito: false,
                preferredContentMode: UserPreferredContentMode.MOBILE,
              ),
              onReceivedServerTrustAuthRequest: (_, challenge) =>
                  handleServerTrustChallenge(challenge),
              onWebViewCreated: (c) => _controller = c,
              onLoadStop: _onLoaded,
              onConsoleMessage: (_, message) {
                if (message.messageLevel == ConsoleMessageLevel.ERROR) {
                  WebPostDiagnostics.consoleError(message.message);
                }
              },
              onReceivedError: (_, request, error) {
                if (request.isForMainFrame == true) {
                  WebPostDiagnostics.loadError(request.url, error.type);
                  _set(_Phase.failed, error: '页面加载失败，请检查网络后重试');
                }
              },
            ),
            if (covered)
              Positioned.fill(
                child: ColoredBox(
                  color: t.surface,
                  child: switch (_phase) {
                    _Phase.failed => StateView(
                      icon: AppIcons.warning,
                      message: _error ?? '发表失败，内容已保留',
                      actionLabel: '重试',
                      onAction: _restart,
                    ),
                    _ => StateView.loading(),
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 发帖表单:手机版与电脑版都认 #postform,再退到含正文输入框的表单
const _findForm = '''
function chhForm() {
  var form = document.getElementById('postform');
  if (form) return form;
  var message = document.querySelector('form textarea[name="message"]');
  return message ? message.form : null;
}
''';

const _hasFormScript =
    '''
(function () {
  $_findForm
  var form = chhForm();
  return !!(form && form.elements['formhash']);
})();
''';

/// 把字段写进表单;页面没有的字段补成隐藏输入。找不到表单返回 null,等下一轮。
/// 返回表单结构摘要(只有字段名和验证控件是否存在),用于排查。
String _fillScript(Map<String, String> fields) =>
    '''
(function (fields) {
  $_findForm
  var form = chhForm();
  if (!form || !form.elements['formhash']) return null;
  Object.keys(fields).forEach(function (name) {
    var el = form.elements[name];
    if (el && !el.tagName && el.length) {
      // 单选组(如分类):按值选中
      el.value = fields[name];
      return;
    }
    if (!el) {
      el = document.createElement('input');
      el.type = 'hidden';
      el.name = name;
      form.appendChild(el);
    }
    el.value = fields[name];
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  var names = [];
  for (var i = 0; i < form.elements.length; i++) {
    var e = form.elements[i];
    if (e.name && names.indexOf(e.name) < 0) names.push(e.name);
  }
  var verify = document.getElementById('codeVerifyButton');
  if (verify) verify.scrollIntoView({ block: 'center' });
  return {
    action: form.getAttribute('action') || '',
    names: names.join(','),
    seccode: document.querySelectorAll('[id^="seccode_"]').length,
    verifyButton: !!verify,
    tcaptcha: typeof window.TencentCaptcha
  };
})(${jsonEncode(fields)});
''';

/// 验证状态:已有票据 / 已打开滑块 / 控件还没出现。按钮只替用户点一次,
/// 用户关掉滑块后可以在页面上自己再点。
const _captchaScript = '''
(function () {
  var ticket = document.getElementById('codeVerifyTicket');
  if (ticket && ticket.value) return 'ticket';
  var button = document.getElementById('codeVerifyButton');
  if (!button) return 'waiting';
  if (!window.__chhOpened && typeof window.TencentCaptcha === 'function') {
    window.__chhOpened = true;
    button.click();
    return 'opened';
  }
  return window.__chhOpened ? 'opened' : 'loading-captcha';
})();
''';

/// 走页面自己的发表按钮,让站点脚本按它的方式提交;没有按钮才直接提交表单
const _submitScript =
    '''
(function () {
  $_findForm
  var form = chhForm();
  if (!form) return 'no-form';
  var button = form.querySelector('#postsubmit, [type="submit"], button[name="topicsubmit"], button[name="replysubmit"]');
  if (button) {
    button.click();
    return 'button';
  }
  HTMLFormElement.prototype.submit.call(form);
  return 'form';
})();
''';
