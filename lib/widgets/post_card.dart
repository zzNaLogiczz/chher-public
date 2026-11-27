/// 楼层卡片:楼主楼与回复楼分级
///
/// 晒单与评测帖本质是「一篇文章 + 评论」,所以楼主楼正文与原比例图片连续排版，
/// 回复楼通过作者、时间和轻量引用建立层级。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../parser/post_note_parser.dart';
import '../design/content_element_tokens.dart';
import '../design/feedback.dart';
import '../design/icons.dart';
import '../design/quote_tokens.dart';
import '../design/avatar_tokens.dart';
import 'site_link_card.dart';
import 'level_badge.dart';
import '../design/level_tokens.dart';

import '../design/tokens.dart';
import '../design/reading.dart';
import '../design/thread_tokens.dart';
import '../design/thread_interaction_tokens.dart';
import '../core/display_time.dart';
import 'comment_row_interaction.dart';
import '../ui/press.dart';
import '../ui/hit_slop.dart';
import '../ui/quote.dart';
import '../design/typography.dart';
import 'expressive_controls.dart';
import '../models/models.dart';
import '../models/quote_presentation.dart';
import '../models/image_stack_group.dart';
import 'image_stack_gallery.dart';
import '../pages/user_drawer.dart';
import 'image_grid.dart';
import 'avatar_image.dart';
import 'rich_content_text.dart';
import 'content_link_block.dart';
import 'post_feedback.dart';

enum _PostPart { whole, header, block, footer }

class PostCard extends StatelessWidget {
  final Post post;

  /// 第一楼按文章排版,其余按回复排版
  final bool isOpening;
  final bool isAuthor;

  /// Comment mode displays the author’s own content without historical quotes.
  final bool commentStyle;
  final bool nested;

  /// Only a nested reply's direct, loaded recipient; root replies omit this.
  final String? replyToAuthor;

  /// 回复这一楼。给每层一个明确入口,长按引用不够显眼。
  final VoidCallback? onReply;
  final VoidCallback? onMore;
  final VoidCallback? onUnlock;
  final VoidCallback? onOpenProfile;
  final Widget? replyContext;
  final Widget? discussionAction;
  final Widget? pollCard;
  final Key? feedbackKey;
  final _PostPart _part;
  final ContentBlock? contentBlock;
  final int? contentIndex;
  final List<String> gallery;
  final int galleryIndex;
  final bool paragraphGapBefore;
  final ImageStackGroup? imageStack;
  final List<SiteLinkBlock>? siteLinks;
  final bool linksGrouped;
  final bool linkGroupStart;
  final bool linkGroupEnd;
  final ValueChanged<PostReference>? onOpenReference;

  const PostCard({
    super.key,
    this.feedbackKey,
    this.imageStack,
    this.siteLinks,
    this.linksGrouped = false,
    this.linkGroupStart = true,
    this.linkGroupEnd = true,
    this.onOpenReference,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.nested = false,
    this.replyToAuthor,
    this.onReply,
    this.onMore,
    this.onUnlock,
    this.onOpenProfile,
    this.replyContext,
    this.discussionAction,
    this.pollCard,
  }) : _part = _PostPart.whole,
       contentBlock = null,
       contentIndex = null,
       gallery = const [],
       galleryIndex = 0,
       paragraphGapBefore = false;

  /// Long opening posts are separate lazy list entries, not one huge Column.
  const PostCard.header({
    super.key,
    this.feedbackKey,
    this.imageStack,
    this.siteLinks,
    this.linksGrouped = false,
    this.linkGroupStart = true,
    this.linkGroupEnd = true,
    this.onOpenReference,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.nested = false,
    this.replyToAuthor,
    this.onReply,
    this.onMore,
    this.onUnlock,
    this.onOpenProfile,
    this.replyContext,
    this.discussionAction,
    this.pollCard,
  }) : _part = _PostPart.header,
       contentBlock = null,
       contentIndex = null,
       gallery = const [],
       galleryIndex = 0,
       paragraphGapBefore = false;

