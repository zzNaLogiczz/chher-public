/// Portal comments are loaded on demand and submitted only by a user action.
library;

import '../core/chh_urls.dart';
import '../models/article_discussion.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/article_comments_parser.dart';
import '../parser/portal_parser.dart';

class ArticleDiscussionRepository {
  final ChhClient client;
  const ArticleDiscussionRepository(this.client);

  static Uri commentsUrl(int aid, {int page = 1}) => Uri.parse(
    '${ChhUrls.base}/portal.php?mod=comment&id=$aid&idtype=aid&page=$page',
  );

  Future<ArticleDiscussion> load(
    int aid, {
    int page = 1,
    bool refresh = false,
  }) async {
    // The reader already fetched page 1; this normally reuses its 90s cache.
    final articleHtml = await client.getHtml(
      ChhUrls.article(aid),
      refresh: refresh,
    );
    final thread = parseArticleThreadLink(articleHtml);
    if (threadBehindArticle(articleHtml) != null && thread != null) {
      return ArticleDiscussion(
        aid: aid,
        title: titleOfPage(articleHtml),
        items: const [],
        page: const PageInfo(current: 1, hasNext: false),
        threadId: thread.tid,
        forumId: thread.fid,
        threadUrl: thread.url,
        forumOnly: true,
        replyIssue: const PostResult(PostResultKind.failed, '请进入原帖参与讨论'),
      );
    }
    final html = await client.getHtml(
      commentsUrl(aid, page: page),
      refresh: refresh,
    );
    final authors = parseArticleAuthors(articleHtml);
    return parseArticleDiscussion(
      html,
      aid: aid,
      page: page,
      thread: thread,
    ).withAuthors(uid: authors.uid, names: authors.names);
  }

  Future<PostResult> reply(
    int aid,
    String message, {
    ArticleComment? replyTo,
  }) async {
    if (message.trim().isEmpty) {
      return const PostResult(PostResultKind.failed, '请输入评论内容');
    }
    var body = message;
    if (replyTo != null) {
      final quoteHtml = await client.getHtml(
        Uri.parse(
          '${ChhUrls.base}/portal.php?mod=portalcp&ac=comment&op=requote'
          '&cid=${replyTo.cid}&aid=$aid&inajax=1',
        ),
        refresh: true,
      );
      String? quote;
      try {
        quote = parseArticleCommentQuote(quoteHtml);
      } on PageMessage catch (message) {
        return PostResult(switch (message.kind) {
          PageMessageKind.loginRequired => PostResultKind.loginRequired,
          PageMessageKind.permissionDenied => PostResultKind.permissionDenied,
          _ => PostResultKind.failed,
        }, message.text);
      }
      if (quote == null) {
        return const PostResult(PostResultKind.failed, '无法取得引用内容，请刷新评论后重试');
      }
      body = '$quote\n$message';
    }
    // Fetch the hash after requote as well, so no intervening request can
    // replace the current session/form before the single submit.
    final html = await client.getHtml(commentsUrl(aid), refresh: true);
    final fresh = parseArticleCommentForm(html, aid: aid);
    if (fresh.issue != null) return fresh.issue!;
    final form = fresh.form!;
    // Exactly one submission. Never retry an uncertain result here.
    final response = await client.postForm(Uri.parse(form.action), {
      ...form.hidden,
      'formhash': form.formhash,
      'message': body,
    });
    if (response.status <= 0 ||
        response.status == 567 ||
        response.rejectedBeforeApp) {
      return const PostResult(PostResultKind.failed, '评论请求未完成，请检查连接与站点状态');
    }
    final result = parseArticleCommentResult(
      response.body,
      status: response.status,
    );
    if (result.isSuccess) client.clearCache();
    return result;
  }
}
