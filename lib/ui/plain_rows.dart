/// 内容页的平铺行:白底、左右 20、按下整行变灰、分隔线从文字起点开始(规格 §6.7)
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
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

/// 帖子行:眉题(版块或分类)→ 标题 → 元信息。元信息只用间距分开,不用间隔号和图标。
class ThreadRow extends StatelessWidget {
  final ThreadSummary thread;
  final String? eyebrow;

  /// 可定位的回复摘要等补充文字
  final String? excerpt;
  final VoidCallback? onTap;

  /// 登录墙:元信息后追加"需登录"与登录按钮
  final bool locked;
  final VoidCallback? onLogin;

  const ThreadRow({
    super.key,
    required this.thread,
    this.eyebrow,
    this.excerpt,
    this.onTap,
    this.locked = false,
    this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final label = eyebrow ?? thread.forumName ?? thread.typeName;
    final when = displayTime(thread);
    final meta = <String>[
      if (thread.author.isNotEmpty) thread.author,
      ?when,
      if (!locked && thread.replies > 0) '${thread.replies} 回复',
      if (thread.hasImages) '含图',
    ];
    final metaStyle = AppType.footnote.copyWith(color: t.text3);
    final sticky =
        thread.sticky &&
        !(PlainRowScope.maybeOf(context)?.impliesSticky ?? false);
    return PlainRow(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sticky || (label?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 8,
                children: [
                  if (sticky)
                    Text('置顶', style: AppType.caption.copyWith(color: t.warn)),
                  if (label?.isNotEmpty ?? false)
                    Text(
                      label!,
                      style: AppType.caption.copyWith(color: t.accent),
                    ),
                ],
              ),
            ),
          Text(
            thread.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.headline.copyWith(color: t.text),
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
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [for (final item in meta) Text(item, style: metaStyle)],
            ),
          ],
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Text('需登录', style: metaStyle.copyWith(color: t.warn)),
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
    );
  }

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
  final bool expanded;
  final VoidCallback onToggle;

  /// 卡片内第 i 条置顶帖;只在展开或动画进行中构建
  final IndexedWidgetBuilder itemBuilder;

  const PinnedGroupRow({
    super.key,
    required this.count,
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
        6,
        AppSpace.screen,
        4,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: t.fill,
          shape: appShape(AppRadii.md),
        ),
        child: AppClip(
          radius: AppRadii.md,
          child: Column(
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.rowInset,
            vertical: 10,
          ),
          child: Row(
            children: [
              Text(
                '置顶帖',
                style: AppType.subhead.copyWith(
                  color: t.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$count 条',
                style: AppType.footnote.copyWith(color: t.text3),
              ),
              const SizedBox(width: 4),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.rowInset),
        child: Divider(
          height: AppSpace.hairline,
          thickness: AppSpace.hairline,
          color: t.separator,
        ),
      ),
      for (var i = 0; i < count; i++)
        PlainRowScope(
          inset: AppSpace.rowInset,
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

  const SearchResultRow({
    super.key,
    required this.title,
    required this.query,
    this.snippet,
    required this.meta,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PlainRow(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            highlight(title, query, t.accent),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.headline.copyWith(color: t.text),
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
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final item in meta)
                  Text(item, style: AppType.footnote.copyWith(color: t.text3)),
              ],
            ),
          ],
        ],
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
