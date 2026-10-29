/// 帖子详情(thread-{tid}-1-1.html)→ 楼层列表
///
/// 结构示例(虚构标识):
/// <div id="post_1001">
///   <table id="pid1001" summary="pid1001">
///     <td class="t_f" id="postmessage_1001">…正文…</td>
///   </table>
/// </div>
/// 作者:<div class="pi"> … <strong><a href="space-uid-1001.html" class="xi2">示例作者</a></strong>
/// 头像:<div class="avatar"><a class="avtm"><img src="./data/avatar/..."></div>
/// 时间:<em id="authorposton1001">发表于 2026-01-01 12:00</em>
/// 楼层:<a id="postnum1001">N#</a>(文本可能为空或"沙发",回退用序号)
/// 说明:<i class="pstatus">本帖最后由 … 编辑</i> / 补充内容
/// 评分:<dl id="ratelog_{pid}" class="rate"> → table.ratl 表头汇总 + tbody.ratl_l 明细
/// 点评:<div id="comment_{pid}" class="cm">(本地样本为空,按条目含用户链接容错解析)
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'content_walker.dart';
import 'dom_utils.dart';

ThreadDetail parseThread(
  String html, {
  required int tid,
  int fallbackPage = 1,
}) {
  final doc = html_parser.parse(html);

  final title =
      (doc.getElementById('thread_subject')?.text.trim().isNotEmpty ?? false)
      ? doc.getElementById('thread_subject')!.text.trim()
      : _titleFromHead(doc);

  final posts = <Post>[];
  final tables = doc.querySelectorAll('table[id]');
  final seen = <int>{};
  for (final table in tables) {
    final pid = int.tryParse((table.id).replaceFirst(RegExp(r'^pid'), ''));
    if (pid == null || !table.id.startsWith('pid') || !seen.add(pid)) continue;

    final authorLink =
        table.querySelector('.authi strong a') ??
        table.querySelectorAll('a[href*="space-uid"]').firstOrNull;
    final author = authorLink?.text.trim() ?? '';
    if (author.isEmpty) continue; // 楼层被删除/隐藏时没有作者,跳过

    final authorUid = ChhUrls.uidFromUrl(authorLink?.attributes['href'] ?? '');

    final avatarRaw = table.querySelector('div.avatar img')?.attributes['src'];
    final avatarUrl = avatarRaw == null ? null : ChhUrls.absolutize(avatarRaw);

    final timeRaw =
        table
            .querySelector('em[id^="authorposton"]')
            ?.text
            .replaceFirst(RegExp(r'^发表于\s*'), '')
            .trim() ??
        '';

    final floorLabel = (table.querySelector('a[id^="postnum"]')?.text ?? '')
        .replaceAll(RegExp(r'\s+'), '');
    final parsedFloor = floorLabel == '楼主'
        ? 1
        : int.tryParse(
            RegExp(
                  r'^(?:第)?([1-9]\d*)(?:#|楼)?$',
                ).firstMatch(floorLabel)?.group(1) ??
                '',
          );
    final floorIsKnown = parsedFloor != null && parsedFloor > 0;
    final floor = floorIsKnown ? parsedFloor : posts.length + 1;

    final message = table.querySelector('td[id^="postmessage_"]');

    posts.add(
      Post(
        pid: pid,
        floor: floor,
        floorIsKnown: floorIsKnown,
        author: author,
        authorUid: authorUid,
        avatarUrl: avatarUrl,
        timeRaw: timeRaw,
        time: ChhUrls.parseTime(timeRaw),
        content: message == null
            ? const []
            : parseContentBlocks(message, threadId: tid),
        notes: _notesIn(message),
        // 评分与点评挂在楼层容器上,不在正文单元格里
        rating: _ratingOf(doc, pid),
        comments: _commentsOf(doc, pid),
      ),
    );
  }

  return ThreadDetail(
    tid: tid,
    fid: _forumId(doc, tid),
    forumName: _forumName(doc),
    title: title,
    posts: posts,
    page: parsePager(doc, fallbackPage: fallbackPage),
  );
}

/// 回复表单比导航更具体：必须是当前帖子的 reply action，避免误取正文
/// 里其他版块或其他帖子的链接。游客页没有可用表单时再读面包屑。
int? _forumId(dom.Document doc, int tid) {
  final base = Uri.parse(ChhUrls.base);
  for (final form in doc.querySelectorAll(
    '#fastpostform[action], #postform[action]',
  )) {
    final action = Uri.tryParse(form.attributes['action'] ?? '');
    if (action == null) continue;
    final url = base.resolveUri(action);
    final query = url.queryParameters;
    if (url.host != base.host ||
        !url.path.endsWith('/forum.php') ||
        query['mod'] != 'post' ||
        query['action'] != 'reply' ||
        int.tryParse(query['tid'] ?? '') != tid) {
      continue;
    }
    final fid = int.tryParse(query['fid'] ?? '');
    if (fid != null && fid > 0) return fid;
  }

  // 嵌套版块取最深的一项；只看站点导航，不扫描用户发布的正文。
  for (final link in doc.querySelectorAll('#pt a[href]').reversed) {
    final href = Uri.tryParse(link.attributes['href'] ?? '');
    if (href == null) continue;
    final url = base.resolveUri(href);
    if (url.host != base.host) continue;
    final isForum =
        RegExp(r'/forum-\d+-\d+\.html$').hasMatch(url.path) ||
        (url.path.endsWith('/forum.php') &&
            url.queryParameters['mod'] == 'forumdisplay');
    if (!isForum) continue;
    final fid = ChhUrls.fidFromUrl(url.toString());
    if (fid != null && fid > 0) return fid;
  }
  return null;
}

