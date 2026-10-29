/// 读页面解析器单测
///
/// 登录态页面不能用真实账号 HTML 做 fixture(公开样本约定),
/// 这里按文档记载的结构人工构造最小样本,断言的是结构契约本身。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/content_walker.dart';
import 'package:chh_app/parser/dom_utils.dart';
import 'package:chh_app/parser/misc_parser.dart';
import 'package:chh_app/parser/notice_parser.dart';
import 'package:chh_app/parser/pm_parser.dart';
import 'package:chh_app/parser/portal_parser.dart';
import 'package:chh_app/parser/space_parser.dart';

String _page(String body) =>
    '<html><head><title>页面</title></head>'
    '<body>$body</body></html>';

void main() {
  group('消息页分流', () {
    test('带 #messagelogin 判为需登录', () {
      final doc = html_parser.parse(
        _page(
          '<div id="messagetext"><p>请先登录</p></div><div id="messagelogin"></div>',
        ),
      );
      final m = detectPageMessage(doc);
      expect(m?.kind, PageMessageKind.loginRequired);
    });

    test('权限不足判为无权限,不是掉线', () {
      final doc = html_parser.parse(
        _page('<div id="messagetext"><p>抱歉,您目前还没有权限邀请好友</p></div>'),
      );
      expect(detectPageMessage(doc)?.kind, PageMessageKind.permissionDenied);
    });

    test('未定义操作判为功能未开放', () {
      final doc = html_parser.parse(
        _page('<div id="messagetext"><p>未定义操作</p></div>'),
      );
      expect(detectPageMessage(doc)?.kind, PageMessageKind.featureUnavailable);
    });

    test('普通页面不产生消息', () {
      final doc = html_parser.parse(_page('<div id="ct">正常内容</div>'));
      expect(detectPageMessage(doc), isNull);
    });
  });

  group('分页', () {
    test('a#autopbn 的 curpage/totalpage 优先于缺失的分页器', () {
      final doc = html_parser.parse(
        _page('<a id="autopbn" curpage="3" totalpage="12"></a>'),
      );
      final page = parsePager(doc);
      expect(page.current, 3);
      expect(page.hasNext, isTrue);
    });

    test('末页没有 a.nxt', () {
      final doc = html_parser.parse(
        _page('<div class="pg"><strong>12</strong></div>'),
      );
      final page = parsePager(doc);
      expect(page.current, 12);
      expect(page.hasNext, isFalse);
    });

    test('下一页地址沿用站点 href,保留全部查询参数', () {
      final doc = html_parser.parse(
        _page(
          '<div class="pg"><strong>1</strong>'
          '<a class="nxt" href="home.php?mod=space&do=notice&view=mypost&type=post&page=2">下一页</a></div>',
        ),
      );
      expect(nextPageUrl(doc), contains('view=mypost&type=post&page=2'));
    });
  });

  group('提醒解析', () {
    final html = _page('''
<div id="ct">
  <dl id="notice_1001">
    <dt><span class="xg1">2026-10-24 20:11</span>
        <a href="home.php?mod=spacecp&ac=common&op=ignore&type=post">屏蔽</a></dt>
    <dd class="avt"><img src="uc_server/data/avatar/x.jpg"></dd>
    <dd class="ntc_body">
      <a href="home.php?mod=space&uid=12345">测试通知用户</a> 回复了你的主题
      <a class="lit" href="forum.php?mod=redirect&goto=findpost&ptid=900101&pid=55512">示例帖子</a>
    </dd>
  </dl>
  <dl id="notice_1002">
    <dt><span class="xg1">2026-10-23 10:00</span></dt>
    <dd class="ntc_body">系统升级了你的用户组</dd>
  </dl>
</div>''');

    test('条目主键取 notice_ 后缀,不是帖子 tid', () {
      final r = parseNotices(html);
      expect(r.items.map((e) => e.id), ['1001', '1002']);
    });

    test('时间只取 dt span.xg1,不混入屏蔽操作文本', () {
      final n = parseNotices(html).items.first;
      expect(n.occurredAtText, '2026-10-24 20:11');
      expect(n.occurredAtText, isNot(contains('屏蔽')));
    });

    test('目标链接解析出 ptid 与非空 pid', () {
      final n = parseNotices(html).items.first;
      expect(n.tid, 900101);
      expect(n.pid, 55512);
      expect(n.actorUid, '12345');
    });

    test('系统提醒允许没有发送人与目标', () {
      final n = parseNotices(html).items[1];
      expect(n.actor, isNull);
      expect(n.targetUrl, isNull);
      expect(n.summary, contains('用户组'));
    });

    test('类型优先用当前筛选参数', () {
      expect(
        parseNotices(html, filterCategory: 'rate').items.first.category,
        'rate',
      );
    });

    test('没有筛选参数时从屏蔽链接的 type 兜底', () {
      expect(parseNotices(html).items.first.category, 'post');
    });
  });

  group('私信解析', () {
    test('列表取 plid,预览剔掉操作区', () {
      final html = _page('''
<div id="deletepmform">
  <dl id="pmlist_880">
    <dd class="avt"><img src="uc_server/data/avatar/y.jpg"></dd>
    <dd class="pm_c">
      <a href="home.php?mod=space&do=pm&subop=view&touid=777">查看</a>
      <a href="home.php?mod=space&uid=777">测试会话用户</a>
      <span class="o"><a href="#">忽略</a></span>
      示例私信预览：显示器相关的合成内容
      <em>2026-10-24 21:30</em>
    </dd>
  </dl>
  <dl id="pmlist_881">
    <dd class="pm_c"><a href="home.php?mod=space&do=pm&subop=view&touid=888">测试会话对象</a>收到</dd>
  </dl>
</div>''');
      final r = parsePmList(html);
      expect(r.items.first.id, '880');
      expect(r.items.first.peerUid, '777');
      expect(r.items.first.preview, contains('显示器'));
      expect(r.items.first.preview, isNot(contains('忽略')));
      expect(r.items.length, 2);
    });

    test('公共消息走 gpmlist_ 前缀', () {
      final html = _page('''
<dl id="gpmlist_12">
  <dd class="pm_c"><a href="home.php?mod=space&do=pm&subop=viewg&pmid=12">站点公告</a>内容</dd>
</dl>''');
      final r = parsePmList(html, filter: PmFilter.announcePm);
      expect(r.items.single.id, '12');
    });

    test('会话详情的 pmlist_ 后缀是 pmid,正文从 dd.ptm 分离', () {
      final html = _page('''
<div id="pm_ul">
  <dl id="pmlist_5001">
    <dd class="ptm">
      <a class="xw1" href="home.php?mod=space&uid=777">测试会话用户</a>
      <span class="xg1">2026-10-24 21:30</span>
      示例私信正文，测试词为背光均匀度。
    </dd>
  </dl>
</div>''');
      final msgs = parsePmThread(html);
      expect(msgs.single.pmid, '5001');
      expect(msgs.single.author, '测试会话用户');
      expect(msgs.single.timeRaw, '2026-10-24 21:30');
      expect(msgs.single.text, contains('背光均匀度'));
      expect(msgs.single.text, isNot(contains('测试会话用户')));
    });

    test('自己发的消息以"您"标出:判为自己,"您"不进正文', () {
      // 合成会话页结构：自己一条没有作者链接,只有 span.xw1 "您"
      final html = _page('''
<div id="pm_ul">
  <dl id="pmlist_6001" class="bbda cl">
    <dd class="m avt"><a href="space-uid-1001.html"><img src="a.jpg"></a></dd>
    <dd class="ptm"><span class="xi2 xw1">您</span> &nbsp; <br> 这是一条合成的本人消息<br> <span class="xg1">2001-1-2 03:04</span></dd>
  </dl>
  <dl id="pmlist_6002" class="bbda cl">
    <dd class="m avt"><a href="space-uid-777.html"><img src="b.jpg"></a></dd>
    <dd class="ptm"><a href="space-uid-777.html" class="xw1">测试会话用户</a> &nbsp; <br> 这是一条合成的对方消息<br> <span class="xg1">2001-1-3 04:05</span></dd>
  </dl>
</div>''');
      final msgs = parsePmThread(html);
      expect(msgs[0].fromSelf, isTrue);
      expect(msgs[0].authorUid, '1001');
      expect(msgs[0].text, '这是一条合成的本人消息');
      expect(msgs[0].timeRaw, '2001-1-2 03:04');
      expect(msgs[1].fromSelf, isFalse);
      expect(msgs[1].author, '测试会话用户');
      expect(msgs[1].authorUid, '777');
    });
    test('自己的消息正文带用户主页链接时仍判为自己', () {
      final html = _page('''
<div id="pm_ul">
  <dl id="pmlist_6003" class="bbda cl">
    <dd class="m avt"><a href="space-uid-1001.html"><img src="a.jpg"></a></dd>
    <dd class="ptm"><span class="xi2 xw1">您</span> &nbsp; <br> 卖家是 <a href="space-uid-5.html">某人</a><br> <span class="xg1">2026-7-3 09:00</span></dd>
  </dl>
</div>''');
      final msg = parsePmThread(html).single;
      expect(msg.fromSelf, isTrue);
      expect(msg.authorUid, '1001');
      expect(msg.text, contains('某人'));
    });

    test('span.xw1 不是"您"时不判为自己', () {
      final html = _page('''
<div id="pm_ul">
  <dl id="pmlist_6004" class="bbda cl">
    <dd class="ptm"><span class="xi2 xw1">系统</span> &nbsp; <br> 公告正文<br> <span class="xg1">2026-7-3 09:00</span></dd>
  </dl>
</div>''');
      expect(parsePmThread(html).single.fromSelf, isFalse);
    });
  });

  group('个人帖子解析', () {
    test('裸表格行解析,一帖归并多条回复摘要', () {
      final html = _page('''
<div id="delform"><table>
  <tr class="th"><td>表头</td></tr>
  <tr class="bw0_all">
    <td class="icn"></td>
    <th><a href="forum.php?mod=viewthread&tid=900101">示例帖子</a></th>
    <td><a href="forum-290-1.html">显卡讨论</a></td>
    <td class="num"><a>128</a><em>42000</em></td>
    <td class="by"><cite><a href="home.php?mod=space&uid=9">测试会话用户</a></cite>
        <em><a href="#">2026-10-24 20:34</a></em></td>
  </tr>
  <tr><td class="xg1" colspan="5">
    我的第一条回复 <a href="forum.php?mod=redirect&goto=findpost&ptid=900101&pid=1001">查看</a>
  </td></tr>
  <tr><td class="xg1" colspan="5">
    我的第二条回复 <a href="forum.php?mod=redirect&goto=findpost&ptid=900101&pid=1002">查看</a>
  </td></tr>
</table></div>''');
      final r = parseMyThreads(html);
      final item = r.items.single;
      expect(item.tid, 900101);
      expect(item.title, '示例帖子');
      expect(item.forumFid, 290);
      expect(item.replies, 128);
      // 唯一的 td.by 是最后回复者,不是主题作者
      expect(item.lastUser, '测试会话用户');
      expect(item.replySnippets.map((e) => e.pid), [1001, 1002]);
    });

    test('pid 为空的摘要行不参与定位', () {
      final html = _page('''
<div id="delform"><table>
  <tr><th><a href="thread-900101-1-1.html">帖子</a></th></tr>
  <tr><td class="xg1" colspan="5">
    <a href="forum.php?mod=redirect&goto=findpost&ptid=900101&pid=">查看</a>
  </td></tr>
</table></div>''');
      expect(parseMyThreads(html).items.single.replySnippets, isEmpty);
    });
  });

  group('收藏解析', () {
    test('favid 与内容 id 分开,类型按目标 URL 判定', () {
      final html = _page('''
<ul id="favorite_ul">
  <li id="fav_3301">
    <a href="thread-900101-1-1.html">收藏的帖子</a>
    <span class="xg1">2026-10-20</span>
  </li>
  <li id="fav_3302">
    <a href="forum-290-1.html">收藏的版块</a>
  </li>
</ul>''');
      final r = parseFavorites(html);
      expect(r.items.first.favid, '3301');
      expect(r.items.first.tid, 900101);
      expect(r.items[1].fid, 290);
    });
  });

  group('标签与分类', () {
    test('标签页是裸 table,按 thread 链接提取', () {
      final html = _page('''
<table>
  <tr><td><a href="thread-900001-1-1.html">水冷帖</a></td>
      <td><a href="home.php?mod=space&uid=5">测试标签作者</a></td>
      <td>2026-10-24</td></tr>
</table>''');
      final r = parseTagThreads(html);
      expect(r.items.single.tid, 900001);
      expect(r.items.single.author, '测试标签作者');
    });

    test('分类名去掉数量徽标但保留名称中的数字', () {
      final types = parseThreadTypes(
        _page('''<ul id="thread_types">
        <li><a href="forum.php?typeid=1">ITX<span class="num">13</span></a></li>
        <li><a href="forum.php?typeid=2">Wi-Fi 7<span class="xg1 num">8512</span></a></li>
      </ul>'''),
      );
      expect(types.map((type) => type.name), ['ITX', 'Wi-Fi 7']);
      expect(types.map((type) => type.typeid), [1, 2]);
    });

    test('分类标签解析 typeid 与当前选中态', () {
      final html = _page('''
<ul id="thread_types">
  <li class="xw1"><a href="forum-290-1.html">全部</a></li>
  <li class="xw1 a"><a href="forum.php?mod=forumdisplay&fid=290&filter=typeid&typeid=1010">ITX</a></li>
</ul>''');
      final types = parseThreadTypes(html);
      expect(types.first.typeid, 0);
      expect(types[1].typeid, 1010);
      expect(types[1].active, isTrue);
    });
  });

  group('表格与设置', () {
    test('表格按实际表头取列,不固定列序', () {
      final table = parseSiteTable(
        _page('''
<table class="dt">
  <tr class="th"><th>操作</th><th>积分变更</th><th>变更时间</th></tr>
  <tr><td>发表主题</td><td>威望 +2</td><td>2026-10-24</td></tr>
</table>'''),
      );
      expect(table.headers, ['操作', '积分变更', '变更时间']);
      expect(table.rows.single[1], '威望 +2');
    });

    test('设置项区分 select 当前值与 checkbox 勾选态', () {
      final form = parseSettingsForm(
        _page('''
<div id="profilelist"><table>
  <tr><th>时区</th><td>
    <select name="timeoffset">
      <option value="9999">系统默认</option>
      <option value="8" selected>UTC+8</option>
    </select></td></tr>
  <tr><th>接受好友请求</th><td>
    <input type="checkbox" name="allowasfriend" checked></td></tr>
</table></div>'''),
      );
      final tz = form.fields.firstWhere((f) => f.name == 'timeoffset');
      expect(tz.value, 'UTC+8');
      expect(tz.options.length, 2);
      final friend = form.fields.firstWhere((f) => f.name == 'allowasfriend');
      expect(friend.checked, isTrue);
    });

    test('勋章排除 _menu 节点,避免重复计数', () {
      final medals = parseMedals(
        _page('''
<div id="medal_7" class="mg_img"><img src="static/image/medal/7.gif" alt="资深会员"></div>
<div id="medal_7_menu" class="tip">颁发给注册满三年的会员</div>'''),
      );
      expect(medals.length, 1);
      expect(medals.single.name, '资深会员');
      expect(medals.single.description, contains('三年'));
    });
  });

  group('门户文章详情', () {
    test('取 h1.ph 与 td#article_content', () {
      final a = parseArticle(
        _page(
          '<h1 class="ph">深度评测</h1>'
          '<table><tr><td id="article_content"><p>正文段落</p>'
          '<img src="/data/attachment/portal/a.jpg"></td></tr></table>',
        ),
        aid: 9001,
      );
      expect(a.title, '深度评测');
      expect(a.content.whereType<TextBlock>().first.text, '正文段落');
      expect(
        a.content.whereType<ImageBlock>().single.url,
        contains('/data/attachment/portal/a.jpg'),
      );
      expect(a.metaRaw, isNull);
    });

    test('文章元信息只取标题区，不匹配前置全站搜索', () {
      final a = parseArticle(
        _page('''
<div id="scbar" class="ptm"><span class="xg1">搜索</span></div>
<div class="bm vw"><div class="h hm">
  <h1 class="ph">示例硬件评测</h1>
  <p class="xg1">2001-01-02 03:04<span class="pipe">|</span>
    发布者: <a href="space-uid-2.html">测试发布者</a>
    <span class="pipe">|</span>原作者: 测试原作者</p>
</div><table><tr><td id="article_content">序言</td></tr></table></div>'''),
        aid: 50001,
      );
      expect(a.metaRaw, contains('2001-01-02 03:04'));
      expect(a.metaRaw, contains('原作者: 测试原作者'));
      expect(a.metaRaw, isNot(contains('搜索')));

      final withoutArticleMeta = parseArticle(
        _page('''
<div class="ptm"><span class="xg1">搜索</span></div>
<div class="bm vw"><div class="h hm"><h1 class="ph">无元信息</h1></div>
<table><tr><td id="article_content"><span class="xg1">正文提示</span></td></tr></table>
</div>'''),
        aid: 50001,
      );
      expect(withoutArticleMeta.metaRaw, isNull);
    });

    test('命中登录墙时抛出消息', () {
      expect(
        () => parseArticle(
          _page(
            '<div id="messagetext">请先登录</div>'
            '<div id="messagelogin"></div>',
          ),
          aid: 1,
        ),
        throwsA(isA<PageMessage>()),
      );
    });
  });

  group('用户主页', () {
    test('资料与统计按实际字段收集', () {
      final p = parseUserProfile(
        _page('''
<div id="uhd"><h2 class="mbn">测试主页用户</h2><img src="uc_server/data/avatar/z.jpg"></div>
<div class="u_profile"><li><em>注册时间</em>2016-03-01</li></div>
<div id="psts"><li><em>主题</em>128</li></div>'''),
        uid: '12345',
      );
      expect(p.name, '测试主页用户');
      expect(p.profile['注册时间'], '2016-03-01');
      expect(p.stats['主题'], '128');
    });
  });

  _contentCleanupTests();
}

