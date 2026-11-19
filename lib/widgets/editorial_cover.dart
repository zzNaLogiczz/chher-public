/// A single visual object shared by an editorial card and its reading header.
library;

import 'dart:ui' as ui;
import 'dart:ui' show lerpDouble;
import 'package:flutter/foundation.dart';
import '../ui/balanced_title.dart';
import '../design/display_text.dart';
import '../design/motion.dart';
import '../design/typography.dart';

import 'package:flutter/material.dart';

import '../data/editorial_cover_cache.dart';
import '../design/tokens.dart';
import '../design/image_tokens.dart';
import '../design/shapes.dart';
import '../models/models.dart';
import 'net_image.dart';

/// Give each placement its own [heroTag], even when the article is repeated.
///
/// The caller supplies finite width/height and clips its desired corner radius.
/// Image, title, and scrim travel together during a Hero transition. Keeping
/// this surface self-contained avoids a separate title flight drifting from
/// its photograph.
class EditorialCover extends StatelessWidget {
  final PortalArticle article;
  final String heroTag;
  final bool expanded;
  final String? eyebrow;
  final BoxFit fit;
  final ValueListenable<double>? scrollOffset;

  /// 横滑卡只放图片,标题在图片下方;展开飞行时仍由目标页带出完整封面
  final bool showText;

  const EditorialCover({
    super.key,
    required this.article,
    required this.heroTag,
    this.expanded = false,
    this.eyebrow,
    this.fit = BoxFit.cover,
    this.showText = true,
    this.scrollOffset,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editorialCoverCache,
      builder: (context, _) => _buildCover(context),
    );
  }

  Widget _buildCover(BuildContext context) {
    final remembered = editorialCoverCache.lookup(article.aid);
    final effectiveUrl = remembered ?? article.coverUrl;
    final effectiveFit = remembered != null ? BoxFit.cover : fit;
    final contents = _CoverContents(
      article: article,
      eyebrow: eyebrow,
      coverUrl: effectiveUrl,
      fit: effectiveFit,
      showText: showText,
      feature: fit == BoxFit.contain,
      scrollOffset: expanded ? null : scrollOffset,
      topInset: expanded ? MediaQuery.viewPaddingOf(context).top : 0,
    );
    final child = expanded
        ? ClipRRect(child: contents)
        : AppClip(radius: AppRadii.lg, child: contents);
    // Reduced motion retains the same content without moving a large picture
    // across the screen. The page route can provide its short crossfade.
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(
      tag: heroTag,
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: (flightContext, animation, direction, from, to) {
        final expandedContext = direction == HeroFlightDirection.push
            ? to
            : from;
        final safeTop = MediaQuery.viewPaddingOf(expandedContext).top;
        // Freeze the image actually present on the source Hero at takeoff.
        // A cache update may rebuild the hidden destination during the flight,
        // but must not swap the photograph in its moving shuttle.
        final source = (from.widget as Hero).child;
        final sourceChild = switch (source) {
          AppClip(:final child) => child,
          ClipRRect(:final child) => child,
          _ => null,
        };
        final sourceContents = sourceChild is _CoverContents
            ? sourceChild
            : null;
        final destination = (to.widget as Hero).child;
        final destinationChild = switch (destination) {
          AppClip(:final child) => child,
          ClipRRect(:final child) => child,
          _ => null,
        };
        final collapsedContents = direction == HeroFlightDirection.push
            ? sourceContents
            : destinationChild is _CoverContents
            ? destinationChild
            : null;
        final flightOffset = animation.drive(
          Tween<double>(
            begin: collapsedContents?.scrollOffset?.value ?? 0,
            end: 0,
          ),
        );
        final flightUrl = sourceContents?.coverUrl ?? effectiveUrl;
        final flightFit = sourceContents?.fit ?? effectiveFit;
        return AnimatedBuilder(
          animation: animation,
          child: RepaintBoundary(
            child: _CoverContents(
              article: article,
              eyebrow: eyebrow,
              coverUrl: flightUrl,
              fit: flightFit,
              feature: fit == BoxFit.contain,
              scrollOffset: flightOffset,
              topInset: safeTop,
              flightProgress: animation,
              animateImage: false,
            ),
          ),
          // The header is square and the source card is rounded. Interpolate
          // this one shared outline, including the final frame, rather than
          // snapping its radius when the flight completes. Keep the photograph
          // mounted throughout both directions.
          builder: (context, child) => AppClip(
            radius: AppRadii.lg * (1 - animation.value.clamp(0.0, 1.0)),
            child: child!,
          ),
        );
      },
      child: child,
    );
  }
}

