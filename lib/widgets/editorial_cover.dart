/// A single visual object shared by an editorial card and its reading header.
library;

import 'dart:ui' show lerpDouble;
import '../design/motion.dart';
import '../design/typography.dart';

import 'package:flutter/material.dart';

import '../data/editorial_cover_cache.dart';
import '../design/tokens.dart';
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
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(expanded ? 0 : AppRadii.lg),
      child: _CoverContents(
        article: article,
        eyebrow: eyebrow,
        coverUrl: effectiveUrl,
        fit: effectiveFit,
        showText: showText,
        topInset: expanded ? MediaQuery.viewPaddingOf(context).top : 0,
      ),
    );
    // Reduced motion retains the same content without moving a large picture
    // across the screen. The page route can provide its short crossfade.
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(
      tag: heroTag,
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: (flightContext, animation, direction, from, to) {
        // LayoutBuilder receives the interpolated Hero rectangle each frame;
        // its typography follows that rectangle continuously in both directions.
        // heroes.dart passes manifest.animation to this builder, NOT the
        // forward-only _proxyAnimation used by its rectangle tween. Thus the
        // value is 0 → 1 on push and 1 → 0 on pop. Using the same 24 → 0 tween
        // in both cases also keeps a push interrupted by pop continuous.
        final expandedContext = direction == HeroFlightDirection.push
            ? to
            : from;
        final safeTop = MediaQuery.viewPaddingOf(expandedContext).top;
        // Freeze the image actually present on the source Hero at takeoff.
        // A cache update may rebuild the hidden destination during the flight,
        // but must not swap the photograph in its moving shuttle.
        final source = (from.widget as Hero).child;
        final sourceContents =
            source is ClipRRect && source.child is _CoverContents
            ? source.child! as _CoverContents
            : null;
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
              topInset: safeTop,
              flightProgress: animation,
              animateImage: false,
            ),
          ),
          builder: (context, child) => ClipRRect(
            borderRadius: BorderRadius.circular(
              lerpDouble(AppRadii.lg, 0, animation.value)!,
            ),
            child: child,
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

  const _CoverContents({
    required this.article,
    this.eyebrow,
    required this.fit,
    required this.coverUrl,
    this.topInset = 0,
    this.animateImage = true,
    this.flightProgress,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const foreground = ImageColors.foreground;
    const overlay = ImageColors.shade;
    // These subtrees do not depend on the interpolating Hero rectangle. Keep
    // them stable while only text constraints and the clipping rect change.
    final photo = (coverUrl?.isNotEmpty ?? false) ? _photo(context) : null;
    final shade = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .28, .48, 1],
          colors: [
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
          final textSize = lerpDouble(
            AppType.sizeTitle2,
            AppType.sizeLargeTitle,
            prominence,
          )!;
          final inset = lerpDouble(20, 24, prominence)!;
          final category = article.categoryName?.trim();
          final label =
              eyebrow ??
              ((category?.isNotEmpty ?? false) ? category! : 'CHH 精选');
          final rawSummary = article.summary?.trim();
          final summary =
              rawSummary != null && !_linkedSummary.hasMatch(rawSummary)
              ? rawSummary
              : null;
          final showSummary =
              height >= 390 &&
              (summary?.isNotEmpty ?? false) &&
              MediaQuery.textScalerOf(context).scale(1) < 1.4;

          return Semantics(
            image: true,
            label: article.title,
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: fit == BoxFit.contain ? ImageColors.shade : t.fill,
                  ),
                  ?photo,
                  if (showText) shade,
                  if (showText)
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
                          Text(
                            article.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontSize: textSize,
                              height: 1.22,
                              letterSpacing: -.55,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (showSummary) ...[
                            const SizedBox(height: 12),
                            Text(
                              summary!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground.withValues(alpha: .84),
                                fontSize: AppType.sizeFootnote,
                                height: 1.6,
                              ),
                            ),
                          ] else if ((category?.isNotEmpty ?? false) &&
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
    final photo = NetImage(
      key: ValueKey('$coverUrl:$fit'),
      url: coverUrl!,
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