/// 面包屑里最深的版块链接文字:嵌套版块显示子版块,不显示分区
String? _forumName(dom.Document doc) {
  for (final link in doc.querySelectorAll('#pt a[href]').reversed) {
    final href = link.attributes['href'] ?? '';
    if (!RegExp(r'(^|/)forum-\d+-\d+\.html$').hasMatch(href) &&
        !(href.contains('mod=forumdisplay') && href.contains('fid='))) {
      continue;
    }
    final name = cleanText(link.text);
    if (name.isNotEmpty) return name;
  }
  return null;
}

/// 说明块:同一个 i.pstatus 承载编辑说明与补充内容,按文案区分
List<PostNote> _notesIn(dom.Element? message) {
  if (message == null) return const [];
  final out = <PostNote>[];
  for (final el in message.querySelectorAll('.pstatus')) {
    final text = el.text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();
    if (text.isEmpty) continue;
    out.add(
      PostNote(
        text.startsWith('补充内容') ? PostNoteKind.supplement : PostNoteKind.edited,
        text,
      ),
    );
  }
  return out;
}

/// 评分:表头是汇总项,tbody.ratl_l 每行一条明细
PostRating? _ratingOf(dom.Document doc, int pid) {
  final box = doc.querySelector('#ratelog_$pid');
  if (box == null) return null;

  final summary = <String>[];
  for (final th in box.querySelectorAll('table.ratl th')) {
    final text = th.text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();
    // 「收起 理由」是操作列,不是汇总
    if (text.isEmpty || text.contains('收起') || text == '理由') continue;
    summary.add(text);
  }

  final entries = <RatingEntry>[];
  for (final tr in box.querySelectorAll('tbody.ratl_l tr')) {
    final cells = tr.querySelectorAll('td');
    if (cells.length < 2) continue;
    // 这一格里有两个指向同一用户的链接,第一个包的是头像图片、没有文字,
    // 直接取 querySelector 会得到空名字
    final link =
        cells[0]
            .querySelectorAll('a[href*="space-uid"]')
            .where((a) => a.text.trim().isNotEmpty)
            .firstOrNull ??
        cells[0].querySelector('a[href*="space-uid"]');
    final user = link?.text.trim().isNotEmpty == true
        ? link!.text.trim()
        : cells[0].text.trim();
    if (user.isEmpty) continue;
    entries.add(
      RatingEntry(
        user: user,
        uid: ChhUrls.uidFromUrl(link?.attributes['href'] ?? ''),
        // 分值保留站点原文,不自行解析正负与单位
        score: cells[1].text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        reason: cells.length > 2
            ? cells[2].text.replaceAll(RegExp(r'\s+'), ' ').trim()
            : null,
      ),
    );
  }

  final rating = PostRating(summary: summary, entries: entries);
  return rating.isEmpty ? null : rating;
}

/// 点评
///
/// 本地样本里这个容器是空的,所以按「条目含用户链接」容错解析,
/// 不对具体 class 名做硬假设。
List<PostComment> _commentsOf(dom.Document doc, int pid) {
  final box = doc.querySelector('#comment_$pid');
  if (box == null) return const [];

  final out = <PostComment>[];
  for (final item in box.children) {
    final link = item.querySelector('a[href*="space-uid"], a[href*="uid="]');
    if (link == null) continue;

    final time = item.querySelectorAll('.xg1').lastOrNull;
    final clone = item.clone(true);
    for (final drop in clone.querySelectorAll(
      'a[href*="space-uid"], a[href*="uid="], .xg1',
    )) {
      drop.remove();
    }
    final text = clone.text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();
    if (text.isEmpty) continue;

    out.add(
      PostComment(
        author: link.text.trim(),
        uid: ChhUrls.uidFromUrl(link.attributes['href'] ?? ''),
        text: text,
        timeRaw: time?.text.trim(),
      ),
    );
  }
  return out;
}

String _titleFromHead(dom.Document doc) {
  final t = doc.head?.querySelector('title')?.text ?? '';
  // "标题 - Chiphell - 分享与交流用户体验"
  final i = t.indexOf(' - Chiphell');
  return (i > 0 ? t.substring(0, i) : t).trim();
}
