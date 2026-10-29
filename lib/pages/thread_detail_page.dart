/// 连续楼层阅读：沿站点分页顺序追加，保留提醒的真实落地页与楼层定位。
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';
import '../design/typography.dart';
import '../ui/feedback.dart';

import '../core/app_log.dart';
import '../design/tokens.dart';
import 'package:motor/motor.dart';
import '../design/motion.dart';
import '../ui/reading_bar.dart';
import '../ui/chrome_button.dart';
import '../ui/nav_bar.dart';
import '../di.dart';
import '../models/models.dart';
import '../attachments/attachment_controller.dart';
import '../widgets/composer_sheet.dart';
import 'source_page_drawer.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/post_card.dart';
import '../widgets/state_view.dart';
import '../data/thread_conversation_index.dart';
import '../data/thread_read_index.dart';
import '../widgets/thread_comment_widgets.dart';

typedef ThreadPageLoader =
    Future<ThreadDetail> Function(int page, String? authorUid, bool refresh);
typedef ThreadGotoLoader = Future<ThreadDetail> Function(String url);
typedef ThreadReplySubmitter =
    Future<PostResult> Function({
      required int tid,
      required int fid,
      required String message,
      int? quotePid,
      int page,
    });

class ThreadDetailPage extends StatefulWidget {
  final int tid;
  final String title;
  final int initialPage;
  final int? fid;
  final int? seenReplies;
  final String? gotoUrl;
  final int? focusPid;
  final bool initialThreaded;

  /// 测试与离线预览可注入读取/提交；默认仍使用真实仓库。
  final ThreadPageLoader? loadPage;
  final ThreadGotoLoader? loadGoto;
  final ThreadReplySubmitter? submitReply;

  const ThreadDetailPage({
    super.key,
    required this.tid,
    required this.title,
    this.initialPage = 1,
    this.fid,
    this.seenReplies,
    this.gotoUrl,
    this.focusPid,
    this.initialThreaded = true,
    this.loadPage,
    this.loadGoto,
    this.submitReply,
  });

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage>
    with TickerProviderStateMixin {
  final _scroll = ScrollController();

  /// 顶栏渐隐与居中小标题跟随的滚动距离
  final _navOffset = ValueNotifier<double>(0);

  /// 评论区标题是否已滚到顶栏下方:决定阅读工具栏圆钮是"评论数"还是"回到顶部"
  final _inComments = ValueNotifier<bool>(false);
  final _commentsKey = GlobalKey();

  /// "回到顶部 / 跳到评论"的弹簧滚动;手指一碰列表就停
  late final SingleMotionController _scrollSpring;
  bool _springing = false;
  final _collapsedTitle = ValueNotifier<bool>(false);
  final _focusKey = GlobalKey();
  final _pages = <int, ThreadDetail>{};
  final _postPages = <int, int>{};
  final _knownPids = <int>{};
  final _entries = <_ThreadReadEntry>[];
  final _entryIndices = <String, int>{};
  ThreadDetail? _loadedDetail;
  String? _authorUid;
  String? _openingAuthor;
  bool _loading = true;
  bool _hasNext = false;
  bool _markedRead = false;
  bool _focusDone = false;
  bool _composerOpen = false;

  /// 回复里的图片,与文字草稿一样按回复目标保留,发送成功后清掉
  final _replyImages = <String, AttachmentController>{};

  /// 正在读取的查看方式(进出只看楼主要读网络):控件先选中它,计数处显示等待
  ThreadViewMode? _pendingMode;

  /// 进入只看楼主前已读的楼层;退出时原样还原,不重新读取
  _ReadSnapshot? _beforeAuthor;

  /// 新内容不足以让评论区标题停在原处时,末尾补的留白;滚出屏幕后收回
  double _tailSlack = 0;

  /// 切换查看方式时只淡化/淡入评论区,首楼和标题不动
  late final _commentsFade = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: 1,
  );
  late final _commentsOpacity = CurvedAnimation(
    parent: _commentsFade,
    curve: Curves.easeOut,
  );
  Object? _error;
  Object? _tailError;
  Object? _beforeError;
  int _generation = 0;
  int _authorEpoch = 0;
  bool _sourceMayHaveChanged = false;
  bool _authReloadQueued = false;
  late bool _sessionLoggedIn;
  late String? _sessionUid;

