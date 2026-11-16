/// Shared previews for adjacent in-site links; metadata uses the existing cache.
library;

import 'package:flutter/material.dart';

import '../core/link_target.dart';
import '../data/link_preview_repository.dart';
import '../design/icons.dart';
import '../design/link_card_tokens.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../di.dart';
import '../models/models.dart';
import '../ui/feedback.dart';
import '../ui/press.dart';
import 'link_opener.dart';
import 'net_image.dart';

typedef SiteLinkOpener = void Function(LinkTarget target, String title);

String siteLinkDate(DateTime date, {DateTime? now}) =>
    '${date.year == (now ?? DateTime.now()).year ? '' : '${date.year}年'}${date.month}月${date.day}日';

bool _urlLabel(String label) =>
    label.trim().isEmpty ||
    RegExp(
      r'^(?:https?://|/|www\.|(?:thread|article)-\d|(?:forum|portal)\.php|(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:[/?#]|$))',
      caseSensitive: false,
    ).hasMatch(label.trim());

String siteLinkFallbackTitle(SiteLinkBlock block) => _urlLabel(block.label)
    ? (block.target is ThreadLink ? '站内帖子' : '站内文章')
    : block.label.trim();

class SiteLinkCard extends StatelessWidget {
  final SiteLinkBlock block;
  final bool compact;
  final LinkPreviewRepository? repository;
  final SiteLinkOpener? onOpen;

  const SiteLinkCard({
    super.key,
    required this.block,
    this.compact = false,
    this.repository,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) => SiteLinkGroupCard(
    blocks: [block],
    compact: compact,
    repository: repository,
    onOpen: onOpen,
  );
}

class SiteLinkGroupCard extends StatefulWidget {
  final List<SiteLinkBlock> blocks;
  final bool compact;
  final bool grouped;
  final bool first;
  final bool last;
  final LinkPreviewRepository? repository;
  final SiteLinkOpener? onOpen;

  const SiteLinkGroupCard({
    super.key,
    required this.blocks,
    this.compact = false,
    this.grouped = false,
    this.first = true,
    this.last = true,
    this.repository,
    this.onOpen,
  });

  @override
  State<SiteLinkGroupCard> createState() => _SiteLinkGroupCardState();
}

class _PreviewEntry {
  final LinkTarget target;
  LinkPreview? preview;
  bool loading;
  _PreviewEntry(this.target, this.preview, {required this.loading});
}

class _SiteLinkGroupCardState extends State<SiteLinkGroupCard> {
  final _entries = <String, _PreviewEntry>{};
  LinkPreviewRepository get _repo => widget.repository ?? linkPreviewRepo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteLinkGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _entries.clear();
    _load();
  }

  void _load() {
    final keys = widget.blocks.map((b) => b.target.key).toSet();
    _entries.removeWhere((key, _) => !keys.contains(key));
    for (final block in widget.blocks) {
      final target = block.target;
      if (_entries.containsKey(target.key)) continue;
      final hit = _repo.cached(target);
      final entry = _PreviewEntry(
        target,
        hit,
        loading: hit == null && !_repo.hasFailed(target),
      );
      _entries[target.key] = entry;
      if (!entry.loading) continue;
      _repo.preview(target).then((preview) {
        if (!mounted || _entries[target.key] != entry) return;
        setState(() {
          entry.preview = preview;
          entry.loading = false;
        });
      });
    }
  }

