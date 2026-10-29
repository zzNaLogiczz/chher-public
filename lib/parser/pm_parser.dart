/// 私信与公共消息(PAGE_SPEC §6.4)
///
/// 列表入口是 home.php?mod=space&do=pm,不是 spacecp&do=pm。
///   私人消息列表  #deletepmform dl[id^="pmlist_"]   后缀对应 plid(会话)
///   公共消息列表  dl[id^="gpmlist_"]
///   会话详情      #pm_ul dl[id^="pmlist_"]          后缀对应 pmid(单条消息)
/// 两个 ID 不可混用,按 subop 分派。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

/// 会话列表:私人消息与公共消息走同一结构,只是容器 id 前缀不同
Paged<PmConversation> parsePmList(
  String html, {
  PmFilter filter = PmFilter.privatePm,
}) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final prefix = filter == PmFilter.privatePm ? 'pmlist_' : 'gpmlist_';
  final items = <PmConversation>[];

  for (final dl in doc.querySelectorAll('dl[id^="$prefix"]')) {
    final conv = _parseConversation(dl, prefix);
    if (conv != null) items.add(conv);
  }

  return Paged(items: items, page: parsePager(doc), nextUrl: nextPageUrl(doc));
}

PmConversation? _parseConversation(dom.Element dl, String prefix) {
  final id = dl.id.replaceFirst(prefix, '');
  if (id.isEmpty) return null;

  // 详情地址照用站点生成的 href,不自己拼 touid / pmid
  final link =
      dl.querySelector('a[href*="subop=view"], a[href*="subop=viewg"]') ??
      dl.querySelector('a[href*="do=pm"]');
  final href = link?.attributes['href'];
  if (href == null || href.isEmpty) return null;

  final peer = findUserLink(dl);
  // 摘要区混着按钮、计数、对方、预览与时间,先剔掉操作区再取预览
  final preview = textWithout(dl.querySelector('.pm_c'), [
    '.o',
    '.pm_o',
    '.y',
    'em',
  ]);

  return PmConversation(
    id: id,
    peer: cleanText(peer?.el.text).isEmpty
        ? cleanText(link?.text)
        : cleanText(peer?.el.text),
    peerUid: peer?.uid,
    avatarUrl: _avatarOf(dl),
    preview: preview,
    timeRaw: cleanText(dl.querySelector('.pm_c em, span.xg1, em')?.text),
    viewUrl: ChhUrls.absolutize(href),
  );
}

/// 会话详情:正文混在 dd.ptm 的文本节点里,不在论坛的 td#postmessage_*
///
/// 需要先分离发送人与时间,再清洗剩余内容;自身与对方靠作者 UID 区分,不靠左右样式猜。
List<PmMessage> parsePmThread(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final out = <PmMessage>[];
  final root = doc.querySelector('#pm_ul');
  if (root == null) return out;

  for (final dl in root.querySelectorAll('dl[id^="pmlist_"]')) {
    final ptm = dl.querySelector('dd.ptm');
    if (ptm == null) continue;

    // 自己发的消息只有 span.xw1"您",没有作者链接(实测 2026-10-27);
    // 先认这个标记,否则正文里的主页链接会被当成作者
    final mark = ptm.querySelector('span.xw1');
    final selfMark = cleanText(mark?.text) == '您' ? mark : null;
    final found = selfMark == null ? findUserLink(ptm) : null;
    final authorA = selfMark == null
        ? ptm.querySelector('a.xw1') ?? found?.el
        : null;
    final body = textWithout(ptm, [
      'a.xw1',
      'span.xw1',
      'span.xg1',
      '.o',
      '.y',
    ]);
    if (body.isEmpty) continue;
    // 头像栏的主页链接对双方都存在,作者链接缺失时用它补 UID
    final avatarHref = dl.querySelector('dd.avt a')?.attributes['href'] ?? '';

    out.add(
      PmMessage(
        pmid: dl.id.replaceFirst('pmlist_', ''),
        author: cleanText((authorA ?? selfMark)?.text),
        authorUid:
            ChhUrls.uidFromUrl(authorA?.attributes['href'] ?? '') ??
            found?.uid ??
            ChhUrls.uidFromUrl(avatarHref),
        timeRaw: cleanText(ptm.querySelector('span.xg1')?.text),
        text: body,
        fromSelf: selfMark != null,
      ),
    );
  }
  return out;
}

/// 会话回复表单(实测 2026-10-25)
///
/// ```
/// form#pmform  POST
///   action=home.php?mod=spacecp&ac=pm&op=send&pmid={pmid}&daterange=0
///          &handlekey=pmsend&pmsubmit=yes
///   textarea[name=message]
///   input[name=formhash]
///   input[name=topmuid]
/// ```
///
/// pmid 在 action 里而不在表单字段里,照搬站点给的 action 即可,不要自己拼。
PostForm? parsePmReplyForm(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final form = doc.querySelector('#pmform');
  final action = form?.attributes['action'];
  if (form == null || action == null || action.isEmpty) return null;

  final hidden = <String, String>{};
  String? formhash;
  for (final input in form.querySelectorAll('input[type="hidden"]')) {
    final name = input.attributes['name'];
    final value = input.attributes['value'] ?? '';
    if (name == null || name.isEmpty) continue;
    if (name == 'formhash') {
      formhash = value;
      continue;
    }
    hidden[name] = value;
  }
  if (formhash == null || formhash.isEmpty) return null;

  return PostForm(
    action: ChhUrls.absolutize(action),
    formhash: formhash,
    hidden: hidden,
  );
}

String? _avatarOf(dom.Element dl) {
  final src = dl.querySelector('.avt img')?.attributes['src'];
  if (src == null || src.isEmpty) return null;
  return ChhUrls.absolutize(src);
}
