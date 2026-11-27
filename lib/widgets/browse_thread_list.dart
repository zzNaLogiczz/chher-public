/// Browse lists use the surrounding NestedScrollView's primary controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../data/browse_thread_layout.dart';
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
import 'route_entry_gate.dart';

class BrowseThreadList extends StatefulWidget {
  final PageLoader<ThreadSummary> loader;
  final Paged<ThreadSummary>? Function()? cachedFirstPage;
  final RouteEntryGate? entryGate;
  final Widget Function(BuildContext context, ThreadSummary thread) itemBuilder;
  final Widget? header;

  /// Changes invalidate in-flight responses, keeping committed rows until arrival.
  final Object? queryKey;
  final bool groupCards;
  final Widget? sectionAction;
  final String? Function(ThreadSummary thread)? sectionLabel;

  /// Equal values identify the same section labels for a cached model.
  final Object? sectionLayoutKey;
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
    this.cachedFirstPage,
    this.entryGate,
    this.header,
    this.queryKey,
    this.groupCards = false,
    this.sectionAction,
    this.sectionLabel,
    this.sectionLayoutKey,
    this.emptyMessage = '这里还没有帖子',
    this.onPassword,
    this.collapsePinned = false,
    this.pinnedMemoryKey,
  });

  @override
  State<BrowseThreadList> createState() => _BrowseThreadListState();
}

