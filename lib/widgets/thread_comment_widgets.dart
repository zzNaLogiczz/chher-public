/// Compact views over already loaded forum replies. These widgets never fetch
/// content and never turn a loaded count into a source-wide total.
library;

import 'package:flutter/material.dart';
import '../ui/press.dart';
import 'package:solar_icons/solar_icons.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/models.dart';
import 'comment_mode_bar.dart';

export 'comment_mode_bar.dart' show CommentViewMode;

/// 帖子沿用评论区共用的查看方式
typedef ThreadViewMode = CommentViewMode;

/// 评论区标题:第一行"评论 N",第二行全宽三段分段(评论 / 原楼层 / 只看楼主)。
/// 两行各自固定,计数变长也不会把分段挤到别的行。
class ThreadCommentHeading extends StatelessWidget {
  /// The caller supplies reply count only; the opening post is excluded.
  final int loadedCount;
  final bool complete;
  final ThreadViewMode mode;
  final ValueChanged<ThreadViewMode> onModeChanged;

  /// 正在读取新查看方式的内容:计数换成等待指示
  final bool busy;

  const ThreadCommentHeading({
    super.key,
    required this.loadedCount,
    required this.complete,
    required this.mode,
    required this.onModeChanged,
    this.busy = false,
  }) : assert(loadedCount >= 0);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('评论', style: AppType.title2.copyWith(color: t.text)),
            const SizedBox(width: 6),
            Flexible(
              child: busy
                  ? const CommentModeBusy()
                  // 只有从第 1 页连续读到末页才给完整数,否则标明是已加载数
                  : Text(
                      complete ? '$loadedCount' : '已加载 $loadedCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.footnote.copyWith(color: t.text3),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CommentModeBar(mode: mode, onChanged: onModeChanged),
      ],
    );
  }
}

class ThreadReplyStrip extends StatelessWidget {
  final List<Post> replies;
  final ValueChanged<Post> onOpen;
  final VoidCallback onOpenAll;
  final bool showAction;
  const ThreadReplyStrip({
    super.key,
    required this.replies,
    required this.onOpen,
    required this.onOpenAll,
    this.showAction = true,
  });

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty) return const SizedBox.shrink();
    final t = AppTokens.of(context);
    final count = replies.length;
    final previewCount = count > 2 ? 2 : count;
    return Container(
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Indexing only these two entries is intentional. Do not map every
          // descendant into this group, even when a long thread has thousands.
          for (var i = 0; i < previewCount; i++)
            _ReplyPreview(post: replies[i], onOpen: onOpen, position: i),
          if (showAction)
            Divider(height: .5, thickness: .5, color: t.separator),
          if (showAction)
            PressScale(
              semanticLabel: '查看已加载的 $count 条回复',
              onTap: onOpenAll,
              scale: .985,
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          SolarIconsBold.chatRoundDots,
                          size: 17,
                          color: t.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '查看已加载的 $count 条回复',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.sizeFootnote,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                              color: t.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          SolarIconsBold.altArrowRight,
                          size: 16,
                          color: t.accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final Post post;
  final ValueChanged<Post> onOpen;
  final int position;
  const _ReplyPreview({
    required this.post,
    required this.onOpen,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final summary = _replySummary(post);
    final author = post.author.trim();
    return PressScale(
      key: ValueKey('thread-reply-preview-${post.pid}-$position'),
      semanticLabel: '${author.isEmpty ? '回复' : author}，$summary，查看回复',
      onTap: () => onOpen(post),
      scale: .985,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(SolarIconsBold.reply, size: 16, color: t.text2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    key: ValueKey('thread-reply-summary-${post.pid}-$position'),
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${author.isEmpty ? '回复' : author}：',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        TextSpan(text: summary),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.sizeFootnote,
                      height: 1.55,
                      color: t.text2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ThreadReplyContext extends StatelessWidget {
  final PostReference reference;

  /// Supply only a same-thread loaded post. Post itself carries no thread ID,
  /// so the caller's conversation index is responsible for that locality check.
  final Post? target;
  final VoidCallback onOpen;
  const ThreadReplyContext({
    super.key,
    required this.reference,
    this.target,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final resolved = target?.pid == reference.pid ? target : null;
    final author = resolved?.author.trim() ?? '';
    final label = author.isEmpty ? '查看引用楼层' : '回复 $author';
    final summary = resolved == null ? null : _replySummary(resolved);
    return PressScale(
      key: ValueKey('thread-reply-context-${reference.tid}-${reference.pid}'),
      semanticLabel: summary == null ? label : '$label，$summary，查看引用楼层',
      onTap: onOpen,
      scale: .985,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.accentFill,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Row(
            children: [
              Icon(SolarIconsBold.reply, size: 18, color: t.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.sizeFootnote,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.sizeFootnote,
                          height: 1.5,
                          color: t.text2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(SolarIconsBold.altArrowRight, size: 16, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Read at most 120 visible graphemes, directly from non-quote text blocks.
/// No concatenation of a complete long post, quote traversal, or image loading.
String _replySummary(Post post) {
  final text = StringBuffer();
  var length = 0;
  var space = false;
  var hasImage = false;
  blocks:
  for (final block in post.content) {
    if (block is ImageBlock) hasImage = true;
    if (block is! TextBlock) continue;
    if (length > 0) space = true;
    for (final char in block.text.characters) {
      if (char.trim().isEmpty) {
        if (length > 0) space = true;
        continue;
      }
      if (space) {
        if (length + 1 >= 120) break blocks;
        text.write(' ');
        length++;
        space = false;
      }
      text.write(char);
      length++;
      if (length == 120) break blocks;
    }
  }
  if (length > 0) return text.toString();
  return hasImage ? '图片回复' : '查看回复';
}
