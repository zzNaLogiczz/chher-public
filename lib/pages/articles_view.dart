/// Editorial discovery with real category filters and server pagination.
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';
import '../ui/press.dart';
import '../design/typography.dart';
import '../ui/picker.dart';

import '../design/tokens.dart';
import '../di.dart';
import '../models/models.dart';
import '../widgets/browse_controls.dart';
import '../widgets/net_image.dart';
import '../widgets/state_view.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/editorial_cover.dart';
import '../widgets/editorial_article_route.dart';
import 'article_page.dart';

class ArticlesPage extends StatelessWidget {
  /// 打开时选中的栏目名(例如"评测");栏目清单里没有这个名字时显示全部
  final String? initialCategoryName;
  const ArticlesPage({super.key, this.initialCategoryName});
  @override
  Widget build(BuildContext context) => BrowseScaffold(
    title: '发现文章',
    body: ArticlesView(initialCategoryName: initialCategoryName),
  );
}

class ArticlesView extends StatefulWidget {
  final Future<Paged<PortalArticle>> Function(
    int category,
    int page,
    bool refresh,
  )?
  loadArticles;
  final Future<List<PortalCategory>> Function()? loadCategories;

  /// 按站点真实栏目名选中初始栏目,不猜测 catid
  final String? initialCategoryName;
  const ArticlesView({
    super.key,
    this.loadArticles,
    this.loadCategories,
    this.initialCategoryName,
  });
  @override
  State<ArticlesView> createState() => _ArticlesViewState();
}

class _ArticlesViewState extends State<ArticlesView> {
  final _items = <PortalArticle>[];
  List<PortalCategory> _categories = const [PortalCategory.all];
  int _catid = 0;
  int _page = 1;
  int _generation = 0;
  bool _hasNext = false;
  bool _loading = false;
  bool _first = true;
  Object? _error;
  int? _failedPage;

  /// 初始栏目尚未从清单中解析出来
  static const _resolving = -1;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategoryName == null) {
      _loadCategories();
      _load(1);
    } else {
      _catid = _resolving;
      _openInitialCategory(widget.initialCategoryName!);
    }
  }

  /// 栏目清单与首页共用同一张门户页(命中缓存),先取到真实 catid 再读列表,
  /// 避免先显示全部再闪到目标栏目
  Future<void> _openInitialCategory(String name) async {
    await _loadCategories();
    if (!mounted) return;
    final match = _categories.where((c) => c.name == name).firstOrNull;
    setState(() => _catid = match?.catid ?? 0);
    _load(1);
  }

  Future<void> _loadCategories() async {
    try {
      final categories =
          await (widget.loadCategories?.call() ?? portalRepo.categories());
      if (!mounted) return;
      final unique = <int, PortalCategory>{0: PortalCategory.all};
      for (final category in categories) {
        unique[category.catid] = category;
      }
      setState(() => _categories = unique.values.toList());
    } catch (_) {
      /* The unfiltered feed remains available. */
    }
  }

  Future<void> _load(int page, {bool refresh = false}) async {
    if (_loading && page != 1) return;
    final generation = page == 1 ? ++_generation : _generation;
    final category = _catid;
    setState(() {
      _loading = true;
      _error = null;
      _failedPage = null;
    });
    try {
      final response =
          await (widget.loadArticles?.call(category, page, refresh) ??
              portalRepo.articles(
                catid: category,
                page: page,
                refresh: refresh,
              ));
      if (!mounted || generation != _generation) return;
      setState(() {
        if (page > 1 && response.page.current <= _page) {
          _hasNext = false;
          return;
        }
        if (page == 1) _items.clear();
        final known = _items.map((e) => e.aid).toSet();
        _items.addAll(response.items.where((e) => known.add(e.aid)));
        _page = response.page.current;
        _hasNext = response.page.hasNext;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          _failedPage = page;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _first = false;
        });
      }
    }
  }

  void _pickCategory(int category) {
    if (category == _catid) return;
    setState(() {
      _catid = category;
      _items.clear();
      _first = true;
      _hasNext = false;
    });
    _load(1);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screen - 4,
          0,
          AppSpace.screen,
          4,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: PickerButton<int>(
            sheetTitle: '选择栏目',
            options: [
              for (final category in _categories)
                PickerOption(value: category.catid, label: category.name),
            ],
            value: _catid,
            // 解析期间先显示目标栏目名,解析后文字不变,不出现"全部"闪过
            placeholder: widget.initialCategoryName,
            onChanged: _pickCategory,
          ),
        ),
      ),
      Expanded(
        child: ExpressivePageReveal(
          active: true,
          revision: (_catid, _first),
          child: _body(),
        ),
      ),
    ],
  );

  Widget _body() {
    final t = AppTokens.of(context);
    if (_first && _items.isEmpty) return StateView.loading();
    final error = _error;
    if (error != null && _items.isEmpty) {
      return error is PageMessage
          ? StateView.forMessage(
              error,
              onLogin: () => Navigator.pushNamed(context, '/login'),
            )
          : StateView.error(error, onRetry: () => _load(1, refresh: true));
    }
    return RefreshIndicator(
      onRefresh: () => _load(1, refresh: true),
      child: BrowsePaginationObserver(
        enabled: _hasNext && !_loading && _error == null,
        threshold: 500,
        onLoadMore: () => _load(_page + 1),
        child: ListView.builder(
          key: PageStorageKey('articles-$_catid'),
          primary: true,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          itemCount: _items.isEmpty
              ? 1
              : _items.length + (_items.length > 1 ? 1 : 0) + 1,
          itemBuilder: (context, index) {
            if (_items.isEmpty) {
              return SizedBox(
                height: 300,
                child: StateView.empty(message: '这个栏目还没有文章'),
              );
            }
            if (index == 0) {
              return _FeaturedArticle(
                article: _items.first,
                heroTag: 'discover-$_catid-${_items.first.aid}',
              );
            }
            final hasHeading = _items.length > 1;
            if (hasHeading && index == 1) {
              return Padding(
                padding: const EdgeInsets.only(top: 28, bottom: 17),
                child: Text(
                  '继续发现',
                  style: TextStyle(
                    fontSize: AppType.sizeTitle2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.4,
                    color: t.text,
                  ),
                ),
              );
            }
            final articleIndex = index - (hasHeading ? 1 : 0);
            if (articleIndex < _items.length) {
              return _ArticleRow(article: _items[articleIndex]);
            }
            if (error != null) {
              return AppButton(
                label: '继续加载',
                variant: AppButtonVariant.plain,
                icon: AppIcons.refresh,
                onPressed: () =>
                    _load(_failedPage ?? _page + 1, refresh: _failedPage == 1),
              );
            }
            return ListFooter(loading: _loading, exhausted: !_hasNext);
          },
        ),
      ),
    );
  }
}

