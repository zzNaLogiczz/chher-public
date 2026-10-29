/// 正文链接分类:决定一个 href 显示成卡片、视频还是普通可点文字
///
/// 只识别明确支持的链接形态(合成样本见 test_data/content_links_synthetic.html),
/// 认不出的本站地址交给浏览器,不猜它对应哪个页面。
library;

import 'chh_urls.dart';

sealed class LinkTarget {
  /// 打开用的完整地址
  final Uri uri;
  const LinkTarget(this.uri);

  /// 同一目标的身份,同一楼层里据此只出一张卡片
  String get key;
}

class ThreadLink extends LinkTarget {
  final int tid;

  /// findpost 链接指向的楼层
  final int? pid;
  const ThreadLink(super.uri, {required this.tid, this.pid});

  @override
  String get key => pid == null ? 'thread:$tid' : 'thread:$tid:$pid';
}

class ArticleLink extends LinkTarget {
  final int aid;
  const ArticleLink(super.uri, {required this.aid});

  @override
  String get key => 'article:$aid';
}

class BilibiliVideo extends LinkTarget {
  /// 带 BV 前缀的稿件号;老内嵌只有 [aid]
  final String? bvid;
  final int? aid;

  /// 分 P,从 1 开始
  final int page;
  const BilibiliVideo(super.uri, {this.bvid, this.aid, this.page = 1});

  @override
  String get key => 'bilibili:${bvid ?? 'av$aid'}:$page';

  /// 在浏览器里打开的视频页;播放器加载失败时用
  Uri get pageUrl => Uri.https(
    'www.bilibili.com',
    '/video/${bvid ?? 'av$aid'}',
    page > 1 ? {'p': '$page'} : null,
  );

  /// 外链播放器地址;用户已点播放,所以自动播放、关弹幕
  Uri get playerUrl => Uri.https('player.bilibili.com', '/player.html', {
    if (bvid != null) 'bvid': bvid! else 'aid': '$aid',
    'p': '$page',
    'autoplay': '1',
    'danmaku': '0',
    'high_quality': '1',
  });
}

/// 本站的其他页面(版块、用户空间、标签等),交给浏览器
class OtherSiteLink extends LinkTarget {
  const OtherSiteLink(super.uri);

  @override
  String get key => 'site:$uri';
}

class ExternalLink extends LinkTarget {
  const ExternalLink(super.uri);

  @override
  String get key => 'external:$uri';
}

final _base = Uri.parse(ChhUrls.base);
final _positive = RegExp(r'^[1-9]\d*$');
final _bvid = RegExp(r'^(?:BV)?([0-9A-Za-z]{10})$');

/// 把正文里的 href 分类;空链接、锚点、javascript:、mailto: 返回 null
LinkTarget? classifyLink(String href) {
  final raw = href.trim();
  if (raw.isEmpty || raw.startsWith('#')) return null;
  final parsed = Uri.tryParse(raw);
  if (parsed == null) return null;
  final uri = _base.resolveUri(parsed);
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;

  final host = uri.host.toLowerCase();
  // 帖子、文章会带着登录 Cookie 在 App 内请求,所以本站只认默认端口、无 userinfo
  if ((host == 'www.chiphell.com' || host == 'chiphell.com') &&
      uri.userInfo.isEmpty &&
      !uri.hasPort) {
    return _siteLink(uri) ?? OtherSiteLink(uri);
  }
  if (host == 'www.bilibili.com' || host == 'm.bilibili.com') {
    final video = _bilibiliPage(uri);
    if (video != null) return video;
  }
  if (host == 'player.bilibili.com') {
    final video = _bilibiliPlayer(uri);
    if (video != null) return video;
  }
  return ExternalLink(uri);
}

/// 播放器 WebView 的主页面是否还在播放器里
///
/// 外链播放器在手机 UA 下会用 JS 跳到 www.bilibili.com/blackboard/ 下的移动版播放器,
/// 这一步要放行;其余地址(主站视频页、bilibili:// 拉起 App)都算离开播放器。
bool isBilibiliPlayerPage(Uri url) {
  if (url.scheme != 'https' && url.scheme != 'http') return false;
  final host = url.host.toLowerCase();
  if (host == 'player.bilibili.com') return true;
  return host == 'www.bilibili.com' && url.path.startsWith('/blackboard/');
}

