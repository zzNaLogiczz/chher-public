/// 提醒(home.php?mod=space&do=notice)(PAGE_SPEC §6.3)
///
/// 统一解析器,覆盖 view=all / mypost / interactive / system / app:
///   dl[id^="notice_"]        条目,id 后缀是 noticeId(不能用 tid 当主键)
///   dt span.xg1              时间(不能直接取整个 dt,里面还有「屏蔽」操作)
///   dd.ntc_body              事件内容,它是事件描述,不保证含完整回复正文
///   dd.avt img               头像
/// 提醒列表本身已有事件内容,不需要先打开帖子。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

Paged<Notice> parseNotices(String html, {String? filterCategory}) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final items = <Notice>[];
  for (final dl in doc.querySelectorAll('dl[id^="notice_"]')) {
    final notice = _parseOne(dl, filterCategory);
    if (notice != null) items.add(notice);
  }

  return Paged(items: items, page: parsePager(doc), nextUrl: nextPageUrl(doc));
}

Notice? _parseOne(dom.Element dl, String? filterCategory) {
  final id = dl.id.replaceFirst('notice_', '');
  if (id.isEmpty) return null;

  final body = dl.querySelector('dd.ntc_body');
  final summary = cleanText(body?.text);
  // 事件内容为空的条目没有展示价值,直接丢弃
  if (summary.isEmpty) return null;

  final actor = findUserLink(body);
  final target = _targetOf(body);

  return Notice(
    id: id,
    // 优先用当前筛选参数;取不到时从屏蔽链接的 type 参数补,再不行记 unknown
    category: filterCategory ?? _categoryFromIgnoreLink(dl) ?? 'unknown',
    actor: cleanText(actor?.el.text).isEmpty ? null : cleanText(actor?.el.text),
    actorUid: actor?.uid,
    avatarUrl: _avatarOf(dl),
    occurredAtText: cleanText(dl.querySelector('dt span.xg1')?.text),
    summary: summary,
    targetUrl: target?.url,
    tid: target?.tid,
    pid: target?.pid,
  );
}

/// 屏蔽动作入口的 type 参数可以反推提醒类型。只读 href,不调用它。
String? _categoryFromIgnoreLink(dom.Element dl) {
  final a = dl.querySelector('dt a[href*="ac=common"][href*="op=ignore"]');
  final href = a?.attributes['href'];
  if (href == null) return null;
  return RegExp(r'[?&]type=([a-zA-Z]+)').firstMatch(href)?.group(1);
}

String? _avatarOf(dom.Element dl) {
  final src = dl.querySelector('dd.avt img')?.attributes['src'];
  if (src == null || src.isEmpty) return null;
  return ChhUrls.absolutize(src);
}

/// 内容目标:优先 .ntc_body a.lit,否则取带非空 pid 的 goto=findpost 链接
///
/// 同一事件的标题链接与查看链接不能拆成两条提醒;pid 为空时不能补造。
({String url, int? tid, int? pid})? _targetOf(dom.Element? body) {
  if (body == null) return null;

  final candidates = <dom.Element>[
    ...body.querySelectorAll('a.lit'),
    ...body.querySelectorAll('a[href*="goto=findpost"]'),
    ...body.querySelectorAll('a[href*="thread-"], a[href*="tid="]'),
  ];

  for (final a in candidates) {
    final href = a.attributes['href'] ?? '';
    if (href.isEmpty) continue;
    final pid = int.tryParse(
      RegExp(r'[?&]pid=(\d+)').firstMatch(href)?.group(1) ?? '',
    );
    final tid =
        int.tryParse(
          RegExp(r'[?&]ptid=(\d+)').firstMatch(href)?.group(1) ?? '',
        ) ??
        ChhUrls.tidFromUrl(href);
    // goto=findpost 必须有非空 pid 才能定位楼层
    if (href.contains('goto=findpost') && pid == null) continue;
    return (url: ChhUrls.absolutize(href), tid: tid, pid: pid);
  }
  return null;
}
