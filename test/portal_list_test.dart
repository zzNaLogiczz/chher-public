/// 门户文章列表解析
///
/// 使用从零编写的合成 HTML，验证门户列表与栏目列表的结构差异。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chh_app/parser/portal_list_parser.dart';

String _page(String body) =>
    '<html><head><title>x</title></head><body>$body</body></html>';

void main() {
  group('全部文章流', () {
    final html = _page('''
<div id="threadulid">
  <section id="normalthread_50003">
    <li>
      <a href="article-50003-1.html" class="tm01 cl">
        <img src="https://static.chiphell.com/synthetic/portal/feed-cover.jpg">
      </a>
      <div class="tmpad cl">
        <a href="article-50003-1.html" class="tm03 cl">示例游戏设备开箱</a>
        <div class="avart">测试作者 2001/01/02</div>
        <div class="tm04 cl">用于测试老游戏设备条目摘要的合成文字。</div>
      </div>
    </li>
  </section>
</div>
<div class="pgs"><div class="pg"><strong>1</strong>
  <a class="nxt" href="portal.php?page=2">下一页</a></div></div>''');

    test('条目 id 后缀是 aid', () {
      expect(parsePortalFeed(html).items.single.aid, 50003);
    });

    test('标题取 a.tm03,不会取成区块标题', () {
      expect(parsePortalFeed(html).items.single.title, '示例游戏设备开箱');
    });

    test('封面是 static 直链', () {
      expect(
        parsePortalFeed(html).items.single.coverUrl,
        startsWith('https://static.chiphell.com/synthetic/portal/'),
      );
    });

    test('摘要来自 .tm04', () {
      expect(parsePortalFeed(html).items.single.summary, contains('老游戏'));
    });

    test('能翻页', () {
      final r = parsePortalFeed(html);
      expect(r.page.hasNext, isTrue);
      expect(r.nextUrl, contains('page=2'));
    });
  });

  group('栏目文章列表', () {
    final html = _page(
      '''
<div class="bm_c xld">
  <dl class="bbda cl">
    <dt class="xs2"><a href="article-50001-1.html" class="xi2">示例硬件评测</a></dt>
    <dd class="xs2 cl">
      <div class="atc"><a href="article-50001-1.html">
        <img src="https://static.chiphell.com/synthetic/portal/category-cover.jpg" class="tn"></a></div>
      这是栏目文章的合成摘要，用于检查正文与封面文本的分离。
    </dd>
    <dd> 分类: <label><a href="portal.php?mod=list&catid=15" class="xi2">主板</a></label>
      <span class="xg1"> 2001-01-02 03:04</span></dd>
  </dl>
</div>
<div class="pgs"><div class="pg"><strong>1</strong>
  <a class="nxt" href="portal.php?mod=list&catid=1&page=2">下一页</a></div></div>''',
    );

    test('解析出 aid 标题封面', () {
      final a = parsePortalCategoryList(html).items.single;
      expect(a.aid, 50001);
      expect(a.title, contains('示例硬件评测'));
      expect(a.coverUrl, contains('category-cover.jpg'));
    });

    test('摘要剔掉封面区的文本', () {
      final a = parsePortalCategoryList(html).items.single;
      expect(a.summary, contains('合成摘要'));
      expect(a.summary, isNot(contains('分类')));
    });

    test('带出栏目名与 catid', () {
      final a = parsePortalCategoryList(html).items.single;
      expect(a.categoryName, '主板');
      expect(a.catid, 15);
      expect(a.timeRaw, '2001-01-02 03:04');
    });
  });

  group('栏目清单', () {
    test('按 catid 去重,过滤过长文案', () {
      final cats = parsePortalCategories(
        _page('''
<a href="https://www.chiphell.com/portal.php?mod=list&catid=1">评测</a>
<a href="portal.php?mod=list&catid=1">评测</a>
<a href="portal.php?mod=list&catid=15">主板</a>
<a href="portal.php?mod=list&catid=99">一个非常长的并不像栏目名的文案</a>'''),
      );

      expect(cats.map((c) => c.catid), [1, 15]);
      expect(cats.first.name, '评测');
    });
  });
}
