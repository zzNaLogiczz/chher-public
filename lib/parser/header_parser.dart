/// 登录态页头:账号、头像、未读计数
///
/// 页头结构示例(账号和标识为虚构数据):
/// ```
/// div#um
///   div.avt.y > a > img.user_avatar          头像
///   p
///     strong.vwmy > a  "示例账号"           账号,href=space-uid-1001.html
///     a#pm_ntc  <em class="prompt_news_0">   私信,未读数在 class 后缀
///     a#myprompt.a.showmenu  "提醒"
///     span#myprompt_check
/// ```
///
/// 未读只认两个可信来源:`prompt_news_N` 的后缀数字,以及文案里的数字。
/// `.a` 类不算 —— 实测无未读时 `#myprompt` 同样带 `a showmenu`。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import 'dom_utils.dart';

class HeaderBadges {
  final int notices;
  final int messages;

  /// 当前登录账号。页头 `#um strong.vwmy a` 就是它(PAGE_SPEC §6.1)。
  final String? userName;
  final String? uid;

  /// 页头上的头像地址
  final String? avatarSrc;

  /// 解析不到账号时留下的页头摘要,仅用于排查,不参与相等判断
  final String? headerSample;

  const HeaderBadges({
    required this.notices,
    required this.messages,
    this.userName,
    this.uid,
    this.avatarSrc,
    this.headerSample,
  });

  /// 头像
  ///
  /// 优先按 uid 推导 middle 尺寸:页头自带的是 small(48px),
  /// 放进 34dp 容器在高倍屏上会糊。推导规则已用真实样本逐条核对。
  /// 取不到 uid 时才退回页头给的地址。
  String? get avatarUrl => uid != null ? ChhUrls.avatar(uid!) : avatarSrc;

  int get total => notices + messages;

  bool get hasAny => total > 0;

  @override
  bool operator ==(Object other) =>
      other is HeaderBadges &&
      other.notices == notices &&
      other.messages == messages &&
      other.userName == userName &&
      other.uid == uid;

  @override
  int get hashCode => Object.hash(notices, messages, userName, uid);

  @override
  String toString() => '提醒 $notices 私信 $messages 账号 ${userName ?? '-'}';
}

/// 解析页头计数
///
/// 返回 null 表示这个页面没有登录态页头(游客页、消息页等),调用方应当保持原值不动,
/// 而不是清零 —— 否则随便打开一个游客页就会把未读抹掉。
HeaderBadges? parseHeaderBadges(String html) {
  final doc = html_parser.parse(html);
  // 模板可能不叫 #um。退出登录链接只在登录态出现,用它兜底定位页头容器。
  final um = doc.querySelector('#um') ?? _headerByLogout(doc);
  if (um == null) return null;
  final me = _currentUser(um);

  // 页头自带头像。实测是 small 尺寸,只在取不到 uid 时用它兜底。
  final avatarEl =
      um.querySelector('img.user_avatar') ?? um.querySelector('.avt img');
  final avatar = avatarEl?.attributes['src'];

  return HeaderBadges(
    notices: _countIn(doc, '#myprompt'),
    messages: _countIn(doc, '#pm_ntc'),
    userName: me?.name,
    uid: me?.uid,
    avatarSrc: (avatar == null || avatar.isEmpty)
        ? null
        : ChhUrls.absolutize(avatar),
    // 命中不了时把页头留下来,便于真机上对照真实模板
    headerSample: me == null ? _sampleOf(um) : null,
  );
}

/// 用退出登录链接反查页头容器
///
/// 往上找两层:退出链接通常和用户名在同一个菜单块里。
dom.Element? _headerByLogout(dom.Document doc) {
  final out = doc.querySelector('a[href*="action=logout"]');
  if (out == null) return null;
  return out.parent?.parent ?? out.parent;
}

/// 页头里的当前账号
///
/// 文档记的是 `#um strong.vwmy a`,但模板会改。所以按从严到宽依次尝试,
/// 最后退到「页头里第一个能解出 uid 且带文字的链接」。
({String name, String? uid})? _currentUser(dom.Element um) {
  for (final sel in const ['strong.vwmy a', '.vwmy a', 'strong a']) {
    final el = um.querySelector(sel);
    final name = cleanText(el?.text);
    if (name.isNotEmpty) {
      return (
        name: name,
        uid: ChhUrls.uidFromUrl(el?.attributes['href'] ?? ''),
      );
    }
  }

  final found = findUserLink(um);
  if (found == null) return null;
  final name = cleanText(found.el.text);
  return name.isEmpty ? null : (name: name, uid: found.uid);
}

/// 页头文本摘要,只取开头一小段用于排查
String _sampleOf(dom.Element um) {
  final text = cleanText(um.text);
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

int _countIn(dom.Document doc, String selector) {
  final el = doc.querySelector(selector);
  if (el == null) return 0;

  // 站点把未读数编在 class 后缀里:<em class="prompt_news_0">
  for (final em in el.querySelectorAll('[class*="prompt_news_"]')) {
    final m = RegExp(r'prompt_news_(\d+)').firstMatch(em.className);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
  }

  // 其次看文案里的数字(常见是 .num 子节点)
  final target = el.querySelector('.num') ?? el;
  final m = RegExp(r'(\d+)').firstMatch(cleanText(target.text));
  return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
}
