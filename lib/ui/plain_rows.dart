/// 内容页的平铺行：按下变底色，仅以留白分隔。
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import 'balanced_title.dart';
import '../design/icons.dart';
import '../design/forum_tokens.dart';
import '../design/thread_row_tokens.dart';
import '../core/chh_urls.dart';
import '../core/display_time.dart';
import '../design/display_text.dart';
import '../widgets/avatar_image.dart';
import '../design/motion.dart';
import '../design/notice_tokens.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../data/thread_read_index.dart';
import '../design/typography.dart';
import '../models/models.dart';
import 'app_button.dart';
import 'press.dart';

class PlainRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool separator;
  final double? verticalPadding;
  final BorderRadius? borderRadius;

  const PlainRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.screen,
      AppRowTokens.plainVerticalPadding,
      AppSpace.screen,
      0,
    ),
    this.separator = true,
    this.verticalPadding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final scope = PlainRowScope.maybeOf(context);
    final rowPadding = padding.resolve(Directionality.of(context));
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        scope?.inset ?? rowPadding.left,
        verticalPadding ??
            (scope == null
                ? rowPadding.top
                : AppRowTokens.plainVerticalPadding),
        scope?.inset ?? rowPadding.right,
        verticalPadding ??
            (scope == null ? rowPadding.bottom : 0) +
                AppRowTokens.plainVerticalPadding,
      ),
      child: SizedBox(width: double.infinity, child: child),
    );
    return onTap == null
        ? content
        : PressHighlight(
            onTap: onTap,
            borderRadius: borderRadius,
            child: content,
          );
  }
}

/// 放进卡片里的平铺行:左右内边距与卡片对齐,末行不画分隔线;
/// 卡片标题已说明的身份(如"置顶")不在每行重复
class PlainRowScope extends InheritedWidget {
  final double inset;
  final bool separator;
  final bool impliesSticky;

  const PlainRowScope({
    super.key,
    required this.inset,
    this.separator = true,
    this.impliesSticky = false,
    required super.child,
  });

  static PlainRowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlainRowScope>();

  @override
  bool updateShouldNotify(PlainRowScope oldWidget) =>
      inset != oldWidget.inset ||
      separator != oldWidget.separator ||
      impliesSticky != oldWidget.impliesSticky;
}

/// 标题色:只有"已看"降为 text2;未看与有新回复都保持强色
Color readTitleColor(AppTokens t, ThreadReadState state) =>
    state is ThreadReadSeen ? t.text2 : t.text;

/// 行级重绘范围:监听放在每一行内部,一次 markRead 只重建状态真正变化的那一行。
/// 绝不能挪到 ListView 外层;也不能用裸 ListenableBuilder,
/// 否则全局索引的每次通知都会让屏上每一行重跑 builder。
/// [replies] 为空表示回复数未知,只区分未看/已看。
class ReadStateBuilder extends StatefulWidget {
  final int tid;
  final int? replies;
  final Widget Function(BuildContext context, ThreadReadState state) builder;

  const ReadStateBuilder({
    super.key,
    required this.tid,
    required this.replies,
    required this.builder,
  });

  @override
  State<ReadStateBuilder> createState() => _ReadStateBuilderState();
}

class _ReadStateBuilderState extends State<ReadStateBuilder> {
  late ThreadReadState _state = _lookup();

  ThreadReadState _lookup() =>
      threadReadIndex.stateOf(widget.tid, replies: widget.replies);

  @override
  void initState() {
    super.initState();
    threadReadIndex.addListener(_onIndexChanged);
  }

  @override
  void didUpdateWidget(ReadStateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _state = _lookup();
  }

  @override
  void dispose() {
    threadReadIndex.removeListener(_onIndexChanged);
    super.dispose();
  }

  // 通知是全局的:只有本行状态真的变了才重建,其余行零开销
  void _onIndexChanged() {
    final next = _lookup();
    if (_sameState(_state, next)) return;
    setState(() => _state = next);
  }

