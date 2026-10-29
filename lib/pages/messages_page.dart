/// Source-backed message counters, explicit filters and readable activity rows.
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';
import '../ui/segmented.dart';
import '../ui/picker.dart';
import '../design/typography.dart';
import '../ui/sheet_scaffold.dart';
import '../ui/plain_rows.dart';

import '../core/chh_urls.dart';
import '../data/message_repository.dart';
import '../di.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../widgets/net_image.dart';
import '../widgets/state_view.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/large_title_scaffold.dart';
import 'pm_thread_page.dart';
import 'thread_detail_page.dart';

/// Keeps the exact source redirect and post ID when opening a notification.
ThreadDetailPage? noticeThreadTarget(Notice notice) => notice.tid == null
    ? null
    : ThreadDetailPage(
        tid: notice.tid!,
        title: notice.summary,
        gotoUrl: notice.targetUrl,
        focusPid: notice.pid,
      );

class MessagesPage extends StatelessWidget {
  final MessageRepository? repository;
  const MessagesPage({super.key, this.repository});
  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '消息',
    body: MessagesBody(repository: repository),
  );
}

class MessagesBody extends StatefulWidget {
  final bool showTitle;
  final MessageRepository? repository;
  const MessagesBody({super.key, this.showTitle = false, this.repository});
  @override
  State<MessagesBody> createState() => _MessagesBodyState();
}

class _MessagesBodyState extends State<MessagesBody> {
  int _section = 0;

  /// 已经打开过的分段;没打开过的不创建列表,避免进页面就多请求一次
  final _visited = <int>{0};
  int _view = 0;
  int _pm = 0;
  String? _type;
  static const _views = [
    NoticeView.all,
    NoticeView.mypost,
    NoticeView.interactive,
    NoticeView.system,
    NoticeView.app,
  ];
  static const _labels = ['全部', '我的帖子', '互动', '系统', '应用'];
  MessageRepository get _repository => widget.repository ?? messageRepo;