  const PostCard.block({
    super.key,
    this.feedbackKey,
    this.imageStack,
    this.siteLinks,
    this.linksGrouped = false,
    this.linkGroupStart = true,
    this.linkGroupEnd = true,
    this.onOpenReference,
    required this.post,
    required this.isOpening,
    required this.contentBlock,
    this.contentIndex,
    this.gallery = const [],
    this.galleryIndex = 0,
    this.paragraphGapBefore = false,
    this.isAuthor = false,
    this.commentStyle = false,
    this.nested = false,
    this.replyToAuthor,
    this.onUnlock,
  }) : _part = _PostPart.block,
       onReply = null,
       onMore = null,
       onOpenProfile = null,
       replyContext = null,
       discussionAction = null,
       pollCard = null;

  const PostCard.footer({
    super.key,
    this.feedbackKey,
    this.imageStack,
    this.siteLinks,
    this.linksGrouped = false,
    this.linkGroupStart = true,
    this.linkGroupEnd = true,
    this.onOpenReference,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.nested = false,
    this.replyToAuthor,
    this.onReply,
    this.onMore,
    this.onUnlock,
    this.replyContext,
    this.discussionAction,
    this.pollCard,
  }) : _part = _PostPart.footer,
       onOpenProfile = null,
       contentBlock = null,
       contentIndex = null,
       gallery = const [],
       galleryIndex = 0,
       paragraphGapBefore = false;

  @override
  Widget build(BuildContext context) => HitSlopRegion(child: _build(context));

