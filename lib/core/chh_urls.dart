/// CHH 站点 URL 构造与链接解析工具
library;

class ChhUrls {
  static const String base = 'https://www.chiphell.com';

  /// 桌面 Chrome UA:实测该 UA + 合格客户端指纹 = WAF 直接放行
  static const String chromeUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36';

  static Uri forumIndex() => Uri.parse('$base/forum.php');

  static Uri threadList(int fid, {int page = 1}) =>
      Uri.parse('$base/forum.php?mod=forumdisplay&fid=$fid&page=$page');

  /// Discuz 伪静态:thread-{tid}-{page}-1.html
  ///
  /// **第 2 段才是页码**,第 3 段是 authorid。写反了会导致任何页码都取回第 1 页,
  /// 表现为可以一直翻页但内容始终不变。
  static Uri thread(int tid, {int page = 1}) =>
      Uri.parse('$base/thread-$tid-$page-1.html');

  /// 版块页。typeid 走 filter=typeid 组合;digest / heat 等走 filter 本身。
  ///
  /// 2026-10-29 实测:第 2 页裸 orderby 与 filter+orderby 结果一致。
  /// 排序沿用站点的配对 filter;分类筛选时 filter=typeid 仍可叠加 orderby。
  static Uri threadListFiltered(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
  }) {
    final q = <String, String>{
      'mod': 'forumdisplay',
      'fid': '$fid',
      'page': '$page',
    };
    if (typeid != null && typeid > 0) {
      q['filter'] = 'typeid';
      q['typeid'] = '$typeid';
    } else if (filter != null) {
      q['filter'] = filter;
    }
    if (orderby != null) q['orderby'] = orderby;
    return Uri.parse('$base/forum.php').replace(queryParameters: q);
  }

  /// 帖子详情。带 authorid 即「只看作者」,结构与常规详情页全同构。
  static Uri threadByAuthor(int tid, String uid, {int page = 1}) => Uri.parse(
    '$base/forum.php?mod=viewthread&tid=$tid&authorid=$uid&page=$page',
  );

  /// 导读流:view = new / hot / my,my 需登录
  static Uri guide({String view = 'new', String? type, int page = 1}) {
    final q = <String, String>{'mod': 'guide', 'view': view, 'page': '$page'};
    if (type != null) q['type'] = type;
    return Uri.parse('$base/forum.php').replace(queryParameters: q);
  }

  static Uri search(String keyword) => Uri.parse(
    '$base/search.php?mod=forum&srchtxt=${Uri.encodeComponent(keyword)}&searchsubmit=yes',
  );

  static Uri tag(int id) => Uri.parse('$base/misc.php?mod=tag&id=$id');

  // ---------- 门户 ----------

  static Uri article(int aid, {int page = 1}) =>
      Uri.parse('$base/article-$aid-$page.html');

  /// 门户栏目文章列表
  static Uri portalCategory(int catid, {int page = 1}) =>
      Uri.parse('$base/portal.php?mod=list&catid=$catid&page=$page');

  /// 门户全部文章流。实测 portal.php?page=N 与 index.php?page=N 等价,15 条一页。
  static Uri portalFeed({int page = 1}) =>
      Uri.parse('$base/portal.php?page=$page');

  // ---------- 个人中心 ----------

  static Uri userSpace(String uid) => Uri.parse('$base/space-uid-$uid.html');

  /// 个人帖子:view = me / we,type = thread / reply / postcomment
  ///
  /// filter 取 common / save / close / aduit / ignored / recyclebin;
  /// 待审核的参数确实拼作 aduit,是站点原拼写。
  static Uri spaceThreads({
    String? uid,
    String view = 'me',
    String? type,
    String? filter,
    int page = 1,
  }) {
    final q = <String, String>{
      'mod': 'space',
      'do': 'thread',
      'view': view,
      'page': '$page',
    };
    if (uid != null) q['uid'] = uid;
    if (type != null) q['type'] = type;
    if (filter != null) q['filter'] = filter;
    return Uri.parse('$base/home.php').replace(queryParameters: q);
  }

  /// 提醒:view = all / mypost / interactive / system / app
  static Uri notice({String view = 'all', String? type, int page = 1}) {
    final q = <String, String>{
      'mod': 'space',
      'do': 'notice',
      'view': view,
      'page': '$page',
    };
    if (type != null) q['type'] = type;
    return Uri.parse('$base/home.php').replace(queryParameters: q);
  }

  /// 私信列表。正确入口是 space&do=pm,不是 spacecp&do=pm。
  static Uri pmList({String filter = 'privatepm', int page = 1}) =>
      Uri.parse('$base/home.php').replace(
        queryParameters: {
          'mod': 'space',
          'do': 'pm',
          'filter': filter,
          'page': '$page',
        },
      );

  /// 收藏:type = all / thread / forum / article
  static Uri favorite({String type = 'all', int page = 1}) =>
      Uri.parse('$base/home.php').replace(
        queryParameters: {
          'mod': 'space',
          'do': 'favorite',
          'type': type,
          'page': '$page',
        },
      );

  static Uri medal({bool mine = false}) =>
      Uri.parse('$base/home.php?mod=medal${mine ? '&action=log' : ''}');

  /// 设置与积分:spacecp 的各 ac / op 组合
  static Uri spacecp({
    required String ac,
    String? op,
    String? suboperation,
    int? page,
  }) {
    final q = <String, String>{'ac': ac};
    if (op != null) q['op'] = op;
    if (suboperation != null) q['suboperation'] = suboperation;
    if (page != null && page > 1) q['page'] = '$page';
    return Uri.parse(
      '$base/home.php?mod=spacecp',
    ).replace(queryParameters: {'mod': 'spacecp', ...q});
  }

  /// archiver 省流源:体积约 1/14,纯文本无图
  static Uri archiverThread(int tid, {int page = 1}) =>
      Uri.parse('$base/archiver/tid-$tid.html?page=$page');

  /// 由 uid 推出头像地址
  ///
  /// 站点自己就用这个形态(样本里 8/8 吻合):uid 补零到 9 位,按 3/2/2/2 切分,
  /// 例如 uid 68733 → data/avatar/000/06/87/33_avatar_middle.jpg。
  ///
  /// 注意不要走 `uc_server/avatar.php`,那个端点实测被 WAF 拦。
  /// size 取 small / middle / big。
  static String avatar(String uid, {String size = 'middle'}) {
    final s = uid.padLeft(9, '0');
    return '$base/data/avatar/${s.substring(0, 3)}/${s.substring(3, 5)}'
        '/${s.substring(5, 7)}/${s.substring(7, 9)}_avatar_$size.jpg';
  }

  /// 相对路径转绝对(static.chiphell.com 图片、/data/avatar 头像等)
  static String absolutize(String url) {
    final s = url.trim();
    if (s.isEmpty) return s;
    if (s.startsWith('//')) return 'https:$s';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return Uri.parse('$base/').resolve(s).toString();
  }

  static int? tidFromUrl(String href) {
    final m =
        RegExp(r'thread-(\d+)-').firstMatch(href) ??
        RegExp(r'[?&]tid=(\d+)').firstMatch(href);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static int? fidFromUrl(String href) {
    final m =
        RegExp(r'forum-(\d+)-').firstMatch(href) ??
        RegExp(r'[?&]fid=(\d+)').firstMatch(href);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 用户 UID。站点同时存在伪静态与查询串两种形态,必须都认:
  ///   space-uid-12345.html
  ///   home.php?mod=space&uid=12345
  static String? uidFromUrl(String href) {
    final m =
        RegExp(r'space-uid-(\d+)').firstMatch(href) ??
        RegExp(r'[?&]uid=(\d+)').firstMatch(href);
    return m?.group(1);
  }

  /// Discuz 数字解析:兼容 "4万" / "47444"(优先取 span title 里的精确值)
  static int? parseCount(String raw, {String? title}) {
    if (title != null) {
      final t = int.tryParse(title.trim());
      if (t != null) return t;
    }
    final s = raw.replaceAll(RegExp(r'[^0-9万亿]'), '');
    if (s.isEmpty) return null;
    final wan = s.endsWith('万');
    final n = int.tryParse(s.replaceAll(RegExp(r'[万亿]'), ''));
    if (n == null) return null;
    return wan ? n * 10000 : n;
  }

  /// Discuz 时间文本:发表于 2026-10-19 14:41 / 2026-9-25 14:55 / 最后发表: ...
  static DateTime? parseTime(String raw) {
    final m = RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(raw);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
  }
}
