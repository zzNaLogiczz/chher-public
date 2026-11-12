import 'dart:io';

import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/background_parser.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/parser/portal_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String _large(String html) => '$html<!--${'x' * backgroundParseThreshold}-->';

const _article = '''
<html><head><title>本地文章 - CHH</title></head><body>
<div id="pt"><a href="portal.php?mod=list&amp;catid=2">硬件</a></div>
<div class="vw"><div class="h"><h1 class="ph">本地文章</h1>
<p class="xg1">发布者: 示例作者</p></div></div>
<div id="article_content"><p>文章正文</p><img src="/fixture.jpg"></div>
<div class="pg"><a>1</a><strong>2</strong><a class="nxt" href="article-1-3.html">下一页</a></div>
</body></html>''';

void main() {
  for (final large in [false, true]) {
    String size(String html) => large ? _large(html) : html;
    test(
      'article dispatch preserves content and pagination large=$large',
      () async {
        final content = await parsePortalContentAsync(size(_article), aid: 7);
        expect(content, isA<ArticleContent>());
        final article = (content as ArticleContent).detail;
        expect(article.aid, 7);
        expect(article.title, '本地文章');
        expect(article.metaRaw, '发布者: 示例作者');
        expect(article.categoryName, '硬件');
        expect(article.content.whereType<TextBlock>().single.text, '文章正文');
        expect(
          article.content.whereType<ImageBlock>().single.url,
          endsWith('/fixture.jpg'),
        );
        expect(article.page.current, 2);
        expect(article.page.hasNext, isTrue);
      },
    );

    test(
      'article redirects preserve actual thread and subject large=$large',
      () async {
        final content = await parsePortalContentAsync(
          size(
            '''
<html><head><link rel="canonical" href="thread-912-1-1.html"></head>
<body><div id="postlist"></div><h1 id="thread_subject">源帖标题</h1></body></html>''',
          ),
          aid: 7,
        );
        expect(content, isA<ThreadContent>());
        expect((content as ThreadContent).tid, 912);
        expect(content.title, '源帖标题');
      },
    );

    test('thread parser preserves DTOs and source page large=$large', () async {
      final html = size(
        File('test_data/thread_synthetic.html').readAsStringSync(),
      );
      final direct = parseThread(html, tid: 900001, fallbackPage: 3);
      final result = await parseThreadAsync(html, tid: 900001, fallbackPage: 3);
      expect(result.tid, direct.tid);
      expect(result.title, direct.title);
      expect(result.page.current, direct.page.current);
      expect(result.posts.map((p) => p.pid), direct.posts.map((p) => p.pid));
      expect(result.posts.first.author, direct.posts.first.author);
      expect(
        result.posts.first.content.length,
        direct.posts.first.content.length,
      );
    });

    test(
      'permission errors keep their type across dispatch large=$large',
      () async {
        final html = size(
          '<html><body><div id="messagetext">请先登录</div>'
          '<div id="messagelogin"></div></body></html>',
        );
        final login = isA<PageMessage>().having(
          (e) => e.kind,
          'kind',
          PageMessageKind.loginRequired,
        );
        await expectLater(
          parsePortalContentAsync(html, aid: 7),
          throwsA(login),
        );
        await expectLater(parseThreadAsync(html, tid: 900001), throwsA(login));
      },
    );
  }

  test(
    'repository dispatch preserves article cache and refresh semantics',
    () async {
      final fetcher = _LocalPage(_large(_article));
      final repository = PortalRepository(ChhClient(fetchers: [fetcher]));
      await repository.openArticle(7, page: 2);
      await repository.openArticle(7, page: 2);
      expect(fetcher.urls, hasLength(1));
      expect(fetcher.urls.single.path, '/article-7-2.html');
      final result = await repository.openArticle(7, page: 2, refresh: true);
      expect(fetcher.urls, hasLength(2));
      expect((result as ArticleContent).detail.page.current, 2);
    },
  );

  test('thread dispatch preserves author URL and fallback page', () async {
    final fetcher = _LocalPage(
      _large(
        '<html><body><h1 id="thread_subject">本地帖</h1>'
        '<div id="postlist"></div></body></html>',
      ),
    );
    final repository = ForumRepository(ChhClient(fetchers: [fetcher]));
    final result = await repository.thread(
      42,
      page: 4,
      authorUid: '1001',
      refresh: true,
    );
    expect(fetcher.urls.single.queryParameters['authorid'], '1001');
    expect(fetcher.urls.single.queryParameters['page'], '4');
    expect(result.page.current, 4);
    final source =
        'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=42&pid=77';
    await repository.threadAtUrl(source, tid: 42);
    expect(fetcher.urls.last.toString(), source);
  });

  test('single-DOM article entry agrees with legacy article entry', () {
    final old = parseArticle(_article, aid: 7);
    final current =
        (parsePortalContent(_article, aid: 7) as ArticleContent).detail;
    expect(current.title, old.title);
    expect(current.page.current, old.page.current);
    expect(current.content.length, old.content.length);
  });

  test('large header supports nested complete um before long body', () {
    final result = parseHeaderBadges(
      _large('''<div id="um">
<div class="avt"><img src="/avatar.jpg"></div>
<p><strong class="vwmy"><a href="space-uid-1001.html">示例账号</a></strong>
<a id="myprompt"><em class="prompt_news_3"></em>提醒</a>
<a id="pm_ntc">私信(2)</a></p></div>'''),
    )!;
    expect(result.uid, '1001');
    expect(result.notices, 3);
    expect(result.messages, 2);
  });

  test('late badge outside header retains whole-document lookup', () {
    final result = parseHeaderBadges(
      '${_large('<div id="um">页头</div>')}'
      '<a id="pm_ntc">私信(8)</a>',
    )!;
    expect(result.messages, 8);
  });

  test('badge spanning prefix boundary keeps its complete count', () {
    const header = '<div id="um">页头</div>';
    final padding = ' ' * (32 * 1024 - header.length - 5);
    final html = '$header$padding<a id="pm_ntc">私信(12)</a>${' ' * 70000}';
    expect(parseHeaderBadges(html)!.messages, 12);
    final openBadge = '$header<a id="pm_ntc">${' ' * 70000}私信(14)</a>';
    expect(parseHeaderBadges(openBadge)!.messages, 14);
  });

  test('truncated header and logout template retain full parser fallback', () {
    final open = parseHeaderBadges(
      '<div id="um">${' ' * 70000}'
      '<a id="myprompt">提醒(6)</a></div>',
    )!;
    expect(open.notices, 6);
    final logout = parseHeaderBadges(
      _large('''<div class="topnav">
<a href="space-uid-1001.html">示例账号</a>
<a href="member.php?mod=logging&amp;action=logout">退出</a>
<a id="myprompt">提醒(4)</a></div>'''),
    )!;
    expect(logout.uid, '1001');
    expect(logout.notices, 4);
  });
}

class _LocalPage extends ChhFetcher {
  final String html;
  final urls = <Uri>[];
  _LocalPage(this.html);
  @override
  String get name => 'local-parser-fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    urls.add(url);
    return ChhResponse(200, html);
  }
}