/// 站点把 [media] 渲染成一段写入播放器 iframe 的脚本;从脚本或 iframe src 里取视频
BilibiliVideo? bilibiliFromEmbed(String source) {
  final match = RegExp(
    r'''https?://player\.bilibili\.com/player\.html\?[^'"\s<>\\]+''',
  ).firstMatch(source);
  if (match == null) return null;
  final uri = Uri.tryParse(match.group(0)!.replaceAll('&amp;', '&'));
  return uri == null ? null : _bilibiliPlayer(uri);
}

LinkTarget? _siteLink(Uri uri) {
  final path = uri.path;
  final q = uri.queryParameters;
  int? id(String? raw) =>
      raw != null && _positive.hasMatch(raw) ? int.parse(raw) : null;

  final threadPath = RegExp(r'^/thread-(\d+)-\d+-\d+\.html$').firstMatch(path);
  if (threadPath != null) {
    final tid = id(threadPath.group(1));
    return tid == null ? null : _thread(tid);
  }
  final articlePath = RegExp(r'^/article-(\d+)-\d+\.html$').firstMatch(path);
  if (articlePath != null) {
    final aid = id(articlePath.group(1));
    return aid == null ? null : _article(aid);
  }
  if (path == '/forum.php' && q['mod'] == 'viewthread') {
    final tid = id(q['tid']);
    return tid == null ? null : _thread(tid);
  }
  if (path == '/forum.php' &&
      q['mod'] == 'redirect' &&
      q['goto'] == 'findpost') {
    final tid = id(q['ptid'] ?? q['tid']);
    final pid = id(q['pid']);
    return tid == null ? null : _thread(tid, pid: pid);
  }
  if (path == '/portal.php' && q['mod'] == 'view') {
    final aid = id(q['aid']);
    return aid == null ? null : _article(aid);
  }
  return null;
}

/// 帖子、文章的打开地址由编号重新拼出,不沿用正文里写的原地址(协议、多余参数都可能被篡改)
ThreadLink _thread(int tid, {int? pid}) => ThreadLink(
  pid == null
      ? ChhUrls.thread(tid)
      : _base.replace(
          path: '/forum.php',
          queryParameters: {
            'mod': 'redirect',
            'goto': 'findpost',
            'ptid': '$tid',
            'pid': '$pid',
          },
        ),
  tid: tid,
  pid: pid,
);

ArticleLink _article(int aid) => ArticleLink(ChhUrls.article(aid), aid: aid);

BilibiliVideo? _bilibiliPage(Uri uri) {
  final m = RegExp(
    r'^/video/(?:(BV[0-9A-Za-z]{10})|av(\d+))/?$',
  ).firstMatch(uri.path);
  if (m == null) return null;
  final page = _page(uri.queryParameters['p']);
  if (m.group(1) != null) {
    return BilibiliVideo(uri, bvid: m.group(1), page: page);
  }
  return BilibiliVideo(uri, aid: int.parse(m.group(2)!), page: page);
}

BilibiliVideo? _bilibiliPlayer(Uri uri) {
  if (uri.host != 'player.bilibili.com' || uri.path != '/player.html') {
    return null;
  }
  final q = uri.queryParameters;
  final page = _page(q['p'] ?? q['page']);
  // 站点生成的内嵌把 BV 前缀吃掉了(bvid=1Tvpb6HEJe),播放器不认,这里补回
  final bv = _bvid.firstMatch(q['bvid'] ?? '');
  if (bv != null) {
    return BilibiliVideo(uri, bvid: 'BV${bv.group(1)}', page: page);
  }
  final aid = q['aid'];
  if (aid != null && _positive.hasMatch(aid)) {
    return BilibiliVideo(uri, aid: int.parse(aid), page: page);
  }
  return null;
}

int _page(String? raw) =>
    raw != null && _positive.hasMatch(raw) ? int.parse(raw) : 1;
