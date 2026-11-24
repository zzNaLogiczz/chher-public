/// Source-backed message counters, explicit filters and readable activity rows.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../design/display_text.dart';
import '../core/display_time.dart';
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
import '../design/list_end_tokens.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../widgets/chhers_refresh_indicator.dart';
import '../widgets/avatar_image.dart';
import '../widgets/expressive_controls.dart' show ContentFade;
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
  final _readPms =
      <(int, PmFilter, String), ({PmConversation item, int revision})>{};
  int _pmReadRevision = 0;
  int _section = 0;
  int _view = 0;
  int _pm = 0;
  String? _type;
  final _position = ValueNotifier<double>(0);
  final _mastOffset = ValueNotifier<double>(0);
  final _scrolls = <int, ScrollController>{};
  final _refresh = <int, Future<void> Function()>{};
  double _collapseExtent = 0;
  double _mastOffsetBias = 0;
  ({int section, double offset})? _preview;
  MessageRepository get _repository => widget.repository ?? messageRepo;
  bool get _sharedChrome => widget.tab || widget.showTitle;

  @override
  void dispose() {
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    _mastOffset.dispose();
    _position.dispose();
    super.dispose();
  }

  ScrollController _scrollFor(int section) => _scrolls.putIfAbsent(
    section,
    () => ScrollController(
      initialScrollOffset: _sharedChrome ? _mastOffset.value : 0,
    ),
  );

  void _previewSection(int section) {
    final target = _scrolls[section];
    final mast = _mastOffset.value;
    if (mast == 0 || _preview != null) return;
    if (target == null || !target.hasClients) {
      _preview = (section: section, offset: 0);
      _scrollFor(section);
    } else if (target.offset < mast) {
      _preview = (section: section, offset: target.offset);
      target.jumpTo(mast);
    }
  }

  void _restorePreview() {
    final preview = _preview;
    _preview = null;
    if (preview == null || preview.section == _section) return;
    final scroll = _scrollFor(preview.section);
    if (scroll.hasClients) scroll.jumpTo(preview.offset);
  }

  void _select(int section) {
    if (section == _section) return;
    if (_sharedChrome) {
      final current = _scrollFor(_section);
      if (current.hasClients) current.jumpTo(current.offset);
      final target = _scrollFor(section);
      final mast = _mastOffset.value.clamp(0.0, _collapseExtent);
      final targetOffset = target.hasClients
          ? target.offset
          : target.initialScrollOffset;
      if (target.hasClients && targetOffset < mast) target.jumpTo(mast);
      if (_preview?.section == section) _preview = null;
      // A deeper saved list position can coexist with the current mast position.
      _mastOffsetBias = mast < _collapseExtent
          ? math.max(0, targetOffset - mast)
          : 0;
    }
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: chhSession,
    builder: (context, _) {
      final onLac = AppTokens.of(context).style == AppearanceStyle.cinnabar;
      final auth = chhSession.authenticationRevision;
      final pmFilter = _pm == 0 ? PmFilter.privatePm : PmFilter.announcePm;
      Widget segmented({bool compact = false}) => AppSegmented<int>(
        options: const [
          PickerOption(value: 0, label: '提醒'),
          PickerOption(value: 1, label: '私信'),
        ],
        value: _section,
        onChanged: _select,
        compact: compact,
        onLac: onLac,
        position: _position,
        messageStyle: true,
        badgeCounts: [chhSession.badges.notices, chhSession.badges.messages],
      );
      final header = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.tab) LargeTitleHeader(title: '消息', onLac: onLac),
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
      Widget page(int i, TabScrollBuilder? buildScroll) => i == 0
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
              precedingBottomPadding: (n) =>
                  NoticeTokens.rowPadding.bottom +
                  (n.replyText?.trim().isNotEmpty == true
                      ? NoticeTokens.quotePadding.bottom
                      : 0),
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
              scroll: _scrollFor(i),
              buildScroll: buildScroll,
              active: i == _section,
              onRefreshReady: (refresh) => _refresh[i] = refresh,
              compactMisty: widget.tab,
            )
          : _MessageFeed<PmConversation>(
              key: ValueKey((
                'pm-feed',
                chhSession.authenticationRevision,
                chhSession.loggedIn,
              )),
              revision: _pm,
              updateCount: pmFilter == PmFilter.privatePm
                  ? chhSession.badges.messages
                  : 0,
              groupByDate: false,
              empty: _pm == 0 ? '还没有私人消息' : '暂时没有公共消息',
              identity: (c) => c.id,
              date: (c) => c.timeRaw,
              precedingBottomPadding: (_) =>
                  NoticeTokens.conversationPadding.bottom,
              load: (page, {bool refresh = false}) => _repository.conversations(
                filter: pmFilter,
                page: page,
                refresh: refresh,
              ),
              onLoading: (page) {
                final readRevision = _pmReadRevision;
                return (result) {
                  final locallyRead = <String>{};
                  for (final item in result.items) {
                    final key = (auth, pmFilter, item.id);
                    final read = _readPms[key];
                    if (read == null) continue;
                    if (read.revision > readRevision ||
                        (item.unread &&
                            read.item.unread &&
                            read.item.preview == item.preview &&
                            read.item.timeRaw == item.timeRaw)) {
                      locallyRead.add(item.id);
                      if (item.unread) {
                        _readPms[key] = (item: item, revision: read.revision);
                      }
                    } else {
                      _readPms.remove(key);
                    }
                  }
                  if (pmFilter != PmFilter.privatePm ||
                      chhSession.authenticationRevision != auth ||
                      !chhSession.loggedIn ||
                      chhSession.currentExpired ||
                      chhSession.accountOperationInProgress) {
                    return null;
                  }
                  chhSession.updatePmList(
                    result,
                    page: page,
                    locallyRead: locallyRead,
                  );
                  return chhSession.badges.messages;
                };
              },
              itemBuilder: (c) => _ConversationRow(
                key: ValueKey(c.id),
                conversation: c,
                repository: _repository,
                read: _readPms.containsKey((auth, pmFilter, c.id)),
                onRead: () {
                  setState(() {
                    _readPms[(auth, pmFilter, c.id)] = (
                      item: c,
                      revision: ++_pmReadRevision,
                    );
                  });
                  if (pmFilter == PmFilter.privatePm) {
                    chhSession.markPmRead(c.id);
                  }
                },
              ),
              filter: PmFilterLabel(
                value: _pm,
                onChanged: (value) {
                  if (value == _pm) return;
                  final scroll = _scrolls[1]!;
                  if (scroll.hasClients) scroll.jumpTo(0);
                  setState(() => _pm = value);
                },
              ),
              scroll: _scrollFor(i),
              buildScroll: buildScroll,
              active: i == _section,
              onRefreshReady: (refresh) => _refresh[i] = refresh,
              compactMisty: widget.tab,
            );
      Widget pager([TabScrollBuilder? buildScroll]) => MessagePager(
        value: _section,
        position: _position,
        onChanged: _select,
        onPreview: _sharedChrome ? _previewSection : null,
        onSettled: _sharedChrome ? _restorePreview : null,
        itemBuilder: (context, i) => page(i, buildScroll),
      );
      final unread = chhSession.badges.total;
      return _sharedChrome
          ? LacquerTabScaffold(
              mistyCompact: widget.tab,
              contentOnPaper: true,
              title: '消息',
              slivers: const [],
              eyebrow: widget.tab
                  ? (unread > 0 ? '$unread 条未读' : '全部已读')
                  : null,
              controller: _scrollFor(_section),
              scrollOffset: _mastOffset,
              mastOffsetForScroll: (pixels) =>
                  (pixels - _mastOffsetBias).clamp(0.0, _collapseExtent),
              header: widget.tab ? null : header,
              headerBody: widget.tab ? header : null,
              fadeHeaderBody: widget.tab,
              compactTitle: Center(child: segmented(compact: true)),
              actions: widget.showTitle
                  ? [
                      ChromeButton(
                        icon: AppIcons.back,
                        tooltip: '返回',
                        onLac: onLac,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ]
                  : const [],
              onRefresh: () async => _refresh[_section]?.call(),
              scrollBody: (buildScroll, collapseExtent) {
                _collapseExtent = collapseExtent;
                return pager(buildScroll);
              },
            )
          : Column(
              children: [
                Padding(padding: const EdgeInsets.all(16), child: segmented()),
                Expanded(child: pager()),
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
      time: formatDisplayTime(raw: notice.occurredAtText),
      text:
          notice.action ??
          notice.summary.replaceFirst(notice.actor ?? '', '').trim(),
      title: notice.title,
      replyText: notice.replyText,
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
        contextLine: formatDisplayTime(raw: notice.occurredAtText),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            4,
            AppSpace.screen,
            32,
          ),
          child: SelectableText(
            normalizeDisplayText(notice.summary),
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
  final bool read;
  final VoidCallback onRead;
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.repository,
    required this.read,
    required this.onRead,
  });
  @override
  Widget build(BuildContext context) => NoticeRow(
    avatar: AvatarImage(
      url: conversation.avatarUrl,
      name: conversation.peer,
      size: 48,
    ),
    name: conversation.peer,
    time: formatDisplayTime(raw: conversation.timeRaw),
    conversation: true,
    isOutgoing: conversation.isOutgoing,
    unread: conversation.unread && !read,
    text: conversation.preview,
    onTap: () {
      onRead();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PmThreadPage(conversation: conversation, repository: repository),
        ),
      );
    },
  );
}