class _CoverContents extends StatelessWidget {
  // Video entries sometimes expose channel/link directories as their summary.
  // Hide that entire field rather than leaving a misleading partial sentence.
  static final _linkedSummary = RegExp(
    r'https?://|bilibili|youtube|youtu\.be',
    caseSensitive: false,
  );

  final PortalArticle article;
  final String? eyebrow;
  final BoxFit fit;
  final double topInset;
  final String? coverUrl;
  final bool animateImage;
  final Animation<double>? flightProgress;
  final bool showText;
  final bool feature;
  final ValueListenable<double>? scrollOffset;

  const _CoverContents({
    required this.article,
    this.eyebrow,
    required this.fit,
    required this.coverUrl,
    this.topInset = 0,
    this.animateImage = true,
    this.flightProgress,
    this.showText = true,
    this.feature = false,
    this.scrollOffset,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const foreground = ImageColors.foreground;
    const overlay = ImageColors.shade;
    // These subtrees do not depend on the interpolating Hero rectangle. Keep
    // them stable while only text constraints and the clipping rect change.
    Widget? photo = (coverUrl?.isNotEmpty ?? false) ? _photo(context) : null;
    if (photo != null && feature) {
      final fixedPhoto = photo;
      final overscan = LayoutBuilder(
        builder: (context, constraints) => OverflowBox(
          minHeight: constraints.maxHeight + HomeCoverTokens.parallaxLimit * 2,
          maxHeight: constraints.maxHeight + HomeCoverTokens.parallaxLimit * 2,
          child: RepaintBoundary(child: fixedPhoto),
        ),
      );
      photo = scrollOffset == null
          ? overscan
          : ValueListenableBuilder<double>(
              valueListenable: scrollOffset!,
              child: overscan,
              builder: (context, offset, child) => Transform.translate(
                key: const ValueKey('editorial-parallax'),
                offset: Offset(
                  0,
                  MediaQuery.disableAnimationsOf(context)
                      ? 0
                      : editorialParallaxOffset(offset),
                ),
                child: child,
              ),
            );
    }
    final shade = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: feature ? const [0, .38, .68, 1] : const [0, .28, .48, 1],
          colors: feature
              ? [
                  overlay.withValues(alpha: 0),
                  overlay.withValues(alpha: 0),
                  overlay.withValues(alpha: .5),
                  overlay.withValues(alpha: .82),
                ]
              : [
                  overlay.withValues(alpha: .34),
                  overlay.withValues(alpha: .02),
                  overlay.withValues(alpha: .12),
                  overlay.withValues(alpha: .92),
                ],
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final prominence = ((height - 260) / 160).clamp(0.0, 1.0);
          final textSize = feature
              ? HomeCoverTokens.titleSize
              : lerpDouble(
                  AppType.sizeTitle2,
                  AppType.sizeLargeTitle,
                  prominence,
                )!;
          final inset = feature
              ? HomeCoverTokens.inset
              : lerpDouble(20, 24, prominence)!;
          final title = normalizeDisplayText(article.title);
          final titleStyle = TextStyle(
            color: foreground,
            fontSize: textSize,
            height: 1.22,
            letterSpacing: -.55,
            fontWeight: FontWeight.w700,
          );
          final category = article.categoryName?.trim();
          final label =
              eyebrow ??
              ((category?.isNotEmpty ?? false) ? category! : 'CHH 精选');
          final rawSummary = article.summary?.trim();
          final summary =
              rawSummary != null && !_linkedSummary.hasMatch(rawSummary)
              ? rawSummary
              : null;
          // Keep the same text blocks at both endpoints. A height threshold
          // inserted a summary (and displaced the title) mid-flight.
          final showSummary =
              (summary?.isNotEmpty ?? false) &&
              MediaQuery.textScalerOf(context).scale(1) < 1.4;

          return Semantics(
            image: true,
            label: title,
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: fit == BoxFit.contain ? ImageColors.shade : t.fill,
                  ),
                  ?photo,
                  if (showText) shade,
                  if (showText && !feature)
                    Positioned(
                      top: inset + (flightProgress == null ? topInset : 0),
                      left: inset,
                      right: 64,
                      child: _flightTopInset(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .9),
                            fontSize: AppType.sizeFootnote,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .6,
                          ),
                        ),
                      ),
                    ),
                  if (showText)
                    Positioned(
                      left: inset,
                      right: inset,
                      bottom: inset,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (feature) ...[
                            Wrap(
                              spacing: 8,
                              children: [
                                Text(
                                  label,
                                  style: AppType.footnote.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (category?.isNotEmpty == true &&
                                    category != label)
                                  Text(
                                    category!,
                                    style: AppType.footnote.copyWith(
                                      color: foreground.withValues(alpha: .62),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (feature)
                            BalancedTitle(
                              title,
                              key: const ValueKey('editorial-balanced-title'),
                              style: titleStyle,
                              maxLines: 3,
                              measurementWidth:
                                  (MediaQuery.sizeOf(context).width -
                                          2 * (HomeTokens.inset + inset))
                                      .clamp(1.0, double.infinity),
                            )
                          else if (flightProgress != null)
                            Text(
                              title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            )
                          else
                            BalancedTitle(
                              title,
                              maxLines: 3,
                              style: titleStyle,
                            ),
                          if (showSummary) ...[
                            const SizedBox(height: 12),
                            Text(
                              normalizeDisplayText(summary!),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground.withValues(alpha: .84),
                                fontSize: AppType.sizeFootnote,
                                height: 1.6,
                              ),
                            ),
                          ] else if (!feature &&
                              (category?.isNotEmpty ?? false) &&
                              category != label) ...[
                            const SizedBox(height: 10),
                            Text(
                              category!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground.withValues(alpha: .82),
                                fontSize: AppType.sizeFootnote,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _flightTopInset({required Widget child}) => flightProgress == null
      ? child
      : AnimatedBuilder(
          animation: flightProgress!,
          child: child,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, topInset * flightProgress!.value),
            child: child,
          ),
        );

  Widget _photo(BuildContext context) {
    if (feature) {
      return _FeaturePhoto(
        coverUrl: coverUrl!,
        fallbackUrl: article.coverUrl,
        animate: animateImage,
      );
    }
    final photo = NetImage(
      key: ValueKey('$coverUrl:$fit'),
      url: coverUrl!,
      dimInDark: true,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
      // One cache key for source card, all flight frames and expanded header.
      decodeWidth: boundedImageDecodeWidth(
        MediaQuery.sizeOf(context).width,
        MediaQuery.devicePixelRatioOf(context),
      ),
    );
    if (!animateImage || MediaQuery.disableAnimationsOf(context)) return photo;
    return AnimatedSwitcher(
      duration: AppMotion.fade,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: photo,
    );
  }
}

/// The photograph travels at 85% of the surrounding card's scroll speed.
double editorialParallaxOffset(double offset) =>
    (offset * HomeCoverTokens.parallaxFactor).clamp(
      0.0,
      HomeCoverTokens.parallaxLimit,
    );

bool isEditorialPortrait(Size size) =>
    size.width > 0 &&
    size.height >= size.width * HomeCoverTokens.portraitThreshold;

class _FeaturePhoto extends StatefulWidget {
  final String coverUrl;
  final String? fallbackUrl;
  final bool animate;
  const _FeaturePhoto({
    required this.coverUrl,
    required this.fallbackUrl,
    required this.animate,
  });

  @override
  State<_FeaturePhoto> createState() => _FeaturePhotoState();
}

class _FeaturePhotoState extends State<_FeaturePhoto>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, value: 1);
  final _streams = <ImageStream, ImageStreamListener>{};
  ImageInfo? _wide;
  ImageInfo? _portrait;
  ui.Image? _blur;
  String? _wideUrl;
  String? _loadedCover;
  int? _decodeWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = boundedImageDecodeWidth(
      MediaQuery.sizeOf(context).width,
      MediaQuery.devicePixelRatioOf(context),
    );
    if (_decodeWidth != width) {
      _decodeWidth = width;
      _load();
    }
  }

  @override
  void didUpdateWidget(_FeaturePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coverUrl != oldWidget.coverUrl ||
        widget.fallbackUrl != oldWidget.fallbackUrl) {
      _load();
    }
  }

  void _load() {
    final changed = _loadedCover != null && _loadedCover != widget.coverUrl;
    _loadedCover = widget.coverUrl;
    if (changed) {
      _portrait?.dispose();
      _portrait = null;
      _fade.value = 1;
    }
    for (final entry in _streams.entries) {
      entry.key.removeListener(entry.value);
    }
    _streams.clear();
    final fallback = widget.fallbackUrl;
    if (fallback != null &&
        fallback.isNotEmpty &&
        (_wide == null || _wideUrl != fallback)) {
      _wideUrl = fallback;
      _resolve(fallback, (info, _) {
        _wide?.dispose();
        _wide = info;
        _blur?.dispose();
        _blur = null;
      });
    }
    if (widget.coverUrl != fallback) {
      _resolve(widget.coverUrl, (info, synchronous) {
        if (!isEditorialPortrait(
          Size(info.image.width.toDouble(), info.image.height.toDouble()),
        )) {
          info.dispose();
          return;
        }
        _portrait?.dispose();
        _portrait = info;
        if (changed && widget.animate) {
          _fade.duration = MediaQuery.disableAnimationsOf(context)
              ? AppMotion.reducedFade
              : HomeCoverTokens.portraitFade;
          _fade.forward(from: 0);
        } else {
          _fade.value = 1;
        }
      });
    }
  }

  void _resolve(String url, void Function(ImageInfo, bool) receive) {
    final stream = boundedNetworkImage(
      url,
      _decodeWidth!,
    ).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, synchronous) {
      if (!mounted) {
        info.dispose();
        return;
      }
      // Synchronous hits arrive during build; later arrivals need a rebuild.
      if (synchronous) {
        receive(info, true);
      } else {
        setState(() => receive(info, false));
      }
    }, onError: (Object _, StackTrace? _) {});
    _streams[stream] = listener;
    stream.addListener(listener);
  }

  void _prepareBlur(Size size) {
    final wide = _wide?.image;
    if (wide == null || size.isEmpty || !size.isFinite || _blur != null) {
      return;
    }
    _blur?.dispose();
    final width = HomeCoverTokens.blurDecodeWidth;
    final height = (width * size.height / size.width).ceil().clamp(1, 1024);
    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final fitted = applyBoxFit(
      BoxFit.cover,
      Size(wide.width.toDouble(), wide.height.toDouble()),
      bounds.size,
    );
    final source = Alignment.center.inscribe(
      fitted.source,
      Rect.fromLTWH(0, 0, wide.width.toDouble(), wide.height.toDouble()),
    );
    final sigma = HomeCoverTokens.blur * width / size.width;
    canvas.drawImageRect(
      wide,
      source,
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..color = ImageColors.shade.withValues(
          alpha: 1 - HomeCoverTokens.backdropBrightness,
        ),
    );
    final picture = recorder.endRecording();
    _blur = picture.toImageSync(width, height);
    picture.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _prepareBlur(constraints.biggest);
      return CustomPaint(
        key: const ValueKey('editorial-feature-photo'),
        painter: _FeaturePhotoPainter(
          wide: _wide?.image,
          portrait: _portrait?.image,
          blur: _blur,
          fade: _fade,
          colorFilter: AppTokens.of(context).isDark
              ? ImageTokens.darkFilter
              : null,
        ),
      );
    },
  );

  @override
  void dispose() {
    for (final entry in _streams.entries) {
      entry.key.removeListener(entry.value);
    }
    _wide?.dispose();
    _portrait?.dispose();
    _blur?.dispose();
    _fade.dispose();
    super.dispose();
  }
}

