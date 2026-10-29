/// Verified against public portal comment pages and portal_comment_requote JS.
library;

import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/article_discussion.dart';
import '../models/models.dart';
import 'content_walker.dart';
import 'dom_utils.dart';
import 'portal_parser.dart';

ArticleDiscussion parseArticleDiscussion(
  String html, {
  required int aid,
  int page = 1,
  ArticleThreadLink? thread,
}) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);
  final seen = <int>{};
  final comments = <ArticleComment>[];
  for (final item in doc.querySelectorAll(r'dl[id^="comment_"][id$="_li"]')) {
    final cid = int.tryParse(
      RegExp(r'^comment_(\d+)_li$').firstMatch(item.id)?.group(1) ?? '',
    );
    final body = item.querySelector('dd');
    if (cid == null || !seen.add(cid) || body == null) continue;
    final author = findUserLink(item.querySelector('dt'));
    final rawTime = cleanText(item.querySelector('dt span.xg1')?.text);
    final avatar = item.querySelector('.avt img')?.attributes['src'];
    comments.add(
      ArticleComment(
        cid: cid,
        author: cleanText(author?.el.text),
        authorUid: author?.uid,
        avatarUrl: avatar == null ? null : ChhUrls.absolutize(avatar),
        timeRaw: rawTime.isEmpty ? null : rawTime,
        time: ChhUrls.parseTime(rawTime),
        content: parseContentBlocks(body),
        text: cleanText(body.text),
      ),
    );
  }
  final header = doc.querySelector('.vw > .h');
  final totalText = cleanText(header?.querySelector('p')?.text);
  final total =
      int.tryParse(
        RegExp(r'评论\s*[（(]\s*(\d+)').firstMatch(totalText)?.group(1) ?? '',
      ) ??
      int.tryParse(cleanText(doc.querySelector('#_commentnum')?.text));
  final reply = parseArticleCommentForm(html, aid: aid);
  if (header == null && comments.isEmpty && reply.form == null) {
    throw const PageMessage(PageMessageKind.message, '未找到文章评论');
  }
  return ArticleDiscussion(
    aid: aid,
    title: cleanText(header?.querySelector('h1.ph')?.text),
    items: comments,
    page: parsePager(doc, fallbackPage: page),
    total: total,
    threadId: thread?.tid,
    forumId: thread?.fid,
    threadUrl: thread?.url,
    replyIssue: reply.issue,
  );
}

/// The full comments page supplies aid + formhash and commentsubmit=true.
/// Never borrow the search form's hash or invent forum pid/repquote fields.
({PostForm? form, PostResult? issue}) parseArticleCommentForm(
  String html, {
  required int aid,
}) {
  final doc = html_parser.parse(html);
  final pageMessage = detectPageMessage(doc);
  if (pageMessage != null) {
    return (
      form: null,
      issue: PostResult(switch (pageMessage.kind) {
        PageMessageKind.loginRequired => PostResultKind.loginRequired,
        PageMessageKind.permissionDenied => PostResultKind.permissionDenied,
        _ => PostResultKind.failed,
      }, pageMessage.text),
    );
  }
  final loggedIn =
      currentUserName(doc) != null ||
      (doc.head
              ?.querySelectorAll('script')
              .any(
                (s) => RegExp(
                  r'''discuz_uid\s*=\s*['"]?([1-9]\d*)''',
                ).hasMatch(s.text),
              ) ??
          false);
  if (!loggedIn) {
    return (
      form: null,
      issue: const PostResult(PostResultKind.loginRequired, '请先登录后发表评论'),
    );
  }
  final form = doc.querySelector('form#cform');
  if (form == null) {
    return (
      form: null,
      issue: const PostResult(PostResultKind.permissionDenied, '当前文章无法发表评论'),
    );
  }
  final action = Uri.tryParse(
    ChhUrls.absolutize(form.attributes['action'] ?? ''),
  );
  if (action == null ||
      action.host != Uri.parse(ChhUrls.base).host ||
      action.path != '/portal.php' ||
      action.queryParameters['mod'] != 'portalcp' ||
      action.queryParameters['ac'] != 'comment') {
    return (
      form: null,
      issue: const PostResult(PostResultKind.failed, '评论表单地址无法确认'),
    );
  }
  final fields = <String, String>{};
  for (final input in form.querySelectorAll('input[type="hidden"]')) {
    final name = input.attributes['name'];
    if (name != null && name.isNotEmpty) {
      fields[name] = input.attributes['value'] ?? '';
    }
  }
  for (final button in form.querySelectorAll('button[type="submit"][name]')) {
    fields[button.attributes['name']!] = button.attributes['value'] ?? '';
  }
  final hash = fields.remove('formhash');
  if (hash == null || hash.isEmpty || fields['aid'] != '$aid') {
    return (
      form: null,
      issue: const PostResult(PostResultKind.failed, '评论表单已失效，请刷新后重试'),
    );
  }
  final captcha =
      form.querySelector(
            '[name="seccodeverify"], [id^="seccode_"], #TencentCaptcha',
          ) !=
          null ||
      form
          .querySelectorAll('script')
          .any((s) => s.text.contains('updateseccode('));
  final parsed = PostForm(
    action: action.toString(),
    formhash: hash,
    hidden: fields,
    hasCaptcha: captcha,
  );
  return (
    form: parsed,
    issue: captcha
        ? const PostResult(PostResultKind.needCaptcha, '站点要求验证码，请在网页版完成本次评论')
        : null,
  );
}

