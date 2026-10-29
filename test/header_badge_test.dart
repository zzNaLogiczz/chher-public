/// 页头未读计数单测
///
/// 关键约束(PAGE_SPEC §6.1):`.a` 类不能当未读状态,无未读时页头同样带 showmenu。
/// 所以只认数字;取不到数字就是没有未读,宁可不显示也不编造。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chh_app/parser/header_parser.dart';

String _page(String body) =>
    '<html><head><title>x</title></head><body>$body</body></html>';

void main() {
  test('从页头数字取未读', () {
    final b = parseHeaderBadges(
      _page('''
<div id="um">
  <a id="myprompt" class="a showmenu">提醒<span class="num">3</span></a>
  <a id="pm_ntc" class="a showmenu">消息<span class="num">2</span></a>
</div>'''),
    )!;

    expect(b.notices, 3);
    expect(b.messages, 2);
    expect(b.total, 5);
  });

  test('带 showmenu 但没有数字时不算未读', () {
    final b = parseHeaderBadges(
      _page('''
<div id="um">
  <a id="myprompt" class="a showmenu">提醒</a>
  <a id="pm_ntc" class="a showmenu">消息</a>
</div>'''),
    )!;

    expect(b.hasAny, isFalse);
  });

  test('数字直接写在文案里也能取到', () {
    final b = parseHeaderBadges(
      _page('<div id="um"><a id="myprompt">提醒(7)</a></div>'),
    )!;
    expect(b.notices, 7);
  });

  test('缺少某一侧入口时该侧计为 0', () {
    final b = parseHeaderBadges(
      _page(
        '<div id="um"><a id="myprompt"><span class="num">1</span></a></div>',
      ),
    )!;
    expect(b.notices, 1);
    expect(b.messages, 0);
  });

  test('没有登录态页头时返回 null,调用方保持原值', () {
    // 游客页不能把已有的未读抹成零
    expect(parseHeaderBadges(_page('<div id="ct">游客页</div>')), isNull);
  });

  test('相同计数视为相等,避免无谓刷新', () {
    const a = HeaderBadges(notices: 1, messages: 2);
    const b = HeaderBadges(notices: 1, messages: 2);
    expect(a, b);
  });

  _accountTests();
}

/// 账号与头像
///
/// 头像地址由 uid 推出:站点自己就用这个形态,本例使用虚构 UID。
/// 不走 uc_server/avatar.php —— 避免依赖该端点的网络可用性。
void _accountTests() {
  group('页头账号', () {
    test('取出账号名与 uid', () {
      final b = parseHeaderBadges(
        '<html><body><div id="um">'
        '<strong class="vwmy"><a href="space-uid-100101.html">示例作者甲</a></strong>'
        '</div></body></html>',
      )!;

      expect(b.userName, '示例作者甲');
      expect(b.uid, '100101');
    });

    test('头像地址按 uid 补零到 9 位后 3/2/2/2 切分', () {
      final b = parseHeaderBadges(
        '<html><body><div id="um">'
        '<strong class="vwmy"><a href="space-uid-10002.html">x</a></strong>'
        '</div></body></html>',
      )!;

      expect(
        b.avatarUrl,
        'https://www.chiphell.com/data/avatar/000/01/00/02_avatar_middle.jpg',
      );
    });

    test('没有账号时头像为空,不编造地址', () {
      final b = parseHeaderBadges(
        '<html><body><div id="um">游客</div></body></html>',
      )!;
      expect(b.userName, isNull);
      expect(b.avatarUrl, isNull);
    });
  });

  _headerVariantTests();
}

/// 页头模板变体
///
/// 文档记的是 #um strong.vwmy a,但模板会改。这里锁住兜底路径。
void _headerVariantTests() {
  group('页头变体', () {
    test('没有 #um 时用退出登录链接反查页头', () {
      final b = parseHeaderBadges('''
<html><body>
  <div class="topnav">
    <a href="home.php?mod=space&uid=100101">示例作者甲</a>
    <a href="member.php?mod=logging&action=logout&formhash=abc">退出</a>
  </div>
</body></html>''');

      expect(b, isNotNull);
      expect(b!.userName, '示例作者甲');
      expect(b.uid, '100101');
    });

    test('vwmy 不在 strong 里也能取到', () {
      final b = parseHeaderBadges(
        '<html><body><div id="um">'
        '<span class="vwmy"><a href="space-uid-1.html">测试通知用户</a></span>'
        '</div></body></html>',
      )!;
      expect(b.userName, '测试通知用户');
    });

    test('认不出账号时留下页头摘要供排查', () {
      final b = parseHeaderBadges(
        '<html><body><div id="um">某种没见过的页头结构</div></body></html>',
      )!;
      expect(b.userName, isNull);
      expect(b.headerSample, contains('没见过'));
    });

    test('游客页仍然返回 null,不误判为登录态', () {
      expect(
        parseHeaderBadges('<html><body><div id="ct">游客</div></body></html>'),
        isNull,
      );
    });
  });

  _syntheticHeaderTests();
}

/// 合成页头结构：覆盖头像、账号与未读提示的组合
///
/// div#um
///   div.avt.y > a > img.user_avatar
///   p > strong.vwmy > a "测试账号"  href=space-uid-100001.html
///     a#pm_ntc > em.prompt_news_0
///     a#myprompt.a.showmenu "提醒"
void _syntheticHeaderTests() {
  const synthetic = '''
<html><body><div id="um">
  <div class="avt y"><a href="space-uid-100001.html">
    <img src="./data/avatar/000/10/00/01_avatar_small.jpg" class="user_avatar"></a></div>
  <p>
    <strong class="vwmy"><a href="space-uid-100001.html" target="_blank">测试账号</a></strong>
    <span class="pipe">|</span>
    <a id="myitem" class="showmenu">我的</a>
    <a href="home.php?mod=space&do=pm" id="pm_ntc"><em class="prompt_news_0"></em>消息</a>
    <a href="home.php?mod=space&do=notice" id="myprompt" class="a showmenu">提醒</a>
    <span id="myprompt_check"></span>
    <a href="member.php?mod=logging&action=logout">退出</a>
  </p>
</div></body></html>''';

  group('合成页头', () {
    test('账号与 uid', () {
      final b = parseHeaderBadges(synthetic)!;
      expect(b.userName, '测试账号');
      expect(b.uid, '100001');
    });

    test('头像取 middle 尺寸,页头自带的 small 在高倍屏上会糊', () {
      final b = parseHeaderBadges(synthetic)!;
      expect(
        b.avatarUrl,
        'https://www.chiphell.com/data/avatar/000/10/00/01_avatar_middle.jpg',
      );
      // 页头原始地址仍然保留,uid 取不到时作兜底
      expect(b.avatarSrc, endsWith('01_avatar_small.jpg'));
    });

    test('prompt_news_0 表示没有未读', () {
      final b = parseHeaderBadges(synthetic)!;
      expect(b.messages, 0);
      expect(b.hasAny, isFalse);
    });

    test('prompt_news_N 的后缀就是未读数', () {
      final b = parseHeaderBadges(
        synthetic.replaceAll('prompt_news_0', 'prompt_news_5'),
      )!;
      expect(b.messages, 5);
    });

    test('带 a showmenu 但无未读时不亮角标', () {
      // 模板兼容：无未读时 #myprompt 同样带 class="a showmenu"
      final b = parseHeaderBadges(synthetic)!;
      expect(b.notices, 0);
    });
  });
}
