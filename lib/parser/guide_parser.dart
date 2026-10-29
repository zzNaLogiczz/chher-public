/// 最新回复 guide(forum.php?mod=guide&view=new)→ 帖子列表
///
/// 结构(实测):与版块页同为 tbody#normalthread_XXX,但列语义不同:
///   th.common > a.xst = 标题
///   第一个 td.by = 所属版块(a href=forum-XX-1.html)
///   第二个 td.by = 作者(cite a)+ 时间(em)
///   td.num = 回复 / 查看
library;

import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'thread_list_parser.dart' show parsePagerOf;

ThreadListPage parseGuide(String html) {
  final doc = html_parser.parse(html);
  final threads = <ThreadSummary>[];

  for (final tbody in doc.querySelectorAll('tbody')) {
    final id = tbody.id;
    if (!id.startsWith('normalthread_')) continue;
    final tid = int.tryParse(id.split('_')[1]);
    if (tid == null) continue;

    final titleA = tbody.querySelector('th a.xst');
    if (titleA == null) continue;
    final title = titleA.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) continue;

    final byCells = tbody.querySelectorAll('td.by');
    String? forumName;
    int? forumFid;
    String author = '';
    DateTime? createdAt;
    if (byCells.isNotEmpty) {
      final fa = byCells[0].querySelector('a[href*="forum-"], a[href*="fid="]');
      forumName = fa?.text.trim();
      forumFid = fa == null
          ? null
          : ChhUrls.fidFromUrl(fa.attributes['href'] ?? '');
    }
    if (byCells.length > 1) {
      author = byCells[1].querySelector('cite a')?.text.trim() ?? '';
      createdAt = ChhUrls.parseTime(byCells[1].querySelector('em')?.text ?? '');
    }

    final numCell = tbody.querySelector('td.num');
    final replies =
        int.tryParse(numCell?.querySelector('a')?.text.trim() ?? '') ?? 0;
    final views =
        int.tryParse(numCell?.querySelector('em')?.text.trim() ?? '') ?? 0;

    threads.add(
      ThreadSummary(
        tid: tid,
        title: title,
        author: author,
        createdAt: createdAt,
        replies: replies,
        views: views,
        forumName: (forumName == null || forumName.isEmpty) ? null : forumName,
        forumFid: forumFid,
      ),
    );
  }

  return ThreadListPage(threads: threads, page: parsePagerOf(doc));
}
