/// 正文保留原图比例；短回复可使用紧凑宫格。图片浏览支持缩放与横向翻阅。
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import '../design/image_tokens.dart';
import '../attachments/image_save.dart';
import '../ui/feedback.dart';
import '../design/icons.dart';
import '../ui/press.dart';
import '../design/motion.dart';
import '../design/typography.dart';
import '../ui/chrome_button.dart';
import '../ui/nav_bar.dart';
import '../ui/image_viewer_chrome.dart';
import '../ui/reading_bar.dart';

import '../design/tokens.dart';
import '../design/system_ui.dart';
import 'article_image.dart';
import 'cached_net_image.dart';
import 'net_image.dart';
import 'expressive_controls.dart';

class ImageGrid extends StatelessWidget {
  final List<String> urls;
  final bool preserveAspectRatio;
  final List<String>? gallery;
  final int galleryStartIndex;
  const ImageGrid(
    this.urls, {
    super.key,
    this.preserveAspectRatio = false,
    this.gallery,
    this.galleryStartIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    if (preserveAspectRatio || urls.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < urls.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == urls.length - 1 ? 0 : 16),
              child: _ImageTile(
                url: urls[i],
                all: gallery ?? urls,
                index: galleryStartIndex + i,
                natural: true,
              ),
            ),
        ],
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: urls.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: urls.length == 2 ? 2 : 3,
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
      ),
      itemBuilder: (context, i) => _ImageTile(
        url: urls[i],
        all: gallery ?? urls,
        index: galleryStartIndex + i,
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  final String url;
  final List<String> all;
  final int index;
  final bool natural;
  const _ImageTile({
    required this.url,
    required this.all,
    required this.index,
    this.natural = false,
  });

  @override
  Widget build(BuildContext context) => InlineImageViewer(
    url: url,
    gallery: all,
    initialIndex: index,
    natural: natural,
  );
}

/// The source and destination share one provider, including its decode size.
class InlineImageViewer extends StatefulWidget {
  const InlineImageViewer({
    super.key,
    required this.url,
    required this.gallery,
    this.initialIndex = 0,
    this.natural = true,
  });

  final String url;
  final List<String> gallery;
  final int initialIndex;
  final bool natural;

  @override
  State<InlineImageViewer> createState() => _InlineImageViewerState();
}

class _InlineImageViewerState extends State<InlineImageViewer> {
  final _heroTag = Object();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final t = AppTokens.of(context);
      final provider = boundedNetworkImage(
        widget.url,
        boundedImageDecodeWidth(
          constraints.maxWidth,
          MediaQuery.devicePixelRatioOf(context),
        ),
      );
      final gallery = widget.gallery.isEmpty ? [widget.url] : widget.gallery;
      final index = widget.initialIndex.clamp(0, gallery.length - 1);
      return PressScale(
        scale: AppPressScale.content,
        semanticLabel: '查看第 ${index + 1} 张图片',
        onTap: () => openImageViewer(
          context,
          urls: gallery,
          initialIndex: index,
          heroTag: _heroTag,
          previewImage: provider,
        ),
        child: HeroMode(
          enabled: !MediaQuery.disableAnimationsOf(context),
          child: Hero(
            tag: _heroTag,
            placeholderBuilder: imageHeroPlaceholder,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                widget.natural ? ImageTokens.radius : AppRadii.xs,
              ),
              child: widget.natural
                  ? ArticleImage(url: widget.url, imageProvider: provider)
                  : Image(
                      image: provider,
                      color: t.isDark ? ImageTokens.darkTint : null,
                      colorBlendMode: BlendMode.modulate,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, synchronous) =>
                          synchronous || frame != null
                          ? child
                          : ColoredBox(color: t.fill),
                      errorBuilder: (context, _, _) => ColoredBox(
                        color: t.fill,
                        child: Center(
                          child: Icon(AppIcons.image, color: t.text3),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
    },
  );
}

/// Keep a reader's photo in its own route if Back skips its return flight.
Widget imageHeroPlaceholder(BuildContext context, Size size, Widget photo) {
  final routeAnimation = ModalRoute.of(context)?.animation;
  return SizedBox.fromSize(
    size: size,
    child: routeAnimation == null
        ? null
        : AnimatedBuilder(
            animation: routeAnimation,
            child: photo,
            builder: (context, child) =>
                routeAnimation.status == AnimationStatus.reverse
                ? child!
                : const SizedBox.shrink(),
          ),
  );
}

Future<void> openImageViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
  Object? heroTag,
  Object Function(int)? heroTagForIndex,
  ImageProvider<Object>? previewImage,
  ImageProvider<Object> Function(int)? previewImageForIndex,
  ValueChanged<int>? onPageChanged,
}) async {
  final chrome = ImageViewerChromeController.maybeOf(context);
  if (urls.isEmpty || chrome?.covered.value == true) return;
  final navigator = Navigator.of(context);
  final readerStyle = AppSystemUi.forBrightness(Theme.of(context).brightness);
  final route = _ImageViewerRoute(
    reduced: MediaQuery.disableAnimationsOf(context),
    readerStyle: () => chrome?.overlayStyle() ?? readerStyle,
    builder: (_) => ImageViewerPage(
      urls: urls,
      initialIndex: initialIndex,
      heroTag: heroTag,
      heroTagForIndex: heroTagForIndex,
      previewImage: previewImage,
      previewImageForIndex: previewImageForIndex,
      onPageChanged: onPageChanged,
    ),
  );
  chrome?.covered.value = true;
  try {
    await navigator.push<void>(route);
    // Restore the reading bars when the return flight has left the overlay.
    await route.completed;
  } finally {
    chrome?.restore();
  }
}