void _openArticle(
  BuildContext context,
  PortalArticle article, {
  String? heroTag,
}) => Navigator.push(
  context,
  EditorialArticleRoute(
    reduceMotion: MediaQuery.disableAnimationsOf(context),
    builder: (_) => ArticlePage(
      aid: article.aid,
      title: article.title,
      preview: article,
      heroTag: heroTag,
    ),
  ),
);

class _FeaturedArticle extends StatelessWidget {
  final PortalArticle article;
  final String heroTag;
  const _FeaturedArticle({required this.article, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (article.coverUrl?.isNotEmpty ?? false) {
      final typeExtra =
          (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0.0, 2.0) * 100;
      return PressScale(
        scale: .97,
        onTap: () => _openArticle(context, article, heroTag: heroTag),
        child: SizedBox(
          height:
              (MediaQuery.sizeOf(context).width * 1.1).clamp(360.0, 480.0) +
              typeExtra,
          child: EditorialCover(article: article, heroTag: heroTag),
        ),
      );
    }
    final summary = article.summary?.trim();
    final readableSummary =
        summary != null &&
        summary.isNotEmpty &&
        !RegExp(
          r'https?://|youtube|bilibili|youtu\.be',
          caseSensitive: false,
        ).hasMatch(summary);
    return Semantics(
      button: true,
      child: PressScale(
        scale: .97,
        onTap: () => _openArticle(context, article),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: t.separator, width: .5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.categoryName ?? 'CHH 精选',
                      style: TextStyle(
                        fontSize: AppType.sizeFootnote,
                        color: t.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      article.title,
                      style: TextStyle(
                        fontSize: AppType.sizeTitle2,
                        height: 1.4,
                        letterSpacing: -.4,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    if (readableSummary) ...[
                      const SizedBox(height: 12),
                      Text(
                        summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.sizeFootnote,
                          height: 1.7,
                          color: t.text2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            article.timeRaw ?? '阅读全文',
                            style: TextStyle(
                              fontSize: AppType.sizeFootnote,
                              color: t.text2,
                            ),
                          ),
                        ),
                        Icon(AppIcons.forward, size: 20, color: t.accent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final PortalArticle article;
  const _ArticleRow({required this.article});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      children: [
        Semantics(
          button: true,
          child: PressHighlight(
            onTap: () => _openArticle(context, article),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (article.categoryName != null) ...[
                          Text(
                            article.categoryName!,
                            style: TextStyle(
                              fontSize: AppType.sizeFootnote,
                              color: t.text2,
                            ),
                          ),
                          const SizedBox(height: 5),
                        ],
                        Text(
                          article.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.sizeBody,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                            color: t.text,
                          ),
                        ),
                        if (article.timeRaw != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            article.timeRaw!,
                            style: TextStyle(
                              fontSize: AppType.sizeFootnote,
                              color: t.text3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (article.coverUrl != null) ...[
                    const SizedBox(width: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: SizedBox(
                        width: 96,
                        height: 90,
                        child: NetImage(url: article.coverUrl!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Divider(height: .5, thickness: .5, color: t.separator),
      ],
    );
  }
}
