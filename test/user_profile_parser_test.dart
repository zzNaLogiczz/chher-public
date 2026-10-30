import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/space_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String _profileHtml({
  bool activity = true,
  bool tip = true,
  bool counts = true,
  bool statistics = true,
  bool avatar = true,
}) =>
    '''
<html><head><title>用户主页</title></head><body>
${avatar ? '<div class="avt"><img src="uc_server/data/avatar/90_avatar_small.jpg"></div>' : ''}
<div class="bm_c u_profile">
 <div class="pbm mbm bbda cl">
  <h2 class="mbn">示例用户<span class="xw0">(UID: 900001)</span></h2>
  <ul class="pf_l cl pbm mbm"><li><em>邮箱状态</em>已验证</li></ul>
  ${counts ? '''<ul class="cl bbda pbm mbm"><li>
   <em class="xg2">统计信息</em>
   <a href="home.php?mod=space&amp;uid=900001&amp;do=thread">主题数 616</a>
   <span class="pipe">|</span><a href="home.php?mod=space&amp;uid=900001&amp;do=friend">好友数 15</a>
   <span class="pipe">|</span><a href="home.php?mod=space&amp;uid=900001&amp;do=thread">回帖数 3,112</a>
  </li></ul>''' : ''}
 </div>
 <div class="pbm mbm bbda cl"><h2 class="mbn">用户认证</h2><a href="#"><img alt="手机认证"/></a></div>
 ${activity ? '''<div class="pbm mbm bbda cl">
  <h2 class="mbn">活跃概况</h2>
  <ul><li><em class="xg1">用户组&nbsp;&nbsp;</em><span class="xi2" ${tip ? 'tip="积分 2,329, 距离下一级还需 1,171 积分"' : ''}><a href="home.php?mod=spacecp&amp;ac=usergroup&amp;gid=40">权天使</a></span></li></ul>
  <ul id="pbbs" class="pf_l">
   <li><em>在线时间</em> 2,845 小时 </li><li><em>注册时间</em>2013-6-1 21:59</li>
   <li><em>最后访问</em>2026-10-30 11:43</li><li><em>上次活动时间</em>2026-10-30 11:43</li>
   <li><em>上次发表时间</em>2026-10-29 22:46</li><li><em>所在时区</em>(GMT +08:00) 北京, 香港</li>
  </ul>
 </div>''' : ''}
 ${statistics ? '''<div id="psts" class="cl"><h2 class="mbn">统计信息</h2><ul class="pf_l">
  <li><em>已用空间</em>   0 B </li><li><em>积分</em> 2,329 </li><li><em>邪恶指数</em>1 583 </li><li><em>门户文章</em>0 </li>
 </ul></div>''' : ''}
</div></body></html>
''';

void _expectNoActivity(UserProfile profile) {
  expect(profile.group, isNull);
  expect(profile.groupId, isNull);
  expect(profile.nextLevelCredits, isNull);
  expect(profile.onlineHours, isNull);
  expect(profile.registeredAt, isNull);
  expect(profile.lastVisitAt, isNull);
  expect(profile.lastPostAt, isNull);
}

