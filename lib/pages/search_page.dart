/// A compact search workspace with real session history and a lazy result stream.
library;

import 'package:flutter/material.dart';
import '../design/icons.dart';
import '../ui/editor_touch.dart';
import '../ui/app_button.dart';
import '../ui/plain_rows.dart';
import '../ui/chrome_button.dart';
import '../design/typography.dart';
import 'package:solar_icons/solar_icons.dart';

import '../di.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../widgets/browse_controls.dart' show BrowsePaginationObserver;
import '../widgets/search_workspace.dart';
import '../widgets/expressive_controls.dart';
import 'thread_detail_page.dart';

class SearchPage extends StatefulWidget {
  final String initialQuery;
  final Future<SearchResultPage> Function(String keyword)? search;
  final Future<SearchResultPage> Function(SearchResultPage previous)?
  searchNext;
  final ValueChanged<ThreadSummary>? onOpenThread;
  final String? entryHeroTag;
  final bool autofocus;
  const SearchPage({
    super.key,
    this.initialQuery = '',
    this.search,
    this.searchNext,
    this.onOpenThread,
    this.entryHeroTag,
    this.autofocus = false,
  });
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final _input = TextEditingController(text: widget.initialQuery);
  final _focus = FocusNode();
  final _rows = <ThreadSummary>[];
  final _seen = <int>{};
  SearchResultPage? _last;
  bool _loading = false;
  bool _searched = false;
  Object? _error;
  Object? _moreError;
  String _submitted = '';
  int _request = 0;
  Animation<double>? _entryAnimation;
  AnimationStatusListener? _entryListener;
  bool _entryFocused = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindEntryFocus();
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autofocus && widget.autofocus) _bindEntryFocus();
  }

  void _bindEntryFocus() {
    if (!widget.autofocus || _entryFocused) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _queueEntryFocus();
      return;
    }
    if (identical(_entryAnimation, animation)) return;
    if (_entryListener != null) {
      _entryAnimation?.removeStatusListener(_entryListener!);
    }
    _entryAnimation = animation;
    _entryListener = (status) {
      if (status == AnimationStatus.completed) _queueEntryFocus();
    };
    animation.addStatusListener(_entryListener!);
  }

  void _queueEntryFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      final animation = route?.animation;
      if (animation != null && animation.status != AnimationStatus.completed) {
        _bindEntryFocus();
        return;
      }
      if (!mounted ||
          _entryFocused ||
          !widget.autofocus ||
          route?.isCurrent == false) {
        return;
      }
      // Hero replaces the destination child with a placeholder during flight.
      // Wait for the real field to reattach before marking autofocus complete.
      if (_focus.context?.mounted != true) {
        _queueEntryFocus();
        return;
      }
      _entryFocused = true;
      _focus.requestFocus();
      EditorTouch.notifyFromUserFocus(context, _focus);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _request++;
    if (_entryListener != null) {
      _entryAnimation?.removeStatusListener(_entryListener!);
    }
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _clear() {
    _request++;
    setState(() {
      _input.clear();
      _rows.clear();
      _seen.clear();
      _last = null;
      _loading = false;
      _error = null;
      _moreError = null;
      _searched = false;
      _submitted = '';
    });
    _focus.requestFocus();
    EditorTouch.notifyFromUserFocus(context, _focus);
  }

  void _submitKeyword(String keyword) {
    _input.value = TextEditingValue(
      text: keyword,
      selection: TextSelection.collapsed(offset: keyword.length),
    );
    _search();
  }

  Future<void> _search() async {
    final keyword = _input.text.trim();
    if (keyword.isEmpty || (_loading && keyword == _submitted)) return;
    _focus.unfocus();
    searchSessionHistory.remember(keyword);
    final request = ++_request;
    setState(() {
      _loading = true;
      _searched = true;
      _submitted = keyword;
      _error = null;
      _moreError = null;
      _rows.clear();
      _seen.clear();
      _last = null;
    });
    try {
      final response =
          await (widget.search?.call(keyword) ?? forumRepo.search(keyword));
      if (!mounted || request != _request) return;
      setState(() {
        _rows.addAll(response.rows.where((row) => _seen.add(row.tid)));
        _last = response;
      });
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final previous = _last;
    if (_loading || previous == null || previous.nextUrl == null) return;
    final request = _request;
    setState(() {
      _loading = true;
      _moreError = null;
    });
    try {
      final response =
          await (widget.searchNext?.call(previous) ??
              forumRepo.searchNext(previous));
      if (!mounted || request != _request) return;
      setState(() {
        final additions = response.rows
            .where((row) => _seen.add(row.tid))
            .toList();
        final repeated =
            response.page.current <= previous.page.current ||
            additions.isEmpty ||
            response.nextUrl == previous.nextUrl;
        if (response.page.current > previous.page.current) {
          _rows.addAll(additions);
        }
        _last = repeated
            ? SearchResultPage(
                rows: response.rows,
                page: PageInfo(current: response.page.current, hasNext: false),
              )
            : response;
      });
    } catch (error) {
      if (mounted && request == _request) setState(() => _moreError = error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  String get _phase {
    if (!_searched) return 'ready';
    if (_loading && _rows.isEmpty) return 'loading-$_request';
    if (_error != null && _rows.isEmpty) return 'error-$_request';
    return _rows.isEmpty ? 'empty-$_request' : 'results-$_request';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final canPop = Navigator.canPop(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 头部只有返回圆钮与搜索胶囊,由键盘搜索键提交
            Padding(
              padding: EdgeInsets.fromLTRB(
                canPop ? 12 : AppSpace.screen,
                8,
                AppSpace.screen,
                12,
              ),
              child: Row(
                children: [
                  if (canPop) ...[
                    ChromeButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.maybePop(context),
                      icon: AppIcons.back,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: SearchEntryHero(
                      tag: widget.entryHeroTag,
                      child: SearchWorkspaceInput(
                        controller: _input,
                        focusNode: _focus,
                        loading: _loading,
                        submitted: _submitted,
                        onSubmit: _search,
                        onClear: _clear,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_searched)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  0,
                  AppSpace.screen,
                  12,
                ),
                // 结果计数在左,搜索范围在右(源站只有全站帖子一种范围)
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _loading && _rows.isEmpty
                              ? '正在搜索'
                              : '已加载 ${_rows.length} 条',
                          style: AppType.footnote.copyWith(color: t.text2),
                        ),
                      ),
                    ),
                    Icon(SolarIconsOutline.global, size: 15, color: t.text3),
                    const SizedBox(width: 4),
                    Text(
                      '全站帖子',
                      style: AppType.footnote.copyWith(color: t.text3),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SearchStateReveal(
                key: ValueKey(_phase),
                child: _content(t),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(AppTokens t) {
    if (!_searched) return _ready(t);
    if (_loading && _rows.isEmpty) return const SearchLoadingPanel();
    final error = _error;
    if (error != null && _rows.isEmpty) return _failure(error);
    if (_rows.isEmpty) {
      return SearchStatusPanel(
        icon: SolarIconsBold.magnifier,
        title: '没有找到相关帖子',
        message: '试试更短的关键词，或换一种说法。',
        actionLabel: '修改关键词',
        onAction: () {
          _focus.requestFocus();
          _input.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _input.text.length,
          );
        },
      );
    }
    return BrowsePaginationObserver(
      enabled: !_loading && _last?.nextUrl != null && _moreError == null,
      onLoadMore: _loadMore,
      child: ListView.builder(
        key: ValueKey('search-results-$_request'),
        primary: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        itemCount: _rows.length + 1,
        itemBuilder: (context, index) {
          if (index == _rows.length) return _footer(t);
          final thread = _rows[index];
          return SearchResultCard(
            thread: thread,
            keyword: _submitted,
            onTap: () => _openThread(thread),
          );
        },
      ),
    );
  }

  void _openThread(ThreadSummary thread) {
    final open = widget.onOpenThread;
    if (open != null) {
      open(thread);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadDetailPage(
          tid: thread.tid,
          seenReplies: thread.replies,
          title: thread.title,
          fid: thread.forumFid,
        ),
      ),
    );
  }

  Widget _ready(AppTokens t) => ListenableBuilder(
    listenable: searchSessionHistory,
    builder: (context, _) {
      final history = searchSessionHistory.queries;
      return ListView(
        key: const PageStorageKey('search-ready'),
        primary: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
        children: [
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '还没有搜索记录',
                style: TextStyle(
                  fontSize: AppType.sizeFootnote,
                  color: t.text2,
                  height: 1.7,
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '最近搜索',
                    style: TextStyle(
                      fontSize: AppType.sizeBody,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
                AppButton(
                  label: '清空',
                  variant: AppButtonVariant.plain,
                  onPressed: searchSessionHistory.clear,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 最近搜索:平铺行(时钟图标 + 关键词),点按重新检索
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final query in history)
                  PlainRow(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                    onTap: () => _submitKeyword(query),
                    child: Row(
                      children: [
                        Icon(
                          SolarIconsOutline.history,
                          size: 18,
                          color: t.text3,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.callout.copyWith(color: t.text),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _failure(Object error) {
    if (error is PageMessage) {
      if (error.kind == PageMessageKind.loginRequired) {
        return SearchStatusPanel(
          icon: SolarIconsBold.lock,
          title: '登录后继续搜索',
          message: error.text,
          actionLabel: '登录',
          onAction: () async {
            await Navigator.pushNamed(context, '/login');
            if (mounted) _submitKeyword(_submitted);
          },
        );
      }
      return SearchStatusPanel(
        icon: SolarIconsBold.shieldWarning,
        title: error.kind == PageMessageKind.permissionDenied
            ? '没有访问权限'
            : '搜索暂不可用',
        message: error.text,
      );
    }
    return SearchStatusPanel(
      icon: SolarIconsBold.restart,
      title: '搜索没有完成',
      message: '请重试，或换一个关键词。',
      actionLabel: '重试',
      onAction: () => _submitKeyword(_submitted),
    );
  }

  Widget _footer(AppTokens t) {
    if (_moreError != null) {
      return Center(
        child: AppButton(
          label: '继续加载',
          variant: AppButtonVariant.plain,
          icon: SolarIconsBold.restart,
          onPressed: _loadMore,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: _loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: t.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在加载更多',
                    style: TextStyle(
                      fontSize: AppType.sizeFootnote,
                      color: t.text2,
                    ),
                  ),
                ],
              )
            : Text(
                _last?.nextUrl == null ? '没有更多结果' : '',
                style: TextStyle(
                  fontSize: AppType.sizeFootnote,
                  color: t.text3,
                ),
              ),
      ),
    );
  }
}