  Widget _build(BuildContext context) {
    final t = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    if (_part != _PostPart.whole) return _buildPart(context, t);
    if (!isOpening) return _comment(context, t);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.gutter - ThreadTokens.imageBleed,
        metrics.postVPad,
        metrics.gutter - ThreadTokens.imageBleed,
        metrics.postVPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _authorRow(context, t),
          ?replyContext,
          Padding(
            padding: const EdgeInsets.only(top: ThreadTokens.bodyTop),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._blocks(context, t),
                ..._notes(context, t, PostNoteKind.supplement),
                ..._notes(context, t, PostNoteKind.edited),
                ?pollCard,
                _feedback(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comment(BuildContext context, AppTokens t) {
    final metrics = ReadingMetrics.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: nested ? 0 : metrics.commentGutter,
        vertical: metrics.commentVPad,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _commentAvatar(context, t),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _commentMetadata(context, t),
                ?replyContext,
                const SizedBox(height: 2),
                ..._blocks(context, t),
                ..._notes(context, t, PostNoteKind.supplement),
                ..._notes(context, t, PostNoteKind.edited),
                ..._commentFeedback(),
                _commentMetaRow(context, t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentMetadata(BuildContext context, AppTokens t) => _identityLine(
    context,
    t,
    owner: isAuthor,
    name: _profileLink(
      context,
      key: ValueKey('post-author-${post.pid}'),
      child: Text(
        post.author,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.footnote.copyWith(
          fontWeight: FontWeight.w600,
          color: isSuppressedPost(post) ? t.text3 : t.text2,
        ),
      ),
    ),
  );

  Widget _identityLine(
    BuildContext context,
    AppTokens t, {
    required Widget name,
    required bool owner,
  }) {
    final level = isSuppressedPost(post)
        ? null
        : LevelDefinition.lookup(post.authorGroupId);
    if (level == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: name),
          if (owner) _ownerBadge(t),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        double textWidth(String text, TextStyle style, TextScaler scale) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            textDirection: TextDirection.ltr,
            textScaler: scale,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final scale = scaler.scale(LevelTokens.fontSize) / LevelTokens.fontSize;
        final badgeWidth =
            (LevelTokens.inset +
                    LevelTokens.tileSize +
                    LevelTokens.gap +
                    LevelTokens.rightInset) *
                scale +
            textWidth(
              level.displayName,
              TextStyle(
                fontSize: LevelTokens.fontSize * scale,
                fontWeight: LevelTokens.fontWeight,
                letterSpacing: (level.tier == 'gold' || level.tier == 'champ')
                    ? LevelTokens.letterSpacing * scale
                    : 0,
              ),
              TextScaler.noScaling,
            );
        final badge = _levelBadge(context);
        final ownerWidth = owner
            ? textWidth(LevelTokens.ownerText, LevelTokens.ownerStyle, scaler) +
                  LevelTokens.ownerInset * 2 +
                  LevelTokens.authorGap
            : 0.0;
        if (badgeWidth +
                LevelTokens.authorGap +
                ownerWidth +
                LevelTokens.authorNameMinWidth >
            constraints.maxWidth) {
          // At large system type, keep both labels whole on subsequent lines.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: constraints.maxWidth, child: name),
              const SizedBox(height: LevelTokens.authorGap),
              Wrap(
                runSpacing: LevelTokens.authorGap,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (badgeWidth > constraints.maxWidth)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: badge,
                    )
                  else
                    badge,
                  if (owner) _ownerBadge(t),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(child: name),
            const SizedBox(width: LevelTokens.authorGap),
            badge,
            if (owner) _ownerBadge(t),
          ],
        );
      },
    );
  }

  Widget _commentMetaRow(BuildContext context, AppTokens t) => CommentMetaRow(
    timeLabel: _commentTime,
    topGap: _hasRating
        ? FeedbackMetrics.ratingBottom
        : ReadingMetrics.commentMetaGap,
    floor: !commentStyle && post.floorIsKnown ? post.floor : null,
    timeSemanticsLabel: post.timeRaw,
    replyKey: ValueKey('comment-reply-${post.pid}'),
    onReply: onReply,
    onMore: onMore,
    moreKey: ValueKey('post-more-${post.pid}'),
  );

  String get _commentTime =>
      formatDisplayTime(raw: post.timeRaw, at: post.time);

  Widget _commentAvatar(BuildContext context, AppTokens t) {
    final metrics = ReadingMetrics.of(context);
    return _profileLink(
      context,
      key: ValueKey('post-avatar-${post.pid}'),
      child: _avatar(t, nested ? metrics.threadAvatarNested : metrics.avatar),
    );
  }

  Widget _levelBadge(BuildContext context) => LevelBadge(
    key: ValueKey('post-level-${post.pid}'),
    gid: post.authorGroupId,
    onTap: post.authorUid == null
        ? null
        : onOpenProfile ?? () => showUserDrawer(context, post.authorUid!),
  );

  Widget _ownerBadge(AppTokens t) => Padding(
    padding: const EdgeInsets.only(left: LevelTokens.authorGap),
    child: Builder(
      builder: (context) {
        final scale =
            MediaQuery.textScalerOf(context).scale(LevelTokens.ownerFontSize) /
            LevelTokens.ownerFontSize;
        return SizedBox(
          key: ValueKey('post-owner-${post.pid}'),
          height: LevelTokens.ownerHeight * scale,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                color: t.accent.withValues(alpha: LevelTokens.ownerBorderAlpha),
                width: LevelTokens.ownerBorder,
              ),
              borderRadius: BorderRadius.circular(LevelTokens.ownerRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LevelTokens.ownerInset,
              ),
              child: Align(
                alignment: Alignment.center,
                widthFactor: 1,
                child: Text(
                  LevelTokens.ownerText,
                  maxLines: 1,
                  style: LevelTokens.ownerStyle.copyWith(color: t.accent),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _avatar(AppTokens t, double size) {
    if (!isSuppressedPost(post)) {
      return AvatarImage(name: post.author, url: post.avatarUrl, size: size);
    }
    return AvatarFrame(
      key: ValueKey('suppressed-avatar-${post.pid}'),
      size: size,
      child: Center(
        child: Text(
          AvatarTokens.initial(post.author),
          textScaler: TextScaler.noScaling,
          style: AvatarTokens.text(size).copyWith(
            color: t.text3.withValues(
              alpha: ContentElementTokens.suppressedAvatarAlpha,
            ),
          ),
        ),
      ),
    );
  }

  Widget _suppressed(AppTokens t) => Row(
    key: ValueKey('suppressed-content-${post.pid}'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        AppIcons.forbidden,
        size: ContentElementTokens.bodySize,
        color: t.text3,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          '作者被禁止或删除，内容已自动屏蔽',
          style: TextStyle(
            fontSize: ContentElementTokens.headingSize,
            color: t.text3,
          ),
        ),
      ),
    ],
  );

  Widget _profileLink(
    BuildContext context, {
    required Widget child,
    Key? key,
  }) => PressScale(
    key: key,
    semanticLabel: '查看${post.author}的主页',
    onTap: post.authorUid == null
        ? null
        : onOpenProfile ?? () => showUserDrawer(context, post.authorUid!),
    child: child,
  );

  Widget _lockBlock(AppTokens t) {
    final lock = post.lock!;
    if (isSuppressedPost(post)) return _suppressed(t);
    return Container(
      key: ValueKey('post-lock-${post.pid}'),
      width: double.infinity,
      padding: ContentElementTokens.lockInset,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: ContentElementTokens.panel(t),
        borderRadius: BorderRadius.circular(ContentElementTokens.panelRadius),
      ),
      child: Column(
        children: [
          Container(
            width: ContentElementTokens.lockSize,
            height: ContentElementTokens.lockSize,
            decoration: BoxDecoration(color: t.surface, shape: BoxShape.circle),
            child: Icon(AppIcons.lock, color: t.text2, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            lock.needsPassword ? '这段内容需要密码' : lock.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ContentElementTokens.lockTitleSize,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          if (lock.needsPassword) ...[
            const SizedBox(height: 12),
            PressScale(
              onTap: onUnlock,
              semanticLabel: '输入密码',
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: ContentElementTokens.buttonHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(
                    ContentElementTokens.buttonRadius,
                  ),
                ),
                child: Text(
                  '输入密码',
                  style: TextStyle(
                    fontSize: ContentElementTokens.buttonSize,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _wideImageRow =>
      _part == _PostPart.block &&
      (imageStack != null || contentBlock is ImageBlock);

  Widget _buildPart(BuildContext context, AppTokens t) {
    final metrics = ReadingMetrics.of(context);
    if (!isOpening) return _commentPart(context, t, metrics);
    final content = switch (_part) {
      _PostPart.header => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _authorRow(context, t),
          ?replyContext,
          SizedBox(height: isOpening ? ThreadTokens.bodyTop : metrics.postVPad),
          if (post.lock != null) _lockBlock(t),
        ],
      ),
      _PostPart.footer => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._notes(context, t, PostNoteKind.supplement),
          ..._notes(context, t, PostNoteKind.edited),
          ?pollCard,
          _feedback(),
        ],
      ),
      _PostPart.block => _contentBlock(context, t, metrics),
      _PostPart.whole => const SizedBox.shrink(),
    };
    final horizontal =
        _wideImageRow ||
            (isOpening &&
                (_part == _PostPart.header || _part == _PostPart.footer))
        ? (metrics.gutter - ThreadTokens.imageBleed)
        : nested
        ? 0.0
        : metrics.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        _part == _PostPart.header
            ? metrics.postVPad
            : (!isOpening && paragraphGapBefore
                  ? ReadingMetrics.paragraphGap
                  : 0),
        horizontal,
        _part == _PostPart.footer ? metrics.postVPad : 0,
      ),
      child: content,
    );
  }

  Widget _contentBlock(
    BuildContext context,
    AppTokens t,
    ReadingMetrics metrics,
  ) {
    if (siteLinks case final links?) {
      return _prefixNonText(
        context,
        _linkGroup(
          links,
          grouped: linksGrouped,
          first: linkGroupStart,
          last: linkGroupEnd,
        ),
      );
    }
    if (imageStack case final group?) {
      return _prefixNonText(
        context,
        ImageStackGallery(
          key: PageStorageKey(
            'post-${post.pid}-image-stack-${group.blockIndex}',
          ),
          urls: group.urls,
          aspectRatios: group.aspectRatios,
          gallery: gallery,
          galleryStartIndex: group.galleryStartIndex,
          compact: !isOpening,
        ),
      );
    }
    final content = switch (contentBlock!) {
      final TextBlock textBlock => _text(
        context,
        textBlock,
        prefix: _replyPrefix,
        last: contentIndex == post.content.length - 1,
      ),
      final QuoteBlock quote => _quote(context, t, quote),
      SiteLinkBlock() || BilibiliBlock() => _linkBlock(contentBlock!),
      ImageBlock(:final url) => Padding(
        padding: EdgeInsets.symmetric(vertical: metrics.imageGap),
        child: InlineImageViewer(
          url: url,
          gallery: gallery.isEmpty ? [url] : gallery,
          initialIndex: galleryIndex,
        ),
      ),
    };
    return contentBlock is! TextBlock && _replyPrefix != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _text(context, const TextBlock(''), prefix: _replyPrefix),
              content,
            ],
          )
        : content;
  }

  Widget _prefixNonText(BuildContext context, Widget child) =>
      _replyPrefix == null
      ? child
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(context, const TextBlock(''), prefix: _replyPrefix),
            child,
          ],
        );

  /// Lazy comments keep the same metadata and indentation as whole comments.
  Widget _commentPart(
    BuildContext context,
    AppTokens t,
    ReadingMetrics metrics,
  ) {
    final avatar = nested ? metrics.threadAvatarNested : metrics.avatar;
    if (_part == _PostPart.header) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          nested ? 0 : metrics.commentGutter,
          metrics.commentVPad,
          nested ? 0 : metrics.commentGutter,
          2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeyedSubtree(
                  key: ValueKey('post-profile-${post.pid}'),
                  child: _commentAvatar(context, t),
                ),
                const SizedBox(width: 10),
                Expanded(child: _commentMetadata(context, t)),
              ],
            ),
            ?replyContext,
            if (post.lock != null) _lockBlock(t),
          ],
        ),
      );
    }
    final child = _part == _PostPart.footer
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._notes(context, t, PostNoteKind.supplement),
              ..._notes(context, t, PostNoteKind.edited),
              ..._commentFeedback(),
              _commentMetaRow(context, t),
            ],
          )
        : _contentBlock(context, t, metrics);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _wideImageRow
            ? (metrics.gutter - ThreadTokens.imageBleed)
            : (nested ? 0 : metrics.commentGutter) + avatar + 10,
        paragraphGapBefore ? ReadingMetrics.paragraphGap : 0,
        _wideImageRow
            ? (metrics.gutter - ThreadTokens.imageBleed)
            : nested
            ? 0
            : metrics.commentGutter,
        _part == _PostPart.footer ? metrics.commentVPad : 0,
      ),
      child: child,
    );
  }

  Widget _authorRow(BuildContext context, AppTokens t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ThreadTokens.imageBleed),
    child: Row(
      children: [
        Expanded(
          child: _profileLink(
            context,
            key: ValueKey('post-profile-${post.pid}'),
            child: Row(
              children: [
                _avatar(t, ReadingMetrics.of(context).openingAvatar),
                const SizedBox(width: ThreadTokens.authorAvatarGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _identityLine(
                        context,
                        t,
                        owner: true,
                        name: Text(
                          post.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.subhead.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSuppressedPost(post) ? t.text3 : t.text,
                          ),
                        ),
                      ),
                      if (post.timeRaw.isNotEmpty || post.time != null) ...[
                        const SizedBox(height: ThreadTokens.authorTimeGap),
                        Text(
                          _commentTime,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          strutStyle: StrutStyle.fromTextStyle(
                            DefaultTextStyle.of(
                              context,
                            ).style.merge(AppType.footnote),
                            forceStrutHeight: true,
                          ),
                          style: AppType.footnote.copyWith(color: t.text3),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onMore != null) _moreControl(),
      ],
    ),
  );

  /// 把内容块渲染成组件,并把相邻图片合并成一个宫格
  List<Widget> _blocks(BuildContext context, AppTokens t) {
    if (post.lock != null) return [_lockBlock(t)];
    final metrics = ReadingMetrics.of(context);
    final out = <Widget>[];
    final gallery = post.content
        .whereType<ImageBlock>()
        .map((b) => b.url)
        .toList(growable: false);
    var prefix = _replyPrefix;
    for (final segment in groupPostImages(post.content)) {
      final block = segment.block;
      if (block is QuoteBlock &&
          !block.isNotice &&
          (commentStyle || (!isOpening && replyContext != null))) {
        continue;
      }
      if (prefix != null && block is! TextBlock) {
        out.add(_text(context, const TextBlock(''), prefix: prefix));
      }
      if (segment.siteLinks case final links?) {
        out.add(
          _linkGroup(
            links,
            grouped: segment.linksGrouped,
            first: segment.linkGroupStart,
            last: segment.linkGroupEnd,
          ),
        );
      } else if (segment.imageStack case final group?) {
        out.add(
          ImageStackGallery(
            key: PageStorageKey(
              'post-${post.pid}-image-stack-${group.blockIndex}',
            ),
            urls: group.urls,
            aspectRatios: group.aspectRatios,
            gallery: gallery,
            galleryStartIndex: group.galleryStartIndex,
            compact: !isOpening,
          ),
        );
      } else {
        switch (block!) {
          case ImageBlock(:final url):
            out.add(
              Padding(
                padding: EdgeInsets.symmetric(vertical: metrics.imageGap),
                child: ImageGrid(
                  [url],
                  preserveAspectRatio: isOpening,
                  gallery: gallery,
                  galleryStartIndex: segment.galleryIndex,
                ),
              ),
            );
          case final TextBlock textBlock:
            if (out.isNotEmpty && !isOpening) {
              out.add(SizedBox(height: ReadingMetrics.paragraphGap));
            }
            out.add(
              _text(
                context,
                textBlock,
                prefix: prefix,
                last: segment.blockIndex == post.content.length - 1,
              ),
            );
          case final QuoteBlock quote:
            out.add(_quote(context, t, quote));
          case SiteLinkBlock() || BilibiliBlock():
            out.add(_linkBlock(block));
        }
      }
      prefix = null;
    }
    if (prefix != null) {
      out.add(_text(context, const TextBlock(''), prefix: prefix));
    }
    if (!isOpening) return out;
    return [
      for (final child in out)
        if (child is ImageStackGallery ||
            (child is Padding && child.child is ImageGrid))
          child
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ThreadTokens.imageBleed,
            ),
            child: child,
          ),
    ];
  }

  /// 站内卡片与视频:和正文同宽,上下留出与段落相近的间距
  Widget _linkBlock(ContentBlock block) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: ContentLinkBlockView(block: block, compact: !isOpening),
  );

  Widget _linkGroup(
    List<SiteLinkBlock> links, {
    bool grouped = false,
    bool first = true,
    bool last = true,
  }) => Padding(
    padding: EdgeInsets.only(top: first ? 4 : 0, bottom: last ? 12 : 0),
    child: SiteLinkGroupCard(
      blocks: links,
      compact: !isOpening,
      grouped: grouped,
      first: first,
      last: last,
    ),
  );

  List<Widget> _notes(BuildContext context, AppTokens t, PostNoteKind kind) {
    final notes = post.notes.where((n) => n.kind == kind).toList();
    final bodyStyle = isOpening
        ? ContentElementTokens.supplementBody
        : ContentElementTokens.replySupplementBody;
    return [
      for (final (index, note) in notes.indexed) ...[
        if (kind == PostNoteKind.edited) ...[
          if (showPostEdit(note, post))
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                postEditedLabel(note.text)!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ContentElementTokens.metadataSize,
                  color: t.text3,
                ),
              ),
            ),
        ] else if (parseSupplement(note.text) case final supplement?)
          Padding(
            key: ValueKey('supplement-${post.pid}-$index'),
            padding: EdgeInsets.only(
              top: index == 0
                  ? ContentElementTokens.supplementTop -
                        (isOpening && post.content.lastOrNull is TextBlock
                            ? ReadingMetrics.paragraphGap
                            : 0)
                  : ContentElementTokens.supplementGap,
              left: isOpening ? ThreadTokens.imageBleed : 0,
              right: isOpening ? ThreadTokens.imageBleed : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.compose,
                          size: ContentElementTokens.supplementIconSize,
                          color: t.accent,
                        ),
                        const SizedBox(
                          width: ContentElementTokens.supplementHeadingGap,
                        ),
                        Text(
                          isOpening ? '楼主补充' : '补充',
                          style: ContentElementTokens.supplementHeading
                              .copyWith(color: t.accent),
                        ),
                      ],
                    ),
                    const SizedBox(
                      width: ContentElementTokens.supplementDateGap,
                    ),
                    Flexible(
                      child: Text(
                        formatDisplayTime(raw: supplement.timeRaw),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ContentElementTokens.supplementDate.copyWith(
                          color: t.text3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: ContentElementTokens.supplementHeadingGap,
                ),
                for (final (paragraphIndex, paragraph)
                    in supplement.text.split('\n\n').indexed) ...[
                  if (paragraphIndex > 0)
                    const SizedBox(height: ReadingMetrics.paragraphGap),
                  SelectableText(
                    paragraph,
                    style: bodyStyle.copyWith(color: t.text2),
                  ),
                ],
              ],
            ),
          )
        else
          SelectableText(note.text, style: TextStyle(color: t.text)),
      ],
    ];
  }

  bool get _hasRating => post.rating?.isEmpty == false;

  List<Widget> _commentFeedback() => [
    if (_hasRating || post.comments.isNotEmpty) ...[
      SizedBox(
        height: _hasRating
            ? FeedbackMetrics.ratingTop
            : FeedbackMetrics.smallGap,
      ),
      CommentFeedback(
        key: PageStorageKey('comment-feedback-${post.pid}'),
        rating: post.rating,
        comments: post.comments,
      ),
    ],
  ];

  Widget _feedback() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ThreadTokens.imageBleed),
    child: KeyedSubtree(
      key: PageStorageKey('opening-feedback-${post.pid}'),
      child: OpeningFeedback(
        key: feedbackKey,
        rating: post.rating,
        comments: post.comments,
      ),
    ),
  );

  Widget _moreControl() => _PostMoreButton(
    key: ValueKey('post-more-${post.pid}'),
    label: isOpening ? '主帖更多操作' : '第 ${post.floor} 楼更多操作',
    onTap: onMore,
    compact: !isOpening,
  );

  String? get _replyPrefix =>
      commentStyle && replyToAuthor != null ? '回复 $replyToAuthor：' : null;

  Widget _text(
    BuildContext context,
    TextBlock block, {
    String? prefix,
    bool last = false,
  }) {
    final metrics = ReadingMetrics.of(context);
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: isOpening ? metrics.bodySize : metrics.commentSize,
      height: isOpening ? metrics.threadBodyHeight : metrics.commentHeight,
    );
    final followedByRating =
        last && _hasRating && post.notes.isEmpty && pollCard == null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: isOpening && !followedByRating
            ? ReadingMetrics.paragraphGap
            : 0,
      ),
      child: RichContentText(
        block: block,
        prefix: prefix,
        prefixStyle: TextStyle(color: AppTokens.of(context).text3),
        style: style,
      ),
    );
  }

  /// 引用块只保留署名与纯文本,嵌套引用不再展开第二层
  Widget _quote(BuildContext context, AppTokens t, QuoteBlock quote) {
    if (quote.isNotice && isSuppressedPost(post)) return _suppressed(t);
    final display = quoteForDisplay(quote);
    final text = display.children
        .whereType<TextBlock>()
        .map((b) => b.text)
        .join(' ')
        .trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: QuoteView(
        author: display.source ?? '',
        bodyStyle: QuoteTokens.body.copyWith(
          fontSize: ReadingMetrics.of(context).bodySize - 2,
        ),
        text: text,
        collapsedLines: 4,
        onOpenReference: quote.reference != null && onOpenReference != null
            ? () => onOpenReference!(quote.reference!)
            : null,
      ),
    );
  }
}

