/// Editorial reading: shared cover, original image order, and real pagination.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'source_page_drawer.dart';
import '../ui/balanced_title.dart';
import '../design/display_text.dart';
import '../core/display_time.dart';
import '../ui/app_button.dart';
import '../ui/feedback.dart';
import '../ui/press.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import '../di.dart';
import '../controllers/article_reader_controller.dart';
import 'article_discussion_page.dart';
import '../data/editorial_cover_cache.dart';
import '../data/history_index.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../design/system_ui.dart';
import '../design/reading.dart';
import '../design/list_end_tokens.dart';
import '../ui/reading_settings_sheet.dart';
import '../design/typography.dart';
import '../ui/reading_bar.dart';
import '../ui/image_viewer_chrome.dart';
import '../ui/favorite_action.dart';
import '../data/favorite_index.dart';
import '../ui/nav_bar.dart';
import '../ui/chrome_button.dart';
import '../models/models.dart';
import '../models/quote_presentation.dart';
import '../widgets/editorial_article_route.dart';
import '../widgets/editorial_cover.dart';
import '../widgets/image_grid.dart';
import '../widgets/article_image.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/rich_content_text.dart';
import '../widgets/state_view.dart';
import 'thread_detail_page.dart';
import '../widgets/thread_landing.dart';
import '../widgets/content_link_block.dart';
import '../widgets/reading_list_end.dart';
import '../ui/quote.dart';
import '../models/image_stack_group.dart';
import '../widgets/site_link_card.dart';

class ArticlePage extends StatefulWidget {
  final int aid;
  final String title;
  final PortalArticle? preview;
  final String? heroTag;
  final String? eyebrow;
  final BoxFit coverFit;
  final ArticlePageLoader? loadPage;
  const ArticlePage({
    super.key,
    required this.aid,
    required this.title,
    this.preview,
    this.heroTag,
    this.eyebrow,
    this.coverFit = BoxFit.cover,
    this.loadPage,
  });
  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  late final ArticleReaderController _reader;
  bool _coverRemembered = false;
  Animation<double>? _coverAnimation;
  AnimationStatusListener? _coverListener;
  final _scroll = ScrollController();
  final _blocks = <ContentBlock>[];
  final _allImages = <String>[];
  final _imageIndex = <int, int>{};
  int _indexedPages = 0;
  final _landingChrome = ThreadLandingChrome();
  late final _coverChrome = ValueNotifier<bool>(_hasCover);
  late final _paperChrome = ValueNotifier<bool>(!_hasCover);
  Timer? _landingSkeletonDelay;
  bool _landingSkeletonVisible = false;
  bool _handedOff = false;
  bool _handoffScheduled = false;
  ModalRoute<dynamic>? _readerRoute;
  NavigatorState? _handoffNavigator;
  bool _overCover = true;
  bool _scrollCheckScheduled = false;
  double get _coverHeight =>
      (MediaQuery.sizeOf(context).width * 1.22).clamp(420.0, 560.0);
  bool get _hasCover => widget.preview?.coverUrl != null;