class _ViewerPagePhysics extends PageScrollPhysics {
  const _ViewerPagePhysics({super.parent});

  @override
  _ViewerPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _ViewerPagePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => AppMotion.sheet.description;
}

class _ImageViewerRoute extends PageRouteBuilder<void> {
  _ImageViewerRoute({
    required WidgetBuilder builder,
    required this.reduced,
    required this.readerStyle,
  }) : super(
         opaque: false,
         allowSnapshotting: false,
         barrierColor: Colors.transparent,
         transitionDuration: reduced
             ? AppMotion.reducedFade
             : AppMotion.heroDuration,
         reverseTransitionDuration: reduced
             ? AppMotion.reducedFade
             : AppMotion.reveal.duration + AppMotion.viewerChromeOut,
         pageBuilder: (context, _, _) =>
             SizedBox.expand(child: builder(context)),
         transitionsBuilder: (context, animation, _, child) => child,
       );

  final bool reduced;
  final ValueGetter<SystemUiOverlayStyle> readerStyle;
  bool _predictiveBack = false;
  bool _holdReturnForChrome = false;
  late final Curve returnCurve = _ViewerReturnCurve(this);

  Animation<double> get progress => controller!.view;

  // Normal pop spends the first 100 ms fading controls at the release rect.
  // Predictive back continues to use the gesture's full progress range.
  double get _returnFlightEnd =>
      AppMotion.reveal.duration.inMicroseconds /
      reverseTransitionDuration.inMicroseconds;

  bool get returning => progress.status == AnimationStatus.reverse;
  bool get followsGesture => _predictiveBack;

  double get flightProgress => returning && _holdReturnForChrome
      ? returnProgress(progress.value)
      : progress.value;

  double returnProgress(double value) =>
      _holdReturnForChrome ? (value / _returnFlightEnd).clamp(0.0, 1.0) : value;

  double get closingChrome {
    if (progress.isDismissed) return 0;
    if (!returning && !followsGesture) return 1;
    if (!_holdReturnForChrome) return progress.value;
    return ((progress.value - _returnFlightEnd) / (1 - _returnFlightEnd)).clamp(
      0.0,
      1.0,
    );
  }

  @override
  void handleStartBackGesture({double progress = 0.0}) {
    _predictiveBack = true;
    super.handleStartBackGesture(progress: progress);
  }

  @override
  bool didPop(void result) {
    _predictiveBack = navigator?.userGestureInProgress ?? false;
    _holdReturnForChrome = !reduced && !_predictiveBack && progress.isCompleted;
    return super.didPop(result);
  }
}

class _ViewerReturnCurve extends Curve {
  const _ViewerReturnCurve(this.route);

  final _ImageViewerRoute route;

  @override
  double transformInternal(double t) =>
      AppMotion.viewerHeroCurve.flipped.transform(route.returnProgress(t));
}

class ImageViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final Object? heroTag;
  final ImageProvider<Object>? previewImage;
  final Object Function(int)? heroTagForIndex;
  final ImageProvider<Object> Function(int)? previewImageForIndex;
  final ValueChanged<int>? onPageChanged;
  const ImageViewerPage({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.heroTag,
    this.previewImage,
    this.heroTagForIndex,
    this.previewImageForIndex,
    this.onPageChanged,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with TickerProviderStateMixin {
  late final _controller = PageController(initialPage: _index);
  late int _index = widget.urls.isEmpty
      ? 0
      : widget.initialIndex.clamp(0, widget.urls.length - 1);
  final _transform = TransformationController();
  final _viewportKey = GlobalKey();
  Animation<double>? _routeAnimation;
  _ImageViewerRoute? _viewerRoute;
  late final _enterChrome = AnimationController(
    vsync: this,
    duration: AppMotion.viewerChromeIn,
  );
  late final _zoom = AnimationController(
    vsync: this,
    duration: AppMotion.revealDuration,
  );
  late final _dismiss = AnimationController.unbounded(vsync: this);
  late final _pageMotion = AnimationController.unbounded(vsync: this);
  final _pointers = <int>{};
  Offset? _dragStart;
  Offset? _lastPosition;
  VelocityTracker? _velocity;
  bool _dragging = false;
  bool _closing = false;
  Animation<Matrix4>? _zoomAnimation;
  double _zoomStartScale = 1, _zoomEndScale = 1;
  Offset _tapPosition = Offset.zero;
  bool _zoomed = false;
  bool _fullResolutionRequested = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pageMotion.addListener(() {
      if (_controller.hasClients) _controller.jumpTo(_pageMotion.value);
    });
    _zoom.addListener(() {
      final animation = _zoomAnimation;
      if (animation != null) _transform.value = animation.value;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _viewerRoute = route is _ImageViewerRoute ? route : null;
    final animation = _viewerRoute?.progress ?? route?.animation;
    if (animation == null) {
      _enterChrome.value = 1;
    }
    if (animation == _routeAnimation) return;
    _routeAnimation?.removeStatusListener(_routeStatusChanged);
    _routeAnimation = animation;
    animation?.addStatusListener(_routeStatusChanged);
    if (animation?.isCompleted == true) _enterChrome.value = 1;
  }

  void _routeStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      // Freeze the presented geometry before Hero measures its departure rect.
      _zoom.stop();
      _dismiss.stop();
      _pageMotion.stop();
      _enterChrome.stop();
      _closing = true;
      _dragStart = _lastPosition = null;
      _dragging = false;
      if (_controller.hasClients) {
        final position = _controller.position;
        if (position is ScrollPositionWithSingleContext) position.goIdle();
      }
    } else if (status == AnimationStatus.completed) {
      _closing = false;
      if (MediaQuery.disableAnimationsOf(context)) {
        _enterChrome.value = 1;
      } else {
        _enterChrome.forward();
      }
    }
  }

  void _doubleTap() {
    if (_closing) return;
    final target = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-_tapPosition.dx, -_tapPosition.dy, 0, 1)
            ..scaleByDouble(2, 2, 1, 1));
    final startScale = _transform.value.getMaxScaleOnAxis();
    final endScale = target.getMaxScaleOnAxis();
    final distance = endScale - startScale;
    final velocity = distance.abs() < .001
        ? 0.0
        : _zoom.velocity * (_zoomEndScale - _zoomStartScale) / distance;
    _zoomStartScale = startScale;
    _zoomEndScale = endScale;
    _zoomAnimation = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(_zoom);
    setState(() {
      _zoomed = !_zoomed;
      _fullResolutionRequested = _zoomed;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _transform.value = target;
    } else {
      _zoom.value = 0;
      AppMotion.settle(
        _zoom,
        target: 1,
        velocity: velocity,
        motion: AppMotion.select,
      );
    }
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    _pageMotion.stop();
    _dismiss.stop();
    if (_pointers.length != 1 || _zoomed || _closing) {
      _cancelDrag();
      return;
    }
    _dragStart = _lastPosition = event.position;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _pointerMove(PointerMoveEvent event) {
    if (_closing) return;
    final start = _dragStart;
    if (start == null) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    final total = event.position - start;
    if (!_dragging && total.distance > kTouchSlop) {
      if (total.dy.abs() <= total.dx.abs() || _zoomed) {
        _cancelDrag();
        return;
      }
      _dragging = true;
    }
    if (_dragging) {
      _dismiss.value = (_dismiss.value + event.position.dy - _lastPosition!.dy)
          .clamp(0.0, MediaQuery.sizeOf(context).height);
      _lastPosition = event.position;
    }
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_dragStart == null) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    final velocity = _velocity?.getVelocity().pixelsPerSecond.dy ?? 0;
    final height = MediaQuery.sizeOf(context).height;
    final dismiss =
        _dragging &&
        (_dismiss.value > height * ImageTokens.dismissFraction ||
            velocity > ImageTokens.dismissVelocity);
    _dragStart = _lastPosition = null;
    _dragging = false;
    if (dismiss && Navigator.of(context).canPop()) {
      _closing = true;
      Navigator.of(context).pop();
    } else {
      AppMotion.settle(
        _dismiss,
        target: 0,
        velocity: velocity,
        motion: AppMotion.sheet,
        reduced: MediaQuery.disableAnimationsOf(context),
      );
    }
  }

  void _cancelDrag() {
    _dragStart = _lastPosition = null;
    _dragging = false;
    if (_closing) return;
    if (_dismiss.value != 0) {
      AppMotion.settle(
        _dismiss,
        target: 0,
        motion: AppMotion.sheet,
        reduced: MediaQuery.disableAnimationsOf(context),
      );
    }
  }

  void _pageChanged(int index) {
    _zoom.stop();
    widget.onPageChanged?.call(index);
    _transform.value = Matrix4.identity();
    setState(() {
      _index = index;
      _zoomed = false;
      _fullResolutionRequested = false;
    });
  }

  void _goTo(int index) {
    _pageMotion.value = _controller.offset;
    AppMotion.settle(
      _pageMotion,
      target: index * _controller.position.viewportDimension,
      motion: AppMotion.sheet,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
  }

  Future<void> _save() async {
    if (_saving || widget.urls.isEmpty) return;
    final url = widget.urls[_index];
    setState(() => _saving = true);
    try {
      final saved = await saveForumImage(url);
      if (mounted && saved) AppToast.show(context, '图片已保存');
    } catch (_) {
      if (mounted) AppToast.show(context, '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _chrome(Widget child) => AnimatedBuilder(
    animation: Listenable.merge([_enterChrome, _routeAnimation]),
    child: child,
    builder: (context, child) {
      final opacity =
          AppMotion.mediaFadeCurve.transform(_enterChrome.value) *
          (_viewerRoute?.closingChrome ?? 1);
      return IgnorePointer(
        ignoring: opacity == 0 || _closing,
        child: Opacity(opacity: opacity, child: child),
      );
    },
  );

  void _close() {
    if (!_closing) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeStatusChanged);
    _enterChrome.dispose();
    _pageMotion.dispose();
    _controller.dispose();
    _transform.dispose();
    _zoom.dispose();
    _dismiss.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foreground = ImageColors.viewerForeground;
    final page = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        systemOverlayStyle: AppSystemUi.lightIcons,
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        centerTitle: true,
        leading: _chrome(
          ChromeButton(
            tooltip: '关闭图片',
            icon: AppIcons.dismiss,
            onImage: true,
            onPressed: _close,
          ),
        ),
        actions: [
          if (widget.urls.isNotEmpty)
            _chrome(
              ChromeButton(
                tooltip: _saving ? '正在保存' : '保存图片',
                icon: AppIcons.update,
                onImage: true,
                onPressed: _saving ? null : _save,
              ),
            ),
        ],
        title: _chrome(
          Text(
            widget.urls.isEmpty
                ? '图片'
                : '${_index + 1} / ${widget.urls.length}',
            style: TextStyle(fontSize: AppType.sizeFootnote, color: foreground),
          ),
        ),
      ),
      body: widget.urls.isEmpty
          ? const SizedBox.shrink()
          : _dragged(
              PageView.builder(
                key: _viewportKey,
                controller: _controller,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const _ViewerPagePhysics(parent: BouncingScrollPhysics()),
                itemCount: widget.urls.length,
                onPageChanged: _pageChanged,
                itemBuilder: (context, i) => GestureDetector(
                  onDoubleTapDown: (details) =>
                      _tapPosition = details.localPosition,
                  onDoubleTap: _doubleTap,
                  child: InteractiveViewer(
                    transformationController: i == _index ? _transform : null,
                    minScale: 1,
                    maxScale: 5,
                    onInteractionStart: (_) => _zoom.stop(),
                    onInteractionUpdate: (_) {
                      final scale = _transform.value.getMaxScaleOnAxis();
                      final zoomed = scale > 1.02;
                      final needOriginal =
                          scale > 1.3 && !_fullResolutionRequested;
                      final releaseOriginal =
                          !zoomed && _fullResolutionRequested;
                      if (zoomed != _zoomed ||
                          needOriginal ||
                          releaseOriginal) {
                        setState(() {
                          _zoomed = zoomed;
                          if (needOriginal) _fullResolutionRequested = true;
                          if (releaseOriginal) _fullResolutionRequested = false;
                        });
                      }
                    },
                    child: RepaintBoundary(
                      child: Center(
                        child: _hero(
                          i,
                          Image(
                            image: i == _index && _fullResolutionRequested
                                ? ChhCachedImage(
                                    widget.urls[i],
                                    headers: chhImageHeaders,
                                  )
                                : i == widget.initialIndex &&
                                      widget.previewImage != null
                                ? widget.previewImage!
                                : widget.previewImageForIndex?.call(i) ??
                                      boundedNetworkImage(
                                        widget.urls[i],
                                        boundedImageDecodeWidth(
                                          MediaQuery.sizeOf(context).width,
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ),
                                        ),
                                      ),
                            color: AppTokens.of(context).isDark
                                ? ImageTokens.darkTint
                                : null,
                            colorBlendMode: BlendMode.modulate,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (context, _, _) => FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    AppIcons.image,
                                    size: 30,
                                    color: foreground,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '图片暂时无法加载',
                                    style: TextStyle(
                                      fontSize: AppType.sizeFootnote,
                                      color: foreground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: widget.urls.isEmpty
          ? null
          : _chrome(
              SafeArea(
                top: false,
                minimum: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ChromeButton(
                      tooltip: '上一张',
                      onImage: true,
                      onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                      icon: AppIcons.back,
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppMotion.fade,
                        child: Text(
                          _zoomed ? '双击还原' : '双击放大',
                          key: ValueKey(_zoomed),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppType.sizeFootnote,
                            color: foreground,
                          ),
                        ),
                      ),
                    ),
                    ChromeButton(
                      tooltip: '下一张',
                      onImage: true,
                      onPressed: _index < widget.urls.length - 1
                          ? () => _goTo(_index + 1)
                          : null,
                      icon: AppIcons.forward,
                    ),
                  ],
                ),
              ),
            ),
    );
    final statusHeight = MediaQuery.viewPaddingOf(context).top;
    return Listener(
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _cancelDrag();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_dismiss, _routeAnimation]),
        child: RepaintBoundary(child: page),
        builder: (context, child) {
          final progress =
              _viewerRoute?.flightProgress ?? _routeAnimation?.value ?? 1;
          final opacity =
              AppMotion.viewerScrimCurve.transform(progress) *
              (1 - _dismiss.value / MediaQuery.sizeOf(context).height).clamp(
                0.0,
                1.0,
              );
          return ColoredBox(
            key: const ValueKey('image-viewer-scrim'),
            color: ImageColors.viewerBackground.withValues(alpha: opacity),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child!,
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: statusHeight,
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    key: const ValueKey('image-viewer-status-style'),
                    value: opacity >= ImageTokens.viewerStatusThreshold
                        ? AppSystemUi.lightIcons
                        : _viewerRoute?.readerStyle() ??
                              AppSystemUi.forBrightness(
                                Theme.of(context).brightness,
                              ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dragged(Widget child) => AnimatedBuilder(
    animation: _dismiss,
    child: RepaintBoundary(child: child),
    builder: (context, child) => Transform.translate(
      key: const ValueKey('image-viewer-drag'),
      offset: Offset(0, _dismiss.value),
      child: Transform.scale(
        key: const ValueKey('image-viewer-drag-scale'),
        scale: MediaQuery.disableAnimationsOf(context)
            ? 1
            : 1 -
                  ImageTokens.dismissScale *
                      (_dismiss.value / MediaQuery.sizeOf(context).height)
                          .clamp(0.0, 1.0),
        child: child,
      ),
    ),
  );

  Widget _hero(int index, Widget child) {
    final tag =
        widget.heroTagForIndex?.call(index) ??
        (index == widget.initialIndex ? widget.heroTag : null);
    return tag != null && !MediaQuery.disableAnimationsOf(context)
        ? Hero(
            tag: tag,
            curve: _viewerRoute == null
                ? AppMotion.viewerHeroCurve
                : AppMotion.viewerHeroTakeoffCurve,
            reverseCurve: _viewerRoute?.returnCurve,
            flightShuttleBuilder: _imageFlight,
            child: child,
          )
        : child;
  }

  Widget _imageFlight(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final destination = (toContext.widget as Hero).child;
    if (direction == HeroFlightDirection.push) {
      return KeyedSubtree(
        key: const ValueKey('image-viewer-open-flight'),
        child: destination,
      );
    }
    final photo = fromContext.findRenderObject();
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final target = toContext.findRenderObject();
    if (photo is! RenderBox || viewport is! RenderBox || target is! RenderBox) {
      return destination;
    }
    final photoRect = MatrixUtils.transformRect(
      photo.getTransformTo(null),
      Offset.zero & photo.size,
    );
    final viewportRect = MatrixUtils.transformRect(
      viewport.getTransformTo(null),
      Offset.zero & viewport.size,
    );
    if (photoRect.isEmpty) return destination;
    final visible = photoRect.intersect(viewportRect);
    final targetRect = MatrixUtils.transformRect(
      target.getTransformTo(null),
      Offset.zero & target.size,
    );
    final RenderObject? targetViewport = RenderAbstractViewport.maybeOf(target);
    final media = MediaQuery.of(toContext);
    var targetBounds = targetViewport is RenderBox
        ? MatrixUtils.transformRect(
            targetViewport.getTransformTo(null),
            Offset.zero & targetViewport.size,
          )
        : Offset.zero & media.size;
    final reader = toContext.getInheritedWidgetOfExactType<ReadingBarAnchor>();
    if (reader != null) {
      // Reading chrome is painted above the viewport, not a clip ancestor.
      final hidden = reader.hiddenProgress.value;
      final bottom = reader.reducedMotion && hidden < 1
          ? reader.height
          : reader.height * (1 - hidden);
      targetBounds = targetBounds.intersect(
        Rect.fromLTRB(
          0,
          media.viewPadding.top + NavOverlay.barHeight,
          media.size.width,
          media.size.height -
              bottom.clamp(media.viewPadding.bottom, media.size.height),
        ),
      );
    }
    final arrival = targetRect.intersect(targetBounds);
    final targetAnimation = ModalRoute.of(toContext)?.animation;
    final roundedDestination = destination is ClipRRect
        ? AnimatedBuilder(
            animation: animation,
            child: destination.child,
            builder: (context, child) => ClipRRect(
              borderRadius: BorderRadiusGeometry.lerp(
                destination.borderRadius,
                BorderRadius.zero,
                animation.value.clamp(0.0, 1.0),
              )!,
              clipBehavior: destination.clipBehavior,
              child: child,
            ),
          )
        : destination;
    // Hero already includes the ancestor's zoom/pan in its flight rect. Only
    // carry the lost viewport clip; applying the matrix again would zoom twice.
    return Builder(
      builder: (flightContext) => ClipRect(
        key: const ValueKey('image-viewer-flight-clip'),
        clipper: _ImageFlightClipper(
          animation,
          visible.isEmpty ? Rect.zero : visible,
          arrival.isEmpty ? Rect.zero : arrival,
          flightContext,
          targetAnimation,
        ),
        child: roundedDestination,
      ),
    );
  }
}

class _ImageFlightClipper extends CustomClipper<Rect> {
  final Animation<double> animation;
  final Rect departureClip;
  final Rect arrivalClip;
  final BuildContext flightContext;
  final Animation<double>? targetAnimation;
  _ImageFlightClipper(
    this.animation,
    this.departureClip,
    this.arrivalClip,
    this.flightContext,
    this.targetAnimation,
  ) : super(reclip: Listenable.merge([animation, targetAnimation]));

  @override
  Rect getClip(Size size) {
    // The Hero overlay outlives the reader when Back is pressed again.
    // Stop painting it as soon as the route it was returning to leaves.
    final status = targetAnimation?.status;
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      return Rect.zero;
    }
    final clip = Rect.lerp(
      arrivalClip,
      departureClip,
      animation.value.clamp(0.0, 1.0),
    )!;
    final box = flightContext.findRenderObject()! as RenderBox;
    // Interpolate in screen space so shrinking the photo cannot expand its
    // visible area over the reader's toolbar. Convert only at paint time.
    return MatrixUtils.transformRect(
      Matrix4.inverted(box.getTransformTo(null)),
      clip,
    );
  }

  @override
  bool shouldReclip(_ImageFlightClipper oldClipper) =>
      departureClip != oldClipper.departureClip ||
      arrivalClip != oldClipper.arrivalClip ||
      flightContext != oldClipper.flightContext ||
      targetAnimation != oldClipper.targetAnimation ||
      animation != oldClipper.animation;
}