  late bool _threaded = widget.initialThreaded;
  late int? _focusTargetPid = widget.focusPid;
  late int? _highlightPid = widget.focusPid;
  bool _pauseHiddenAppend = false;
  final _pinnedRoots = <int>{};
  final _visibleReplies = <int, int>{};
  int? _expandingRoot;
  final _revealingEntries = <String>{};
  late final _replyReveal =
      AnimationController(
        vsync: this,
        duration: AppMotion.revealDuration,
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            _revealingEntries.isNotEmpty) {
          _update(_revealingEntries.clear);
        }
      });
  late final _replyRevealCurve = CurvedAnimation(
    parent: _replyReveal,
    curve: AppMotion.revealCurve,
  );
  List<Post> _orderedPosts = const [];
  late ThreadConversationIndex _index = ThreadConversationIndex.build(
    tid: widget.tid,
    posts: const [],
  );
  void _update(VoidCallback change) => setState(change);

  bool get _grouped => _threaded && _authorUid == null;

  void _finishReplyReveal() {
    _revealingEntries.clear();
    _replyReveal.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _finishReplyReveal();
  }

  String? _replyToAuthor(Post post) {
    if (!_grouped) return null;
    final resolution = _index.resolutionFor(post.pid);
    final target = resolution?.directTarget;
    if (resolution == null ||
        !resolution.isGroupedReply ||
        target == null ||
        target.tid != widget.tid ||
        target.pid == resolution.rootPid) {
      return null;
    }
    final author = _index.postsByPid[target.pid]?.author.trim();
    return author == null || author.isEmpty ? null : author;
  }

  void _rebuildReadIndex() {
    final seen = <int>{};
    final keys = _pages.keys.toList()..sort();
    _postPages.clear();
    final orderedPosts = <Post>[];
    for (final page in keys) {
      for (final post in _pages[page]!.posts) {
        if (seen.add(post.pid)) {
          _postPages[post.pid] = page;
          orderedPosts.add(post);
        }
      }
    }
    _knownPids
      ..clear()
      ..addAll(seen);
    _orderedPosts = List.unmodifiable(orderedPosts);
    final complete =
        _authorUid == null &&
        !_sourceMayHaveChanged &&
        _pages.containsKey(1) &&
        _pages[_pages.keys.reduce((a, b) => a > b ? a : b)]?.page.hasNext ==
            false;
    _index = ThreadConversationIndex.build(
      tid: widget.tid,
      posts: orderedPosts,
      sourceComplete: complete,
      pinnedRootPids: _pinnedRoots,
    );
    _pinnedRoots.addAll(_index.roots.map((p) => p.pid));
    _entries.clear();
    _entryIndices.clear();
    var commentsStarted = false;
    for (final post in _grouped ? _index.roots : orderedPosts) {
      if (!postIsOpening(post) && !commentsStarted) {
        commentsStarted = true;
        _entries.add(_ThreadReadEntry(post, _ThreadEntryKind.commentsHeading));
      }
      _addPostEntries(post);
      if (_grouped && !postIsOpening(post)) {
        final replies = _index.repliesFor(post.pid);
        final visible = (_visibleReplies[post.pid] ?? 0).clamp(
          0,
          replies.length,
        );
        for (var i = 0; i < visible; i++) {
          _addPostEntries(replies[i], nested: true);
        }
        // Source pages contain mixed conversations, so the source-wide total
        // must never be advertised as this root's remaining reply count.
        if (replies.isNotEmpty || _visibleReplies.containsKey(post.pid)) {
          _entries.add(_ThreadReadEntry(post, _ThreadEntryKind.replies));
        }
      }
    }
    // 查看方式切换在评论区标题上;只有首楼(例如只看楼主时)也必须给出标题,
    // 否则用户无法切回评论或原楼层
    if (!commentsStarted && orderedPosts.isNotEmpty) {
      _entries.add(
        _ThreadReadEntry(orderedPosts.last, _ThreadEntryKind.commentsHeading),
      );
    }
    for (var i = 0; i < _entries.length; i++) {
      _entryIndices[_entries[i].key] = i + 1;
    }
  }

  void _addPostEntries(Post post, {bool nested = false}) {
    final hideQuotes =
        !postIsOpening(post) &&
        (_grouped || _index.directTargetFor(post.pid) != null);
    final blocks = hideQuotes
        ? post.content.where((block) => block is! QuoteBlock).toList()
        : post.content;
    final images = blocks.whereType<ImageBlock>().map((b) => b.url).toList();
    if (!postIsOpening(post) && images.length <= 3 && blocks.length <= 12) {
      _entries.add(
        _ThreadReadEntry(post, _ThreadEntryKind.whole, nested: nested),
      );
      return;
    }
    final gallery = List<String>.unmodifiable(images);
    _entries.add(
      _ThreadReadEntry(post, _ThreadEntryKind.header, nested: nested),
    );
    var imageIndex = 0;
    for (var n = 0; n < blocks.length; n++) {
      final block = blocks[n];
      _entries.add(
        _ThreadReadEntry(
          post,
          _ThreadEntryKind.block,
          block: block,
          blockIndex: n,
          gallery: gallery,
          imageIndex: imageIndex,
          nested: nested,
        ),
      );
      if (block is ImageBlock) imageIndex++;
    }
    _entries.add(
      _ThreadReadEntry(post, _ThreadEntryKind.footer, nested: nested),
    );
  }

  int get _firstPage => _pages.keys.reduce((a, b) => a < b ? a : b);
  int get _lastPage => _pages.keys.reduce((a, b) => a > b ? a : b);

  @override
  void initState() {
    super.initState();
    // 即使首屏加载失败或中途退出,也必须在可用的生命周期里创建 ticker。
    _scrollSpring = SingleMotionController(
      motion: AppMotion.reveal,
      vsync: this,
      initialValue: 0,
    )..addListener(_followSpring);
    _scroll.addListener(_handleScroll);
    _sessionLoggedIn = chhSession.loggedIn;
    _sessionUid = chhSession.badges.uid;
    chhSession.addListener(_sessionChanged);
    _loadInitial(useGoto: true);
  }

  void _sessionChanged() {
    final loggedIn = chhSession.loggedIn;
    final uid = chhSession.badges.uid;
    final changed =
        loggedIn != _sessionLoggedIn ||
        (_sessionUid != null && uid != null && uid != _sessionUid);
    _sessionLoggedIn = loggedIn;
    _sessionUid = loggedIn ? (uid ?? _sessionUid) : null;
    if (!changed || !mounted) return;
    _generation++;
    _authorEpoch++;
    _update(() {
      _pages.clear();
      _postPages.clear();
      _pinnedRoots.clear();
      _visibleReplies.clear();
      _finishReplyReveal();
      _expandingRoot = null;
      _loadedDetail = null;
      _openingAuthor = null;
      _authorUid = null;
      _pendingMode = null;
      _beforeAuthor = null;
      _tailSlack = 0;
      _commentsFade.value = 1;
      _hasNext = false;
      _error = null;
      _tailError = null;
      _beforeError = null;
      _loading = true;
      _rebuildReadIndex();
    });
    if (_authReloadQueued) return;
    _authReloadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authReloadQueued = false;
      if (mounted) _loadInitial(useGoto: widget.gotoUrl != null, refresh: true);
    });
  }

  void _handleScroll() {
    if (_scroll.hasClients) {
      final collapsed = _scroll.offset > 140;
      if (_collapsedTitle.value != collapsed) _collapsedTitle.value = collapsed;
      _navOffset.value = _scroll.offset;
      _syncInComments();
      // 末尾留白已完全滚出屏幕:收回不会移动当前内容
      if (_tailSlack > 0 && _scroll.position.extentAfter > _tailSlack + 1) {
        _update(() => _tailSlack = 0);
      }
    }
    _considerAppend();
  }

  // 评论区标题被滚到顶栏下方即算进入评论区;标题已被回收时保持上一次的判断
  void _syncInComments() {
    final box = _commentsKey.currentContext?.findRenderObject() as RenderBox?;
    final barBottom = MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
    if (box != null && box.attached) {
      // 记下标题抵达顶栏时的滚动位置,标题被回收后仍能判断
      _commentsAt =
          _scroll.offset + box.localToGlobal(Offset.zero).dy - barBottom;
    }
    final at = _commentsAt;
    if (at == null) return;
    // 内容不够长时标题到不了顶栏;滚到页面底部也算进入评论区
    final position = _scroll.position;
    final atEnd =
        position.pixels > 0 && position.pixels >= position.maxScrollExtent - 1;
    final inside = _scroll.offset >= at - 1 || atEnd;
    if (_inComments.value != inside) _inComments.value = inside;
  }

  double? _commentsAt;

  void _followSpring() {
    if (_springing && _scroll.hasClients) {
      final position = _scroll.position;
      _scroll.jumpTo(
        _scrollSpring.value.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
  }

  void _springScrollTo(double target) {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return;
    }
    _springing = true;
    _scrollSpring.value = _scroll.offset;
    _scrollSpring.animateTo(target).whenComplete(() => _springing = false);
  }

  void _stopSpring() {
    if (!_springing) return;
    _springing = false;
    _scrollSpring.stop();
  }

  void _backToTop() => _springScrollTo(0);

  /// 跳到评论区:标题尚未构建时先按屏高逐步前移,直到标题出现再对齐到顶栏下方
  Future<void> _showComments() async {
    if (!_scroll.hasClients) return;
    for (var i = 0; i < 40 && _commentsKey.currentContext == null; i++) {
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) break;
      _scroll.jumpTo(
        (position.pixels + position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final box = _commentsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final barBottom = MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
    final delta = box.localToGlobal(Offset.zero).dy - barBottom - 8;
    final position = _scroll.position;
    _springScrollTo(
      (position.pixels + delta).clamp(0, position.maxScrollExtent),
    );
  }

  ThreadViewMode get _viewMode => _authorUid != null
      ? ThreadViewMode.author
      : _threaded
      ? ThreadViewMode.threaded
      : ThreadViewMode.floors;

  /// 控件上显示的方式:读取中的目标优先
  ThreadViewMode get _shownMode => _pendingMode ?? _viewMode;

  /// 三种查看方式互斥。切换时评论区标题停在屏幕原处,只替换它下方的评论;
  /// 新的选择会取消尚未完成的读取
  Future<void> _setViewMode(ThreadViewMode mode) async {
    if (mode == _shownMode) return;
    final anchor = _headingDy();
    if (_pendingMode != null) {
      _authorEpoch++;
      _update(() => _pendingMode = null);
      if (mode == _viewMode) {
        _fadeComments(to: 1);
        return;
      }
    }
    if (mode == ThreadViewMode.author) {
      await _enterAuthorMode(anchor);
    } else if (_authorUid != null) {
      await _leaveAuthorMode(mode == ThreadViewMode.threaded, anchor);
    } else {
      _regroup(mode == ThreadViewMode.threaded);
      _settleAfterSwitch(anchor);
    }
  }

  /// 评论 ⇄ 原楼层:只对已读楼层重新排列,不读网络
  void _regroup(bool threaded) {
    _update(() {
      _threaded = threaded;
      _pinnedRoots.clear();
      _visibleReplies.clear();
      _finishReplyReveal();
      _expandingRoot = null;
      _pauseHiddenAppend = false;
      _rebuildReadIndex();
    });
  }

  /// 进入只看楼主:控件先选中并淡化当前评论,读到楼主的楼层后再替换;
  /// 失败退回原方式,已读内容原样保留
  Future<void> _enterAuthorMode(double? anchor) async {
    final epoch = ++_authorEpoch;
    // 丢弃进行中的翻页,旧方式的回包不能混进新内容
    _generation++;
    _update(() {
      _pendingMode = ThreadViewMode.author;
      _loading = false;
    });
    _fadeComments(to: .4);
    try {
      // 通知可能落在中段,只取首屏确认楼主,不把当前回复作者当作楼主
      final owner = _openingAuthor ?? await _lookupOpeningAuthor();
      if (!mounted || epoch != _authorEpoch) return;
      if (owner == null) throw StateError('opening author unknown');
      final detail = await _readAs(owner, 1);
      if (!mounted || epoch != _authorEpoch) return;
      final snapshot = _ReadSnapshot(Map.of(_pages), _hasNext, _loadedDetail);
      _update(() {
        _beforeAuthor = snapshot;
        _authorUid = owner;
        _threaded = false;
        _pendingMode = null;
        _resetPages(detail);
      });
      _settleAfterSwitch(anchor);
    } catch (_) {
      if (!mounted || epoch != _authorEpoch) return;
      _update(() => _pendingMode = null);
      _fadeComments(to: 1);
      AppToast.show(context, '暂时无法读取楼主的楼层，请稍后重试');
    }
  }

  Future<String?> _lookupOpeningAuthor() async {
    final first = await _readAs(null, 1);
    return _openingAuthor ??= first.posts
        .where((p) => postIsOpening(p))
        .firstOrNull
        ?.authorUid;
  }

  /// 退出只看楼主:优先还原进入前已读的楼层;没有可还原的内容时重新读第 1 页
  Future<void> _leaveAuthorMode(bool threaded, double? anchor) async {
    final snapshot = _beforeAuthor;
    final epoch = ++_authorEpoch;
    _generation++;
    if (snapshot != null) {
      _update(() {
        _authorUid = null;
        _beforeAuthor = null;
        _restorePages(snapshot);
      });
      _regroup(threaded);
      _settleAfterSwitch(anchor);
      return;
    }
    _update(() {
      _pendingMode = threaded ? ThreadViewMode.threaded : ThreadViewMode.floors;
      _loading = false;
    });
    _fadeComments(to: .4);
    try {
      final detail = await _readAs(null, 1);
      if (!mounted || epoch != _authorEpoch) return;
      _update(() {
        _authorUid = null;
        _threaded = threaded;
        _pendingMode = null;
        _resetPages(detail);
      });
      _settleAfterSwitch(anchor);
    } catch (_) {
      if (!mounted || epoch != _authorEpoch) return;
      _update(() => _pendingMode = null);
      _fadeComments(to: 1);
      AppToast.show(context, '暂时无法读取全部楼层，请稍后重试');
    }
  }

  /// 评论区标题此刻在屏幕上的纵向位置;未构建时为 null
  double? _headingDy() {
    final box = _commentsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero).dy;
  }

  /// 切换完成:评论区淡入,标题放回切换前的屏幕位置,再按需续读
  void _settleAfterSwitch(double? anchor) {
    _fadeComments(from: 0, to: 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alignHeading(anchor);
      _considerAppend();
    });
  }

  void _alignHeading(double? anchor, [int attempt = 0]) {
    if (anchor == null || !mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final dy = _headingDy();
    if (dy == null) {
      // 标题前的内容变了(例如补上了首楼)时标题可能尚未构建:从顶部逐屏寻找
      if (attempt >= 40) return;
      _scroll.jumpTo(
        attempt == 0
            ? 0
            : (position.pixels + position.viewportDimension).clamp(
                0,
                position.maxScrollExtent,
              ),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _alignHeading(anchor, attempt + 1),
      );
      return;
    }
    final target = position.pixels + dy - anchor;
    // 新内容不足一屏时在末尾补白,标题才能停在原处
    final needed = target - (position.maxScrollExtent - _tailSlack);
    final slack = needed > .5 ? needed : 0.0;
    if ((slack - _tailSlack).abs() > .5) {
      _update(() => _tailSlack = slack);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(target.clamp(0, max));
      });
      return;
    }
    if ((target - position.pixels).abs() > .5) {
      _scroll.jumpTo(target.clamp(0, position.maxScrollExtent));
    }
  }

  /// 评论区透明度:读取中淡化,内容替换后从 0 淡入;减少动态效果时直接到位
  void _fadeComments({double? from, required double to}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _commentsFade.value = to;
      return;
    }
    if (from != null) _commentsFade.value = from;
    _commentsFade.animateTo(to);
  }

  /// 用一次完整读取替换已读楼层(首次进入、刷新、切换只看楼主)
  void _resetPages(ThreadDetail detail) {
    _generation++;
    _pages.clear();
    _postPages.clear();
    _pinnedRoots.clear();
    _visibleReplies.clear();
    _finishReplyReveal();
    _expandingRoot = null;
    _pauseHiddenAppend = false;
    _sourceMayHaveChanged = false;
    _remember(detail);
    _hasNext = detail.page.hasNext && detail.posts.isNotEmpty;
    _loading = false;
    _error = null;
    _tailError = null;
    _beforeError = null;
  }

  void _restorePages(_ReadSnapshot snapshot) {
    _pages
      ..clear()
      ..addAll(snapshot.pages);
    _loadedDetail = snapshot.loadedDetail;
    _hasNext = snapshot.hasNext;
    _loading = false;
    _error = null;
    _tailError = null;
    _beforeError = null;
  }

  Future<ThreadDetail> _read(int page, {bool refresh = false}) =>
      _readAs(_authorUid, page, refresh: refresh);

  Future<ThreadDetail> _readAs(
    String? author,
    int page, {
    bool refresh = false,
  }) =>
      widget.loadPage?.call(page, author, refresh) ??
      forumRepo.thread(
        widget.tid,
        page: page,
        authorUid: author,
        refresh: refresh,
      );

  void _remember(ThreadDetail detail) {
    _loadedDetail = detail;
    _pages[detail.page.current] = detail;
    _rebuildReadIndex();
    // 只有真正的首楼才能确定楼主；提醒落地页的首条回复不是楼主。
    final opening = detail.posts.where((p) => postIsOpening(p)).firstOrNull;
    _openingAuthor ??= opening?.authorUid;
  }

  Future<void> _loadInitial({
    bool useGoto = false,
    int? page,
    bool refresh = false,
  }) async {
    final generation = ++_generation;
    _update(() {
      _loading = true;
      _error = null;
      _tailError = null;
      _beforeError = null;
    });
    try {
      final goto = useGoto ? widget.gotoUrl : null;
      final detail = goto == null
          ? await _read(page ?? widget.initialPage, refresh: refresh)
          : await (widget.loadGoto?.call(goto) ??
                forumRepo.threadAtUrl(goto, tid: widget.tid));
      if (!mounted || generation != _generation) return;
      _update(() {
        // 主动刷新后,进入只看楼主前的旧楼层不再可信
        if (refresh) _beforeAuthor = null;
        _resetPages(detail);
      });
      // 等首次有效加载成功后再通知列表；刷新和分页不推进本次打开的已看计数。
      if (!_markedRead && widget.seenReplies != null) {
        _markedRead = true;
        threadReadIndex.markRead(widget.tid, widget.seenReplies!);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _locateFocusedPost();
        _considerAppend();
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _update(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _considerAppend() {
    if (!_scroll.hasClients ||
        _expandingRoot != null ||
        _pendingMode != null ||
        _composerOpen ||
        _loading ||
        _tailError != null ||
        !_hasNext ||
        _pages.isEmpty ||
        _error != null ||
        _pauseHiddenAppend) {
      return;
    }
    if (_scroll.position.extentAfter < 650) _append();
  }

  Future<void> _append({bool retry = false, bool fromExpansion = false}) async {
    if (_loading ||
        !_hasNext ||
        _pages.isEmpty ||
        (_tailError != null && !retry)) {
      return;
    }
    final generation = _generation;
    final target = _lastPage + 1;
    final previousRoots = _index.roots.length;
    _update(() {
      _loading = true;
      _tailError = null;
    });
    try {
      final detail = await _read(target, refresh: retry);
      if (!mounted || generation != _generation) return;
      final advanced =
          detail.page.current == target &&
          detail.posts.any((p) => !_knownPids.contains(p.pid));
      _update(() {
        // 越界静默回第一页时不重复追加，也不进入无限请求循环。
        if (advanced) _remember(detail);
        _hasNext = advanced && detail.page.hasNext;
        _pauseHiddenAppend =
            fromExpansion || (_grouped && _index.roots.length <= previousRoots);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _considerAppend());
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _update(() {
        _loading = false;
        _tailError = error;
      });
    }
  }

  Future<void> _loadBefore() async {
    if (_loading || _pages.isEmpty || _firstPage <= 1) return;
    final target = _firstPage - 1;
    final generation = _generation;
    final retry = _beforeError != null;
    final oldMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    _update(() {
      _loading = true;
      _beforeError = null;
    });
    try {
      final detail = await _read(target, refresh: retry);
      if (!mounted || generation != _generation) return;
      _update(() {
        if (detail.page.current == target) _remember(detail);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final delta = _scroll.position.maxScrollExtent - oldMax;
        _scroll.jumpTo(
          (oldOffset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _update(() {
        _loading = false;
        _beforeError = error;
      });
    }
  }

  Future<void> _locateFocusedPost() async {
    if (_focusDone || _focusTargetPid == null) return;
    final groupedRoot = _index.rootPidFor(_focusTargetPid!);
    if (_grouped && groupedRoot != null && groupedRoot != _focusTargetPid) {
      final replies = _index.repliesFor(groupedRoot);
      final position = replies.indexWhere((p) => p.pid == _focusTargetPid);
      _update(() {
        _visibleReplies[groupedRoot] = position + 1;
        _rebuildReadIndex();
      });
    }
    final index = _entries.indexWhere(
      (entry) => entry.isStart && entry.post.pid == _focusTargetPid,
    );
    if (index < 0) {
      _focusDone = true;
      AppLog.w('FOCUS', 'pid=$_focusTargetPid 不在提醒落地页');
      if (mounted) {
        AppToast.show(context, '暂时无法定位该楼层，已显示可阅读的内容');
      }
      return;
    }
    _focusDone = true;
    for (var attempt = 0; attempt < 12; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      final context = _focusKey.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(
          context,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.revealDuration,
          curve: AppMotion.revealCurve,
          alignment: .14,
        );
        return;
      }
      final max = _scroll.position.maxScrollExtent;
      // 逐步靠近目标，懒列表构建后再精确定位。
      final estimate = max * (index + 1) / (_entries.length + 1);
      _scroll.jumpTo(estimate.clamp(0.0, max));
    }
    AppLog.w('FOCUS', 'pid=$_focusTargetPid 无法精确定位');
  }

  Widget? _referenceContext(Post post) {
    final reference = _index.directTargetFor(post.pid);
    if (_grouped || reference == null || postIsOpening(post)) return null;
    return ThreadReplyContext(
      reference: reference,
      target: reference.tid == widget.tid
          ? _index.postsByPid[reference.pid]
          : null,
      onOpen: () => _openReference(reference),
    );
  }

  Future<void> _expandReplies(int rootPid) async {
    if (_loading ||
        _pendingMode != null ||
        _expandingRoot != null ||
        _replyReveal.isAnimating) {
      return;
    }
    final generation = _generation;
    final visible = _visibleReplies[rootPid] ?? 0;
    final target = visible + 10;
    _update(() => _expandingRoot = rootPid);
    // Read at most one source page per click. Cache surplus replies for the
    // next click; sparse pages must not trigger an unbounded whole-thread scan.
    if (_index.repliesFor(rootPid).length < target && _hasNext) {
      await _append(retry: _tailError != null, fromExpansion: true);
    }
    if (!mounted ||
        generation != _generation ||
        !_grouped ||
        _expandingRoot != rootPid) {
      return;
    }
    final previous = _entries.map((entry) => entry.key).toSet();
    _update(() {
      _visibleReplies[rootPid] = _tailError == null
          ? target.clamp(0, _index.repliesFor(rootPid).length)
          : visible;
      _expandingRoot = null;
      _pauseHiddenAppend = true;
      _rebuildReadIndex();
      if (!MediaQuery.disableAnimationsOf(context)) {
        // Bound zero-height animated entries so a very long reply cannot force
        // the lazy viewport to lay out every paragraph on the first frame.
        _revealingEntries.addAll(
          _entries
              .where((entry) => entry.nested && !previous.contains(entry.key))
              .take(24)
              .map((entry) => entry.key),
        );
        if (_revealingEntries.isNotEmpty) _replyReveal.forward(from: 0);
      }
    });
  }

  Widget _replyExpansion(Post post) {
    final visible = _visibleReplies[post.pid] ?? 0;
    final remaining = _index.repliesFor(post.pid).length - visible;
    final finished = remaining <= 0 && !_hasNext && _tailError == null;
    final loading = _expandingRoot == post.pid;
    final label = loading
        ? '正在加载回复…'
        : _tailError != null
        ? '回复加载失败，点击重试'
        : remaining > 0
        ? (visible == 0 ? '展开 $remaining 条回复' : '展开更多回复（$remaining）')
        : '继续加载回复';
    final content = finished
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(64, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                key: ValueKey('thread-expand-replies-${post.pid}'),
                label: label,
                variant: AppButtonVariant.plain,
                icon: AppIcons.down,
                onPressed:
                    _loading ||
                        _expandingRoot != null ||
                        _replyReveal.isAnimating
                    ? null
                    : () => _expandReplies(post.pid),
              ),
            ),
          );
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return AnimatedSize(
      duration: AppMotion.revealDuration,
      curve: AppMotion.revealCurve,
      alignment: Alignment.topLeft,
      child: content,
    );
  }

  Future<void> _showOriginalPost(Post post) async {
    if (!mounted) return;
    _update(() {
      _threaded = false;
      _focusTargetPid = post.pid;
      _highlightPid = post.pid;
      _focusDone = false;
      _pinnedRoots.clear();
      _visibleReplies.clear();
      _finishReplyReveal();
      _expandingRoot = null;
      _rebuildReadIndex();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _locateFocusedPost();
  }

  Future<void> _openReference(PostReference reference) async {
    if (!mounted || reference.pid <= 0 || reference.tid <= 0) return;
    final target = reference.tid == widget.tid
        ? _index.postsByPid[reference.pid]
        : null;
    if (target != null) {
      await _showOriginalPost(target);
      return;
    }
    // Offline callers must inject this read too; never escape into live traffic.
    if (widget.loadPage != null && widget.loadGoto == null) {
      AppToast.show(context, '暂时无法读取引用楼层');
      return;
    }
    final url = Uri.https('www.chiphell.com', '/forum.php', {
      'mod': 'redirect',
      'goto': 'findpost',
      'ptid': '${reference.tid}',
      'pid': '${reference.pid}',
    }).toString();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailPage(
          tid: reference.tid,
          title: '引用楼层',
          gotoUrl: url,
          focusPid: reference.pid,
          initialThreaded: false,
          loadGoto: widget.loadGoto,
          loadPage: reference.tid == widget.tid
              ? widget.loadPage
              : widget.loadPage != null || widget.loadGoto != null
              ? (_, _, _) => Future.error(StateError('未提供该帖的离线加载器'))
              : null,
          submitReply: widget.submitReply,
        ),
      ),
    );
  }

  Future<void> _openComposer(Post? quoted) async {
    if (_composerOpen) return;
    final fid = widget.fid ?? _loadedDetail?.fid;
    if (fid == null) {
      AppToast.show(context, '暂时无法读取版块信息，请刷新后重试');
      return;
    }
    _composerOpen = true;
    final replyPage = quoted == null
        ? _lastPage
        : (_postPages[quoted.pid] ?? _lastPage);
    final draftKey = 'thread:${widget.tid}:${quoted?.pid ?? 0}';
    final images = _replyImages.putIfAbsent(
      draftKey,
      () => AttachmentController(
        loadContext: () =>
            postRepo.replyUploadContext(tid: widget.tid, fid: fid),
        upload: uploaderFor(postRepo),
      ),
    );
    final result = await ComposerSheet.show(
      context,
      draftKey: draftKey,
      attachments: images,
      quoteOf: quoted == null
          ? null
          : '${quoted.author}${quoted.floorIsKnown ? ' #${quoted.floor}' : ''}',
      onSubmit: (message) =>
          widget.submitReply?.call(
            tid: widget.tid,
            fid: fid,
            message: message,
            quotePid: quoted?.pid,
            page: replyPage,
          ) ??
          postRepo.reply(
            tid: widget.tid,
            fid: fid,
            message: message,
            quotePid: quoted?.pid,
            page: replyPage,
            images: images.aids,
          ),
    );
    _composerOpen = false;
    if (result?.isSuccess ?? false) _replyImages.remove(draftKey)?.dispose();
    if (!mounted || result == null) return;
    showPostResult(context, result);
    if (result.isSuccess || result.kind == PostResultKind.unknown) {
      // Revalidate the write context AND the last loaded source page. A reply to
      // an early comment may create a new page at the end of the thread.
      if (_pages.isEmpty) return;
      final generation = _generation;
      final lastLoadedPage = _lastPage;
      _update(() {
        _sourceMayHaveChanged = true;
        // 新回复不在进入只看楼主前的旧楼层里,退出时改为重新读取
        _beforeAuthor = null;
        _rebuildReadIndex();
      });
      for (final page in <int>{replyPage, lastLoadedPage}) {
        try {
          final detail = await _read(page, refresh: true);
          if (!mounted || generation != _generation) return;
          if (detail.page.current != page || detail.tid != widget.tid) continue;
          _update(() {
            _remember(detail);
            if (page == lastLoadedPage) _hasNext = detail.page.hasNext;
          });
        } catch (_) {
          // Preserve the confirmed send result and loaded-only counts.
        }
      }
    }
  }

  @override
  void dispose() {
    for (final images in _replyImages.values) {
      images.dispose();
    }
    _generation++;
    _authorEpoch++;
    chhSession.removeListener(_sessionChanged);
    _scroll.dispose();
    _collapsedTitle.dispose();
    _navOffset.dispose();
    _inComments.dispose();
    _scrollSpring.dispose();
    _commentsOpacity.dispose();
    _commentsFade.dispose();
    _replyRevealCurve.dispose();
    _replyReveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _syncInComments();
    });
    return Scaffold(
      extendBody: true,
      backgroundColor: t.bg,
      body: Stack(
        children: [
          ExpressivePageReveal(
            active: true,
            // 只在整页内容出现时播放;切换查看方式只淡入评论区
            revision: _pages.isEmpty,
            child: _pages.isEmpty
                ? _initialState()
                : RefreshIndicator(
                    onRefresh: () =>
                        _loadInitial(page: _firstPage, refresh: true),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.depth == 0 &&
                            notification is ScrollStartNotification &&
                            notification.dragDetails != null) {
                          _stopSpring();
                        }
                        if (notification.depth == 0 &&
                            notification is ScrollStartNotification &&
                            notification.dragDetails != null &&
                            _pauseHiddenAppend) {
                          _pauseHiddenAppend = false;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _considerAppend();
                          });
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(
                          top: top + NavOverlay.barHeight,
                          bottom: 120,
                        ),
                        itemCount: _entries.length + 2,
                        findChildIndexCallback: (key) {
                          if (key == _focusKey) {
                            final index = _entries.indexWhere(
                              (e) => e.isStart && e.post.pid == _focusTargetPid,
                            );
                            return index < 0 ? null : index + 1;
                          }
                          return key is ValueKey<String>
                              ? _entryIndices[key.value]
                              : null;
                        },
                        itemBuilder: (context, index) {
                          if (index == 0) return _heading(t);
                          // 标题之后的内容随查看方式切换淡化/淡入
                          final heading =
                              _entryIndices[_ThreadReadEntry.headingKey] ??
                              _entries.length + 1;
                          if (index == _entries.length + 1) {
                            return FadeTransition(
                              opacity: _commentsOpacity,
                              child: _tail(t),
                            );
                          }
                          final entry = _entries[index - 1];
                          final post = entry.post;
                          final focused = post.pid == _highlightPid;
                          final author =
                              post.authorUid != null &&
                              post.authorUid == _openingAuthor;
                          void onReply() {
                            _openComposer(post);
                          }

                          final card = switch (entry.kind) {
                            _ThreadEntryKind.whole => PostCard(
                              post: post,
                              isOpening: postIsOpening(post),
                              commentStyle: _grouped && !postIsOpening(post),
                              replyToAuthor: _replyToAuthor(post),
                              isAuthor: author,
                              onReply: onReply,
                              replyContext: _referenceContext(post),
                            ),
                            _ThreadEntryKind.header => PostCard.header(
                              post: post,
                              isOpening: postIsOpening(post),
                              commentStyle: _grouped && !postIsOpening(post),
                              isAuthor: author,
                              onReply: onReply,
                              replyContext: _referenceContext(post),
                            ),
                            _ThreadEntryKind.block => PostCard.block(
                              post: post,
                              isOpening: postIsOpening(post),
                              commentStyle: _grouped && !postIsOpening(post),
                              replyToAuthor: entry.blockIndex == 0
                                  ? _replyToAuthor(post)
                                  : null,
                              isAuthor: author,
                              contentBlock: entry.block!,
                              gallery: entry.gallery,
                              galleryIndex: entry.imageIndex,
                            ),
                            _ThreadEntryKind.footer => PostCard.footer(
                              post: post,
                              isOpening: postIsOpening(post),
                              commentStyle: _grouped && !postIsOpening(post),
                              isAuthor: author,
                              onReply: onReply,
                            ),
                            _ThreadEntryKind.commentsHeading => Padding(
                              key: _commentsKey,
                              padding: const EdgeInsets.fromLTRB(
                                AppSpace.screen,
                                20,
                                AppSpace.screen,
                                8,
                              ),
                              child: ThreadCommentHeading(
                                loadedCount: _orderedPosts
                                    .where((p) => !postIsOpening(p))
                                    .length,
                                complete: _index.sourceComplete,
                                mode: _shownMode,
                                busy: _pendingMode != null,
                                onModeChanged: _setViewMode,
                              ),
                            ),
                            _ThreadEntryKind.replies => _replyExpansion(post),
                          };
                          final content = ColoredBox(
                            color: focused ? t.accentFill : t.bg,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: entry.nested ? 40 : 0,
                              ),
                              child: card,
                            ),
                          );
                          final reveal = _revealingEntries.contains(entry.key)
                              ? _replyRevealCurve
                              : const AlwaysStoppedAnimation<double>(1);
                          final row = Column(
                            key: focused && entry.isStart
                                ? _focusKey
                                : ValueKey(entry.key),
                            // 默认居中会给子项宽松约束,不足一行的段落随之居中
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 紧跟评论区标题的第一条不画分隔线,分段控件已隔开
                              if (entry.isStart &&
                                  !entry.nested &&
                                  index > 1 &&
                                  index != heading + 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    thickness: AppSpace.hairline,
                                    color: t.separator,
                                  ),
                                ),
                              if (entry.nested)
                                SizeTransition(
                                  sizeFactor: reveal,
                                  alignment: Alignment.topCenter,
                                  child: FadeTransition(
                                    opacity: reveal,
                                    child: content,
                                  ),
                                )
                              else
                                content,
                            ],
                          );
                          return index > heading
                              ? FadeTransition(
                                  opacity: _commentsOpacity,
                                  child: row,
                                )
                              : row;
                        },
                      ),
                    ),
                  ),
          ),
          // 顶栏只有返回圆钮;滚动后居中显示标题,顶部渐隐代替硬切
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: _collapsedTitle,
              builder: (context, collapsed, _) => NavOverlay(
                leading: ChromeButton(
                  icon: AppIcons.back,
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                // 与返回键同款圆钮、左右对称:平时只是顶栏的一部分,要找时固定在右上角
                actions: [
                  ChromeButton(
                    key: const ValueKey('thread-source-page'),
                    icon: AppIcons.webPage,
                    tooltip: '查看原页面',
                    onPressed: () => showSourcePage(
                      context,
                      threadSourceUrl(widget.tid, page: _firstPage),
                    ),
                  ),
                ],
                inlineTitle: _loadedDetail?.title ?? widget.title,
                scrollOffset: _navOffset,
                collapseAt: 140,
                background: t.bg,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _pages.isEmpty ? null : _toolbar(),
    );
  }

  Widget _initialState() {
    if (_loading) return StateView.loading();
    final error = _error;
    if (error is PageMessage) {
      return StateView.forMessage(
        error,
        onLogin: () => Navigator.of(context).pushNamed('/login'),
      );
    }
    if (error != null) {
      return StateView.error(
        error,
        onRetry: () => _loadInitial(useGoto: true, refresh: true),
      );
    }
    return const StateView(icon: AppIcons.comments, message: '这里还没有回复');
  }

  /// 眉题:帖子所在版块;只看楼主时一并标出
  String get _eyebrow =>
      [?_loadedDetail?.forumName, if (_authorUid != null) '只看楼主'].join(' · ');

  Widget _heading(AppTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_eyebrow.isNotEmpty) ...[
          Text(
            _eyebrow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.sizeFootnote,
              color: t.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
        ],
        Text(
          _loadedDetail?.title ?? widget.title,
          style: TextStyle(
            fontSize: _firstPage == 1
                ? AppType.sizeLargeTitle
                : AppType.sizeTitle2,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: t.text,
            letterSpacing: -.4,
          ),
        ),
        if (_firstPage > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppButton(
              label: _beforeError == null ? '查看前面的讨论' : '前文未加载，轻点重试',
              variant: AppButtonVariant.plain,
              icon: AppIcons.up,
              onPressed: _loading ? null : _loadBefore,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '刷新未完成，已保留当前内容',
                    style: TextStyle(
                      fontSize: AppType.sizeFootnote,
                      color: t.text2,
                    ),
                  ),
                ),
                AppButton(
                  label: '重试',
                  variant: AppButtonVariant.plain,
                  onPressed: _loading
                      ? null
                      : () => _loadInitial(page: _firstPage, refresh: true),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _tail(AppTokens t) => Padding(
    padding: EdgeInsets.fromLTRB(24, 24, 24, 8 + _tailSlack),
    child: Center(
      child: _loading
          ? SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            )
          : _tailError != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '后面的讨论暂时没有加载出来',
                  style: TextStyle(
                    fontSize: AppType.sizeFootnote,
                    color: t.text2,
                  ),
                ),
                AppButton(
                  label: '重试',
                  variant: AppButtonVariant.plain,
                  onPressed: () => _append(retry: true),
                ),
              ],
            )
          : Text(
              _hasNext ? '继续向下阅读' : '已读到这里',
              style: TextStyle(fontSize: AppType.sizeFootnote, color: t.text3),
            ),
    ),
  );

  /// 底部阅读工具栏:"写回复…"输入胶囊 + 评论数 / 回到顶部圆钮
  Widget _toolbar() => ValueListenableBuilder<bool>(
    valueListenable: _inComments,
    builder: (context, inComments, _) => ReadingBar(
      placeholder: '写回复…',
      onCompose: () => _openComposer(null),
      count: _orderedPosts.where((p) => !postIsOpening(p)).length,
      inComments: inComments,
      onShowComments: _showComments,
      onBackToTop: _backToTop,
    ),
  );
}

