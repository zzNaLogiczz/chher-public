/// 正文保留原图比例；短回复可使用紧凑宫格。图片浏览支持缩放与横向翻阅。
library;

import 'package:flutter/material.dart';
import '../design/icons.dart';
import '../ui/press.dart';
import '../design/motion.dart';
import '../design/typography.dart';
import '../ui/chrome_button.dart';

import '../design/tokens.dart';
import 'article_image.dart';
import 'cached_net_image.dart';
import 'net_image.dart';
import 'expressive_controls.dart';

class ImageGrid extends StatelessWidget {
  final List<String> urls;
  final bool preserveAspectRatio;
  const ImageGrid(this.urls, {super.key, this.preserveAspectRatio = false});

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
                all: urls,
                index: i,
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
      itemBuilder: (context, i) =>
          _ImageTile(url: urls[i], all: urls, index: i),
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
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      button: true,
      label: '查看第 ${index + 1} 张图片',
      child: PressHighlight(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ImageViewerPage(urls: all, initialIndex: index),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(natural ? 12 : 8),
          child: natural
              ? ArticleImage(url: url)
              : LayoutBuilder(
                  builder: (context, constraints) => Image(
                    image: boundedNetworkImage(
                      url,
                      boundedImageDecodeWidth(
                        constraints.maxWidth,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                    ),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    frameBuilder: (context, child, frame, synchronous) =>
                        synchronous || frame != null
                        ? child
                        : Container(color: t.fill),
                    errorBuilder: (context, _, _) => Container(
                      color: t.fill,
                      alignment: Alignment.center,
                      child: Icon(AppIcons.image, size: 22, color: t.text3),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class ImageViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const ImageViewerPage({super.key, required this.urls, this.initialIndex = 0});

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with SingleTickerProviderStateMixin {
  late final _controller = PageController(initialPage: _index);
  late int _index = widget.urls.isEmpty
      ? 0
      : widget.initialIndex.clamp(0, widget.urls.length - 1);
  final _transform = TransformationController();
  late final _zoom = AnimationController(
    vsync: this,
    duration: AppMotion.revealDuration,
  );
  Animation<Matrix4>? _zoomAnimation;
  Offset _tapPosition = Offset.zero;
  bool _zoomed = false;
  bool _fullResolutionRequested = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final animation = _zoomAnimation;
      if (animation != null) _transform.value = animation.value;
    });
  }

  void _doubleTap() {
    final target = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-_tapPosition.dx, -_tapPosition.dy, 0, 1)
            ..scaleByDouble(2, 2, 1, 1));
    _zoomAnimation = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOutCubic));
    setState(() {
      _zoomed = !_zoomed;
      if (_zoomed) _fullResolutionRequested = true;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _transform.value = target;
    } else {
      _zoom.forward(from: 0);
    }
  }

  void _pageChanged(int index) {
    _zoom.stop();
    _transform.value = Matrix4.identity();
    setState(() {
      _index = index;
      _zoomed = false;
      _fullResolutionRequested = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _transform.dispose();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foreground = ImageColors.viewerForeground;
    return Scaffold(
      backgroundColor: ImageColors.viewerBackground,
      appBar: AppBar(
        backgroundColor: ImageColors.viewerBackground,
        foregroundColor: foreground,
        centerTitle: true,
        leading: ChromeButton(
          tooltip: '关闭图片',
          icon: AppIcons.dismiss,
          onImage: true,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.urls.isEmpty ? '图片' : '${_index + 1} / ${widget.urls.length}',
          style: TextStyle(fontSize: AppType.sizeFootnote, color: foreground),
        ),
      ),
      body: widget.urls.isEmpty
          ? const SizedBox.shrink()
          : PageView.builder(
              controller: _controller,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
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
                    if (zoomed != _zoomed || needOriginal) {
                      setState(() {
                        _zoomed = zoomed;
                        if (needOriginal) _fullResolutionRequested = true;
                      });
                    }
                  },
                  child: RepaintBoundary(
                    child: Center(
                      child: Image(
                        image: i == _index && _fullResolutionRequested
                            ? ChhCachedImage(
                                widget.urls[i],
                                headers: chhImageHeaders,
                              )
                            : boundedNetworkImage(
                                widget.urls[i],
                                boundedImageDecodeWidth(
                                  MediaQuery.sizeOf(context).width,
                                  MediaQuery.devicePixelRatioOf(context),
                                ),
                              ),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, _, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.image, size: 30, color: foreground),
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
      bottomNavigationBar: widget.urls.isEmpty
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ChromeButton(
                    tooltip: '上一张',
                    onImage: true,
                    onPressed: _index > 0
                        ? () => _controller.previousPage(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : AppMotion.revealDuration,
                            curve: AppMotion.revealCurve,
                          )
                        : null,
                    icon: AppIcons.back,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : AppMotion.tapDuration,
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
                        ? () => _controller.nextPage(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : AppMotion.revealDuration,
                            curve: AppMotion.revealCurve,
                          )
                        : null,
                    icon: AppIcons.forward,
                  ),
                ],
              ),
            ),
    );
  }
}
