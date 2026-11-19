/// Browse lists use the surrounding NestedScrollView's primary controller.
library;

import 'package:flutter/material.dart';
import '../data/user_block_index.dart';
import '../ui/app_button.dart';

import '../ui/plain_rows.dart';
import '../ui/feedback.dart';
import '../models/models.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../design/forum_tokens.dart';
import '../design/list_end_tokens.dart';
import '../design/shapes.dart';
import '../design/thread_row_tokens.dart';
import '../design/typography.dart';
import 'browse_controls.dart';
import 'paged_list.dart' show PageLoader;
import 'password_sheet.dart';
import 'chhers_refresh_indicator.dart';
import 'state_view.dart';
import 'expressive_controls.dart';

class BrowseThreadList extends StatefulWidget {
  final PageLoader<ThreadSummary> loader;
  final Widget Function(BuildContext context, ThreadSummary thread) itemBuilder;
  final Widget? header;

  /// Changes invalidate in-flight responses, keeping committed rows until arrival.
  final Object? queryKey;
  final bool groupCards;
  final Widget? sectionAction;
  final String? Function(ThreadSummary thread)? sectionLabel;
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
    this.queryKey,
    this.groupCards = false,
    this.sectionAction,
    this.sectionLabel,
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
  int _generation = 0;
  int _contentRevision = 0;
  Object? _committedQueryKey;
  String? Function(ThreadSummary)? _committedSectionLabel;
  Widget Function(BuildContext, ThreadSummary)? _committedBuilder;