  static bool _sameState(ThreadReadState a, ThreadReadState b) =>
      a.runtimeType == b.runtimeType &&
      (a is! ThreadReadNewReplies ||
          a.count == (b as ThreadReadNewReplies).count);

  @override
  Widget build(BuildContext context) => widget.builder(context, _state);
}

/// Shared title and metadata layout for forum, discussion, search and account lists.
class ThreadRow extends StatelessWidget {
  final ThreadSummary thread;
  final String? eyebrow;
  final String? timeLabel;
  final bool showCategory;
  final bool forumStyle;
  final String? excerpt;
  final String? query;
  final bool trimEmptySearchTail;
  final Widget? footer;
  final VoidCallback? onTap;
  final bool locked;
  final VoidCallback? onLogin;
  final ThreadReadState readState;

  const ThreadRow({
    super.key,
    required this.thread,
    this.eyebrow,
    this.timeLabel,
    this.showCategory = true,
    this.forumStyle = false,
    this.excerpt,
    this.query,
    this.trimEmptySearchTail = false,
    this.footer,
    this.onTap,
    this.locked = false,
    this.onLogin,
    this.readState = const ThreadReadUnseen(),
  });

  /// Account rows only have a subset of the forum list fields.
  factory ThreadRow.entry({
    required int tid,
    required String title,
    String? category,
    String? timeRaw,
    int? replies,
    Widget? footer,
    VoidCallback? onTap,
    ThreadReadState readState = const ThreadReadUnseen(),
  }) => ThreadRow(
    thread: ThreadSummary(
      tid: tid,
      title: title,
      author: '',
      forumName: category,
      lastPostTimeRaw: timeRaw,
      replies: replies ?? 0,
      views: 0,
    ),
    footer: footer,
    onTap: onTap,
    readState: readState,
  );

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final when = timeLabel ?? displayTime(thread);
    final category = showCategory
        ? eyebrow ?? thread.forumName ?? thread.typeName
        : null;
    final label = category == null ? null : formatForumName(category);
    final sticky =
        thread.sticky &&
        !(PlainRowScope.maybeOf(context)?.impliesSticky ?? false);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? AppMotion.reducedFade
        : AppMotion.fade;
    final summary = (excerpt ?? thread.snippet)?.trim();
    final title = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: readTitleColor(t, readState)),
      duration: duration,
      builder: (context, color, _) => _text(
        thread.title,
        ThreadRowTokens.title.copyWith(color: color),
        accent: t.accent,
      ),
    );
    final snippet = summary == null || summary.isEmpty
        ? null
        : _text(
            summary,
            ThreadRowTokens.summary.copyWith(color: t.text2),
            accent: t.accent,
            lines: ThreadRowTokens.searchSummaryLines,
          );
    final metadata =
        sticky ||
            label?.isNotEmpty == true ||
            thread.author.isNotEmpty ||
            when.isNotEmpty ||
            thread.hasImages ||
            (!locked && thread.replies > 0)
        ? _metadata(t, label, when, sticky, duration)
        : null;
    return PlainRow(
      verticalPadding: ThreadRowTokens.verticalPadding,
      borderRadius: forumStyle
          ? BorderRadius.circular(ForumTokens.rowRadius)
          : null,
      onTap: onTap,
      child: Semantics(
        label: readState is ThreadReadSeen ? '已看' : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (query != null && (!trimEmptySearchTail || metadata != null))
              SearchThreadRowLayout(
                title: title,
                summary: snippet,
                metadata: metadata,
              )
            else ...[
              title,
              if (snippet != null) ...[
                const SizedBox(height: ThreadRowTokens.summaryGap),
                snippet,
              ],
              if (metadata != null) ...[
                const SizedBox(height: ThreadRowTokens.gap),
                metadata,
              ],
            ],
            if (locked)
              Padding(
                padding: const EdgeInsets.only(top: ThreadRowTokens.gap),
                child: Row(
                  children: [
                    Text(
                      '需登录',
                      style: AppType.footnote.copyWith(color: t.warn),
                    ),
                    const Spacer(),
                    AppButton(
                      label: '登录',
                      small: true,
                      variant: AppButtonVariant.tinted,
                      onPressed: onLogin,
                    ),
                  ],
                ),
              ),
            ?footer,
          ],
        ),
      ),
    );
  }

  Widget _text(
    String value,
    TextStyle style, {
    required Color accent,
    int lines = 1,
  }) {
    final display = normalizeDisplayText(value);
    final keyword = query;
    if (keyword == null) {
      return Text(
        display,
        style: style,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      highlight(display, normalizeDisplayText(keyword), accent),
      style: style,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _metadata(
    AppTokens t,
    String? label,
    String? when,
    bool sticky,
    Duration duration,
  ) {
    const gap = SizedBox(width: ThreadRowTokens.gap);
    final separator = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ThreadRowTokens.separatorInset,
      ),
      child: SizedBox.square(
        dimension: ThreadRowTokens.separatorSize,
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.text3, shape: BoxShape.circle),
        ),
      ),
    );
    final style = ThreadRowTokens.metadata.copyWith(color: t.text3);
    final hasAuthor = thread.author.isNotEmpty;
    final hasCategory = label?.isNotEmpty == true;
    final hasIdentity = hasAuthor || hasCategory || sticky;
    final hasTime = when?.isNotEmpty == true;
    final count = !locked && thread.replies > 0;
    final uid = thread.authorUid?.trim();
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (hasAuthor && query == null) ...[
                  AnimatedOpacity(
                    opacity: readState is ThreadReadSeen
                        ? ThreadRowTokens.seenAvatarOpacity
                        : 1,
                    duration: duration,
                    child: AvatarImage(
                      key: ValueKey('thread-avatar-${thread.tid}'),
                      name: thread.author,
                      url: uid != null && RegExp(r'^\d{1,9}$').hasMatch(uid)
                          ? ChhUrls.avatar(uid)
                          : null,
                      size: ThreadRowTokens.avatarSize,
                      lazy: true,
                    ),
                  ),
                  gap,
                ],
                if (sticky) ...[
                  Flexible(
                    child: _oneLine('置顶', style.copyWith(color: t.warn)),
                  ),
                  if (hasCategory || hasAuthor) separator,
                ],
                if (hasCategory) ...[
                  Flexible(child: _oneLine(label!, style)),
                  if (hasAuthor) separator,
                ],
                if (hasAuthor)
                  Flexible(
                    child: _oneLine(
                      thread.author,
                      style.copyWith(color: t.text2),
                    ),
                  ),
                if (hasTime) ...[
                  if (hasIdentity) separator,
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          constraints.maxWidth *
                          ThreadRowTokens.timeWidthFraction,
                    ),
                    child: _oneLine(when!, style),
                  ),
                ],
                if (thread.hasImages) ...[
                  if (hasIdentity || hasTime) separator,
                  Icon(
                    AppIcons.image,
                    size: ThreadRowTokens.iconSize,
                    color: t.text3,
                    semanticLabel: '含图',
                  ),
                ],
              ],
            ),
          ),
          if (count) ...[
            gap,
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    constraints.maxWidth * ThreadRowTokens.countWidthFraction,
              ),
              child: _replies(t, style),
            ),
          ],
        ],
      ),
    );
  }

  Widget _replies(AppTokens t, TextStyle style) {
    final state = readState;
    final fresh = state is ThreadReadNewReplies ? state.count : null;
    return Semantics(
      label: fresh == null
          ? '${thread.replies} 回复'
          : '有 $fresh 条新回复，共 ${thread.replies} 回复',
      excludeSemantics: true,
      child: FittedBox(
        key: ValueKey('thread-count-${thread.tid}'),
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.comments,
              size: ThreadRowTokens.iconSize,
              color: t.text3,
            ),
            const SizedBox(width: ThreadRowTokens.iconGap),
            _oneLine(_compactCount(thread.replies), style),
            if (fresh != null) ...[
              const SizedBox(width: ThreadRowTokens.iconGap),
              _oneLine(
                '+${_compactCount(fresh)}',
                style.copyWith(color: t.accent, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _oneLine(String text, TextStyle style) =>
      Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);

  static String _compactCount(int count) => count < 10000
      ? '$count'
      : '${(count / 10000).toStringAsFixed(count < 100000 ? 1 : 0)}万';

  static String displayTime(ThreadSummary thread) => formatDisplayTime(
    raw:
        thread.createdAtRaw ??
        (thread.createdAt == null ? thread.lastPostTimeRaw : null),
    at: thread.createdAt,
    style: DisplayTimeStyle.list,
  );

  /// 不区分大小写地标出所有命中片段
  static TextSpan highlight(String text, String query, Color color) {
    final keyword = query.trim();
    if (keyword.isEmpty) return TextSpan(text: text);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in RegExp(
      RegExp.escape(keyword),
      caseSensitive: false,
    ).allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(color: color),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(children: spans);
  }
}

/// Search reserves the same line slots for placeholders and loaded results.
class SearchThreadRowLayout extends StatelessWidget {
  const SearchThreadRowLayout({
    super.key,
    required Widget this.title,
    this.summary,
    this.metadata,
  }) : skeleton = false;

  const SearchThreadRowLayout.skeleton({super.key})
    : title = null,
      summary = null,
      metadata = null,
      skeleton = true;

  final Widget? title, summary, metadata;
  final bool skeleton;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _slot(context, ThreadRowTokens.title, title, const [
        ThreadRowTokens.searchSkeletonTitleWidth,
      ]),
      const SizedBox(height: ThreadRowTokens.summaryGap),
      _slot(
        context,
        ThreadRowTokens.summary,
        summary,
        ThreadRowTokens.searchSkeletonSummaryWidths,
      ),
      const SizedBox(height: ThreadRowTokens.gap),
      _slot(context, ThreadRowTokens.metadata, metadata, const [
        ThreadRowTokens.searchSkeletonMetadataWidth,
      ]),
    ],
  );

  Widget _slot(
    BuildContext context,
    TextStyle style,
    Widget? child,
    List<double> widths,
  ) {
    final lineHeight =
        (MediaQuery.textScalerOf(context).scale(style.fontSize!) *
                style.height!)
            .ceilToDouble();
    return SizedBox(
      height: lineHeight * widths.length,
      child: skeleton
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final width in widths)
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: width,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTokens.of(context).fill,
                            borderRadius: BorderRadius.circular(AppRadii.xs),
                          ),
                          child: SizedBox(
                            height:
                                lineHeight *
                                ThreadRowTokens.searchSkeletonBarHeight,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : Align(alignment: AlignmentDirectional.topStart, child: child),
    );
  }
}