  void _open(SiteLinkBlock block) {
    final title =
        _entries[block.target.key]?.preview?.title ??
        siteLinkFallbackTitle(block);
    if (widget.onOpen case final open?) {
      open(block.target, title);
    } else {
      openLinkTarget(context, block.target, title: title);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildCard);

  Widget _buildCard(BuildContext context, BoxConstraints constraints) {
    final t = AppTokens.of(context);
    final compact = widget.compact;
    final first = !widget.grouped || widget.first;
    final last = !widget.grouped || widget.last;
    final radius = Radius.circular(
      compact ? LinkCardTokens.compactRadius : LinkCardTokens.radius,
    );
    final inset = compact ? LinkCardTokens.compactInset : LinkCardTokens.inset;
    final shadows = compact ? <BoxShadow>[] : LinkCardTokens.shadow(t);
    final geometries = [
      for (final block in widget.blocks)
        _RowGeometry(
          context,
          compact: compact,
          width: constraints.maxWidth - inset * 2,
          title:
              _entries[block.target.key]?.preview?.title ??
              siteLinkFallbackTitle(block),
        ),
    ];
    final background = compact ? t.fill : t.surface;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: first ? radius : Radius.zero,
          topRight: first ? radius : Radius.zero,
          bottomLeft: last ? radius : Radius.zero,
          bottomRight: last ? radius : Radius.zero,
        ),
        boxShadow: compact ? null : shadows,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          inset,
          first ? inset : 0,
          inset,
          last ? inset : 0,
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, block) in widget.blocks.indexed)
                  _PreviewRow(
                    key: ValueKey((index, block.target.key)),
                    block: block,
                    entry: _entries[block.target.key]!,
                    geometry: geometries[index],
                    onOpen: () => _open(block),
                  ),
              ],
            ),
            // One breathing layer for the whole group, containing only bars.
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: SkeletonPulse(
                    active: _entries.values.any((e) => e.loading),
                    child: Column(
                      children: [
                        for (final (index, block) in widget.blocks.indexed)
                          _SkeletonRow(
                            entry: _entries[block.target.key]!,
                            geometry: geometries[index],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.grouped || compact) return card;
    final extent = shadows.fold<double>(0, (largest, shadow) {
      final edge =
          shadow.blurRadius * 2 +
          shadow.spreadRadius.abs() +
          shadow.offset.distance;
      return edge > largest ? edge : largest;
    });
    return ClipRect(
      clipBehavior: Clip.hardEdge,
      clipper: _SliceShadowClipper(first: first, last: last, extent: extent),
      child: card,
    );
  }
}

// Internal slice edges share a surface; keep shadows only around the group.
class _SliceShadowClipper extends CustomClipper<Rect> {
  final bool first;
  final bool last;
  final double extent;
  const _SliceShadowClipper({
    required this.first,
    required this.last,
    required this.extent,
  });
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -extent,
    first ? -extent : 0,
    size.width + extent,
    size.height + (last ? extent : 0),
  );
  @override
  bool shouldReclip(_SliceShadowClipper oldClipper) =>
      first != oldClipper.first ||
      last != oldClipper.last ||
      extent != oldClipper.extent;
}