class _FeaturePhotoPainter extends CustomPainter {
  final ui.Image? wide;
  final ui.Image? portrait;
  final ui.Image? blur;
  final Animation<double> fade;
  final ColorFilter? colorFilter;
  _FeaturePhotoPainter({
    this.wide,
    this.portrait,
    this.blur,
    required this.fade,
    this.colorFilter,
  }) : super(repaint: fade);

  @override
  void paint(Canvas canvas, Size size) {
    if (blur case final image?) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()
          ..colorFilter = colorFilter
          ..filterQuality = FilterQuality.low,
      );
    }
    if (wide case final image?) {
      final height = size.width * image.height / image.width;
      // Paint alpha per strip instead of allocating a ShaderMask saveLayer.
      const strips = 32;
      for (var i = 0; i < strips; i++) {
        final fraction = i / strips;
        final alpha = ((1 - fraction) / .45).clamp(0.0, 1.0);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(
            0,
            image.height * fraction,
            image.width.toDouble(),
            image.height / strips,
          ),
          Rect.fromLTWH(
            0,
            HomeCoverTokens.parallaxLimit + height * fraction,
            size.width,
            height / strips + .5,
          ),
          Paint()
            ..color = ImageColors.foreground.withValues(alpha: alpha)
            ..colorFilter = colorFilter
            ..filterQuality = FilterQuality.low,
        );
      }
    }
    if (portrait case final image?) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: image,
        fit: BoxFit.cover,
        alignment: HomeCoverTokens.portraitAlignment,
        opacity: fade.value,
        colorFilter: colorFilter,
      );
    }
  }

  @override
  bool shouldRepaint(_FeaturePhotoPainter oldDelegate) =>
      oldDelegate.wide != wide ||
      oldDelegate.portrait != portrait ||
      oldDelegate.blur != blur ||
      oldDelegate.fade != fade ||
      oldDelegate.colorFilter != colorFilter;
}