  List<({String label, String? value})> get _types =>
      _views[_view] == NoticeView.mypost
      ? [
          (label: '全部类型', value: null),
          (label: '回复', value: 'post'),
          (label: '评分', value: 'rate'),
          (label: '点评', value: 'pcomment'),
          (label: '提到我', value: 'at'),
          (label: '活动', value: 'activity'),
          (label: '悬赏', value: 'reward'),
          (label: '商品', value: 'goods'),
        ]
      : _views[_view] == NoticeView.interactive
      ? [
          (label: '全部类型', value: null),
          (label: '打招呼', value: 'poke'),
          (label: '好友', value: 'friend'),
          (label: '留言', value: 'wall'),
          (label: '评论', value: 'comment'),
          (label: '互动', value: 'click'),
          (label: '分享', value: 'sharenotice'),
        ]
      : [(label: '全部类型', value: null)];

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      children: [
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 8),
            child: Row(
              children: [
                BackButton(onPressed: () => Navigator.of(context).maybePop()),
                Text(
                  '消息',
                  style: TextStyle(
                    fontSize: AppType.sizeTitle2,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ],
            ),
          ),
        AnimatedBuilder(
          animation: chhSession,
          builder: (context, _) {
            final counts = [
              chhSession.badges.notices,
              chhSession.badges.messages,
            ];
            String label(int i) {
              final name = i == 0 ? '提醒' : '私信';
              final n = counts[i];
              return n > 0 ? '$name ${n > 99 ? '99+' : n}' : name;
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen,
                4,
                AppSpace.screen,
                6,
              ),
              child: AppSegmented<int>(
                fallbackTitle: '消息',
                options: [
                  PickerOption(value: 0, label: label(0)),
                  PickerOption(value: 1, label: label(1)),
                ],
                value: _section,
                onChanged: (i) => setState(() {
                  _section = i;
                  _visited.add(i);
                }),
              ),
            );
          },
        ),
        // 两个分段常驻:切回来是原来的列表,不重新请求也不再淡入;
        // 私信列表第一次切过去才创建,不在前台的分段停掉动画计时
        Expanded(
          child: IndexedStack(
            index: _section,
            children: [
              TickerMode(
                enabled: _section == 0,
                child: _MessageFeed<Notice>(
                  key: ValueKey('notice-$_view-$_type'),
                  empty: '暂时没有提醒',
                  identity: (n) => n.id,
                  date: (n) => n.occurredAtText,
                  load: (page, {bool refresh = false}) => _repository.notices(
                    view: _views[_view],
                    type: _type,
                    page: page,
                    refresh: refresh,
                  ),
                  next: (previous) => _repository.noticesNext(previous),
                  itemBuilder: (n) => _NoticeRow(notice: n),
                  filter: _noticeFilter(),
                ),
              ),
              TickerMode(
                enabled: _section == 1,
                child: _visited.contains(1)
                    ? _MessageFeed<PmConversation>(
                        key: ValueKey('pm-$_pm'),
                        empty: _pm == 0 ? '还没有私人消息' : '暂时没有公共消息',
                        identity: (c) => c.id,
                        date: (c) => c.timeRaw,
                        load: (page, {bool refresh = false}) =>
                            _repository.conversations(
                              filter: _pm == 0
                                  ? PmFilter.privatePm
                                  : PmFilter.announcePm,
                              page: page,
                              refresh: refresh,
                            ),
                        itemBuilder: (c) => _ConversationRow(
                          conversation: c,
                          repository: _repository,
                          announcement: _pm == 1,
                        ),
                        filter: PickerButton<int>(
                          sheetTitle: '私信类型',
                          options: const [
                            PickerOption(value: 0, label: '私人消息'),
                            PickerOption(value: 1, label: '公共消息'),
                          ],
                          value: _pm,
                          onChanged: (i) => setState(() => _pm = i),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 提醒的分类与子类型:放在第一个日期行右侧,而不是横向铺开
  Widget _noticeFilter() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_types.length > 1) ...[
        PickerButton<String?>(
          sheetTitle: '提醒子类型',
          options: [
            for (final type in _types)
              PickerOption(value: type.value, label: type.label),
          ],
          value: _type,
          onChanged: (value) => setState(() => _type = value),
        ),
        const SizedBox(width: 12),
      ],
      PickerButton<int>(
        sheetTitle: '提醒类型',
        options: [
          for (var i = 0; i < _labels.length; i++)
            PickerOption(value: i, label: _labels[i]),
        ],
        value: _view,
        onChanged: (i) => setState(() {
          _view = i;
          _type = null;
        }),
      ),
    ],
  );
}

class _NoticeRow extends StatelessWidget {
  final Notice notice;
  const _NoticeRow({required this.notice});
  static const labels = {
    'post': '回复',
    'rate': '评分',
    'pcomment': '点评',
    'at': '提到我',
    'system': '系统',
    'friend': '好友',
    'comment': '评论',
    'poke': '打招呼',
    'wall': '留言',
  };
  @override
  Widget build(BuildContext context) {
    final kind = labels[notice.category] ?? '提醒';
    return NoticeRow(
      avatar: _MessageAvatar(
        url: notice.avatarUrl,
        label: notice.actor ?? kind,
        icon: AppIcons.notification,
      ),
      name: notice.actor ?? '系统提醒',
      time: _clock(notice.occurredAtText),
      text: notice.summary,
      onTap: () => _open(context),
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
  final bool announcement;
  const _ConversationRow({
    required this.conversation,
    required this.repository,
    required this.announcement,
  });
  @override
  Widget build(BuildContext context) => NoticeRow(
    avatar: _MessageAvatar(
      url: conversation.avatarUrl,
      label: conversation.peer,
      icon: announcement ? AppIcons.notification : AppIcons.person,
    ),
    name: conversation.peer,
    time: _clock(conversation.timeRaw),
    text: conversation.preview,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PmThreadPage(conversation: conversation, repository: repository),
      ),
    ),
  );
}

class _MessageAvatar extends StatelessWidget {
  final String? url;
  final String label;
  final IconData icon;
  const _MessageAvatar({this.url, required this.label, required this.icon});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return url != null
        ? NetImage(url: url!)
        : ColoredBox(
            color: t.fill,
            child: Icon(icon, size: 22, color: t.text2),
          );
  }
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

String _clock(String raw) =>
    RegExp(r'\d{1,2}:\d{2}').firstMatch(raw)?.group(0) ?? raw;

/// Local pagination provides an actionable retry instead of swallowing failures.
class _MessageFeed<T> extends StatefulWidget {
  final Future<Paged<T>> Function(int page, {bool refresh}) load;
  final Future<Paged<T>> Function(Paged<T> previous)? next;
  final Widget Function(T item) itemBuilder;
  final String Function(T item) identity;
  final String Function(T item) date;
  final String empty;

  /// 类型选择:放在第一个日期行右侧;无内容、加载或失败时单独占一行
  final Widget? filter;
  const _MessageFeed({
    super.key,
    required this.load,
    this.next,
    required this.itemBuilder,
    required this.identity,
    required this.date,
    required this.empty,
    this.filter,
  });
  @override
  State<_MessageFeed<T>> createState() => _MessageFeedState<T>();
}

class _MessageFeedState<T> extends State<_MessageFeed<T>> {
  final _scroll = ScrollController();
  final _items = <T>[];
  Paged<T>? _last;
  bool _busy = false;
  bool _started = false;
  bool _hasNext = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    _fetch();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _nearEnd() {
    if (!_busy &&
        _hasNext &&
        _error == null &&
        _scroll.position.extentAfter < 260) {
      _fetch(more: true);
    }
  }

  Future<void> _fetch({bool more = false, bool refresh = false}) async {
    if (_busy) return;
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
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        final ids = _items.map(widget.identity).toSet();
        _items.addAll(result.items.where((e) => ids.add(widget.identity(e))));
        _hasNext =
            result.page.hasNext &&
            (!more || result.page.current > (previous?.page.current ?? 0));
        _last = result;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          if (e is PageMessage &&
              (e.kind == PageMessageKind.loginRequired ||
                  e.kind == PageMessageKind.permissionDenied)) {
            _items.clear();
            _last = null;
            _hasNext = false;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _started = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (!_started) return _withFilterRow(const _MessageSkeleton());
    final error = _error;
    if (_items.isEmpty && error != null) {
      if (error is PageMessage) {
        final login = error.kind == PageMessageKind.loginRequired;
        return _withFilterRow(
          StateView(
            icon: login ? AppIcons.lock : AppIcons.info,
            message: login ? '登录后查看消息' : error.text,
            actionLabel: login ? '登录' : '重试',
            onAction: login
                ? () async {
                    await Navigator.of(context).pushNamed('/login');
                    if (mounted) await _fetch(refresh: true);
                  }
                : () => _fetch(refresh: true),
          ),
        );
      }
      return _withFilterRow(
        StateView.error(error, onRetry: () => _fetch(refresh: true)),
      );
    }
    return ExpressivePageReveal(
      active: true,
      animateOnMount: true,
      child: RefreshIndicator(
        onRefresh: () => _fetch(refresh: true),
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(top: 4, bottom: 120),
          itemCount: _items.isEmpty ? 1 : _items.length + 1,
          itemBuilder: (context, index) {
            if (_items.isEmpty) {
              return Column(
                children: [
                  if (widget.filter != null) _filterRow(null),
                  SizedBox(
                    height: 300,
                    child: StateView.empty(message: widget.empty),
                  ),
                ],
              );
            }
            if (index == _items.length) {
              if (error != null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: AppButton(
                      label: '未能加载更多，轻点重试',
                      variant: AppButtonVariant.plain,
                      icon: AppIcons.refresh,
                      onPressed: () => _fetch(more: true),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
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
                          style: TextStyle(
                            fontSize: AppType.sizeFootnote,
                            color: t.text3,
                          ),
                        ),
                ),
              );
            }
            final day = _day(widget.date(_items[index]));
            final newDay =
                index == 0 || day != _day(widget.date(_items[index - 1]));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (newDay && index == 0 && widget.filter != null)
                  _filterRow(day)
                else if (newDay)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.screen,
                      index == 0 ? 10 : 22,
                      AppSpace.screen,
                      2,
                    ),
                    child: Text(
                      day,
                      style: TextStyle(
                        fontSize: AppType.sizeFootnote,
                        color: t.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                widget.itemBuilder(_items[index]),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 第一个日期行:左侧日期,右侧类型选择
  Widget _filterRow(String? day) {
    final t = AppTokens.of(context);
    return Padding(
      key: const ValueKey('message-filter-row'),
      padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, 12, 0),
      child: Row(
        children: [
          if (day != null)
            Text(
              day,
              style: TextStyle(
                fontSize: AppType.sizeFootnote,
                color: t.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
          const Spacer(),
          widget.filter!,
        ],
      ),
    );
  }

  Widget _withFilterRow(Widget child) => widget.filter == null
      ? child
      : Column(
          children: [
            _filterRow(null),
            Expanded(child: child),
          ],
        );
}

class _MessageSkeleton extends StatelessWidget {
  const _MessageSkeleton();
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: List.generate(
        4,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: t.fill,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 110, height: 13, color: t.fill),
                    const SizedBox(height: 13),
                    Container(height: 13, color: t.fill),
                    const SizedBox(height: 9),
                    FractionallySizedBox(
                      widthFactor: .65,
                      child: Container(height: 13, color: t.fill),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
