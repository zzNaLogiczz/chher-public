/// 通用分页列表:把「首屏加载 / 下拉刷新 / 滚动追加 / 状态分流」收口到一处
///
/// 站点是真分页不是无限流,所以按页取;越界页码会被静默回落到第 1 页,
/// 因此是否还有下一页一律以响应里的 PageInfo 为准,不自己推算。
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';

import '../design/tokens.dart';
import '../models/models.dart';
import 'browse_controls.dart';
import 'expressive_controls.dart';
import 'state_view.dart';
import 'password_sheet.dart';

/// 加载一页。实现方负责把各自的响应类型适配成 `Paged<T>`。
typedef PageLoader<T> = Future<Paged<T>> Function(int page, {bool refresh});

class PagedList<T> extends StatefulWidget {
  final PageLoader<T> loader;

  /// 单项渲染。连续项之间的分隔与圆角面由 [groupBuilder] 决定。
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Legacy whole-group wrapper. It cannot virtualize arbitrary layouts.
  /// Prefer decorating individual items in itemBuilder for long lists.
  final Widget Function(BuildContext context, List<Widget> rows)? groupBuilder;

  /// 列表顶部附加内容,例如门户头图或筛选条
  final Widget? header;
  final String emptyMessage;
  final Future<bool> Function(int fid)? onPassword;
  final EdgeInsetsGeometry padding;

  const PagedList({
    super.key,
    required this.loader,
    required this.itemBuilder,
    this.groupBuilder,
    this.header,
    this.emptyMessage = '这里还没有内容',
    this.onPassword,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.screen,
      0,
      AppSpace.screen,
      24,
    ),
  });

  @override
  State<PagedList<T>> createState() => PagedListState<T>();
}

class PagedListState<T> extends State<PagedList<T>> {
  final _items = <T>[];

  int _page = 1;
  bool _hasNext = false;
  bool _loading = false;
  Object? _error;
  int? _failedPage;
  bool _firstLoadDone = false;
  int _contentRevision = 0;
  bool _unlocking = false;

  Future<void> _unlock(PageMessage message) async {
    final fid = message.fid;
    if (_unlocking || fid == null) return;
    _unlocking = true;
    try {
      final success =
          await (widget.onPassword?.call(fid) ??
              showForumPasswordUnlock(context, fid));
      if (mounted && success) await refresh();
    } finally {
      _unlocking = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  /// 取某一页。page == 1 视为重置,其余为追加。
  Future<void> _load(int page, {bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (page == 1) _error = null;
    });

    try {
      final result = await widget.loader(page, refresh: refresh);
      if (!mounted) return;
      setState(() {
        if (page > 1 && (result.page.current != page || result.items.isEmpty)) {
          _hasNext = false;
          return;
        }
        if (page == 1) {
          _items.clear();
          _contentRevision++;
        }
        _items.addAll(result.items);
        // 当前页以响应为准:请求第 5 页可能被站点回落到第 1 页
        _page = result.page.current;
        _hasNext = result.page.hasNext;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _failedPage = page;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _firstLoadDone = true;
        });
      }
    }
  }

  Future<void> refresh() => _load(1, refresh: true);

  @override
  Widget build(BuildContext context) {
    final err = _error;
    final headerCount = widget.header == null ? 0 : 1;
    final rowCount = widget.groupBuilder == null ? _items.length : 1;
    return ExpressivePageReveal(
      active: true,
      revision: (_firstLoadDone, _contentRevision, _items.isEmpty ? err : null),
      child: RefreshIndicator(
        onRefresh: refresh,
        child: BrowsePaginationObserver(
          enabled: !_loading && _hasNext && _error == null,
          threshold: 320,
          onLoadMore: () => _load(_page + 1),
          child: ListView.builder(
            primary: true,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            itemCount: headerCount + (_items.isEmpty ? 1 : rowCount + 1),
            itemBuilder: (context, rawIndex) {
              if (headerCount == 1 && rawIndex == 0) return widget.header!;
              final index = rawIndex - headerCount;
              if (_items.isEmpty) {
                Widget state;
                if (!_firstLoadDone) {
                  state = StateView.loading();
                } else if (err is PageMessage) {
                  state = StateView.forMessage(
                    err,
                    onPassword: () => _unlock(err),
                    onLogin: () async {
                      await Navigator.of(context).pushNamed('/login');
                      if (mounted) await refresh();
                    },
                  );
                } else if (err != null) {
                  state = StateView.error(err, onRetry: refresh);
                } else {
                  state = StateView.empty(message: widget.emptyMessage);
                }
                return SizedBox(height: 320, child: state);
              }
              if (index < rowCount) {
                final group = widget.groupBuilder;
                if (group != null) {
                  return group(
                    context,
                    _items.map((e) => widget.itemBuilder(context, e)).toList(),
                  );
                }
                return widget.itemBuilder(context, _items[index]);
              }
              if (err != null) {
                return Center(
                  child: AppButton(
                    label: '加载失败，重试',
                    variant: AppButtonVariant.plain,
                    onPressed: () =>
                        _load(_failedPage ?? _page + 1, refresh: true),
                  ),
                );
              }
              return ListFooter(loading: _loading, exhausted: !_hasNext);
            },
          ),
        ),
      ),
    );
  }
}
