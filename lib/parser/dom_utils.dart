/// 解析层公共工具:文本清洗、分页、表格、消息页判定
///
/// 所有新页面解析器共用这些函数,避免每个页面各写一套翻页与清洗逻辑。
library;

import 'package:html/dom.dart' as dom;

import '../core/chh_urls.dart';
import '../models/models.dart';

/// 压掉连续空白与不可见字符,Discuz 模板里到处是换行加缩进
String cleanText(String? raw) =>
    (raw ?? '').replaceAll(RegExp(r'[\s ]+'), ' ').trim();

/// 克隆后移除若干选择器,再取文本。用于私信预览剔掉操作区。
String textWithout(dom.Element? el, List<String> dropSelectors) {
  if (el == null) return '';
  final clone = el.clone(true);
  for (final sel in dropSelectors) {
    for (final n in clone.querySelectorAll(sel)) {
      n.remove();
    }
  }
  return cleanText(clone.text);
}

/// 标准分页器:div.pg 里 strong 是当前页,a.nxt 是下一页
///
/// 个人帖子页实测可能只有「下一页」而没有 strong,所以当前页允许回退到 [fallbackPage]。
PageInfo parsePager(dom.Document doc, {int fallbackPage = 1}) {
  final pg = doc.querySelector('div.pg');
  if (pg == null) {
    // 没有分页器不代表只有一页,autopbn 仍可能给出总页数
    final auto = doc.querySelector('a#autopbn');
    final cur = int.tryParse(auto?.attributes['curpage'] ?? '');
    final total = int.tryParse(auto?.attributes['totalpage'] ?? '');
    if (cur != null && total != null) {
      return PageInfo(current: cur, hasNext: cur < total);
    }
    return PageInfo(current: fallbackPage, hasNext: false);
  }
  final current =
      int.tryParse(cleanText(pg.querySelector('strong')?.text)) ?? fallbackPage;
  return PageInfo(current: current, hasNext: pg.querySelector('a.nxt') != null);
}

/// 下一页的完整地址:必须沿用站点生成的 href,它带着 uid/view/type/filter 等参数
String? nextPageUrl(dom.Document doc) {
  final nxt = doc.querySelector('div.pg a.nxt') ?? doc.querySelector('a.nxt');
  final href = nxt?.attributes['href'];
  if (href == null || href.isEmpty) return null;
  return ChhUrls.absolutize(href);
}

/// a#autopbn 自带 curpage/totalpage,免解析直接拿当前页与总页数
({int current, int total})? autoPageInfo(dom.Document doc) {
  final a = doc.querySelector('a#autopbn');
  final cur = int.tryParse(a?.attributes['curpage'] ?? '');
  final total = int.tryParse(a?.attributes['totalpage'] ?? '');
  if (cur == null || total == null) return null;
  return (current: cur, total: total);
}

/// 通用表格解析:按实际表头取列,不固定列序
///
/// 积分记录、用户组对比、社区权限矩阵共用。表头缺失时 headers 为空,
/// 由调用方决定怎么展示。
SiteTable parseTable(dom.Element? table) {
  if (table == null) return const SiteTable(headers: [], rows: []);

  final headers = <String>[];
  final headRow = table.querySelector('tr.th') ?? table.querySelector('tr');
  if (headRow != null) {
    for (final c in headRow.querySelectorAll('th, td')) {
      headers.add(cleanText(c.text));
    }
  }

  final rows = <List<String>>[];
  for (final tr in table.querySelectorAll('tr')) {
    if (tr == headRow) continue;
    final cells = tr.querySelectorAll('td, th');
    if (cells.isEmpty) continue;
    final row = cells.map((c) => cleanText(c.text)).toList();
    if (row.every((v) => v.isEmpty)) continue;
    rows.add(row);
  }

  return SiteTable(headers: headers, rows: rows);
}

/// 消息页判定与分流
///
/// 标题含「提示信息」或存在 #messagetext 只说明这是消息页,不能直接判为掉线。
/// 必须结合正文与 #messagelogin 分类(PAGE_SPEC §二.3)。
PageMessage? detectPageMessage(dom.Document doc) {
  final box = doc.querySelector('#messagetext');
  final title = cleanText(doc.querySelector('title')?.text);
  if (box == null && !title.contains('提示信息')) return null;

  final text = cleanText(box?.text ?? title);
  final hasLoginForm = doc.querySelector('#messagelogin') != null;

  if (hasLoginForm || text.contains('请先登录') || text.contains('登录后才能')) {
    return PageMessage(PageMessageKind.loginRequired, text);
  }
  if (text.contains('没有权限') || text.contains('阅读权限') || text.contains('权限不足')) {
    return PageMessage(PageMessageKind.permissionDenied, text);
  }
  if (text.contains('未定义操作') || text.contains('尚未开通')) {
    return PageMessage(PageMessageKind.featureUnavailable, text);
  }
  return PageMessage(PageMessageKind.message, text);
}

/// 消息页就抛出来,交给 UI 层按语义渲染状态视图
void throwIfMessagePage(dom.Document doc) {
  final m = detectPageMessage(doc);
  if (m != null) throw m;
}

/// 找出真正指向用户空间的链接
///
/// 站点的用户链接有伪静态(space-uid-N)与查询串(mod=space&uid=N)两种形态,
/// 而 touid= / authorid= 这类参数也含 "uid=",用 CSS 选择器区分不了,
/// 所以先取候选再用 [ChhUrls.uidFromUrl] 过滤。
({dom.Element el, String uid})? findUserLink(dom.Element? root) {
  if (root == null) return null;

  ({dom.Element el, String uid})? fallback;
  for (final a in root.querySelectorAll('a[href]')) {
    final uid = ChhUrls.uidFromUrl(a.attributes['href'] ?? '');
    if (uid == null) continue;
    // 同一个用户常有两个链接,前一个包着头像图片、没有文字。
    // 优先取带文字的那个,否则名字会解析成空串。
    if (a.text.trim().isNotEmpty) return (el: a, uid: uid);
    fallback ??= (el: a, uid: uid);
  }
  return fallback;
}

/// 登录态判定:标准页头 #um strong.vwmy a 是当前用户
String? currentUserName(dom.Document doc) {
  final a = doc.querySelector('#um strong.vwmy a');
  final name = cleanText(a?.text);
  return name.isEmpty ? null : name;
}
