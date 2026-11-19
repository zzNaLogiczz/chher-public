/// Discussion-specific surfaces: local motion only, no scroll-driven effects.
library;

import '../core/display_time.dart';
import '../design/typography.dart';
import 'package:flutter/material.dart';
import '../design/reading.dart';

import '../design/tokens.dart';
import '../ui/quote.dart';
import '../ui/hit_slop.dart';
import '../ui/press.dart';
import '../pages/user_drawer.dart';
import 'post_card.dart' show CommentMetaRow;
import '../models/article_discussion.dart';
import '../models/models.dart';
import '../models/quote_presentation.dart';
import 'article_image.dart';
import 'avatar_image.dart';
import 'rich_content_text.dart';
import 'content_link_block.dart';
import 'site_link_card.dart';
import '../models/image_stack_group.dart';

enum ArticleCommentPart { complete, header, footer }

class ArticleCommentTile extends StatelessWidget {
  final ArticleCommentPart part;
  final ArticleComment comment;
  final VoidCallback onReply;

  /// 评论模式下归在上一条评论里的回复:头像更小,由列表负责缩进
  final bool nested;

  /// 深层回复的直接回复对象;直接回复主评论时为 null
  final String? replyToAuthor;

  /// 引用已由归组表达时不再重复显示引文
  final bool hideQuotes;

  /// 作者本人的评论加"作者"标签
  final bool byAuthor;

