import 'package:flutter/material.dart';
import '../ui/hit_slop.dart';

import '../design/feedback.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../ui/press.dart';
import 'net_image.dart';

/// Keeps notification feedback in the panel’s own palette.
class PostFeedbackHighlight extends InheritedWidget {
  final double strength;
  const PostFeedbackHighlight({
    super.key,
    required this.strength,
    required super.child,
  });

  static Color backgroundOf(
    BuildContext context,
    Color original, {
    Color? emphasis,
  }) {
    final highlight = context
        .dependOnInheritedWidgetOfExactType<PostFeedbackHighlight>();
    if (highlight == null || highlight.strength == 0) return original;
    final t = AppTokens.of(context);
    final base = Color.alphaBlend(original, t.bg);
    final target = Color.alphaBlend(emphasis ?? t.fill3, base);
    return Color.lerp(base, target, highlight.strength)!;
  }

  @override
  bool updateShouldNotify(PostFeedbackHighlight oldWidget) =>
      strength != oldWidget.strength;
}

// Participation is metadata, not a score type. Unknown summaries stay intact.
List<RatingSummaryItem> _scores(PostRating rating) =>
    rating.items.where((item) => item.label != '参与人数').toList();
bool _hasRating(PostRating? rating) => rating != null && !rating.isEmpty;
bool _negative(String score) => RegExp(r'^\s*[-−]').hasMatch(score);
String _summaryText(RatingSummaryItem item) =>
    item.value == null ? item.label : '${item.value} ${item.label}';

class OpeningFeedback extends StatelessWidget {
  final PostRating? rating;
  final List<PostComment> comments;
  const OpeningFeedback({super.key, this.rating, this.comments = const []});

  @override
  Widget build(BuildContext context) =>
      _FeedbackCards(rating: rating, comments: comments, opening: true);
}

class FloorFeedback extends StatelessWidget {
  final PostRating? rating;
  final List<PostComment> comments;
  const FloorFeedback({super.key, this.rating, this.comments = const []});

  @override
  Widget build(BuildContext context) =>
      _FeedbackCards(rating: rating, comments: comments, opening: false);
}

class _FeedbackCards extends StatelessWidget {
  final PostRating? rating;
  final List<PostComment> comments;
  final bool opening;
  const _FeedbackCards({
    required this.rating,
    required this.comments,
    required this.opening,
  });

  @override
  Widget build(BuildContext context) {
    final hasRating = _hasRating(rating);
    if (!hasRating && comments.isEmpty) return const SizedBox.shrink();
    final strip =
        !opening &&
        hasRating &&
        rating!.entries.length == 1 &&
        _scores(rating!).length == 1 &&
        (rating!.participants == null || rating!.participants == 1);
    return Padding(
      padding: EdgeInsets.only(
        top: opening ? FeedbackMetrics.openingTop : FeedbackMetrics.floorTop,
        bottom: FeedbackMetrics.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasRating)
            if (strip)
              _RatingStrip(rating: rating!)
            else
              _RatingCard(rating: rating!, opening: opening),
          if (hasRating && comments.isNotEmpty)
            const SizedBox(height: FeedbackMetrics.cardGap),
          if (comments.isNotEmpty)
            _CommentsCard(comments: comments, opening: opening),
        ],
      ),
    );
  }
}

