import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/rating_repository.dart';
import '../di.dart' show ratingRepo;
import '../pages/source_page_drawer.dart';
import 'package:motor/motor.dart';
import '../ui/hit_slop.dart';

import '../design/feedback.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/thread_tokens.dart';
import '../models/models.dart';
import '../ui/chat.dart' show chatTimestamp;
import '../ui/press.dart';
import 'avatar_image.dart';

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
  final RatingRepository? repository;
  const OpeningFeedback({
    super.key,
    this.rating,
    this.comments = const [],
    this.repository,
  });

  @override
  Widget build(BuildContext context) => _FeedbackCards(
    rating: rating,
    comments: comments,
    opening: true,
    repository: repository,
  );
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
  final RatingRepository? repository;
  final PostRating? rating;
  final List<PostComment> comments;
  final bool opening;
  const _FeedbackCards({
    required this.rating,
    required this.comments,
    required this.opening,
    this.repository,
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
              _RatingCard(
                key: const PageStorageKey('rating-card'),
                rating: rating!,
                opening: opening,
                repository: repository,
              ),
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
  final RatingRepository? repository;
  const _RatingCard({
    super.key,
    required this.rating,
    required this.opening,
    this.repository,
  });
  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  bool _expanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expanded =
        PageStorage.maybeOf(context)?.readState(context) as bool? ?? false;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    PageStorage.maybeOf(context)?.writeState(context, _expanded);
  }

  Widget _row(RatingEntry entry, int index) => _RatingRow(
    key: PageStorageKey((index, entry.user, entry.score, entry.reason)),
    entry: entry,
    rating: widget.rating,
    repository: widget.repository,
    opening: widget.opening,
  );

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
          opening ? t.surface : t.greenSoft,
          emphasis: opening ? t.accentFill : t.green.withValues(alpha: .10),
        ),
        borderRadius: BorderRadius.circular(
          opening ? FeedbackMetrics.cardRadius : FeedbackMetrics.floorRadius,
        ),
        boxShadow: opening ? t.shadowE1 : null,
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
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: inset,
                vertical: FeedbackMetrics.tinyGap,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < entries.length && i < fold; i++)
                    _row(entries[i], i),
                  _Reveal(
                    open: _expanded,
                    child: Column(
                      children: [
                        for (var i = fold; i < entries.length; i++)
                          _row(entries[i], i),
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
              label: opening
                  ? '其余 ${entries.length - fold} 人'
                  : '展开全部 ${entries.length} 条评分',
              color: ThreadTokens.score(t),
              onTap: _toggle,
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
                color: ThreadTokens.score(t),
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
          background: opening ? t.surface : t.greenSoft,
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
              color: label == '人评分'
                  ? ThreadTokens.participants(t)
                  : _negative(value)
                  ? t.red
                  : ThreadTokens.score(t),
              fontFeatures: FeedbackMetrics.tabular,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: TextStyle(
              fontSize: opening
                  ? FeedbackMetrics.summaryLabelSize
                  : FeedbackMetrics.floorSummaryLabelSize,
              color: label == '人评分' ? ThreadTokens.participants(t) : t.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingRow extends StatefulWidget {
  final RatingEntry entry;
  final bool opening;
  final PostRating rating;
  final RatingRepository? repository;
  const _RatingRow({
    super.key,
    required this.entry,
    required this.rating,
    this.repository,
    this.opening = false,
  });

  @override
  State<_RatingRow> createState() => _RatingRowState();
}

class _RatingRowState extends State<_RatingRow> {
  bool _expanded = false;
  Object? _measurementKey;
  bool _truncated = false;
  bool _loading = false;
  bool _failed = false;
  String? _fullReason;
  bool _fadeArrival = false;
  int _requestGeneration = 0;
  RatingRepository get _repo => widget.repository ?? ratingRepo;

  void _restoreDetails() {
    if (!isRatingReasonTruncated(widget.entry.reason)) return;
    _fullReason = _repo.cached(widget.rating)?.reasonFor(widget.entry);
    _failed =
        _repo.hasAttempted(widget.rating) &&
        !_repo.isLoading(widget.rating) &&
        _fullReason == null;
    // Reattach only to an already-started read after lazy scroll disposal.
    if (_expanded && _repo.isLoading(widget.rating) && !_loading) {
      _loadDetails();
    }
  }

  Future<void> _loadDetails() async {
    if (_loading || _fullReason != null || _failed) return;
    final cached = _repo.cached(widget.rating);
    if (cached != null ||
        (_repo.hasAttempted(widget.rating) &&
            !_repo.isLoading(widget.rating))) {
      _fullReason = cached?.reasonFor(widget.entry);
      _failed = _fullReason == null;
      return;
    }
    _loading = true;
    final generation = _requestGeneration;
    final result = await _repo.load(widget.rating);
    if (!mounted || generation != _requestGeneration) return;
    setState(() {
      _loading = false;
      _fullReason = result?.reasonFor(widget.entry);
      _failed = _fullReason == null;
      _fadeArrival = _expanded && _fullReason != null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.key is PageStorageKey) {
      _expanded =
          PageStorage.maybeOf(context)?.readState(context) as bool? ?? false;
    }
    _restoreDetails();
  }

  @override
  void didUpdateWidget(covariant _RatingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((
          oldWidget.rating.tid,
          oldWidget.rating.pid,
          oldWidget.entry.user,
          oldWidget.entry.score,
          oldWidget.entry.reason,
          oldWidget.repository,
        ) !=
        (
          widget.rating.tid,
          widget.rating.pid,
          widget.entry.user,
          widget.entry.score,
          widget.entry.reason,
          widget.repository,
        )) {
      _requestGeneration++;
      _loading = false;
      _failed = false;
      _fullReason = null;
      _fadeArrival = false;
      _restoreDetails();
    }
  }

  bool _isTruncated(String reason, TextStyle style, double width) {
    final effectiveStyle = DefaultTextStyle.of(context).style
        .merge(style)
        .merge(
          TextStyle(
            fontWeight: MediaQuery.boldTextOf(context) ? FontWeight.bold : null,
            height: MediaQuery.maybeLineHeightScaleFactorOverrideOf(context),
            letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
            wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
          ),
        );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final key = (reason, effectiveStyle, width, scaler, direction, locale);
    if (_measurementKey != key) {
      final painter = TextPainter(
        text: TextSpan(text: reason, style: effectiveStyle),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: width);
      _truncated = reason.isNotEmpty && painter.didExceedMaxLines;
      painter.dispose();
      _measurementKey = key;
    }
    return _truncated;
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _fadeArrival = false;
      if (_expanded && isRatingReasonTruncated(widget.entry.reason)) {
        _loadDetails();
      }
    });
    if (widget.key is PageStorageKey) {
      PageStorage.maybeOf(context)?.writeState(context, _expanded);
    }
  }

  Widget _reasonBody(AppTokens t, String original) {
    final serverTruncated = isRatingReasonTruncated(original);
    final uri = _repo.detailsUrl(widget.rating);
    return _RatingReasonResize(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Padding(
                // The indicator owns a fixed gutter, never another text line.
                padding: EdgeInsets.only(
                  right: serverTruncated
                      ? FeedbackMetrics.reasonLoadingGutter
                      : 0,
                ),
                child: ExcludeSemantics(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_fullReason),
                    tween: Tween(begin: _fadeArrival ? 0 : 1, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? AppMotion.reducedFade
                        : AppMotion.fade,
                    builder: (context, opacity, _) => Text(
                      _fullReason ?? original,
                      style: TextStyle(
                        fontSize: FeedbackMetrics.reasonSize,
                        height: FeedbackMetrics.reasonHeight,
                        color: t.text2.withValues(alpha: opacity),
                      ),
                    ),
                  ),
                ),
              ),
              if (_loading)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: SizedBox.square(
                    dimension: FeedbackMetrics.reasonLoadingSize,
                    child: CircularProgressIndicator(
                      strokeWidth: FeedbackMetrics.reasonLoadingStroke,
                      color: t.text3,
                      value: MediaQuery.disableAnimationsOf(context)
                          ? 0.75
                          : null,
                      semanticsLabel: '正在读取完整附言',
                    ),
                  ),
                ),
            ],
          ),
          if (_failed && uri != null)
            Align(
              alignment: Alignment.centerLeft,
              child: PressHighlight(
                onTap: () => showSourcePage(context, uri),
                color: t.pressed,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: FeedbackMetrics.touchTarget,
                  ),
                  child: Align(
                    widthFactor: 1,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '在网页中查看',
                      style: TextStyle(
                        fontSize: FeedbackMetrics.labelSize,
                        color: t.text3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final entry = widget.entry;
    final opening = widget.opening;
    final reason = entry.reason?.trim() ?? '';
    final size = opening
        ? FeedbackMetrics.rowSize
        : FeedbackMetrics.capsuleSize;
    final avatarSize = opening
        ? FeedbackMetrics.rowAvatar
        : FeedbackMetrics.smallAvatar;
    final scoreWidth = opening
        ? FeedbackMetrics.scoreWidth
        : FeedbackMetrics.compactScoreWidth;
    final reasonStyle = TextStyle(fontSize: size, color: t.text2);
    return LayoutBuilder(
      builder: (context, constraints) {
        final userWidth = (constraints.maxWidth * FeedbackMetrics.userFraction)
            .clamp(
              0.0,
              opening
                  ? FeedbackMetrics.userWidth
                  : FeedbackMetrics.compactUserWidth,
            );
        final reasonWidth =
            (constraints.maxWidth -
                    avatarSize -
                    userWidth -
                    scoreWidth -
                    FeedbackMetrics.gap * 3)
                .clamp(0.0, double.infinity);
        final truncated =
            isRatingReasonTruncated(reason) ||
            _isTruncated(reason, reasonStyle, reasonWidth);
        final open = truncated && _expanded;
        final body = Padding(
          padding: EdgeInsets.symmetric(
            vertical: opening
                ? FeedbackMetrics.rowPadding
                : FeedbackMetrics.compactRowPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                excluding: _failed,
                child: Row(
                  children: [
                    _Avatar(
                      url: entry.avatarUrl,
                      name: entry.user,
                      size: avatarSize,
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
                      width: scoreWidth,
                      child: Text(
                        entry.score,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: size,
                          fontWeight: FontWeight.w700,
                          fontFeatures: FeedbackMetrics.tabular,
                          color: _negative(entry.score)
                              ? t.red
                              : ThreadTokens.score(t),
                        ),
                      ),
                    ),
                    const SizedBox(width: FeedbackMetrics.gap),
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: open ? 0 : 1, end: open ? 0 : 1),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? AppMotion.reducedFade
                            : AppMotion.fade,
                        builder: (context, opacity, _) => Text(
                          reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: reasonStyle.copyWith(
                            color: t.text2.withValues(alpha: opacity),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _Reveal(
                open: open,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: avatarSize + FeedbackMetrics.gap,
                      top: FeedbackMetrics.reasonTop,
                    ),
                    child: _reasonBody(t, reason),
                  ),
                ),
              ),
            ],
          ),
        );
        if (!truncated) return body;
        return Semantics(
          container: true,
          button: true,
          expanded: open,
          label: '${entry.user} ${entry.score} ${_fullReason ?? reason}',
          hint: open ? '收起附言' : '展开附言',
          value: _loading ? '正在读取完整附言' : null,
          liveRegion: _loading,
          onTap: _toggle,
          explicitChildNodes: _failed,
          child: PressHighlight(
            onTap: _toggle,
            color: t.pressed,
            borderRadius: BorderRadius.circular(
              opening
                  ? FeedbackMetrics.ratingRowRadius
                  : FeedbackMetrics.compactRatingRowRadius,
            ),
            child: ExcludeSemantics(excluding: !_failed, child: body),
          ),
        );
      },
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
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _Avatar(
                    url: entry.avatarUrl,
                    name: entry.user,
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
                        color: _negative(entry.score)
                            ? t.red
                            : ThreadTokens.score(t),
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
          _Avatar(
            name: comment.author,
            url: comment.avatarUrl,
            size: FeedbackMetrics.smallAvatar,
          ),
          const SizedBox(width: FeedbackMetrics.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: FeedbackMetrics.gap,
                  runSpacing: FeedbackMetrics.tinyGap,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      comment.author,
                      style: TextStyle(
                        fontSize: FeedbackMetrics.commentSize,
                        fontWeight: FontWeight.w600,
                        color: t.text2,
                      ),
                    ),
                    if (comment.timeRaw?.isNotEmpty == true)
                      Text(
                        chatTimestamp(comment.timeRaw!),
                        style: TextStyle(
                          fontSize: FeedbackMetrics.labelSize,
                          color: t.text3,
                        ),
                      ),
                  ],
                ),
                Text(
                  comment.text,
                  style: TextStyle(
                    fontSize: FeedbackMetrics.commentSize,
                    height: FeedbackMetrics.lineHeight,
                    color: t.text,
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
        : scores.map(_summaryText).join('　');
    return '${summary.isEmpty ? '评分' : summary}${rating.participants == null ? '' : '　${rating.participants}人'}';
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
                      : ThreadTokens.score(t),
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
                                    : ThreadTokens.score(t),
                                fontFeatures: FeedbackMetrics.tabular,
                              ),
                            ),
                        ],
                      ),
                    for (final entry in rating.entries)
                      _RatingRow(entry: entry, rating: rating),
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
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: label.contains('　')
                            ? label.substring(0, label.lastIndexOf('　'))
                            : label,
                      ),
                      if (label.contains('　'))
                        TextSpan(
                          text: label.substring(label.lastIndexOf('　')),
                          style: TextStyle(
                            color: ThreadTokens.participants(
                              AppTokens.of(context),
                            ),
                          ),
                        ),
                    ],
                  ),
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
  final String name;
  final double size;
  const _Avatar({required this.url, required this.name, required this.size});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AvatarImage(name: name, url: url, size: size),
  );
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
                        name: entries[i].user,
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
  final VoidCallback onTap;
  const _ExpandButton({
    required this.expanded,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
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
      return RotatedBox(quarterTurns: open ? 2 : 0, child: icon);
    }
    return SingleMotionBuilder(
      motion: AppMotion.select,
      value: open ? FeedbackMetrics.halfTurn : 0.0,
      builder: (context, value, child) =>
          Transform.rotate(angle: value * 6.283185307179586, child: child),
      child: icon,
    );
  }
}

