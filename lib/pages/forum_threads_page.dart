/// Forum discussion and site-provided type filters.
library;

import 'package:flutter/material.dart';

import '../di.dart';
import '../data/forum_repository.dart';
import '../data/favorite_index.dart';
import '../ui/favorite_action.dart';
import '../models/models.dart';
import '../models/thread_sort.dart';
import '../widgets/browse_controls.dart';
import '../design/tokens.dart';
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
      if (mounted) setState(() => _types = types);
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
    if (!mounted || picked == null || picked.value == _sort) return;
    setState(() => _sort = picked.value);
    _sortMemory[widget.fid] = _sort;
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
              ChromeGroupItem(
                tooltip: '排序',
                icon: AppIcons.sort,
                selected: _sort != ThreadSort.fallback,
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
                tooltip: '发主题',
                icon: AppIcons.compose,
                onPressed: _openNewThread,
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
      body: Column(
        children: [
          ExpressiveVisibility(
            visible: options.length > 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen - 4,
                0,
                AppSpace.screen,
                4,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PickerButton<int>(
                  sheetTitle: '选择分类',
                  options: options,
                  value: _typeid,
                  onChanged: (id) {
                    if (id != _typeid) setState(() => _typeid = id);
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: BrowseThreadList(
              key: ValueKey('${widget.fid}-$_typeid-${_sort.name}-$_revision'),
              loader: (page, {bool refresh = false}) async {
                final result = await _repository.threadList(
                  widget.fid,
                  page: page,
                  typeid: _typeid == 0 ? null : _typeid,
                  filter: _sort.filter,
                  orderby: _sort.orderby,
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
              // 行级监听:一次 markRead 只重建对应一行
              itemBuilder: (context, thread) => ReadStateBuilder(
                tid: thread.tid,
                replies: thread.replies,
                builder: (context, state) => ThreadRow(
                  thread: thread,
                  readState: state,
                  eyebrow: thread.typeName,
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
        ],
      ),
    );
  }
}
