/// Forum discussion and site-provided type filters.
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';
import '../design/display_text.dart';
import '../design/scroll_progress.dart';
import '../design/forum_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/press.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../models/thread_list_time.dart';

import '../di.dart';
import '../data/forum_repository.dart';
import '../data/favorite_index.dart';
import '../ui/favorite_action.dart';
import '../models/models.dart';
import '../models/thread_sort.dart';
import '../widgets/browse_controls.dart';
import '../ui/chrome_button.dart';
import '../ui/picker.dart';
import '../widgets/browse_thread_list.dart';
import '../widgets/password_sheet.dart';
import '../widgets/route_entry_gate.dart';
import '../ui/plain_rows.dart';
import '../widgets/expressive_controls.dart';
import 'new_thread_page.dart';
import 'search_page.dart';
import 'thread_detail_page.dart';

class ForumThreadsPage extends StatefulWidget {
  final int fid;
  final String title;
  final ForumRepository? repository;
  const ForumThreadsPage({
    super.key,
    required this.fid,
    required this.title,
    this.repository,
  });
  @override
  State<ForumThreadsPage> createState() => _ForumThreadsPageState();
}

class _ForumThreadsPageState extends State<ForumThreadsPage>
    with SingleTickerProviderStateMixin {
  static final Map<int, ThreadSort> _sortMemory = {};
  final _entryGate = RouteEntryGate();
  late ThreadSort _sort;
  bool _typePickerOpen = false;
  late final _composeProgress = ScrollDeltaProgress(
    vsync: this,
    travel: ForumTokens.fabTravel,
  );
  final _types = ValueNotifier<List<ThreadType>>(const []);
  int _typeid = 0;
  String _lastTypeLabel = '';
  int _revision = 0;
  ForumRepository get _repository => widget.repository ?? forumRepo;

  @override
  void initState() {
    super.initState();
    _sort = _sortMemory[widget.fid] ?? ThreadSort.fallback;
    if (_repository.cachedThreadTypes(widget.fid) case final cached?) {
      _types.value = cached;
    } else {
      _loadTypes();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entryGate.update(ModalRoute.of(context));
  }

  Future<void> _loadTypes() async {
    try {
      final types = await _repository.threadTypes(widget.fid);
      if (_entryGate.wait case final wait?) {
        if (!await wait) return;
      }
      if (!mounted) return;
      _types.value = types;
      // With no active filter, only the category action needs to update.
      if (_typeid != 0) {
        setState(() {
          if (!types.any((type) => type.typeid == _typeid)) {
            _typeid = 0;
          }
        });
      }
    } catch (_) {
      /* Categories are optional; discussion remains available. */
    }
  }

  Future<void> _pickType(List<PickerOption<int>> options) async {
    if (_typePickerOpen) return;
    _typePickerOpen = true;
    final picked = await showPickerSheet<int>(
      context,
      title: '选择分类',
      options: options,
      value: _typeid,
      columns: 3,
      immediateSelection: true,
    );
    _typePickerOpen = false;
    if (!mounted || picked == null || picked.value == _typeid) return;
    setState(() {
      _typeid = picked.value;
      if (_typeid != 0) {
        _lastTypeLabel = options
            .firstWhere((option) => option.value == _typeid)
            .label;
      }
    });
    _showCompose();
  }

  void _selectSort(ThreadSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    _sortMemory[widget.fid] = sort;
    _showCompose();
  }

  void _showCompose() =>
      _composeProgress.show(reduced: MediaQuery.disableAnimationsOf(context));

  bool _trackScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (notification is ScrollStartNotification) _composeProgress.stop();
    if (notification is ScrollUpdateNotification) {
      _composeProgress.drag(notification.scrollDelta ?? 0, reduced: reduced);
    }
    if (notification is ScrollEndNotification) {
      _composeProgress.settle(
        velocity: -(notification.dragDetails?.primaryVelocity ?? 0),
        reduced: reduced,
      );
    }
    return false;
  }

  @override
  void dispose() {
    _entryGate.dispose();
    _types.dispose();
    _composeProgress.dispose();
    super.dispose();
  }

  Future<void> _openNewThread() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewThreadPage(fid: widget.fid, forumName: widget.title),
      ),
    );
    if (posted == true && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sort = _sort;
    final typeid = _typeid;
    final selectedType = _typeid == 0
        ? null
        : _types.value.where((type) => type.typeid == _typeid).firstOrNull;
    return NotificationListener<ScrollNotification>(
      onNotification: _trackScroll,
      child: BrowseScaffold(
        surface: AppSurface.grouped,
        title: formatForumName(widget.title),
        actions: [
          FavoriteActionBuilder(
            target: FavoriteTarget(
              type: FavoriteType.forum,
              targetId: widget.fid,
              title: widget.title,
            ),
            builder: (context, favorited, busy, toggle) =>
                ValueListenableBuilder(
                  valueListenable: _types,
                  builder: (context, types, _) {
                    final options = [
                      const PickerOption(value: 0, label: '全部分类'),
                      for (final type in types)
                        if (type.typeid != 0)
                          PickerOption(value: type.typeid, label: type.name),
                    ];
                    return ChromeGroup(
                      items: [
                        ChromeGroupItem(
                          tooltip: '分类筛选',
                          icon: AppIcons.filter,
                          selected: typeid != 0,
                          dot: typeid != 0,
                          onPressed: options.length > 1
                              ? () => _pickType(options)
                              : null,
                        ),
                        ChromeGroupItem(
                          tooltip: '搜索帖子',
                          icon: AppIcons.search,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SearchPage(),
                            ),
                          ),
                        ),
                        ChromeGroupItem(
                          tooltip: favorited ? '取消收藏版块' : '收藏版块',
                          icon: favorited
                              ? AppIcons.bookmarkFilled
                              : AppIcons.bookmark,
                          selected: favorited,
                          onPressed: busy ? null : toggle,
                        ),
                      ],
                    );
                  },
                ),
          ),
        ],
        header: SingleMotionBuilder(
          value: selectedType == null ? 0.0 : 1.0,
          motion: AppMotion.of(context, AppMotion.reveal),
          active: !MediaQuery.disableAnimationsOf(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PressScale(
                key: const ValueKey('forum-filter-clear'),
                onTap: selectedType == null
                    ? null
                    : () {
                        setState(() => _typeid = 0);
                        _showCompose();
                      },
                semanticLabel: '清除分类',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          selectedType?.name ?? _lastTypeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.footnote.copyWith(
                            color: AppTokens.of(context).accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        AppIcons.close,
                        size: 14,
                        color: AppTokens.of(context).accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          builder: (context, value, child) => ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: value.clamp(0.0, 1.0),
              child: ExcludeSemantics(
                excluding: selectedType == null,
                child: IgnorePointer(
                  ignoring: selectedType == null,
                  child: child,
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: ValueListenableBuilder<double>(
          valueListenable: _composeProgress,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              end: AppSpace.screen - kFloatingActionButtonMargin,
            ),
            child: _composeButton(context),
          ),
          builder: (context, progress, child) => IgnorePointer(
            ignoring: progress >= 1,
            child: ExcludeSemantics(
              excluding: progress >= 1,
              child: Transform.translate(
                key: const ValueKey('forum-compose-visibility'),
                offset: Offset(
                  0,
                  MediaQuery.disableAnimationsOf(context)
                      ? 0
                      : ForumTokens.fabTravel * progress,
                ),
                child: Opacity(opacity: 1 - progress, child: child),
              ),
            ),
          ),
        ),
        body: BrowseThreadList(
          key: PageStorageKey('forum-list-${widget.fid}'),
          queryKey: (widget.fid, _typeid, _sort, _revision),
          entryGate: _entryGate,
          cachedFirstPage: () {
            final result = _repository.cachedThreadList(
              widget.fid,
              typeid: typeid == 0 ? null : typeid,
              filter: sort.filter,
              orderby: sort.orderby,
            );
            return result == null
                ? null
                : Paged(items: result.threads, page: result.page);
          },
          groupCards: true,
          sectionAction: Tooltip(
            message: '排序',
            child: PickerButton<ThreadSort>(
              sheetTitle: '排序方式',
              options: [
                for (final value in ThreadSort.values)
                  PickerOption(value: value, label: value.label),
              ],
              value: _sort,
              onChanged: _selectSort,
              sheetColumns: 1,
              labelStyle: AppType.footnote.copyWith(
                color: AppTokens.of(context).text2,
              ),
            ),
          ),
          loader: (page, {bool refresh = false}) async {
            final result = await _repository.threadList(
              widget.fid,
              page: page,
              typeid: typeid == 0 ? null : typeid,
              filter: sort.filter,
              orderby: sort.orderby,
              refresh: refresh,
            );
            return Paged(items: result.threads, page: result.page);
          },
          onPassword: (fid) async {
            final success = await showForumPasswordUnlock(
              context,
              fid,
              repository: _repository,
            );
            if (success && mounted) await _loadTypes();
            return success;
          },
          emptyMessage: '这个分类还没有帖子',
          collapsePinned: true,
          pinnedMemoryKey: widget.fid,
          sectionLayoutKey: (sort, now.year, now.month, now.day),
          sectionLabel: ThreadListTime.sectionLabels(sort, now: now),
          // 行级监听:一次 markRead 只重建对应一行
          itemBuilder: (context, thread) => ReadStateBuilder(
            tid: thread.tid,
            replies: thread.replies,
            builder: (context, state) => ThreadRow(
              thread: thread,
              forumStyle: true,
              readState: state,
              showCategory: false,
              timeLabel: ThreadListTime.of(thread, sort, now: now).label ?? '',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ThreadDetailPage(
                    tid: thread.tid,
                    seenReplies: thread.replies,
                    observedReplies: thread.observedReplies,
                    title: thread.title,
                    fid: widget.fid,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _composeButton(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Tooltip(
      message: '发帖',
      excludeFromSemantics: true,
      child: PressScale(
        onTap: _openNewThread,
        semanticLabel: '发帖',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.accent,
            shape: BoxShape.circle,
            boxShadow: tokens.btnShadow,
          ),
          child: SizedBox.square(
            dimension: ForumTokens.fabSize,
            child: Icon(
              AppIcons.compose,
              color: tokens.onAccent,
              size: ForumTokens.fabIconSize,
            ),
          ),
        ),
      ),
    );
  }
}