/// 正文清洗回归
///
/// 曾经把附件的悬浮提示当成正文,楼层里混进
/// 「xxx.jpg (206.96 KB, 下载次数: 0) 下载附件 2026-10-23 09:56 上传」。
/// 那块在网页上是 display:none 的 tip,用户根本看不到。
void _contentCleanupTests() {
  group('正文清洗', () {
    test('附件悬浮提示不进正文', () {
      final html = _page('''
<div align="center">
  <ignore_js_op>
    <img id="aimg_1" zoomfile="https://static.chiphell.com/forum/a.png" class="zoom">
    <div class="tip tip_4 aimg_tip" id="aimg_1_menu" style="position: absolute; display: none">
      <div class="xs0">
        <p><strong>synthetic-attachment.png</strong><em class="xg1">(123.45 KB, 下载次数: 0)</em></p>
        <p><a href="forum.php?mod=attachment&aid=xxx">下载附件</a></p>
        <p class="xg1 y">2001-01-02 03:04 上传</p>
      </div>
      <div class="tip_horn"></div>
    </div>
  </ignore_js_op>
</div>
<div align="center">设计图:</div>''');

      final root = html_parser.parse(html).body!;
      final blocks = parseContentBlocks(root);
      final text = blocks.whereType<TextBlock>().map((b) => b.text).join(' ');

      expect(text, isNot(contains('下载次数')));
      expect(text, isNot(contains('下载附件')));
      expect(text, isNot(contains('上传')));
      expect(text, isNot(contains('KB')));
      // 真正的正文要保留
      expect(text, contains('设计图'));
      // 图片本身照常取 zoomfile
      expect(
        blocks.whereType<ImageBlock>().single.url,
        'https://static.chiphell.com/forum/a.png',
      );
    });

    test('任何 display:none 的节点都不进正文', () {
      final root = html_parser
          .parse(_page('<p>可见段落</p><p style="display:none">隐藏内容</p>'))
          .body!;
      final text = parseContentBlocks(
        root,
      ).whereType<TextBlock>().map((b) => b.text).join(' ');

      expect(text, contains('可见段落'));
      expect(text, isNot(contains('隐藏内容')));
    });
  });

  _favoriteTests();
}

