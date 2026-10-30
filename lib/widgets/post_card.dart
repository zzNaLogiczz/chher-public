/// 楼层卡片:楼主楼与回复楼分级
///
/// 晒单与评测帖本质是「一篇文章 + 评论」,所以楼主楼正文与原比例图片连续排版，
/// 回复楼通过作者、时间和轻量引用建立层级。
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';

import '../design/tokens.dart';
import '../ui/press.dart';
import '../ui/quote.dart';
import '../design/typography.dart';
import 'expressive_controls.dart';
import '../models/models.dart';
import '../pages/user_drawer.dart';
import 'article_image.dart';
import 'image_grid.dart';
import 'net_image.dart';
import 'rich_content_text.dart';
import 'content_link_block.dart';

enum _PostPart { whole, header, block, footer }

class PostCard extends StatelessWidget {
  final Post post;

  /// 第一楼按文章排版,其余按回复排版
  final bool isOpening;
  final bool isAuthor;

  /// Comment mode displays the author’s own content without historical quotes.
  final bool commentStyle;

  /// Only a nested reply's direct, loaded recipient; root replies omit this.
  final String? replyToAuthor;

  /// 回复这一楼。给每层一个明确入口,长按引用不够显眼。
  final VoidCallback? onReply;
  final VoidCallback? onUnlock;
  final Widget? replyContext;
  final Widget? discussionAction;
  final _PostPart _part;
  final ContentBlock? contentBlock;
  final List<String> gallery;
  final int galleryIndex;

  const PostCard({
    super.key,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.replyToAuthor,
    this.onReply,
    this.onUnlock,
    this.replyContext,
    this.discussionAction,
  }) : _part = _PostPart.whole,
       contentBlock = null,
       gallery = const [],
       galleryIndex = 0;

  /// Long opening posts are separate lazy list entries, not one huge Column.
  const PostCard.header({
    super.key,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.replyToAuthor,
    this.onReply,
    this.onUnlock,
    this.replyContext,
    this.discussionAction,
  }) : _part = _PostPart.header,
       contentBlock = null,
       gallery = const [],
       galleryIndex = 0;

  const PostCard.block({
    super.key,
    required this.post,
    required this.isOpening,
    required this.contentBlock,
    this.gallery = const [],
    this.galleryIndex = 0,
    this.isAuthor = false,
    this.commentStyle = false,
    this.replyToAuthor,
    this.onUnlock,
  }) : _part = _PostPart.block,
       onReply = null,
       replyContext = null,
       discussionAction = null;

  const PostCard.footer({
    super.key,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.replyToAuthor,
    this.onReply,
    this.onUnlock,
    this.replyContext,
    this.discussionAction,
  }) : _part = _PostPart.footer,
       contentBlock = null,
       gallery = const [],
       galleryIndex = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (_part != _PostPart.whole) return _buildPart(context, t);
    if (commentStyle) return _comment(context, t);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        isOpening ? 24 : 20,
        24,
        isOpening ? 26 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _authorRow(context, t),
          ?replyContext,
          Padding(
            // 回复楼与头像对齐缩进,楼主楼不缩进
            padding: EdgeInsets.only(top: isOpening ? 18 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 编辑说明排在正文前,补充内容排在正文后 —— 跟站点的阅读顺序一致
                ..._notes(context, t, PostNoteKind.edited),
                ..._blocks(context, t),
                ..._notes(context, t, PostNoteKind.supplement),
                if (post.rating != null) _ratingBlock(context, t, post.rating!),
                if (post.comments.isNotEmpty) _commentsBlock(context, t),
                _actions(t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comment(BuildContext context, AppTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _profileLink(
          context,
          key: ValueKey('post-avatar-${post.pid}'),
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _avatar(t, 28),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: _profileLink(
                      context,
                      key: ValueKey('post-author-${post.pid}'),
                      child: Text(
                        post.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.sizeFootnote,
                          fontWeight: FontWeight.w600,
                          color: t.text2,
                        ),
                      ),
                    ),
                  ),
                  // 评论区里楼主的评论和楼中楼回复同样标出楼主
                  if (isAuthor) _ownerBadge(t),
                ],
              ),
              const SizedBox(height: 4),
              ..._blocks(context, t),
              ..._notes(context, t, PostNoteKind.supplement),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (post.timeRaw.isNotEmpty)
                    Text(
                      post.timeRaw,
                      style: TextStyle(
                        fontSize: AppType.sizeFootnote,
                        color: t.text3,
                      ),
                    ),
                  if (onReply != null)
                    AppButton(
                      key: ValueKey('comment-reply-${post.pid}'),
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

  Widget _ownerBadge(AppTokens t) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: t.accentFill,
        borderRadius: BorderRadius.circular(AppRadii.xs - 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text('楼主', style: AppType.caption.copyWith(color: t.accent)),
      ),
    ),
  );

