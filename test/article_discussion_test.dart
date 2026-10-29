/// Synthetic fixtures and fake transport only; no requests are sent to CHH.
library;

import 'dart:io';

import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/article_discussion_repository.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/parser/article_comments_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String file) => File('test_data/$file').readAsStringSync();
String page(String body) => '<html><body>$body</body></html>';
String form({
  String hash = 'fresh',
  String extra = '',
  String action = 'portal.php?mod=portalcp&amp;ac=comment',
}) => page('''
<div id="um"><strong class="vwmy"><a>测试用户</a></strong></div>
<form id="cform" action="$action" method="post">
<input type="hidden" name="formhash" value="$hash">
<input type="hidden" name="aid" value="50001">
<textarea name="message"></textarea>$extra
<button type="submit" name="commentsubmit" value="true">评论</button></form>''');

class FakeDiscussionFetcher extends ChhFetcher {
  final Map<String, String> pages;
  ChhResponse result;
  final gets = <String>[];
  final posts = <({Uri url, Map<String, String> fields})>[];
  FakeDiscussionFetcher(
    this.pages, {
    this.result = const ChhResponse(200, '<div id="messagetext">评论成功</div>'),
  });
  @override
  String get name => 'fake';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    gets.add(url.toString());
    return ChhResponse(
      200,
      pages[url.toString()] ?? '<html>missing fixture</html>',
    );
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> fields) async {
    posts.add((url: url, fields: Map.of(fields)));
    return result;
  }
}