/// Lay out only the added panel once; the spring changes its visible height.
class _Reveal extends StatefulWidget {
  final bool open;
  final Widget child;
  const _Reveal({required this.open, required this.child});
  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: widget.open ? 1 : 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.open ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant _Reveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      AppMotion.settle(
        _controller,
        target: widget.open ? 1 : 0,
        motion: AppMotion.reveal,
        reduced: MediaQuery.disableAnimationsOf(context),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) => _controller.value == 0 && !widget.open
        ? const SizedBox.shrink()
        : ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _controller.value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
  );
}

/// Only this reason changes height when its full text arrives. The paragraph
/// keeps unconstrained height, so spring ticks reuse its completed layout.
class _RatingReasonResize extends StatefulWidget {
  final Widget child;
  const _RatingReasonResize({required this.child});
  @override
  State<_RatingReasonResize> createState() => _RatingReasonResizeState();
}

class _RatingReasonResizeState extends State<_RatingReasonResize>
    with SingleTickerProviderStateMixin {
  late final _height = AnimationController.unbounded(vsync: this);
  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ReasonSizeBox(
    height: _height,
    reduced: MediaQuery.disableAnimationsOf(context),
    child: RepaintBoundary(child: widget.child),
  );
}

class _ReasonSizeBox extends SingleChildRenderObjectWidget {
  final AnimationController height;
  final bool reduced;
  const _ReasonSizeBox({
    required this.height,
    required this.reduced,
    required super.child,
  });
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReasonSize(height, reduced);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReasonSize renderObject,
  ) {
    renderObject.reduced = reduced;
    renderObject.markNeedsLayout();
  }
}

class _RenderReasonSize extends RenderProxyBox {
  final AnimationController height;
  bool reduced;
  double? _target;
  double? _width;
  bool _layingOut = false;
  void _tick() {
    if (!_layingOut) markNeedsLayout();
  }

  _RenderReasonSize(this.height, this.reduced);
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    height.addListener(_tick);
  }

  @override
  void detach() {
    height.removeListener(_tick);
    super.detach();
  }

  @override
  void performLayout() {
    _layingOut = true;
    child!.layout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    final target = child!.size.height;
    if (_target == null || _width != constraints.maxWidth || reduced) {
      if (height.value != target || height.isAnimating) height.value = target;
    } else if (_target != target) {
      AppMotion.settle(height, target: target, motion: AppMotion.reveal);
    }
    _target = target;
    _width = constraints.maxWidth;
    size = constraints.constrain(
      Size(child!.size.width, height.value.clamp(0, double.infinity)),
    );
    _layingOut = false;
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => Offset.zero & size;
  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => super.paint(context, offset),
      clipBehavior: Clip.hardEdge,
    );
  }
}
