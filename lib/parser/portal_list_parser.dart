/// 门户文章列表
///
/// 两套结构,都用真实登录页实测过(2026-10-25):
///
/// 全部文章 `portal.php?page=N`,15 条一页:
/// ```
/// #threadulid
///   section#normalthread_{aid}
///     li
///       a.tm01 > img            封面,static.chiphell.com 直链
///       div.tmpad
///         a.tm03                标题
///         div.tm04              摘要
/// ```
///
/// 栏目文章 `portal.php?mod=list&catid=N&page=M`,16 条一页:
/// ```
/// div.bm_c.xld
///   dl.bbda.cl
///     dt.xs2 > a.xi2            标题
///     dd.xs2 > div.atc > img.tn 封面
///            + 摘要文本
///     dd > label > a.xi2        栏目名(href 带 catid)
///       + span.xg1              时间
/// ```
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

/// 栏目导航。顶部栏目与子栏目都在页面里,按 catid 去重。
List<PortalCategory> parsePortalCategories(String html) {
  final doc = html_parser.parse(html);
  final out = <int, PortalCategory>{};

  for (final a in doc.querySelectorAll('a[href*="mod=list"]')) {
    final href = a.attributes['href'] ?? '';
    final catid = int.tryParse(
      RegExp(r'catid=(\d+)').firstMatch(href)?.group(1) ?? '',
    );
    final name = cleanText(a.text);
    if (catid == null || name.isEmpty || name.length > 8) continue;
    out.putIfAbsent(catid, () => PortalCategory(catid: catid, name: name));
  }

  return out.values.toList();
}

/// 全部文章流
Paged<PortalArticle> parsePortalFeed(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final items = <PortalArticle>[];
  for (final sec in doc.querySelectorAll(
    '#threadulid section[id^="normalthread_"]',
  )) {
    final aid = int.tryParse(sec.id.split('_').last);
    final titleA =
        sec.querySelector('a.tm03') ?? sec.querySelector('a[href*="article-"]');
    final title = cleanText(titleA?.text);
    if (aid == null || title.isEmpty) continue;

    items.add(
      PortalArticle(
        aid: aid,
        title: title,
        coverUrl: _cover(sec),
        summary: _nullIfEmpty(cleanText(sec.querySelector('.tm04')?.text)),
        timeRaw: _nullIfEmpty(cleanText(sec.querySelector('.avart')?.text)),
      ),
    );
  }

  return Paged(items: items, page: parsePager(doc), nextUrl: nextPageUrl(doc));
}

/// 栏目文章列表
Paged<PortalArticle> parsePortalCategoryList(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final items = <PortalArticle>[];
  for (final dl in doc.querySelectorAll('div.bm_c dl.bbda')) {
    final titleA =
        dl.querySelector('dt a') ?? dl.querySelector('a[href*="article-"]');
    final href = titleA?.attributes['href'] ?? '';
    final aid = int.tryParse(
      RegExp(r'article-(\d+)-').firstMatch(href)?.group(1) ?? '',
    );
    final title = cleanText(titleA?.text);
    if (aid == null || title.isEmpty) continue;

    // 分类与时间在最后一个 dd 里,摘要混在带封面的那个 dd 的文本节点中
    final catA = dl.querySelector('label a');
    final summaryDd = dl.querySelector('dd.xs2');

    items.add(
      PortalArticle(
        aid: aid,
        title: title,
        coverUrl: _cover(dl),
        summary: _nullIfEmpty(textWithout(summaryDd, ['div.atc'])),
        categoryName: _nullIfEmpty(cleanText(catA?.text)),
        catid: int.tryParse(
          RegExp(
                r'catid=(\d+)',
              ).firstMatch(catA?.attributes['href'] ?? '')?.group(1) ??
              '',
        ),
        timeRaw: _nullIfEmpty(cleanText(dl.querySelector('span.xg1')?.text)),
      ),
    );
  }

  return Paged(items: items, page: parsePager(doc), nextUrl: nextPageUrl(doc));
}

/// 封面:门户图是直链 src,没有懒加载属性
String? _cover(dom.Element root) {
  final img = root.querySelector('img');
  final src = img?.attributes['src'];
  if (src == null || src.isEmpty) return null;
  return ChhUrls.absolutize(src);
}

String? _nullIfEmpty(String s) => s.isEmpty ? null : s;
