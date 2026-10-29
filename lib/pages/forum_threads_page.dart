/// Forum discussion and site-provided type filters.
library;

import 'package:flutter/material.dart';

import '../di.dart';
import '../data/forum_repository.dart';
import '../models/models.dart';
import '../widgets/browse_controls.dart';
import '../design/tokens.dart';
import '../ui/chrome_button.dart';
import '../ui/picker.dart';
import '../widgets/browse_thread_list.dart';
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
  List<ThreadType> _types = const [];
  int _typeid = 0;
  int _revision = 0;
  ForumRepository get _repository => widget.repository ?? forumRepo;

  @override
  void initState() {
    super.initState();
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
        ChromeGroup(
          items: [
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
          ],
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
              key: ValueKey('$_typeid-$_revision'),
              loader: (page, {bool refresh = false}) async {
                final result = await _repository.threadList(
                  widget.fid,
                  page: page,
                  typeid: _typeid == 0 ? null : _typeid,
                  refresh: refresh,
                );
                return Paged(items: result.threads, page: result.page);
              },
              emptyMessage: '这个分类还没有帖子',
              collapsePinned: true,
              pinnedMemoryKey: widget.fid,
              itemBuilder: (context, thread) => ThreadRow(
                thread: thread,
                eyebrow: thread.typeName,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ThreadDetailPage(
                      tid: thread.tid,
                      title: thread.title,
                      fid: widget.fid,
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
