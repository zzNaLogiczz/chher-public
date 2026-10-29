/// 门户文章详情
///
/// 门户首页的区块解析见 portal_home_parser,文章列表见 portal_list_parser。
/// 门户文章图是直链 src,无懒加载,与论坛帖的 zoomfile 不同。
library;

import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'content_walker.dart';
import 'dom_utils.dart';

/// 这个页面是不是落到了论坛帖上
///
/// 门户条目 article-{aid} 可能 302 到 thread-{tid}。落地页有楼层容器就是帖子,
/// tid 优先取 canonical 链接,取不到再从正文里的帖子链接兜底。
int? threadBehindArticle(String html) {
  final doc = html_parser.parse(html);
  final isThread =
      doc.querySelector('#postlist') != null ||
      doc.querySelector('table[id^="pid"]') != null;
  if (!isThread) return null;

  final canonical =
      doc.querySelector('link[rel="canonical"]')?.attributes['href'] ?? '';
  return ChhUrls.tidFromUrl(canonical) ??
      ChhUrls.tidFromUrl(
        RegExp(r'thread-\d+-\d+-\d+\.html').firstMatch(html)?.group(0) ?? '',
      );
}

/// 落地页的标题
String titleOfPage(String html) {
  final doc = html_parser.parse(html);
  final subject = cleanText(doc.getElementById('thread_subject')?.text);
  if (subject.isNotEmpty) return subject;
  final t = cleanText(doc.querySelector('title')?.text);
  final i = t.indexOf(' - ');
  return i > 0 ? t.substring(0, i) : t;
}

/// 门户文章:h1.ph 标题,td#article_content 正文(图直链),.pg 分页
ArticleDetail parseArticle(String html, {required int aid}) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final title = cleanText(doc.querySelector('h1.ph')?.text);
  // .ptm / .xg1 are also used by the global search and navigation. Article
  // metadata is the p.xg1 directly below h1.ph inside the .vw title header.
  final meta = cleanText(doc.querySelector('.vw > .h > p.xg1')?.text);
  final body =
      doc.querySelector('td#article_content') ??
      doc.querySelector('#article_content');

  // 面包屑:门户 › 栏目 › 子栏目 › 查看内容,取最深的栏目
  final category = doc
      .querySelectorAll('#pt a[href*="mod=list"][href*="catid="]')
      .map((a) => cleanText(a.text))
      .where((name) => name.isNotEmpty)
      .lastOrNull;

  return ArticleDetail(
    aid: aid,
    title: title.isEmpty ? '门户文章' : title,
    metaRaw: meta.isEmpty ? null : meta,
    categoryName: category,
    // 门户文章图是直链 src,parseContentBlocks 的候选链已覆盖
    content: body == null ? const [] : parseContentBlocks(body),
    page: parsePager(doc),
  );
}

/// 文章作者身份:标题下元信息里的发布者(带 uid)与原作者(只有名字)
///
/// ```
/// <div class="vw"><div class="h"><h1 class="ph">…</h1>
///   <p class="xg1">2026-01-01 12:00| 发布者: <a href="space-uid-1001.html">示例发布者</a>| 原作者: 示例原作者</p>
/// ```
/// 编辑常代发他人的评测,评论区里真正答疑的多是原作者,所以两者都算作者。
({String? uid, Set<String> names}) parseArticleAuthors(String html) {
  final doc = html_parser.parse(html);
  final meta = doc.querySelector('.vw > .h > p.xg1');
  if (meta == null) return (uid: null, names: const <String>{});
  final publisher = findUserLink(meta);
  final names = <String>{
    if (publisher != null && cleanText(publisher.el.text).isNotEmpty)
      cleanText(publisher.el.text),
  };
  final original = RegExp(
    r'原作者\s*[:：]\s*([^|｜]+)',
  ).firstMatch(cleanText(meta.text))?.group(1)?.trim();
  if (original != null && original.isNotEmpty) names.add(original);
  return (uid: publisher?.uid, names: names);
}
