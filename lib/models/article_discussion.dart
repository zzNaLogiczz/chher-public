/// Portal comment IDs (cid) are independent of forum post IDs (pid).
library;

import 'models.dart';

class ArticleComment {
  final int cid;
  final String author;
  final String? authorUid;
  final String? avatarUrl;
  final DateTime? time;
  final String? timeRaw;
  final List<ContentBlock> content;
  final String text;

  const ArticleComment({
    required this.cid,
    required this.author,
    this.authorUid,
    this.avatarUrl,
    this.time,
    this.timeRaw,
    this.content = const [],
    this.text = '',
  });
}

class ArticleDiscussion {
  final int aid;
  final String title;
  final List<ArticleComment> items;
  final PageInfo page;
  final int? total;
  final int? threadId;
  final int? forumId;
  final String? threadUrl;

  /// True only when the article URL actually landed on a forum thread.
  final bool forumOnly;

  /// Null only when the current source form permits a normal submission.
  final PostResult? replyIssue;
  bool get canReply => replyIssue == null;

  /// 文章作者:发布者 uid 与发布者/原作者的名字;都没有时不提供"只看作者"
  final String? authorUid;
  final Set<String> authorNames;
  bool get knowsAuthor => authorUid != null || authorNames.isNotEmpty;

  /// 这条评论是不是文章作者本人发的
  bool byAuthor(ArticleComment comment) =>
      (authorUid != null && comment.authorUid == authorUid) ||
      authorNames.contains(comment.author.trim());

  const ArticleDiscussion({
    required this.aid,
    required this.title,
    required this.items,
    required this.page,
    this.total,
    this.threadId,
    this.forumId,
    this.threadUrl,
    this.forumOnly = false,
    this.replyIssue,
    this.authorUid,
    this.authorNames = const {},
  });

  ArticleDiscussion withAuthors({String? uid, Set<String> names = const {}}) =>
      ArticleDiscussion(
        aid: aid,
        title: title,
        items: items,
        page: page,
        total: total,
        threadId: threadId,
        forumId: forumId,
        threadUrl: threadUrl,
        forumOnly: forumOnly,
        replyIssue: replyIssue,
        authorUid: uid,
        authorNames: names,
      );
}

class ArticleThreadLink {
  final int tid;
  final int? fid;
  final String url;
  const ArticleThreadLink({required this.tid, required this.url, this.fid});
}