void main() {
  group('用户组门槛解析', () {
    test('目标组名与首个积分下限', () {
      final level = parseUserGroupLevel('''<ul id="tba" class="tb c2">
        <li id="c2">晋级用户组 - 能天使</li></ul><div class="tscr">
        <table class="tdat"><tr><th><span class="notice">积分下限 2500</span>
        <span class="notice">积分下限 3500</span></th></tr></table></div>''');
      expect(level?.name, '能天使');
      expect(level?.lowerCredits, 2500);
    });

    test('负数门槛和全页正则兜底', () {
      final level = parseUserGroupLevel('''<ul id="tba"><li id="c2">
        晋级用户组 - 新手</li></ul><div>积分下限 -50</div>''');
      expect(level, (name: '新手', lowerCredits: -50));
    });

    test('消息页、需登录、空页、缺数据都返回 null', () {
      for (final html in [
        '',
        '<div id="messagetext"><p>请先登录</p></div>',
        '<form id="loginform"></form>',
        '<ul id="tba"><li id="c2">晋级用户组 - 能天使</li></ul>',
        '<span class="notice">积分下限 2500</span>',
      ]) {
        expect(parseUserGroupLevel(html), isNull);
      }
    });

    test('个人页用户组链接解析 gid 41', () {
      final profile = parseUserProfile(
        _profileHtml().replaceAll('gid=40', 'gid=41'),
        uid: '900001',
      );
      expect(profile.groupId, 41);
    });

    test('无效 gid 保持 null', () {
      for (final gid in ['0', '-1', 'unknown']) {
        expect(
          parseUserProfile(
            _profileHtml().replaceAll('gid=40', 'gid=$gid'),
            uid: '900001',
          ).groupId,
          isNull,
        );
      }
    });
  });

  group('结构化个人资料', () {
    test('真实结构解析全部字段，名字不含 UID，链接按文字前缀拆分', () {
      final profile = parseUserProfile(_profileHtml(), uid: '900001');
      expect(profile.uid, '900001');
      expect(profile.name, '示例用户');
      expect(profile.group, '权天使');
      expect(profile.groupId, 40);
      expect(profile.nextLevelCredits, 1171);
      expect(profile.onlineHours, 2845);
      expect(profile.credits, 2329);
      expect(profile.evil, 1583);
      expect(profile.threads, 616);
      expect(profile.replies, 3112);
      expect(profile.friends, 15);
      expect(profile.registeredAt, '2013-6-1 21:59');
      expect(profile.lastVisitAt, '2026-10-30 11:43');
      expect(profile.lastPostAt, '2026-10-29 22:46');
      expect(profile.portalArticles, 0);
      expect(profile.avatarUrl, ChhUrls.avatar('900001', size: 'big'));
      expect(profile.avatarUrl, isNot(contains('small')));
    });

    test('缺活跃概况时仅省略对应字段', () {
      final profile = parseUserProfile(
        _profileHtml(activity: false),
        uid: '900001',
      );
      _expectNoActivity(profile);
      expect(profile.credits, 2329);
      expect(profile.threads, 616);
    });

    test('缺 tip 时保留用户组，不补下一级积分', () {
      final profile = parseUserProfile(_profileHtml(tip: false), uid: '900001');
      expect(profile.group, '权天使');
      expect(profile.nextLevelCredits, isNull);
    });

    test('缺统计信息时对应计数为空', () {
      final profile = parseUserProfile(
        _profileHtml(counts: false, statistics: false),
        uid: '900001',
      );
      expect(profile.credits, isNull);
      expect(profile.evil, isNull);
      expect(profile.threads, isNull);
      expect(profile.replies, isNull);
      expect(profile.friends, isNull);
      expect(profile.portalArticles, isNull);
      expect(profile.group, '权天使');
      expect(profile.onlineHours, 2845);
    });

    test('游客空页字段为空且仍提供大头像地址', () {
      final profile = parseUserProfile(
        '<html><body></body></html>',
        uid: '900001',
      );
      _expectNoActivity(profile);
      expect(profile.credits, isNull);
      expect(profile.evil, isNull);
      expect(profile.threads, isNull);
      expect(profile.replies, isNull);
      expect(profile.friends, isNull);
      expect(profile.portalArticles, isNull);
      expect(profile.avatarUrl, ChhUrls.avatar('900001', size: 'big'));
    });

    test('没有头像图片时仍使用大头像地址', () {
      final profile = parseUserProfile(
        _profileHtml(avatar: false),
        uid: '900001',
      );
      expect(profile.avatarUrl, ChhUrls.avatar('900001', size: 'big'));
    });

    test('未知数字不补零，空白和千分位可解析', () {
      final profile = parseUserProfile(
        _profileHtml()
            .replaceAll('1,171 积分', '1&nbsp;171 积分')
            .replaceAll('2,845 小时', '2&nbsp;845 小时')
            .replaceAll('> 2,329 <', '> 未知 <')
            .replaceAll('回帖数 3,112', '回帖数 3&nbsp;112'),
        uid: '900001',
      );
      expect(profile.nextLevelCredits, 1171);
      expect(profile.onlineHours, 2845);
      expect(profile.replies, 3112);
      expect(profile.credits, isNull);
    });
  });
}