enum _ThreadEntryKind { whole, header, block, footer, commentsHeading, replies }

class _ThreadReadEntry {
  final Post post;
  final _ThreadEntryKind kind;
  final ContentBlock? block;
  final int blockIndex;
  final List<String> gallery;
  final int imageIndex;
  final bool nested;
  const _ThreadReadEntry(
    this.post,
    this.kind, {
    this.block,
    this.blockIndex = -1,
    this.gallery = const [],
    this.imageIndex = 0,
    this.nested = false,
  });
  bool get isStart =>
      kind == _ThreadEntryKind.whole || kind == _ThreadEntryKind.header;

  /// 评论区标题的键与首条评论无关,切换查看方式时标题保持同一个元素
  static const headingKey = 'comments-heading';

  String get key => switch (kind) {
    _ThreadEntryKind.whole => 'post-${post.pid}',
    _ThreadEntryKind.commentsHeading => headingKey,
    _ => 'post-${post.pid}-${kind.name}-$blockIndex',
  };
}

/// 进入只看楼主前的已读楼层
class _ReadSnapshot {
  final Map<int, ThreadDetail> pages;
  final bool hasNext;
  final ThreadDetail? loadedDetail;
  const _ReadSnapshot(this.pages, this.hasNext, this.loadedDetail);
}