/// 置顶帖分组:收起时是一行"置顶帖  N 条 ⌄";展开时灰色底向下长成大卡片,
/// 置顶帖排在卡片内,收起时卡片向上折回一行
class PinnedGroupRow extends StatelessWidget {
  final int count;
  final String? firstTitle;
  final bool expanded;
  final VoidCallback onToggle;

  /// 卡片内第 i 条置顶帖;只在展开或动画进行中构建
  final IndexedWidgetBuilder itemBuilder;

  const PinnedGroupRow({
    super.key,
    required this.count,
    this.firstTitle,
    required this.expanded,
    required this.onToggle,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.groupInset,
        2,
        AppSpace.groupInset,
        6,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: t.surface,
          shape: appShape(ForumTokens.groupRadius),
        ),
        child: AppClip(
          radius: ForumTokens.groupRadius,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(t, reduced),
              // 高度只作用于卡片内新出现的置顶帖;灰色底随之伸缩,不另画一层
              SingleMotionBuilder(
                value: expanded ? 1 : 0,
                active: !reduced && count <= 24,
                motion: AppMotion.of(context, AppMotion.reveal),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ForumTokens.groupInset,
                    0,
                    ForumTokens.groupInset,
                    ForumTokens.groupInset,
                  ),
                  child: AppClip(
                    radius: ForumTokens.rowRadius,
                    child: _rows(t),
                  ),
                ),
                builder: (context, progress, rows) {
                  final p = progress.clamp(0.0, 1.0);
                  if (p == 0) return const SizedBox.shrink();
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: p,
                      child: rows,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppTokens t, bool reduced) => PressHighlight(
    onTap: onToggle,
    paintInset: const EdgeInsets.all(ForumTokens.groupInset),
    borderRadius: BorderRadius.circular(ForumTokens.rowRadius),
    semanticLabel: '置顶帖 $count 条',
    child: Semantics(
      expanded: expanded,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.singleLineHeight - 2 * ForumTokens.groupInset,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '置顶',
                style: AppType.caption.copyWith(
                  color: t.warn,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedOpacity(
                  opacity: expanded ? 0 : 1,
                  duration: reduced ? AppMotion.reducedFade : AppMotion.fade,
                  child: Text(
                    firstTitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.filter.copyWith(
                      color: t.text2,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count 条',
                style: AppType.footnote.copyWith(color: t.text3),
              ),
              const SizedBox(width: 2),
              SingleMotionBuilder(
                value: expanded ? .5 : 0.0,
                active: !reduced,
                motion: AppMotion.select,
                builder: (_, turns, child) => Transform.rotate(
                  angle: turns * 6.283185307179586,
                  child: child,
                ),
                child: Icon(AppIcons.down, size: 15, color: t.text3),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _rows(AppTokens t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < count; i++)
        PlainRowScope(
          inset: 12,
          separator: false,
          impliesSticky: true,
          child: Builder(builder: (context) => itemBuilder(context, i)),
        ),
    ],
  );
}

/// Source-backed notice sentences and conversation previews inside message cards.
class NoticeRow extends StatefulWidget {
  static const unreadDotKey = ValueKey('notice-unread-dot');

  final Widget avatar;
  final String name;
  final String time;
  final String text;
  final bool unread;
  final VoidCallback? onTap;
  final String? title;
  final String? replyText;
  final String? scoreText;
  final String? category;
  final bool system;
  final bool conversation;
  final bool isOutgoing;

  const NoticeRow({
    super.key,
    required this.avatar,
    required this.name,
    required this.time,
    required this.text,
    this.unread = false,
    this.onTap,
    this.title,
    this.replyText,
    this.scoreText,
    this.category,
    this.system = false,
    this.conversation = false,
    this.isOutgoing = false,
  });

  @override
  State<NoticeRow> createState() => _NoticeRowState();
}

class _NoticeRowState extends State<NoticeRow>
    with SingleTickerProviderStateMixin {
  late bool _unread = widget.unread;
  late final _dot = AnimationController.unbounded(
    vsync: this,
    value: widget.unread ? .6 : 0,
  );
  bool _started = false;

  void _changeUnread() {
    if (!_dot.isAnimating && _dot.value == (_unread ? 1 : 0)) return;
    if (_unread && _dot.value == 0) _dot.value = .6;
    AppMotion.settle(
      _dot,
      target: _unread ? 1 : 0,
      motion: _unread ? AppMotion.pop : AppMotion.tap,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started || MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _changeUnread();
    }
  }

  @override
  void didUpdateWidget(covariant NoticeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unread == widget.unread) return;
    _unread = widget.unread;
    _changeUnread();
  }

  void _open() {
    if (_unread) {
      setState(() => _unread = false);
      _changeUnread();
    }
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final name = widget.system ? '系统' : widget.name;
    final title = switch (widget.title) {
      final value? => normalizeDisplayText(value.trim()),
      null => null,
    };
    final reply = widget.replyText;
    final score = widget.conversation ? null : widget.scoreText?.trim();
    final hasScore = score != null && score.isNotEmpty;
    final rawText = widget.text;
    final action = normalizeDisplayText(
      hasScore
          ? rawText
                .replaceFirst(score, '')
                .trim()
                .replaceAll(_ratingActionWhitespace, ' ')
          : rawText,
    );
    final titleText = title == null || title.isEmpty
        ? null
        : title.startsWith('《') && title.endsWith('》')
        ? title
        : '《$title》';
    final content = Padding(
      padding: widget.conversation
          ? NoticeTokens.conversationPadding
          : NoticeTokens.rowPadding,
      child: Row(
        crossAxisAlignment: widget.conversation
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          _avatar(t),
          const SizedBox(width: NoticeTokens.avatarGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: widget.conversation
                            ? Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NoticeTokens.name.copyWith(
                                  color: t.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : Text.rich(
                                key: const ValueKey('notice-sentence'),
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: name,
                                      style: TextStyle(
                                        color: t.text,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (action.isNotEmpty)
                                      const TextSpan(text: ' '),
                                    TextSpan(text: action),
                                  ],
                                ),
                                maxLines: hasScore ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: NoticeTokens.sentence.copyWith(
                                  color: t.text2,
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              constraints.maxWidth *
                              NoticeTokens.timeWidthFraction,
                        ),
                        child: _time(t),
                      ),
                    ],
                  ),
                ),
                if (widget.conversation) ...[
                  const SizedBox(height: NoticeTokens.titleGap),
                  Text.rich(
                    key: const ValueKey('notice-preview'),
                    TextSpan(
                      children: [
                        if (widget.isOutgoing)
                          TextSpan(
                            text: '你：',
                            style: TextStyle(color: t.text3),
                          ),
                        TextSpan(text: action),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NoticeTokens.preview.copyWith(
                      color: _unread ? t.text : t.text2,
                    ),
                  ),
                ] else ...[
                  if (hasScore || titleText != null) ...[
                    const SizedBox(height: NoticeTokens.titleGap),
                    if (hasScore)
                      _ratingDetail(t, score, titleText)
                    else
                      _noticeTitle(t, titleText!),
                  ],
                  if (reply != null && reply.trim().isNotEmpty) ...[
                    const SizedBox(height: NoticeTokens.quoteGap),
                    Container(
                      key: const ValueKey('notice-quote'),
                      width: double.infinity,
                      padding: NoticeTokens.quotePadding,
                      decoration: BoxDecoration(
                        color: t.fill,
                        borderRadius: BorderRadius.circular(
                          NoticeTokens.quoteRadius,
                        ),
                      ),
                      child: Text(
                        reply,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NoticeTokens.preview.copyWith(color: t.text2),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return MergeSemantics(
      child: Semantics(
        label: _unread ? '未读' : null,
        child: widget.onTap == null
            ? content
            : PressHighlight(
                onTap: _open,
                borderRadius: BorderRadius.circular(NoticeTokens.rowRadius),
                child: content,
              ),
      ),
    );
  }

  static final _ratingActionWhitespace = RegExp(r'[\s\u3000]+');

  Widget _noticeTitle(AppTokens t, String title) => Text(
    title,
    key: const ValueKey('notice-title'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: NoticeTokens.preview.copyWith(color: t.text2),
  );

  Widget _ratingDetail(AppTokens t, String score, String? title) =>
      LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: title == null
                    ? constraints.maxWidth
                    : (constraints.maxWidth -
                              NoticeTokens.scoreTitleGap -
                              MediaQuery.textScalerOf(
                                context,
                              ).scale(NoticeTokens.preview.fontSize!))
                          .clamp(0.0, constraints.maxWidth),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  score,
                  key: const ValueKey('notice-score'),
                  maxLines: 1,
                  softWrap: false,
                  style: NoticeTokens.preview.copyWith(
                    color: t.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (title != null) ...[
              const SizedBox(width: NoticeTokens.scoreTitleGap),
              Expanded(child: _noticeTitle(t, title)),
            ],
          ],
        ),
      );

  Widget _time(AppTokens t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedBuilder(
        animation: _dot,
        builder: (context, _) {
          final scale = _dot.value.clamp(0.0, 2.0);
          if (scale == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Transform.scale(
              scale: scale,
              child: DecoratedBox(
                key: NoticeRow.unreadDotKey,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: scale.clamp(0.0, 1.0)),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: NoticeTokens.dot),
              ),
            ),
          );
        },
      ),
      if (widget.time.isNotEmpty)
        Flexible(
          child: Text(
            widget.time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NoticeTokens.time.copyWith(color: t.text3),
          ),
        ),
    ],
  );

  Widget _avatar(AppTokens t) {
    final size = widget.conversation
        ? NoticeTokens.conversationAvatar
        : NoticeTokens.avatar;
    final kind = switch (widget.category) {
      'post' => (AppIcons.comments, '回复'),
      'rate' => (AppIcons.credits, '评分'),
      'pcomment' => (AppIcons.comments, '点评'),
      'at' => (null, '@'),
      'friend' => (AppIcons.person, '好友'),
      'poke' => (NoticeTokens.pokeIcon, '打招呼'),
      _ => null,
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox.square(
          key: const ValueKey('notice-avatar'),
          dimension: size,
          child: ExcludeSemantics(
            child: widget.system
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.fill,
                      borderRadius: BorderRadius.circular(
                        NoticeTokens.quoteRadius,
                      ),
                    ),
                    child: Icon(
                      AppIcons.notification,
                      size: NoticeTokens.systemIcon,
                      color: t.text2,
                    ),
                  )
                : ClipOval(child: widget.avatar),
          ),
        ),
        if (!widget.system && !widget.conversation && kind != null)
          Positioned(
            right: NoticeTokens.kindOffset,
            bottom: NoticeTokens.kindOffset,
            child: Semantics(
              label: kind.$2,
              child: Container(
                key: const ValueKey('notice-kind'),
                width: NoticeTokens.kindFrame,
                height: NoticeTokens.kindFrame,
                decoration: BoxDecoration(
                  color: t.surface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: NoticeTokens.kind,
                  height: NoticeTokens.kind,
                  decoration: BoxDecoration(
                    color: t.fill,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: ExcludeSemantics(
                    child: kind.$1 == null
                        ? Text(
                            '@',
                            style: NoticeTokens.time.copyWith(color: t.text2),
                          )
                        : Icon(
                            kind.$1,
                            size: NoticeTokens.kindIcon,
                            color: t.text2,
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 更多评测:88×60 缩略图(只用门户给出的封面,没有就不留位)+ 眉题 + 两行标题
class ArticleRow extends StatelessWidget {
  final Widget? thumbnail;
  final String? eyebrow;
  final String title;
  final VoidCallback? onTap;

  const ArticleRow({
    super.key,
    this.thumbnail,
    this.eyebrow,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PlainRow(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        10,
        AppSpace.screen,
        0,
      ),
      child: Row(
        children: [
          if (thumbnail != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: SizedBox(width: 88, height: 60, child: thumbnail),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow?.isNotEmpty ?? false)
                  Text(
                    eyebrow!,
                    style: AppType.footnote.copyWith(color: t.text3),
                  ),
                BalancedTitle(
                  title,
                  maxLines: 2,
                  style: AppType.subhead.copyWith(
                    color: t.text,
                    fontWeight: FontWeight.w600,
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

/// 快讯:两行标题,模型里有时间才显示
class NewsRow extends StatelessWidget {
  final String title;
  final String? time;
  final VoidCallback? onTap;
  const NewsRow({super.key, required this.title, this.time, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PlainRow(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        11,
        AppSpace.screen,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: BalancedTitle(
              title,
              maxLines: 2,
              style: AppType.subhead.copyWith(color: t.text),
            ),
          ),
          if (time != null) ...[
            const SizedBox(width: 12),
            Text(time!, style: AppType.footnote.copyWith(color: t.text3)),
          ],
        ],
      ),
    );
  }
}
