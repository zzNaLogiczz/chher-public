/// 用户主页、收藏、个人帖子(PAGE_SPEC §6.2、§6.5)
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

/// 用户主页:.u_profile 资料、#pbbs 论坛统计、#psts 帖子统计
///
/// 自己的页头与操作项不保证与他人空间相同,所以字段按页面实际存在性收集。
UserProfile parseUserProfile(String html, {required String uid}) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final name = cleanText(doc.querySelector('h2.mbn, #uhd h2')?.text);
  final avatar = doc.querySelector('.avt img, #uhd img')?.attributes['src'];

  return UserProfile(
    uid: uid,
    name: name.isEmpty ? '用户 $uid' : name,
    avatarUrl: (avatar == null || avatar.isEmpty)
        ? null
        : ChhUrls.absolutize(avatar),
    profile: _definitionPairs(doc.querySelector('.u_profile')),
    stats: {
      ..._definitionPairs(doc.querySelector('#psts')),
      ..._definitionPairs(doc.querySelector('#pbbs')),
    },
  );
}

/// Discuz 资料区是 li > em(标签) + 值 的结构,按实际字段收集,不补造
Map<String, String> _definitionPairs(dom.Element? root) {
  if (root == null) return const {};
  final out = <String, String>{};
  for (final li in root.querySelectorAll('li')) {
    final label = cleanText(li.querySelector('em')?.text).replaceAll(':', '');
    if (label.isEmpty) continue;
    final value = textWithout(li, ['em']);
    if (value.isNotEmpty) out[label] = value;
  }
  return out;
}

/// 收藏(实测 2026-10-25)
///
/// ```
/// li#fav_{favid}.bbda
///   a#a_delete_{favid}.y  href=…ac=favorite&op=delete…  "删除"
///   input.pc
///   span > img.t
///   a  href=thread-2816863-1-1.html   标题
///   span.xg1  "2026-6-11 11:58"
/// ```
///
/// favid 不等于内容 tid/fid/aid。取标题要跳过删除链接 ——
/// 它排在内容链接**前面**,直接取第一个 a 会把「删除」当成标题。
Paged<FavoriteItem> parseFavorites(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final items = <FavoriteItem>[];
  for (final li in doc.querySelectorAll('#favorite_ul > li[id^="fav_"]')) {
    final favid = li.id.replaceFirst('fav_', '');
    final a = _contentLink(li);
    final href = a?.attributes['href'] ?? '';
    final title = cleanText(a?.text);
    if (favid.isEmpty || href.isEmpty || title.isEmpty) continue;

    final url = ChhUrls.absolutize(href);
    items.add(
      FavoriteItem(
        favid: favid,
        title: title,
        url: url,
        timeRaw: cleanText(li.querySelector('span.xg1')?.text),
        tid: ChhUrls.tidFromUrl(url),
        fid: ChhUrls.fidFromUrl(url),
        portalKind: url.contains('article-') || url.contains('aid=')
            ? PortalItemKind.article
            : PortalItemKind.thread,
      ),
    );
  }

  return Paged(items: items, page: parsePager(doc), nextUrl: nextPageUrl(doc));
}

/// 收藏项里真正指向内容的链接
///
/// 排除收藏管理动作(删除、编辑淘帖),剩下第一个有文字的就是内容。
dom.Element? _contentLink(dom.Element li) {
  for (final a in li.querySelectorAll('a[href]')) {
    if (a.id.startsWith('a_delete_')) continue;
    final href = a.attributes['href'] ?? '';
    if (href.contains('ac=favorite') || href.contains('op=delete')) continue;
    if (cleanText(a.text).isEmpty) continue;
    return a;
  }
  return null;
}

/// 个人帖子页(我的主题 / 我的回复 / 好友的帖子)
///
/// 关键差异:#delform 下是裸表格,**不是** tbody#normalthread_*,标题链接也没有 .xst。
/// 回复视图里主题行后面跟着若干 td.xg1[colspan] 的回复摘要行,一帖可有多个 pid。
Paged<MyThread> parseMyThreads(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  // 主题行与摘要行是兄弟关系,先顺序扫描成「主题 + 它后面的摘要」再归组
  final groups = <(MyThread, List<MyReplySnippet>)>[];

  for (final tr in doc.querySelectorAll('#delform table tr')) {
    if (tr.className.contains('th')) continue;

    final snippetCell = tr.querySelector('td.xg1[colspan]');
    if (snippetCell != null) {
      if (groups.isEmpty) continue;
      final s = _replySnippet(snippetCell);
      if (s != null) groups.last.$2.add(s);
      continue;
    }

    final row = _threadRow(tr);
    if (row != null) groups.add((row, <MyReplySnippet>[]));
  }

  final items = groups.map((g) {
    final (base, snippets) = g;
    if (snippets.isEmpty) return base;
    return MyThread(
      tid: base.tid,
      title: base.title,
      forumName: base.forumName,
      forumFid: base.forumFid,
      replies: base.replies,
      views: base.views,
      lastUser: base.lastUser,
      lastTimeRaw: base.lastTimeRaw,
      replySnippets: snippets,
    );
  }).toList();

  return Paged(items: items, page: parsePager(doc), nextUrl: nextPageUrl(doc));
}

/// 主题行:带 th > a 的记录行。tid 从伪静态、tid 或 ptid 参数提取。
MyThread? _threadRow(dom.Element tr) {
  final a = tr.querySelector('th > a');
  final href = a?.attributes['href'] ?? '';
  final title = cleanText(a?.text);
  if (title.isEmpty || href.isEmpty) return null;

  final tid =
      ChhUrls.tidFromUrl(href) ??
      int.tryParse(RegExp(r'[?&]ptid=(\d+)').firstMatch(href)?.group(1) ?? '');
  if (tid == null) return null;

  final forumA = tr.querySelector('a[href*="forum-"], a[href*="fid="]');
  final num = tr.querySelector('td.num');
  // 唯一的 td.by 是最后回复者,不是主题作者
  final by = tr.querySelector('td.by');

  return MyThread(
    tid: tid,
    title: title,
    forumName: cleanText(forumA?.text).isEmpty ? null : cleanText(forumA?.text),
    forumFid: ChhUrls.fidFromUrl(forumA?.attributes['href'] ?? ''),
    replies: int.tryParse(cleanText(num?.querySelector('a')?.text)),
    views: int.tryParse(cleanText(num?.querySelector('em')?.text)),
    lastUser: cleanText(by?.querySelector('cite a')?.text).isEmpty
        ? null
        : cleanText(by?.querySelector('cite a')?.text),
    lastTimeRaw: cleanText(by?.querySelector('em a, em')?.text),
  );
}

/// 回复摘要行:定位楼层必须用摘要行里的非空 pid,主题行的 pid 实测可能为空
MyReplySnippet? _replySnippet(dom.Element cell) {
  final a = cell.querySelector('a[href*="goto=findpost"]');
  final href = a?.attributes['href'] ?? '';
  final pid = int.tryParse(
    RegExp(r'[?&]pid=(\d+)').firstMatch(href)?.group(1) ?? '',
  );
  if (pid == null) return null;

  return MyReplySnippet(
    pid: pid,
    text: cleanText(cell.text),
    targetUrl: ChhUrls.absolutize(href),
  );
}
