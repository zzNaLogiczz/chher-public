/// Portal comments and source-linked forum discussions remain distinct.
library;

import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../ui/app_button.dart';
import '../design/icons.dart';
import '../ui/bottom_bar.dart';
import '../ui/chrome_button.dart';
import '../design/typography.dart';
import '../ui/reading_bar.dart';
import '../ui/sheet_scaffold.dart';
import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:solar_icons/solar_icons.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

import '../data/article_comment_index.dart';
import '../data/article_discussion_repository.dart';
import '../design/tokens.dart';
import '../di.dart';
import '../models/article_discussion.dart';
import '../models/models.dart';
import '../widgets/article_reply_sheet.dart';
import '../widgets/article_discussion_widgets.dart';
import '../widgets/comment_mode_bar.dart';
import '../widgets/composer_sheet.dart' show showPostResult;
import '../widgets/state_view.dart';
import 'thread_detail_page.dart';

class ArticleDiscussionPage extends StatefulWidget {
  final int aid;
  final String title;
  final bool _asSheet;

  /// These optional adapters keep interaction tests independent of real accounts.
  final Future<ArticleDiscussion> Function(int page, bool refresh)? loadPage;
  final Future<PostResult> Function(String message, ArticleComment? replyTo)?
  submitReply;
  final bool Function()? isLoggedIn;
  final Future<void> Function(BuildContext context)? onLogin;

  const ArticleDiscussionPage({
    super.key,
    required this.aid,
    required this.title,
    this.loadPage,
    this.submitReply,
    this.isLoggedIn,
    this.onLogin,
  }) : _asSheet = false;

  const ArticleDiscussionPage._sheet({
    required this.aid,
    required this.title,
    this.loadPage,
    this.submitReply,
    this.isLoggedIn,
    this.onLogin,
  }) : _asSheet = true;

