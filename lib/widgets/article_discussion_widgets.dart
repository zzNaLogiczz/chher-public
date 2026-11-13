/// Discussion-specific surfaces: local motion only, no scroll-driven effects.
library;

import '../design/motion.dart';
import '../design/typography.dart';
import 'package:flutter/material.dart';
import '../design/reading.dart';
import 'package:motor/motor.dart';

import '../design/tokens.dart';
import '../ui/app_button.dart';
import '../ui/hit_slop.dart';
import '../ui/press.dart';
import '../pages/user_drawer.dart';
import 'post_card.dart' show CommentMetaRow;
import '../models/article_discussion.dart';
import '../models/models.dart';
import 'article_image.dart';
import 'avatar_image.dart';
import 'rich_content_text.dart';
import 'content_link_block.dart';

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

  String get _timeLabel {
    final time = comment.time;
    if (time == null) return comment.timeRaw ?? '';
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    if (time.year != DateTime.now().year) return '${time.year}-$month-$day';
    return '$month-$day ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    final avatar = nested ? metrics.avatarNested : metrics.avatar;
    if (part == ArticleCommentPart.footer) {
      return HitSlopRegion(
        child: Padding(
          padding: EdgeInsets.only(left: avatar + 10, bottom: metrics.postVPad),
          child: _metadata(),
        ),
      );
    }
    // 与帖子评论同样式:圆形头像、名字、正文,时间后跟浅色"回复"
    return HitSlopRegion(
      child: Padding(
        padding: EdgeInsets.only(
          top: metrics.postVPad,
          bottom: part == ArticleCommentPart.header ? 0 : metrics.postVPad,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _profileLink(
              context,
              key: ValueKey('article-comment-avatar-${comment.cid}'),
              child: AvatarImage(url: comment.avatarUrl, size: avatar),
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
                      blocks: hideQuotes
                          ? comment.content
                                .where(
                                  (block) =>
                                      block is! QuoteBlock || block.isNotice,
                                )
                                .toList()
                          : comment.content,
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
    timeLabel: (comment.timeRaw?.isNotEmpty ?? false) ? _timeLabel : '',
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

  /// 写在正文最前面的"回复 X："
  final String? prefix;

  const DiscussionCommentContent({
    super.key,
    required this.blocks,
    this.fallback = '',
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
          for (var i = 0; i < blocks.length; i++)
            DiscussionCommentBlock(
              block: blocks[i],
              last: i == blocks.length - 1,
              prefix: i == firstText ? prefix : null,
            ),
        ],
      ),
    );
  }
}

/// One independently laid-out paragraph, image, quote or link in a comment.
class DiscussionCommentBlock extends StatelessWidget {
  final ContentBlock block;
  final bool last;
  final String? prefix;
  const DiscussionCommentBlock({
    super.key,
    required this.block,
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
        padding: EdgeInsets.only(bottom: last ? 0 : metrics.paragraphGap),
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
        padding: EdgeInsets.only(bottom: metrics.paragraphGap),
        child: DiscussionQuote(quote: block as QuoteBlock),
      ),
      SiteLinkBlock() || BilibiliBlock() => Padding(
        padding: EdgeInsets.only(bottom: metrics.paragraphGap),
        child: ContentLinkBlockView(block: block),
      ),
    };
  }
}

TextBlock _prefixed(TextBlock block, String prefix) => TextBlock(
  '$prefix${block.text}',
  nodes: block.hasInline ? [InlineText(prefix), ...block.nodes] : const [],
);

class DiscussionQuote extends StatefulWidget {
  final QuoteBlock quote;
  const DiscussionQuote({super.key, required this.quote});
  @override
  State<DiscussionQuote> createState() => _DiscussionQuoteState();
}

class _DiscussionQuoteState extends State<DiscussionQuote> {
  bool _expanded = false;
  bool _opened = false;
  String _plain(List<ContentBlock> blocks) => blocks
      .map(
        (b) => switch (b) {
          TextBlock(:final text) => text,
          QuoteBlock(:final children) => _plain(children),
          ImageBlock() => '引用图片',
          // 引用里的链接只保留文字,不会产生卡片
          SiteLinkBlock() || BilibiliBlock() => '',
        },
      )
      .join('\n');

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    // 与帖子引用同一种样式:左侧细线,不用灰框(规格 §6.13)
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: metrics.textScaler(MediaQuery.textScalerOf(context)),
      ),
      child: Container(
        key: const ValueKey('discussion-quote'),
        padding: const EdgeInsets.fromLTRB(12, 2, 0, 4),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.fill2, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.quote.source?.isNotEmpty == true
                        ? widget.quote.source!
                        : '引用评论',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.sizeFootnote,
                      color: t.text2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                AppButton(
                  label: _expanded ? '收起引用' : '展开引用',
                  variant: AppButtonVariant.plain,
                  small: true,
                  onPressed: () => setState(() {
                    _expanded = !_expanded;
                    _opened = true;
                  }),
                ),
              ],
            ),
            SingleMotionBuilder(
              value: _expanded ? 1 : 0,
              active: !MediaQuery.disableAnimationsOf(context),
              motion: AppMotion.of(context, AppMotion.reveal),
              child: _opened
                  ? DiscussionCommentContent(blocks: widget.quote.children)
                  : const SizedBox.shrink(),
              builder: (context, progress, full) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topLeft,
                      heightFactor: (1 - progress).clamp(0, 1),
                      child: Text(
                        _plain(widget.quote.children),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: metrics.commentSize,
                          height: metrics.commentHeight,
                          color: t.text2,
                        ),
                      ),
                    ),
                  ),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topLeft,
                      heightFactor: progress.clamp(0, 1),
                      child: ExcludeSemantics(
                        excluding: !_expanded,
                        child: full,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