/// 文章与帖子评论共用时间、回复字形度量和透明触区；外层提供 HitSlopRegion。
class CommentMetaRow extends StatelessWidget {
  static final _numericCommentTime = RegExp(r'^[0-9\s:./-]+$');

  static StrutStyle _strut(BuildContext context) => StrutStyle.fromTextStyle(
    DefaultTextStyle.of(context).style.merge(AppType.footnote),
    forceStrutHeight: true,
  );

  /// The metadata and reply label share the bottom of the centered inner row.
  static double textBottomInsetOf(BuildContext context) {
    final painter = TextPainter(
      text: const TextSpan(text: '回复', style: AppType.footnote),
      strutStyle: _strut(context),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final contentHeight = math.max(
      ReadingMetrics.commentActionHeight,
      painter.height,
    );
    painter.dispose();
    return math.max(0, (ReadingMetrics.commentMetaHeight - contentHeight) / 2);
  }

  final String timeLabel;
  final double topGap;
  final int? floor;
  final String? timeSemanticsLabel;
  final Key? replyKey;
  final VoidCallback? onReply;
  final VoidCallback? onMore;
  final Key? moreKey;

  const CommentMetaRow({
    super.key,
    required this.timeLabel,
    this.topGap = ReadingMetrics.commentMetaGap,
    this.floor,
    this.timeSemanticsLabel,
    this.replyKey,
    this.onReply,
    this.onMore,
    this.moreKey,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (timeLabel.isEmpty &&
        floor == null &&
        onReply == null &&
        onMore == null) {
      return const SizedBox.shrink();
    }
    // 数字与中文 fallback 的 ascent/descent 不同，行框齐底不等于基线一致。
    // 两段文字共用继承字体的行度量，字号缩放交给 Text；不做设备像素补偿。
    final strut = _strut(context);
    final opticalLift =
        Theme.of(context).platform == TargetPlatform.android &&
            _numericCommentTime.hasMatch(timeLabel)
        ? MediaQuery.textScalerOf(context).scale(AppType.sizeFootnote) *
              ReadingMetrics.commentReplyOpticalLiftEm
        : 0.0;
    final timeStyle = AppType.footnote.copyWith(color: t.text3);
    final replyStyle = AppType.footnote.copyWith(
      color: t.text2,
      fontWeight: FontWeight.w600,
    );
    final hasTime = timeLabel.isNotEmpty || floor != null;
    final time = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (floor != null) Text('#$floor', strutStyle: strut, style: timeStyle),
        if (floor != null && timeLabel.isNotEmpty)
          const SizedBox(width: ThreadInteractionTokens.metaSpacing),
        if (timeLabel.isNotEmpty)
          Flexible(
            child: Text(
              timeLabel,
              semanticsLabel: timeSemanticsLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: strut,
              style: timeStyle,
            ),
          ),
      ],
    );
    final reply = onReply == null
        ? null
        : _replyControl(
            key: replyKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ReadingMetrics.commentActionHeight,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: EdgeInsets.only(bottom: opticalLift),
                  child: ExcludeSemantics(
                    child: Text('回复', strutStyle: strut, style: replyStyle),
                  ),
                ),
              ),
            ),
          );
    final more = onMore == null
        ? null
        : SizedBox(
            width:
                ThreadInteractionTokens.moreWidth -
                ThreadInteractionTokens.moreOverhang,
            height: ThreadInteractionTokens.moreHeight,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: ThreadInteractionTokens.moreWidth,
              maxWidth: ThreadInteractionTokens.moreWidth,
              child: HitSlopTarget(
                enabled: true,
                slop: const EdgeInsets.symmetric(
                  horizontal:
                      (AppSizes.singleLineHeight -
                          ThreadInteractionTokens.moreWidth) /
                      2,
                  vertical:
                      (AppSizes.singleLineHeight -
                          ThreadInteractionTokens.moreHeight) /
                      2,
                ),
                child: CommentMoreButton(key: moreKey, onPressed: onMore!),
              ),
            ),
          );
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: ReadingMetrics.commentMetaHeight,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasTime) Flexible(child: time),
                  if (hasTime && reply != null)
                    const SizedBox(width: ThreadInteractionTokens.metaSpacing),
                  ?reply,
                ],
              ),
            ),
            if (more != null && reply != null)
              const SizedBox(width: ThreadInteractionTokens.metaSpacing),
            ?more,
          ],
        ),
      ),
    );
  }

  Widget _replyControl({Key? key, required Widget child}) => HitSlopTarget(
    enabled: onReply != null,
    slop: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    child: PressScale(
      key: key,
      onTap: onReply,
      semanticLabel: '回复',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 28),
        child: child,
      ),
    ),
  );
}