class _BrowseThreadListState extends State<BrowseThreadList>
    with SingleTickerProviderStateMixin {
  /// 会话内记住各版块置顶组是否展开
  static final _pinnedMemory = <Object, bool>{};

  late BrowseThreadLayout _layout;
  bool _viewportOnly = true;
  int? _firstRowLimit;
  final _skeletonKey = GlobalKey();
  bool _skeletonVisible = false;
  Rect? _skeletonExitBounds;
  AnimationController? _skeletonExit;
  late bool _pinnedExpanded =
      _pinnedMemory[widget.pinnedMemoryKey ?? Object()] ?? false;
  late bool _splitPinned = _pinnedExpanded;
  bool _closingSplitPins = false;
  final _pinnedRowKeys = <int, GlobalKey>{};

  void _togglePinned() {
    setState(() {
      _closingSplitPins = _splitPinned;
      _splitPinned = false;
      _pinnedExpanded = !_pinnedExpanded;
    });
    if (_closingSplitPins) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _closingSplitPins = false;
      });
    }
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
    if (oldWidget.collapsePinned != widget.collapsePinned ||
        oldWidget.groupCards != widget.groupCards ||
        (oldWidget.header == null) != (widget.header == null) ||
        (oldWidget.sectionAction == null) != (widget.sectionAction == null)) {
      _layout = _prepareLayout(_layout.source);
    }
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
    if (mounted) setState(() => _layout = _prepareLayout(_layout.source));
  }

  BrowseThreadLayout _prepareLayout(
    List<ThreadSummary> source, {
    bool firstPage = false,
    Object? cacheKey,
  }) => BrowseThreadLayout(
    source,
    options: (
      collapsePinned: widget.collapsePinned,
      groupCards: widget.groupCards,
      hasHeader: widget.header != null,
      hasAction: widget.sectionAction != null,
    ),
    firstPage: firstPage,
    cacheKey: cacheKey,
    sectionLabel: _committedSectionLabel,
  );

  @override
  void initState() {
    super.initState();
    userBlockIndex.addListener(_blocksChanged);
    if (widget.cachedFirstPage?.call() case final cached?) {
      _commit(
        cached,
        1,
        widget.queryKey,
        widget.sectionLabel,
        widget.sectionLayoutKey,
        widget.itemBuilder,
      );
      _first = false;
    } else {
      _layout = _prepareLayout(const []);
      _load(1);
    }
  }

  @override
  void dispose() {
    userBlockIndex.removeListener(_blocksChanged);
    _skeletonExit?.dispose();
    super.dispose();
  }

  void _retainVisibleSkeleton() {
    if (!_first || !_skeletonVisible || widget.entryGate == null) return;
    final skeleton = _skeletonKey.currentContext?.findRenderObject();
    final viewport = context.findRenderObject();
    if (skeleton is! RenderBox ||
        viewport is! RenderBox ||
        !skeleton.hasSize ||
        !viewport.hasSize) {
      return;
    }
    final bounds =
        skeleton.localToGlobal(Offset.zero, ancestor: viewport) & skeleton.size;
    if (!bounds.overlaps(Offset.zero & viewport.size)) return;
    _skeletonExitBounds = bounds;
    _skeletonExit =
        AnimationController(
          vsync: this,
          duration: AppMotion.loadingOut,
          value: 1,
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) {
            setState(() => _skeletonExitBounds = null);
          }
        });
    _skeletonExit!.reverse(from: 15 / 16);
  }

  Future<void> _load(int page, {bool refresh = false}) async {
    if (_loading && page != 1) return;
    final generation = page == 1 ? ++_generation : _generation;
    final queryKey = widget.queryKey;
    final sectionLabel = widget.sectionLabel;
    final sectionLayoutKey = widget.sectionLayoutKey;
    final itemBuilder = widget.itemBuilder;
    setState(() {
      _loading = true;
      _error = null;
      _failedPage = null;
    });
    var cancelled = false;
    try {
      final response = await widget.loader(page, refresh: refresh);
      if (!mounted || generation != _generation) return;
      if (widget.entryGate?.wait case final wait?) {
        cancelled = !await wait;
        if (cancelled || !mounted || generation != _generation) return;
      }
      final resetScroll =
          page == 1 && !_first && _committedQueryKey != queryKey;
      _retainVisibleSkeleton();
      setState(
        () => _commit(
          response,
          page,
          queryKey,
          sectionLabel,
          sectionLayoutKey,
          itemBuilder,
        ),
      );
      if (resetScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) _scrollToStart();
        });
      }
    } catch (error) {
      if (!cancelled && mounted && generation == _generation) {
        setState(() {
          _error = error;
          _failedPage = page;
        });
      }
    } finally {
      if (!cancelled && mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _first = false;
        });
      }
    }
  }

  void _commit(
    Paged<ThreadSummary> response,
    int page,
    Object? queryKey,
    String? Function(ThreadSummary)? sectionLabel,
    Object? sectionLayoutKey,
    Widget Function(BuildContext, ThreadSummary) itemBuilder,
  ) {
    if (page > 1 && response.page.current != page) {
      _hasNext = false;
      return;
    }
    if (page == 1) {
      if (_first || _committedQueryKey != queryKey) _contentRevision++;
      _committedQueryKey = queryKey;
      _committedSectionLabel = sectionLabel;
      _committedBuilder = itemBuilder;
      _layout = _prepareLayout(
        response.items,
        firstPage: true,
        cacheKey: sectionLayoutKey,
      );
    } else {
      final current = _layout.source;
      final known = current.map((item) => item.tid).toSet();
      final joined = [
        ...current,
        ...response.items.where((item) => known.add(item.tid)),
      ];
      if (joined.length == current.length) {
        _hasNext = false;
        return;
      }
      _layout = _prepareLayout(joined);
    }
    _page = response.page.current;
    _hasNext = response.page.hasNext;
    if (page == 1 && _viewportOnly && _layout.items.isNotEmpty) {
      if (_first && _loading && widget.entryGate != null && !_splitPinned) {
        // Leave room for the sort and pinned entries and the first thread.
        _firstRowLimit = 3;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Cached rows already paint during entry. Restore overscan after entry.
        if (widget.entryGate?.wait case final wait?) {
          if (!await wait || !mounted) return;
        }
        if (widget.entryGate != null) {
          // Give the visible rows their first fade frames before adding overscan.
          final binding = WidgetsBinding.instance;
          if (_firstRowLimit != null) {
            setState(() => _firstRowLimit = 7);
            await binding.endOfFrame;
            if (!mounted) return;
            setState(() => _firstRowLimit = null);
          }
          await binding.endOfFrame;
          await binding.endOfFrame;
          if (!mounted) return;
        }
        setState(() => _viewportOnly = false);
      });
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
    final layout = _layout;
    final items = layout.items;
    final slots = layout.slots;
    final pinned = layout.pinned;
    final itemBuilder = _committedQueryKey != widget.queryKey
        ? _committedBuilder ?? widget.itemBuilder
        : widget.itemBuilder;
    final visibleCount = slots.length;
    final splitPinned = _splitPinned && pinned > 0;
    final keys = splitPinned ? layout.expanded : layout.collapsed;
    final rowLimit = _firstRowLimit;
    final rowCount = rowLimit == null || splitPinned
        ? keys.rows.length
        : keys.rows.length.clamp(0, rowLimit + (widget.header == null ? 0 : 1));
    final footerInCard = layout.footerInCard;
    final error = _error;
    final list = ExpressivePageReveal(
      active: true,
      startOnFirstFrame: widget.entryGate != null && _contentRevision == 1,
      revision: _contentRevision,
      child: ChhersRefreshIndicator(
        onRefresh: () => _load(1, refresh: true),
        child: BrowsePaginationObserver(
          enabled:
              _hasNext && !_loading && rowLimit == null && _error == null,
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
            scrollCacheExtent: _viewportOnly
                ? const ScrollCacheExtent.pixels(0)
                : null,
            itemCount: rowCount,
            findChildIndexCallback: (key) {
              final index = keys.indexes[key];
              return index != null && index < rowCount ? index : null;
            },
            itemBuilder: (context, rawIndex) => KeyedSubtree(
              key: keys.rows[rawIndex],
              child: Builder(
                builder: (context) {
                  if (widget.header != null && rawIndex == 0) {
                    return widget.header!;
                  }
                  final row = rawIndex - (widget.header == null ? 0 : 1);
                  if (splitPinned && row > 0 && row <= pinned) {
                    return _pinnedSlice(
                      context,
                      first: row == 1,
                      last: row == pinned,
                      child: Builder(
                        builder: (context) =>
                            _pinnedItem(context, items[row - 1], itemBuilder),
                      ),
                    );
                  }
                  final slot = splitPinned && row > 0 ? row - pinned : row;
                  if (items.isEmpty &&
                      widget.sectionAction != null &&
                      slot == 0) {
                    return _section(context, '', widget.sectionAction);
                  }
                  if (pinned > 0 && slot == 0) {
                    if (splitPinned) {
                      return PinnedGroupRow.header(
                        count: pinned,
                        firstTitle: items.first.title,
                        onToggle: _togglePinned,
                      );
                    }
                    return PinnedGroupRow(
                      count: pinned,
                      firstTitle: items.first.title,
                      expanded: _pinnedExpanded,
                      animateFromExpanded: _closingSplitPins,
                      onToggle: _togglePinned,
                      itemBuilder: (context, i) =>
                          _pinnedItem(context, items[i], itemBuilder),
                    );
                  }
                  if (_first) {
                    return SizedBox(
                      height: 300,
                      child: widget.entryGate == null
                          ? const SkeletonList(rows: 3)
                          : _entrySkeleton(),
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
                      child: layout.source.isNotEmpty
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
                      slot == layout.firstSection ? widget.sectionAction : null,
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
    if (widget.entryGate == null) return list;
    return Stack(
      fit: StackFit.expand,
      children: [
        list,
        if (_skeletonExitBounds case final bounds?)
          Positioned.fromRect(
            rect: bounds,
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _skeletonExit!,
                  child: _entrySkeleton(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _entrySkeleton() => SkeletonList(
    key: _skeletonKey,
    rows: 3,
    onVisible: () => _skeletonVisible = true,
  );

  Widget _pinnedItem(
    BuildContext context,
    ThreadSummary thread,
    Widget Function(BuildContext, ThreadSummary) builder,
  ) => KeyedSubtree(
    key: _pinnedRowKeys.putIfAbsent(thread.tid, GlobalKey.new),
    child: builder(context, thread),
  );

  Widget _pinnedSlice(
    BuildContext context, {
    required bool first,
    required bool last,
    required Widget child,
  }) {
    const outer = Radius.circular(ForumTokens.groupRadius);
    const inner = Radius.circular(ForumTokens.rowRadius);
    final edge = BorderRadius.vertical(bottom: last ? outer : Radius.zero);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.groupInset,
        0,
        AppSpace.groupInset,
        last ? 6 : 0,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: AppTokens.of(context).surface,
          shape: appShape(ForumTokens.groupRadius, borderRadius: edge),
        ),
        child: AppClip.borderRadius(
          borderRadius: edge,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              ForumTokens.groupInset,
              0,
              ForumTokens.groupInset,
              last ? ForumTokens.groupInset : 0,
            ),
            child: AppClip.borderRadius(
              borderRadius: BorderRadius.vertical(
                top: first ? inner : Radius.zero,
                bottom: last ? inner : Radius.zero,
              ),
              child: PlainRowScope(
                inset: 12,
                separator: false,
                impliesSticky: true,
                child: child,
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
    final surface = AppTokens.of(context).surface;
    final inset = Padding(
      padding: EdgeInsets.fromLTRB(
        ForumTokens.groupInset,
        first ? ForumTokens.groupInset : 0,
        ForumTokens.groupInset,
        last ? ForumTokens.groupInset : 0,
      ),
      child: child,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.groupInset),
      child: !first && !last
          ? ColoredBox(color: surface, child: inset)
          : DecoratedBox(
              decoration: ShapeDecoration(
                color: surface,
                shape: appShape(
                  ForumTokens.groupRadius,
                  borderRadius: BorderRadius.vertical(
                    top: first
                        ? const Radius.circular(ForumTokens.groupRadius)
                        : Radius.zero,
                    bottom: last
                        ? const Radius.circular(ForumTokens.groupRadius)
                        : Radius.zero,
                  ),
                ),
              ),
              child: inset,
            ),
    );
  }
}
