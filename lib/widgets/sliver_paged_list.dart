/// Sliver 版分页列表
///
/// 首页要让内容从大标题与顶栏底下滚过去,必须整屏是一个 CustomScrollView,
/// 不能嵌套 ListView。这里把「首屏加载 / 刷新 / 续页 / 状态分流」做成 sliver。
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';

import '../design/tokens.dart';
import '../models/models.dart';
import 'state_view.dart';
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
  final Object Function(T item)? itemKey;

  const SliverPagedList({
    super.key,
    required this.loader,
    required this.itemBuilder,
    required this.controller,
    this.groupBuilder,
    this.itemKey,
    this.emptyMessage = '这里还没有内容',
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
  int _contentRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    load(1);
  }

  @override
  void dispose() {
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
        if (page == 1) {
          _items.clear();
          _contentRevision++;
        }
        final key = widget.itemKey;
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
  Widget build(BuildContext context) => ExpressivePageReveal(
    active: true,
    sliver: true,
    revision: (_first, _contentRevision, _items.isEmpty ? _error : null),
    child: _buildSliver(context),
  );

  Widget _buildSliver(BuildContext context) {
    if (_first && _items.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(height: 240, child: StateView.loading()),
      );
    }

    final err = _error;
    if (err != null && _items.isEmpty) {
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

    if (_items.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 240,
          child: StateView.empty(message: widget.emptyMessage),
        ),
      );
    }

    final footer = _error != null
        ? Center(
            child: AppButton(
              label: '加载失败，重试',
              variant: AppButtonVariant.plain,
              onPressed: () => load(_failedPage ?? _page + 1, refresh: true),
            ),
          )
        : ListFooter(loading: _loading, exhausted: !_hasNext);
    if (widget.groupBuilder == null) {
      // 平铺行自带屏幕边距与分隔线,列表不再加边距和分隔
      return SliverMainAxisGroup(
        slivers: [
          SliverList.builder(
            itemCount: _items.length,
            itemBuilder: (context, index) =>
                widget.itemBuilder(context, _items[index]),
          ),
          SliverToBoxAdapter(child: footer),
        ],
      );
    }
    final rows = _items.map((e) => widget.itemBuilder(context, e)).toList();
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