/// Only explicit article-to-thread metadata or the actual redirected thread
/// qualifies. Arbitrary forum links inside an article are not associations.
ArticleThreadLink? parseArticleThreadLink(String html) {
  final doc = html_parser.parse(html);
  final redirectedTid = threadBehindArticle(html);
  if (redirectedTid != null) {
    int? fid;
    for (final a in doc.querySelectorAll('#pt a[href]')) {
      fid = ChhUrls.fidFromUrl(a.attributes['href'] ?? '') ?? fid;
    }
    return ArticleThreadLink(
      tid: redirectedTid,
      fid: fid,
      url: '${ChhUrls.base}/thread-$redirectedTid-1-1.html',
    );
  }
  final form = doc.querySelector('#cform');
  final idtype = form
      ?.querySelector('input[name="idtype"]')
      ?.attributes['value'];
  final tid = int.tryParse(
    form?.querySelector('input[name="id"]')?.attributes['value'] ?? '',
  );
  if (idtype == 'tid' && tid != null && tid > 0) {
    return ArticleThreadLink(
      tid: tid,
      url: '${ChhUrls.base}/thread-$tid-1-1.html',
    );
  }
  for (final a in doc.querySelectorAll('.vw .o a[href]')) {
    if (!RegExp(r'原帖|相关帖子|论坛讨论|查看帖子').hasMatch(cleanText(a.text))) continue;
    final href = a.attributes['href'] ?? '';
    final linkedTid = ChhUrls.tidFromUrl(href);
    if (linkedTid != null) {
      return ArticleThreadLink(
        tid: linkedTid,
        fid: ChhUrls.fidFromUrl(href),
        url: ChhUrls.absolutize(href),
      );
    }
  }
  return null;
}

/// Public requote GET returns BBCode in #wp (or an AJAX XML CDATA response).
String? parseArticleCommentQuote(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);
  final text = doc.querySelector('#wp')?.text ?? doc.body?.text ?? html;
  return RegExp(
    r'\[quote\][\s\S]*?\[/quote\]',
    caseSensitive: false,
  ).firstMatch(text)?.group(0);
}

/// A returned comment list, empty redirect or arbitrary "成功" in another
/// person's comment does not prove that our submission succeeded.
PostResult parseArticleCommentResult(String html, {int status = 200}) {
  final doc = html_parser.parse(html);
  final text = cleanText(doc.querySelector('#messagetext')?.text);
  final message = detectPageMessage(doc);
  if (message?.kind == PageMessageKind.loginRequired) {
    return PostResult(PostResultKind.loginRequired, message!.text);
  }
  if (message?.kind == PageMessageKind.permissionDenied) {
    return PostResult(PostResultKind.permissionDenied, message!.text);
  }
  if (text.contains('验证码')) return PostResult(PostResultKind.needCaptcha, text);
  if (RegExp(r'间隔|重复|过于频繁').hasMatch(text)) {
    return PostResult(PostResultKind.throttled, text);
  }
  if (status >= 200 &&
      status < 300 &&
      RegExp(r'(?:评论|回复|操作|提交).{0,8}成功').hasMatch(text) &&
      !RegExp(r'失败|不成功|未成功').hasMatch(text)) {
    return PostResult(PostResultKind.success, text);
  }
  if (text.isNotEmpty) return PostResult(PostResultKind.failed, text);
  return const PostResult(PostResultKind.unknown, '站点未明确确认评论结果，请查看评论后再决定是否重试');
}