/// 收藏解析的回归
///
/// 合成结构：删除链接排在内容链接**前面**,
/// 之前直接取第一个 a,整列标题都成了「删除」。
void _favoriteTests() {
  group('收藏', () {
    const synthetic = '''
<ul id="favorite_ul">
  <li id="fav_80001" class="bbda ptm pbm">
    <a href="home.php?mod=spacecp&ac=favorite&op=delete&favid=80001" id="a_delete_80001" class="y">删除</a>
    <input class="pc" type="checkbox">
    <span><img class="t" src="x.gif"></span>
    <a href="thread-900501-1-1.html">示例打印设备讨论</a>
    <span class="xg1">2001-1-2 03:04</span>
  </li>
  <li id="fav_80002" class="bbda ptm pbm">
    <a href="home.php?mod=spacecp&ac=favorite&op=delete&favid=80002" id="a_delete_80002" class="y">删除</a>
    <a href="forum-312-1.html">示例闲聊区</a>
    <span class="xg1">2001-1-2 03:04</span>
  </li>
</ul>''';

    test('标题取内容链接,不是删除链接', () {
      final r = parseFavorites(_page(synthetic));
      expect(r.items.map((e) => e.title), ['示例打印设备讨论', '示例闲聊区']);
    });

    test('favid 与内容 id 分开', () {
      final r = parseFavorites(_page(synthetic));
      expect(r.items.first.favid, '80001');
      expect(r.items.first.tid, 900501);
      expect(r.items[1].fid, 312);
    });

    test('时间来自 span.xg1', () {
      expect(
        parseFavorites(_page(synthetic)).items.first.timeRaw,
        '2001-1-2 03:04',
      );
    });

    test('只有删除链接的残缺条目不产出', () {
      final r = parseFavorites(
        _page('''
<ul id="favorite_ul">
  <li id="fav_1"><a href="home.php?mod=spacecp&ac=favorite&op=delete" id="a_delete_1">删除</a></li>
</ul>'''),
      );
      expect(r.items, isEmpty);
    });
  });

  _tablePagingTests();
}

