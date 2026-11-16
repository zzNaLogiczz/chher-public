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
import '../design/content_video_tokens.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../models/models.dart';
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
  final bool compact;

  const BilibiliCard({
    super.key,
    required this.block,
    this.playerBuilder = _webPlayer,
    this.compact = false,
  });

  /// 页面上正在播放的那张卡片
  static final _active = ValueNotifier<Object?>(null);

  @override
  State<BilibiliCard> createState() => _BilibiliCardState();
}

enum _Phase { idle, loading, playing, failed }

class _BilibiliCardState extends State<BilibiliCard>
    with TickerProviderStateMixin {
  static const _loadTimeout = Duration(seconds: 15);

  var _phase = _Phase.idle;
  Timer? _timeout;
  int _generation = 0;
  late final _spring = AnimationController(vsync: this);
  late final _fade = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _reduced = false;

  BilibiliVideo get _video => widget.block.video;

  @override
  void initState() {
    super.initState();
    BilibiliCard._active.addListener(_onActiveChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _fade.duration = _reduced ? AppMotion.reducedFade : AppMotion.fade;
    if (_reduced) _spring.value = 1;
  }

  @override
  void didUpdateWidget(covariant BilibiliCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.video.key != _video.key) _reset();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    BilibiliCard._active.removeListener(_onActiveChanged);
    if (BilibiliCard._active.value == this) BilibiliCard._active.value = null;
    _spring.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _reset() {
    _generation++;
    _timeout?.cancel();
    _spring.stop();
    _fade.stop();
    _phase = _Phase.idle;
  }

  /// 别的卡片开始播放时销毁播放器，迟到的回调不能改写下一次播放。
  void _onActiveChanged() {
    if (BilibiliCard._active.value == this || _phase == _Phase.idle) return;
    setState(_reset);
  }

  void _play() {
    if (_phase != _Phase.idle) return;
    BilibiliCard._active.value = this;
    final generation = ++_generation;
    _timeout?.cancel();
    _timeout = Timer(_loadTimeout, () => _fail(generation));
    setState(() => _phase = _Phase.loading);
    _animate();
  }

  void _animate() {
    _spring.value = 0;
    AppMotion.settle(
      _spring,
      target: 1,
      motion: _phase == _Phase.loading ? AppMotion.tap : AppMotion.reveal,
      reduced: _reduced,
    );
    _fade.forward(from: 0);
  }

  void _ready(int generation) {
    if (!mounted || generation != _generation || _phase != _Phase.loading) {
      return;
    }
    _timeout?.cancel();
    _spring.stop();
    _fade.stop();
    setState(() => _phase = _Phase.playing);
  }

  void _fail(int generation) {
    if (!mounted ||
        generation != _generation ||
        (_phase != _Phase.loading && _phase != _Phase.playing)) {
      return;
    }
    _timeout?.cancel();
    setState(() => _phase = _Phase.failed);
    _animate();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final showPlayer = _phase == _Phase.loading || _phase == _Phase.playing;
    return AspectRatio(
      aspectRatio: ContentVideoTokens.aspectRatio,
      child: AppClip(
        radius: widget.compact
            ? ContentVideoTokens.compactRadius
            : ContentVideoTokens.radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showPlayer)
              widget.playerBuilder(
                context,
                _video.playerUrl,
                () => _ready(generation),
                () => _fail(generation),
              ),
            if (_phase != _Phase.playing) ...[
              const _VideoSurface(),
              if (_phase != _Phase.failed) Center(child: _playControl()),
              Positioned(left: 14, right: 14, bottom: 11, child: _platform()),
              if (_phase == _Phase.failed) _failed(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _playControl() => PressScale(
    onTap: _phase == _Phase.idle ? _play : null,
    semanticLabel: _phase == _Phase.loading ? '正在加载视频' : '播放视频',
    child: Container(
      key: const ValueKey('bilibili-play-circle'),
      width: ContentVideoTokens.playSize,
      height: ContentVideoTokens.playSize,
      decoration: ShapeDecoration(
        color: ContentVideoTokens.playFill,
        shape: const CircleBorder(),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_spring, _fade]),
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              key: const ValueKey('bilibili-play-triangle'),
              scale: _phase == _Phase.idle ? 1 : 1 - _spring.value,
              child: const Padding(
                padding: EdgeInsets.only(left: 3),
                child: Icon(
                  AppIcons.play,
                  size: ContentVideoTokens.playIconSize,
                  color: ContentVideoTokens.foreground,
                ),
              ),
            ),
            if (_phase == _Phase.loading)
              FadeTransition(
                opacity: _fade,
                child: SizedBox.square(
                  dimension: ContentVideoTokens.spinnerSize,
                  child: CircularProgressIndicator(
                    // 减少动态效果时保留静态进度标记，不运行持续 Ticker。
                    value: _reduced ? .65 : null,
                    strokeWidth: ContentVideoTokens.spinnerStroke,
                    color: ContentVideoTokens.foreground,
                    semanticsLabel: '正在加载视频',
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _failed(BuildContext context) => Positioned.fill(
    bottom:
        19 +
        MediaQuery.textScalerOf(
              context,
            ).scale(ContentVideoTokens.identifierStyle.fontSize!) *
            ContentVideoTokens.identifierStyle.height!,
    child: Center(
      child: SingleChildScrollView(
        child: AnimatedBuilder(
          animation: Listenable.merge([_spring, _fade]),
          builder: (context, _) {
            final opacity = _fade.value;
            return Transform.translate(
              key: const ValueKey('bilibili-failure-motion'),
              offset: Offset(
                0,
                ContentVideoTokens.failureTravel * (1 - _spring.value),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '暂时无法播放',
                      style: ContentVideoTokens.failureStyle.copyWith(
                        color: ContentVideoTokens.foreground.withValues(
                          alpha: opacity,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    PressScale(
                      onTap: () => openExternal(context, _video.pageUrl),
                      semanticLabel: '在浏览器打开',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: ContentVideoTokens.foreground.withValues(
                                alpha: opacity,
                              ),
                              shape: appShape(AppRadii.full),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Text(
                                '在浏览器打开',
                                style: ContentVideoTokens.browserStyle.copyWith(
                                  color: ContentVideoTokens.browserText
                                      .withValues(alpha: opacity),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _platform() => Row(
    children: [
      Icon(
        ContentVideoTokens.television,
        size: 18,
        color: ContentVideoTokens.label,
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          '哔哩哔哩',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ContentVideoTokens.platformStyle,
        ),
      ),
      if (_video.bvid != null || _video.aid != null) ...[
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _video.bvid ?? 'av${_video.aid}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ContentVideoTokens.identifierStyle,
          ),
        ),
      ],
    ],
  );
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(gradient: ContentVideoTokens.screen),
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: ContentVideoTokens.blueGlow),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: ContentVideoTokens.pinkGlow),
      ),
    ),
  );
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
