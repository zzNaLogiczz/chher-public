/// Editorial reading: shared cover, original image order, and real pagination.
library;

import 'package:flutter/material.dart';
import 'source_page_drawer.dart';
import '../ui/app_button.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import '../di.dart';
import '../controllers/article_reader_controller.dart';
import 'article_discussion_page.dart';
import '../data/editorial_cover_cache.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/reading_bar.dart';
import '../ui/favorite_action.dart';
import '../data/favorite_index.dart';
import '../ui/nav_bar.dart';
import '../ui/chrome_button.dart';
import '../models/models.dart';
import '../widgets/editorial_article_route.dart';
import '../widgets/editorial_cover.dart';
import '../widgets/image_grid.dart';
import '../widgets/article_image.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/rich_content_text.dart';
import '../widgets/state_view.dart';
import 'thread_detail_page.dart';
import '../widgets/content_link_block.dart';

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
  bool _handedOff = false;
  bool _largeText = false;
  bool _overCover = true;
  bool _scrollCheckScheduled = false;
  double get _coverHeight =>
      (MediaQuery.sizeOf(context).width * 1.22).clamp(420.0, 560.0);
  bool get _hasCover => widget.preview?.coverUrl != null;

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
  void dispose() {
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
    if (_reader.thread case final thread?) _handOffToThread(thread);
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
      final animation = ModalRoute.of(context)?.animation;
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
      _loadNearEnd();
    });
  }

  void _openDiscussion() =>
      ArticleDiscussionPage.show(context, aid: widget.aid, title: widget.title);

  void _handOffToThread(ThreadContent c) {
    if (_handedOff) return;
    _handedOff = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ThreadDetailPage(tid: c.tid, title: c.title),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final first = _reader.pages.firstOrNull;
    final error = _reader.error;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overCover && _hasCover
          ? SystemUiOverlayStyle.light
          : (t.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark),
      child: Scaffold(
        backgroundColor: t.bg,
        body: Stack(
          children: [
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
                        child: EditorialCover(
                          article: widget.preview!,
                          heroTag:
                              widget.heroTag ?? 'article-cover-${widget.aid}',
                          expanded: true,
                          fit: widget.coverFit,
                          eyebrow: widget.eyebrow,
                        ),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.paddingOf(context).top + 62,
                      ),
                    ),
                  if (first != null) ...[
                    _articleHeader(first, t),
                    ..._contentSlivers(),
                    SliverToBoxAdapter(child: _continuationFooter(t)),
                  ] else if (error != null)
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
                    SliverToBoxAdapter(child: _readingPlaceholder()),
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              ),
            ),
            // 滚过封面后顶部渐隐,不再是一条实色带硬切正文
            if (!_overCover || !_hasCover)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, .7, 1],
                        colors: [t.bg, t.bg, t.bg.withValues(alpha: 0)],
                      ),
                    ),
                    child: SizedBox(
                      height:
                          MediaQuery.paddingOf(context).top +
                          NavOverlay.barHeight +
                          NavOverlay.fadeBand,
                    ),
                  ),
                ),
              ),
            // 关闭在左、字号在右;压在封面上用深色玻璃,滚过封面换回白色玻璃
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              left: 10,
              child: _closeButton(t),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              right: 10,
              // 原页面与字号同在右侧,合进一个胶囊,不并排两颗圆钮
              child: ChromeGroup(
                onImage: _overCover && _hasCover,
                items: [
                  ChromeGroupItem(
                    icon: AppIcons.webPage,
                    tooltip: '查看原页面',
                    onPressed: () =>
                        showSourcePage(context, articleSourceUrl(widget.aid)),
                  ),
                  ChromeGroupItem(
                    icon: CupertinoIcons.textformat_size,
                    tooltip: _largeText ? '标准字号' : '放大字号',
                    selected: _largeText,
                    onPressed: () => setState(() => _largeText = !_largeText),
                  ),
                ],
              ),
            ),
            if (_hasCover)
              Positioned(
                top: MediaQuery.paddingOf(context).top,
                left: 100,
                right: 100,
                child: _dismissHandle(t),
              ),
            if (first != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _readingToolbar(t),
              ),
          ],
        ),
      ),
    );
  }

  Widget _closeButton(AppTokens t) => ChromeButton(
    icon: AppIcons.dismiss,
    tooltip: '关闭文章',
    onImage: _overCover && _hasCover,
    onPressed: () => Navigator.of(context).pop(),
  );

  Widget _dismissHandle(AppTokens t) {
    final route = ModalRoute.of(context);
    return GestureDetector(
      key: const ValueKey('article-dismiss-handle'),
      dragStartBehavior: DragStartBehavior.down,
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: route is EditorialArticleRoute
          ? (_) => route.beginDismiss()
          : null,
      onVerticalDragUpdate: route is EditorialArticleRoute
          ? (d) => route.updateDismiss(
              d.primaryDelta! / MediaQuery.sizeOf(context).height,
            )
          : null,
      onVerticalDragEnd: route is EditorialArticleRoute
          ? (d) => route.endDismiss(
              d.primaryVelocity! / MediaQuery.sizeOf(context).height,
            )
          : null,
      onVerticalDragCancel: route is EditorialArticleRoute
          ? () => route.endDismiss(0)
          : null,
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
  }

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
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 眉题:文章所在栏目;从首页卡片进来时卡片已带出分类
            if ((article.categoryName ?? widget.preview?.categoryName)
                case final category?) ...[
              Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.accent,
                  fontSize: AppType.sizeFootnote,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (!_hasCover) ...[
              Text(
                article.title,
                style: TextStyle(
                  fontSize: AppType.sizeTitle2,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (article.metaRaw != null)
              Text(
                article.metaRaw!,
                style: TextStyle(
                  fontSize: AppType.sizeFootnote,
                  height: 1.7,
                  color: t.text2,
                ),
              ),
            const SizedBox(height: 18),
            Divider(height: .5, thickness: .5, color: t.separator),
          ],
        ),
      ),
    );
  }

  List<Widget> _contentSlivers() {
    final t = AppTokens.of(context);
    return [
      SliverList.builder(
        addRepaintBoundaries: false,
        itemCount: _blocks.length,
        itemBuilder: (context, i) {
          final block = _blocks[i];
          final bodyStyle = TextStyle(
            fontSize: _largeText
                ? AppType.readingLarge.fontSize
                : AppType.reading.fontSize,
            height: 1.85,
            letterSpacing: 0,
            color: t.text,
          );
          return RepaintBoundary(
            key: ValueKey('article-block-$i'),
            child: switch (block) {
              ImageBlock(:final url) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(
                  button: true,
                  label: '查看第 ${_imageIndex[i]! + 1} 张原图',
                  child: GestureDetector(
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
                padding: const EdgeInsets.fromLTRB(26, 10, 26, 16),
                child: RichContentText(block: block, style: bodyStyle),
              ),
              QuoteBlock(:final children) => Padding(
                padding: const EdgeInsets.fromLTRB(26, 8, 26, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final child in children.whereType<TextBlock>())
                      RichContentText(
                        block: child,
                        style: bodyStyle.copyWith(color: t.text2),
                      ),
                  ],
                ),
              ),
              SiteLinkBlock() || BilibiliBlock() => Padding(
                padding: const EdgeInsets.fromLTRB(26, 4, 26, 16),
                child: ContentLinkBlockView(block: block),
              ),
            },
          );
        },
      ),
    ];
  }

  Widget _continuationFooter(AppTokens t) {
    if (_reader.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: t.text2,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '正在加载后续内容',
              style: TextStyle(fontSize: AppType.sizeFootnote, color: t.text2),
            ),
          ],
        ),
      );
    }
    if (_reader.error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(26, 20, 26, 12),
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
    if (_reader.hasNext) return const SizedBox(height: 48);
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 32, 26, 12),
      child: Column(
        children: [
          Divider(height: .5, thickness: .5, color: t.separator),
          const SizedBox(height: 26),
          Text(
            'CHH',
            style: TextStyle(
              fontSize: AppType.sizeTitle2,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: t.text3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '正文已读完',
            style: TextStyle(fontSize: AppType.sizeFootnote, color: t.text2),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: '查看评论',
            variant: AppButtonVariant.plain,
            icon: AppIcons.comments,
            onPressed: _openDiscussion,
          ),
        ],
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