  Color _readerBackground(AppTokens tokens) =>
      _paperChrome.value ? tokens.bg : tokens.grouped;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateScroll);
    _reader = ArticleReaderController(
      loadPage:
          widget.loadPage ??
          (page, refresh) =>
              portalRepo.openArticle(widget.aid, page: page, refresh: refresh),
    );
    _reader.addListener(_readerChanged);
    _reader.loadNext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigator = Navigator.of(context);
    if (navigator != _handoffNavigator) {
      _handoffNavigator?.userGestureInProgressNotifier.removeListener(
        _retryThreadHandoff,
      );
      _handoffNavigator = navigator;
      navigator.userGestureInProgressNotifier.addListener(_retryThreadHandoff);
    }
  }

  // Observe route current changes away from the reading subtree and its Hero.
  late final _watchReaderRoute = Builder(
    builder: (context) {
      final route = ModalRoute.of(context);
      if (route != _readerRoute) {
        _readerRoute?.animation?.removeStatusListener(_handoffStatusChanged);
        _readerRoute = route;
        route?.animation?.addStatusListener(_handoffStatusChanged);
      }
      _retryThreadHandoff();
      return const SizedBox.shrink();
    },
  );

  void _handoffStatusChanged(AnimationStatus status) => _retryThreadHandoff();

  void _retryThreadHandoff() {
    if (!mounted) return;
    if (_reader.thread != null) _handOffToThread();
  }

  void _waitForLandingSkeleton() {
    _landingSkeletonDelay = Timer(AppMotion.skeletonDelay, () {
      if (mounted) setState(() => _landingSkeletonVisible = true);
    });
  }

  @override
  void dispose() {
    _readerRoute?.animation?.removeStatusListener(_handoffStatusChanged);
    _handoffNavigator?.userGestureInProgressNotifier.removeListener(
      _retryThreadHandoff,
    );
    _landingSkeletonDelay?.cancel();
    _coverChrome.dispose();
    _paperChrome.dispose();
    _landingChrome.dispose();
    _scroll.dispose();
    _reader.removeListener(_readerChanged);
    _reader.dispose();
    if (_coverListener != null) {
      _coverAnimation?.removeStatusListener(_coverListener!);
    }
    super.dispose();
  }

  void _readerChanged() {
    if (!mounted) return;
    final pages = _reader.pages;
    _paperChrome.value =
        _reader.thread != null || (!_hasCover && pages.isEmpty);
    if (_indexedPages == 0 && pages.isNotEmpty) {
      final article = pages.first;
      historyIndex.record(
        type: HistoryType.article,
        id: article.aid,
        title: article.title,
        column: article.categoryName ?? widget.preview?.categoryName,
        author: article.author ?? '',
      );
    }
    // Loading/error notifications do not change already-indexed content.
    for (var page = _indexedPages; page < pages.length; page++) {
      for (final block in pages[page].content) {
        if (block case ImageBlock(:final url)) {
          _imageIndex[_blocks.length] = _allImages.length;
          _allImages.add(url);
        }
        _blocks.add(block);
      }
    }
    _indexedPages = pages.length;
    if (!_hasCover && !_handedOff) {
      if (_reader.thread != null || pages.isNotEmpty || _reader.error != null) {
        _landingSkeletonDelay?.cancel();
      } else if (_reader.isLoading &&
          !(_landingSkeletonDelay?.isActive ?? false) &&
          !_landingSkeletonVisible) {
        _waitForLandingSkeleton();
      }
    }
    if (_reader.thread != null) _handOffToThread();
    if (!_coverRemembered && _reader.pages.isNotEmpty) {
      _rememberCover(_reader.pages.first);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadNearEnd();
    });
  }

  void _rememberCover(ArticleDetail article) {
    final firstImage = article.content.whereType<ImageBlock>().firstOrNull;
    if (firstImage == null) return;
    _coverRemembered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = _readerRoute?.animation;
      if (animation == null || animation.isCompleted) {
        editorialCoverCache.remember(widget.aid, firstImage.url);
      } else {
        if (_coverListener != null) {
          _coverAnimation?.removeStatusListener(_coverListener!);
        }
        _coverAnimation = animation;
        _coverListener = (status) {
          if (status != AnimationStatus.completed) return;
          animation.removeStatusListener(_coverListener!);
          _coverListener = null;
          if (mounted) editorialCoverCache.remember(widget.aid, firstImage.url);
        };
        animation.addStatusListener(_coverListener!);
      }
    });
  }

  void _loadNearEnd() {
    if (!_scroll.hasClients || _blocks.isEmpty) return;
    final viewport = _scroll.position.viewportDimension;
    if (_scroll.position.extentAfter <= (viewport * .8).clamp(240.0, 800.0)) {
      _reader.loadNext();
    }
  }

  void _updateScroll() {
    if (_scrollCheckScheduled) return;
    _scrollCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCheckScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final over = _hasCover && _scroll.offset < _coverHeight - 80;
      if (over != _overCover) setState(() => _overCover = over);
      if (!_handedOff) {
        _coverChrome.value = over;
        _landingChrome.offset.value = over ? 0 : _scroll.offset;
      }
      _loadNearEnd();
    });
  }

  void _openDiscussion() =>
      ArticleDiscussionPage.show(context, aid: widget.aid, title: widget.title);

  void _handOffToThread() {
    if (_handedOff || _handoffScheduled) return;
    _handoffScheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handoffScheduled = false;
      if (!mounted || _handedOff) return;
      final route = _readerRoute;
      final navigator = Navigator.of(context);
      // Keep an existing Hero mounted until its shuttle has left the Overlay.
      if (route == null ||
          !route.isActive ||
          !route.isCurrent ||
          route.offstage ||
          route.animation?.status == AnimationStatus.reverse ||
          (_hasCover &&
              widget.heroTag != null &&
              route.animation != null &&
              !route.animation!.isCompleted) ||
          navigator.userGestureInProgress) {
        return;
      }
      _coverChrome.value = false;
      _landingChrome.offset.value = 0;
      setState(() => _handedOff = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final first = _reader.pages.firstOrNull;
    final error = _reader.error;
    final thread = _handedOff ? _reader.thread : null;
    final onCover = _overCover && _hasCover && thread == null;
    final overlayStyle = onCover
        ? AppSystemUi.lightIcons
        : AppSystemUi.forBrightness(Theme.of(context).brightness);
    return ImageViewerChromeScope(
      overlayStyle: overlayStyle,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          key: const ValueKey('article-reader-surface'),
          backgroundColor: _readerBackground(t),
          resizeToAvoidBottomInset: thread == null ? null : false,
          body: Stack(
            children: [
              _watchReaderRoute,
              if (thread != null)
                ThreadDetailPage(
                  tid: thread.tid,
                  title: thread.title,
                  initialPage: thread.detail?.page.current ?? 1,
                  initialDetail: thread.detail,
                  initialDetailCacheGeneration: thread.cacheGeneration,
                  initialDetailThreadRevision: thread.threadCacheRevision,
                  landingChrome: _landingChrome,
                  landingTitle: _hasCover ? thread.title : widget.title,
                  landingSkeletonVisible: _landingSkeletonVisible,
                )
              else
                _articleBody(first, error, t),
              _readerNav,
              if (thread == null && _hasCover)
                Positioned(
                  top: MediaQuery.paddingOf(context).top,
                  left: 100,
                  right: 100,
                  child: Builder(
                    builder: (context) {
                      final route = _readerRoute;
                      return route is EditorialArticleRoute
                          ? ImageViewerReaderChrome(
                              child: _dismissHandle(t, route),
                            )
                          : const SizedBox.shrink();
                    },
                  ),
                ),
              if (thread == null && first != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ImageViewerReaderChrome(child: _readingToolbar(t)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _articleBody(ArticleDetail? first, Object? error, AppTokens t) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadNearEnd();
          });
          return false;
        },
        child: CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            if (_hasCover)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _coverHeight,
                  child: HeroMode(
                    enabled: widget.heroTag != null,
                    child: EditorialCover(
                      article: widget.preview!,
                      heroTag: widget.heroTag ?? 'article-cover-${widget.aid}',
                      expanded: true,
                      fit: widget.coverFit,
                      eyebrow: widget.eyebrow,
                    ),
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      MediaQuery.paddingOf(context).top + NavOverlay.barHeight,
                ),
              ),
            if (first != null)
              ExpressivePageReveal(
                active: true,
                sliver: true,
                animateOnMount: _readerRoute?.animation?.isCompleted ?? true,
                child: SliverMainAxisGroup(
                  slivers: [
                    _articleHeader(first, t),
                    ..._contentSlivers(),
                    SliverPadding(
                      padding: EdgeInsets.only(
                        bottom: ReadingBar.heightFor(
                          bottomPadding: MediaQuery.paddingOf(context).bottom,
                        ),
                      ),
                      sliver: SliverToBoxAdapter(child: _continuationFooter(t)),
                    ),
                  ],
                ),
              )
            else if (error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: error is PageMessage
                    ? StateView.forMessage(
                        error,
                        onLogin: () =>
                            Navigator.of(context).pushNamed('/login'),
                      )
                    : StateView.error(error, onRetry: _reader.retry),
              )
            else
              SliverToBoxAdapter(
                child: _hasCover
                    ? LoadingPlaceholder(child: _readingPlaceholder())
                    : ThreadLandingSkeleton(
                        title: widget.title,
                        bars: _landingSkeletonVisible,
                      ),
              ),
          ],
        ),
      );

  late final _readerNav = Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: ImageViewerReaderChrome(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _paperChrome,
          _coverChrome,
          _landingChrome.collapsed,
        ]),
        builder: (context, _) {
          final modal = ModalRoute.of(context) is EditorialArticleRoute;
          final onCover = _coverChrome.value;
          return NavOverlay(
            key: const ValueKey('article-reader-nav'),
            leading: ChromeButton(
              icon: modal ? AppIcons.dismiss : AppIcons.back,
              tooltip: modal ? '关闭文章' : '返回',
              onImage: onCover,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              ChromeGroup(
                key: const ValueKey('thread-reading-settings'),
                onImage: onCover,
                items: [
                  ChromeGroupItem(
                    icon: AppIcons.webPage,
                    tooltip: '查看原页面',
                    onPressed: () => _openReaderSource(context),
                  ),
                  ChromeGroupItem(
                    icon: CupertinoIcons.textformat_size,
                    tooltip: '阅读设置',
                    onPressed: () => showReadingSettingsSheet(context),
                  ),
                ],
              ),
            ],
            inlineTitle: normalizeDisplayText(
              _landingChrome.title ?? _reader.thread?.title ?? widget.title,
            ),
            scrollOffset: _landingChrome.offset,
            collapseAt: double.infinity,
            titleVisible: _landingChrome.collapsed,
            readingProgress: _landingChrome.progress,
            readingProgressVisible: _landingChrome.progressVisible,
            background: _readerBackground(AppTokens.of(context)),
          );
        },
      ),
    ),
  );

  void _openReaderSource(BuildContext context) {
    final thread = _handedOff ? _reader.thread : null;
    final uri =
        _landingChrome.sourceUrl ??
        (thread == null
            ? articleSourceUrl(widget.aid)
            : threadSourceUrl(
                thread.tid,
                page: thread.detail?.page.current ?? 1,
              ));
    showSourcePage(context, uri);
  }

  Widget _dismissHandle(AppTokens t, EditorialArticleRoute route) =>
      GestureDetector(
        key: const ValueKey('article-dismiss-handle'),
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => route.beginDismiss(),
        onVerticalDragUpdate: (d) => route.updateDismiss(
          d.primaryDelta! / MediaQuery.sizeOf(context).height,
        ),
        onVerticalDragEnd: (d) => route.endDismiss(
          d.primaryVelocity! / MediaQuery.sizeOf(context).height,
        ),
        onVerticalDragCancel: () => route.endDismiss(0),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: _overCover
                    ? ImageColors.foreground.withValues(alpha: .6)
                    : t.separator,
                borderRadius: BorderRadius.circular(AppRadii.bar),
              ),
            ),
          ),
        ),
      );

  Widget _readingPlaceholder() {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final width in [1.0, .9, .7, 1.0, .85])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: width,
                child: Container(
                  height: 13,
                  decoration: BoxDecoration(
                    color: t.fill,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _articleHeader(ArticleDetail article, AppTokens t) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(26, 28, 26, _blocks.isEmpty ? 0 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 眉题:文章所在栏目;从首页卡片进来时卡片已带出分类
            if ((article.categoryName ?? widget.preview?.categoryName)
                case final category?) ...[
              Text(
                normalizeDisplayText(category),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.accent,
                  fontSize: AppType.sizeFootnote,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!_hasCover || article.metaRaw != null || _blocks.isNotEmpty)
                const SizedBox(height: 10),
            ],
            if (!_hasCover) ...[
              BalancedTitle(
                article.title,
                style: TextStyle(
                  fontSize: AppType.sizeTitle2,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  color: t.text,
                ),
              ),
              if (article.metaRaw != null || _blocks.isNotEmpty)
                const SizedBox(height: 12),
            ],
            if (article.metaRaw != null)
              Text(
                formatDisplayTime(raw: article.metaRaw, embedded: true),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.sizeFootnote,
                  height: 1.7,
                  color: t.text2,
                ),
              ),
            if (_blocks.isNotEmpty) const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  List<Widget> _contentSlivers() {
    final t = AppTokens.of(context);
    final segments = groupPostImages(_blocks, groupImages: false);
    return [
      SliverList.builder(
        addRepaintBoundaries: false,
        itemCount: segments.length,
        itemBuilder: (context, index) {
          final segment = segments[index];
          final isReadingEnd = index == segments.length - 1;
          final i = segment.blockIndex;
          final rawBlock = segment.block!;
          final block = rawBlock is QuoteBlock
              ? quoteForDisplay(rawBlock)
              : rawBlock;
          final metrics = ReadingMetrics.of(context);
          final bodyStyle = TextStyle(
            fontSize: metrics.bodySize,
            height: metrics.bodyHeight,
            letterSpacing: 0,
            color: t.text,
          );
          return RepaintBoundary(
            key: ValueKey('article-block-$i'),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: metrics.textScaler(
                  MediaQuery.textScalerOf(context),
                ),
              ),
              child: switch (block) {
                ImageBlock(:final url) => Padding(
                  padding: EdgeInsets.only(
                    top: ReadingMetrics.articleBlockVerticalSpacing,
                    bottom: isReadingEnd
                        ? 0
                        : ReadingMetrics.articleBlockVerticalSpacing,
                  ),
                  child: Semantics(
                    button: true,
                    label: '查看第 ${_imageIndex[i]! + 1} 张原图',
                    child: PressScale(
                      scale: AppPressScale.content,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ImageViewerPage(
                            urls: List.unmodifiable(_allImages),
                            initialIndex: _imageIndex[i]!,
                          ),
                        ),
                      ),
                      child: ArticleImage(url: url),
                    ),
                  ),
                ),
                TextBlock() => Padding(
                  padding: EdgeInsets.fromLTRB(
                    ReadingMetrics.articleBodyInset,
                    index > 0 && segments[index - 1].block is TextBlock
                        ? 0
                        : ReadingMetrics.articleTextTop,
                    ReadingMetrics.articleBodyInset,
                    index + 1 < segments.length &&
                            segments[index + 1].block is TextBlock
                        ? ReadingMetrics.paragraphGap
                        : isReadingEnd
                        ? 0
                        : ReadingMetrics.articleTextBottom,
                  ),
                  child: RichContentText(block: block, style: bodyStyle),
                ),
                QuoteBlock(:final source, :final children) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    26,
                    8,
                    26,
                    isReadingEnd
                        ? 0
                        : ReadingMetrics.articleBlockVerticalSpacing,
                  ),
                  child: QuoteView(
                    author: source ?? '',
                    text: children
                        .whereType<TextBlock>()
                        .map((b) => b.text)
                        .join('\n'),
                    bodyStyle: bodyStyle.copyWith(
                      fontSize: metrics.bodySize - 2,
                      color: t.text2,
                    ),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final child in children.whereType<TextBlock>())
                          RichContentText(
                            block: child,
                            style: bodyStyle.copyWith(
                              fontSize: metrics.bodySize - 2,
                              color: t.text2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SiteLinkBlock() || BilibiliBlock() => Padding(
                  padding: EdgeInsets.fromLTRB(
                    26,
                    segment.linkGroupStart ? 4 : 0,
                    26,
                    segment.linkGroupEnd && !isReadingEnd
                        ? ReadingMetrics.articleBlockVerticalSpacing
                        : 0,
                  ),
                  child: segment.siteLinks != null
                      ? SiteLinkGroupCard(
                          blocks: segment.siteLinks!,
                          grouped: segment.linksGrouped,
                          first: segment.linkGroupStart,
                          last: segment.linkGroupEnd,
                        )
                      : ContentLinkBlockView(block: block),
                ),
              },
            ),
          );
        },
      ),
    ];
  }

  Widget _continuationFooter(AppTokens t) {
    if (_reader.error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(26, ListEndTokens.markerGap, 26, 0),
        child: Column(
          children: [
            Text(
              '后续内容暂时无法加载',
              style: TextStyle(fontSize: AppType.sizeFootnote, color: t.text2),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: '重试',
              variant: AppButtonVariant.plain,
              onPressed: _reader.retry,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        top: _reader.hasNext ? 0 : ListEndTokens.markerGap,
      ),
      child: Center(
        child: ReadingListEnd(
          loading: _reader.isLoading,
          exhausted: !_reader.hasNext,
          topPadding: _reader.hasNext ? ListEndTokens.markerGap : 0,
        ),
      ),
    );
  }

  /// 底部阅读工具栏:与帖子页同一套;门户文章的评论在弹层里,圆钮直接打开它
  Widget _readingToolbar(AppTokens t) => FavoriteActionBuilder(
    target: FavoriteTarget(
      type: FavoriteType.article,
      targetId: widget.aid,
      title: widget.title,
    ),
    builder: (context, favorited, busy, toggle) => ReadingBar(
      placeholder: '写评论…',
      onCompose: _openDiscussion,
      inComments: false,
      onShowComments: _openDiscussion,
      onBackToTop: () {},
      favorited: favorited,
      favoriteBusy: busy,
      onToggleFavorite: toggle,
    ),
  );
}
