/// Source-backed message counters, explicit filters and readable activity rows.
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';
import '../ui/segmented.dart';
import '../ui/picker.dart';
import '../design/typography.dart';
import '../ui/sheet_scaffold.dart';
import '../ui/plain_rows.dart';
import '../ui/feedback.dart';

import '../core/chh_urls.dart';
import '../data/message_repository.dart';
import '../di.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../widgets/avatar_image.dart';
import '../widgets/state_view.dart';
import '../design/icons.dart';
import '../widgets/lacquer_tab_scaffold.dart';
import '../ui/nav_bar.dart';
import '../ui/chrome_button.dart';
import '../ui/message_filters.dart';
import '../ui/message_pager.dart';
import '../design/motion.dart';
import '../design/notice_tokens.dart';
import 'pm_thread_page.dart';
import 'thread_detail_page.dart';

/// Keeps the exact source redirect and post ID when opening a notification.
ThreadDetailPage? noticeThreadTarget(Notice notice) => notice.tid == null
    ? null
    : ThreadDetailPage(
        tid: notice.tid!,
        title: notice.title ?? notice.summary,
        gotoUrl: notice.targetUrl,
        focusPid: notice.pid,
        focusOpeningFeedback: const {
          'rate',
          'pcomment',
        }.contains(notice.category),
      );

class MessagesPage extends StatelessWidget {
  final MessageRepository? repository;
  const MessagesPage({super.key, this.repository});
  @override
  Widget build(BuildContext context) =>
      MessagesBody(repository: repository, showTitle: true);
}

/// 底栏"消息"用:漆面骨架(分段住进漆面,列表在纸面上)
class MessagesTabPage extends StatelessWidget {
  final MessageRepository? repository;
  const MessagesTabPage({super.key, this.repository});
  @override
  Widget build(BuildContext context) =>
      MessagesBody(repository: repository, tab: true);
}

class MessagesBody extends StatefulWidget {
  final bool showTitle;

  /// 一级页形态:分段上漆、列表进纸面;推送路由保持纸面标题行
  final bool tab;
  final MessageRepository? repository;
  const MessagesBody({
    super.key,
    this.showTitle = false,
    this.tab = false,
    this.repository,
  });
  @override
  State<MessagesBody> createState() => _MessagesBodyState();
}

class _MessagesBodyState extends State<MessagesBody> {
  final _readNotices = <String>{};
  int _section = 0;
  int _view = 0;
  int _pm = 0;
  String? _type;
  final _position = ValueNotifier<double>(0);
  MessageRepository get _repository => widget.repository ?? messageRepo;

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: chhSession,
    builder: (context, _) {
      final onLac = AppTokens.of(context).style == AppearanceStyle.cinnabar;
      Widget segmented({bool compact = false}) => AppSegmented<int>(
        options: const [
          PickerOption(value: 0, label: '提醒'),
          PickerOption(value: 1, label: '私信'),
        ],
        value: _section,
        onChanged: (i) => setState(() => _section = i),
        compact: compact,
        onLac: onLac,
        position: _position,
        messageStyle: true,
        badgeCounts: [chhSession.badges.notices, chhSession.badges.messages],
      );
      final header = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LargeTitleHeader(
            title: '消息',
            onLac: onLac,
            compact: widget.tab && !onLac,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.groupInset,
              TabChromeTokens.mistySegmentGap,
              AppSpace.groupInset,
              0,
            ),
            child: segmented(),
          ),
        ],
      );
      Widget page(int i) => i == 0
          ? _MessageFeed<Notice>(
              key: ValueKey((
                'notices-feed',
                chhSession.authenticationRevision,
                chhSession.loggedIn,
              )),
              revision: (_view, _type),
              empty: _type == null && _view == 0
                  ? '没有提醒'
                  : '没有${_type == null ? noticeViewLabels[_view] : noticeTypes(_view).firstWhere((e) => e.value == _type).label}提醒',
              identity: (n) => n.id,
              date: (n) => n.occurredAtText,
              load: (page, {bool refresh = false}) => _repository.notices(
                view: noticeViews[_view],
                type: _type,
                page: page,
                refresh: refresh,
              ),
              next: (previous) => _repository.noticesNext(previous),
              itemBuilder: (n) => _NoticeRow(
                key: ValueKey(n.id),
                notice: n,
                read: _readNotices.contains(n.id),
                onRead: () => _readNotices.add(n.id),
              ),
              filter: NoticeFilter(
                view: _view,
                type: _type,
                onChanged: (v, t) => setState(() {
                  _view = v;
                  _type = t;
                }),
              ),
              header: header,
              compact: segmented(compact: true),
              chrome: widget.tab || widget.showTitle,
              showBack: widget.showTitle,
              compactMisty: widget.tab,
            )
          : _MessageFeed<PmConversation>(
              key: ValueKey((
                'pm-feed',
                chhSession.authenticationRevision,
                chhSession.loggedIn,
              )),
              revision: _pm,
              updateCount: chhSession.badges.messages,
              groupByDate: false,
              empty: _pm == 0 ? '还没有私人消息' : '暂时没有公共消息',
              identity: (c) => c.id,
              date: (c) => c.timeRaw,
              load: (page, {bool refresh = false}) => _repository.conversations(
                filter: _pm == 0 ? PmFilter.privatePm : PmFilter.announcePm,
                page: page,
                refresh: refresh,
              ),
              itemBuilder: (c) => _ConversationRow(
                key: ValueKey(c.id),
                conversation: c,
                repository: _repository,
              ),
              filter: PmFilterLabel(
                value: _pm,
                onChanged: (i) => setState(() => _pm = i),
              ),
              header: header,
              compact: segmented(compact: true),
              chrome: widget.tab || widget.showTitle,
              showBack: widget.showTitle,
              compactMisty: widget.tab,
            );
      final pager = MessagePager(
        value: _section,
        position: _position,
        onChanged: (i) => setState(() => _section = i),
        itemBuilder: (context, i) => page(i),
      );
      return widget.tab || widget.showTitle
          ? pager
          : Column(
              children: [
                Padding(padding: const EdgeInsets.all(16), child: segmented()),
                Expanded(child: pager),
              ],
            );
    },
  );
}

