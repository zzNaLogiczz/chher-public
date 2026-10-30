/// Browse lists use the surrounding NestedScrollView's primary controller.
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';

import '../ui/plain_rows.dart';
import '../ui/feedback.dart';
import '../models/models.dart';
import 'browse_controls.dart';
import 'paged_list.dart' show PageLoader;
import 'password_sheet.dart';
import 'state_view.dart';
import 'expressive_controls.dart';

class BrowseThreadList extends StatefulWidget {
  final PageLoader<ThreadSummary> loader;
  final Widget Function(BuildContext context, ThreadSummary thread) itemBuilder;
  final Widget? header;
  final String emptyMessage;
  final Future<bool> Function(int fid)? onPassword;

  /// 把首页开头连续的置顶帖收成一行,点开原地展开
  final bool collapsePinned;

  /// 展开状态按这个键在会话内记住(版块页传 fid)
  final Object? pinnedMemoryKey;

  const BrowseThreadList({
    super.key,
    required this.loader,
    required this.itemBuilder,
    this.header,
    this.emptyMessage = '这里还没有帖子',
    this.onPassword,
    this.collapsePinned = false,
    this.pinnedMemoryKey,
  });

  @override
  State<BrowseThreadList> createState() => _BrowseThreadListState();
}

class _BrowseThreadListState extends State<BrowseThreadList> {
  /// 会话内记住各版块置顶组是否展开
  static final _pinnedMemory = <Object, bool>{};

  final _items = <ThreadSummary>[];
  late bool _pinnedExpanded =
      _pinnedMemory[widget.pinnedMemoryKey ?? Object()] ?? false;

  /// 开头连续的置顶帖数量;不折叠时为 0
  int get _pinned {
    if (!widget.collapsePinned) return 0;
    var n = 0;
    while (n < _items.length && _items[n].sticky) {
      n++;
    }
    return n;
  }

  /// 列表格数(不含页脚):置顶帖无论展开与否都收在第 0 格的卡片里
  int get _visibleCount {
    final pinned = _pinned;
    if (pinned == 0) return _items.length;
    return 1 + _items.length - pinned;
  }

  void _togglePinned() {
    setState(() => _pinnedExpanded = !_pinnedExpanded);
    final key = widget.pinnedMemoryKey;
    if (key != null) _pinnedMemory[key] = _pinnedExpanded;
  }

  int _page = 1;
  bool _loading = false;
  bool _first = true;
  bool _hasNext = false;
  Object? _error;
  int? _failedPage;
  bool _unlocking = false;

  Future<void> _unlock(PageMessage message) async {
    final fid = message.fid;
    if (_unlocking || fid == null) return;
    _unlocking = true;
    try {
      final success =
          await (widget.onPassword?.call(fid) ??
              showForumPasswordUnlock(context, fid));
      if (mounted && success) await _load(1, refresh: true);
    } finally {
      _unlocking = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page, {bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _failedPage = null;
    });
    try {
      final response = await widget.loader(page, refresh: refresh);
      if (!mounted) return;
      setState(() {
        if (page > 1 && response.page.current <= _page) {
          _hasNext = false;
          return;
        }
        if (page == 1) _items.clear();
        final known = _items.map((e) => e.tid).toSet();
        _items.addAll(response.items.where((e) => known.add(e.tid)));
        _page = response.page.current;
        _hasNext = response.page.hasNext;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _failedPage = page;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _first = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return ExpressivePageReveal(
      active: true,
      revision: _first,
      child: RefreshIndicator(
        onRefresh: () => _load(1, refresh: true),
        child: BrowsePaginationObserver(
          enabled: _hasNext && !_loading && _error == null,
          onLoadMore: () => _load(_page + 1),
          child: ListView.builder(
            primary: true,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 4, bottom: 96),
            itemCount:
                (widget.header == null ? 0 : 1) +
                (_items.isEmpty ? 1 : _visibleCount + 1),
            itemBuilder: (context, rawIndex) {
              if (widget.header != null && rawIndex == 0) return widget.header!;
              final slot = rawIndex - (widget.header == null ? 0 : 1);
              final pinned = _pinned;
              // 置顶组:第 0 格是卡片,展开时置顶帖排在卡片内
              if (pinned > 0 && slot == 0 && _items.isNotEmpty) {
                return PinnedGroupRow(
                  count: pinned,
                  expanded: _pinnedExpanded,
                  onToggle: _togglePinned,
                  itemBuilder: (context, i) =>
                      widget.itemBuilder(context, _items[i]),
                );
              }
              final index = pinned == 0 ? slot : slot - 1 + pinned;
              if (_first) {
                // 首屏用静态骨架,不跑闪光动画
                return const SizedBox(
                  height: 300,
                  child: SkeletonList(rows: 3),
                );
              }
              if (_items.isEmpty && error != null) {
                return SizedBox(
                  height: 300,
                  child: error is PageMessage
                      ? StateView.forMessage(
                          error,
                          onPassword: () => _unlock(error),
                          onLogin: () async {
                            await Navigator.pushNamed(context, '/login');
                            if (mounted) await _load(1, refresh: true);
                          },
                        )
                      : StateView.error(
                          error,
                          onRetry: () => _load(1, refresh: true),
                        ),
                );
              }
              if (_items.isEmpty) {
                return SizedBox(
                  height: 300,
                  child: StateView.empty(message: widget.emptyMessage),
                );
              }
              if (slot == _visibleCount) {
                if (error != null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: AppButton(
                      label: '继续加载',
                      variant: AppButtonVariant.plain,
                      icon: AppIcons.refresh,
                      onPressed: () => _load(
                        _failedPage ?? _page + 1,
                        refresh: _failedPage == 1,
                      ),
                    ),
                  );
                }
                return ListFooter(loading: _loading, exhausted: !_hasNext);
              }
              return widget.itemBuilder(context, _items[index]);
            },
          ),
        ),
      ),
    );
  }
}