  const ArticleCommentTile({
    super.key,
    required this.comment,
    required this.onReply,
    this.nested = false,
    this.replyToAuthor,
    this.hideQuotes = false,
    this.byAuthor = false,
    this.part = ArticleCommentPart.complete,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    final avatar = nested ? metrics.avatarNested : metrics.avatar;
    if (part == ArticleCommentPart.footer) {
      return HitSlopRegion(
        child: Padding(
          padding: EdgeInsets.only(
            left: avatar + 10,
            bottom: metrics.commentVPad,
          ),
          child: _metadata(),
        ),
      );
    }
    // 与帖子评论同样式:圆形头像、名字、正文,时间后跟浅色"回复"
    return HitSlopRegion(
      child: Padding(
        padding: EdgeInsets.only(
          top: metrics.commentVPad,
          bottom: part == ArticleCommentPart.header ? 0 : metrics.commentVPad,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _profileLink(
              context,
              key: ValueKey('article-comment-avatar-${comment.cid}'),
              child: AvatarImage(
                name: comment.author,
                url: comment.avatarUrl,
                size: avatar,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: _profileLink(
                          context,
                          key: ValueKey(
                            'article-comment-author-${comment.cid}',
                          ),
                          child: Text(
                            comment.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.footnote.copyWith(
                              fontWeight: FontWeight.w600,
                              color: t.text2,
                            ),
                          ),
                        ),
                      ),
                      if (byAuthor)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: t.accentFill,
                              borderRadius: BorderRadius.circular(AppRadii.xs),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              child: Text(
                                '作者',
                                style: AppType.caption.copyWith(
                                  color: t.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (part == ArticleCommentPart.complete)
                    DiscussionCommentContent(
                      blocks: comment.content,
                      hideQuotes: hideQuotes,
                      fallback: comment.text,
                      prefix: replyToAuthor == null
                          ? null
                          : '回复 $replyToAuthor：',
                    ),
                  if (part == ArticleCommentPart.complete) _metadata(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadata() => CommentMetaRow(
    timeLabel: formatDisplayTime(raw: comment.timeRaw, at: comment.time),
    timeSemanticsLabel: comment.timeRaw,
    replyKey: ValueKey('article-comment-reply-${comment.cid}'),
    onReply: onReply,
  );

  Widget _profileLink(
    BuildContext context, {
    required Key key,
    required Widget child,
  }) {
    final uid = comment.authorUid;
    if (uid == null || !RegExp(r'^[1-9]\d{0,8}$').hasMatch(uid)) {
      return KeyedSubtree(key: key, child: child);
    }
    return PressScale(
      key: key,
      semanticLabel: '查看${comment.author}的主页',
      onTap: () => showUserDrawer(context, uid),
      child: child,
    );
  }
}

class DiscussionCommentContent extends StatelessWidget {
  final List<ContentBlock> blocks;
  final String fallback;
  final bool hideQuotes;

  /// 写在正文最前面的"回复 X："
  final String? prefix;

  const DiscussionCommentContent({
    super.key,
    required this.blocks,
    this.fallback = '',
    this.hideQuotes = false,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    final style = TextStyle(
      fontSize: metrics.commentSize,
      color: t.text,
      height: metrics.commentHeight,
    );
    final firstText = blocks.indexWhere((block) => block is TextBlock);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: metrics.textScaler(MediaQuery.textScalerOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (blocks.isEmpty && fallback.isNotEmpty)
            SelectableText('${prefix ?? ''}$fallback', style: style)
          // 没有文字段落(只有图片等)时,回复对象单独一行
          else if (prefix != null && firstText < 0)
            Text(prefix!, style: style),
          for (final segment in groupPostImages(blocks, groupImages: false))
            if (!(hideQuotes &&
                segment.block is QuoteBlock &&
                !(segment.block as QuoteBlock).isNotice))
              DiscussionCommentBlock(
                block: segment.block!,
                siteLinks: segment.siteLinks,
                linksGrouped: segment.linksGrouped,
                linkGroupStart: segment.linkGroupStart,
                linkGroupEnd: segment.linkGroupEnd,
                last:
                    segment.blockIndex + (segment.siteLinks?.length ?? 1) ==
                    blocks.length,
                prefix: segment.blockIndex == firstText ? prefix : null,
              ),
        ],
      ),
    );
  }
}

/// One independently laid-out paragraph, image, quote or link in a comment.
class DiscussionCommentBlock extends StatelessWidget {
  final ContentBlock block;
  final List<SiteLinkBlock>? siteLinks;
  final bool linksGrouped;
  final bool linkGroupStart;
  final bool linkGroupEnd;
  final bool last;
  final String? prefix;
  const DiscussionCommentBlock({
    super.key,
    required this.block,
    this.siteLinks,
    this.linksGrouped = false,
    this.linkGroupStart = true,
    this.linkGroupEnd = true,
    this.last = false,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    final style = TextStyle(
      fontSize: metrics.commentSize,
      color: t.text,
      height: metrics.commentHeight,
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: metrics.textScaler(MediaQuery.textScalerOf(context)),
      ),
      child: _content(metrics, style),
    );
  }

  Widget _content(ReadingMetrics metrics, TextStyle style) {
    return switch (block) {
      TextBlock() => Padding(
        padding: EdgeInsets.only(
          bottom: last ? 0 : ReadingMetrics.paragraphGap,
        ),
        child: RichContentText(
          block: prefix != null
              ? _prefixed(block as TextBlock, prefix!)
              : block as TextBlock,
          style: style,
        ),
      ),
      ImageBlock(:final url) => Padding(
        padding: EdgeInsets.symmetric(vertical: metrics.imageGap),
        child: RepaintBoundary(child: ArticleImage(url: url)),
      ),
      QuoteBlock() => Padding(
        padding: EdgeInsets.only(bottom: ReadingMetrics.paragraphGap),
        child: DiscussionQuote(quote: block as QuoteBlock),
      ),
      SiteLinkBlock() || BilibiliBlock() => Padding(
        padding: EdgeInsets.only(
          bottom: linkGroupEnd ? ReadingMetrics.paragraphGap : 0,
        ),
        child: siteLinks != null
            ? SiteLinkGroupCard(
                blocks: siteLinks!,
                compact: true,
                grouped: linksGrouped,
                first: linkGroupStart,
                last: linkGroupEnd,
              )
            : ContentLinkBlockView(block: block, compact: true),
      ),
    };
  }
}

TextBlock _prefixed(TextBlock block, String prefix) => TextBlock(
  '$prefix${block.text}',
  nodes: block.hasInline ? [InlineText(prefix), ...block.nodes] : const [],
);

class DiscussionQuote extends StatelessWidget {
  final QuoteBlock quote;
  const DiscussionQuote({super.key, required this.quote});

  String _plain(List<ContentBlock> blocks) => blocks
      .map(
        (b) => switch (b) {
          TextBlock(:final text) => text,
          QuoteBlock(:final children) => _plain(children),
          ImageBlock() => '引用图片',
          SiteLinkBlock() || BilibiliBlock() => '',
        },
      )
      .join('\n');

  bool _hasMedia(List<ContentBlock> blocks) => blocks.any(
    (b) => switch (b) {
      TextBlock(:final hasInline) => hasInline,
      QuoteBlock(:final children) => _hasMedia(children),
      _ => true,
    },
  );

  @override
  Widget build(BuildContext context) {
    final display = quoteForDisplay(quote);
    final metrics = ReadingMetrics.of(context);
    final theme = Theme.of(context);
    final t = AppTokens.of(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: metrics.textScaler(MediaQuery.textScalerOf(context)),
      ),
      child: QuoteView(
        key: const ValueKey('discussion-quote'),
        author: display.source ?? '',
        text: _plain(display.children),
        bodyStyle: TextStyle(
          fontSize: metrics.commentSize,
          height: metrics.commentHeight,
        ),
        expandedContent: _hasMedia(display.children)
            ? Theme(
                data: theme.copyWith(
                  extensions: [
                    ...theme.extensions.values.where((e) => e is! AppTokens),
                    t.copyWith(text: t.text2),
                  ],
                ),
                child: DiscussionCommentContent(blocks: display.children),
              )
            : null,
      ),
    );
  }
}
