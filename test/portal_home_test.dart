/// 门户首页编辑内容解析
///
/// 从零编写的合成 HTML，所有条目、正文、日期和图片路径均为示例。
/// 幻灯片里 swiper 会克隆首尾片,必须去重。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chh_app/parser/portal_home_parser.dart';
import 'package:chh_app/parser/portal_parser.dart';

String _page(String body) =>
    '<html><head><title>x</title></head><body>$body</body></html>';

const _home = '''
<div id="newBannerSwiper" class="swiper-container">
  <div class="swiper-wrapper">
    <div class="swiper-slide swiper-slide-duplicate">
      <img class="img-cover" src="https://static.chiphell.com/portal/a.jpg">
      <a href="article-50002-1.html"><p>示例桌面规划</p></a>
    </div>
    <div class="swiper-slide swiper-slide-active">
      <img class="img-cover" src="https://static.chiphell.com/portal/a.jpg">
      <a href="article-50002-1.html"><p>示例桌面规划</p></a>
    </div>
    <div class="swiper-slide">
      <img class="img-cover" src="https://static.chiphell.com/portal/b.jpg">
      <a href="article-50003-1.html"><p>示例出行记录</p></a>
    </div>
  </div>
</div>

<div id="portal_block_673_content">
  <ul>
    <li><a href="https://www.chiphell.com/forum-317-1.htm">快讯</a></li>
    <li><a href="thread-900601-1-1.html">示例设备快讯甲</a></li>
    <li><a href="thread-900602-1-1.html">示例设备快讯乙</a></li>
  </ul>
</div>

<div id="portal_block_675_content">
  <ul>
    <li>
      <a class="tm01 cl" href="article-50001-1.html">
        <img src="https://static.chiphell.com/portal/c.jpg"></a>
      <div class="tmpad cl">
        <a class="tm03 cl" href="article-50001-1.html">示例主板评测</a>
        <div class="avimain cl">
          <span>2001-01-02</span><span class="avie">7556</span>
          <span class="arep">11</span>
          <a class="asort" href="portal.php?mod=list&catid=15">主板</a>
        </div>
        <div class="tm04 cl">合成评测摘要：用于验证封面、栏目与日期提取</div>
      </div>
    </li>
  </ul>
</div>''';

void main() {
  group('幻灯片', () {
    test('克隆片去重后只剩原始条目', () {
      final b = parsePortalHighlights(_page(_home)).banners;
      expect(b.length, 2);
      expect(b.map((e) => e.aid), [50002, 50003]);
    });

    test('标题取 a 里的 p,封面取 img', () {
      final b = parsePortalHighlights(_page(_home)).banners.first;
      expect(b.title, '示例桌面规划');
      expect(b.coverUrl, endsWith('/portal/a.jpg'));
    });
  });

  group('快讯', () {
    test('只收论坛帖,区块标题指向版块会被过滤', () {
      final n = parsePortalHighlights(_page(_home)).news;
      expect(n.length, 2);
      expect(n.first.tid, 900601);
      expect(n.map((e) => e.title), isNot(contains('快讯')));
    });
  });

  group('评测', () {
    test('标题封面摘要栏目时间都要', () {
      final r = parsePortalHighlights(_page(_home)).reviews.single;
      expect(r.aid, 50001);
      expect(r.title, '示例主板评测');
      expect(r.coverUrl, endsWith('/portal/c.jpg'));
      expect(r.summary, contains('合成评测摘要'));
      expect(r.categoryName, '主板');
      expect(r.timeRaw, '2001-01-02');
    });
  });

  test('空页面不产生内容,也不抛异常', () {
    final h = parsePortalHighlights(_page('<div id="ct">没有门户区块</div>'));
    expect(h.isEmpty, isTrue);
  });

  _articleRoutingTests();
}

/// 门户条目的落地页分流
///
/// 合成测试分别覆盖文章页面和重定向后的帖子页面。
/// 一律按文章解析就会得到空白页,这正是首页 banner 点进去全白的原因。
void _articleRoutingTests() {
  group('文章还是帖子', () {
    test('落到帖子页时识别出 tid,优先取 canonical', () {
      final html = _page('''
<link rel="canonical" href="https://www.chiphell.com/thread-900002-1-1.html">
<div id="postlist"><table id="pid90000101"></table></div>''');

      expect(threadBehindArticle(html), 900002);
    });

    test('没有 canonical 时从正文里的帖子链接兜底', () {
      final html = _page(
        '<div id="postlist"></div><a href="thread-900004-1-1.html">x</a>',
      );
      expect(threadBehindArticle(html), 900004);
    });

    test('真文章不会被误判成帖子', () {
      final html = _page(
        '<h1 class="ph">示例主板评测</h1>'
        '<table><tr><td id="article_content">正文</td></tr></table>',
      );
      expect(threadBehindArticle(html), isNull);
    });

    test('落地页标题优先取 thread_subject', () {
      expect(
        titleOfPage(_page('<h1 id="thread_subject">示例旅行记录</h1>')),
        '示例旅行记录',
      );
    });

    test('没有主题节点时从 title 里截站点后缀之前的部分', () {
      expect(
        titleOfPage(
          '<html><head><title>某篇文章 - 原创分享(新) - Chiphell</title></head>'
          '<body></body></html>',
        ),
        '某篇文章',
      );
    });
  });
}
