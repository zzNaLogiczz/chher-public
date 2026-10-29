/// 版块页(forum.php?mod=forumdisplay)→ 帖子列表
///
/// 结构(实测):
/// <tbody id="normalthread_2904966">          ← 置顶为 stickthread_XXX
///   <th class="new">
///     <em>[<a href="...typeid=1010">ITX</a>]</em>
///     <a href="thread-2904966-1-1.html" class="s xst">标题</a>
///     <i class="fico-image ..."></i>          ← 含图标记
///   </th>
///   <td class="by"><cite><a href="space-uid-..">作者</a></cite>
///                  <em><span>2026-9-25 14:55</span></em></td>
///   <td class="num"><a ..>2</a><em>1434</em></td>   ← 回复 / 查看
///   <td class="by"><cite><a>最后回复人</a></cite>
///                  <em><a href="...goto=lastpost">2026-10-22 12:39</a></em></td>
/// </tbody>
/// 翻页:div.pgs → div.pg,a.nxt = 下一页,strong = 当前页
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';

ThreadListPage parseThreadList(String html) {
  final doc = html_parser.parse(html);
  final threads = <ThreadSummary>[];

  for (final tbody in doc.querySelectorAll('tbody')) {
    final id = tbody.id;
    if (!id.startsWith('normalthread_') && !id.startsWith('stickthread_')) {
      continue;
    }
    final sticky = id.startsWith('stickthread_');
    final tid = int.tryParse(id.split('_')[1]);
    if (tid == null) continue;

    final titleLink = tbody.querySelector('th a.xst');
    if (titleLink == null) continue;
    final title = titleLink.text.trim();
    if (title.isEmpty) continue;

    final typeA = tbody.querySelector('th > em > a');
    final typeName = typeA?.text.trim();

    final byCells = tbody.querySelectorAll('td.by');
    String author = '';
    DateTime? createdAt;
    String? lastUser;
    String? lastAt;
    if (byCells.isNotEmpty) {
      author = byCells[0].querySelector('cite a')?.text.trim() ?? '';
      createdAt = ChhUrls.parseTime(byCells[0].querySelector('em')?.text ?? '');
    }
    if (byCells.length > 1) {
      lastUser = byCells[1].querySelector('cite a')?.text.trim();
      lastAt = byCells[1].querySelector('em')?.text.trim();
    }

    final numCell = tbody.querySelector('td.num');
    final replies =
        int.tryParse(numCell?.querySelector('a')?.text.trim() ?? '') ?? 0;
    final views =
        int.tryParse(numCell?.querySelector('em')?.text.trim() ?? '') ?? 0;
    final hasImages = tbody.querySelector('i.fico-image') != null;

    threads.add(
      ThreadSummary(
        tid: tid,
        title: title,
        typeName: (typeName == null || typeName.isEmpty) ? null : typeName,
        author: author,
        createdAt: createdAt,
        replies: replies,
        views: views,
        lastPostUser: lastUser,
        lastPostTimeRaw: lastAt,
        hasImages: hasImages,
        sticky: sticky,
      ),
    );
  }

  return ThreadListPage(threads: threads, page: parsePagerOf(doc));
}

/// div.pgs → 当前页(strong)+ 是否有下一页(a.nxt);guide 解析器共用
PageInfo parsePagerOf(dom.Document doc) {
  dom.Element? pg;
  for (final p in doc.querySelectorAll('div.pgs')) {
    final inner = p.querySelector('div.pg');
    if (inner != null) {
      pg = inner;
      break;
    }
  }
  if (pg == null) return const PageInfo(current: 1, hasNext: false);
  final current =
      int.tryParse(pg.querySelector('strong')?.text.trim() ?? '') ?? 1;
  final hasNext = pg.querySelector('a.nxt') != null;
  return PageInfo(current: current, hasNext: hasNext);
}
