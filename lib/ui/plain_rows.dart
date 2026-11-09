/// 内容页的平铺行:白底、左右 20、按下整行变灰、分隔线从文字起点开始(规格 §6.7)
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/motion.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final scope = PlainRowScope.maybeOf(context);
    final separator = this.separator && (scope?.separator ?? true);
    final content = Padding(
      padding: scope == null
          ? padding
          : EdgeInsets.fromLTRB(scope.inset, 14, scope.inset, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: separator
              ? Border(
                  bottom: BorderSide(
                    color: t.separator,
                    width: AppSpace.hairline,
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
    return onTap == null
        ? content
        : PressHighlight(onTap: onTap, child: content);
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
    final duration = reduced ? Duration.zero : AppMotion.revealDuration;
    return PlainRow(
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
                    curve: Curves.easeOut,
                    builder: (context, color, _) => Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.headline.copyWith(color: color),
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
            if (!locked) ...[const SizedBox(width: 12), _count(t, duration)],
          ],
        ),
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
            TextSpan(
              text: '$label  ',
              style: style.copyWith(
                color: t.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
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
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            constraints: const BoxConstraints(
              minWidth: 30,
              minHeight: 22,
              maxWidth: 44,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: fresh != null
                  ? t.accent
                  : seen
                  ? t.fill3
                  : thread.replies == 0
                  ? Colors.transparent
                  : t.fill,
              borderRadius: BorderRadius.circular(22),
            ),
            child: AnimatedDefaultTextStyle(
              duration: duration,
              curve: Curves.easeOut,
              style: AppType.footnote.copyWith(
                fontWeight: FontWeight.w600,
                color: fresh != null
                    ? t.onAccent
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

  static final _turn = AppMotion.curveOf(AppMotion.select);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        2,
        AppSpace.screen,
        6,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: t.fill3,
          shape: appShape(AppRadii.sm),
        ),
        child: AppClip(
          radius: AppRadii.sm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(t, reduced),
              // 高度只作用于卡片内新出现的置顶帖;灰色底随之伸缩,不另画一层
              SingleMotionBuilder(
                value: expanded ? 1 : 0,
                active: !reduced,
                motion: AppMotion.of(context, AppMotion.reveal),
                child: _rows(t),
                builder: (context, progress, rows) {
                  final p = progress.clamp(0.0, 1.0);
                  if (p == 0) return const SizedBox.shrink();
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: p,
                      child: Opacity(opacity: p, child: rows),
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
    semanticLabel: '置顶帖 $count 条',
    child: Semantics(
      expanded: expanded,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  duration: reduced ? Duration.zero : AppMotion.fade,
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
              TweenAnimationBuilder<double>(
                tween: Tween(end: expanded ? .5 : 0),
                duration: reduced ? Duration.zero : _turn.duration,
                curve: _turn,
                builder: (_, turns, child) => RotationTransition(
                  turns: AlwaysStoppedAnimation(turns),
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
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Divider(
          height: AppSpace.hairline,
          thickness: AppSpace.hairline,
          color: t.separator,
        ),
      ),
      for (var i = 0; i < count; i++)
        PlainRowScope(
          inset: 12,
          separator: i < count - 1,
          impliesSticky: true,
          child: Builder(builder: (context) => itemBuilder(context, i)),
        ),
    ],
  );
}

/// 提醒、私信会话行:头像 44 正圆 → 名字与时间 → 两行内容;未读在头像左侧标蓝点
class NoticeRow extends StatelessWidget {
  static const unreadDotKey = ValueKey('notice-unread-dot');

  final Widget avatar;
  final String name;
  final String time;
  final String text;
  final bool unread;
  final VoidCallback? onTap;

  const NoticeRow({
    super.key,
    required this.avatar,
    required this.name,
    required this.time,
    required this.text,
    this.unread = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            12,
            AppSpace.screen,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(child: SizedBox.square(dimension: 44, child: avatar)),
              const SizedBox(width: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: t.separator,
                        width: AppSpace.hairline,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.callout.copyWith(
                                  color: t.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              time,
                              style: AppType.footnote.copyWith(color: t.text3),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.subhead.copyWith(color: t.text2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (unread)
          Positioned(
            left: 7,
            top: 30,
            child: DecoratedBox(
              key: unreadDotKey,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 8),
            ),
          ),
      ],
    );
    return onTap == null
        ? content
        : PressHighlight(onTap: onTap, semanticLabel: name, child: content);
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
