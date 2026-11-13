/// Forum discussion and site-provided type filters.
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../ui/app_button.dart';
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

class _ForumThreadsPageState extends State<ForumThreadsPage> {
  static final Map<int, ThreadSort> _sortMemory = {};
  late ThreadSort _sort;
  bool _sortPickerOpen = false;
  bool _typePickerOpen = false;
  final _composeVisible = ValueNotifier<bool>(true);
  double _dragDistance = 0;
  List<ThreadType> _types = const [];
  int _typeid = 0;
  int _revision = 0;
  ForumRepository get _repository => widget.repository ?? forumRepo;

  @override
  void initState() {
    super.initState();
    _sort = _sortMemory[widget.fid] ?? ThreadSort.fallback;
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await _repository.threadTypes(widget.fid);
      if (mounted) {
        setState(() {
          _types = types;
          if (_typeid != 0 && !types.any((type) => type.typeid == _typeid)) {
            _typeid = 0;
          }
        });
      }
    } catch (_) {
      /* Categories are optional; discussion remains available. */
    }
  }

  Future<void> _pickSort() async {
    if (_sortPickerOpen) return;
    _sortPickerOpen = true;
    final picked = await showPickerSheet<ThreadSort>(
      context,
      title: '排序方式',
      options: [
        for (final sort in ThreadSort.values)
          PickerOption(value: sort, label: sort.label),
      ],
      value: _sort,
    );
    _sortPickerOpen = false;
    if (mounted && picked != null) _selectSort(picked.value);
  }

  Future<void> _pickType(List<PickerOption<int>> options) async {
    if (_typePickerOpen) return;
    _typePickerOpen = true;
    final picked = await showPickerSheet<int>(
      context,
      title: '选择分类',
      options: options,
      value: _typeid,
    );
    _typePickerOpen = false;
    if (!mounted || picked == null || picked.value == _typeid) return;
    setState(() => _typeid = picked.value);
    _composeVisible.value = true;
  }

  void _selectSort(ThreadSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    _sortMemory[widget.fid] = sort;
    _composeVisible.value = true;
  }

  bool _trackScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta.sign != _dragDistance.sign) _dragDistance = 0;
      _dragDistance += delta;
      if (_dragDistance.abs() >= 6) {
        final visible = _dragDistance < 0 || notification.metrics.pixels < 40;
        if (_composeVisible.value != visible) _composeVisible.value = visible;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _composeVisible.dispose();
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
    final options = [
      const PickerOption(value: 0, label: '全部分类'),
      for (final type in _types.where((type) => type.typeid != 0))
        PickerOption(value: type.typeid, label: type.name),
    ];
    final hasCategories = options.length > 1;
    final now = DateTime.now();
    final sort = _sort;
    final typeid = _typeid;
    return BrowseScaffold(
      title: widget.title,
      actions: [
        FavoriteActionBuilder(
          target: FavoriteTarget(
            type: FavoriteType.forum,
            targetId: widget.fid,
            title: widget.title,
          ),
          builder: (context, favorited, busy, toggle) => ChromeGroup(
            items: [
              if (hasCategories)
                ChromeGroupItem(
                  tooltip: '分类筛选',
                  icon: AppIcons.filter,
                  selected: typeid != 0,
                  onPressed: () => _pickType(options),
                ),
              ChromeGroupItem(
                tooltip: '排序',
                icon: AppIcons.sort,
                selected: sort != ThreadSort.fallback,
                onPressed: _pickSort,
              ),
              ChromeGroupItem(
                tooltip: '搜索帖子',
                icon: AppIcons.search,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
              ),
              ChromeGroupItem(
                tooltip: favorited ? '取消收藏版块' : '收藏版块',
                icon: favorited ? AppIcons.bookmarkFilled : AppIcons.bookmark,
                selected: favorited,
                onPressed: busy ? null : toggle,
              ),
            ],
          ),
        ),
      ],
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _composeVisible,
        child: Tooltip(
          message: '发主题',
          child: AppButton(
            label: '发帖',
            icon: AppIcons.compose,
            onPressed: _openNewThread,
          ),
        ),
        builder: (context, visible, child) => IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: SingleMotionBuilder(
              value: visible ? 1.0 : 0.0,
              motion: AppMotion.of(context, AppMotion.reveal),
              active: !MediaQuery.disableAnimationsOf(context),
              child: child,
              builder: (context, progress, child) => Opacity(
                key: const ValueKey('forum-compose-visibility'),
                opacity: progress.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 80 * (1 - progress.clamp(0.0, 1.0))),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _trackScroll,
        child: BrowseThreadList(
          key: ValueKey('${widget.fid}-$_typeid-${_sort.name}-$_revision'),
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
          sectionLabel: sort.groupsByDate
              ? (thread) => ThreadListTime.of(thread, sort, now: now).section
              : null,
          // 行级监听:一次 markRead 只重建对应一行
          itemBuilder: (context, thread) => ReadStateBuilder(
            tid: thread.tid,
            replies: thread.replies,
            builder: (context, state) => ThreadRow(
              thread: thread,
              readState: state,
              eyebrow: thread.typeName,
              showCategory: _typeid == 0,
              timeLabel: ThreadListTime.of(thread, sort, now: now).label ?? '',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ThreadDetailPage(
                    tid: thread.tid,
                    seenReplies: thread.replies,
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
}