class _NoticeRow extends StatelessWidget {
  final Notice notice;
  final bool read;
  final VoidCallback onRead;
  const _NoticeRow({
    super.key,
    required this.notice,
    required this.read,
    required this.onRead,
  });
  @override
  Widget build(BuildContext context) {
    return NoticeRow(
      avatar: AvatarImage(
        url: notice.avatarUrl,
        name: notice.actor ?? '',
        size: 40,
      ),
      name: notice.actor ?? '系统',
      time: _clock(notice.occurredAtText),
      text:
          notice.action ??
          notice.summary.replaceFirst(notice.actor ?? '', '').trim(),
      title: notice.title,
      scoreText: notice.score,
      category: notice.category,
      system: notice.actor == null,
      unread: notice.unread && !read,
      onTap: () {
        onRead();
        _open(context);
      },
    );
  }

  void _open(BuildContext context) {
    final target = noticeThreadTarget(notice);
    if (target != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => target));
      return;
    }
    showAppSheet<void>(
      context,
      builder: (context) => SheetScaffold(
        title: notice.actor ?? '系统提醒',
        contextLine: notice.occurredAtText,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            4,
            AppSpace.screen,
            32,
          ),
          child: SelectableText(
            notice.summary,
            style: AppType.reading.copyWith(color: AppTokens.of(context).text),
          ),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final PmConversation conversation;
  final MessageRepository repository;
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.repository,
  });
  @override
  Widget build(BuildContext context) => NoticeRow(
    avatar: AvatarImage(
      url: conversation.avatarUrl,
      name: conversation.peer,
      size: 48,
    ),
    name: conversation.peer,
    time: messagePreviewTime(conversation.timeRaw),
    conversation: true,
    isOutgoing: conversation.isOutgoing,
    unread: conversation.unread,
    text: conversation.preview,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PmThreadPage(conversation: conversation, repository: repository),
      ),
    ),
  );
}

String _day(String raw) {
  if (raw.contains('今天')) return '今天';
  if (raw.contains('昨天')) return '昨天';
  final date = ChhUrls.parseTime(raw);
  if (date == null) return '消息记录';
  final now = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.dateOnly(date);
  if (day == now) return '今天';
  if (day == now.subtract(const Duration(days: 1))) return '昨天';
  return '${date.year == now.year ? '' : '${date.year}年'}${date.month}月${date.day}日';
}