class _RowGeometry {
  final bool compact;
  late final double titleHeight;
  final double metaHeight;
  _RowGeometry(
    BuildContext context, {
    required this.compact,
    required double width,
    required String title,
  }) : metaHeight =
           MediaQuery.textScalerOf(context).scale(
             (compact
                     ? LinkCardTokens.compactMetadata
                     : LinkCardTokens.metadata)
                 .fontSize!,
           ) *
           1.4 {
    // Share actual title height with the group's skeleton overlay.
    final painter =
        TextPainter(
          text: TextSpan(
            text: title,
            style: DefaultTextStyle.of(context).style.merge(titleStyle),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 2,
          ellipsis: '…',
        )..layout(
          maxWidth: (width - padding.horizontal - marker - gap - 22).clamp(
            0,
            double.infinity,
          ),
        );
    titleHeight = painter.height;
    painter.dispose();
  }
  double get marker =>
      compact ? LinkCardTokens.compactMarker : LinkCardTokens.marker;
  double get gap => compact ? 10 : 12;
  double get textHeight => titleHeight + 4 + metaHeight;
  double get rowHeight => textHeight < marker ? marker : textHeight;
  EdgeInsets get padding =>
      compact ? LinkCardTokens.compactPadding : LinkCardTokens.rowPadding;
  TextStyle get titleStyle =>
      compact ? LinkCardTokens.compactTitle : LinkCardTokens.title;
  TextStyle get metaStyle =>
      compact ? LinkCardTokens.compactMetadata : LinkCardTokens.metadata;
}

class _SkeletonRow extends StatelessWidget {
  final _PreviewEntry entry;
  final _RowGeometry geometry;
  const _SkeletonRow({required this.entry, required this.geometry});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final g = geometry;
    Widget bar(double factor, double height, String key) =>
        FractionallySizedBox(
          widthFactor: factor,
          alignment: Alignment.centerLeft,
          child: Container(
            key: ValueKey(key),
            height: height,
            decoration: BoxDecoration(
              color: LinkCardTokens.skeleton(t),
              borderRadius: BorderRadius.circular(
                LinkCardTokens.skeletonRadius,
              ),
            ),
          ),
        );
    return Padding(
      padding: g.padding,
      child: SizedBox(
        height: g.rowHeight,
        child: Row(
          children: [
            SizedBox(width: g.marker + g.gap),
            Expanded(
              child: AnimatedOpacity(
                opacity: entry.loading ? 1 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? AppMotion.reducedFade
                    : AppMotion.fade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: g.titleHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: bar(.78, 13, 'site-card-title-placeholder'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: g.metaHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: bar(.38, 10, 'site-card-date-placeholder'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatefulWidget {
  final SiteLinkBlock block;
  final _PreviewEntry entry;
  final _RowGeometry geometry;
  final VoidCallback onOpen;
  const _PreviewRow({
    super.key,
    required this.block,
    required this.entry,
    required this.geometry,
    required this.onOpen,
  });
  @override
  State<_PreviewRow> createState() => _PreviewRowState();
}

class _PreviewRowState extends State<_PreviewRow>
    with SingleTickerProviderStateMixin {
  late final _arrival = AnimationController(
    vsync: this,
    value: widget.entry.loading ? 0 : 1,
  );
  @override
  void didUpdateWidget(covariant _PreviewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.loading) {
      _arrival.value = 0;
    } else if (_arrival.value == 0) {
      _arrival.duration = MediaQuery.disableAnimationsOf(context)
          ? AppMotion.reducedFade
          : AppMotion.fade;
      _arrival.forward();
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final g = widget.geometry;
    final preview = widget.entry.preview;
    final isThread = preview?.isThread ?? widget.block.target is ThreadLink;
    final title = preview?.title ?? siteLinkFallbackTitle(widget.block);
    final failed = !widget.entry.loading && preview == null;
    final background = g.compact ? t.surface : t.fill;
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        g.compact
            ? LinkCardTokens.compactRadius - LinkCardTokens.compactInset
            : LinkCardTokens.radius - LinkCardTokens.inset,
      ),
      child: PressScale(
        scale: AppPressScale.content,
        pressedColor: t.fill,
        onTap: widget.onOpen,
        semanticLabel: '${isThread ? '帖子' : '文章'} $title',
        child: Padding(
          padding: g.padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  g.compact
                      ? LinkCardTokens.compactMarkerRadius
                      : LinkCardTokens.markerRadius,
                ),
                child: SizedBox.square(
                  dimension: g.marker,
                  child: ColoredBox(
                    color: background,
                    child: _CoverMarker(
                      url: preview?.coverUrl,
                      size: g.marker,
                      fallback: Icon(
                        isThread ? AppIcons.thread : AppIcons.article,
                        size: g.compact ? 17 : 20,
                        color: t.text3,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: g.gap),
              Expanded(
                child: SizedBox(
                  height: g.textHeight,
                  child: FadeTransition(
                    opacity: _arrival,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: g.titleHeight,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: g.titleStyle.copyWith(
                              color: failed ? t.text2 : t.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: g.metaHeight,
                          child: failed && _urlLabel(widget.block.label)
                              ? Text(
                                  '点开查看原帖',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: g.metaStyle.copyWith(color: t.text3),
                                )
                              : Row(
                                  children: [
                                    if (preview?.author case final author?) ...[
                                      Flexible(
                                        child: Text(
                                          author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: g.metaStyle.copyWith(
                                            color: t.text2,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (preview?.time != null)
                                        const SizedBox(width: 10),
                                    ],
                                    if (preview?.time case final date?)
                                      Flexible(
                                        child: Text(
                                          siteLinkDate(date),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: g.metaStyle.copyWith(
                                            color: t.text3,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: g.textHeight,
                child: Center(
                  child: Icon(AppIcons.forward, size: 14, color: t.text3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverMarker extends StatelessWidget {
  final String? url;
  final double size;
  final Widget fallback;
  const _CoverMarker({
    required this.url,
    required this.size,
    required this.fallback,
  });
  @override
  Widget build(BuildContext context) {
    if (url == null) return fallback;
    return Image(
      image: boundedNetworkImage(
        url!,
        boundedImageDecodeWidth(size, MediaQuery.devicePixelRatioOf(context)),
      ),
      width: size,
      height: size,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, synchronous) => synchronous
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                fallback,
                AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? AppMotion.reducedFade
                      : AppMotion.fade,
                  child: child,
                ),
              ],
            ),
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
