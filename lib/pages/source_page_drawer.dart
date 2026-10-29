/// 原页面抽屉:从右侧滑入,内容是站点手机版原页面,可以在里面任意操作
///
/// 关闭按钮或返回手势收起抽屉,回到 App 页面。网页在滑入结束后才创建:
/// 原生网页视图跟着动画移动会掉帧,而抽屉停稳之后它就是一个普通页面。
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/chh_urls.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/chrome_button.dart';
import '../widgets/state_view.dart';

/// 帖子的手机版原页面
Uri threadSourceUrl(int tid, {int page = 1}) => Uri.parse(
  '${ChhUrls.base}/forum.php?mod=viewthread&tid=$tid&page=$page&mobile=2',
);

/// 门户文章的手机版原页面
Uri articleSourceUrl(int aid, {int page = 1}) => Uri.parse(
  '${ChhUrls.base}/portal.php?mod=view&aid=$aid&page=$page&mobile=2',
);

Future<void> showSourcePage(BuildContext context, Uri url) {
  final t = AppTokens.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: t.scrim,
      barrierDismissible: true,
      barrierLabel: '关闭原页面',
      transitionDuration: reduced ? Duration.zero : AppMotion.sheetDuration,
      reverseTransitionDuration: reduced
          ? Duration.zero
          : AppMotion.revealDuration,
      pageBuilder: (_, _, _) => SourcePageDrawer(url: url),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: AppMotion.sheetCurve,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      ),
    ),
  );
}

class SourcePageDrawer extends StatefulWidget {
  final Uri url;

  const SourcePageDrawer({super.key, required this.url});

  @override
  State<SourcePageDrawer> createState() => _SourcePageDrawerState();
}

class _SourcePageDrawerState extends State<SourcePageDrawer> {
  InAppWebViewController? _controller;
  Animation<double>? _route;
  bool _settled = false;
  bool _failed = false;
  double _progress = 0;
  String _title = '原页面';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (animation != _route) {
      _route?.removeStatusListener(_routeStatus);
      _route = animation;
      animation?.addStatusListener(_routeStatus);
    }
    // 推入时先在屏幕外渲染一帧计算转场,那一帧的动画被临时标为已完成,不能当作已停稳
    if (animation == null ||
        (!route!.offstage && animation.status == AnimationStatus.completed)) {
      _settled = true;
    }
  }

  void _routeStatus(AnimationStatus status) {
    final offstage = ModalRoute.of(context)?.offstage ?? false;
    if (status == AnimationStatus.completed &&
        !offstage &&
        !_settled &&
        mounted) {
      setState(() => _settled = true);
    }
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_routeStatus);
    super.dispose();
  }

  void _reload() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Material(
      color: t.surface,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  ChromeButton(
                    icon: AppIcons.dismiss,
                    tooltip: '关闭原页面',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.headline.copyWith(color: t.text),
                    ),
                  ),
                  ChromeButton(
                    icon: AppIcons.refresh,
                    tooltip: '重新加载',
                    onPressed: _controller == null ? null : _reload,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 2,
            child: _progress > 0 && _progress < 1 && !_failed
                ? LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2,
                    color: t.accent,
                    backgroundColor: t.fill,
                  )
                : null,
          ),
          Expanded(
            child: !_settled
                ? StateView.loading()
                : Stack(
                    children: [
                      InAppWebView(
                        initialUrlRequest: URLRequest(
                          url: WebUri.uri(widget.url),
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          incognito: false,
                          preferredContentMode: UserPreferredContentMode.MOBILE,
                          useShouldOverrideUrlLoading: true,
                        ),
                        onWebViewCreated: (c) =>
                            setState(() => _controller = c),
                        // 页面里拉起其他 App 的协议链接直接拦下,免得出现无法打开的错误页
                        shouldOverrideUrlLoading: (_, action) async {
                          final scheme = action.request.url?.scheme ?? '';
                          return scheme == 'http' || scheme == 'https'
                              ? NavigationActionPolicy.ALLOW
                              : NavigationActionPolicy.CANCEL;
                        },
                        onTitleChanged: (_, title) {
                          if (title != null && title.trim().isNotEmpty) {
                            setState(() => _title = title.split(' - ').first);
                          }
                        },
                        onProgressChanged: (_, progress) =>
                            setState(() => _progress = progress / 100),
                        onReceivedError: (_, request, _) {
                          if (request.isForMainFrame == true) {
                            setState(() => _failed = true);
                          }
                        },
                      ),
                      if (_failed)
                        Positioned.fill(
                          child: ColoredBox(
                            color: t.surface,
                            child: StateView(
                              icon: AppIcons.warning,
                              message: '原页面暂时无法加载',
                              actionLabel: '重新加载',
                              onAction: _reload,
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
}
