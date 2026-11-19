/// Sliver 版分页列表
///
/// 首页要让内容从大标题与顶栏底下滚过去,必须整屏是一个 CustomScrollView,
/// 不能嵌套 ListView。这里把「首屏加载 / 刷新 / 续页 / 状态分流」做成 sliver。
library;

import 'package:flutter/material.dart';
import '../data/user_block_index.dart';
import '../design/list_end_tokens.dart';
import '../ui/app_button.dart';

import '../design/tokens.dart';
import '../models/models.dart';
import 'state_view.dart';
import 'chhers_loading_transition.dart';
import 'expressive_controls.dart';

typedef SliverPageLoader<T> =
    Future<Paged<T>> Function(int page, {bool refresh});

class SliverPagedList<T> extends StatefulWidget {
  final SliverPageLoader<T> loader;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// 把一页的条目包成分组面
  final Widget Function(BuildContext context, List<Widget> rows)? groupBuilder;
  final ScrollController controller;
  final String emptyMessage;

  /// Gives rows stable identity and lets only newly added rows fade in.
  final Object Function(T item)? itemKey;
  final double precedingBottomPadding;
  final double followingBottomPadding;

  const SliverPagedList({
    super.key,
    required this.loader,
    required this.itemBuilder,
    required this.controller,
    this.groupBuilder,
    this.itemKey,
    this.emptyMessage = '这里还没有内容',
    this.precedingBottomPadding = 0,
    this.followingBottomPadding = 0,
  });

  @override
  State<SliverPagedList<T>> createState() => SliverPagedListState<T>();
}

class SliverPagedListState<T> extends State<SliverPagedList<T>> {
  final _items = <T>[];
  int _page = 1;
  bool _hasNext = false;
  bool _loading = false;
  Object? _error;
  int? _failedPage;
  bool _first = true;
  int _revision = 0;
  bool _checkScheduled = false;
  final _arrivals = <Object>{};

  void _blocksChanged() {
    if (mounted) setState(() {});
  }

  List<T> get _visibleItems => _items
      .where(
        (item) =>
            item is! ThreadSummary || !userBlockIndex.isBlocked(item.authorUid),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    userBlockIndex.addListener(_blocksChanged);
    widget.controller.addListener(_onScroll);
    load(1);
  }

  @override
  void dispose() {
    userBlockIndex.removeListener(_blocksChanged);
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted ||
          _loading ||
          !_hasNext ||
          _error != null ||
          !widget.controller.hasClients) {
        return;
      }
      final p = widget.controller.position;
      if (p.extentAfter < 600) load(_page + 1);
    });
  }

  /// 取某一页。page == 1 视为重置。
  Future<void> load(
    int page, {
    bool refresh = false,
    bool clear = false,
  }) async {
    if (_loading && page != 1) return;
    final revision = page == 1 ? ++_revision : _revision;
    setState(() {
      _loading = true;
      _error = null;
      if (clear) {
        _items.clear();
        _first = true;
      }
    });

    try {
      final r = await widget.loader(page, refresh: refresh);
      if (!mounted || revision != _revision) return;
      setState(() {
        if (page > 1 && (r.page.current != page || r.items.isEmpty)) {
          _hasNext = false;
          return;
        }
        final key = widget.itemKey;
        if (key != null) {
          final previous = _items.map(key).toSet();
          if (page == 1) _arrivals.clear();
          _arrivals.addAll(
            r.items.map(key).where((id) => !previous.contains(id)),
          );
        }
        if (page == 1) _items.clear();
        final seen = key == null ? <Object>{} : _items.map(key).toSet();
        _items.addAll(
          key == null ? r.items : r.items.where((item) => seen.add(key(item))),
        );
        // 当前页以响应为准:站点对越界页码会静默回落
        _page = r.page.current;
        _hasNext = r.page.hasNext;
      });
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = e;
          _failedPage = page;
        });
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() {
          _loading = false;
          _first = false;
        });
        _onScroll();
      }
    }
  }

  Future<void> refresh({bool clear = false}) =>
      load(1, refresh: true, clear: clear);

  @override
  Widget build(BuildContext context) => ChhersLoadingTransition.sliver(
    placeholderBuilder: (indicator) => SliverToBoxAdapter(
      child: SizedBox(height: 240, child: Center(child: indicator)),
    ),
    child: _first && _visibleItems.isEmpty ? null : _buildSliver(context),
  );

  Widget _item(BuildContext context, T item) {
    final child = widget.itemBuilder(context, item);
    final key = widget.itemKey?.call(item);
    if (key == null) return child;
    return ExpressivePageReveal(
      key: ValueKey(key),
      active: true,
      animateOnMount: _arrivals.remove(key),
      child: child,
    );
  }

  Widget _buildSliver(BuildContext context) {
    final items = _visibleItems;
    final err = _error;
    if (err != null && items.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 280,
          child: err is PageMessage
              ? StateView.forMessage(
                  err,
                  onLogin: () async {
                    await Navigator.of(context).pushNamed('/login');
                    if (mounted) await refresh();
                  },
                )
              : StateView.error(err, onRetry: refresh),
        ),
      );
    }

    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 240,
          child: _items.isNotEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('已隐藏黑名单用户的帖子'),
                    if (_hasNext)
                      AppButton(
                        label: '继续加载',
                        variant: AppButtonVariant.plain,
                        onPressed: _loading ? null : () => load(_page + 1),
                      ),
                  ],
                )
              : StateView.empty(message: widget.emptyMessage),
        ),
      );
    }

    final footer = _error != null
        ? Padding(
            padding: EdgeInsets.only(
              top: ListEndTokens.markerPadding(widget.precedingBottomPadding),
              bottom: ListEndTokens.markerPadding(
                widget.followingBottomPadding,
              ),
            ),
            child: Center(
              child: AppButton(
                label: '加载失败，重试',
                variant: AppButtonVariant.plain,
                onPressed: () => load(_failedPage ?? _page + 1, refresh: true),
              ),
            ),
          )
        : ListFooter(
            loading: _loading,
            exhausted: !_hasNext,
            precedingBottomPadding: widget.precedingBottomPadding,
            followingBottomPadding: widget.followingBottomPadding,
          );
    if (widget.groupBuilder == null) {
      // 平铺行自带屏幕边距与分隔线,列表不再加边距和分隔
      return SliverMainAxisGroup(
        slivers: [
          SliverList.builder(
            itemCount: items.length,
            findChildIndexCallback: widget.itemKey == null
                ? null
                : (key) {
                    if (key is! ValueKey) return null;
                    final index = items.indexWhere(
                      (item) => widget.itemKey?.call(item) == key.value,
                    );
                    return index < 0 ? null : index;
                  },
            itemBuilder: (context, index) => _item(context, items[index]),
          ),
          SliverToBoxAdapter(child: footer),
        ],
      );
    }
    final rows = items.map((e) => _item(context, e)).toList();
    final group = widget.groupBuilder;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        0,
        AppSpace.screen,
        8,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (group != null) group(context, rows) else ...rows,
            footer,
          ],
        ),
      ),
    );
  }
}
