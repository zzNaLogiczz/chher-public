/// 首页:上半编辑内容,下半社区讨论
///
/// 不再用「最新 / 热门 / 门户」三段并列 —— 它们不是同级概念:
/// 文章是编辑内容,帖子是社区内容,热门只是帖子流的一种排序。
/// 所以改成单屏下滑:幻灯片与精选占首屏吸引,帖子流占主体无限续页,
/// 热门降级为帖子流上的筛选。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../data/editorial_cover_cache.dart';
import '../data/featured_cover_prefetch.dart';
import '../data/portal_repository.dart';
import '../data/forum_repository.dart';
import '../data/thread_read_index.dart';
import '../design/motion.dart';
import '../widgets/shelf_scroll_physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../ui/app_button.dart';
import '../ui/feedback.dart';
import '../design/typography.dart';
import '../ui/picker.dart';
import '../ui/segmented.dart';
import '../design/tokens.dart';
import '../design/shapes.dart';
import '../di.dart';
import '../models/models.dart';
import '../widgets/search_entry_route.dart';
import '../widgets/editorial_cover.dart';
import '../widgets/editorial_article_route.dart';
import '../widgets/lacquer_tab_scaffold.dart';
import '../widgets/sliver_paged_list.dart';
import '../widgets/expressive_controls.dart';
import '../ui/plain_rows.dart';
import '../ui/press.dart';
import '../ui/chrome_button.dart';
import '../widgets/net_image.dart';
import '../ui/cards.dart';
import '../ui/section_header.dart';
import 'article_page.dart';
import 'articles_view.dart';
import 'forum_threads_page.dart';
import 'search_page.dart';
import 'thread_detail_page.dart';

/// 快讯所在版块,实测区块标题链到 forum-317
const int _newsForumFid = 317;

class FeedPage extends StatefulWidget {
  final PortalRepository? portalRepository;
  final ForumRepository? forumRepository;
  final EditorialCoverCache? coverCache;
  const FeedPage({
    super.key,
    this.portalRepository,
    this.forumRepository,
    this.coverCache,
  });

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  /// 帖子流排序:最新 / 热门
  String _view = 'new';

  PortalRepository get _portal => widget.portalRepository ?? portalRepo;
  ForumRepository get _forum => widget.forumRepository ?? forumRepo;
  late Future<PortalHighlights> _highlights = _portal.highlights();
  PortalHighlights? _lastHighlights;

  final _listKey = GlobalKey<SliverPagedListState<ThreadSummary>>();

  final _scroll = ScrollController();
  final _scrollOffset = ValueNotifier<double>(0);
  final _discussionAnchor = GlobalKey();
  late final _prefetch = FeaturedCoverPrefetch(
    repository: _portal,
    cache: widget.coverCache ?? editorialCoverCache,
    imageSize: _imageSize,
  );