void main() {
  group('portal comment source contracts', () {
    test('synthetic comment cid, author, quote, total and guest semantics', () {
      final result = parseArticleDiscussion(
        fixture('article_comments_synthetic.html'),
        aid: 50001,
      );
      expect(result.total, 14);
      expect(result.items.length, 2);
      expect(result.items.first.cid, 7002);
      expect(result.items.first.author, '测试读者甲');
      expect(result.items.first.authorUid, '8001');
      expect(result.items.first.time, DateTime(2001, 1, 2, 9, 30));
      expect(result.items.last.content.whereType<QuoteBlock>(), hasLength(1));
      expect(result.items.last.text, contains('合成回复正文'));
      expect(result.replyIssue!.kind, PostResultKind.loginRequired);
      expect(result.page.hasNext, isFalse);
    });

    test(
      'comment pagination does not use article pages or guessed page sizes',
      () {
        final result = parseArticleDiscussion(
          page(
            '''
<div class="vw"><div class="h"><h1 class="ph">文章</h1><p>评论 (30)</p></div></div>
<div class="pg"><a>1</a><strong>2</strong><a class="nxt" href="portal.php?mod=comment&amp;id=50001&amp;idtype=aid&amp;page=3">下一页</a></div>''',
          ),
          aid: 50001,
          page: 2,
        );
        expect(result.page.current, 2);
        expect(result.page.hasNext, isTrue);
        expect(result.total, 30);
      },
    );

    test('requote uses source BBCode and cid, not a forum pid', () {
      final quote = parseArticleCommentQuote(
        fixture('article_comment_requote_synthetic.html'),
      );
      expect(quote, startsWith('[quote]测试读者乙:'));
      expect(quote, endsWith('[/quote]'));
      expect(quote, isNot(contains('搜索')));
    });

    test(
      'confirmed thread redirect is detected, article body links are ignored',
      () {
        final thread = parseArticleThreadLink(
          fixture('article_thread_redirect_synthetic.html'),
        )!;
        expect(thread.tid, 2100);
        expect(thread.fid, 42);
        expect(
          parseArticleThreadLink(
            page(
              '<div class="vw"><div id="article_content"><a href="thread-999-1-1.html">参考原帖</a></div></div>',
            ),
          ),
          isNull,
        );
      },
    );

    test('form is scoped, captcha is detected before JS creates its input', () {
      final fresh = parseArticleCommentForm(
        form(extra: '<span id="seccode_abcd"></span>'),
        aid: 50001,
      );
      expect(fresh.issue!.kind, PostResultKind.needCaptcha);
      final available = parseArticleCommentForm(form(), aid: 50001);
      expect(available.issue, isNull);
      expect(available.form!.formhash, 'fresh');
      expect(available.form!.hidden['commentsubmit'], 'true');
      final foreign = parseArticleCommentForm(
        form(
          action:
              'https://other.example/portal.php?mod=portalcp&amp;ac=comment',
        ),
        aid: 50001,
      );
      expect(foreign.issue!.kind, PostResultKind.failed);
    });

    test(
      'existing comments or a redirect are not positive submit evidence',
      () {
        expect(
          parseArticleCommentResult(
            fixture('article_comments_synthetic.html'),
          ).kind,
          PostResultKind.unknown,
        );
        expect(
          parseArticleCommentResult('', status: 302).kind,
          PostResultKind.unknown,
        );
        expect(
          parseArticleCommentResult(page('<dd>我的评论发布成功了</dd>')).kind,
          PostResultKind.unknown,
        );
        expect(
          parseArticleCommentResult(
            page('<div id="messagetext">评论发表成功</div>'),
          ).kind,
          PostResultKind.success,
        );
        expect(
          parseArticleCommentResult(
            page('<div id="messagetext">评论失败，未成功</div>'),
          ).kind,
          PostResultKind.failed,
        );
        expect(
          parseArticleCommentResult(
            page('<div id="messagetext">两次评论间隔太短</div>'),
          ).kind,
          PostResultKind.throttled,
        );
        expect(
          parseArticleCommentResult(
            page(
              '<div id="messagetext">请先登录</div><div id="messagelogin"></div>',
            ),
          ).kind,
          PostResultKind.loginRequired,
        );
      },
    );
  });

  group('repository never sends real requests in tests', () {
    final commentsUrl = ArticleDiscussionRepository.commentsUrl(
      50001,
    ).toString();
    test(
      'load reuses cached article and loads comments only on demand',
      () async {
        final transport = FakeDiscussionFetcher({
          ChhUrls.article(50001).toString(): page(
            '<div class="vw"><h1 class="ph">文章</h1></div>',
          ),
          commentsUrl: fixture('article_comments_synthetic.html'),
        });
        final client = ChhClient(fetchers: [transport]);
        await client.getHtml(ChhUrls.article(50001));
        final result = await ArticleDiscussionRepository(client).load(50001);
        expect(result.items, hasLength(2));
        expect(
          transport.gets.where(
            (url) => url == ChhUrls.article(50001).toString(),
          ),
          hasLength(1),
        );
        expect(transport.posts, isEmpty);
      },
    );

    test(
      'reply refreshes formhash, quotes source cid and submits once',
      () async {
        final quoteUrl =
            '${ChhUrls.base}/portal.php?mod=portalcp&ac=comment&op=requote&cid=7001&aid=50001&inajax=1';
        final transport = FakeDiscussionFetcher({
          commentsUrl: form(hash: 'stale'),
          quoteUrl: fixture('article_comment_requote_synthetic.html'),
        });
        final client = ChhClient(fetchers: [transport]);
        await client.getHtml(Uri.parse(commentsUrl));
        transport.pages[commentsUrl] = form(hash: 'fresh');
        final result = await ArticleDiscussionRepository(client).reply(
          50001,
          '测试回复',
          replyTo: const ArticleComment(cid: 7001, author: '测试读者乙'),
        );
        expect(result.isSuccess, isTrue);
        expect(transport.gets.where((url) => url == commentsUrl), hasLength(2));
        expect(transport.posts, hasLength(1));
        expect(transport.posts.single.fields['formhash'], 'fresh');
        expect(
          transport.posts.single.fields['message'],
          startsWith('[quote]测试读者乙:'),
        );
        expect(transport.posts.single.fields['message'], endsWith('\n测试回复'));
        expect(transport.posts.single.fields.containsKey('pid'), isFalse);
        expect(transport.posts.single.fields.containsKey('repquote'), isFalse);
      },
    );

    test(
      'login and captcha stop before POST; uncertain response is never retried',
      () async {
        final transport = FakeDiscussionFetcher({
          commentsUrl: fixture('article_comments_synthetic.html'),
        });
        final repository = ArticleDiscussionRepository(
          ChhClient(fetchers: [transport]),
        );
        expect(
          (await repository.reply(50001, '测试')).kind,
          PostResultKind.loginRequired,
        );
        expect(transport.posts, isEmpty);
        transport.pages[commentsUrl] = form(
          extra: '<span id="seccode_pending"></span>',
        );
        expect(
          (await repository.reply(50001, '测试')).kind,
          PostResultKind.needCaptcha,
        );
        expect(transport.posts, isEmpty);
        transport.pages[commentsUrl] = form();
        transport.result = const ChhResponse(200, '<html>unknown</html>');
        expect(
          (await repository.reply(50001, '测试')).kind,
          PostResultKind.unknown,
        );
        expect(transport.posts, hasLength(1));
      },
    );

    test(
      'redirected community article goes to forum without loading portal comments',
      () async {
        final transport = FakeDiscussionFetcher({
          ChhUrls.article(50002).toString(): fixture(
            'article_thread_redirect_synthetic.html',
          ),
        });
        final result = await ArticleDiscussionRepository(
          ChhClient(fetchers: [transport]),
        ).load(50002);
        expect(result.threadId, 2100);
        expect(result.forumId, 42);
        expect(result.forumOnly, isTrue);
        expect(transport.gets, hasLength(1));
      },
    );
  });
}