  Widget _avatar(AppTokens t, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 2),
    child: Container(
      width: size,
      height: size,
      color: t.fill,
      child: post.avatarUrl == null
          ? Icon(AppIcons.person, size: size * .55, color: t.text3)
          : NetImage(url: post.avatarUrl!, width: size, height: size),
    ),
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
        : () => showUserDrawer(context, post.authorUid!),
    child: child,
  );

  Widget _lockBlock(AppTokens t) {
    final lock = post.lock!;
    return Container(
      key: ValueKey('post-lock-${post.pid}'),
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.lock, color: t.text2, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lock.text,
                  style: AppType.body.copyWith(color: t.text2),
                ),
              ),
            ],
          ),
          if (lock.needsPassword) ...[
            const SizedBox(height: 8),
            AppButton(label: '输入密码', onPressed: onUnlock),
          ],
        ],
      ),
    );
  }

  Widget _buildPart(BuildContext context, AppTokens t) {
    final content = switch (_part) {
      _PostPart.header => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _authorRow(context, t),
          ?replyContext,
          const SizedBox(height: 16),
          ..._notes(context, t, PostNoteKind.edited),
          if (post.lock != null) _lockBlock(t),
        ],
      ),
      _PostPart.footer => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._notes(context, t, PostNoteKind.supplement),
          if (post.rating != null) _ratingBlock(context, t, post.rating!),
          if (post.comments.isNotEmpty) _commentsBlock(context, t),
          _actions(t),
        ],
      ),
      _PostPart.block => switch (contentBlock!) {
        final TextBlock textBlock => _text(
          context,
          textBlock,
          prefix: _replyPrefix,
        ),
        QuoteBlock(:final source, :final children) => _quote(
          context,
          t,
          source,
          children,
        ),
        SiteLinkBlock() || BilibiliBlock() => _linkBlock(contentBlock!),
        ImageBlock(:final url) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 16),
          child: Semantics(
            button: true,
            label: '查看第 ${galleryIndex + 1} 张图片',
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ImageViewerPage(
                    urls: gallery.isEmpty ? [url] : gallery,
                    initialIndex: galleryIndex,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: ArticleImage(url: url),
              ),
            ),
          ),
        ),
      },
      _PostPart.whole => const SizedBox.shrink(),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        _part == _PostPart.header ? (isOpening ? 24 : 20) : 0,
        24,
        _part == _PostPart.footer ? (isOpening ? 26 : 20) : 0,
      ),
      child:
          _part == _PostPart.block &&
              contentBlock is! TextBlock &&
              _replyPrefix != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(context, const TextBlock(''), prefix: _replyPrefix),
                content,
              ],
            )
          : content,
    );
  }

  Widget _authorRow(BuildContext context, AppTokens t) {
    final size = isOpening ? 38.0 : 32.0;
    return Row(
      children: [
        Expanded(
          child: _profileLink(
            context,
            key: ValueKey('post-profile-${post.pid}'),
            child: Row(
              children: [
                _avatar(t, size),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.subhead.copyWith(
                                fontWeight: FontWeight.w600,
                                color: t.text,
                              ),
                            ),
                          ),
                          // 楼主小标签紧跟名字,不再单独占右侧
                          if (isOpening || isAuthor) _ownerBadge(t),
                        ],
                      ),
                      if (post.timeRaw.isNotEmpty)
                        Text(
                          post.timeRaw,
                          style: AppType.footnote.copyWith(color: t.text3),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 首楼的 #1 没有意义;其余楼层保留楼层号便于对照原帖
        if (!isOpening) ...[
          const SizedBox(width: 8),
          Text(
            post.floorIsKnown ? '#${post.floor}' : '原帖',
            style: AppType.footnote.copyWith(color: t.text3),
          ),
        ],
      ],
    );
  }

  /// 把内容块渲染成组件,并把相邻图片合并成一个宫格
  List<Widget> _blocks(BuildContext context, AppTokens t) {
    if (post.lock != null) return [_lockBlock(t)];
    final out = <Widget>[];
    final pendingImages = <String>[];
    var prefix = _replyPrefix;

    void flushImages() {
      if (pendingImages.isEmpty) return;
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: ImageGrid(
            List.of(pendingImages),
            preserveAspectRatio: isOpening,
          ),
        ),
      );
      pendingImages.clear();
    }

    for (final block in post.content) {
      if (block is QuoteBlock &&
          !block.isNotice &&
          (commentStyle || (!isOpening && replyContext != null))) {
        continue;
      }
      if (prefix != null && block is! TextBlock) {
        out.add(_text(context, const TextBlock(''), prefix: prefix));
      }
      switch (block) {
        case ImageBlock(:final url):
          pendingImages.add(url);
        case TextBlock():
          flushImages();
          out.add(_text(context, block, prefix: prefix));
        case QuoteBlock(:final source, :final children):
          flushImages();
          out.add(_quote(context, t, source, children));
        case SiteLinkBlock() || BilibiliBlock():
          flushImages();
          out.add(_linkBlock(block));
      }
      prefix = null;
    }
    flushImages();
    if (prefix != null) {
      out.add(_text(context, const TextBlock(''), prefix: prefix));
    }
    return out;
  }

  /// 站内卡片与视频:和正文同宽,上下留出与段落相近的间距
  Widget _linkBlock(ContentBlock block) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: ContentLinkBlockView(block: block),
  );

  /// 说明块
  ///
  /// 编辑说明只是一行元信息,压到最弱;补充内容是楼主后补的正文,
  /// 要能一眼看出它不属于原帖,所以给一条左边界和标题。
  List<Widget> _notes(BuildContext context, AppTokens t, PostNoteKind kind) {
    final notes = post.notes.where((n) => n.kind == kind);
    if (notes.isEmpty) return const [];

    if (kind == PostNoteKind.edited) {
      return [
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              n.text,
              style: TextStyle(fontSize: AppType.sizeFootnote, color: t.text3),
            ),
          ),
      ];
    }

    return [
      for (final n in notes)
        Container(
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: t.separator, width: AppSpace.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '补充内容',
                style: TextStyle(
                  fontSize: AppType.sizeFootnote,
                  fontWeight: FontWeight.w600,
                  color: t.text2,
                ),
              ),
              const SizedBox(height: 5),
              SelectableText(
                n.text.replaceFirst(RegExp(r'^补充内容\s*'), ''),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: AppType.sizeBody,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// 评分
  ///
  /// 汇总项用强调色,明细一行一条:谁、加了多少、理由。
  /// 分值保留站点原文,不自行换算。
  Widget _ratingBlock(BuildContext context, AppTokens t, PostRating rating) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.accentFill,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                '评分',
                style: TextStyle(
                  fontSize: AppType.sizeFootnote,
                  fontWeight: FontWeight.w600,
                  color: t.accent,
                ),
              ),
              for (final s in rating.summary)
                Text(
                  s,
                  style: TextStyle(
                    fontSize: AppType.sizeFootnote,
                    color: t.accent,
                  ),
                ),
            ],
          ),
          for (final e in rating.entries)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      e.user,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.sizeFootnote,
                        color: t.text,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      e.score,
                      style: TextStyle(
                        fontSize: AppType.sizeFootnote,
                        fontWeight: FontWeight.w600,
                        color: t.accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.reason ?? '',
                      style: TextStyle(
                        fontSize: AppType.sizeFootnote,
                        color: t.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 点评:挂在楼层下方的短评论,比正文弱一档
  Widget _commentsBlock(BuildContext context, AppTokens t) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in post.comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        c.author,
                        style: TextStyle(
                          fontSize: AppType.sizeFootnote,
                          fontWeight: FontWeight.w500,
                          color: t.text,
                        ),
                      ),
                      const Spacer(),
                      if (c.timeRaw != null)
                        Text(
                          c.timeRaw!,
                          style: TextStyle(
                            fontSize: AppType.sizeFootnote,
                            color: t.text3,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    c.text,
                    style: TextStyle(
                      fontSize: AppType.sizeFootnote,
                      height: 1.6,
                      color: t.text2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 楼层操作:回复这一层
  Widget _actions(AppTokens t) {
    if (onReply == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (discussionAction != null) ...[
          Expanded(child: discussionAction!),
          const SizedBox(width: 8),
        ],
        // 回复是一行浅色文字操作,不再是灰色方块
        PressHighlight(
          onTap: onReply,
          borderRadius: BorderRadius.circular(AppRadii.xs),
          semanticLabel: '回复',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                widthFactor: 1,
                child: Text(
                  isOpening || !post.floorIsKnown ? '回复' : '回复 #${post.floor}',
                  style: AppType.footnote.copyWith(
                    fontWeight: FontWeight.w500,
                    color: t.text3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String? get _replyPrefix =>
      commentStyle && replyToAuthor != null ? '回复 $replyToAuthor：' : null;

  Widget _text(BuildContext context, TextBlock block, {String? prefix}) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: commentStyle ? AppType.sizeBody - 1 : AppType.sizeBody,
      height: isOpening ? 1.85 : 1.7,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichContentText(
        block: prefix == null
            ? block
            : TextBlock(
                '$prefix${block.text}',
                nodes: block.hasInline
                    ? [InlineText(prefix), ...block.nodes]
                    : const [],
              ),
        style: style,
      ),
    );
  }

  /// 引用块只保留署名与纯文本,嵌套引用不再展开第二层
  Widget _quote(
    BuildContext context,
    AppTokens t,
    String? source,
    List<ContentBlock> children,
  ) {
    final text = children
        .whereType<TextBlock>()
        .map((b) => b.text)
        .join(' ')
        .trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: QuoteView(author: source ?? '', text: text, collapsedLines: 4),
    );
  }
}