/// Serial pagination keeps source next URLs and leaves existing rows on failure.
class _MessageFeed<T> extends StatefulWidget {
  const _MessageFeed({
    super.key,
    required this.load,
    this.next,
    required this.itemBuilder,
    required this.identity,
    required this.date,
    required this.precedingBottomPadding,
    required this.empty,
    required this.filter,
    required this.scroll,
    required this.active,
    required this.onRefreshReady,
    required this.revision,
    this.buildScroll,
    this.compactMisty = false,
    this.groupByDate = true,
    this.updateCount = 0,
    this.onLoading,
  });
  final Future<Paged<T>> Function(int page, {bool refresh}) load;
  final Future<Paged<T>> Function(Paged<T>)? next;
  final Widget Function(T) itemBuilder;
  final String Function(T) identity;
  final String Function(T) date;
  final double Function(T) precedingBottomPadding;
  final String empty;
  final Widget filter;
  final ScrollController scroll;
  final bool active;
  final ValueChanged<Future<void> Function()> onRefreshReady;
  final int? Function(Paged<T> result) Function(int page)? onLoading;
  final TabScrollBuilder? buildScroll;
  final Object revision;
  final bool groupByDate;
  final bool compactMisty;
  final int updateCount;
  @override
  State<_MessageFeed<T>> createState() => _MessageFeedState<T>();
}

