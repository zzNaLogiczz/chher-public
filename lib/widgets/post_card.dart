/// 楼层卡片:楼主楼与回复楼分级
///
/// 晒单与评测帖本质是「一篇文章 + 评论」,所以楼主楼正文与原比例图片连续排版，
/// 回复楼通过作者、时间和轻量引用建立层级。
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';

import '../design/tokens.dart';
import '../design/reading.dart';
import 'package:solar_icons/solar_icons.dart';
import '../ui/press.dart';
import '../ui/hit_slop.dart';
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
  final VoidCallback? onUnlock;
  final Widget? replyContext;
  final Widget? discussionAction;
  final _PostPart _part;
  final ContentBlock? contentBlock;
  final List<String> gallery;
  final int galleryIndex;
  final bool paragraphGapBefore;

  const PostCard({
    super.key,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.nested = false,
    this.replyToAuthor,
    this.onReply,
    this.onUnlock,
    this.replyContext,
    this.discussionAction,
  }) : _part = _PostPart.whole,
       contentBlock = null,
       gallery = const [],
       galleryIndex = 0,
       paragraphGapBefore = false;

  /// Long opening posts are separate lazy list entries, not one huge Column.
  const PostCard.header({
    super.key,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.nested = false,
    this.replyToAuthor,
    this.onReply,
    this.onUnlock,
    this.replyContext,
    this.discussionAction,
  }) : _part = _PostPart.header,
       contentBlock = null,
       gallery = const [],
       galleryIndex = 0,
       paragraphGapBefore = false;

  const PostCard.block({
    super.key,
    required this.post,
    required this.isOpening,
    required this.contentBlock,
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
       replyContext = null,
       discussionAction = null;

  const PostCard.footer({
    super.key,
    required this.post,
    required this.isOpening,
    this.isAuthor = false,
    this.commentStyle = false,
    this.nested = false,
    this.replyToAuthor,
    this.onReply,
    this.onUnlock,
    this.replyContext,
    this.discussionAction,
  }) : _part = _PostPart.footer,
       contentBlock = null,
       gallery = const [],
       galleryIndex = 0,
       paragraphGapBefore = false;

  @override
  Widget build(BuildContext context) => HitSlopRegion(child: _build(context));

  Widget _build(BuildContext context) {
    final t = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    if (_part != _PostPart.whole) return _buildPart(context, t);
    if (commentStyle && !isOpening) return _comment(context, t);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.gutter,
        metrics.postVPad,
        metrics.gutter,
        metrics.postVPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _authorRow(context, t),
          ?replyContext,
          Padding(
            // 回复楼与头像对齐缩进,楼主楼不缩进
            padding: EdgeInsets.only(top: metrics.postVPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 编辑说明排在正文前,补充内容排在正文后 —— 跟站点的阅读顺序一致
                ..._notes(context, t, PostNoteKind.edited),
                ..._blocks(context, t),
                ..._notes(context, t, PostNoteKind.supplement),
                _feedback(),
                _actions(t),
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
        horizontal: nested ? 0 : metrics.gutter,
        vertical: metrics.postVPad,
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
                const SizedBox(height: 2),
                ..._blocks(context, t),
                ..._notes(context, t, PostNoteKind.supplement),
                if (post.rating?.isEmpty == false ||
                    post.comments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  CommentFeedback(rating: post.rating, comments: post.comments),
                ],
                _commentMetaRow(context, t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentMetadata(BuildContext context, AppTokens t) => Row(
    children: [
      Expanded(
        child: Row(
          children: [
            Flexible(
              child: _profileLink(
                context,
                key: ValueKey('post-author-${post.pid}'),
                child: Text(
                  post.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.footnote.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.text2,
                  ),
                ),
              ),
            ),
            if (isAuthor) _ownerBadge(t),
          ],
        ),
      ),
    ],
  );

  Widget _commentMetaRow(BuildContext context, AppTokens t) => CommentMetaRow(
    timeLabel: post.timeRaw,
    replyKey: ValueKey('comment-reply-${post.pid}'),
    onReply: onReply,
  );

  Widget _commentAvatar(BuildContext context, AppTokens t) {
    final metrics = ReadingMetrics.of(context);
    return _profileLink(
      context,
      key: ValueKey('post-avatar-${post.pid}'),
      child: _avatar(t, nested ? metrics.avatarNested : metrics.avatar),
    );
  }

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
    final metrics = ReadingMetrics.of(context);
    if (commentStyle && !isOpening) return _commentPart(context, t, metrics);
    final content = switch (_part) {
      _PostPart.header => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _authorRow(context, t),
          ?replyContext,
          SizedBox(height: metrics.postVPad),
          ..._notes(context, t, PostNoteKind.edited),
          if (post.lock != null) _lockBlock(t),
        ],
      ),
      _PostPart.footer => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._notes(context, t, PostNoteKind.supplement),
          _feedback(),
          _actions(t),
        ],
      ),
      _PostPart.block => _contentBlock(context, t, metrics),
      _PostPart.whole => const SizedBox.shrink(),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        nested ? 0 : metrics.gutter,
        _part == _PostPart.header
            ? metrics.postVPad
            : (!isOpening && paragraphGapBefore ? metrics.paragraphGap : 0),
        nested ? 0 : metrics.gutter,
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
    final content = switch (contentBlock!) {
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
        padding: EdgeInsets.symmetric(vertical: metrics.imageGap),
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

  /// Lazy comments keep the same metadata and indentation as whole comments.
  Widget _commentPart(
    BuildContext context,
    AppTokens t,
    ReadingMetrics metrics,
  ) {
    final avatar = nested ? metrics.avatarNested : metrics.avatar;
    if (_part == _PostPart.header) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          nested ? 0 : metrics.gutter,
          metrics.postVPad,
          nested ? 0 : metrics.gutter,
          2,
        ),
        child: Row(
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
      );
    }
    final child = _part == _PostPart.footer
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._notes(context, t, PostNoteKind.supplement),
              if (post.rating?.isEmpty == false ||
                  post.comments.isNotEmpty) ...[
                const SizedBox(height: 6),
                CommentFeedback(rating: post.rating, comments: post.comments),
              ],
              _commentMetaRow(context, t),
            ],
          )
        : _contentBlock(context, t, metrics);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        (nested ? 0 : metrics.gutter) + avatar + 10,
        paragraphGapBefore ? metrics.paragraphGap : 0,
        nested ? 0 : metrics.gutter,
        _part == _PostPart.footer ? metrics.postVPad : 0,
      ),
      child: child,
    );
  }

  Widget _authorRow(BuildContext context, AppTokens t) {
    final metrics = ReadingMetrics.of(context);
    final size = isOpening ? metrics.openingAvatar : 34.0;
    final row = Row(
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
                          style: TextStyle(
                            fontSize: ThreadMetrics.metaSize,
                            color: t.text3,
                          ),
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
    if (!isOpening) return row;
    return Container(
      padding: EdgeInsets.symmetric(vertical: metrics.postVPad - 2),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: t.separator, width: AppSpace.hairline),
        ),
      ),
      child: row,
    );
  }

  /// 把内容块渲染成组件,并把相邻图片合并成一个宫格
  List<Widget> _blocks(BuildContext context, AppTokens t) {
    if (post.lock != null) return [_lockBlock(t)];
    final metrics = ReadingMetrics.of(context);
    final out = <Widget>[];
    final pendingImages = <String>[];
    var prefix = _replyPrefix;

    void flushImages() {
      if (pendingImages.isEmpty) return;
      out.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: metrics.imageGap),
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
          if (out.isNotEmpty && !isOpening) {
            out.add(SizedBox(height: metrics.paragraphGap));
          }
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
            child: Row(
              children: [
                Icon(SolarIconsOutline.clockCircle, size: 13, color: t.text3),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _editedLabel(n.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ThreadMetrics.metaSize,
                      color: t.text3,
                    ),
                  ),
                ),
              ],
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
            color: t.warnBg,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(4),
              right: Radius.circular(AppRadii.sm),
            ),
            border: Border(left: BorderSide(color: t.warn, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _supplementLabel(n.text),
                style: TextStyle(
                  fontSize: ThreadMetrics.metaSize,
                  fontWeight: FontWeight.w600,
                  color: t.warn,
                ),
              ),
              const SizedBox(height: 5),
              SelectableText(
                n.text.replaceFirst(
                  RegExp(
                    r'^补充内容\s*(?:[（(]\d{4}-\d{2}-\d{2}[^)）]*[)）]\s*[:：]?\s*)?',
                  ),
                  '',
                ),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: AppType.sizeSubhead,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  String _editedLabel(String text) {
    final match = RegExp(
      r'于\s*\d{4}-(\d{2}-\d{2})\s+(\d{2}:\d{2})\s*编辑',
    ).firstMatch(text);
    return match == null ? text : '${match[1]} ${match[2]} 编辑过';
  }

  String _supplementLabel(String text) {
    final match = RegExp(r'\d{4}-(\d{2}-\d{2})').firstMatch(text);
    return match == null ? '楼主补充' : '楼主补充 · ${match[1]}';
  }

  Widget _feedback() => isOpening
      ? OpeningFeedback(rating: post.rating, comments: post.comments)
      : FloorFeedback(rating: post.rating, comments: post.comments);

  /// Opening replies are composed from the reading toolbar only.
  Widget _actions(AppTokens t) {
    if (isOpening || onReply == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (discussionAction != null) ...[
          Expanded(child: discussionAction!),
          const SizedBox(width: 8),
        ],
        _replyControl(
          child: SizedBox(
            height: 20,
            child: Text(
              !post.floorIsKnown ? '回复' : '回复 #${post.floor}',
              style: AppType.footnote.copyWith(
                fontWeight: FontWeight.w500,
                color: t.text3,
              ),
            ),
          ),
        ),
      ],
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

  String? get _replyPrefix =>
      commentStyle && replyToAuthor != null ? '回复 $replyToAuthor：' : null;

  Widget _text(BuildContext context, TextBlock block, {String? prefix}) {
    final metrics = ReadingMetrics.of(context);
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: isOpening ? metrics.bodySize : metrics.commentSize,
      height: isOpening ? metrics.bodyHeight : metrics.commentHeight,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: isOpening ? metrics.paragraphGap : 0),
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

/// 文章与帖子评论共用时间、回复字形度量和透明触区；外层提供 HitSlopRegion。
class CommentMetaRow extends StatelessWidget {
  static final _numericCommentTime = RegExp(r'^[0-9\s:./-]+$');

  final String timeLabel;
  final String? timeSemanticsLabel;
  final Key? replyKey;
  final VoidCallback? onReply;

  const CommentMetaRow({
    super.key,
    required this.timeLabel,
    this.timeSemanticsLabel,
    this.replyKey,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (timeLabel.isEmpty && onReply == null) return const SizedBox.shrink();
    // 数字与中文 fallback 的 ascent/descent 不同，行框齐底不等于基线一致。
    // 两段文字共用继承字体的行度量，字号缩放交给 Text；不做设备像素补偿。
    final strut = StrutStyle.fromTextStyle(
      DefaultTextStyle.of(context).style.merge(AppType.footnote),
      forceStrutHeight: true,
    );
    final opticalLift =
        Theme.of(context).platform == TargetPlatform.android &&
            _numericCommentTime.hasMatch(timeLabel)
        ? MediaQuery.textScalerOf(context).scale(AppType.sizeFootnote) *
              ReadingMetrics.commentReplyOpticalLiftEm
        : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: ReadingMetrics.commentMetaGap),
      child: Wrap(
        spacing: ReadingMetrics.commentMetaGap,
        // 换行后避开回复向上扩展的透明触区，时间文字不触发回复。
        runSpacing: ReadingMetrics.commentMetaRunGap,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          if (timeLabel.isNotEmpty)
            Text(
              timeLabel,
              semanticsLabel: timeSemanticsLabel,
              strutStyle: strut,
              style: AppType.footnote.copyWith(color: t.text3),
            ),
          if (onReply != null)
            _replyControl(
              key: replyKey,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 20),
                // 最小高度只约束触控容器，不拉伸文字段落。
                child: Align(
                  alignment: Alignment.bottomLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  // 在触控容器内部预留光学校正空间，换行后也不侵入上一行。
                  child: Padding(
                    padding: EdgeInsets.only(bottom: opticalLift),
                    child: ExcludeSemantics(
                      child: Text(
                        '回复',
                        strutStyle: strut,
                        style: AppType.footnote.copyWith(
                          color: t.text2,
                          fontWeight: FontWeight.w600,
                        ),
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
