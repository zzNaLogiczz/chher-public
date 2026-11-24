import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/notice_parser.dart';
import 'package:chh_app/parser/pm_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String noticeHtml(
  String body, {
  String attributes = '',
  String type = 'post',
}) =>
    '''<dl id="notice_12" $attributes>
      <dt><span class="xg1">2026-11-15 17:40</span>
      <a href="home.php?mod=spacecp&amp;ac=common&amp;op=ignore&amp;type=$type">屏蔽</a></dt>
      <dd class="ntc_body">$body</dd>
    </dl>''';

const actor = '<a href="home.php?mod=space&amp;uid=17">合成用户</a>';
const title =
    '<a class="lit" href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=25&amp;pid=33">合成帖子</a>';
const view =
    '<a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=25&amp;pid=33">查看</a>';

String conversationHtml(String preview, {String attributes = ''}) =>
    '''
  <dl id="pmlist_9" $attributes>
    <dd class="avt"><img src="avatar.jpg"></dd>
    <dd class="pm_c">
      <a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=17">查看</a>
      $preview
      <em>2026-11-15 17:40</em>
      <span class="pm_o">忽略</span>
    </dd>
  </dl>''';

void main() {
  group('提醒定稿字段', () {
    test('标题、动作与原文分别保留，定位字段不变', () {
      final n = parseNotices(
        noticeHtml('$actor 回复了你的主题 $title $view'),
      ).items.single;
      expect(n.actor, '合成用户');
      expect(n.title, '合成帖子');
      expect(n.action, '回复了你的主题');
      expect(n.summary, '合成用户 回复了你的主题 合成帖子 查看');
      expect(n.tid, 25);
      expect(n.pid, 33);
      expect(n.targetUrl, contains('goto=findpost'));
      expect(n.score, isNull);
    });

    test('标题含人名时只删除作者节点，不破坏真实标题', () {
      final n = parseNotices(
        noticeHtml(
          '$actor 回复了你的主题 <a class="lit" href="thread-25-1-1.html">合成用户的桌面</a> $view',
        ),
      ).items.single;
      expect(n.title, '合成用户的桌面');
      expect(n.action, '回复了你的主题');
    });

    test('评分保留分值与单位，不把局部加粗当作新提醒', () {
      final n = parseNotices(
        noticeHtml(
          '$actor 给你的回复 $title 评分 <strong class="xi1">激情 +2</strong> $view',
          type: 'rate',
        ),
      ).items.single;
      expect(n.action, '评分了您的帖子　激情 +2');
      expect(n.score, '激情 +2');
      expect(n.unread, isFalse);
    });

    test('没有强调标签时仍解析源站分值，不补造缺失分数', () {
      final rated = parseNotices(
        noticeHtml('$actor 给你的主题 $title 评分 邪恶 - 2 $view', type: 'rate'),
      ).items.single;
      final missing = parseNotices(
        noticeHtml('$actor 给你的主题 $title 评分', type: 'rate'),
      ).items.single;
      expect(rated.score, '邪恶 - 2');
      expect(missing.score, isNull);
    });

    test('评分不能误取人名或标题里的数字', () {
      final n = parseNotices(
        noticeHtml(
          '<a class="xi2" href="space-uid-17.html">User+99</a> 给你的主题 '
          '<a class="lit" href="thread-25-1-1.html"><span class="xi1">DDR5+32</span></a> 评分 激情 +2',
          type: 'rate',
        ),
      ).items.single;
      expect(n.score, '激情 +2');
    });

    test('明确的条目加粗样式标记为新提醒', () {
      for (final attributes in [
        'class="xw1"',
        'style="font-weight: bold;"',
        'style="font-weight:700"',
      ]) {
        final n = parseNotices(
          noticeHtml('$actor 回复了你的主题 $title', attributes: attributes),
        ).items.single;
        expect(n.unread, isTrue, reason: attributes);
      }
    });

    test('事件块与整段加粗标记为新提醒', () {
      for (final html in [
        noticeHtml('$actor 回复了你的主题 $title').replaceFirst(
          'class="ntc_body"',
          'class="ntc_body" style="font-weight:bold"',
        ),
        noticeHtml('<strong>$actor 回复了你的主题 $title</strong>'),
      ]) {
        expect(parseNotices(html).items.single.unread, isTrue);
      }
    });

    test('只有标题或名字加粗，以及没有样式时沿用非未读显示', () {
      for (final body in [
        '<strong>$actor</strong> 回复了你的主题 $title',
        '$actor 回复了你的主题 <strong>$title</strong>',
        '$actor 回复了你的主题 $title',
      ]) {
        expect(parseNotices(noticeHtml(body)).items.single.unread, isFalse);
      }
    });

    test('系统消息不补造作者和标题，动作避免重复系统名字', () {
      final n = parseNotices(
        noticeHtml('系统升级了你的用户组', type: 'system'),
      ).items.single;
      expect(n.actor, isNull);
      expect(n.title, isNull);
      expect(n.score, isNull);
      expect(n.action, '升级了你的用户组');
      expect(n.summary, '系统升级了你的用户组');
    });

    test('缺失标题时不从查看链接补造标题', () {
      final n = parseNotices(noticeHtml('$actor 回复了你 $view')).items.single;
      expect(n.title, isNull);
      expect(n.action, '回复了你');
      expect(n.pid, 33);
    });

    test('去掉空的标题书名号并保留后续动作', () {
      final n = parseNotices(
        noticeHtml('$actor 在主题《$title》中提到了你 $view', type: 'at'),
      ).items.single;
      expect(n.action, '在主题中提到了你');
    });
  });

  group('私信预览', () {
    test('收到的预览去人名和对您说前缀', () {
      final c = parsePmList(conversationHtml('$actor 对您说：合成消息')).items.single;
      expect(c.preview, '合成消息');
      expect(c.peer, '合成用户');
      expect(c.peerUid, '17');
      expect(c.isOutgoing, isFalse);
      expect(c.unread, isFalse);
      expect(c.viewUrl, contains('subop=view&touid=17'));
      expect(c.timeRaw, '2026-11-15 17:40');
    });

    test('发出的预览标记方向，正文中的同名内容不删除', () {
      final c = parsePmList(
        conversationHtml('您对 $actor 说: 合成用户提到这款显示器'),
      ).items.single;
      expect(c.preview, '合成用户提到这款显示器');
      expect(c.isOutgoing, isTrue);
    });

    test('紧邻的内联节点也能分离前缀', () {
      final c = parsePmList(conversationHtml('您对$actor说：测试正文')).items.single;
      expect(c.preview, '测试正文');
      expect(c.isOutgoing, isTrue);
    });

    test('缺少方向前缀时保留预览，newpm_avt 不表示未读', () {
      final c = parsePmList(
        conversationHtml('$actor 普通摘要', attributes: 'class="cur1 newpm_avt"'),
      ).items.single;
      expect(c.preview, '合成用户 普通摘要');
      expect(c.isOutgoing, isFalse);
      expect(c.unread, isFalse);
    });

    test('独立的 newpm 类标记未读会话', () {
      final c = parsePmList(
        conversationHtml(
          '$actor 对您说：新消息',
          attributes: 'class="bbda cur1 cl newpm"',
        ),
      ).items.single;
      expect(c.unread, isTrue);
    });

    test('公共消息保留真实标题与正文', () {
      final c = parsePmList('''
        <dl id="gpmlist_8"><dd class="pm_c">
          <a href="home.php?mod=space&amp;do=pm&amp;subop=viewg&amp;pmid=8">站点公告</a> 合成正文
        </dd></dl>''', filter: PmFilter.announcePm).items.single;
      expect(c.peer, '站点公告');
      expect(c.preview, contains('合成正文'));
      expect(c.isOutgoing, isFalse);
    });
  });
}
