/// 门户首页的编辑内容(实测 2026-10-25)
///
/// ```
/// #newBannerSwiper .swiper-wrapper > .swiper-slide     幻灯片,9 片
///   img.img-cover                                      封面
///   a[href=article-{aid}] > p                          标题
///
/// #portal_block_673_content li > a[href=thread-{tid}]  快讯,指向论坛帖
///
/// #portal_block_675_content li                         评测
///   a.tm01 > img                                       封面
///   div.tmpad
///     a.tm03                                           标题
///     div.avimain  span(日期) .avie(浏览) .arep(回复) a.asort(栏目)
///     div.tm04                                         摘要
/// ```
///
/// 幻灯片里有 swiper 克隆出来的 duplicate 片,必须按 aid 去重,否则首尾会重复。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

PortalHighlights parsePortalHighlights(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  return PortalHighlights(
    banners: _banners(doc),
    news: _news(doc),
    reviews: _reviews(doc),
  );
}

List<PortalArticle> _banners(dom.Document doc) {
  final seen = <int>{};
  final out = <PortalArticle>[];

  for (final slide in doc.querySelectorAll('#newBannerSwiper .swiper-slide')) {
    final a = slide.querySelector('a[href*="article-"]');
    final aid = _aid(a?.attributes['href']);
    final title = cleanText(a?.querySelector('p')?.text ?? a?.text);
    // swiper 会克隆首尾片,去重后顺序仍是原始顺序
    if (aid == null || title.isEmpty || !seen.add(aid)) continue;

    final src = slide.querySelector('img')?.attributes['src'];
    out.add(
      PortalArticle(
        aid: aid,
        title: title,
        coverUrl: (src == null || src.isEmpty) ? null : ChhUrls.absolutize(src),
      ),
    );
  }
  return out;
}

List<NewsItem> _news(dom.Document doc) {
  final out = <NewsItem>[];
  final seen = <int>{};

  for (final a in doc.querySelectorAll('#portal_block_673_content a[href]')) {
    final href = a.attributes['href'] ?? '';
    final tid = ChhUrls.tidFromUrl(href);
    final title = cleanText(a.text);
    // 区块标题那一条指向版块而不是帖子,自然被过滤掉
    if (tid == null || title.isEmpty || !seen.add(tid)) continue;
    out.add(NewsItem(tid: tid, title: title));
  }
  return out;
}

List<PortalArticle> _reviews(dom.Document doc) {
  final out = <PortalArticle>[];
  final seen = <int>{};

  for (final li in doc.querySelectorAll('#portal_block_675_content li')) {
    final titleA =
        li.querySelector('a.tm03') ?? li.querySelector('a[href*="article-"]');
    final aid = _aid(titleA?.attributes['href']);
    final title = cleanText(titleA?.text);
    if (aid == null || title.isEmpty || !seen.add(aid)) continue;

    final src = li.querySelector('img')?.attributes['src'];
    final meta = li.querySelector('.avimain');

    out.add(
      PortalArticle(
        aid: aid,
        title: title,
        coverUrl: (src == null || src.isEmpty) ? null : ChhUrls.absolutize(src),
        summary: _orNull(cleanText(li.querySelector('.tm04')?.text)),
        categoryName: _orNull(cleanText(meta?.querySelector('a.asort')?.text)),
        timeRaw: _orNull(cleanText(meta?.querySelector('span')?.text)),
      ),
    );
  }
  return out;
}

int? _aid(String? href) => int.tryParse(
  RegExp(r'article-(\d+)-').firstMatch(href ?? '')?.group(1) ?? '',
);

String? _orNull(String s) => s.isEmpty ? null : s;
