/// 正文里的 B 站视频:先显示卡片,点了才在原位置加载外链播放器
///
/// 长帖里可能有很多视频,WebView 很重,所以不预先创建;同一时间只留一个播放器,
/// 点另一个视频时前一个恢复成卡片。拿不到视频标题(B 站接口对无 Cookie 请求返回 412),
/// 卡片只写平台名,不编造标题。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/link_target.dart';
import '../design/icons.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/models.dart';
import '../ui/app_button.dart';
import '../ui/press.dart';
import 'link_opener.dart';

/// 播放器构造;测试里替换掉真实 WebView
typedef BilibiliPlayerBuilder =
    Widget Function(
      BuildContext context,
      Uri url,
      VoidCallback onReady,
      VoidCallback onError,
    );

class BilibiliCard extends StatefulWidget {
  final BilibiliBlock block;
  final BilibiliPlayerBuilder playerBuilder;

  const BilibiliCard({
    super.key,
    required this.block,
    this.playerBuilder = _webPlayer,
  });

  /// 页面上正在播放的那张卡片
  static final _active = ValueNotifier<Object?>(null);

  @override
  State<BilibiliCard> createState() => _BilibiliCardState();
}

enum _Phase { idle, loading, playing, failed }

class _BilibiliCardState extends State<BilibiliCard> {
  /// 超过这个时间播放器还没加载完就算失败,给出浏览器入口
  static const _loadTimeout = Duration(seconds: 15);

  var _phase = _Phase.idle;
  Timer? _timeout;

  BilibiliVideo get _video => widget.block.video;

  @override
  void initState() {
    super.initState();
    BilibiliCard._active.addListener(_onActiveChanged);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    BilibiliCard._active.removeListener(_onActiveChanged);
    if (BilibiliCard._active.value == this) BilibiliCard._active.value = null;
    super.dispose();
  }

  /// 别的卡片开始播放时,自己恢复成卡片并销毁播放器
  void _onActiveChanged() {
    if (BilibiliCard._active.value == this || _phase == _Phase.idle) return;
    _timeout?.cancel();
    setState(() => _phase = _Phase.idle);
  }

  void _play() {
    BilibiliCard._active.value = this;
    _timeout?.cancel();
    _timeout = Timer(_loadTimeout, _fail);
    setState(() => _phase = _Phase.loading);
  }

  void _ready() {
    if (!mounted || _phase != _Phase.loading) return;
    _timeout?.cancel();
    setState(() => _phase = _Phase.playing);
  }

  void _fail() {
    if (!mounted || _phase == _Phase.idle) return;
    _timeout?.cancel();
    setState(() => _phase = _Phase.failed);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.dark;
    final showPlayer = _phase == _Phase.loading || _phase == _Phase.playing;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: AppClip(
        radius: AppRadii.sm,
        child: ColoredBox(
          color: t.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showPlayer)
                widget.playerBuilder(context, _video.playerUrl, _ready, _fail),
              if (_phase == _Phase.loading)
                Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: t.text,
                  ),
                ),
              if (_phase == _Phase.idle) ..._idle(t),
              if (_phase == _Phase.failed) _failed(context, t),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _idle(AppTokens t) => [
    Center(
      child: PressScale(
        onTap: _play,
        semanticLabel: '播放视频',
        child: Container(
          width: 56,
          height: 56,
          decoration: ShapeDecoration(
            color: AppTokens.light.glass,
            shape: const CircleBorder(),
          ),
          child: Icon(AppIcons.play, size: 24, color: AppTokens.light.text),
        ),
      ),
    ),
    Positioned(left: 14, bottom: 12, child: _platform(t)),
  ];

  Widget _failed(BuildContext context, AppTokens t) => Positioned(
    left: 14,
    right: 14,
    bottom: 12,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _platform(t),
              Text(
                '暂时无法播放',
                style: AppType.subhead.copyWith(
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ],
          ),
        ),
        AppButton(
          label: '在浏览器打开',
          small: true,
          onPressed: () => openExternal(context, _video.pageUrl),
        ),
      ],
    ),
  );

  Widget _platform(AppTokens t) =>
      Text('哔哩哔哩', style: AppType.caption.copyWith(color: t.text2));
}

/// 等 video 元素出现后开始播放;最多等 10 秒,播放被拒绝时保持播放器原样
const _autoplayScript = '''
(function () {
  var tries = 0;
  var timer = setInterval(function () {
    var video = document.querySelector('video');
    if (video) {
      clearInterval(timer);
      if (video.paused) video.play().catch(function () {});
    } else if (++tries > 40) {
      clearInterval(timer);
    }
  }, 250);
})();
''';

/// 播放器设置。用户已点播放,允许无手势自动播放并支持全屏。
///
/// 不用 Hybrid Composition:那种方式下只要播放器在页面里,Flutter 每一帧都要和
/// Android 主线程同步合成,视频播放时弹出回复框、键盘,整页动画会明显掉帧。
/// 纹理合成把播放器画面当作一张纹理交给 Flutter,页面动画不再被它拖住。
InAppWebViewSettings bilibiliPlayerSettings() => InAppWebViewSettings(
  javaScriptEnabled: true,
  mediaPlaybackRequiresUserGesture: false,
  allowsInlineMediaPlayback: true,
  supportZoom: false,
  transparentBackground: true,
  useShouldOverrideUrlLoading: true,
  useHybridComposition: false,
);

/// 真实播放器:B 站外链播放器页
Widget _webPlayer(
  BuildContext context,
  Uri url,
  VoidCallback onReady,
  VoidCallback onError,
) => InAppWebView(
  initialUrlRequest: URLRequest(url: WebUri.uri(url)),
  initialSettings: bilibiliPlayerSettings(),
  // 主页面只留在播放器里(含手机上跳转的移动版播放器):点标题、logo 跳主站时交给浏览器;
  // bilibili:// 这类拉起 App 的协议直接拦下,不让它把正在播的视频判成失败
  shouldOverrideUrlLoading: (_, action) async {
    final url = action.request.url;
    if (!action.isForMainFrame ||
        url == null ||
        isBilibiliPlayerPage(Uri.parse(url.toString()))) {
      return NavigationActionPolicy.ALLOW;
    }
    if ((url.scheme == 'https' || url.scheme == 'http') && context.mounted) {
      unawaited(openExternal(context, Uri.parse(url.toString())));
    }
    return NavigationActionPolicy.CANCEL;
  },
  onLoadStop: (controller, _) {
    // 手机上的移动版播放器不认 autoplay 参数,用户已在卡片上点过播放,这里替他点第二次
    controller.evaluateJavascript(source: _autoplayScript);
    onReady();
  },
  // 只看主页面;播放器里的统计、广告子请求失败不影响播放
  onReceivedError: (_, request, _) {
    if (request.isForMainFrame ?? true) onError();
  },
  onReceivedHttpError: (_, request, _) {
    if (request.isForMainFrame ?? true) onError();
  },
);
