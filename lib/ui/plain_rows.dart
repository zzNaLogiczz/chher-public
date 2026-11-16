/// 内容页的平铺行：按下变底色，仅以留白分隔。
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/forum_tokens.dart';
import '../core/chh_urls.dart';
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
import 'chrome_button.dart' show BadgeAppearance;

class PlainRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool separator;
  final BorderRadius? borderRadius;

  const PlainRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.screen,
      14,
      AppSpace.screen,
      0,
    ),
    this.separator = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final scope = PlainRowScope.maybeOf(context);
    final content = Padding(
      padding: scope == null
          ? padding
          : EdgeInsets.fromLTRB(scope.inset, 14, scope.inset, 0),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SizedBox(width: double.infinity, child: child),
      ),
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

/// 读屏标签:颜色不能是唯一线索,已看与新回复数都要说出来
String? readSemanticsLabel(ThreadReadState state) => switch (state) {
  ThreadReadSeen() => '已看',
  ThreadReadNewReplies(:final count) => '有 $count 条新回复',
  ThreadReadUnseen() => null,
};

/// 元信息行里追加的一项 `+N 新回复`,与其余项同为 Wrap 里的一个 Text,不加分隔符
Widget newRepliesText(AppTokens t, ThreadReadNewReplies state) => Text(
  '+${state.count} 新回复',
  style: AppType.footnote.copyWith(color: t.accent),
);

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

/// 方案 A：两行标题、元信息与独立回复数列。
class ThreadRow extends StatelessWidget {
  final ThreadSummary thread;
  final String? eyebrow;
  final String? timeLabel;
  final bool showCategory;
  final bool forumStyle;

  /// 可定位的回复摘要等补充文字
  final String? excerpt;
  final VoidCallback? onTap;

  /// 登录墙:元信息后追加"需登录"与登录按钮
  final bool locked;
  final VoidCallback? onLogin;

  /// 已看/新回复的呈现;已看只降标题色,不加文字不加行高
  final ThreadReadState readState;

