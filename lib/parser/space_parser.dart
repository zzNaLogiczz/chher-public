/// 用户主页、收藏、个人帖子(PAGE_SPEC §6.2、§6.5)
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

/// 用户主页:按源站字段解析,缺少或隐藏的资料保持为空。
UserProfile parseUserProfile(String html, {required String uid}) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final root = doc.querySelector('.u_profile');
  final heading =
      root?.querySelector('h2.mbn') ?? doc.querySelector('#uhd h2, h2.mbn');
  final name = heading == null ? '' : textWithout(heading, ['.xw0']);
  final profile = _definitionPairs(root);
  final stats = {
    ..._definitionPairs(doc.querySelector('#psts')),
    ..._definitionPairs(doc.querySelector('#pbbs')),
  };
  final fields = {...profile, ...stats};

  dom.Element? activity;
  for (final title in root?.querySelectorAll('h2') ?? <dom.Element>[]) {
    if (cleanText(title.text) == '活跃概况') {
      activity = title.parent;
      break;
    }
  }
  dom.Element? groupRow;
  for (final li in activity?.querySelectorAll('li') ?? <dom.Element>[]) {
    if (cleanText(li.querySelector('em')?.text) == '用户组') {
      groupRow = li;
      break;
    }
  }
  final groupLink = groupRow?.querySelector('a');
  final group = cleanText(groupLink?.text);
  final groupId = int.tryParse(
    Uri.tryParse(groupLink?.attributes['href'] ?? '')?.queryParameters['gid'] ??
        '',
  );
  final tip = groupRow?.querySelector('[tip]')?.attributes['tip'];
  final nextLevel = RegExp(r'距离下一级还需\s*([\d,\s]+)\s*积分').firstMatch(tip ?? '');

  final counts = <String, int>{};
  for (final li in root?.querySelectorAll('li') ?? <dom.Element>[]) {
    if (cleanText(li.querySelector('em')?.text) != '统计信息') continue;
    for (final link in li.querySelectorAll('a')) {
      final text = cleanText(link.text);
      for (final prefix in ['好友数', '回帖数', '主题数']) {
        if (!text.startsWith(prefix)) continue;
        final count = _profileNumber(text.substring(prefix.length));
        if (count != null) counts[prefix] = count;
      }
    }
  }

  return UserProfile(
    uid: uid,
    name: name.isEmpty ? '用户 $uid' : name,
    avatarUrl: ChhUrls.avatar(uid, size: 'big'),
    group: group.isEmpty ? null : group,
    groupId: groupId != null && groupId > 0 ? groupId : null,
    nextLevelCredits: _profileNumber(nextLevel?.group(1)),
    onlineHours: _profileNumber(fields['在线时间']),
    credits: _profileNumber(fields['积分']),
    evil: _profileNumber(fields['邪恶指数']),
    threads: counts['主题数'],
    replies: counts['回帖数'],
    friends: counts['好友数'],
    registeredAt: fields['注册时间'],
    lastVisitAt: fields['最后访问'],
    lastPostAt: fields['上次发表时间'],
    portalArticles: _profileNumber(fields['门户文章']),
    profile: profile,
    stats: stats,
  );
}

/// 只取目标用户组,缺资料或遇到登录/消息页时不给字典写入未知值。
({String name, int lowerCredits})? parseUserGroupLevel(String html) {
  try {
    final doc = html_parser.parse(html);
    throwIfMessagePage(doc);
    if (doc.querySelector('#loginform, form[action*="logging"]') != null) {
      return null;
    }
    final heading = cleanText(doc.querySelector('#tba li#c2')?.text);
    final name = heading.replaceFirst(RegExp(r'^晋级用户组\s*-\s*'), '').trim();
    if (name.isEmpty) return null;
    final pattern = RegExp(r'积分下限\s*(-?\d+)');
    RegExpMatch? match;
    for (final notice in doc.querySelectorAll('.tscr span.notice')) {
      match = pattern.firstMatch(cleanText(notice.text));
      if (match != null) break;
    }
    match ??= pattern.firstMatch(cleanText(doc.body?.text));
    final lowerCredits = int.tryParse(match?.group(1) ?? '');
    return lowerCredits == null
        ? null
        : (name: name, lowerCredits: lowerCredits);
  } catch (_) {
    return null;
  }
}

/// 站点数字可能带千分位、空白和单位,不把未知文本补成零。
int? _profileNumber(String? value) {
  final number = RegExp(r'^\s*(\d[\d,\s]*)').firstMatch(value ?? '');
  return int.tryParse(number?.group(1)?.replaceAll(RegExp(r'[,\s]'), '') ?? '');
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
    final fallback = FavoriteItem(favid: favid, title: title, url: url);
    final type = switch (li.querySelector('img.t')?.attributes['alt']) {
      'thread' => FavoriteType.thread,
      'forum' => FavoriteType.forum,
      'article' => FavoriteType.article,
      _ => fallback.type,
    };
    final vid = int.tryParse(
      li.querySelector('input[vid]')?.attributes['vid'] ?? '',
    );
    final targetId = vid != null && vid > 0 ? vid : fallback.targetId;
    items.add(
      FavoriteItem(
        favid: favid,
        title: title,
        url: url,
        timeRaw: cleanText(li.querySelector('span.xg1')?.text),
        type: type,
        targetId: targetId,
        tid: type == FavoriteType.thread ? targetId : null,
        fid: type == FavoriteType.forum ? targetId : null,
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
