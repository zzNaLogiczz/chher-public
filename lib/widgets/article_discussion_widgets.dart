/// Discussion-specific surfaces: local motion only, no scroll-driven effects.
library;

import '../design/motion.dart';
import '../design/typography.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/tokens.dart';
import '../ui/app_button.dart';
import '../models/article_discussion.dart';
import '../models/models.dart';
import 'article_image.dart';
import 'net_image.dart';
import 'rich_content_text.dart';
import 'content_link_block.dart';

class ArticleCommentTile extends StatelessWidget {
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
    final avatar = nested ? 22.0 : 28.0;
    // 与帖子评论同样式:圆形头像、名字、正文,时间后跟浅色"回复"
    return Padding(
      padding: EdgeInsets.symmetric(vertical: nested ? 8 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: Container(
              width: avatar,
              height: avatar,
              color: t.fill,
              child: comment.avatarUrl == null
                  ? Icon(AppIcons.person, size: avatar * .55, color: t.text3)
                  : NetImage(
                      url: comment.avatarUrl!,
                      width: avatar,
                      height: avatar,
                    ),
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
                    if (byAuthor)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: t.accentFill,
                            borderRadius: BorderRadius.circular(
                              AppRadii.xs - 2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            child: Text(
                              '作者',
                              style: AppType.caption.copyWith(color: t.accent),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                DiscussionCommentContent(
                  blocks: hideQuotes
                      ? comment.content
                            .where((block) => block is! QuoteBlock)
                            .toList()
                      : comment.content,
                  fallback: comment.text,
                  prefix: replyToAuthor == null ? null : '回复 $replyToAuthor：',
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (comment.timeRaw?.isNotEmpty ?? false)
                      Text(
                        _timeLabel,
                        semanticsLabel: comment.timeRaw,
                        style: AppType.footnote.copyWith(color: t.text3),
                      ),
                    AppButton(
                      key: ValueKey('article-comment-reply-${comment.cid}'),
                      label: '回复',
                      variant: AppButtonVariant.quiet,
                      onPressed: onReply,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
    final style = TextStyle(
      fontSize: AppType.sizeBody,
      color: t.text,
      height: 1.75,
    );
    final firstText = blocks.indexWhere((block) => block is TextBlock);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocks.isEmpty && fallback.isNotEmpty)
          SelectableText('${prefix ?? ''}$fallback', style: style)
        // 没有文字段落(只有图片等)时,回复对象单独一行
        else if (prefix != null && firstText < 0)
          Text(prefix!, style: style),
        for (var i = 0; i < blocks.length; i++)
          switch (blocks[i]) {
            TextBlock() => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RichContentText(
                block: i == firstText && prefix != null
                    ? _prefixed(blocks[i] as TextBlock, prefix!)
                    : blocks[i] as TextBlock,
                style: style,
              ),
            ),
            ImageBlock(:final url) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: RepaintBoundary(child: ArticleImage(url: url)),
            ),
            QuoteBlock() => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DiscussionQuote(
                key: ValueKey('quote-$i'),
                quote: blocks[i] as QuoteBlock,
              ),
            ),
            SiteLinkBlock() || BilibiliBlock() => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ContentLinkBlockView(block: blocks[i]),
            ),
          },
      ],
    );
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
    // 与帖子引用同一种样式:左侧细线,不用灰框(规格 §6.13)
    return Container(
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
                        fontSize: AppType.sizeFootnote,
                        height: 1.65,
                        color: t.text2,
                      ),
                    ),
                  ),
                ),
                ClipRect(
                  child: Align(
                    alignment: Alignment.topLeft,
                    heightFactor: progress.clamp(0, 1),
                    child: ExcludeSemantics(excluding: !_expanded, child: full),
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
