/// 连续楼层阅读：沿站点分页顺序追加，保留提醒的真实落地页与楼层定位。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind, VelocityTracker;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import '../ui/balanced_title.dart';
import '../design/display_text.dart';
import '../ui/reading_settings_sheet.dart';
import '../ui/app_button.dart';
import '../design/typography.dart';
import '../ui/feedback.dart';

import '../core/app_log.dart';
import '../core/chh_urls.dart';
import '../design/tokens.dart';
import '../design/reading.dart';
import '../design/list_end_tokens.dart';
import '../design/feedback.dart';
import '../design/thread_page_tokens.dart';
import '../design/scroll_progress.dart';
import '../ui/press.dart';
import '../design/motion.dart';
import '../ui/reading_bar.dart';
import '../ui/image_viewer_chrome.dart';
import '../ui/favorite_action.dart';
import '../data/favorite_index.dart';
import '../data/history_index.dart';
import '../ui/chrome_button.dart';
import '../ui/nav_bar.dart';
import '../di.dart';
import '../models/models.dart';
import '../models/poll.dart';
import '../models/image_stack_group.dart';
import '../models/post_interaction.dart';
import '../data/post_interaction_repository.dart';
import '../data/user_block_index.dart';
import '../data/blocked_post_projection.dart';
import '../ui/user_block_action.dart';
import '../widgets/chhers_loader.dart';
import '../widgets/chhers_loading_transition.dart';
import '../widgets/chhers_refresh_indicator.dart';
import '../widgets/post_action_menu.dart';
import '../widgets/comment_row_interaction.dart';
import '../widgets/post_interaction_sheet.dart';
import '../attachments/attachment_controller.dart';
import '../widgets/composer_sheet.dart';
import 'source_page_drawer.dart';
import 'user_drawer.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/avatar_image.dart';
import '../widgets/post_card.dart';
import '../widgets/connected_thread_poll.dart';
import '../widgets/reading_list_end.dart';
import '../widgets/post_feedback.dart';
import '../widgets/state_view.dart';
import '../data/thread_conversation_index.dart';
import '../data/forum_repository.dart';
import '../network/chh_client.dart' show ChhClient, ThreadReadCancelled;
import '../widgets/password_sheet.dart';
import '../data/thread_read_index.dart';
import '../widgets/thread_comment_widgets.dart';
import '../widgets/anchored_reading_list.dart';
import '../widgets/thread_landing.dart';

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
  final ThreadDetail? initialDetail;
  final int? initialDetailCacheGeneration;
  final int? initialDetailThreadRevision;

  /// A portal reader keeps ownership of the route surface and its chrome.
  final ThreadLandingChrome? landingChrome;
  final String? landingTitle;
  final bool landingSkeletonVisible;

  /// 首屏就绪后限速补齐的页数，包含落地页；后续仍按阅读进度追加。
  final int preloadPages;
  final int? fid;
  final int? seenReplies;
  final int? observedReplies;
  final String? gotoUrl;
  final int? focusPid;
  final BlockedUserSource? blockedSource;
  final bool? initialThreaded;

  /// 点评/评分提醒仅在目标为主楼时定位附属模块。
  final bool focusOpeningFeedback;

  /// 测试与离线预览可注入读取/提交；默认仍使用真实仓库。
  final ThreadPageLoader? loadPage;
  final ThreadGotoLoader? loadGoto;
  final ThreadReplySubmitter? submitReply;
  final ForumRepository? repository;
  final PostInteractionRepository? interactions;
  final UserBlockIndex? blockIndex;

  const ThreadDetailPage({
    super.key,
    required this.tid,
    required this.title,
    this.initialPage = 1,
    this.initialDetail,
    this.initialDetailCacheGeneration,
    this.initialDetailThreadRevision,
    this.landingChrome,
    this.landingTitle,
    this.landingSkeletonVisible = false,
    this.preloadPages = 30,
    this.fid,
    this.seenReplies,
    this.observedReplies,
    this.gotoUrl,
    this.focusPid,
    this.blockedSource,
    this.initialThreaded,
    this.focusOpeningFeedback = false,
    this.loadPage,
    this.loadGoto,
    this.submitReply,
    this.repository,
    this.interactions,
    this.blockIndex,
  });

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _initialDetailConsumed = false;
  final _scroll = ScrollController();
  final _readListKey = GlobalKey();
  String? _centerEntryKey;

  /// 顶栏渐隐与居中小标题跟随的滚动距离
  late final _chrome = widget.landingChrome ?? ThreadLandingChrome();
  ValueNotifier<double> get _navOffset => _chrome.offset;
  ValueNotifier<double> get _readingProgress => _chrome.progress;

  bool get _portalLanding => widget.landingChrome != null;
  Timer? _landingSkeletonDelay;
  late bool _landingSkeletonVisible = widget.landingSkeletonVisible;
  late bool _landingPaintPending = _portalLanding;
  late final _landingArrival = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
  );
  late final _landingOpacity = CurveTween(
    curve: AppMotion.contentFadeCurve,
  ).animate(_landingArrival);
  late final _skeletonOpacity = Tween(begin: 1.0, end: 0.0).animate(
    CurveTween(
      curve: Interval(
        0,
        AppMotion.skeletonFade.inMicroseconds /
            _landingArrival.duration!.inMicroseconds,
        curve: AppMotion.skeletonFadeCurve,
      ),
    ).animate(_landingArrival),
  );
  int? _readingTotalPosts;
  final _entryProgress = <String, ({double start, double span})>{};
  final _titleKey = GlobalKey();
  double _titleAt = 140;
  late final _barProgress = ScrollDeltaProgress(
    vsync: this,
    travel: ThreadPageTokens.readingBarTravel,
  );
  VelocityTracker? _barDragVelocity;
  bool _barReleasedToBallistic = false;

  /// 评论区标题是否已滚到顶栏下方:决定阅读工具栏圆钮是"评论数"还是"回到顶部"
  final _inComments = ValueNotifier<bool>(false);
  final _commentsKey = GlobalKey();

  /// "回到顶部 / 跳到评论"的弹簧滚动;手指一碰列表就停
  bool _springing = false;
  ValueNotifier<bool> get _collapsedTitle => _chrome.collapsed;
  final _focusKey = GlobalKey();
  final _feedbackKey = GlobalKey();
  late bool _focusOpeningFeedback = widget.focusOpeningFeedback;
  late final _focusHighlight = AnimationController(
    vsync: this,
    duration: ThreadPageTokens.focusDuration,
    value: 1,
  );
  final _pages = <int, ThreadDetail>{};
  final _postPages = <int, int>{};
  final _knownPids = <int>{};
  final _entries = <_ThreadReadEntry>[];
  final _entryIndices = <String, int>{};
  ThreadDetail? _loadedDetail;
  int? _replyCountSequence;
  ({int replies, int sequence})? _verifiedReplyCount;
  int? get _replyCount {
    final verified = _verifiedReplyCount;
    if (_authorUid == null &&
        verified != null &&
        verified.sequence >= (_replyCountSequence ?? 0)) {
      return verified.replies;
    }
    return _loadedDetail?.replyCount;
  }

  String? _authorUid;
  String? _openingAuthor;
  bool _loading = true;
  Object? _beforeLoad;
  bool get _loadingBefore => _beforeLoad != null;
  bool _hasNext = false;
  Object? _updateCheck;
  int? _failedUpdatePage;
  ({String key, double y})? _endPullAnchor;
  int _dragRevision = 0;
  Timer? _preloadTimer;
  bool _prefetching = false;
  Completer<void>? _appendCompletion;
  ValueNotifier<bool>? _navigationGesture;
  Completer<void>? _navigationIdle;
  bool _routeCurrent = true;
  bool _viewerCovered = false;
  int _preloadEndPage = 0;

  bool get _navigationBusy =>
      _viewerCovered || (_navigationGesture?.value ?? false);

  bool get _canPreload =>
      mounted &&
      _routeCurrent &&
      !_navigationBusy &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      !_loading &&
      !_loadingBefore &&
      _updateCheck == null &&
      !_landingPaintPending &&
      _pendingMode == null &&
      !_composerOpen &&
      !_postActionOpen &&
      _unlocking.isEmpty &&
      _error == null &&
      _tailError == null &&
      _hasNext &&
      _pages.isNotEmpty &&
      _lastPage < _preloadEndPage;

  void _schedulePreload() {
    if (!_canPreload || _expandingRoot != null) {
      _preloadTimer?.cancel();
      _preloadTimer = null;
      return;
    }
    if (_prefetching || _preloadTimer != null) return;
    final cached =
        widget.loadPage == null &&
        _repository.hasCachedThread(
          widget.tid,
          page: _lastPage + 1,
          authorUid: _authorUid,
        );
    _preloadTimer = Timer(
      cached ? Duration.zero : ChhClient.defaultThreadRequestInterval,
      () {
        _preloadTimer = null;
        if (_canPreload && _expandingRoot == null) _append(background: true);
      },
    );
  }

  void _navigationGestureChanged() {
    if (!_navigationBusy) {
      _navigationIdle?.complete();
      _navigationIdle = null;
    }
    _schedulePreload();
  }

  Future<void> _waitForNavigationIdle(int generation) async {
    // Keep an arrived page without rebuilding the reading tree under a drag.
    while (mounted && generation == _generation && _navigationBusy) {
      await (_navigationIdle ??= Completer<void>()).future;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _schedulePreload();
  }

  bool _markedRead = false;
  bool _historyRecorded = false;
  bool _focusDone = false;
  bool _composerOpen = false;
  bool _postActionOpen = false;
  UserBlockIndex get _blocks => widget.blockIndex ?? userBlockIndex;
  late final int _blockSourceEpoch;
  BlockedUserSource? get _activeBlockSource =>
      _blockSourceEpoch == _blocks.epoch ? widget.blockedSource : null;
  PostInteractionRepository get _interactions =>
      widget.interactions ?? postInteractionRepo;
  bool _blocked(Post post) => _blocks.isBlocked(post.authorUid);
  bool _isSourcePost(Post post) => post.pid == _activeBlockSource?.pid;
  Post? get _blockedSourcePost {
    final post = _index.postsByPid[_activeBlockSource?.pid];
    return post != null && _blocked(post) ? post : null;
  }

  List<Post> _conversationReplies(int pid) => _index
      .repliesFor(pid)
      .where((p) => !_blocked(p) || _isSourcePost(p))
      .toList();
  int get _shownReplyCount =>
      _orderedPosts.where((p) => !postIsOpening(p) && !_blocked(p)).length;
  final _unlocking = <int>{};
  bool _forumPasswordOpen = false;
  ForumRepository get _repository => widget.repository ?? forumRepo;

  /// 回复里的图片,与文字草稿一样按回复目标保留,发送成功后清掉
  final _replyImages = <String, AttachmentController>{};

  /// 正在读取的查看方式(进出只看楼主要读网络):控件先选中它,计数处显示等待
  ThreadViewMode? _pendingMode;

  /// 进入只看楼主前已读的楼层;退出时原样还原,不重新读取
  _ReadSnapshot? _beforeAuthor;

  /// 切换查看方式时只淡化/淡入评论区,首楼和标题不动
  late final _commentsFade = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: 1,
  );
  late final _commentsOpacity = CurvedAnimation(
    parent: _commentsFade,
    curve: Curves.linear,
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

  late bool _threaded = widget.initialThreaded ?? true;
  bool _preferencesApplied = false;
  bool _preferAuthor = false;
  late int? _focusTargetPid = _activeBlockSource?.pid ?? widget.focusPid;
  String? get _gotoUrl {
    final source = _activeBlockSource;
    if (source != null &&
        (widget.loadPage == null || widget.loadGoto != null)) {
      return _postLocationUrl(source.tid, source.pid);
    }
    return widget.gotoUrl;
  }

  int? _highlightPid;
  bool _pauseHiddenAppend = false;
  final _pinnedRoots = <int>{};
  final _visibleReplies = <int, int>{};
  final _heldReplies = <int, ValueNotifier<bool>>{};
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
  @visibleForTesting
  ThreadConversationIndex get debugConversationIndex => _index;

  void _update(VoidCallback change) => setState(change);

  bool get _grouped => _threaded && _authorUid == null;

  void _finishReplyReveal() {
    _revealingEntries.clear();
    _replyReveal.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final gesture = Navigator.maybeOf(context)?.userGestureInProgressNotifier;
    if (_navigationGesture != gesture) {
      _navigationGesture?.removeListener(_navigationGestureChanged);
      _navigationGesture = gesture;
      gesture?.addListener(_navigationGestureChanged);
    }
    _navigationGestureChanged();
    final prefs = ReadingScope.maybeOf(context);
    if (!_preferencesApplied && (prefs?.ready ?? true)) {
      _preferencesApplied = true;
      final mode = prefs?.prefs.commentMode;
      if (widget.initialThreaded == null) {
        _threaded = mode != ThreadViewMode.floors;
        // 通知与跳楼入口必须保留目标楼层，不能被楼主筛选隐藏。
        _preferAuthor =
            mode == ThreadViewMode.author &&
            _gotoUrl == null &&
            _focusTargetPid == null &&
            widget.initialPage == 1;
        if (_loadedDetail != null && !_loading) {
          _rebuildReadIndex();
          if (_preferAuthor) {
            _preferAuthor = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _enterAuthorMode(null);
            });
          }
        }
      }
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _finishReplyReveal();
      if (_portalLanding && _landingArrival.isAnimating) {
        _landingArrival.value = 1;
      }
    }
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
    if (_blocks.isBlocked(_index.postsByPid[target.pid]?.authorUid)) {
      return '已屏蔽用户';
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
        keys.firstOrNull == 1 &&
        keys.last == keys.length &&
        !_pages[keys.last]!.page.hasNext;
    _index = ThreadConversationIndex.build(
      tid: widget.tid,
      posts: orderedPosts,
      sourceComplete: complete,
      pinnedRootPids: _pinnedRoots,
    );
    _pinnedRoots.addAll(_index.roots.map((p) => p.pid));
    _rebuildReadEntries();
  }

  // 展开数量变化只更新展示投影，已加载楼层和引用归组快照保持不变。
  void _rebuildReadEntries() {
    _entries.clear();
    _entryIndices.clear();
    var commentsStarted = false;
    for (final post in _grouped ? _index.roots : _orderedPosts) {
      if (!postIsOpening(post) && !commentsStarted) {
        commentsStarted = true;
        _entries.add(_ThreadReadEntry(post, _ThreadEntryKind.commentsHeading));
      }
      final replies = _grouped
          ? _conversationReplies(post.pid)
          : const <Post>[];
      if (_blocked(post)) {
        if (!postIsOpening(post) &&
            (_isSourcePost(post) || (_grouped && replies.isNotEmpty))) {
          _entries.add(_ThreadReadEntry(post, _ThreadEntryKind.blocked));
        }
      } else {
        _addPostEntries(post);
      }
      if (_grouped && !postIsOpening(post)) {
        final visible = (_visibleReplies[post.pid] ?? 0).clamp(
          0,
          replies.length,
        );
        for (var i = 0; i < visible; i++) {
          final reply = replies[i];
          if (_blocked(reply)) {
            _entries.add(
              _ThreadReadEntry(reply, _ThreadEntryKind.blocked, nested: true),
            );
          } else {
            _addPostEntries(reply, nested: true);
          }
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
    if (!commentsStarted && _orderedPosts.isNotEmpty) {
      _entries.add(
        _ThreadReadEntry(_orderedPosts.last, _ThreadEntryKind.commentsHeading),
      );
    }
    for (var i = 0; i < _entries.length; i++) {
      _entryIndices[_entries[i].key] = i + 1;
    }
    _rebuildProgressIndex();
    if (_centerEntryKey != null &&
        !_entryIndices.containsKey(_centerEntryKey)) {
      _centerEntryKey = null;
      if (_scroll.hasClients) _scroll.position.correctPixels(0);
    }
  }

  void _rebuildProgressIndex() {
    _entryProgress.clear();
    final total = _readingTotalPosts;
    if (total == null || total <= 0) return;
    final counts = <int, int>{};
    for (final entry in _entries) {
      if (!entry.nested &&
          entry.kind != _ThreadEntryKind.commentsHeading &&
          entry.kind != _ThreadEntryKind.replies) {
        counts.update(entry.post.pid, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final offsets = <int, int>{};
    var rootFloor = 0;
    for (final entry in _entries) {
      final post = entry.post;
      if (!post.floorIsKnown) continue;
      if (entry.nested || entry.kind == _ThreadEntryKind.replies) {
        // A later quoted floor stays at its root's position in comment mode.
        _entryProgress[entry.key] = (start: rootFloor / total, span: 0);
      } else if (entry.kind == _ThreadEntryKind.commentsHeading) {
        _entryProgress[entry.key] = (
          start: (post.floor - (postIsOpening(post) ? 0 : 1)) / total,
          span: 0,
        );
      } else {
        rootFloor = post.floor;
        final count = counts[post.pid]!;
        final offset = offsets[post.pid] ?? 0;
        offsets[post.pid] = offset + 1;
        _entryProgress[entry.key] = (
          start: (post.floor - 1 + offset / count) / total,
          span: 1 / count / total,
        );
      }
    }
  }

  void _syncReadingProgress(double top) {
    final position = _scroll.position;
    _chrome.progressVisible.value =
        position.extentBefore > position.viewportDimension;
    final total = _readingTotalPosts;
    final last = _orderedPosts.lastOrNull;
    if (_entryProgress.isEmpty) {
      _readingProgress.value = 0;
      return;
    }
    if (total != null &&
        _authorUid == null &&
        !_hasNext &&
        _pages.isNotEmpty &&
        !_pages[_lastPage]!.page.hasNext &&
        position.extentBefore > 0 &&
        position.extentAfter <= 1 &&
        last != null &&
        last.floorIsKnown &&
        last.floor >= total) {
      _readingProgress.value = 1;
      return;
    }
    if (_scroll.position.pixels <= _scroll.position.minScrollExtent &&
        _centerEntryKey == null &&
        _pages.containsKey(1)) {
      _readingProgress.value = 0;
      return;
    }
    for (final row in _mountedReadingRows()) {
      if (row.height <= 0 || row.y + row.height <= top) continue;
      final progress = _entryProgress[row.key];
      if (progress == null) continue;
      final fraction = ((top - row.y) / row.height).clamp(0.0, 1.0);
      // Stale counts or floor gaps cannot claim completion before the real end.
      _readingProgress.value = (progress.start + progress.span * fraction)
          .clamp(0.0, .999);
      return;
    }
  }

  void _addPostEntries(Post post, {bool nested = false}) {
    post = projectBlockedPost(
      post,
      tid: widget.tid,
      knownPosts: _index.postsByPid,
      isBlocked: _blocks.isBlocked,
    );
    final hideQuotes =
        !postIsOpening(post) &&
        (_grouped || _index.directTargetFor(post.pid) != null);
    final blocks = post.content;
    final images = blocks
        .whereType<ImageBlock>()
        .map((b) => b.url)
        .toList(growable: false);
    final smallReply =
        !postIsOpening(post) && images.length <= 3 && blocks.length <= 12;
    // Only inspect short candidates here. Long runs are grouped once below.
    final smallSegments = post.lock == null && smallReply && images.length >= 2
        ? groupPostImages(blocks)
        : null;
    final shortImageGroup =
        smallSegments?.any((segment) => segment.imageStack != null) ?? false;
    if (post.lock != null || (smallReply && !shortImageGroup)) {
      _entries.add(
        _ThreadReadEntry(post, _ThreadEntryKind.whole, nested: nested),
      );
      return;
    }
    final gallery = List<String>.unmodifiable(images);
    _entries.add(
      _ThreadReadEntry(post, _ThreadEntryKind.header, nested: nested),
    );
    var firstContent = true;
    for (final segment in smallSegments ?? groupPostImages(blocks)) {
      final block = segment.block;
      if (hideQuotes && block is QuoteBlock && !block.isNotice) continue;
      final group = segment.imageStack;
      _entries.add(
        _ThreadReadEntry(
          post,
          group == null ? _ThreadEntryKind.block : _ThreadEntryKind.imageStack,
          block: block,
          imageStack: group,
          siteLinks: segment.siteLinks,
          linksGrouped: segment.linksGrouped,
          linkGroupStart: segment.linkGroupStart,
          linkGroupEnd: segment.linkGroupEnd,
          firstContent: firstContent,
          blockIndex: segment.blockIndex,
          gallery: gallery,
          imageIndex: segment.galleryIndex,
          nested: nested,
        ),
      );
      firstContent = false;
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
    // Create tickers while the element is active, including early load failures.
    _commentsFade;
    _commentsOpacity;
    _replyReveal;
    _replyRevealCurve;
    _focusHighlight;
    if (_portalLanding) _landingArrival;
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_handleScroll);
    _sessionLoggedIn = chhSession.loggedIn;
    _sessionUid = chhSession.badges.uid;
    chhSession.addListener(_sessionChanged);
    _blockSourceEpoch = _blocks.epoch;
    _blocks.addListener(_blocksChanged);
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
    _beforeLoad = null;
    _updateCheck = null;
    _prefetching = false;
    _authorEpoch++;
    _update(() {
      _pages.clear();
      _postPages.clear();
      _pinnedRoots.clear();
      _visibleReplies.clear();
      _finishReplyReveal();
      _expandingRoot = null;
      _loadedDetail = null;
      _replyCountSequence = null;
      _verifiedReplyCount = null;
      _readingTotalPosts = null;
      _openingAuthor = null;
      _authorUid = null;
      _pendingMode = null;
      _beforeAuthor = null;
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
      if (mounted) _loadInitial(useGoto: _gotoUrl != null, refresh: true);
    });
  }

  void _handleScroll() {
    if (_scroll.hasClients) {
      final collapsed = _scroll.offset >= _titleAt;
      final position = _scroll.position;
      if (_collapsedTitle.value != collapsed) _collapsedTitle.value = collapsed;
      _navOffset.value = position.pixels - position.minScrollExtent;
      _syncInComments();
      _scheduleReadingGeometry();
    }
    _considerAppend();
  }

  void _trackReadingBar(ScrollNotification notification) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (notification is ScrollStartNotification) {
      final details = notification.dragDetails;
      _barReleasedToBallistic = false;
      _barDragVelocity = details == null
          ? null
          : VelocityTracker.withKind(details.kind ?? PointerDeviceKind.touch);
      if (details?.sourceTimeStamp case final time?) {
        _barDragVelocity!.addPosition(time, details!.localPosition);
      }
      _barProgress.stop();
      return;
    }

    final metrics = notification.metrics;
    final atEdge = metrics.extentAfter <= 1 || metrics.extentBefore <= 0;
    if (notification is ScrollUpdateNotification) {
      final details = notification.dragDetails;
      if (details?.sourceTimeStamp case final time?) {
        _barDragVelocity?.addPosition(time, details!.localPosition);
      }
      if (atEdge) {
        _barProgress.show(reduced: reduced);
      } else if (!_springing && details == null && _barDragVelocity != null) {
        // The drag hands off on the first ballistic update. Remaining inertia
        // must not keep dragging the bar after it has started to settle.
        _barReleasedToBallistic = true;
        _barProgress.settle(
          velocity: -_barDragVelocity!.getVelocity().pixelsPerSecond.dy,
          reduced: reduced,
        );
        _barDragVelocity = null;
      } else if (!_springing && !_barReleasedToBallistic) {
        _barProgress.drag(notification.scrollDelta ?? 0, reduced: reduced);
      }
    } else if (notification is ScrollEndNotification) {
      if (atEdge) {
        _barProgress.show(reduced: reduced);
      } else if (!_barReleasedToBallistic) {
        _barProgress.settle(
          velocity: -(notification.dragDetails?.primaryVelocity ?? 0),
          reduced: reduced,
        );
      }
      _barReleasedToBallistic = false;
      _barDragVelocity = null;
    }
  }

  // 评论区标题被滚到顶栏下方即算进入评论区;标题已被回收时保持上一次的判断
  void _syncInComments() {
    final at = _commentsAt;
    if (at == null) return;
    // 内容不够长时标题到不了顶栏;滚到页面底部也算进入评论区
    final position = _scroll.position;
    final atEnd =
        position.extentBefore > 0 &&
        position.pixels >= position.maxScrollExtent - 1;
    final inside =
        _scroll.offset >= at - ThreadPageTokens.commentHeadingGap - 1 || atEnd;
    if (_inComments.value != inside) _inComments.value = inside;
  }

  bool _geometryScheduled = false;
  void _scheduleReadingGeometry() {
    if (_geometryScheduled) return;
    _geometryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final barBottom =
          MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
      final title = _titleKey.currentContext?.findRenderObject() as RenderBox?;
      if (title != null && title.attached && title.hasSize) {
        _titleAt =
            _scroll.offset +
            title.localToGlobal(Offset(0, title.size.height)).dy -
            barBottom;
      }
      final comments =
          _commentsKey.currentContext?.findRenderObject() as RenderBox?;
      if (comments != null && comments.attached && comments.hasSize) {
        _commentsAt =
            _scroll.offset + comments.localToGlobal(Offset.zero).dy - barBottom;
      }
      _collapsedTitle.value = _scroll.offset >= _titleAt;
      _syncReadingProgress(barBottom);
      _syncInComments();
    });
  }

  double? _commentsAt;

  int _scrollGeneration = 0;

  Future<void> _springScrollTo(double target) async {
    if (!_scroll.hasClients) return;
    final generation = ++_scrollGeneration;
    _springing = true;
    await AppMotion.scrollTo(
      _scroll.position,
      target,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
    if (mounted && generation == _scrollGeneration) _springing = false;
  }

  void _stopSpring() {
    if (!_springing || !_scroll.hasClients) return;
    _scrollGeneration++;
    _springing = false;
    _scroll.jumpTo(_scroll.offset);
  }

  Future<void> _backToTop() async {
    if (!_scroll.hasClients) return;
    if (_centerEntryKey == null) return _springScrollTo(0);
    _stopSpring();
    final generation = ++_scrollGeneration;
    _springing = true;
    final reduced = MediaQuery.disableAnimationsOf(context);
    _update(() {
      _centerEntryKey = null;
      _titleAt = 140;
      _commentsAt = null;
      // Rebase at the known first row instead of guessing a negative extent.
      _scroll.position.correctPixels(
        reduced ? 0 : _scroll.position.viewportDimension,
      );
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _scrollGeneration) return;
    await _springScrollTo(0);
  }

  /// 未挂载的评论标题直接成为惰性视口的锚点，只构建目标前一屏。
  Future<void> _showComments() async {
    if (!_scroll.hasClients) return;
    final barBottom = MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
    if (_commentsKey.currentContext == null) {
      if (!_entryIndices.containsKey(_ThreadReadEntry.headingKey)) return;
      _stopSpring();
      _scroll.jumpTo(_scroll.offset);
      final generation = ++_scrollGeneration;
      _springing = true;
      final reduced = MediaQuery.disableAnimationsOf(context);
      final target = -barBottom - ThreadPageTokens.commentHeadingGap;
      _update(() {
        _centerEntryKey = _ThreadReadEntry.headingKey;
        _titleAt = double.negativeInfinity;
        _commentsAt = -barBottom;
        _scroll.position.correctPixels(
          reduced ? target : target - _scroll.position.viewportDimension,
        );
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _scrollGeneration) return;
      await _springScrollTo(target);
      return;
    }
    final box = _commentsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final delta =
        box.localToGlobal(Offset.zero).dy -
        barBottom -
        ThreadPageTokens.commentHeadingGap;
    final position = _scroll.position;
    await _springScrollTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
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
    _preferencesApplied = true;
    if (mode == _shownMode) return;
    final anchor = _headingDy();
    if (_pendingMode != null) {
      _authorEpoch++;
      _update(() => _pendingMode = null);
      if (mode == _viewMode) {
        _fadeComments(to: 1);
        _rememberViewMode(mode);
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
    if (mounted && _pendingMode == null && _viewMode == mode) {
      _rememberViewMode(mode);
    }
  }

  void _rememberViewMode(ThreadViewMode mode) {
    final prefs = ReadingScope.maybeOf(context);
    if (prefs != null) prefs.set(prefs.prefs.copyWith(commentMode: mode));
  }

  /// 评论 ⇄ 原楼层:只对已读楼层重新排列,不读网络
  void _regroup(bool threaded) {
    _update(() {
      _beforeLoad = null;
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
    _beforeLoad = null;
    _updateCheck = null;
    _failedUpdatePage = null;
    _prefetching = false;
    _update(() {
      _pendingMode = ThreadViewMode.author;
      _loading = false;
    });
    _fadeComments(to: CommentModeTokens.pendingOpacity);
    try {
      // 通知可能落在中段,只取首屏确认楼主,不把当前回复作者当作楼主
      final owner =
          _openingAuthor ??
          await _lookupOpeningAuthor(() => mounted && epoch == _authorEpoch);
      if (!mounted || epoch != _authorEpoch) return;
      if (owner == null) throw StateError('opening author unknown');
      final detail = await _readAs(
        owner,
        1,
        shouldContinue: () => mounted && epoch == _authorEpoch,
      );
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

  Future<String?> _lookupOpeningAuthor(bool Function() shouldContinue) async {
    final first = await _readAs(null, 1, shouldContinue: shouldContinue);
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
    _beforeLoad = null;
    _updateCheck = null;
    _failedUpdatePage = null;
    _prefetching = false;
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
    _fadeComments(to: CommentModeTokens.pendingOpacity);
    try {
      final detail = await _readAs(
        null,
        1,
        shouldContinue: () => mounted && epoch == _authorEpoch,
      );
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
            ? position.minScrollExtent
            : (position.pixels + position.viewportDimension).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _alignHeading(anchor, attempt + 1),
      );
      return;
    }
    final target = (position.pixels + dy - anchor).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() > .5) {
      _scroll.jumpTo(target);
    }
  }

  /// 替换到达后只淡入新内容；减少动态效果保留 150ms 透明度过渡。
  void _fadeComments({double? from, required double to}) {
    _commentsFade.duration = MediaQuery.disableAnimationsOf(context)
        ? AppMotion.reducedFade
        : AppMotion.fade;
    if (from != null) _commentsFade.value = from;
    _commentsFade.animateTo(to);
  }

  /// 用一次完整读取替换已读楼层(首次进入、刷新、切换只看楼主)
  void _resetPages(ThreadDetail detail) {
    _generation++;
    _beforeLoad = null;
    _prefetching = false;
    _preloadEndPage = detail.page.current + widget.preloadPages - 1;
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
    _preloadEndPage = _firstPage + widget.preloadPages - 1;
    _loadedDetail = snapshot.loadedDetail;
    _hasNext = snapshot.hasNext;
    _loading = false;
    _error = null;
    _tailError = null;
    _beforeError = null;
  }

  Future<ThreadDetail> _read(
    int page, {
    bool refresh = false,
    bool Function()? shouldContinue,
  }) => _readAs(
    _authorUid,
    page,
    refresh: refresh,
    shouldContinue: shouldContinue,
  );

  Future<ThreadDetail> _readAs(
    String? author,
    int page, {
    bool refresh = false,
    bool Function()? shouldContinue,
  }) async {
    final initial = _initialDetailConsumed ? null : widget.initialDetail;
    _initialDetailConsumed = true;
    // Reuse only this navigation's landing page, never an older session's data.
    if (widget.loadPage == null &&
        _gotoUrl == null &&
        !refresh &&
        author == null &&
        initial?.tid == widget.tid &&
        initial?.page.current == page &&
        (widget.initialDetailThreadRevision == null ||
            widget.initialDetailThreadRevision ==
                _repository.client.threadCacheRevision(widget.tid)) &&
        widget.initialDetailCacheGeneration ==
            _repository.client.cacheGeneration) {
      if (shouldContinue?.call() == false) throw const ThreadReadCancelled();
      return initial!;
    }
    return widget.loadPage?.call(page, author, refresh) ??
        _repository.thread(
          widget.tid,
          page: page,
          authorUid: author,
          refresh: refresh,
          shouldContinue: shouldContinue,
        );
  }

  bool get _openingIsBlocked =>
      _orderedPosts.any((p) => postIsOpening(p) && _blocked(p));

  void _blocksChanged() {
    if (!mounted) return;
    final offset = _scroll.hasClients ? _scroll.offset : null;
    _update(() {
      if (_activeBlockSource == null && widget.blockedSource != null) {
        final sourcePid = widget.blockedSource!.pid;
        if (_focusTargetPid == sourcePid) _focusTargetPid = widget.focusPid;
        if (_highlightPid == sourcePid) _highlightPid = null;
      }
      _rebuildReadIndex();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && offset != null && _scroll.hasClients) {
        _scroll.jumpTo(
          offset.clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  Widget _blockedOpening(AppTokens t) {
    final epoch = _blocks.epoch;
    final opening = _orderedPosts.firstWhere(
      (p) => postIsOpening(p) && _blocked(p),
    );
    final note = _blocks.entryFor(opening.authorUid)?.note;
    final source = _blockedSourcePost;
    final sourceIsOpening = source?.pid == opening.pid;
    return Scaffold(
      backgroundColor: _portalLanding ? Colors.transparent : t.bg,
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.paddingOf(context).top + NavOverlay.barHeight,
                24,
                24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sourceIsOpening)
                    _blockedOpeningSource(t, source!)
                  else ...[
                    Icon(AppIcons.forbidden, color: t.text2, size: 32),
                    const SizedBox(height: 16),
                    Text(
                      '已屏蔽该用户的帖子',
                      style: AppType.headline.copyWith(color: t.text),
                    ),
                  ],
                  if (note != null) ...[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        note,
                        textAlign: TextAlign.center,
                        style: AppType.footnote.copyWith(
                          color: t.text2,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppButton(
                    label: '解除黑名单',
                    onPressed: () {
                      if (epoch != _blocks.epoch) return;
                      toggleUserBlock(
                        context,
                        uid: opening.authorUid!,
                        name: opening.author,
                        avatarUrl: opening.avatarUrl,
                        index: _blocks,
                      );
                    },
                  ),
                  if (source != null && !sourceIsOpening) ...[
                    const SizedBox(height: 16),
                    _blockedOpeningSource(t, source),
                  ],
                ],
              ),
            ),
          ),
          if (!_portalLanding)
            NavOverlay(
              leading: ChromeButton(
                icon: AppIcons.back,
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              inlineTitle: '帖子',
              collapseAt: 1,
              scrollOffset: _navOffset,
              background: t.bg,
            ),
        ],
      ),
    );
  }

  Widget _blockedOpeningSource(AppTokens t, Post post) => ConstrainedBox(
    key: _focusKey,
    constraints: const BoxConstraints(maxWidth: 280),
    child: AnimatedBuilder(
      animation: _focusHighlight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _blockedSourceRow(t, ReadingMetrics.of(context), post),
      ),
      builder: (context, child) =>
          _sourceHighlight(context, t, post.pid, _focusHighlight.value, child!),
    ),
  );

  Future<void> _refreshPostPage(Post post) async {
    final generation = _generation;
    final page = _postPages[post.pid];
    if (page == null) throw StateError('目标楼层尚未加载');
    final detail = await _read(page, refresh: true);
    if (!mounted || generation != _generation) return;
    final updated = detail.posts.where((p) => p.pid == post.pid).firstOrNull;
    if (detail.page.current != page || updated == null) {
      throw StateError('目标楼层未返回，请刷新帖子核对');
    }
    final offset = _scroll.hasClients ? _scroll.offset : null;
    _update(() {
      _remember(detail);
      _beforeAuthor = _beforeAuthor?.withPost(updated);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && offset != null && _scroll.hasClients) {
        _scroll.jumpTo(
          offset.clamp(
            _scroll.position.minScrollExtent,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  BlockedUserSource _blockSource(Post post) => BlockedUserSource(
    tid: widget.tid,
    pid: post.pid,
    floor: post.floorIsKnown ? post.floor : 0,
    title: _loadedDetail?.title ?? widget.title,
    excerpt: post.content
        .whereType<TextBlock>()
        .expand((block) sync* {
          yield* block.text.characters;
          yield '\n';
        })
        .take(UserBlockIndex.maxExcerptLength)
        .join()
        .trimRight(),
  );

  void _openPostProfile(Post post) {
    showUserDrawer(
      context,
      post.authorUid!,
      blockIndex: _blocks,
      blockSource: _blockSource(post),
      onOpenBlockSource: () => _showOriginalPost(post),
    );
  }

  Future<void> _openPostActions(Post post) async {
    if (_postActionOpen) return;
    _postActionOpen = true;
    final generation = _generation;
    final blockEpoch = _blocks.epoch;
    final sessionRevision = chhSession.identityRevision;
    bool isCurrent() =>
        generation == _generation &&
        blockEpoch == _blocks.epoch &&
        sessionRevision == chhSession.identityRevision;
    try {
      if (!_blocks.accountReady) await _blocks.load();
      if (!mounted || !isCurrent()) return;
      PostRateForm? checkedRating;
      final action = await showPostActionMenu(
        context,
        post: post,
        opening: postIsOpening(post),
        loggedIn: chhSession.loggedIn,
        blocked: _blocked(post),
        sessionChanges: chhSession,
        sessionIdentity: () =>
            chhSession.loggedIn ? chhSession.badges.uid : null,
        sessionRevision: () => chhSession.identityRevision,
        checkRating: () async {
          final form = await _interactions.rateForm(
            tid: widget.tid,
            pid: post.pid,
            pageUrl: post.actions.ratingUrl,
          );
          checkedRating = form;
          return form;
        },
        isSelf:
            post.authorUid != null && post.authorUid == chhSession.badges.uid,
      );
      if (!mounted || !isCurrent() || action == null) return;
      if (action == PostMenuAction.reply) {
        _postActionOpen = false;
        _openComposer(post);
        return;
      }
      if (action == PostMenuAction.blockUser) {
        final uid = post.authorUid;
        if (uid != null) {
          await toggleUserBlock(
            context,
            uid: uid,
            name: post.author,
            avatarUrl: post.avatarUrl,
            index: _blocks,
            src: _blockSource(post),
            onOpenSource: () => _showOriginalPost(post),
          );
        }
        return;
      }
      if (action == PostMenuAction.login || !chhSession.loggedIn) {
        await Navigator.of(context).pushNamed('/login');
        return;
      }
      if (chhSession.badges.uid == null) {
        AppToast.show(context, '登录信息读取中，请稍后再试');
        return;
      }
      final supplement = action == PostMenuAction.supplement;
      if (supplement &&
          (post.authorUid == null || post.authorUid != chhSession.badges.uid)) {
        return;
      }
      final rating = action == PostMenuAction.rating;
      final result = await showPostInteractionSheet(
        context,
        kind: supplement
            ? PostInteractionKind.supplement
            : rating
            ? PostInteractionKind.rating
            : PostInteractionKind.comment,
        tid: widget.tid,
        post: post,
        repository: _interactions,
        sessionIdentity: () =>
            chhSession.loggedIn ? chhSession.badges.uid : null,
        sessionChanges: chhSession,
        sessionRevision: () => chhSession.identityRevision,
        pageUrl: supplement
            ? post.actions.supplementUrl
            : rating
            ? post.actions.ratingUrl
            : post.actions.commentUrl,
        initialRatingForm: rating ? checkedRating : null,
        onCheckResult: () => _refreshPostPage(post),
      );
      if (!mounted || generation != _generation || result == null) return;
      if (result.isSuccess) {
        try {
          await _refreshPostPage(post);
          if (mounted) {
            AppToast.show(
              context,
              supplement
                  ? '已补充'
                  : rating
                  ? '评分成功'
                  : '点评已发表',
            );
          }
        } catch (_) {
          if (mounted) AppToast.show(context, '已提交，内容刷新失败，请刷新核对');
        }
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        AppToast.show(context, '读取未完成，请重试');
      }
    } finally {
      _postActionOpen = false;
    }
  }

  Future<void> _unlockPost(Post post) async {
    if (!_unlocking.add(post.pid)) return;
    final generation = _generation;
    final page = _postPages[post.pid];
    try {
      final password = await showPasswordSheet(context, title: '输入帖子密码');
      if (!mounted ||
          password == null ||
          generation != _generation ||
          page == null) {
        return;
      }
      final pagePrefix = _pages[page]?.cookiePrefix;
      final prefix = pagePrefix != null && pagePrefix.isNotEmpty
          ? pagePrefix
          : _repository.cookiePrefix;
      if (prefix == null || prefix.isEmpty) throw StateError('缺少 Cookie 前缀');
      await _repository.unlockPost(
        pid: post.pid,
        password: password,
        cookiePrefix: prefix,
      );
      if (!mounted || generation != _generation) return;
      final detail = await _read(page, refresh: true);
      if (!mounted || generation != _generation) return;
      final unlocked = detail.posts.where((p) => p.pid == post.pid).firstOrNull;
      if (detail.page.current != page || unlocked == null) {
        throw StateError('目标楼层未返回');
      }
      if (unlocked.lock?.needsPassword == true) {
        AppToast.show(context, '密码不正确');
        return;
      }
      final offset = _scroll.hasClients ? _scroll.offset : null;
      _update(() {
        _remember(detail);
        _beforeAuthor = _beforeAuthor?.withPost(unlocked);
      });
      _recordHistoryIfReadable(detail);
      // 局部替换只更新条目；展开数量、查看方式与其他已读页均保留。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && offset != null && _scroll.hasClients) {
          _scroll.jumpTo(
            offset.clamp(
              _scroll.position.minScrollExtent,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        AppToast.show(context, '解锁未完成，请重试');
      }
    } finally {
      _unlocking.remove(post.pid);
    }
  }

  Future<void> _unlockForum(int fid) async {
    if (_forumPasswordOpen) return;
    _forumPasswordOpen = true;
    try {
      final success = await showForumPasswordUnlock(
        context,
        fid,
        repository: _repository,
      );
      if (mounted && success) await _loadInitial(useGoto: true, refresh: true);
    } finally {
      _forumPasswordOpen = false;
    }
  }

  void _remember(ThreadDetail detail) => _rememberPages([detail]);

  void _rememberPages(List<ThreadDetail> details) {
    for (final detail in details) {
      _storePage(detail);
    }
    if (_portalLanding) {
      _chrome.title = details.last.title;
      _chrome.sourceUrl = threadSourceUrl(widget.tid, page: _firstPage);
    }
    _rebuildReadIndex();
  }

  void _storePage(ThreadDetail detail) {
    // Page appends must not move the denominator while the viewport stays still.
    _readingTotalPosts ??= detail.replyCount == null
        ? null
        : detail.replyCount! + 1;
    if (_readingTotalPosts == null &&
        _authorUid == null &&
        detail.page.current == 1 &&
        !detail.page.hasNext &&
        detail.posts.every((post) => post.floorIsKnown)) {
      _readingTotalPosts = detail.posts.fold<int>(
        0,
        (last, post) => post.floor > last ? post.floor : last,
      );
    }
    // 后续页可能省略统计；仅用实际返回的计数更新已经读到的数据。
    final sequence = detail.replyCount == null || widget.loadPage != null
        ? null
        : _repository.cachedPageSequence(detail, authorUid: _authorUid);
    final useCount =
        detail.replyCount != null &&
        (sequence == null || sequence >= (_replyCountSequence ?? 0));
    if (useCount && sequence != null) _replyCountSequence = sequence;
    _loadedDetail = ThreadDetail(
      tid: detail.tid,
      cookiePrefix: detail.cookiePrefix,
      fid: detail.fid,
      forumName: detail.forumName,
      title: detail.title,
      posts: detail.posts,
      viewCount: detail.viewCount ?? _loadedDetail?.viewCount,
      replyCount: useCount ? detail.replyCount : _loadedDetail?.replyCount,
      favoriteCount: detail.favoriteCount ?? _loadedDetail?.favoriteCount,
      poll: detail.poll ?? _loadedDetail?.poll,
      page: detail.page,
    );
    _pages[detail.page.current] = detail;
    // 只有真正的首楼才能确定楼主；提醒落地页的首条回复不是楼主。
    final opening = detail.posts.where((p) => postIsOpening(p)).firstOrNull;
    _openingAuthor ??= opening?.authorUid;
  }

  void _verifyReplyCount() {
    if (widget.loadPage != null || _authorUid != null) return;
    final coverage = _repository.cachedThreadCoverage(
      widget.tid,
      observedReplies: widget.observedReplies,
    );
    final replies = coverage?.replyCount;
    final sequence = coverage?.verifiedCountSequence;
    _verifiedReplyCount = replies != null && sequence != null
        ? (replies: replies, sequence: sequence)
        : null;
    if (_replyCount case final total? when _verifiedReplyCount != null) {
      _readingTotalPosts = total + 1;
    }
  }

  void _recordHistoryIfReadable(ThreadDetail detail) {
    if (_historyRecorded ||
        _openingIsBlocked ||
        !detail.posts.any(
          (post) =>
              !_blocked(post) &&
              post.lock == null &&
              (post.content.isNotEmpty ||
                  post.notes.isNotEmpty ||
                  (postIsOpening(post) && detail.poll != null)),
        )) {
      return;
    }
    final cachedOpeningPage = detail.page.current > 1 && widget.loadPage == null
        ? _repository.cachedThreadPage(widget.tid, 1)
        : null;
    final opening =
        detail.posts.where(postIsOpening).firstOrNull ??
        cachedOpeningPage?.posts.where(postIsOpening).firstOrNull;
    final previous = opening == null || detail.forumName == null
        ? historyIndex.all
              .where(
                (entry) =>
                    entry.type == HistoryType.thread && entry.id == widget.tid,
              )
              .firstOrNull
        : null;
    _historyRecorded = true;
    historyIndex.record(
      type: HistoryType.thread,
      id: widget.tid,
      title: detail.title,
      fid: detail.fid ?? widget.fid ?? previous?.fid,
      forumName:
          detail.forumName ??
          cachedOpeningPage?.forumName ??
          previous?.forumName,
      author: opening?.author ?? previous?.author ?? '',
    );
  }

  Future<void> _loadInitial({
    bool useGoto = false,
    int? page,
    bool refresh = false,
    bool resetThread = false,
  }) async {
    final coverage = !refresh && widget.loadPage == null
        ? _repository.cachedThreadCoverage(
            widget.tid,
            observedReplies: widget.observedReplies,
          )
        : null;
    final generation = ++_generation;
    _beforeLoad = null;
    _updateCheck = null;
    _prefetching = false;
    if (_portalLanding && _pages.isEmpty && !_landingSkeletonVisible) {
      _landingSkeletonDelay?.cancel();
      _landingSkeletonDelay = Timer(AppMotion.skeletonDelay, () {
        if (mounted) setState(() => _landingSkeletonVisible = true);
      });
    }
    _update(() {
      _loading = true;
      _error = null;
      _tailError = null;
      _beforeError = null;
      _failedUpdatePage = null;
    });
    try {
      final goto = useGoto ? _gotoUrl : null;
      final detail = goto == null
          ? await _read(
              page ?? widget.initialPage,
              refresh: refresh,
              shouldContinue: () => mounted && generation == _generation,
            )
          : await (widget.loadGoto?.call(goto) ??
                _repository.threadAtUrl(
                  goto,
                  tid: widget.tid,
                  refresh: refresh,
                  shouldContinue: () => mounted && generation == _generation,
                ));
      if (!mounted || generation != _generation) return;
      _landingSkeletonDelay?.cancel();
      final firstLanding = _landingPaintPending && _pages.isEmpty;
      _update(() {
        // 主动刷新后,进入只看楼主前的旧楼层不再可信
        if (refresh) _beforeAuthor = null;
        if (resetThread) {
          _loadedDetail = null;
          _replyCountSequence = null;
          _verifiedReplyCount = null;
          _focusDone = true;
          _focusTargetPid = null;
          _highlightPid = null;
          _centerEntryKey = null;
          _titleAt = 140;
          _commentsAt = null;
          if (_scroll.hasClients) _scroll.position.correctPixels(0);
        }
        _readingTotalPosts = null;
        _resetPages(detail);
        if (coverage?.verifiedCountSequence != null) {
          _verifyReplyCount();
          _rebuildProgressIndex();
        }
      });
      if (firstLanding) _startLandingArrival();
      if (_preferAuthor) {
        _preferAuthor = false;
        await _enterAuthorMode(null);
        if (!mounted) return;
      }
      // 等首次有效加载成功后再通知列表；刷新和分页不推进本次打开的已看计数。
      if (!_markedRead && widget.seenReplies != null) {
        _markedRead = true;
        threadReadIndex.markRead(widget.tid, widget.seenReplies!);
      }
      _recordHistoryIfReadable(detail);
      final observed = widget.observedReplies;
      final previous = coverage?.replyCount;
      if (coverage != null &&
          _authorUid == null &&
          (!coverage.recent ||
              observed == null ||
              previous == null ||
              observed != previous)) {
        final checkDecrease =
            observed != null && previous != null && observed < previous;
        final boundary = math.max(coverage.lastPage, detail.page.current);
        unawaited(
          _refreshFrom(
            checkDecrease ? 1 : boundary,
            previousReplies: previous,
            checkDecrease: checkDecrease,
            boundary: boundary,
          ),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_portalLanding || _scroll.hasClients || _openingIsBlocked) {
          _locateFocusedPost();
        }
        _considerAppend();
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _landingSkeletonDelay?.cancel();
      _update(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refreshEntireThread() {
    if (widget.loadPage == null) _repository.invalidateThread(widget.tid);
    return _loadInitial(page: 1, refresh: true, resetThread: true);
  }

  int _visibleTailPage() {
    final top = MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
    final bottom =
        MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).bottom;
    for (final row in _mountedReadingRows().reversed) {
      if (row.y >= bottom || row.y + row.height <= top) continue;
      final index = _entryIndices[row.key];
      if (index == null || row.key == _ThreadReadEntry.headingKey) continue;
      final page = _postPages[_entries[index - 1].post.pid];
      if (page != null) return page;
    }
    return _lastPage;
  }

  Future<void> _checkTailForUpdates({({String key, double y})? anchor}) async {
    if (_pages.isEmpty || !_routeCurrent) return;
    await _refreshFrom(
      _failedUpdatePage ?? _visibleTailPage(),
      previousReplies: _authorUid == null ? _replyCount : null,
      fromTail: true,
      tailAnchor: anchor,
    );
  }

  Future<void> _refreshVisibleEnd() {
    final anchor = _endPullAnchor;
    _endPullAnchor = null;
    return _checkTailForUpdates(anchor: anchor);
  }

  Future<void> _refreshFrom(
    int start, {
    required int? previousReplies,
    bool fromTail = false,
    ({String key, double y})? tailAnchor,
    bool checkDecrease = false,
    int? boundary,
  }) async {
    if (_updateCheck != null ||
        _loading ||
        _loadingBefore ||
        _prefetching ||
        _navigationBusy ||
        _pendingMode != null ||
        _expandingRoot != null ||
        _composerOpen ||
        _postActionOpen ||
        _unlocking.isNotEmpty ||
        _pages.isEmpty) {
      return;
    }
    final generation = _generation;
    final check = Object();
    bool active() =>
        mounted && generation == _generation && identical(_updateCheck, check);
    void invalidate(int page) {
      if (widget.loadPage == null) {
        _repository.invalidateThread(widget.tid, fromPage: page);
      }
    }

    Future<ThreadDetail> read(int page) =>
        _read(page, refresh: true, shouldContinue: active);
    final lastShown = _lastPage;
    final dragRevision = _dragRevision;
    final initialAnchor =
        tailAnchor ??
        (fromTail && _scroll.hasClients ? _readingAnchor() : null);
    _update(() {
      _updateCheck = check;
      _failedUpdatePage = null;
      _tailError = null;
      _sourceMayHaveChanged = true;
      _rebuildReadIndex();
    });
    try {
      var page = start;
      final preceding =
          _pages[page - 1] ??
          (_authorUid == null && widget.loadPage == null && page > 1
              ? _repository.cachedThreadPage(widget.tid, page - 1)
              : null);
      if (!checkDecrease) invalidate(page);
      var detail = await read(page);
      if (!active()) return;
      final decreased =
          _authorUid == null &&
          previousReplies != null &&
          detail.replyCount != null &&
          detail.replyCount! < previousReplies;
      final precedingPids = preceding?.posts
          .where((post) => !postIsOpening(post))
          .map((post) => post.pid)
          .toSet();
      final shifted =
          page > 1 &&
          (detail.page.current != page ||
              detail.posts.any(
                (post) => precedingPids?.contains(post.pid) ?? false,
              ));
      final rebuild = decreased || shifted;
      if (rebuild) {
        if (page != 1) {
          page = 1;
          invalidate(page);
          detail = await read(page);
        } else if (checkDecrease) {
          invalidate(2);
        }
      } else if (checkDecrease &&
          boundary != null &&
          boundary > 1 &&
          detail.replyCount != null &&
          detail.replyCount! > previousReplies!) {
        // A stale, lower list count prompted this check, but the source grew.
        page = boundary;
        invalidate(page);
        detail = await read(page);
      }
      if (!active()) return;
      if (detail.page.current != page || detail.posts.isEmpty) {
        throw StateError('未能核对帖子分页');
      }

      final refreshed = [detail];
      if (fromTail && !rebuild) {
        final known = {
          for (final entry in _pages.entries)
            if (entry.key < page)
              for (final post in entry.value.posts) post.pid,
          for (final post in detail.posts) post.pid,
        };
        // Refresh any loaded suffix, then read at most one newly available page
        // immediately. Regular pagination takes over beyond that page.
        for (
          var next = page + 1;
          next <= lastShown + 1 && refreshed.last.page.hasNext;
          next++
        ) {
          final later = await read(next);
          if (!active()) return;
          if (later.page.current != next ||
              !later.posts.any((post) => !known.contains(post.pid))) {
            throw StateError('未能核对帖子分页');
          }
          known.addAll(later.posts.map((post) => post.pid));
          refreshed.add(later);
        }
      }
      await _waitForNavigationIdle(generation);
      if (!active()) return;
      final anchor = !fromTail || !_scroll.hasClients
          ? null
          : dragRevision == _dragRevision
          ? initialAnchor
          : _readingAnchor();
      final anchorIndex = anchor == null ? null : _entryIndices[anchor.key];
      _update(() {
        _sourceMayHaveChanged = false;
        if (rebuild || (page >= _firstPage && page <= lastShown + 1)) {
          if (rebuild) _pages.clear();
          final last = refreshed.last;
          if (!last.page.hasNext) {
            _pages.removeWhere((number, _) => number > last.page.current);
          }
          final count = refreshed.reversed
              .map((item) => item.replyCount)
              .whereType<int>()
              .firstOrNull;
          if (_authorUid == null && count != null) {
            _readingTotalPosts = count + 1;
          }
          _verifyReplyCount();
          _rememberPages(refreshed);
          _hasNext = _pages[_lastPage]!.page.hasNext;
          _beforeAuthor = null;
          if (anchor != null && anchorIndex != _entryIndices[anchor.key]) {
            _retainReadingAnchor(anchor);
          }
        } else {
          // Reuse cached prefix pages in order before inserting this page.
          _verifyReplyCount();
          _rebuildReadIndex();
        }
      });
    } on ThreadReadCancelled {
      return;
    } catch (error) {
      if (!active()) return;
      if (fromTail) {
        _update(() {
          _failedUpdatePage = start;
          _tailError = error;
        });
      }
    } finally {
      if (mounted && identical(_updateCheck, check)) {
        _update(() => _updateCheck = null);
        WidgetsBinding.instance.addPostFrameCallback((_) => _considerAppend());
      }
    }
  }

  void _startLandingArrival() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_openingIsBlocked || MediaQuery.disableAnimationsOf(context)) {
        _landingArrival.value = 1;
      } else {
        // Paint the first viewport before starting the paint-only transition.
        await _landingArrival.forward().orCancel.catchError((Object error) {
          if (error is! TickerCanceled) throw error;
        });
      }
      if (!mounted) return;
      // Wait for the final fade frame to paint before scheduling cache layout.
      binding.ensureVisualUpdate();
      await binding.endOfFrame;
      if (!mounted) return;
      setState(() {
        _landingPaintPending = false;
        _landingSkeletonVisible = false;
      });
      binding.addPostFrameCallback((_) {
        if (!mounted) return;
        _considerAppend();
      });
    });
  }

  void _considerAppend() {
    if (!mounted) return;
    _schedulePreload();
    if (_landingPaintPending ||
        !_routeCurrent ||
        _navigationBusy ||
        !_scroll.hasClients ||
        _expandingRoot != null ||
        _pendingMode != null ||
        _composerOpen ||
        _unlocking.isNotEmpty ||
        _loading ||
        _loadingBefore ||
        _updateCheck != null ||
        _tailError != null ||
        !_hasNext ||
        _pages.isEmpty ||
        _error != null ||
        _pauseHiddenAppend) {
      return;
    }
    if (_scroll.position.extentAfter < 650) _append();
  }

  Future<void> _append({
    bool retry = false,
    bool fromExpansion = false,
    bool background = false,
  }) async {
    if (_loading ||
        _loadingBefore ||
        _updateCheck != null ||
        _prefetching ||
        _navigationBusy ||
        !_hasNext ||
        _pages.isEmpty ||
        (_tailError != null && !retry)) {
      return;
    }
    final generation = _generation;
    final target = _lastPage + 1;
    final previousRoots = _index.roots.length;
    final completion = Completer<void>();
    _appendCompletion = completion;
    _prefetching = background;
    if (!background) {
      _update(() {
        _loading = true;
        _tailError = null;
      });
    }
    try {
      final detail = await _read(
        target,
        refresh: retry,
        shouldContinue: () =>
            mounted &&
            generation == _generation &&
            (!background || _canPreload),
      );
      await _waitForNavigationIdle(generation);
      if (!mounted || generation != _generation) return;
      if (background && !_canPreload) return;
      final advanced =
          detail.page.current == target &&
          detail.posts.any((p) => !_knownPids.contains(p.pid));
      _update(() {
        // 越界静默回第一页时不重复追加，也不进入无限请求循环。
        if (advanced) _remember(detail);
        _hasNext = advanced && detail.page.hasNext;
        if (!background) {
          _pauseHiddenAppend =
              fromExpansion ||
              (_grouped && _index.roots.length <= previousRoots);
        }
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _considerAppend());
    } on ThreadReadCancelled {
      if (!background && mounted && generation == _generation) {
        _update(() => _loading = false);
      }
    } catch (error) {
      await _waitForNavigationIdle(generation);
      if (!mounted || generation != _generation) return;
      _update(() {
        _loading = false;
        _tailError = error;
      });
    } finally {
      completion.complete();
      if (identical(_appendCompletion, completion)) _appendCompletion = null;
      if (mounted && generation == _generation) {
        _prefetching = false;
        _schedulePreload();
      }
    }
  }

  // Read only mounted lazy rows. Source counts and estimated scroll extents
  // cannot tell us the height of newly inserted paragraphs or images.
  List<({String key, double y, double height})> _mountedReadingRows() {
    final rows = <({String key, double y, double height})>[];
    void visit(Element element) {
      final key = element.widget.key;
      if (key is _ThreadRowKey) {
        RenderObject? box;
        void content(Element child) {
          if (child.widget.key == ValueKey(key.value) ||
              child.widget.key == _focusKey) {
            box = child.findRenderObject();
          } else {
            child.visitChildElements(content);
          }
        }

        element.visitChildElements(content);
        final measured = box ?? element.findRenderObject();
        if (measured is RenderBox && measured.attached && measured.hasSize) {
          rows.add((
            key: key.value,
            y: measured.localToGlobal(Offset.zero).dy,
            height: measured.size.height,
          ));
        }
        return;
      }
      element.visitChildElements(visit);
    }

    _readListKey.currentContext?.visitChildElements(visit);
    // The sliver before the retained center grows in reverse child order.
    rows.sort((a, b) => a.y.compareTo(b.y));
    return rows;
  }

  ({String key, double y})? _readingAnchor() {
    final top = MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
    for (final row in _mountedReadingRows()) {
      if (row.key == _ThreadReadEntry.headingKey) continue;
      if (row.y + row.height > top && row.height > 0) {
        return (key: row.key, y: row.y);
      }
    }
    return null;
  }

  void _retainReadingAnchor(({String key, double y})? anchor) {
    if (anchor == null || !_entryIndices.containsKey(anchor.key)) return;
    _centerEntryKey = anchor.key;
    // Rebase the sliver at the same row and pixel before the next paint.
    final firstReply =
        _entryIndices[anchor.key] ==
        (_entryIndices[_ThreadReadEntry.headingKey] ?? -2) + 1;
    _scroll.position.correctPixels(
      -anchor.y + (firstReply ? ThreadPageTokens.cardInset : 0),
    );
    _titleAt = double.negativeInfinity;
    _commentsAt = double.negativeInfinity;
  }

  Future<void> _loadBefore() async {
    if (_loading ||
        _loadingBefore ||
        _updateCheck != null ||
        _pendingMode != null ||
        !_routeCurrent ||
        _pages.isEmpty ||
        _firstPage <= 1) {
      return;
    }
    final firstPage = _firstPage;
    final lastTarget = math.max(
      1,
      firstPage - ThreadPageTokens.loadBeforePages,
    );
    final generation = _generation;
    final load = Object();
    bool active() =>
        mounted && generation == _generation && identical(_beforeLoad, load);
    final retry = _beforeError != null;
    _update(() {
      _beforeLoad = load;
      _beforeError = null;
    });
    final pages = <ThreadDetail>[];
    Object? failure;
    try {
      // Finish any existing forward prefetch before issuing backward reads.
      await _appendCompletion?.future;
      for (var page = firstPage - 1; page >= lastTarget; page--) {
        if (!active()) return;
        final detail = await _read(
          page,
          refresh: retry && page == firstPage - 1,
          shouldContinue: active,
        );
        if (!active()) return;
        if (detail.page.current != page) {
          throw StateError('Expected page $page, got ${detail.page.current}');
        }
        pages.add(detail);
      }
    } catch (error) {
      failure = error;
    }
    if (!active()) return;
    final anchor = pages.isEmpty ? null : _readingAnchor();
    _update(() {
      if (pages.isNotEmpty) _rememberPages(pages);
      _retainReadingAnchor(anchor);
      _beforeLoad = null;
      _beforeError = failure;
    });
  }

  ThreadPoll? _pollSource;
  ThreadPoll? _updatedPoll;
  int? _pollRevision;

  Widget? _pollFor(Post post) {
    if (!postIsOpening(post) || post.lock != null) return null;
    final poll = _pages[1]?.poll;
    if (poll == null) return null;
    final revision = chhSession.identityRevision;
    if (!identical(_pollSource, poll) || _pollRevision != revision) {
      _pollSource = poll;
      _updatedPoll = null;
      _pollRevision = revision;
    }
    return ConnectedThreadPoll(
      key: ValueKey('poll-${widget.tid}'),
      poll: _updatedPoll ?? poll,
      onUpdated: (fresh) {
        if (identical(_pollSource, poll) && _pollRevision == revision) {
          _updatedPoll = fresh;
        }
      },
    );
  }

  bool get _focusOnFeedback {
    final post = _index.postsByPid[_focusTargetPid];
    return _focusOpeningFeedback &&
        post != null &&
        postIsOpening(post) &&
        post.lock == null &&
        (post.rating?.isEmpty == false || post.comments.isNotEmpty);
  }

  bool _isFocusEntry(_ThreadReadEntry entry) =>
      entry.post.pid == _focusTargetPid &&
      (_focusOnFeedback
          ? entry.kind == _ThreadEntryKind.footer
          : entry.isStart);

  Future<void> _locateFocusedPost() async {
    if (_focusDone) return;
    if (_focusTargetPid == null && _focusOpeningFeedback) {
      _focusTargetPid = _orderedPosts.where(postIsOpening).firstOrNull?.pid;
    }
    if (_focusTargetPid == null) return;
    final generation = _generation;
    final targetPid = _focusTargetPid;
    final fromBlockSource = targetPid == _activeBlockSource?.pid;
    final sourceInBlockedOpening = fromBlockSource && _openingIsBlocked;
    if (sourceInBlockedOpening && _blockedSourcePost == null) {
      _focusDone = true;
      return;
    }
    final groupedRoot = _index.rootPidFor(_focusTargetPid!);
    if (!sourceInBlockedOpening &&
        _grouped &&
        groupedRoot != null &&
        groupedRoot != _focusTargetPid) {
      final replies = _conversationReplies(groupedRoot);
      final position = replies.indexWhere((p) => p.pid == _focusTargetPid);
      _update(() {
        _visibleReplies[groupedRoot] = position + 1;
        _rebuildReadEntries();
      });
    }
    final index = sourceInBlockedOpening
        ? -1
        : _entries.indexWhere(_isFocusEntry);
    if (index < 0 && !sourceInBlockedOpening) {
      _focusDone = true;
      if (_blocks.isBlocked(_index.postsByPid[_focusTargetPid]?.authorUid)) {
        if (mounted) AppToast.show(context, '该楼层已被黑名单隐藏');
        return;
      }
      AppLog.w('FOCUS', 'pid=$_focusTargetPid 不在提醒落地页');
      if (mounted) {
        AppToast.show(context, '暂时无法定位该楼层，已显示可阅读的内容');
      }
      return;
    }
    _focusDone = true;
    if (index >= 0 &&
        fromBlockSource &&
        _scroll.hasClients &&
        _focusKey.currentContext == null) {
      _update(
        () => _retainReadingAnchor((
          key: _entries[index].key,
          y: MediaQuery.paddingOf(context).top + NavOverlay.barHeight + 12,
        )),
      );
    }
    for (var attempt = 0; attempt < 12; attempt++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _generation ||
          targetPid != _focusTargetPid ||
          (!sourceInBlockedOpening && !_scroll.hasClients)) {
        return;
      }
      final context =
          (_focusOnFeedback ? _feedbackKey : _focusKey).currentContext;
      if (context != null && context.mounted) {
        await AppMotion.revealInScroll(context, alignment: .14);
        if (!mounted ||
            generation != _generation ||
            targetPid != _focusTargetPid) {
          return;
        }
        _update(() => _highlightPid = targetPid);
        if (fromBlockSource && MediaQuery.disableAnimationsOf(this.context)) {
          _focusHighlight.value = 0;
          _focusHighlight.animateTo(1, duration: AppMotion.reducedFade);
        } else {
          _focusHighlight.forward(from: 0);
        }
        return;
      }
      if (sourceInBlockedOpening) return;
      final position = _scroll.position;
      // 逐步靠近目标，懒列表构建后再精确定位。
      final estimate =
          position.minScrollExtent +
          (position.maxScrollExtent - position.minScrollExtent) *
              (index + 1) /
              (_entries.length + 1);
      _scroll.jumpTo(
        estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
    AppLog.w('FOCUS', 'pid=$_focusTargetPid 无法精确定位');
  }

  Widget? _referenceContext(Post post) {
    final reference = _index.directTargetFor(post.pid);
    if (_grouped || reference == null || postIsOpening(post)) return null;
    if (reference.tid == widget.tid &&
        _blocks.isBlocked(_index.postsByPid[reference.pid]?.authorUid)) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '引用已屏蔽楼层',
          style: AppType.footnote.copyWith(color: AppTokens.of(context).text2),
        ),
      );
    }
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
        _loadingBefore ||
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
    if (_conversationReplies(rootPid).length < target && _hasNext) {
      final pending = _prefetching ? _appendCompletion : null;
      if (pending != null) {
        // An explicit expansion adopts the page already being prefetched.
        // Do not drop the tap or fetch a second page for the same click.
        await pending.future;
      } else {
        await _append(retry: _tailError != null, fromExpansion: true);
      }
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
          ? target.clamp(0, _conversationReplies(rootPid).length)
          : visible;
      _expandingRoot = null;
      _pauseHiddenAppend = true;
      _rebuildReadEntries();
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

  bool _hasReplyExpansion(int remaining) =>
      remaining > 0 || _hasNext || _tailError != null;

  int _remainingReplies(Post post) =>
      _conversationReplies(post.pid).length - (_visibleReplies[post.pid] ?? 0);

  String _replyExpansionLabel(Post post, int remaining) =>
      _expandingRoot == post.pid
      ? '正在加载回复…'
      : _tailError != null
      ? '回复加载失败，点击重试'
      : remaining > 0
      ? '展开 $remaining 条回复'
      : '继续加载回复';

  Widget _replyExpansion(
    BuildContext context,
    Post post, {
    required bool last,
  }) {
    final metrics = ReadingMetrics.of(context);
    final t = AppTokens.of(context);
    final remaining = _remainingReplies(post);
    final finished = !_hasReplyExpansion(remaining);
    final label = _replyExpansionLabel(post, remaining);
    final bottomPadding = last && !finished
        ? metrics.postVPad.clamp(
            0.0,
            ListEndTokens.markerPadding(
              ThreadPageTokens.cardInset + _expansionTextInset(context, post),
            ),
          )
        : metrics.postVPad;
    final content = finished
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.commentGutter + metrics.avatar + 10,
              0,
              metrics.commentGutter,
              bottomPadding,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PressScale(
                key: ValueKey('thread-expand-replies-${post.pid}'),
                semanticLabel: label,
                onTap:
                    _loading ||
                        _expandingRoot != null ||
                        _replyReveal.isAnimating
                    ? null
                    : () => _expandReplies(post.pid),
                child: Container(
                  height: ThreadPageTokens.expansionHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 11),

                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: ThreadPageTokens.expansionLineWidth,
                        height: ThreadPageTokens.expansionLineHeight,
                        color: t.text3,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ThreadPageTokens.expansionLabel.copyWith(
                            color: t.text2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(AppIcons.down, size: 13, color: t.text2),
                    ],
                  ),
                ),
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
      _highlightPid = null;
      _focusHighlight.value = 1;
      _focusOpeningFeedback = false;
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailPage(
          tid: reference.tid,
          title: '引用楼层',
          gotoUrl: _postLocationUrl(reference.tid, reference.pid),
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
      quoteOf: quoted?.author,
      quoteText:
          quoted != null &&
              quoted.content.whereType<TextBlock>().any(
                (block) => block.text.trim().isNotEmpty,
              )
          ? threadReplySummary(quoted)
          : null,
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
        _readingTotalPosts = null;
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
    _preloadTimer?.cancel();
    _navigationGesture?.removeListener(_navigationGestureChanged);
    _navigationIdle?.complete();
    _navigationIdle = null;
    WidgetsBinding.instance.removeObserver(this);
    for (final images in _replyImages.values) {
      images.dispose();
    }
    _generation++;
    _authorEpoch++;
    chhSession.removeListener(_sessionChanged);
    _blocks.removeListener(_blocksChanged);
    for (final hold in _heldReplies.values) {
      hold.dispose();
    }
    _barProgress.dispose();
    _landingSkeletonDelay?.cancel();
    if (_portalLanding) {
      _landingArrival.dispose();
    } else {
      _chrome.dispose();
    }
    _scroll.dispose();
    _inComments.dispose();
    _commentsOpacity.dispose();
    _commentsFade.dispose();
    _replyRevealCurve.dispose();
    _replyReveal.dispose();
    _focusHighlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = Builder(builder: _buildReader);
    final keyboardStableReader = Builder(
      builder: (context) {
        final media = MediaQuery.of(context);
        // The reply editor is a separate route and owns the keyboard insets.
        // Keep the reader and its list anchored while the IME opens or closes.
        return MediaQuery(
          data: media.viewInsets.bottom == 0
              ? media
              : media.copyWith(
                  viewInsets: media.viewInsets.copyWith(bottom: 0),
                  padding: media.padding.copyWith(
                    bottom: media.viewPadding.bottom,
                  ),
                ),
          child: reader,
        );
      },
    );
    return ImageViewerChromeScope(
      child: Builder(
        builder: (context) => ValueListenableBuilder<bool>(
          valueListenable: ImageViewerChromeController.maybeOf(
            context,
          )!.covered,
          child: keyboardStableReader,
          builder: (context, covered, child) {
            // Back makes this route current before the viewer's Hero lands.
            _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
            if (!_routeCurrent) _beforeLoad = null;
            _viewerCovered = covered;
            _navigationGestureChanged();
            return child!;
          },
        ),
      ),
    );
  }

  Widget _buildReader(BuildContext context) {
    final t = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    final top = MediaQuery.paddingOf(context).top;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _handleScroll();
    });
    if (_openingIsBlocked) return _blockedOpening(t);
    final page = Scaffold(
      extendBody: true,
      backgroundColor: _portalLanding ? Colors.transparent : t.bg,
      body: Builder(
        builder: (bodyContext) {
          // Capture the actual bar height for the tail and image viewport sizing.
          final readerInsets = MediaQuery.paddingOf(bodyContext);
          return Stack(
            children: [
              _initialArrival(
                _pages.isEmpty
                    ? (_loading && !_portalLanding ? null : _initialState())
                    : ChhersRefreshIndicator(
                        edgeOffset: top + NavOverlay.barHeight,
                        endEdgeOffset: readerInsets.bottom,
                        onRefresh: _refreshEntireThread,
                        onRefreshAtEnd:
                            !_loading &&
                                _updateCheck == null &&
                                (!_hasNext || _failedUpdatePage != null)
                            ? _refreshVisibleEnd
                            : null,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.depth == 0 &&
                                notification.metrics.axis == Axis.vertical) {
                              _trackReadingBar(notification);
                            }
                            if (notification.depth == 0 &&
                                notification is ScrollStartNotification &&
                                notification.dragDetails != null) {
                              _stopSpring();
                              _dragRevision++;
                              _endPullAnchor =
                                  notification.metrics.extentAfter <= 1
                                  ? _readingAnchor()
                                  : null;
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
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: metrics.textScaler(
                                MediaQuery.textScalerOf(context),
                              ),
                            ),
                            child: AnchoredReadingList(
                              key: _readListKey,
                              controller: _scroll,
                              centerIndex: _entryIndices[_centerEntryKey] ?? 0,
                              scrollCacheExtent: _landingPaintPending
                                  ? const ScrollCacheExtent.pixels(0)
                                  : null,
                              itemCount: _entries.length + 2,
                              findChildIndexCallback: (key) {
                                if (key == _focusKey) {
                                  final index = _entries.indexWhere(
                                    _isFocusEntry,
                                  );
                                  return index < 0 ? null : index + 1;
                                }
                                return key is ValueKey<String>
                                    ? _entryIndices[key.value]
                                    : null;
                              },
                              itemBuilder: (context, index) {
                                final metrics = ReadingMetrics.of(context);
                                if (index == 0) {
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      top: top + NavOverlay.barHeight,
                                    ),
                                    child: _heading(t),
                                  );
                                }
                                // 标题之后的内容随查看方式切换淡化/淡入
                                final heading =
                                    _entryIndices[_ThreadReadEntry
                                        .headingKey] ??
                                    _entries.length + 1;
                                if (index == _entries.length + 1) {
                                  return _landingFade(
                                    t,
                                    ContentFade(
                                      background: t.bg,
                                      opacity: _commentsOpacity,
                                      child: _tail(
                                        context,
                                        t,
                                        readerInsets.bottom,
                                      ),
                                    ),
                                  );
                                }
                                final entry = _entries[index - 1];
                                final originalPost = entry.post;
                                final post = originalPost;
                                final focused =
                                    post.pid == _highlightPid &&
                                    entry.kind !=
                                        _ThreadEntryKind.commentsHeading &&
                                    entry.kind != _ThreadEntryKind.replies &&
                                    (!_focusOnFeedback || _isFocusEntry(entry));
                                final author =
                                    post.authorUid != null &&
                                    post.authorUid == _openingAuthor;
                                void onReply() {
                                  _openComposer(post);
                                }

                                final previousPost = index > 1
                                    ? _entries[index - 2].post
                                    : null;
                                final followsOpening =
                                    previousPost != null &&
                                    postIsOpening(previousPost);
                                final openingHasFeedback =
                                    followsOpening &&
                                    (previousPost.rating?.isEmpty == false ||
                                        previousPost.comments.isNotEmpty);
                                final card = switch (entry.kind) {
                                  _ThreadEntryKind.blocked => Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      entry.nested ? 0 : metrics.gutter,
                                      12,
                                      entry.nested ? 0 : metrics.gutter,
                                      _isSourcePost(post)
                                          ? 12
                                          : ThreadPageTokens.cardInset,
                                    ),
                                    child: _isSourcePost(post)
                                        ? _blockedSourceRow(t, metrics, post)
                                        : Text(
                                            '已屏蔽用户的发言',
                                            style: AppType.footnote.copyWith(
                                              color: t.text2,
                                            ),
                                          ),
                                  ),
                                  _ThreadEntryKind.whole => PostCard(
                                    pollCard: _pollFor(post),
                                    post: post,
                                    isOpening: postIsOpening(post),
                                    commentStyle:
                                        _grouped && !postIsOpening(post),
                                    nested: entry.nested,
                                    replyToAuthor: _replyToAuthor(post),
                                    isAuthor: author,
                                    onReply: onReply,
                                    onMore: () =>
                                        _openPostActions(originalPost),
                                    onOpenProfile: () =>
                                        _openPostProfile(originalPost),
                                    onUnlock: () => _unlockPost(post),
                                    replyContext: _referenceContext(post),
                                    onOpenReference: _openReference,
                                  ),
                                  _ThreadEntryKind.header => PostCard.header(
                                    post: post,
                                    isOpening: postIsOpening(post),
                                    commentStyle:
                                        _grouped && !postIsOpening(post),
                                    nested: entry.nested,
                                    isAuthor: author,
                                    onReply: onReply,
                                    onMore: () =>
                                        _openPostActions(originalPost),
                                    onOpenProfile: () =>
                                        _openPostProfile(originalPost),
                                    onUnlock: () => _unlockPost(post),
                                    replyContext: _referenceContext(post),
                                    onOpenReference: _openReference,
                                  ),
                                  _ThreadEntryKind.block ||
                                  _ThreadEntryKind.imageStack => PostCard.block(
                                    post: post,
                                    isOpening: postIsOpening(post),
                                    commentStyle:
                                        _grouped && !postIsOpening(post),
                                    nested: entry.nested,
                                    replyToAuthor: entry.firstContent
                                        ? _replyToAuthor(post)
                                        : null,
                                    isAuthor: author,
                                    contentBlock: entry.block,
                                    contentIndex: entry.blockIndex,
                                    imageStack: entry.imageStack,
                                    siteLinks: entry.siteLinks,
                                    linksGrouped: entry.linksGrouped,
                                    linkGroupStart: entry.linkGroupStart,
                                    linkGroupEnd: entry.linkGroupEnd,
                                    onOpenReference: _openReference,
                                    paragraphGapBefore:
                                        !entry.firstContent &&
                                        entry.imageStack == null &&
                                        entry.linkGroupStart,
                                    gallery: entry.gallery,
                                    galleryIndex: entry.imageIndex,
                                  ),
                                  _ThreadEntryKind.footer => PostCard.footer(
                                    pollCard: _pollFor(post),
                                    feedbackKey:
                                        _isFocusEntry(entry) && _focusOnFeedback
                                        ? _feedbackKey
                                        : null,
                                    post: post,
                                    isOpening: postIsOpening(post),
                                    commentStyle:
                                        _grouped && !postIsOpening(post),
                                    nested: entry.nested,
                                    isAuthor: author,
                                    onReply: onReply,
                                    onMore: () =>
                                        _openPostActions(originalPost),
                                    onUnlock: () => _unlockPost(post),
                                  ),
                                  _ThreadEntryKind.commentsHeading => Padding(
                                    key: _commentsKey,
                                    padding: EdgeInsets.fromLTRB(
                                      metrics.gutter,
                                      followsOpening
                                          ? ThreadPageTokens
                                                    .openingCommentsGap -
                                                metrics.postVPad -
                                                (openingHasFeedback
                                                    ? FeedbackMetrics.bottom
                                                    : 0)
                                          : metrics.postVPad +
                                                ThreadPageTokens
                                                    .commentHeadingGap,
                                      metrics.gutter,
                                      ThreadPageTokens.commentHeadingBottom,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_firstPage > 1)
                                          Builder(
                                            builder: (context) =>
                                                _loadBeforeControl(context, t),
                                          ),
                                        ThreadCommentHeading(
                                          loadedCount: _shownReplyCount,
                                          totalCount: _replyCount,
                                          complete:
                                              _index.sourceComplete &&
                                              !_orderedPosts.any(_blocked),
                                          mode: _shownMode,
                                          showAuthor: _openingAuthor != null,
                                          busy: _pendingMode != null,
                                          onModeChanged: _setViewMode,
                                        ),
                                      ],
                                    ),
                                  ),
                                  _ThreadEntryKind.replies => _replyExpansion(
                                    context,
                                    post,
                                    last: index == _entries.length,
                                  ),
                                };
                                final wideImageRow = entry.imageStack != null;
                                final imageCard = wideImageRow
                                    ? MediaQuery(
                                        data: MediaQuery.of(
                                          context,
                                        ).copyWith(padding: readerInsets),
                                        child: card,
                                      )
                                    : card;
                                final cardContent =
                                    entry.nested && !wideImageRow
                                    ? Container(
                                        margin: EdgeInsets.only(
                                          left:
                                              metrics.commentGutter +
                                              metrics.avatar,
                                          right: metrics.commentGutter,
                                        ),
                                        // Keep the visible gutter unchanged while
                                        // letting reply hit slop reach this inset.
                                        padding: const EdgeInsets.only(
                                          left: 10,
                                          right: 8,
                                        ),
                                        child: card,
                                      )
                                    : imageCard;
                                final content = !focused
                                    ? cardContent
                                    : AnimatedBuilder(
                                        animation: _focusHighlight,
                                        child: cardContent,
                                        builder: (context, child) {
                                          final progress =
                                              _focusHighlight.value;
                                          if (_isSourcePost(post) &&
                                              entry.kind ==
                                                  _ThreadEntryKind.blocked) {
                                            return _sourceHighlight(
                                              context,
                                              t,
                                              post.pid,
                                              progress,
                                              child!,
                                            );
                                          }
                                          final strength = 1 - progress;
                                          return PostFeedbackHighlight(
                                            strength: strength,
                                            child: ColoredBox(
                                              color: _focusOnFeedback
                                                  ? t.bg
                                                  : Color.lerp(
                                                      t.bg,
                                                      Color.alphaBlend(
                                                        t.accentFill,
                                                        t.bg,
                                                      ),
                                                      strength,
                                                    )!,
                                              child: child,
                                            ),
                                          );
                                        },
                                      );
                                final reveal =
                                    _revealingEntries.contains(entry.key)
                                    ? _replyRevealCurve
                                    : const AlwaysStoppedAnimation<double>(1);
                                final row = Column(
                                  key: _isFocusEntry(entry)
                                      ? _focusKey
                                      : ValueKey(entry.key),
                                  // 默认居中会给子项宽松约束,不足一行的段落随之居中
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (entry.nested)
                                      SizeTransition(
                                        sizeFactor: reveal,
                                        alignment: Alignment.topCenter,
                                        child: ContentFade(
                                          background: t.bg,
                                          opacity: reveal,
                                          child: content,
                                        ),
                                      )
                                    else
                                      content,
                                  ],
                                );
                                if (index <= heading) {
                                  return KeyedSubtree(
                                    key: _ThreadRowKey(entry.key),
                                    child: _landingFade(t, row),
                                  );
                                }
                                final first = index == heading + 1;
                                final last = index == _entries.length;
                                return Padding(
                                  key: _ThreadRowKey(entry.key),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: ThreadPageTokens.cardMargin,
                                  ),
                                  child: _landingFade(
                                    t,
                                    ClipRRect(
                                      borderRadius: BorderRadius.vertical(
                                        top: first
                                            ? const Radius.circular(
                                                ThreadPageTokens.cardRadius,
                                              )
                                            : Radius.zero,
                                        bottom: last
                                            ? const Radius.circular(
                                                ThreadPageTokens.cardRadius,
                                              )
                                            : Radius.zero,
                                      ),
                                      clipBehavior: Clip.hardEdge,
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          top: first
                                              ? ThreadPageTokens.cardInset
                                              : 0,
                                          bottom: last
                                              ? ThreadPageTokens.cardInset
                                              : 0,
                                        ),
                                        child: ContentFade(
                                          background: t.bg,
                                          opacity: _commentsOpacity,
                                          child: CommentRowInteraction(
                                            highlight: _heldReplies.putIfAbsent(
                                              post.pid,
                                              () => ValueNotifier(false),
                                            ),
                                            onLongPress: () =>
                                                _openPostActions(originalPost),
                                            child: row,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
              ),
              if (_portalLanding &&
                  _pages.isNotEmpty &&
                  _landingSkeletonVisible &&
                  _landingPaintPending)
                Positioned(
                  top: top + NavOverlay.barHeight,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: FadeTransition(
                      opacity: _skeletonOpacity,
                      child: RepaintBoundary(
                        child: ThreadLandingSkeleton(
                          title: widget.landingTitle ?? widget.title,
                          bars: true,
                          showTitle: false,
                        ),
                      ),
                    ),
                  ),
                ),
              // 顶栏只有返回圆钮;滚动后居中显示标题,顶部渐隐代替硬切
              if (!_portalLanding)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ImageViewerReaderChrome(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _collapsedTitle,
                      builder: (context, collapsed, _) => NavOverlay(
                        leading: ChromeButton(
                          icon: AppIcons.back,
                          tooltip: '返回',
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        // 原页面与阅读设置共用顶栏操作胶囊。
                        actions: [
                          ChromeGroup(
                            key: const ValueKey('thread-reading-settings'),
                            items: [
                              ChromeGroupItem(
                                icon: AppIcons.webPage,
                                tooltip: '查看原页面',
                                onPressed: () => showSourcePage(
                                  context,
                                  threadSourceUrl(widget.tid, page: _firstPage),
                                ),
                              ),
                              ChromeGroupItem(
                                icon: CupertinoIcons.textformat_size,
                                tooltip: '阅读设置',
                                onPressed: () =>
                                    showReadingSettingsSheet(context),
                              ),
                            ],
                          ),
                        ],
                        inlineTitle: normalizeDisplayText(
                          _loadedDetail?.title ?? widget.title,
                        ),
                        scrollOffset: _navOffset,
                        collapseAt: _titleAt,
                        titleVisible: _collapsedTitle,
                        readingProgress: _readingProgress,
                        readingProgressVisible: _chrome.progressVisible,
                        background: t.bg,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: _pages.isEmpty
          ? null
          : ImageViewerReaderChrome(
              child: ValueListenableBuilder<double>(
                valueListenable: _barProgress,
                child: _toolbar(),
                builder: (context, progress, child) {
                  final reduced = MediaQuery.disableAnimationsOf(context);
                  return IgnorePointer(
                    ignoring: progress >= 1,
                    child: ExcludeSemantics(
                      excluding: progress >= 1,
                      child: FractionalTranslation(
                        key: const ValueKey('thread-reading-bar-position'),
                        translation: Offset(0, reduced ? 0 : progress),
                        child: Opacity(opacity: 1 - progress, child: child),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
    return ReadingBarAnchor(
      hiddenProgress: _barProgress,
      bottomPadding: MediaQuery.paddingOf(context).bottom,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
      child: page,
    );
  }

  Widget _blockedSourceRow(AppTokens t, ReadingMetrics metrics, Post post) =>
      Row(
        children: [
          AvatarImage(
            url: post.avatarUrl,
            name: post.author,
            size: metrics.avatar,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '已屏蔽 · ${post.author}',
              style: AppType.footnote.copyWith(
                color: t.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (post.floorIsKnown)
            Text(
              '#${post.floor}',
              semanticsLabel: '第 ${post.floor} 楼',
              style: AppType.footnote.copyWith(color: t.text2),
            ),
        ],
      );

  Widget _sourceHighlight(
    BuildContext context,
    AppTokens t,
    int pid,
    double progress,
    Widget child,
  ) {
    final curve = MediaQuery.disableAnimationsOf(context)
        ? Curves.easeOut
        : const Interval(.35, 1, curve: Curves.easeOut);
    final strength = 1 - curve.transform(progress);
    return DecoratedBox(
      key: ValueKey('blocked-source-highlight-$pid'),
      decoration: BoxDecoration(
        color: t.accentFill.withValues(alpha: t.accentFill.a * strength),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: child,
    );
  }

  Widget _initialArrival(Widget? child) => _portalLanding
      ? child!
      : ChhersLoadingTransition(
          child: child,
          onContentReady: () {
            if (!_scroll.hasClients) return;
            _locateFocusedPost();
            _handleScroll();
          },
        );

  Widget _landingFade(AppTokens tokens, Widget child) => !_portalLanding
      ? child
      : ContentFade(
          background: tokens.bg,
          opacity: _landingOpacity,
          child: RepaintBoundary(child: child),
        );

  Widget _initialState() {
    if (_loading) {
      return SingleChildScrollView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + NavOverlay.barHeight,
        ),
        child: ThreadLandingSkeleton(
          title: widget.landingTitle ?? widget.title,
          bars: _landingSkeletonVisible,
        ),
      );
    }
    final error = _error;
    if (error is PageMessage) {
      return StateView.forMessage(
        error,
        onLogin: () => Navigator.of(context).pushNamed('/login'),
        onPassword: error.fid == null ? null : () => _unlockForum(error.fid!),
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
  String get _eyebrow => [
    if (_loadedDetail?.forumName case final name?) formatForumName(name),
    if (_authorUid != null) '只看楼主',
  ].where((label) => label.isNotEmpty).join('，');

  Widget _heading(AppTokens t) {
    final metrics = ReadingMetrics.of(context);
    final eyebrow = _eyebrow;
    final stats = [
      if (_loadedDetail?.viewCount case final count? when count > 0)
        '$count 查看',
      if (_replyCount case final count? when count > 0) '$count 回复',
    ].join('　');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.gutter,
        ThreadPageTokens.headingTop,
        metrics.gutter,
        ThreadPageTokens.headingBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow.isNotEmpty) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: threadEyebrowStyle(t),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  AppIcons.forward,
                  size: ThreadMetrics.metaSize,
                  color: t.accent,
                ),
              ],
            ),
            const SizedBox(height: ThreadPageTokens.eyebrowGap),
          ] else if (_portalLanding) ...[
            ThreadHeadingSpace(style: threadEyebrowStyle(t)),
            const SizedBox(height: ThreadPageTokens.eyebrowGap),
          ],
          BalancedTitle(
            _loadedDetail?.title ?? widget.title,
            key: _titleKey,
            style: threadTitleStyle(t),
          ),
          if (stats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: ThreadPageTokens.statsGap),
              child: Text(
                stats,
                style: AppType.footnote.copyWith(color: t.text3),
              ),
            )
          else if (_portalLanding) ...[
            const SizedBox(height: ThreadPageTokens.statsGap),
            const ThreadHeadingSpace(style: AppType.footnote),
          ],
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
                    onPressed: _loading ? null : _refreshEntireThread,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _loadBeforeControl(BuildContext context, AppTokens t) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Only the control needs to rebuild when another route interrupts loading.
    final loading = (ModalRoute.isCurrentOf(context) ?? true) && _loadingBefore;
    return Padding(
      padding: const EdgeInsets.only(bottom: ThreadPageTokens.loadBeforeGap),
      child: SizedBox(
        height: AppSizes.buttonHeight,
        child: Semantics(
          container: loading,
          label: loading ? '正在加载' : null,
          liveRegion: loading,
          excludeSemantics: loading,
          child: AnimatedSwitcher(
            duration: reduced ? AppMotion.reducedFade : AppMotion.loadingIn,
            reverseDuration: reduced
                ? AppMotion.reducedFade
                : AppMotion.loadingOut,
            switchInCurve: AppMotion.contentFadeCurve,
            layoutBuilder: (current, previous) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (final child in [...previous, ?current])
                    IgnorePointer(
                      key: child.key,
                      ignoring: child != current,
                      child: ExcludeSemantics(
                        excluding: child != current,
                        child: child,
                      ),
                    ),
                ],
              );
            },
            child: loading
                ? const ChhersLoader(
                    size: ChhersLoaderSize.list,
                    delayed: false,
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(AppRadii.full),
                    ),
                    child: AppButton(
                      label: _beforeError == null ? '查看前面的回复' : '加载失败，重试',
                      variant: AppButtonVariant.plain,
                      icon: AppIcons.up,
                      onPressed: _loading || _pendingMode != null
                          ? null
                          : _loadBefore,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  double _endMarkerGap(BuildContext context) {
    final metrics = ReadingMetrics.of(context);
    var index = _entries.length - 1;
    if (index < 0) return ListEndTokens.markerGap;
    var entry = _entries[index];
    if (index > 0 &&
        entry.kind == _ThreadEntryKind.replies &&
        !_hasReplyExpansion(_remainingReplies(entry.post))) {
      entry = _entries[--index];
    }
    if (entry.kind == _ThreadEntryKind.commentsHeading) {
      return ListEndTokens.markerPadding(ThreadPageTokens.commentHeadingBottom);
    }
    final rowPadding = switch (entry.kind) {
      _ThreadEntryKind.replies =>
        metrics.postVPad + _expansionTextInset(context, entry.post),
      _ThreadEntryKind.whole || _ThreadEntryKind.footer =>
        metrics.commentVPad + CommentMetaRow.textBottomInsetOf(context),
      _ThreadEntryKind.blocked => ThreadPageTokens.cardInset,
      _ => 0.0,
    };
    return ListEndTokens.markerPadding(ThreadPageTokens.cardInset + rowPadding);
  }

  double _expansionTextInset(BuildContext context, Post post) =>
      centeredLabelBottomInset(
        context,
        _replyExpansionLabel(post, _remainingReplies(post)),
        ThreadPageTokens.expansionLabel,
        ThreadPageTokens.expansionHeight,
      );

  Widget _tail(BuildContext context, AppTokens t, double barHeight) => Padding(
    padding: EdgeInsets.fromLTRB(
      ListEndTokens.markerGap,
      _endMarkerGap(context),
      ListEndTokens.markerGap,
      barHeight,
    ),
    child: Center(
      child: !_loading && _tailError != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _failedUpdatePage == null ? '后面的讨论暂时没有加载出来' : '暂时无法检查新回复',
                  style: TextStyle(
                    fontSize: AppType.sizeFootnote,
                    color: t.text2,
                  ),
                ),
                AppButton(
                  label: '重试',
                  variant: AppButtonVariant.plain,
                  onPressed: _failedUpdatePage == null
                      ? () => _append(retry: true)
                      : _checkTailForUpdates,
                ),
              ],
            )
          : ReadingListEnd(loading: _loading, exhausted: !_hasNext),
    ),
  );

  Future<void> _refreshFavoriteCount() async {
    final generation = _generation;
    try {
      final fresh = await _readAs(null, 1, refresh: true);
      if (!mounted ||
          generation != _generation ||
          fresh.tid != widget.tid ||
          fresh.favoriteCount == null) {
        return;
      }
      final detail = _loadedDetail;
      if (detail == null) return;
      _update(
        () => _loadedDetail = ThreadDetail(
          tid: detail.tid,
          cookiePrefix: detail.cookiePrefix,
          fid: detail.fid,
          forumName: detail.forumName,
          title: detail.title,
          posts: detail.posts,
          viewCount: detail.viewCount,
          replyCount: detail.replyCount,
          favoriteCount: fresh.favoriteCount,
          poll: detail.poll,
          page: detail.page,
        ),
      );
    } catch (_) {
      // A count refresh must not turn a confirmed favorite into a failed action.
    }
  }

  /// 底部阅读工具栏:"写回复…"输入胶囊 + 评论数 / 回到顶部圆钮
  Widget _toolbar() => ValueListenableBuilder<bool>(
    valueListenable: _inComments,
    builder: (context, inComments, _) => FavoriteActionBuilder(
      target: FavoriteTarget(
        type: FavoriteType.thread,
        targetId: widget.tid,
        title: _loadedDetail?.title ?? widget.title,
      ),
      onChanged: _refreshFavoriteCount,
      builder: (context, favorited, busy, toggle) => ReadingBar(
        placeholder: '写回复…',
        threadStyle: true,
        onCompose: () => _openComposer(null),
        count: _replyCount,
        inComments: inComments,
        onShowComments: _showComments,
        onBackToTop: _backToTop,
        favorited: favorited,
        favoriteCount: _loadedDetail?.favoriteCount,
        favoriteBusy: busy,
        onToggleFavorite: toggle,
      ),
    ),
  );
}

String _postLocationUrl(int tid, int pid) => ChhUrls.forumIndex()
    .replace(
      queryParameters: {
        'mod': 'redirect',
        'goto': 'findpost',
        'ptid': '$tid',
        'pid': '$pid',
      },
    )
    .toString();

enum _ThreadEntryKind {
  whole,
  header,
  block,
  imageStack,
  footer,
  blocked,
  commentsHeading,
  replies,
}

class _ThreadReadEntry {
  final Post post;
  final _ThreadEntryKind kind;
  final ContentBlock? block;
  final ImageStackGroup? imageStack;
  final List<SiteLinkBlock>? siteLinks;
  final bool linksGrouped;
  final bool linkGroupStart;
  final bool linkGroupEnd;
  final int blockIndex;
  final List<String> gallery;
  final int imageIndex;
  final bool nested;
  final bool firstContent;
  const _ThreadReadEntry(
    this.post,
    this.kind, {
    this.block,
    this.imageStack,
    this.siteLinks,
    this.linksGrouped = false,
    this.linkGroupStart = true,
    this.linkGroupEnd = true,
    this.blockIndex = -1,
    this.gallery = const [],
    this.imageIndex = 0,
    this.nested = false,
    this.firstContent = false,
  });
  bool get isStart =>
      kind == _ThreadEntryKind.whole ||
      kind == _ThreadEntryKind.header ||
      kind == _ThreadEntryKind.blocked;

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

  /// 作者视图页码与普通页不同，只按 PID 更新快照中已解锁的楼层。
  _ReadSnapshot withPost(Post post) {
    ThreadDetail replace(ThreadDetail detail) {
      if (!detail.posts.any((p) => p.pid == post.pid)) return detail;
      return ThreadDetail(
        tid: detail.tid,
        cookiePrefix: detail.cookiePrefix,
        fid: detail.fid,
        forumName: detail.forumName,
        title: detail.title,
        viewCount: detail.viewCount,
        replyCount: detail.replyCount,
        favoriteCount: detail.favoriteCount,
        poll: detail.poll,
        posts: [for (final p in detail.posts) p.pid == post.pid ? post : p],
        page: detail.page,
      );
    }

    return _ReadSnapshot(
      pages.map((page, detail) => MapEntry(page, replace(detail))),
      hasNext,
      loadedDetail == null ? null : replace(loadedDetail!),
    );
  }
}

// Keep the list child's identity distinct from the inner focus/inspection key.
class _ThreadRowKey extends ValueKey<String> {
  const _ThreadRowKey(super.value);
}
