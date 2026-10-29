/// 首页:上半编辑内容,下半社区讨论
///
/// 不再用「最新 / 热门 / 门户」三段并列 —— 它们不是同级概念:
/// 文章是编辑内容,帖子是社区内容,热门只是帖子流的一种排序。
/// 所以改成单屏下滑:幻灯片与精选占首屏吸引,帖子流占主体无限续页,
/// 热门降级为帖子流上的筛选。
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';
import '../design/typography.dart';
import '../ui/picker.dart';
import '../ui/segmented.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../di.dart';
import '../models/models.dart';
import '../widgets/search_entry_route.dart';
import '../widgets/editorial_cover.dart';
import '../widgets/editorial_article_route.dart';
import '../widgets/sliver_paged_list.dart';
import '../ui/plain_rows.dart';
import '../ui/press.dart';
import '../ui/chrome_button.dart';
import '../ui/nav_bar.dart';
import '../design/icons.dart';
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
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  /// 帖子流排序:最新 / 热门
  String _view = 'new';

  late Future<PortalHighlights> _highlights = portalRepo.highlights();

  final _scroll = ScrollController();
  final _listKey = GlobalKey<SliverPagedListState<ThreadSummary>>();
  final _offset = ValueNotifier<double>(0);
  final _titleKey = GlobalKey();
  double _collapseAt = double.infinity;

  @override
  void dispose() {
    _offset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // 大标题行的实际高度决定顶栏小标题出现的位置
  void _measureTitle() {
    final height = _titleKey.currentContext?.size?.height;
    if (height != null && height != _collapseAt && mounted) {
      setState(() => _collapseAt = height);
    }
  }

  String _today() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 星期${weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTitle());
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
                _offset.value = n.metrics.pixels;
              }
              return false;
            },
            child: _content(top),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: NavOverlay(
              inlineTitle: '精选',
              scrollOffset: _offset,
              collapseAt: _collapseAt,
              background: t.bg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(double top) => RefreshIndicator(
    onRefresh: () async {
      setState(() => _highlights = portalRepo.highlights(refresh: true));
      await _listKey.currentState?.refresh();
    },
    child: CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top + NavOverlay.barHeight)),
        // 日期眉题 + 大标题 + 同一行的搜索圆钮;铃铛已去掉,未读挂在底栏
        SliverToBoxAdapter(
          child: KeyedSubtree(
            key: _titleKey,
            child: LargeTitleHeader(
              eyebrow: _today(),
              title: '精选',
              accessory: Hero(
                tag: 'search-entry-feed',
                child: ChromeButton(
                  tooltip: '搜索',
                  icon: AppIcons.search,
                  onPressed: () => Navigator.of(context).push(
                    SearchEntryRoute(
                      builder: (_) => const SearchPage(
                        entryHeroTag: 'search-entry-feed',
                        autofocus: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _highlightsSection()),
        SliverToBoxAdapter(child: _discussionHeader()),
        SliverPagedList<ThreadSummary>(
          key: _listKey,
          controller: _scroll,
          itemKey: (thread) => thread.tid,
          loader: (page, {bool refresh = false}) async {
            final r = await forumRepo.guide(
              view: _view,
              page: page,
              refresh: refresh,
            );
            return Paged(items: r.threads, page: r.page);
          },
          // 行级监听:一次 markRead 只重建对应一行
          itemBuilder: (context, item) => ReadStateBuilder(
            tid: item.tid,
            replies: item.replies,
            builder: (context, state) => ThreadRow(
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
      ],
    ),
  );

  Widget _highlightsSection() {
    return FutureBuilder<PortalHighlights>(
      future: _highlights,
      builder: (context, snap) {
        final t = AppTokens.of(context);
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              8,
              AppSpace.screen,
              16,
            ),
            child: Container(
              height: 400,
              decoration: BoxDecoration(
                color: t.fill,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
            ),
          );
        }
        final h = snap.data ?? PortalHighlights.empty;
        if (h.isEmpty) {
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
                    _highlights = portalRepo.highlights(refresh: true);
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (feature != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  8,
                  AppSpace.screen,
                  0,
                ),
                child: _EditorialCard(
                  article: feature,
                  heroTag: 'feed-feature-${feature.aid}',
                  height: (MediaQuery.sizeOf(context).width * 1.1).clamp(
                    360.0,
                    480.0,
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
            if (shelf.isNotEmpty) _editorialShelf(shelf),
            if (moreReviews.isNotEmpty) _reviewSection(moreReviews),
            if (h.news.isNotEmpty) _newsSection(h.news),
          ],
        );
      },
    );
  }

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
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
          itemCount: articles.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final a = articles[i];
            final tag = 'feed-shelf-${a.aid}';
            return Align(
              alignment: Alignment.topCenter,
              child: ShelfCard(
                title: a.title,
                source: '灵感与日常',
                onTap: () => _openArticle(a, heroTag: tag),
                image: EditorialCover(
                  article: a,
                  heroTag: tag,
                  showText: false,
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
      // 快讯本身没有图,平铺的文字行就是合适的形态
      for (final n in news.take(4))
        NewsRow(
          title: n.title,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadDetailPage(tid: n.tid, title: n.title),
            ),
          ),
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
      for (final a in reviews.take(3))
        ArticleRow(
          title: a.title,
          eyebrow: a.categoryName,
          // 只用门户已给出的封面,没有就不留缩略图位
          thumbnail: (a.coverUrl?.isNotEmpty ?? false)
              ? NetImage(url: a.coverUrl!, width: 88, height: 60)
              : null,
          onTap: () => _openArticle(a),
        ),
    ],
  );

  /// 讨论区标题行。热门不再占一级入口,只是这里的排序。
  Widget _discussionHeader() {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        AppSpace.section,
        AppSpace.screen,
        12,
      ),
      child: Row(
        children: [
          Text(
            '社区讨论',
            style: TextStyle(
              fontSize: AppType.sizeTitle2,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: t.text,
            ),
          ),
          const Spacer(),
          AppSegmented<String>(
            compact: true,
            fallbackTitle: '排序',
            options: const [
              PickerOption(value: 'new', label: '最新'),
              PickerOption(value: 'hot', label: '热门'),
            ],
            value: _view,
            onChanged: _setSort,
          ),
        ],
      ),
    );
  }

  void _setSort(String value) {
    if (_view == value) return;
    setState(() => _view = value);
    _listKey.currentState?.refresh(clear: true);
  }

  void _openArticle(
    PortalArticle a, {
    String? heroTag,
    String? eyebrow,
    BoxFit coverFit = BoxFit.cover,
  }) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      EditorialArticleRoute(
        builder: (_) => ArticlePage(
          aid: a.aid,
          title: a.title,
          preview: a,
          heroTag: heroTag,
          eyebrow: eyebrow,
          coverFit: coverFit,
        ),
      ),
    );
  }
}

class _EditorialCard extends StatelessWidget {
  final PortalArticle article;
  final String heroTag;
  final double height;
  final String? eyebrow;
  final BoxFit fit;
  final VoidCallback onTap;
  const _EditorialCard({
    required this.article,
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: t.shadowE2,
          ),
          child: SizedBox(
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: EditorialCover(
                article: article,
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