/// 表格页分页
///
/// 积分记录有几十页,之前只解析第一页,拉不到历史。
void _tablePagingTests() {
  group('只读表格分页', () {
    test('带出当前页与下一页地址', () {
      final t = parseSiteTable(
        _page(
          '''
<table class="dt">
  <tr class="th"><th>操作</th><th>积分变更</th><th>详情</th><th>变更时间</th></tr>
  <tr><td>积分规则</td><td>邪恶指数 +1</td><td></td><td>2026-10-24 20:57</td></tr>
</table>
<div class="pgs cl mtm"><div class="pg"><strong>1</strong>
  <a class="nxt" href="home.php?mod=spacecp&op=log&ac=credit&page=2">下一页</a></div></div>''',
        ),
      );

      expect(t.headers, ['操作', '积分变更', '详情', '变更时间']);
      expect(t.rows.single[1], '邪恶指数 +1');
      expect(t.page.current, 1);
      expect(t.page.hasNext, isTrue);
      expect(t.nextUrl, contains('page=2'));
    });

    test('末页没有下一页', () {
      final t = parseSiteTable(
        _page('''
<table class="dt"><tr class="th"><th>操作</th></tr><tr><td>签到</td></tr></table>
<div class="pgs"><div class="pg"><strong>9</strong></div></div>'''),
      );
      expect(t.page.hasNext, isFalse);
    });
  });
}
