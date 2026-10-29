/// 搜索结果页(search.php?mod=forum&searchid=NNN)→ 结果列表
///
/// 结构示例(虚构标识与内容):
/// <div class="slst mtw" id="threadlist"><ul>
/// <li class="pbw" id="1001">
///   <h3 class="xs3"><a href="forum.php?mod=viewthread&tid=1001&highlight=硬件">
///       `<strong><font color="#ff0000">硬件</font></strong> 示例讨论`</a></h3>
///   <p class="xg1">2 个回复 - 1076 次查看</p>
///   <p>…摘要…</p>
///   <p><span>2026-01-01 12:00</span> - <span><a href="space-uid-1001.html">示例作者</a></span>
///      - <span><a href="forum-146-1.html" class="xi1">电脑讨论(新)</a></span></p>
/// </li>
/// 翻页:div.pgs → div.pg,a.nxt href = 下页 searchid URL
library;

import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';

SearchResultPage parseSearchResult(String html) {
  final doc = html_parser.parse(html);
  final rows = <ThreadSummary>[];

  for (final li in doc.querySelectorAll('#threadlist li.pbw')) {
    final tid = int.tryParse(li.id);
    final titleA = li.querySelector('h3 a[href*="tid="]');
    if (tid == null || titleA == null) continue;
    final title = titleA.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) continue;

    var replies = 0;
    var views = 0;
    final stats = li.querySelector('p.xg1')?.text ?? '';
    final m = RegExp(r'(\d+)\s*个回复\s*-\s*(\d+)\s*次查看').firstMatch(stats);
    if (m != null) {
      replies = int.parse(m.group(1)!);
      views = int.parse(m.group(2)!);
    }

    // 结构:p.xg1(统计)…若干摘要 p…最后一个 p(时间-作者-版块)
    final ps = li.querySelectorAll('p');
    final meta = ps.isNotEmpty ? ps.last : null;
    String? snippet;
    if (ps.length > 2) {
      snippet = ps
          .sublist(1, ps.length - 1)
          .map((p) => p.text.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((t) => t.isNotEmpty)
          .join(' ');
      if (snippet.isEmpty) snippet = null;
    }

    final timeRaw = meta?.querySelector('span')?.text.trim();
    final author =
        meta?.querySelector('a[href*="space-uid"]')?.text.trim() ?? '';
    final forumA = meta?.querySelector('a[href*="forum-"], a[href*="fid="]');
    final forumName = forumA?.text.trim();
    final forumFid = forumA == null
        ? null
        : ChhUrls.fidFromUrl(forumA.attributes['href'] ?? '');

    rows.add(
      ThreadSummary(
        tid: tid,
        title: title,
        author: author,
        createdAt: ChhUrls.parseTime(timeRaw ?? ''),
        replies: replies,
        views: views,
        forumName: (forumName == null || forumName.isEmpty) ? null : forumName,
        forumFid: forumFid,
        snippet: snippet == null || snippet.length < 300
            ? snippet
            : snippet.substring(0, 300),
      ),
    );
  }

  // 翻页:提取下一页绝对 URL
  String? nextUrl;
  int current = 1;
  for (final pgs in doc.querySelectorAll('div.pgs')) {
    final pg = pgs.querySelector('div.pg');
    if (pg == null) continue;
    current = int.tryParse(pg.querySelector('strong')?.text.trim() ?? '') ?? 1;
    final nxt = pg.querySelector('a.nxt');
    final href = nxt?.attributes['href'];
    if (href != null && href.isNotEmpty) nextUrl = ChhUrls.absolutize(href);
    break;
  }

  return SearchResultPage(
    rows: rows,
    page: PageInfo(current: current, hasNext: nextUrl != null),
    nextUrl: nextUrl,
  );
}