/// A compact visual mark with a transparent 44dp touch target.
class _PostMoreButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool compact;
  const _PostMoreButton({
    super.key,
    required this.label,
    this.onTap,
    this.compact = true,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final glyph = SolidMoreIcon(opening: !compact, color: t.text2);
    final height =
        MediaQuery.textScalerOf(context).scale(AppType.sizeFootnote) *
        AppType.footnote.height!;
    final compactHeight = height.clamp(20.0, double.infinity);
    final verticalSlop = ((44 - compactHeight) / 2).clamp(0.0, 12.0);
    return Tooltip(
      message: '更多操作',
      child: HitSlopTarget(
        enabled: onTap != null,
        slop: compact
            ? EdgeInsets.symmetric(vertical: verticalSlop)
            : EdgeInsets.zero,
        child: PressScale(
          semanticLabel: label,
          pressedOpacity: .6,
          onTap: onTap,
          child: compact
              ? SizedBox(
                  width: 44,
                  height: compactHeight,
                  child: Center(child: glyph),
                )
              : SizedBox.square(
                  dimension: ThreadTokens.authorMoreTarget,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.surface2,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(
                        dimension: ThreadTokens.authorMoreSize,
                        child: Center(child: glyph),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Solid circles match the approved vector, independently of font metrics.
class SolidMoreIcon extends StatelessWidget {
  final bool opening;
  final Color color;
  const SolidMoreIcon({super.key, this.opening = false, required this.color});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(opening ? ThreadTokens.authorMoreIconSize : 16),
      painter: _SolidMorePainter(opening, color),
    ),
  );
}

class _SolidMorePainter extends CustomPainter {
  final bool opening;
  final Color color;
  const _SolidMorePainter(this.opening, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final x in opening ? [3.5, 9.0, 14.5] : [3.0, 8.0, 13.0]) {
      canvas.drawCircle(
        Offset(x, size.height / 2),
        opening ? 1.75 : 1.6,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SolidMorePainter oldDelegate) =>
      opening != oldDelegate.opening || color != oldDelegate.color;
}
