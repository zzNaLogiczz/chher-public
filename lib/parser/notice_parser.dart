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
  final title = body == null
      ? ''
      : _threadLinks(body)
                .map((link) => cleanText(link.text))
                .where((text) => text.isNotEmpty && text != '查看')
                .firstOrNull ??
            '';
  final category = filterCategory ?? _categoryFromIgnoreLink(dl) ?? 'unknown';
  var action = _actionOf(body);
  final score = category == 'rate' ? _scoreOf(body, action) : null;
  if (category == 'rate') action = _ratingAction(action, score);

  return Notice(
    id: id,
    // 优先用当前筛选参数;取不到时从屏蔽链接的 type 参数补,再不行记 unknown
    category: category,
    actor: cleanText(actor?.el.text).isEmpty ? null : cleanText(actor?.el.text),
    actorUid: actor?.uid,
    avatarUrl: _avatarOf(dl),
    occurredAtText: cleanText(dl.querySelector('dt span.xg1')?.text),
    summary: summary,
    title: title.isEmpty ? null : title,
    action: action,
    score: score,
    unread: _isNew(dl, body),
    targetUrl: target?.url,
    tid: target?.tid,
    pid: target?.pid,
  );
}

String _actionOf(dom.Element? body) {
  if (body == null) return '';
  final actor = findUserLink(body);
  final clone = _actionBody(body);
  var action = cleanText(clone.text)
      .replaceFirst(RegExp(r'\s*查看[。.!！]?\s*$'), '')
      .replaceAll(RegExp(r'《\s*》|“\s*”|「\s*」|【\s*】'), '')
      .trim();
  if (actor == null) action = action.replaceFirst(RegExp(r'^系统\s*'), '');
  // 标题移入引用块后，只整理句首的模板语法，保留后面的理由原文。
  action = action
      .replaceFirstMapped(
        RegExp(r'^(?:您|你)\s*在主题\s*的帖子被\s*(评分|点评|回复)(?:了)?\s*'),
        (m) => '${m[1]}了您的帖子 ',
      )
      .replaceFirstMapped(
        RegExp(r'^(回复|点评)了?\s*(?:您|你)\s*在主题\s*的帖子\s*'),
        (m) => '${m[1]}了您的帖子 ',
      )
      .replaceFirstMapped(RegExp(r'^在主题\s*的(帖子|回复)\s*中\s*'), (m) => '在${m[1]}中')
      .replaceFirst(RegExp(r'^在主题\s*中\s*'), '在主题中');
  return cleanText(action);
}

String _ratingAction(String action, String? score) {
  const verb = '评分了您的帖子';
  action = action.replaceFirst(
    RegExp(r'^(?:给|对)(?:您|你)的(?:主题|帖子|回复)\s*评分\s*'),
    '$verb ',
  );
  if (!action.startsWith(verb)) return action;
  final detail = action.substring(verb.length).trim();
  if (detail.isEmpty) return verb;
  if (score == null || !detail.startsWith(score)) return '$verb　$detail';
  final reason = detail.substring(score.length).trim();
  return [verb, score, if (reason.isNotEmpty) reason].join('　');
}

String? _scoreOf(dom.Element? body, String action) {
  final amount = RegExp(r'[+\-−]\s*\d+(?:\.\d+)?');
  final clone = body == null ? null : _actionBody(body);
  for (final el in clone?.querySelectorAll('.xi1, .xi2') ?? <dom.Element>[]) {
    final text = cleanText(el.text);
    final match = amount.firstMatch(text);
    if (match != null) return text.substring(0, match.end).trim();
  }
  return RegExp(
    r'(?:(?:积分|威望|金钱|贡献|激情|邪恶|体力|人气|金币)(?:指数)?)?\s*[+\-−]\s*\d+(?:\.\d+)?',
  ).firstMatch(action)?.group(0)?.trim();
}

Iterable<dom.Element> _threadLinks(dom.Element body) => body
    .querySelectorAll('a[href]')
    .where(
      (a) => RegExp(
        r'goto=findpost|[?&](?:p?tid)=\d+|thread-\d+',
      ).hasMatch(a.attributes['href']!),
    );

dom.Element _actionBody(dom.Element body) {
  final clone = body.clone(true);
  findUserLink(clone)?.el.remove();
  for (final link in _threadLinks(clone).toList()) {
    link.remove();
  }
  for (final link in clone.querySelectorAll('a.lit')) {
    if (cleanText(link.text) == '查看') link.remove();
  }
  return clone;
}

bool _isNew(dom.Element dl, dom.Element? body) {
  bool bold(dom.Element el) =>
      el.classes.contains('xw1') ||
      el.localName == 'b' ||
      el.localName == 'strong' ||
      RegExp(
        r'font-weight\s*:\s*(bold|[6-9]00)\b',
        caseSensitive: false,
      ).hasMatch(el.attributes['style'] ?? '');
  if (bold(dl)) return true;
  if (body == null) return false;
  if (bold(body)) return true;
  // 只认覆盖整段事件的加粗，评分或标题的局部强调不代表未读。
  return body
      .querySelectorAll('b, strong, .xw1, [style]')
      .any((el) => bold(el) && cleanText(el.text) == cleanText(body.text));
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

/// 内容目标优先带 pid 的帖子链接；a.lit 可能只是「查看」。
///
/// 同一事件的标题链接与查看链接不能拆成两条提醒;pid 为空时不能补造。
({String url, int? tid, int? pid})? _targetOf(dom.Element? body) {
  if (body == null) return null;

  final candidates = {..._threadLinks(body), ...body.querySelectorAll('a.lit')};
  ({String url, int? tid, int? pid})? fallback;

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
    final target = (url: ChhUrls.absolutize(href), tid: tid, pid: pid);
    if (pid != null) return target;
    fallback ??= target;
  }
  return fallback;
}