  @override
  void didUpdateWidget(covariant BrowseThreadList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryKey != widget.queryKey) _load(1);
  }

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

  void _blocksChanged() {
    if (mounted) setState(() {});
  }

  List<ThreadSummary> get _visibleItems => _items
      .where((item) => !userBlockIndex.isBlocked(item.authorUid))
      .toList();

  @override
  void initState() {
    super.initState();
    userBlockIndex.addListener(_blocksChanged);
    _load(1);
  }

  @override
  void dispose() {
    userBlockIndex.removeListener(_blocksChanged);
    super.dispose();
  }

  Future<void> _load(int page, {bool refresh = false}) async {
    if (_loading && page != 1) return;
    final generation = page == 1 ? ++_generation : _generation;
    final queryKey = widget.queryKey;
    final sectionLabel = widget.sectionLabel;
    final itemBuilder = widget.itemBuilder;
    setState(() {
      _loading = true;
      _error = null;
      _failedPage = null;
    });
    try {
      final response = await widget.loader(page, refresh: refresh);
      if (!mounted || generation != _generation) return;
      final resetScroll =
          page == 1 && !_first && _committedQueryKey != queryKey;
      setState(() {
        if (page > 1 && response.page.current != page) {
          _hasNext = false;
          return;
        }
        if (page == 1) {
          if (_first || _committedQueryKey != queryKey) _contentRevision++;
          _items.clear();
          _committedQueryKey = queryKey;
          _committedSectionLabel = sectionLabel;
          _committedBuilder = itemBuilder;
        }
        final known = _items.map((e) => e.tid).toSet();
        final added = response.items.where((e) => known.add(e.tid)).toList();
        _items.addAll(added);
        if (page > 1 && added.isEmpty) {
          _hasNext = false;
          return;
        }
        _page = response.page.current;
        _hasNext = response.page.hasNext;
      });
      if (resetScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) _scrollToStart();
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          _failedPage = page;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _first = false;
        });
      }
    }
  }

  void _scrollToStart() {
    final nested = context.findAncestorStateOfType<NestedScrollViewState>();
    final controller =
        nested?.innerController ?? PrimaryScrollController.maybeOf(context);
    if (controller == null || !controller.hasClients) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final position = controller.position;
    if (nested == null) {
      AppMotion.scrollTo(position, position.minScrollExtent, reduced: reduced);
      return;
    }
    final outer = nested.outerController.position;
    // The outer position owns the header; its coordinate also resets the body.
    final distance = outer.pixels + position.pixels;
    if (!reduced && distance > outer.viewportDimension * 1.5) {
      position.jumpTo(
        (outer.viewportDimension - outer.maxScrollExtent).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
    if (outer.pixels == outer.minScrollExtent &&
        position.pixels == position.minScrollExtent) {
      return;
    }
    if (reduced) {
      outer.jumpTo(outer.minScrollExtent);
    } else {
      outer.animateTo(
        outer.minScrollExtent,
        duration: AppMotion.revealDuration,
        curve: AppMotion.revealCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;
    final awaitingReplacement = _committedQueryKey != widget.queryKey;
    final itemBuilder = awaitingReplacement
        ? _committedBuilder ?? widget.itemBuilder
        : widget.itemBuilder;
    final sectionLabel = awaitingReplacement
        ? _committedSectionLabel
        : widget.sectionLabel;
    var pinned = 0;
    if (widget.collapsePinned) {
      while (pinned < items.length && items[pinned].sticky) {
        pinned++;
      }
    }
    final slots = <({int index, String? section})>[];
    if (pinned > 0) slots.add((index: -1, section: null));
    String? previousSection;
    var hasSectionAction = false;
    for (var i = pinned; i < items.length; i++) {
      final section = sectionLabel?.call(items[i]);
      if (section != previousSection || (i == pinned && section != null)) {
        slots.add((index: i, section: section ?? ''));
        hasSectionAction = true;
      }
      previousSection = section;
      slots.add((index: i, section: null));
    }
    if (!hasSectionAction && widget.sectionAction != null) {
      slots.insert(pinned > 0 ? 1 : 0, (index: -2, section: ''));
    }
    final firstSection = slots.indexWhere((slot) => slot.section != null);
    final visibleCount = slots.length;
    final lastSlot = slots.lastOrNull;
    final footerInCard =
        widget.groupCards &&
        lastSlot != null &&
        lastSlot.index >= 0 &&
        lastSlot.section == null;
    final error = _error;
    const sortKey = ValueKey('browse-sort-section');
    final childKeys = <Key>[
      if (widget.header != null) const ValueKey('browse-header'),
      if (items.isEmpty) ...[
        if (widget.sectionAction != null) sortKey,
        const ValueKey('browse-empty'),
      ] else ...[
        for (final (slot, entry) in slots.indexed)
          if (entry.index == -1)
            const ValueKey('browse-pinned')
          else if (entry.section != null)
            slot == firstSection && widget.sectionAction != null
                ? sortKey
                : ValueKey(('browse-section', entry.section, entry.index))
          else
            ValueKey('browse-thread-${items[entry.index].tid}'),
        const ValueKey('browse-footer'),
      ],
    ];
    return ExpressivePageReveal(
      active: true,
      revision: _contentRevision,
      child: ChhersRefreshIndicator(
        onRefresh: () => _load(1, refresh: true),
        child: BrowsePaginationObserver(
          enabled: _hasNext && !_loading && _error == null,
          onLoadMore: () => _load(_page + 1),
          child: ListView.builder(
            key: const PageStorageKey('browse-scroll'),
            primary: true,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: widget.collapsePinned ? 0 : 4,
              bottom:
                  MediaQuery.paddingOf(context).bottom +
                  ListEndTokens.navigationGap,
            ),
            itemCount:
                (widget.header == null ? 0 : 1) +
                (items.isEmpty
                    ? (widget.sectionAction == null ? 1 : 2)
                    : visibleCount + 1),
            findChildIndexCallback: (key) {
              final index = childKeys.indexOf(key);
              return index < 0 ? null : index;
            },
            itemBuilder: (context, rawIndex) => KeyedSubtree(
              key: childKeys[rawIndex],
              child: Builder(
                builder: (context) {
                  if (widget.header != null && rawIndex == 0) {
                    return widget.header!;
                  }
                  final slot = rawIndex - (widget.header == null ? 0 : 1);
                  if (items.isEmpty &&
                      widget.sectionAction != null &&
                      slot == 0) {
                    return _section(context, '', widget.sectionAction);
                  }
                  // 置顶组:第 0 格是卡片,展开时置顶帖排在卡片内
                  if (pinned > 0 && slot == 0 && items.isNotEmpty) {
                    return PinnedGroupRow(
                      count: pinned,
                      firstTitle: items.first.title,
                      expanded: _pinnedExpanded,
                      onToggle: _togglePinned,
                      itemBuilder: (context, i) =>
                          itemBuilder(context, items[i]),
                    );
                  }
                  if (_first) {
                    // 首屏用静态骨架,不跑闪光动画
                    return const SizedBox(
                      height: 300,
                      child: SkeletonList(rows: 3),
                    );
                  }
                  if (items.isEmpty && error != null) {
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
                  if (items.isEmpty) {
                    return SizedBox(
                      height: 300,
                      child: _items.isNotEmpty
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('已隐藏黑名单用户的帖子'),
                                if (_hasNext)
                                  AppButton(
                                    label: '继续加载',
                                    variant: AppButtonVariant.plain,
                                    onPressed: _loading
                                        ? null
                                        : () => _load(_page + 1),
                                  ),
                              ],
                            )
                          : StateView.empty(message: widget.emptyMessage),
                    );
                  }
                  if (slot == visibleCount) {
                    final rowPadding = footerInCard
                        ? ThreadRowTokens.verticalPadding
                        : 0.0;
                    final cardPadding = footerInCard
                        ? ForumTokens.groupInset
                        : 0.0;
                    final footer = error == null
                        ? ListFooter(
                            loading: _loading,
                            exhausted: !_hasNext,
                            precedingBottomPadding: rowPadding,
                            followingBottomPadding: cardPadding,
                          )
                        : Padding(
                            padding: EdgeInsets.only(
                              top: ListEndTokens.markerPadding(rowPadding),
                              bottom: ListEndTokens.markerPadding(cardPadding),
                            ),
                            child: Center(
                              child: AppButton(
                                label: '继续加载',
                                variant: AppButtonVariant.plain,
                                icon: AppIcons.refresh,
                                onPressed: () => _load(
                                  _failedPage ?? _page + 1,
                                  refresh: _failedPage == 1,
                                ),
                              ),
                            ),
                          );
                    return footerInCard
                        ? ForumThreadCardSlice(
                            first: false,
                            last: true,
                            child: footer,
                          )
                        : footer;
                  }
                  final entry = slots[slot];
                  if (entry.section case final section?) {
                    return _section(
                      context,
                      section,
                      slot == firstSection ? widget.sectionAction : null,
                    );
                  }
                  final thread = items[entry.index];
                  return KeyedSubtree(
                    key: ValueKey('browse-thread-${thread.tid}'),
                    child: widget.groupCards
                        ? ForumThreadCardSlice(
                            key: ValueKey('forum-card-${thread.tid}'),
                            first:
                                entry.index == pinned ||
                                slots[slot - 1].section != null,
                            last: slot == slots.length - 1
                                ? !footerInCard
                                : slots[slot + 1].section != null,
                            child: PlainRowScope(
                              inset: 14,
                              separator: false,
                              child: itemBuilder(context, thread),
                            ),
                          )
                        : itemBuilder(context, thread),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label, Widget? action) =>
      Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.groupLabelInset,
            12,
            AppSpace.groupLabelInset,
            6,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppType.footnote.copyWith(
                    color: AppTokens.of(context).text3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?action,
            ],
          ),
        ),
      );
}

/// Adjacent slices paint one card while each row keeps lazy layout and caching.
class ForumThreadCardSlice extends StatelessWidget {
  const ForumThreadCardSlice({
    super.key,
    required this.first,
    required this.last,
    required this.child,
  });
  final bool first;
  final bool last;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: first ? const Radius.circular(ForumTokens.groupRadius) : Radius.zero,
      bottom: last
          ? const Radius.circular(ForumTokens.groupRadius)
          : Radius.zero,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.groupInset),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: AppTokens.of(context).surface,
          shape: appShape(ForumTokens.groupRadius, borderRadius: radius),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ForumTokens.groupInset,
            first ? ForumTokens.groupInset : 0,
            ForumTokens.groupInset,
            last ? ForumTokens.groupInset : 0,
          ),
          child: child,
        ),
      ),
    );
  }
}