  Future<Size?> _imageSize(String url) async {
    if (!mounted) return null;
    final stream = boundedNetworkImage(
      url,
      boundedImageDecodeWidth(
        MediaQuery.sizeOf(context).width,
        MediaQuery.devicePixelRatioOf(context),
      ),
    ).resolve(createLocalImageConfiguration(context));
    final result = Completer<Size?>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!result.isCompleted) {
          result.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          );
        }
        info.dispose();
      },
      onError: (Object _, StackTrace? stack) {
        if (!result.isCompleted) result.complete(null);
      },
    );
    stream.addListener(listener);
    try {
      return await result.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => null,
      );
    } finally {
      stream.removeListener(listener);
    }
  }

  Future<void> _refresh() async {
    final highlights = _portal.highlights(refresh: true);
    setState(() {
      _highlights = highlights;
    });
    await Future.wait([
      highlights,
      if (_listKey.currentState != null) _listKey.currentState!.refresh(),
    ]);
  }

  String _today() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 星期${weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    // 风格分支:朱砂红走漆面骨架,薄雾白走 1.0.7 的纸面大标题骨架
    final misty = AppTokens.of(context).style == AppearanceStyle.misty;
    final searchButton = Hero(
      tag: 'search-entry-feed',
      child: ChromeButton(
        tooltip: '搜索',
        icon: AppIcons.search,
        // 漆面上是奶白玻璃圆钮,薄雾白纸面用默认描边
        onLac: !misty,
        onPressed: () => Navigator.of(context).push(
          SearchEntryRoute(
            builder: (_) => const SearchPage(
              entryHeroTag: 'search-entry-feed',
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    return LacquerTabScaffold(
      title: '精选',
      eyebrow: _today(),
      actions: [searchButton],
      controller: _scroll,
      scrollOffset: _scrollOffset,
      onRefresh: _refresh,
      seamOverlap: HomeTokens.featureOverlap,
      discussionAnchor: _discussionAnchor,
      compactAccessory: _sortControl(onLac: !misty),
      slivers: [
        SliverToBoxAdapter(child: _highlightsSection()),
        SliverToBoxAdapter(child: _discussionHeader()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            HomeTokens.inset,
            0,
            HomeTokens.inset,
            16,
          ),
          sliver: DecoratedSliver(
            decoration: BoxDecoration(
              color: AppTokens.of(context).surface,
              borderRadius: BorderRadius.circular(HomeTokens.cardRadius),
            ),
            sliver: SliverPadding(
              padding: const EdgeInsets.all(HomeTokens.cardPadding),
              sliver: SliverPagedList<ThreadSummary>(
                key: _listKey,
                controller: _scroll,
                itemKey: (thread) => thread.tid,
                itemRevision: (thread) => (
                  thread.title,
                  thread.author,
                  thread.forumName,
                  ThreadRow.displayTime(thread),
                  thread.replies,
                ),
                loader: (page, {bool refresh = false}) async {
                  final r = await _forum.guide(
                    view: _view,
                    page: page,
                    refresh: refresh,
                  );
                  return Paged(items: r.threads, page: r.page);
                },
                itemBuilder: (context, item) => ReadStateBuilder(
                  tid: item.tid,
                  replies: item.replies,
                  builder: (context, state) => _DiscussionRow(
                    thread: item,
                    readState: state,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ThreadDetailPage(
                          tid: item.tid,
                          seenReplies: item.replies,
                          title: item.title,
                          fid: item.forumFid,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _highlightsSection() {
    return FutureBuilder<PortalHighlights>(
      future: _highlights,
      builder: (context, snap) {
        final t = AppTokens.of(context);
        final h = snap.data ?? _lastHighlights;
        if (snap.hasData) _lastHighlights = snap.data;
        if (h == null && snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              8,
              AppSpace.screen,
              16,
            ),
            child: LoadingPlaceholder(
              child: Container(
                key: const ValueKey('feed-highlights-skeleton'),
                height: HomeTokens.featureHeight(
                  MediaQuery.sizeOf(context).width,
                ),
                decoration: ShapeDecoration(
                  color: t.fill,
                  shape: appShape(AppRadii.lg),
                ),
              ),
            ),
          );
        }
        if (h == null || h.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpace.screen),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '精选暂时没有加载出来',
                    style: TextStyle(
                      fontSize: AppType.sizeFootnote,
                      color: t.text2,
                    ),
                  ),
                ),
                AppButton(
                  label: '重试',
                  variant: AppButtonVariant.plain,
                  onPressed: () => setState(() {
                    _highlights = _portal.highlights(refresh: true);
                  }),
                ),
              ],
            ),
          );
        }
        final readableReviews = h.reviews
            .where(
              (a) => !RegExp(
                r'youtu\.?be|bilibili|视频地址',
                caseSensitive: false,
              ).hasMatch(a.summary ?? ''),
            )
            .toList();
        final feature =
            readableReviews.firstOrNull ??
            h.reviews.firstOrNull ??
            h.banners.firstOrNull;
        final shelf = h.banners.where((a) => a.aid != feature?.aid).toList();
        final moreReviews = h.reviews
            .where((a) => a.aid != feature?.aid)
            .toList();
        if (feature != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_prefetch.fetch(feature.aid));
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (feature != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HomeTokens.inset,
                  0,
                  HomeTokens.inset,
                  0,
                ),
                child: _articleArrival(
                  feature,
                  _EditorialCard(
                    article: feature,
                    scrollOffset: _scrollOffset,
                    heroTag: 'feed-feature-${feature.aid}',
                    height: HomeTokens.featureHeight(
                      MediaQuery.sizeOf(context).width,
                    ),
                    eyebrow: '本期精选',
                    fit: BoxFit.contain,
                    onTap: () => _openArticle(
                      feature,
                      heroTag: 'feed-feature-${feature.aid}',
                      eyebrow: '本期精选',
                      coverFit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            if (shelf.isNotEmpty) _editorialShelf(shelf),
            if (moreReviews.isNotEmpty) _reviewSection(moreReviews),
            if (h.news.isNotEmpty) _newsSection(h.news),
            if (snap.hasError)
              AppButton(
                label: '未能刷新，轻点重试',
                variant: AppButtonVariant.plain,
                onPressed: () => setState(() {
                  _highlights = _portal.highlights(refresh: true);
                }),
              ),
          ],
        );
      },
    );
  }

  Widget _articleArrival(PortalArticle article, Widget child) =>
      ExpressivePageReveal(
        key: ValueKey(article.aid),
        active: true,
        animateOnMount: true,
        revision: (
          article.aid,
          article.title,
          article.coverUrl,
          article.summary,
          article.categoryName,
        ),
        child: child,
      );

  Widget _editorialShelf(List<PortalArticle> articles) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(
        title: '社区精选',
        actionLabel: '全部',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ArticlesPage())),
      ),
      // 横滑卡:图上字下,只有图片部分参与展开成文章的 Hero
      SizedBox(
        height: ShelfCard.heightFor(MediaQuery.textScalerOf(context)),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: ShelfScrollPhysics(
            reducedMotion: MediaQuery.disableAnimationsOf(context),
            itemExtent: ShelfCard.width + HomeTokens.shelfGap,
          ),
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(horizontal: HomeTokens.inset),
          itemCount: articles.length,
          findItemIndexCallback: (key) {
            if (key is! ValueKey<int>) return null;
            final index = articles.indexWhere((a) => a.aid == key.value);
            return index < 0 ? null : index;
          },
          separatorBuilder: (_, _) =>
              const SizedBox(width: HomeTokens.shelfGap),
          itemBuilder: (context, i) {
            final a = articles[i];
            final tag = 'feed-shelf-${a.aid}';
            return Align(
              key: ValueKey(a.aid),
              alignment: Alignment.topCenter,
              child: _articleArrival(
                a,
                ShelfCard(
                  title: a.title,
                  onTap: () => _openArticle(a, directDetail: true),
                  image: EditorialCover(
                    article: a,
                    heroTag: tag,
                    showText: false,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _newsSection(List<NewsItem> news) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(
        title: '快讯',
        actionLabel: '全部',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                const ForumThreadsPage(fid: _newsForumFid, title: '快讯'),
          ),
        ),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          var style = DefaultTextStyle.of(context).style.merge(
            AppType.subhead.copyWith(color: AppTokens.of(context).text),
          );
          if (MediaQuery.boldTextOf(context)) {
            style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
          }
          var capsule = false;
          if (news.length == 1) {
            final painter =
                TextPainter(
                  text: TextSpan(text: news.single.title, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  locale: Localizations.maybeLocaleOf(context),
                  maxLines: 1,
                )..layout(
                  maxWidth:
                      (constraints.maxWidth -
                              2 *
                                  (HomeTokens.inset +
                                      HomeTokens.cardPadding +
                                      HomeTokens.rowInset) -
                              HomeTokens.newsDot -
                              12)
                          .clamp(0.0, double.infinity),
                );
            capsule =
                !painter.didExceedMaxLines &&
                painter.height <=
                    AppSizes.singleLineHeight - 2 * HomeTokens.cardPadding;
            painter.dispose();
          }
          return _card([
            for (final n in news.take(4))
              ExpressivePageReveal(
                key: ValueKey(n.tid),
                active: true,
                animateOnMount: true,
                revision: (n.tid, n.title),
                child: _CardRow(
                  capsule: capsule,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ThreadDetailPage(tid: n.tid, title: n.title),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: capsule
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          top: capsule ? 0 : 8,
                          right: 12,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTokens.of(
                              context,
                            ).accent.withValues(alpha: .35),
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(
                            dimension: HomeTokens.newsDot,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          n.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ], capsule: capsule);
        },
      ),
    ],
  );

  Widget _reviewSection(List<PortalArticle> reviews) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(
        title: '更多评测',
        actionLabel: '全部',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ArticlesPage(initialCategoryName: '评测'),
          ),
        ),
      ),
      _card([
        for (final a in reviews.take(3))
          _articleArrival(
            a,
            _CardRow(
              onTap: () => _openArticle(a),
              child: Row(
                children: [
                  if (a.coverUrl?.isNotEmpty ?? false) ...[
                    AppClip(
                      radius: AppRadii.sm,
                      child: NetImage(url: a.coverUrl!, width: 76, height: 52),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (a.categoryName?.isNotEmpty ?? false)
                          Text(
                            a.categoryName!,
                            style: AppType.footnote.copyWith(
                              color: AppTokens.of(context).text3,
                            ),
                          ),
                        Text(
                          a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.subhead.copyWith(
                            color: AppTokens.of(context).text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ]),
    ],
  );

  Widget _card(List<Widget> rows, {bool capsule = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: HomeTokens.inset),
    child: DecoratedBox(
      decoration: capsule
          ? ShapeDecoration(
              color: AppTokens.of(context).surface,
              shape: appShape(AppRadii.full),
              shadows: HomeTokens.cardShadow(AppTokens.of(context)),
            )
          : BoxDecoration(
              color: AppTokens.of(context).surface,
              borderRadius: BorderRadius.circular(HomeTokens.cardRadius),
              boxShadow: HomeTokens.cardShadow(AppTokens.of(context)),
            ),
      child: Padding(
        padding: EdgeInsets.all(capsule ? 0 : HomeTokens.cardPadding),
        child: Column(children: rows),
      ),
    ),
  );

  /// 讨论区标题行。热门不再占一级入口,只是这里的排序。
  Widget _discussionHeader() {
    final t = AppTokens.of(context);
    return Padding(
      key: _discussionAnchor,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        AppSpace.section,
        AppSpace.screen,
        12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '社区讨论',
              style: TextStyle(
                fontSize: AppType.sizeTitle2,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: _sortControl()),
        ],
      ),
    );
  }

  Widget _sortControl({bool onLac = false}) => AppSegmented<String>(
    compact: true,
    onLac: onLac,
    fallbackTitle: '排序',
    options: const [
      PickerOption(value: 'new', label: '最新'),
      PickerOption(value: 'hot', label: '热门'),
    ],
    value: _view,
    onChanged: _setSort,
  );

  void _setSort(String value) {
    if (_view == value) return;
    setState(() => _view = value);
    _listKey.currentState?.refresh();
  }

  void _openArticle(
    PortalArticle a, {
    String? heroTag,
    String? eyebrow,
    BoxFit coverFit = BoxFit.cover,
    bool directDetail = false,
  }) {
    HapticFeedback.selectionClick();
    Widget reader(BuildContext context) => ArticlePage(
      aid: a.aid,
      title: a.title,
      preview: directDetail ? null : a,
      heroTag: heroTag,
      eyebrow: eyebrow,
      coverFit: coverFit,
      loadPage: (page, refresh) =>
          _portal.openArticle(a.aid, page: page, refresh: refresh),
    );
    Navigator.of(context).push(
      heroTag == null || directDetail
          ? MaterialPageRoute<void>(builder: reader)
          : EditorialArticleRoute(builder: reader),
    );
  }
}

class _EditorialCard extends StatelessWidget {
  final PortalArticle article;
  final ValueListenable<double>? scrollOffset;
  final String heroTag;
  final double height;
  final String? eyebrow;
  final BoxFit fit;
  final VoidCallback onTap;
  const _EditorialCard({
    required this.article,
    this.scrollOffset,
    required this.heroTag,
    required this.height,
    required this.onTap,
    this.eyebrow,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    // 精选大卡:24 圆角 + e2 阴影;按下缩到 0.97
    return RepaintBoundary(
      child: PressScale(
        onTap: onTap,
        scale: .97,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: appShape(AppRadii.lg),
            shadows: HomeTokens.floatingShadow(t),
          ),
          child: SizedBox(
            height: height,
            child: AppClip(
              radius: AppRadii.lg,
              child: EditorialCover(
                article: article,
                scrollOffset: scrollOffset,
                heroTag: heroTag,
                fit: fit,
                eyebrow: eyebrow,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool capsule;
  const _CardRow({
    required this.child,
    required this.onTap,
    this.capsule = false,
  });
  @override
  Widget build(BuildContext context) => capsule
      ? PressHighlight(
          onTap: onTap,
          paintInset: const EdgeInsets.all(HomeTokens.cardPadding),
          borderRadius: BorderRadius.circular(AppRadii.full),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.singleLineHeight - 2 * HomeTokens.cardPadding,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HomeTokens.rowInset,
              ),
              child: child,
            ),
          ),
        )
      : AppClip(
          radius: HomeTokens.rowRadius,
          child: PressHighlight(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HomeTokens.rowInset,
                vertical: 12,
              ),
              child: child,
            ),
          ),
        );
}

class _DiscussionRow extends StatelessWidget {
  final ThreadSummary thread;
  final ThreadReadState readState;
  final VoidCallback onTap;
  const _DiscussionRow({
    required this.thread,
    required this.readState,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final metadata = [
      thread.forumName,
      thread.author,
      ThreadRow.displayTime(thread),
    ].whereType<String>().where((s) => s.isNotEmpty).toList();
    final fresh = readState is ThreadReadNewReplies
        ? (readState as ThreadReadNewReplies).count
        : null;
    return _CardRow(
      onTap: onTap,
      child: Semantics(
        label: readSemanticsLabel(readState),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: readTitleColor(t, readState)),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? AppMotion.reducedFade
                  : AppMotion.fade,
              builder: (_, color, _) => Text(
                thread.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.headline.copyWith(
                  fontSize: HomeTokens.rowTitleSize,
                  color: color,
                  fontWeight: readState is ThreadReadSeen
                      ? FontWeight.w500
                      : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      for (final item in metadata)
                        Text(
                          item,
                          style: AppType.footnote.copyWith(color: t.text3),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: fresh == null
                      ? '${thread.replies} 回复'
                      : '有 $fresh 条新回复，共 ${thread.replies} 回复',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.tabMessages, size: 14, color: t.text3),
                      const SizedBox(width: 4),
                      Text(
                        fresh == null ? '${thread.replies}' : '+$fresh',
                        style: AppType.footnote.copyWith(
                          color: fresh == null ? t.text3 : t.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