class _MessageFeedState<T> extends State<_MessageFeed<T>>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _arrival = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: 1,
  );
  final _items = <T>[];
  ScrollController get _scroll => widget.scroll;
  final _inserted = <String>{};
  Paged<T>? _last, _pending;
  bool _busy = false, _started = false, _hasNext = false, _failedMore = false;
  bool _refreshQueued = false;
  int? _loadedUpdateCount;
  Object? _error;
  int _generation = 0;
  bool get _atTop =>
      !_scroll.hasClients ||
      (_scroll.offset <= .5 && !_scroll.position.isScrollingNotifier.value);

  @override
  void initState() {
    super.initState();
    _arrival;
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    widget.onRefreshReady(() => _fetch(refresh: true));
    _fetch(refresh: true);
  }

  @override
  void didUpdateWidget(covariant _MessageFeed<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousCount = _loadedUpdateCount ?? oldWidget.updateCount;
    _loadedUpdateCount = null;
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
      }
      _fetch(refresh: true, revealOnArrival: true);
    } else {
      if (widget.updateCount > previousCount) _refreshQueued = true;
      unawaited(_refreshWhenVisible());
    }
  }

  Future<void> _refreshWhenVisible() async {
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_refreshQueued ||
        _busy ||
        !widget.active ||
        !visible ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    await _fetch(refresh: true, deferWhileReading: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_refreshWhenVisible());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshWhenVisible());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _arrival.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_pending != null && _atTop) {
      final result = _pending!;
      _pending = null;
      setState(() => _apply(result, false));
    }
    if (widget.active &&
        _scroll.hasClients &&
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
      final now = DateTime.now();
      final dates = {
        for (final item in _items)
          widget.identity(item): ChhUrls.parseTime(widget.date(item), now: now),
      };
      _items.sort((a, b) {
        final at = dates[widget.identity(a)], bt = dates[widget.identity(b)];
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
    bool revealOnArrival = false,
  }) async {
    if (_busy) return;
    if (more && !_hasNext) return;
    if (!more) _refreshQueued = false;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final previous = _last;
      final page = more ? (previous?.page.current ?? 0) + 1 : 1;
      final onLoaded = widget.onLoading?.call(page);
      final result =
          more &&
              previous != null &&
              previous.nextUrl != null &&
              widget.next != null
          ? await widget.next!(previous)
          : await widget.load(page, refresh: refresh);
      if (!mounted || generation != _generation) return;
      _loadedUpdateCount = onLoaded?.call(result);
      setState(() {
        if (deferWhileReading &&
            !widget.groupByDate &&
            !more &&
            _started &&
            !_atTop) {
          _pending = result;
        } else {
          _apply(result, more);
          if (!more && !deferWhileReading && (!_started || revealOnArrival)) {
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
        await _refreshWhenVisible();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slivers = [
      ..._slivers(context),
      SliverToBoxAdapter(
        child: SizedBox(
          height:
              ListEndTokens.navigationGap +
              MediaQuery.paddingOf(context).bottom,
        ),
      ),
    ];
    final body =
        widget.buildScroll?.call(
          _scroll,
          slivers,
          active: widget.active,
          // The label owns the gap so its 44dp filter target can extend into
          // the whitespace while the visible date stays 20dp below the tabs.
          mistyContentGap:
              _items.isEmpty &&
                  _error is PageMessage &&
                  (_error as PageMessage).kind == PageMessageKind.loginRequired
              ? TabChromeTokens.mistyContentGap
              : 0,
        ) ??
        ChhersRefreshIndicator(
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
    final now = DateTime.now();
    for (final item in _items) {
      final day = widget.groupByDate
          ? formatDisplayTime(
              raw: widget.date(item),
              style: DisplayTimeStyle.section,
              now: now,
            )
          : null;
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
            itemCount: group.rows.length + (index == groups.length - 1 ? 1 : 0),
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final index = group.rows.indexWhere(
                (row) => widget.identity(row) == key.value,
              );
              return index < 0 ? null : index;
            },
            itemBuilder: (_, i) {
              if (i == group.rows.length) return _footer(error);
              final item = group.rows[i], id = widget.identity(group.rows[i]);
              return _NewMessageRow(
                key: ValueKey(id),
                reveal: _inserted.remove(id),
                child: ContentFade(
                  opacity: _arrival,
                  background: AppTokens.of(context).surface,
                  child: widget.itemBuilder(item),
                ),
              );
            },
          ),
        ),
      ],
    ];
  }

  Widget _footer(Object? error) {
    final preceding = widget.precedingBottomPadding(_items.last);
    const following = MessageListTokens.cardPadding;
    if (error == null && (_busy || !_hasNext)) {
      return ListFooter(
        loading: _busy,
        exhausted: !_hasNext,
        endLabel: '已显示全部消息',
        precedingBottomPadding: preceding,
        followingBottomPadding: following,
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        top: ListEndTokens.markerPadding(preceding),
        bottom: ListEndTokens.markerPadding(following),
      ),
      child: Center(
        child: error != null
            ? AppButton(
                label: _failedMore ? '未能加载更多，轻点重试' : '未能刷新，轻点重试',
                variant: AppButtonVariant.plain,
                icon: AppIcons.refresh,
                onPressed: () =>
                    _fetch(more: _failedMore, refresh: !_failedMore),
              )
            : AppButton(
                label: '加载更多',
                variant: AppButtonVariant.plain,
                onPressed: () => _fetch(more: true),
              ),
      ),
    );
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