  /// A real draggable discussion sheet; the page constructor remains available
  /// for independent navigation and offline previews.
  static Future<void> show(
    BuildContext context, {
    required int aid,
    required String title,
    Future<ArticleDiscussion> Function(int page, bool refresh)? loadPage,
    Future<PostResult> Function(String message, ArticleComment? replyTo)?
    submitReply,
    bool Function()? isLoggedIn,
    Future<void> Function(BuildContext context)? onLogin,
  }) async {
    final t = AppTokens.of(context);
    await Navigator.of(context).push<void>(
      ModalSheetRoute<void>(
        builder: (_) => ArticleDiscussionPage._sheet(
          aid: aid,
          title: title,
          loadPage: loadPage,
          submitReply: submitReply,
          isLoggedIn: isLoggedIn,
          onLogin: onLogin,
        ),
        barrierDismissible: true,
        barrierColor: t.scrim,
        barrierLabel: '关闭讨论',
        swipeDismissible: true,
        swipeDismissSensitivity: const SwipeDismissSensitivity(
          minFlingVelocityRatio: 1.6,
          dismissalOffset: SheetOffset(.32),
        ),
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.sheetDuration,
        transitionCurve: AppMotion.sheetCurve,
        viewportBuilder: (context, child) => SheetViewport(
          padding: EdgeInsets.only(
            top: MediaQuery.viewPaddingOf(context).top + 8,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  State<ArticleDiscussionPage> createState() => _ArticleDiscussionPageState();
}

class _ArticleDiscussionPageState extends State<ArticleDiscussionPage>
    with TickerProviderStateMixin {
  late final _repository = ArticleDiscussionRepository(chhClient);
  final _scroll = ScrollController();
  final _sheet = SheetController();
  final _sheetExpanded = ValueNotifier<bool>(false);
  double _fullExtent = 1;
  ScrollController? _sheetScroll;
  bool _loadCheckQueued = false;
  final _items = <ArticleComment>[];
  final _drafts = <int, String>{};
  ArticleDiscussion? _discussion;
  Object? _error;
  bool _first = true;
  bool _composerOpen = false;
  bool _loading = false;
  bool _hasNext = false;
  int _page = 0;

  /// 查看方式与帖子一致:评论(按引用归组)/ 原楼层 / 只看作者
  CommentViewMode _mode = CommentViewMode.threaded;
  ArticleCommentIndex _index = ArticleCommentIndex.empty;
  List<_CommentEntry> _entries = const [];

  /// 已作为一级评论展示过的 cid:后续分页揭示其引用对象时也不搬走
  final _pinnedRoots = <int>{};
  final _visibleReplies = <int, int>{};

  /// 本次展开新出现的回复,从上往下展开
  final _revealing = <int>{};
  late final _replyReveal =
      AnimationController(
        vsync: this,
        duration: AppMotion.revealDuration,
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _revealing.isNotEmpty) {
          setState(_revealing.clear);
        }
      });
  late final _replyRevealCurve = CurvedAnimation(
    parent: _replyReveal,
    curve: AppMotion.revealCurve,
  );

  /// 切换查看方式时评论区淡入;控件所在的头部不动
  late final _modeFade = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: 1,
  );
  late final _modeOpacity = CurvedAnimation(
    parent: _modeFade,
    curve: Curves.easeOut,
  );

  bool get _forumOnly => _discussion?.forumOnly ?? false;

  bool get _showModes => !_forumOnly && _items.isNotEmpty;

  bool get _loggedIn => widget.isLoggedIn?.call() ?? chhSession.loggedIn;

  @override
  void initState() {
    super.initState();
    if (!widget._asSheet) _scroll.addListener(_checkLoadMore);
    _sheet.addListener(_sheetChanged);
    _load(1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _fullExtent = (media.size.height - media.viewPadding.top - 8).clamp(
      1.0,
      double.infinity,
    );
  }

  void _sheetChanged() {
    final expanded = (_sheet.value ?? 0) > _fullExtent * .84;
    if (_sheetExpanded.value != expanded) _sheetExpanded.value = expanded;
  }

  @override
  void dispose() {
    _sheet.dispose();
    _sheetExpanded.dispose();
    _scroll.dispose();
    _replyRevealCurve.dispose();
    _replyReveal.dispose();
    _modeOpacity.dispose();
    _modeFade.dispose();
    super.dispose();
  }

  /// 按当前查看方式重排已加载的评论
  void _rebuildEntries() {
    _index = ArticleCommentIndex.build(_items, pinnedRoots: _pinnedRoots);
    _pinnedRoots.addAll(_index.roots.map((c) => c.cid));
    final discussion = _discussion;
    _entries = switch (_mode) {
      CommentViewMode.floors => [for (final c in _items) _CommentEntry(c)],
      CommentViewMode.author => [
        for (final c in _items)
          if (discussion?.byAuthor(c) ?? false) _CommentEntry(c),
      ],
      CommentViewMode.threaded => [
        for (final root in _index.roots) ..._threadedEntries(root),
      ],
    };
  }

  Iterable<_CommentEntry> _threadedEntries(ArticleComment root) sync* {
    yield _CommentEntry(root);
    final replies = _index.repliesFor(root.cid);
    final visible = (_visibleReplies[root.cid] ?? 0).clamp(0, replies.length);
    for (var i = 0; i < visible; i++) {
      yield _CommentEntry(replies[i], nested: true);
    }
    if (visible < replies.length) {
      yield _CommentEntry(root, expander: replies.length - visible);
    }
  }

  void _finishReplyReveal() {
    _revealing.clear();
    _replyReveal.value = 1;
  }

  /// 切换查看方式:控件固定在头部,新内容从列表顶部开始并淡入
  void _setMode(CommentViewMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _visibleReplies.clear();
      _finishReplyReveal();
      _rebuildEntries();
    });
    final controller = widget._asSheet ? _sheetScroll : _scroll;
    if (controller != null &&
        controller.hasClients &&
        controller.positions.length == 1) {
      controller.jumpTo(0);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _modeFade.value = 1;
    } else {
      _modeFade.forward(from: 0);
    }
    // 只看作者可能需要继续读后面的分页才能找到作者的评论
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLoadMore());
  }