String messagePreviewTime(String raw, {DateTime? now}) {
  now ??= DateTime.now();
  if (raw.contains('昨天')) return '昨天';
  if (raw.contains('今天')) return _clock(raw);
  final date = ChhUrls.parseTime(raw);
  if (date == null) return raw;
  final day = DateUtils.dateOnly(date), today = DateUtils.dateOnly(now);
  if (day == today) return _clock(raw);
  if (day == today.subtract(const Duration(days: 1))) return '昨天';
  return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _clock(String raw) =>
    RegExp(r'\d{1,2}:\d{2}').firstMatch(raw)?.group(0) ?? raw;

/// Serial pagination keeps source next URLs and leaves existing rows on failure.
class _MessageFeed<T> extends StatefulWidget {
  const _MessageFeed({
    super.key,
    required this.load,
    this.next,
    required this.itemBuilder,
    required this.identity,
    required this.date,
    required this.empty,
    required this.filter,
    required this.header,
    required this.compact,
    required this.revision,
    required this.chrome,
    this.showBack = false,
    this.compactMisty = false,
    this.groupByDate = true,
    this.updateCount = 0,
  });
  final Future<Paged<T>> Function(int page, {bool refresh}) load;
  final Future<Paged<T>> Function(Paged<T>)? next;
  final Widget Function(T) itemBuilder;
  final String Function(T) identity;
  final String Function(T) date;
  final String empty;
  final Widget filter, header, compact;
  final Object revision;
  final bool chrome, showBack, groupByDate;
  final bool compactMisty;
  final int updateCount;
  @override
  State<_MessageFeed<T>> createState() => _MessageFeedState<T>();
}

class _MessageFeedState<T> extends State<_MessageFeed<T>>
    with SingleTickerProviderStateMixin {
  late final _arrival = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: 1,
  );
  final _items = <T>[];
  final _scroll = ScrollController();
  final _inserted = <String>{};
  Paged<T>? _last, _pending;
  bool _busy = false, _started = false, _hasNext = false, _failedMore = false;
  bool _refreshQueued = false;
  Object? _error;
  int _generation = 0;
  bool get _atTop =>
      !_scroll.hasClients ||
      (_scroll.offset <= .5 && !_scroll.position.isScrollingNotifier.value);

  @override
  void initState() {
    super.initState();
    _arrival;
    _scroll.addListener(_onScroll);
    _fetch(refresh: true);
  }

  @override
  void didUpdateWidget(covariant _MessageFeed<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _generation++;
      _refreshQueued = false;
      _busy = false;
      _pending = null;
      if (!widget.groupByDate) {
        _items.clear();
        _last = null;
        _started = false;
        _hasNext = false;
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
      _fetch(refresh: true);
    } else if (widget.updateCount > oldWidget.updateCount) {
      _fetch(refresh: true, deferWhileReading: true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _arrival.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_pending != null && _atTop) {
      final result = _pending!;
      _pending = null;
      setState(() => _apply(result, false));
    }
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 260 &&
        _hasNext &&
        !_busy &&
        _error == null) {
      _fetch(more: true);
    }
  }

  void _apply(Paged<T> result, bool more) {
    final previous = _last;
    final oldIds = _items.map(widget.identity).toSet();
    _inserted.clear();
    if (!more) {
      _pending = null;
      if (!widget.groupByDate && _started && _atTop) {
        _inserted.addAll(
          result.items
              .map(widget.identity)
              .where((id) => !oldIds.contains(id))
              .take(24),
        );
      }
      _items.clear();
    }
    final ids = _items.map(widget.identity).toSet();
    final fresh = result.items
        .where((e) => ids.add(widget.identity(e)))
        .toList();
    _items.addAll(fresh);
    if (!widget.groupByDate) {
      // Stable fallback when the source supplied no parseable date.
      final order = {
        for (var i = 0; i < _items.length; i++) widget.identity(_items[i]): i,
      };
      _items.sort((a, b) {
        final at = ChhUrls.parseTime(widget.date(a)),
            bt = ChhUrls.parseTime(widget.date(b));
        if (at == null && bt != null) return 1;
        if (at != null && bt == null) return -1;
        final byTime = at != null && bt != null ? bt.compareTo(at) : 0;
        return byTime != 0
            ? byTime
            : order[widget.identity(a)]!.compareTo(order[widget.identity(b)]!);
      });
    }
    _hasNext =
        result.page.hasNext &&
        (!more ||
            (fresh.isNotEmpty &&
                result.page.current > (previous?.page.current ?? 0)));
    _last = result;
  }

  Future<void> _fetch({
    bool more = false,
    bool refresh = false,
    bool deferWhileReading = false,
  }) async {
    if (_busy) {
      if (deferWhileReading) _refreshQueued = true;
      return;
    }
    if (more && !_hasNext) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final previous = _last;
      final result =
          more &&
              previous != null &&
              previous.nextUrl != null &&
              widget.next != null
          ? await widget.next!(previous)
          : await widget.load(
              more ? (previous?.page.current ?? 0) + 1 : 1,
              refresh: refresh,
            );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (deferWhileReading &&
            !widget.groupByDate &&
            !more &&
            _started &&
            !_atTop) {
          _pending = result;
        } else {
          _apply(result, more);
          if (!more && !deferWhileReading) {
            _arrival.duration = MediaQuery.disableAnimationsOf(context)
                ? AppMotion.reducedFade
                : AppMotion.fade;
            _arrival.forward(from: 0);
          }
        }
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _failedMore = more;
        if (e is PageMessage &&
            (e.kind == PageMessageKind.loginRequired ||
                e.kind == PageMessageKind.permissionDenied)) {
          _items.clear();
          _last = null;
          _hasNext = false;
          _pending = null;
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _started = true;
        });
        if (_refreshQueued) {
          _refreshQueued = false;
          await _fetch(refresh: true, deferWhileReading: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slivers = _slivers(context);
    final body = widget.chrome
        ? LacquerTabScaffold(
            mistyCompact: widget.compactMisty,
            // The label owns the gap so its 44dp filter target can extend into
            // the whitespace while the visible date stays 20dp below the tabs.
            mistyContentGap:
                _items.isEmpty &&
                    _error is PageMessage &&
                    (_error as PageMessage).kind ==
                        PageMessageKind.loginRequired
                ? TabChromeTokens.mistyContentGap
                : 0,
            contentOnPaper: true,
            title: '消息',
            controller: _scroll,
            header: widget.header,
            compactTitle: Center(child: widget.compact),
            actions: widget.showBack
                ? [
                    ChromeButton(
                      icon: AppIcons.back,
                      tooltip: '返回',
                      onLac:
                          AppTokens.of(context).style ==
                          AppearanceStyle.cinnabar,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ]
                : const [],
            onRefresh: () => _fetch(refresh: true),
            slivers: slivers,
          )
        : RefreshIndicator(
            onRefresh: () => _fetch(refresh: true),
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: slivers,
            ),
          );
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        if (_pending != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onScroll();
          });
        }
        return false;
      },
      child: body,
    );
  }

  List<Widget> _slivers(BuildContext context) {
    final error = _error;
    final login =
        error is PageMessage && error.kind == PageMessageKind.loginRequired;
    if (!_started) {
      return [
        SliverToBoxAdapter(child: SkeletonPulse(child: _MessageSkeleton())),
      ];
    }
    if (_items.isEmpty) {
      Widget child;
      if (error is PageMessage) {
        child = StateView(
          icon: login ? AppIcons.lock : AppIcons.info,
          message: login ? '登录后查看消息' : error.text,
          actionLabel: login ? '登录' : '重试',
          onAction: () async {
            if (login) await Navigator.of(context).pushNamed('/login');
            if (mounted) await _fetch(refresh: true);
          },
        );
      } else if (error != null) {
        child = StateView.error(error, onRetry: () => _fetch(refresh: true));
      } else {
        child = StateView(icon: AppIcons.notification, message: widget.empty);
      }
      return [
        if (!login) SliverToBoxAdapter(child: _label(null, first: true)),
        _card(
          SliverToBoxAdapter(
            child:
                widget.compactMisty &&
                    AppTokens.of(context).style == AppearanceStyle.misty
                ? ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: MessageListTokens.stateMinHeight,
                    ),
                    child: child,
                  )
                : SizedBox(
                    height: MessageListTokens.stateMinHeight,
                    child: child,
                  ),
          ),
        ),
      ];
    }
    final groups = <({String? day, List<T> rows})>[];
    for (final item in _items) {
      final day = widget.groupByDate ? _day(widget.date(item)) : null;
      if (groups.isEmpty || groups.last.day != day) {
        groups.add((day: day, rows: <T>[]));
      }
      groups.last.rows.add(item);
    }
    return [
      for (final (index, group) in groups.indexed) ...[
        SliverToBoxAdapter(child: _label(group.day, first: index == 0)),
        _card(
          SliverList.builder(
            itemCount: group.rows.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final index = group.rows.indexWhere(
                (row) => widget.identity(row) == key.value,
              );
              return index < 0 ? null : index;
            },
            itemBuilder: (_, i) {
              final item = group.rows[i], id = widget.identity(group.rows[i]);
              return _NewMessageRow(
                key: ValueKey(id),
                reveal: _inserted.remove(id),
                child: Stack(
                  children: [
                    widget.itemBuilder(item),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _arrival,
                          builder: (_, _) => ColoredBox(
                            color: AppTokens.of(
                              context,
                            ).surface.withValues(alpha: 1 - _arrival.value),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Center(
            child: error != null
                ? AppButton(
                    label: _failedMore ? '未能加载更多，轻点重试' : '未能刷新，轻点重试',
                    variant: AppButtonVariant.plain,
                    icon: AppIcons.refresh,
                    onPressed: () =>
                        _fetch(more: _failedMore, refresh: !_failedMore),
                  )
                : _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : _hasNext
                ? AppButton(
                    label: '加载更多',
                    variant: AppButtonVariant.plain,
                    onPressed: () => _fetch(more: true),
                  )
                : Text(
                    '已显示全部消息',
                    style: AppType.footnote.copyWith(
                      color: AppTokens.of(context).text3,
                    ),
                  ),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 120)),
    ];
  }

  Widget _card(Widget sliver) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: MessageListTokens.inset),
    sliver: DecoratedSliver(
      decoration: BoxDecoration(
        color: AppTokens.of(context).surface,
        borderRadius: BorderRadius.circular(MessageListTokens.cardRadius),
        boxShadow: MessageListTokens.cardShadow(AppTokens.of(context)),
      ),
      sliver: SliverPadding(
        padding: const EdgeInsets.all(MessageListTokens.cardPadding),
        sliver: sliver,
      ),
    ),
  );

  Widget _label(String? day, {required bool first}) => Padding(
    key: first ? const ValueKey('message-filter-row') : null,
    padding:
        first &&
            widget.compactMisty &&
            AppTokens.of(context).style == AppearanceStyle.misty
        ? MessageListTokens.labelPadding.copyWith(
            top:
                TabChromeTokens.mistyContentGap -
                ((MessageListTokens.labelHeight -
                            MediaQuery.textScalerOf(
                                  context,
                                ).scale(AppType.sizeFootnote) *
                                AppType.footnote.height!)
                        .clamp(0.0, MessageListTokens.labelHeight) /
                    2),
          )
        : MessageListTokens.labelPadding,
    child: Row(
      children: [
        if (day != null)
          Expanded(
            child: Text(
              day,
              style: AppType.footnote.copyWith(
                color: AppTokens.of(context).text3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (first) widget.filter,
      ],
    ),
  );
}

class _NewMessageRow extends StatefulWidget {
  const _NewMessageRow({super.key, required this.reveal, required this.child});
  final bool reveal;
  final Widget child;
  @override
  State<_NewMessageRow> createState() => _NewMessageRowState();
}

class _NewMessageRowState extends State<_NewMessageRow>
    with SingleTickerProviderStateMixin {
  late final _progress = AnimationController.unbounded(vsync: this, value: 1);
  @override
  void initState() {
    super.initState();
    if (widget.reveal) _progress.value = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_progress.value == 0) {
      AppMotion.settle(
        _progress,
        target: 1,
        motion: AppMotion.reveal,
        reduced: MediaQuery.disableAnimationsOf(context),
      );
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    child: widget.child,
    builder: (_, child) => ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: _progress.value.clamp(0.0, 1.0),
        child: child,
      ),
    ),
  );
}

class _MessageSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      key: const ValueKey('message-skeleton-card'),
      margin: EdgeInsets.fromLTRB(
        MessageListTokens.inset,
        MessageListTokens.labelPadding.vertical + MessageListTokens.labelHeight,
        MessageListTokens.inset,
        0,
      ),
      padding: const EdgeInsets.all(MessageListTokens.cardPadding),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(MessageListTokens.cardRadius),
      ),
      child: Column(
        children: List.generate(
          3,
          (i) => Padding(
            padding: NoticeTokens.rowPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: ValueKey('message-skeleton-avatar-$i'),
                  width: NoticeTokens.avatar,
                  height: NoticeTokens.avatar,
                  decoration: BoxDecoration(
                    color: t.fill,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 14, width: 150, color: t.fill),
                      const SizedBox(height: 10),
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: t.fill,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                      ),
                    ],
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
