/// 论坛首页(forum.php)→ 分组版块列表
///
/// 结构(实测 CHH 模板):
/// <div class="bm bmw flg cl">
///   <div class="bm_h cl"><h2><a href="forum.php?gid=19">站务区</a></h2></div>
///   <div id="category_19" class="bm_c">
///     <table class="fl_tb"><tr><td class="fl_g">
///       <dt><a href="forum-324-1.html">举报专区</a></dt>
///       <dd><em>主题: 107</em>, <em>帖数: <span title="47444">4万</span></em></dd>
///       <dd><a href="...goto=lastpost">最后发表: 2026-10-23 08:48</a></dd>
///     </td></tr></table>
///   </div>
/// </div>
library;

import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';

List<ForumCategory> parseForumIndex(String html) {
  final doc = html_parser.parse(html);
  final categories = <ForumCategory>[];

  for (final bm in doc.querySelectorAll('div.bm')) {
    // The outer `div.fl.bm` wraps every category and owns no header/body.
    // Descendant queries would borrow the first category's children and parse
    // that category a second time. Match only blocks owned by this `.bm`.
    final headers = bm.children.where(
      (child) => child.classes.contains('bm_h'),
    );
    final bodies = bm.children.where((child) => child.classes.contains('bm_c'));
    if (headers.isEmpty || bodies.isEmpty) continue;
    final header = headers.first.querySelector('h2 a');
    final body = bodies.first;
    if (header == null) continue;
    final catName = header.text.trim();
    if (catName.isEmpty) continue;

    final forums = <Forum>[];
    for (final td in body.querySelectorAll('td.fl_g')) {
      // A nested real category keeps its own membership, even if names match.
      var owner = td.parent;
      while (owner != null && !owner.classes.contains('bm_c')) {
        owner = owner.parent;
      }
      if (!identical(owner, body)) continue;
      final link = td.querySelector('dt a[href]');
      if (link == null) continue;
      final fid = ChhUrls.fidFromUrl(link.attributes['href'] ?? '');
      final name = link.text.trim();
      if (fid == null || name.isEmpty) continue;

      int? threads, posts;
      for (final em in td.querySelectorAll('dd em')) {
        final t = em.text.trim();
        if (t.startsWith('主题')) {
          threads = ChhUrls.parseCount(t);
        } else if (t.startsWith('帖数')) {
          posts = ChhUrls.parseCount(
            t,
            title: em.querySelector('span')?.attributes['title'],
          );
        }
      }
      final lastPost = td
          .querySelector('dd a[href*="goto=lastpost"]')
          ?.text
          .replaceFirst(RegExp(r'^最后发表:?\s*'), '')
          .trim();

      forums.add(
        Forum(
          fid: fid,
          name: name,
          threadCount: threads,
          postCount: posts,
          lastPostTimeRaw: (lastPost == null || lastPost.isEmpty)
              ? null
              : lastPost,
        ),
      );
    }
    if (forums.isNotEmpty) {
      categories.add(ForumCategory(name: catName, forums: forums));
    }
  }
  return categories;
}