  /// 楼内展开:每次最多追加 10 条,新出现的回复从上往下展开
  void _expandReplies(int rootCid) {
    if (_replyReveal.isAnimating) return;
    final before = _visibleReplies[rootCid] ?? 0;
    final total = _index.repliesFor(rootCid).length;
    setState(() {
      _visibleReplies[rootCid] = (before + 10).clamp(0, total);
      _rebuildEntries();
      if (!MediaQuery.disableAnimationsOf(context)) {
        _revealing.addAll(
          _index.repliesFor(rootCid).skip(before).take(10).map((c) => c.cid),
        );
        _replyReveal.forward(from: 0);
      }
    });
  }

  Future<void> _load(int page, {bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = widget.loadPage == null
          ? await _repository.load(widget.aid, page: page, refresh: refresh)
          : await widget.loadPage!(page, refresh);
      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _items.clear();
          // 重新读第 1 页(刷新、发表后)可以重新归组
          _pinnedRoots.clear();
          _visibleReplies.clear();
          _finishReplyReveal();
        }
        final seen = _items.map((c) => c.cid).toSet();
        final additions = data.items.where((c) => seen.add(c.cid)).toList();
        _items.addAll(additions);
        _discussion = data;
        _rebuildEntries();
        // Some source pages silently return page 1 when the end is exceeded.
        _hasNext =
            data.page.hasNext &&
            data.page.current >= page &&
            additions.isNotEmpty;
        _page = data.page.current;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _first = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkLoadMore());
      }
    }
  }

  void _checkLoadMore() {
    if (!mounted || _loading || !_hasNext || _error != null) return;
    final controller = widget._asSheet ? _sheetScroll : _scroll;
    final after =
        controller != null &&
            controller.hasClients &&
            controller.positions.length == 1
        ? controller.position.extentAfter
        : double.infinity;
    if (after < 400) _load(_page + 1);
  }

  void _queueSheetLoadCheck(ScrollMetrics metrics) {
    if (!widget._asSheet || metrics.axis != Axis.vertical) return;
    if (_loadCheckQueued) return;
    _loadCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCheckQueued = false;
      _checkLoadMore();
    });
  }

  Future<void> _login() async {
    if (widget.onLogin != null) {
      await widget.onLogin!(context);
    } else {
      await Navigator.of(context).pushNamed('/login');
      if (!mounted) return;
      await chhSession.refresh();
    }
    if (mounted) setState(() {});
  }

  Future<void> _openComposer([ArticleComment? target]) async {
    if (_composerOpen) return;
    _composerOpen = true;
    try {
      await _composeReply(target);
    } finally {
      _composerOpen = false;
    }
  }

  Future<void> _composeReply(ArticleComment? target) async {
    if (!_loggedIn) {
      await _login();
      if (!mounted || !_loggedIn) return;
      await _load(1, refresh: true);
      if (!mounted) return;
    }
    final issue = _discussion?.replyIssue;
    if (issue != null && issue.kind != PostResultKind.loginRequired) {
      showPostResult(context, issue);
      return;
    }
    final draftKey = target?.cid ?? 0;
    final result = await ArticleReplySheet.show(
      context,
      initialText: _drafts[draftKey] ?? '',
      onDraftChanged: (text) => _drafts[draftKey] = text,
      quoteAuthor: target?.author,
      quoteText: target?.text,
      onLogin: _login,
      onSubmit: (message) => widget.submitReply == null
          ? _repository.reply(widget.aid, message, replyTo: target)
          : widget.submitReply!(message, target),
    );
    if (!mounted || result == null) return;
    if (result.kind == PostResultKind.unknown) {
      await _load(1, refresh: true);
      return;
    }
    if (result.isSuccess) {
      _drafts.remove(draftKey);
      showPostResult(context, result);
      await _load(1, refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (widget._asSheet) return _sheetPresentation(t);
    return Scaffold(
      appBar: AppBar(
        title: _titleRow(t),
        leading: Navigator.canPop(context)
            ? ChromeButton(
                icon: AppIcons.back,
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showModes) _modeBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(1, refresh: true),
              child: _discussionBody(t),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _composeDock(t),
    );
  }

  /// 与帖子评论区同一个三段控件;认不出作者时只有前两段
  Widget _modeBar() => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, 12),
    child: CommentModeBar(
      mode: _mode,
      onChanged: _setMode,
      authorLabel: '只看作者',
      showAuthor: _discussion?.knowsAuthor ?? false,
    ),
  );

  Widget _discussionBody(AppTokens t) {
    final scrollView = CustomScrollView(
      controller: widget._asSheet ? null : _scroll,
      primary: widget._asSheet ? true : null,
      physics: widget._asSheet
          ? const ClampingScrollPhysics()
          : const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
        if (_discussion?.threadId != null)
          SliverToBoxAdapter(child: _threadEntry(t)),
        if (_first)
          SliverFillRemaining(hasScrollBody: false, child: StateView.loading())
        else if (_error != null && _items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _error is PageMessage
                ? StateView.forMessage(_error as PageMessage, onLogin: _login)
                : StateView.error(
                    _error!,
                    onRetry: () => _load(1, refresh: true),
                  ),
          )
        else if (_items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: StateView.empty(
              message: _forumOnly ? '这篇内容的讨论在论坛原帖中' : '暂时没有评论，写下你的看法',
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            // 每种查看方式一个新列表:回到顶部时不沿用旧行的布局偏移,
            // 否则滚动校正会把位置"保留"在旧内容的高度上
            sliver: SliverList.builder(
              key: ValueKey(_mode),
              itemCount: _entries.length,
              itemBuilder: (context, index) => FadeTransition(
                opacity: _modeOpacity,
                child: _entryView(t, index),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(opacity: _modeOpacity, child: _tail(t)),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
    if (!widget._asSheet) return scrollView;
    return Builder(
      builder: (bodyContext) {
        // Observe the package-owned primary controller; supplying our own would
        // disconnect the list from smooth_sheets' gesture coordination.
        _sheetScroll = PrimaryScrollController.maybeOf(bodyContext);
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) {
              _queueSheetLoadCheck(notification.metrics);
            }
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) {
                _queueSheetLoadCheck(notification.metrics);
              }
              return false;
            },
            child: scrollView,
          ),
        );
      },
    );
  }

  Widget _entryView(AppTokens t, int index) {
    final entry = _entries[index];
    final comment = entry.comment;
    if (entry.expander > 0) return _expander(entry);
    final grouped = _mode == CommentViewMode.threaded;
    final tile = ArticleCommentTile(
      key: ValueKey('comment-${comment.cid}'),
      comment: comment,
      nested: entry.nested,
      // 归组已表达回复关系时不再重复引文;认不出对象的引用仍保留
      hideQuotes: grouped && entry.nested,
      replyToAuthor: grouped ? _index.replyToAuthor(comment.cid) : null,
      byAuthor: _discussion?.byAuthor(comment) ?? false,
      onReply: () => _openComposer(comment),
    );
    final view = entry.nested
        ? Padding(padding: const EdgeInsets.only(left: 38), child: tile)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (index > 0)
                Divider(height: .5, thickness: .5, color: t.separator),
              tile,
            ],
          );
    if (!_revealing.contains(comment.cid) || !entry.nested) return view;
    return SizeTransition(
      sizeFactor: _replyRevealCurve,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _replyRevealCurve, child: view),
    );
  }

  Widget _expander(_CommentEntry entry) {
    final visible = _visibleReplies[entry.comment.cid] ?? 0;
    final remaining = entry.expander;
    return Padding(
      padding: const EdgeInsets.only(left: 38, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppButton(
          key: ValueKey('article-expand-replies-${entry.comment.cid}'),
          label: visible == 0 ? '展开 $remaining 条回复' : '展开更多回复（$remaining）',
          variant: AppButtonVariant.plain,
          icon: AppIcons.down,
          onPressed: () => _expandReplies(entry.comment.cid),
        ),
      ),
    );
  }

  Widget _sheetPresentation(AppTokens t) => Sheet(
    controller: _sheet,
    initialOffset: const SheetOffset(.62),
    snapGrid: const SheetSnapGrid(snaps: [SheetOffset(.62), SheetOffset(1)]),
    scrollConfiguration: const SheetScrollConfiguration(),
    decoration: SheetDecorationBuilder(
      size: SheetSize.stretch,
      builder: (context, child) => AppSheetSurface(child: child),
    ),
    child: SheetContentScaffold(
      backgroundColor: t.surface,
      topBar: _sheetHeader(t),
      body: SizedBox.expand(
        child: RefreshIndicator(
          color: t.accent,
          backgroundColor: t.surface,
          onRefresh: () => _load(1, refresh: true),
          child: _discussionBody(t),
        ),
      ),
      bottomBarVisibility: const BottomBarVisibility.always(
        ignoreBottomInset: true,
      ),
      bottomBar: _composeDock(t),
    ),
  );

  /// 头部只有标题与关闭;文章名一行;展开靠拖动,刷新靠下拉
  String get _heading => _forumOnly ? '原帖讨论' : '评论';

  /// 页面模式的标题:与弹层头部一致,标题 + text3 计数
  Widget _titleRow(AppTokens t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(_heading),
      if (_discussion?.total != null) ...[
        const SizedBox(width: 6),
        Text('${_discussion!.total}', style: TextStyle(color: t.text3)),
      ],
    ],
  );

  Widget _sheetHeader(AppTokens t) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SheetHeader(
        title: _heading,
        count: _discussion?.total,
        contextLine: widget.title,
        closeTooltip: '关闭讨论',
        grabberKey: const ValueKey('discussion-sheet-grip'),
      ),
      // 控件固定在头部,滚到哪里都能切换
      if (_showModes) _modeBar(),
    ],
  );

  /// 底部只有一个 fill 底输入胶囊;原帖讨论时进入论坛原帖回复
  Widget _composeDock(AppTokens t) => BottomBar(
    child: ComposeCapsule(
      key: const ValueKey('discussion-write-action'),
      placeholder: _forumOnly ? '进入原帖回复' : (_loggedIn ? '写评论…' : '登录后参与讨论'),
      color: t.fill,
      onTap: _first && _loading
          ? null
          : (_forumOnly ? _openThread : _openComposer),
    ),
  );

  void _openThread() {
    final discussion = _discussion;
    if (discussion?.threadId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailPage(
          tid: discussion!.threadId!,
          fid: discussion.forumId,
          title: widget.title,
        ),
      ),
    );
  }

  Widget _threadEntry(AppTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
    child: CupertinoButton(
      padding: const EdgeInsets.all(16),
      color: t.accentFill,
      borderRadius: BorderRadius.circular(AppRadii.md),
      pressedOpacity: .85,
      onPressed: _openThread,
      child: Row(
        children: [
          Icon(SolarIconsBold.chatRoundDots, color: t.accent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '论坛跟帖',
                  style: TextStyle(
                    fontSize: AppType.sizeBody,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _forumOnly ? '在原帖中参与讨论' : '查看关联的论坛讨论',
                  style: TextStyle(
                    fontSize: AppType.sizeFootnote,
                    color: t.text2,
                  ),
                ),
              ],
            ),
          ),
          Icon(SolarIconsBold.altArrowRight, size: 20, color: t.accent),
        ],
      ),
    ),
  );

  Widget _tail(AppTokens t) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '评论加载失败',
              style: TextStyle(fontSize: AppType.sizeFootnote, color: t.text2),
            ),
            AppButton(
              label: '重试',
              variant: AppButtonVariant.plain,
              onPressed: () => _load(_page + 1),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: StateView.loading(),
      );
    }
    if (!_hasNext) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _entries.isEmpty && _mode == CommentViewMode.author
                ? '作者还没有发表评论'
                : '已显示全部评论',
            style: TextStyle(fontSize: AppType.sizeFootnote, color: t.text3),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// 列表中的一行:一条评论,或某条一级评论下"展开 N 条回复"的按钮
class _CommentEntry {
  final ArticleComment comment;
  final bool nested;

  /// 大于 0 时是展开按钮,值为尚未显示的回复数
  final int expander;

  const _CommentEntry(this.comment, {this.nested = false, this.expander = 0});
}