class _RatingCard extends StatefulWidget {
  final PostRating rating;
  final bool opening;
  const _RatingCard({required this.rating, required this.opening});
  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final opening = widget.opening;
    final entries = widget.rating.entries;
    final fold = opening
        ? FeedbackMetrics.openingFold
        : FeedbackMetrics.compactFold;
    final inset = opening
        ? FeedbackMetrics.inset
        : FeedbackMetrics.compactInset;
    return Container(
      decoration: BoxDecoration(
        color: PostFeedbackHighlight.backgroundOf(
          context,
          opening ? t.greenFill : t.greenSoft,
          emphasis: t.green.withValues(alpha: .10),
        ),
        borderRadius: BorderRadius.circular(
          opening ? FeedbackMetrics.cardRadius : FeedbackMetrics.floorRadius,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: inset,
              vertical: opening
                  ? FeedbackMetrics.headerVPad
                  : FeedbackMetrics.floorHeaderVPad,
            ),
            child: _RatingHeader(rating: widget.rating, opening: opening),
          ),
          if (entries.isNotEmpty) ...[
            _Rule(color: t.greenLine),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: inset,
                vertical: FeedbackMetrics.tinyGap,
              ),
              child: Column(
                children: [
                  for (final entry in entries.take(fold))
                    _RatingRow(entry: entry, opening: opening),
                  _Reveal(
                    open: _expanded,
                    child: Column(
                      children: [
                        for (final entry in entries.skip(fold))
                          _RatingRow(entry: entry, opening: opening),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (entries.length > fold)
            _ExpandButton(
              expanded: _expanded,
              label: '展开全部 ${entries.length} 条评分',
              color: t.green,
              ruleColor: t.greenLine,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

class _RatingHeader extends StatelessWidget {
  final PostRating rating;
  final bool opening;
  const _RatingHeader({required this.rating, required this.opening});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final items = _scores(rating);
    final participants = rating.participants;
    return Wrap(
      spacing: FeedbackMetrics.headerGap,
      runSpacing: FeedbackMetrics.tinyGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final item in items)
          if (item.value != null)
            _SummaryNumber(
              value: item.value!,
              label: item.label,
              opening: opening,
            )
          else
            Text(
              item.label,
              style: TextStyle(
                fontSize: opening
                    ? FeedbackMetrics.summaryLabelSize
                    : FeedbackMetrics.floorSummaryLabelSize,
                color: t.green,
              ),
            ),
        if (participants != null)
          _SummaryNumber(
            value: '$participants',
            label: '人评分',
            opening: opening,
          ),
        _AvatarStack(
          rating: rating,
          limit: FeedbackMetrics.headerAvatars,
          size: opening
              ? FeedbackMetrics.summaryAvatar
              : FeedbackMetrics.floorSummaryAvatar,
          overlap: opening
              ? FeedbackMetrics.avatarOverlap
              : FeedbackMetrics.compactOverlap,
          border: opening
              ? FeedbackMetrics.avatarBorder
              : FeedbackMetrics.compactAvatarBorder,
          background: opening ? t.greenFill : t.greenSoft,
          showRemaining: true,
        ),
      ],
    );
  }
}

class _SummaryNumber extends StatelessWidget {
  final String value;
  final String label;
  final bool opening;
  const _SummaryNumber({
    required this.value,
    required this.label,
    required this.opening,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: opening
                  ? FeedbackMetrics.summarySize
                  : FeedbackMetrics.floorSummarySize,
              fontWeight: FontWeight.w600,
              color: _negative(value) ? t.red : t.green,
              fontFeatures: FeedbackMetrics.tabular,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: TextStyle(
              fontSize: opening
                  ? FeedbackMetrics.summaryLabelSize
                  : FeedbackMetrics.floorSummaryLabelSize,
              color: t.green,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final RatingEntry entry;
  final bool opening;
  const _RatingRow({required this.entry, this.opening = false});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reason = entry.reason?.trim();
    final size = opening
        ? FeedbackMetrics.rowSize
        : FeedbackMetrics.capsuleSize;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: opening
            ? FeedbackMetrics.rowPadding
            : FeedbackMetrics.compactRowPadding,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final userWidth =
              (constraints.maxWidth * FeedbackMetrics.userFraction).clamp(
                0.0,
                opening
                    ? FeedbackMetrics.userWidth
                    : FeedbackMetrics.compactUserWidth,
              );
          return Row(
            children: [
              _Avatar(
                url: entry.avatarUrl,
                size: opening
                    ? FeedbackMetrics.rowAvatar
                    : FeedbackMetrics.smallAvatar,
              ),
              const SizedBox(width: FeedbackMetrics.gap),
              SizedBox(
                width: userWidth,
                child: Text(
                  entry.user,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
              const SizedBox(width: FeedbackMetrics.gap),
              SizedBox(
                width: opening
                    ? FeedbackMetrics.scoreWidth
                    : FeedbackMetrics.compactScoreWidth,
                child: Text(
                  entry.score,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    fontFeatures: FeedbackMetrics.tabular,
                    color: _negative(entry.score) ? t.red : t.green,
                  ),
                ),
              ),
              const SizedBox(width: FeedbackMetrics.gap),
              Expanded(
                child: Text(
                  reason == null || reason.isEmpty ? '—' : reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size,
                    color: reason == null || reason.isEmpty ? t.text3 : t.text2,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RatingStrip extends StatelessWidget {
  final PostRating rating;
  const _RatingStrip({required this.rating});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final entry = rating.entries.single;
    final reason = entry.reason?.trim();
    return Container(
      height: FeedbackMetrics.stripHeight,
      padding: const EdgeInsets.symmetric(horizontal: FeedbackMetrics.gap),
      decoration: BoxDecoration(
        color: PostFeedbackHighlight.backgroundOf(
          context,
          t.greenSoft,
          emphasis: t.green.withValues(alpha: .10),
        ),
        borderRadius: BorderRadius.circular(FeedbackMetrics.panelRadius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _Avatar(
                    url: entry.avatarUrl,
                    size: FeedbackMetrics.floorAvatar,
                  ),
                  const SizedBox(width: FeedbackMetrics.gap),
                  Flexible(
                    child: Text(
                      entry.user,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: FeedbackMetrics.rowSize,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: FeedbackMetrics.gap),
                  Flexible(
                    child: Text(
                      '${entry.score} ${_scores(rating).single.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: FeedbackMetrics.rowSize,
                        fontWeight: FontWeight.w700,
                        color: _negative(entry.score) ? t.red : t.green,
                        fontFeatures: FeedbackMetrics.tabular,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(width: FeedbackMetrics.gap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      constraints.maxWidth * FeedbackMetrics.reasonFraction,
                ),
                child: Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: FeedbackMetrics.rowSize,
                    color: t.text2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentsCard extends StatefulWidget {
  final List<PostComment> comments;
  final bool opening;
  const _CommentsCard({required this.comments, required this.opening});
  @override
  State<_CommentsCard> createState() => _CommentsCardState();
}

class _CommentsCardState extends State<_CommentsCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        widget.opening ? FeedbackMetrics.inset : FeedbackMetrics.compactInset,
        FeedbackMetrics.compactInset,
        widget.opening ? FeedbackMetrics.inset : FeedbackMetrics.compactInset,
        FeedbackMetrics.tinyGap,
      ),
      decoration: BoxDecoration(
        color: PostFeedbackHighlight.backgroundOf(context, Colors.transparent),
        border: Border.all(color: t.separator, width: AppSpace.hairline),
        borderRadius: BorderRadius.circular(
          widget.opening
              ? FeedbackMetrics.cardRadius
              : FeedbackMetrics.floorRadius,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '点评 ${widget.comments.length}',
            style: TextStyle(
              fontSize: FeedbackMetrics.labelSize,
              fontWeight: FontWeight.w600,
              color: t.text3,
            ),
          ),
          for (final comment in widget.comments.take(
            FeedbackMetrics.compactFold,
          ))
            _CommentRow(comment: comment),
          _Reveal(
            open: _expanded,
            child: Column(
              children: [
                for (final comment in widget.comments.skip(
                  FeedbackMetrics.compactFold,
                ))
                  _CommentRow(comment: comment),
              ],
            ),
          ),
          if (widget.comments.length > FeedbackMetrics.compactFold)
            _ExpandButton(
              expanded: _expanded,
              label: '展开全部 ${widget.comments.length} 条点评',
              color: t.accent,
              ruleColor: t.separator,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final PostComment comment;
  const _CommentRow({required this.comment});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FeedbackMetrics.tinyGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(url: comment.avatarUrl, size: FeedbackMetrics.smallAvatar),
          const SizedBox(width: FeedbackMetrics.gap),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: FeedbackMetrics.commentSize,
                  height: FeedbackMetrics.lineHeight,
                  color: t.text2,
                ),
                children: [
                  TextSpan(
                    text: comment.author,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  TextSpan(text: ' ${comment.text}'),
                  if (comment.timeRaw?.isNotEmpty == true)
                    TextSpan(
                      text: ' ${comment.timeRaw}',
                      style: TextStyle(
                        fontSize: FeedbackMetrics.labelSize,
                        color: t.text3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CommentFeedback extends StatefulWidget {
  final PostRating? rating;
  final List<PostComment> comments;
  const CommentFeedback({super.key, this.rating, this.comments = const []});
  @override
  State<CommentFeedback> createState() => _CommentFeedbackState();
}

class _CommentFeedbackState extends State<CommentFeedback> {
  bool _ratingOpen = false;
  bool _commentsOpen = false;

  bool _expandable(PostRating rating) =>
      (rating.participants ?? 0) > 1 ||
      rating.entries.length > 1 ||
      _scores(rating).length > 1 ||
      // Incomplete summaries must not hide known details or imply a total count.
      (rating.entries.isNotEmpty &&
          !_scores(rating).any((item) => item.value != null)) ||
      rating.entries.any((entry) => entry.reason?.trim().isNotEmpty == true);

  String _label(PostRating rating) {
    if (rating.participants == 1 && rating.entries.isNotEmpty) {
      final entry = rating.entries.first;
      return '${entry.user} ${entry.score}';
    }
    final scores = _scores(rating);
    final first = scores.where((item) => item.value != null).firstOrNull;
    final summary = first != null
        ? _summaryText(first)
        : scores.map(_summaryText).join(' · ');
    return '${summary.isEmpty ? '评分' : summary}${rating.participants == null ? '' : ' · ${rating.participants}人'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final rating = widget.rating;
    final hasRating = _hasRating(rating);
    if (!hasRating && widget.comments.isEmpty) return const SizedBox.shrink();
    return HitSlopRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: FeedbackMetrics.smallGap,
            runSpacing: FeedbackMetrics.smallGap,
            children: [
              if (hasRating)
                _Capsule(
                  label: _label(rating!),
                  semanticLabel:
                      '评分${rating.participants == null ? '' : '，${rating.participants} 人'}${_expandable(rating) ? (_ratingOpen ? '，收起明细' : '，展开明细') : ''}',
                  color:
                      _negative(
                        rating.participants == 1 && rating.entries.isNotEmpty
                            ? rating.entries.first.score
                            : _scores(rating)
                                      .where((item) => item.value != null)
                                      .firstOrNull
                                      ?.value ??
                                  '',
                      )
                      ? t.red
                      : t.green,
                  background: _ratingOpen ? t.greenFill : t.greenSoft,
                  open: _ratingOpen,
                  onTap: _expandable(rating)
                      ? () => setState(() => _ratingOpen = !_ratingOpen)
                      : null,
                  leading: _AvatarStack(
                    rating: rating,
                    limit: FeedbackMetrics.capsuleAvatars,
                    size: FeedbackMetrics.floorAvatar,
                    overlap: FeedbackMetrics.capsuleOverlap,
                    border: FeedbackMetrics.compactAvatarBorder,
                    background: t.bg,
                  ),
                ),
              if (widget.comments.isNotEmpty)
                _Capsule(
                  label: '点评 ${widget.comments.length}',
                  semanticLabel:
                      '点评 ${widget.comments.length} 条，${_commentsOpen ? '收起' : '展开'}',
                  color: t.text2,
                  background: _commentsOpen ? t.fill : t.fill3,
                  open: _commentsOpen,
                  onTap: () => setState(() => _commentsOpen = !_commentsOpen),
                  leading: Icon(
                    AppIcons.comments,
                    size: FeedbackMetrics.arrowSize,
                    color: t.text2,
                  ),
                ),
            ],
          ),
          if (hasRating)
            _Reveal(
              open: _ratingOpen && _expandable(rating!),
              child: _Panel(
                color: PostFeedbackHighlight.backgroundOf(
                  context,
                  t.greenSoft,
                  emphasis: t.green.withValues(alpha: .10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_scores(rating!).length > 1)
                      Wrap(
                        spacing: FeedbackMetrics.compactInset,
                        runSpacing: FeedbackMetrics.tinyGap,
                        children: [
                          for (final item in _scores(rating))
                            Text(
                              _summaryText(item),
                              style: TextStyle(
                                fontSize: FeedbackMetrics.labelSize,
                                fontWeight: FontWeight.w700,
                                color: _negative(item.value ?? '')
                                    ? t.red
                                    : t.green,
                                fontFeatures: FeedbackMetrics.tabular,
                              ),
                            ),
                        ],
                      ),
                    for (final entry in rating.entries)
                      _RatingRow(entry: entry),
                  ],
                ),
              ),
            ),
          if (widget.comments.isNotEmpty)
            _Reveal(
              open: _commentsOpen,
              child: _Panel(
                color: t.fill3,
                child: Column(
                  children: [
                    for (final comment in widget.comments)
                      _CommentRow(comment: comment),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final Color color;
  final Color background;
  final bool open;
  final VoidCallback? onTap;
  final Widget leading;
  const _Capsule({
    required this.label,
    required this.semanticLabel,
    required this.color,
    required this.background,
    required this.open,
    required this.onTap,
    required this.leading,
  });
  @override
  Widget build(BuildContext context) => HitSlopTarget(
    enabled: onTap != null,
    child: Semantics(
      expanded: onTap == null ? null : open,
      child: PressScale(
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: Container(
          height: FeedbackMetrics.capsuleHeight,
          constraints: const BoxConstraints(
            minWidth: FeedbackMetrics.touchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: FeedbackMetrics.smallGap,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(FeedbackMetrics.floorRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: FeedbackMetrics.smallGap),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: FeedbackMetrics.capsuleSize,
                    fontWeight: FontWeight.w600,
                    fontFeatures: FeedbackMetrics.tabular,
                    color: color,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: FeedbackMetrics.tinyGap),
                _Arrow(open: open, color: color),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Panel({required this.color, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(
      top: FeedbackMetrics.smallGap,
      bottom: FeedbackMetrics.tinyGap,
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: FeedbackMetrics.compactInset,
      vertical: FeedbackMetrics.smallGap,
    ),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(FeedbackMetrics.panelRadius),
    ),
    child: child,
  );
}

class _Avatar extends StatelessWidget {
  final String? url;
  final double size;
  const _Avatar({required this.url, required this.size});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: url == null || url!.isEmpty
              ? ColoredBox(
                  color: t.fill,
                  child: Icon(
                    AppIcons.person,
                    size: size * FeedbackMetrics.avatarIconRatio,
                    color: t.text3,
                  ),
                )
              : NetImage(url: url!, width: size, height: size),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final PostRating rating;
  final int limit;
  final double size;
  final double overlap;
  final double border;
  final Color background;
  final bool showRemaining;
  const _AvatarStack({
    required this.rating,
    required this.limit,
    required this.size,
    required this.overlap,
    required this.border,
    required this.background,
    this.showRemaining = false,
  });
  @override
  Widget build(BuildContext context) {
    final entries = rating.entries.take(limit).toList();
    final remaining = (rating.participants ?? 0) - limit;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entries.isNotEmpty)
          SizedBox(
            width: size + (entries.length - 1) * (size - overlap),
            height: size,
            child: Stack(
              children: [
                for (var i = 0; i < entries.length; i++)
                  Positioned(
                    left: i * (size - overlap),
                    child: Container(
                      width: size,
                      height: size,
                      padding: EdgeInsets.all(border),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: background,
                      ),
                      child: _Avatar(
                        url: entries[i].avatarUrl,
                        size: size - border * 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (showRemaining && remaining > 0)
          Padding(
            padding: const EdgeInsets.only(left: FeedbackMetrics.tinyGap),
            child: Text(
              '+$remaining',
              style: TextStyle(
                fontSize: FeedbackMetrics.labelSize,
                fontWeight: FontWeight.w600,
                color: AppTokens.of(context).green,
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpandButton extends StatelessWidget {
  final bool expanded;
  final String label;
  final Color color;
  final Color ruleColor;
  final VoidCallback onTap;
  const _ExpandButton({
    required this.expanded,
    required this.label,
    required this.color,
    required this.ruleColor,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      _Rule(color: ruleColor),
      Semantics(
        expanded: expanded,
        child: PressScale(
          onTap: onTap,
          semanticLabel: expanded ? '收起' : label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: FeedbackMetrics.touchTarget,
              minWidth: FeedbackMetrics.touchTarget,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    expanded ? '收起' : label,
                    style: TextStyle(
                      fontSize: FeedbackMetrics.rowSize,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: FeedbackMetrics.tinyGap),
                _Arrow(open: expanded, color: color),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _Arrow extends StatelessWidget {
  final bool open;
  final Color color;
  const _Arrow({required this.open, required this.color});
  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      AppIcons.down,
      size: FeedbackMetrics.arrowSize,
      color: color,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return RotatedBox(
        quarterTurns: open ? FeedbackMetrics.halfTurnQuarters : 0,
        child: icon,
      );
    }
    return AnimatedRotation(
      turns: open ? FeedbackMetrics.halfTurn : 0,
      duration: AppMotion.revealDuration,
      curve: AppMotion.revealCurve,
      child: icon,
    );
  }
}

/// Collapsed rows are unmounted; every newly revealed group fades in together.
class _Reveal extends StatelessWidget {
  final bool open;
  final Widget child;
  const _Reveal({required this.open, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return open ? child : const SizedBox.shrink();
    }
    return AnimatedSize(
      duration: AppMotion.revealDuration,
      curve: AppMotion.revealCurve,
      alignment: Alignment.topCenter,
      child: open
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.revealDuration,
              curve: AppMotion.revealCurve,
              builder: (_, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: child,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _Rule extends StatelessWidget {
  final Color color;
  const _Rule({required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSpace.hairline,
    child: ColoredBox(color: color),
  );
}