  const ThreadRow({
    super.key,
    required this.thread,
    this.eyebrow,
    this.timeLabel,
    this.showCategory = true,
    this.forumStyle = false,
    this.excerpt,
    this.onTap,
    this.locked = false,
    this.onLogin,
    this.readState = const ThreadReadUnseen(),
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final when = timeLabel ?? displayTime(thread);
    final label = showCategory
        ? eyebrow ?? thread.forumName ?? thread.typeName
        : null;
    final sticky =
        thread.sticky &&
        !(PlainRowScope.maybeOf(context)?.impliesSticky ?? false);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? AppMotion.reducedFade : AppMotion.fade;
    return PlainRow(
      separator: !forumStyle,
      borderRadius: forumStyle
          ? BorderRadius.circular(ForumTokens.rowRadius)
          : null,
      onTap: onTap,
      child: Semantics(
        label: readSemanticsLabel(readState),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: readTitleColor(t, readState)),
                    duration: duration,
                    builder: (context, color, _) => Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (forumStyle ? ForumTokens.title : AppType.headline)
                          .copyWith(color: color),
                    ),
                  ),
                  if ((excerpt ?? thread.snippet) case final String text) ...[
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.subhead.copyWith(color: t.text2),
                    ),
                  ],
                  const SizedBox(height: 5),
                  if (forumStyle)
                    _forumMetadata(context, t, label, when, sticky, duration)
                  else
                    _metadata(context, t, label, when, sticky),
                  if (locked)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
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
                ],
              ),
            ),
            if (!locked) ...[
              const SizedBox(width: 12),
              if (forumStyle)
                _ForumReplyCount(thread: thread, state: readState)
              else
                _count(t, duration),
            ],
          ],
        ),
      ),
    );
  }

  Widget _forumMetadata(
    BuildContext context,
    AppTokens t,
    String? label,
    String? when,
    bool sticky,
    Duration duration,
  ) {
    final uid = thread.authorUid?.trim();
    final hasUid = uid != null && RegExp(r'^\d{1,9}$').hasMatch(uid);
    final avatar = AnimatedOpacity(
      opacity: readState is ThreadReadSeen ? ForumTokens.seenAvatarOpacity : 1,
      duration: duration,
      child: AvatarImage(
        key: ValueKey('thread-avatar-${thread.tid}'),
        name: thread.author,
        // Reuse the detail avatar source and its disk cache at a bounded decode size.
        url: hasUid ? ChhUrls.avatar(uid) : null,
        size: ForumTokens.avatarSize,
        lazy: true,
      ),
    );
    final style = ForumTokens.metadata.copyWith(color: t.text3);
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .55),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    thread.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(color: t.text2),
                  ),
                ),
              ],
            ),
          ),
          if (sticky) Text('置顶', style: style.copyWith(color: t.warn)),
          if (label?.isNotEmpty == true)
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          if (when?.isNotEmpty == true)
            Text(
              when!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          if (thread.hasImages)
            Icon(AppIcons.image, size: 14, color: t.text3, semanticLabel: '含图'),
        ],
      ),
    );
  }

  Widget _metadata(
    BuildContext context,
    AppTokens t,
    String? label,
    String? when,
    bool sticky,
  ) {
    final style = AppType.footnote.copyWith(color: t.text3);
    final identity = Text.rich(
      TextSpan(
        children: [
          if (sticky)
            TextSpan(
              text: '置顶  ',
              style: style.copyWith(color: t.warn),
            ),
          if (label?.isNotEmpty ?? false)
            TextSpan(text: '$label  ', style: style),
          TextSpan(text: thread.author, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final timeAndImage = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (when?.isNotEmpty ?? false)
          Flexible(
            child: Text(
              when!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        if (thread.hasImages) ...[
          if (when?.isNotEmpty ?? false) const SizedBox(width: 8),
          Icon(AppIcons.image, size: 14, color: t.text3, semanticLabel: '含图'),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            MediaQuery.textScalerOf(context).scale(AppType.sizeFootnote) > 19 ||
            constraints.maxWidth < 200;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              if (when?.isNotEmpty == true || thread.hasImages)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: timeAndImage,
                ),
            ],
          );
        }
        return Row(
          children: [
            Flexible(child: identity),
            if (when?.isNotEmpty == true || thread.hasImages) ...[
              const SizedBox(width: 10),
              Flexible(child: timeAndImage),
            ],
          ],
        );
      },
    );
  }

  Widget _count(AppTokens t, Duration duration) {
    final fresh = readState is ThreadReadNewReplies
        ? (readState as ThreadReadNewReplies).count
        : null;
    final seen = readState is ThreadReadSeen;
    final text = fresh == null
        ? _compactCount(thread.replies)
        : '+${_compactCount(fresh)}';
    return SizedBox(
      key: ValueKey('thread-count-${thread.tid}'),
      width: 44,
      child: Align(
        alignment: Alignment.topRight,
        child: Semantics(
          label: fresh == null
              ? '${thread.replies} 回复'
              : '有 $fresh 条新回复，共 ${thread.replies} 回复',
          excludeSemantics: true,
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: Curves.easeOut,
            style: AppType.subhead.copyWith(
              fontWeight: FontWeight.w600,
              color: fresh != null
                  ? t.accent
                  : seen || thread.replies == 0
                  ? t.text3
                  : t.text2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(text, maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }

  static String _compactCount(int count) => count < 10000
      ? '$count'
      : '${(count / 10000).toStringAsFixed(count < 100000 ? 1 : 0)}万';

  /// 时间优先用解析出的结构化时间:今天只显示时分,今年显示月-日;拿不到就用站点原文
  static String? displayTime(ThreadSummary thread) {
    final at = thread.createdAt;
    if (at != null) {
      final now = DateTime.now();
      final sameYear = at.year == now.year;
      final hm =
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
      if (sameYear && at.month == now.month && at.day == now.day) return hm;
      return sameYear
          ? '${at.month}-${at.day}'
          : '${at.year}-${at.month}-${at.day}';
    }
    final raw = thread.lastPostTimeRaw;
    return (raw == null || raw.isEmpty) ? null : raw;
  }
}

class _ForumReplyCount extends StatefulWidget {
  const _ForumReplyCount({required this.thread, required this.state});
  final ThreadSummary thread;
  final ThreadReadState state;

  @override
  State<_ForumReplyCount> createState() => _ForumReplyCountState();
}

class _ForumReplyCountState extends State<_ForumReplyCount> {
  int _lastFresh = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final state = widget.state;
    final fresh = state is ThreadReadNewReplies ? state.count : null;
    if (fresh != null) _lastFresh = fresh;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? AppMotion.reducedFade
        : AppMotion.fade;
    return SizedBox(
      key: ValueKey('thread-count-${widget.thread.tid}'),
      width: ForumTokens.countWidth,
      child: Semantics(
        label: fresh == null
            ? '${widget.thread.replies} 回复'
            : '有 $fresh 条新回复，共 ${widget.thread.replies} 回复',
        excludeSemantics: true,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            AnimatedOpacity(
              opacity: fresh == null ? 1 : 0,
              duration: duration,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: state is ThreadReadSeen ? t.text3 : t.text2,
                ),
                duration: duration,
                builder: (_, color, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ThreadRow._compactCount(widget.thread.replies),
                        style: AppType.subhead.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Text('回复', style: AppType.caption.copyWith(color: t.text3)),
                  ],
                ),
              ),
            ),
            BadgeAppearance(
              visible: fresh != null,
              child: Container(
                key: ValueKey('thread-new-replies-${widget.thread.tid}'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: t.accentFill,
                  borderRadius: BorderRadius.circular(ForumTokens.badgeRadius),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '+${ThreadRow._compactCount(_lastFresh)}',
                    style: AppType.footnote.copyWith(
                      color: t.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
  late bool _emphasized = widget.unread;
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
    ).whenCompleteOrCancel(() {
      if (mounted && !_unread && _dot.value == 0 && _emphasized) {
        setState(() => _emphasized = false);
      }
    });
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
    if (_unread) _emphasized = true;
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
    final title = widget.title;
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
                Row(
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
                                      color: _emphasized ? t.text : t.text2,
                                      fontWeight: _emphasized
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  if (widget.text.isNotEmpty)
                                    const TextSpan(text: ' '),
                                  ..._action(t),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: NoticeTokens.sentence.copyWith(
                                color: t.text2,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    _time(t),
                  ],
                ),
                if (widget.conversation) ...[
                  const SizedBox(height: 3),
                  Text.rich(
                    key: const ValueKey('notice-preview'),
                    TextSpan(
                      children: [
                        if (widget.isOutgoing)
                          TextSpan(
                            text: '你：',
                            style: TextStyle(color: t.text3),
                          ),
                        TextSpan(text: widget.text),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NoticeTokens.preview.copyWith(
                      color: _unread ? t.text : t.text2,
                    ),
                  ),
                ] else if (title != null && title.isNotEmpty) ...[
                  const SizedBox(height: 8),
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
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NoticeTokens.preview.copyWith(
                        color: _emphasized ? t.text : t.text2,
                      ),
                    ),
                  ),
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

  List<InlineSpan> _action(AppTokens t) {
    final score = widget.scoreText;
    if (score == null || score.isEmpty) return [TextSpan(text: widget.text)];
    final index = widget.text.indexOf(score);
    return [
      TextSpan(text: index < 0 ? widget.text : widget.text.substring(0, index)),
      if (index < 0) const TextSpan(text: ' '),
      TextSpan(
        text: score,
        style: TextStyle(color: t.accent, fontWeight: FontWeight.w600),
      ),
      if (index >= 0)
        TextSpan(text: widget.text.substring(index + score.length)),
    ];
  }

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
        Text(widget.time, style: NoticeTokens.time.copyWith(color: t.text3)),
    ],
  );

  Widget _avatar(AppTokens t) {
    final size = widget.conversation
        ? NoticeTokens.conversationAvatar
        : NoticeTokens.avatar;
    final kind = switch (widget.category) {
      'post' => (AppIcons.reply, '回复'),
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

/// 搜索结果行:标题与摘要中命中的关键词用强调色,元信息只用间距分开
class SearchResultRow extends StatelessWidget {
  final String title;
  final String query;
  final String? snippet;
  final List<String> meta;
  final VoidCallback? onTap;

  /// 已看只降标题基础色;高亮段仍用 accent,与 text2 不同色,依旧可辨
  final ThreadReadState readState;

  const SearchResultRow({
    super.key,
    required this.title,
    required this.query,
    this.snippet,
    required this.meta,
    this.onTap,
    this.readState = const ThreadReadUnseen(),
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PlainRow(
      onTap: onTap,
      child: Semantics(
        label: readSemanticsLabel(readState),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              highlight(title, query, t.accent),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.headline.copyWith(
                color: readTitleColor(t, readState),
              ),
            ),
            if (snippet?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text.rich(
                highlight(snippet!, query, t.accent),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.subhead.copyWith(color: t.text2),
              ),
            ],
            if (meta.isNotEmpty || readState is ThreadReadNewReplies) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final item in meta)
                    Text(
                      item,
                      style: AppType.footnote.copyWith(color: t.text3),
                    ),
                  if (readState case final ThreadReadNewReplies fresh)
                    newRepliesText(t, fresh),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

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
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
