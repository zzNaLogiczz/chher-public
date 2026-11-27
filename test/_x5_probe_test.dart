// 临时对照工具：用 App 解析器分别解析本地 X3.5 / X5.0 抓取页，输出摘要 JSON。用完删除。
import 'dart:convert';
import 'dart:io';

import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/poll.dart';
import 'package:chh_app/parser/archiver_parser.dart';
import 'package:chh_app/parser/article_comments_parser.dart';
import 'package:chh_app/parser/dom_utils.dart';
import 'package:chh_app/parser/favorite_parser.dart';
import 'package:chh_app/parser/forum_index_parser.dart';
import 'package:chh_app/parser/guide_parser.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/parser/misc_parser.dart';
import 'package:chh_app/parser/notice_parser.dart';
import 'package:chh_app/parser/pm_parser.dart';
import 'package:chh_app/parser/poll_parser.dart';
import 'package:chh_app/parser/portal_home_parser.dart';
import 'package:chh_app/parser/portal_list_parser.dart';
import 'package:chh_app/parser/portal_parser.dart';
import 'package:chh_app/parser/post_action_parser.dart';
import 'package:chh_app/parser/post_form_parser.dart';
import 'package:chh_app/parser/rating_parser.dart';
import 'package:chh_app/parser/search_result_parser.dart';
import 'package:chh_app/parser/space_parser.dart';
import 'package:chh_app/parser/thread_list_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

String blocks(List<ContentBlock> b) {
  final counts = <String, int>{};
  for (final x in b) {
    counts.update(x.runtimeType.toString(), (v) => v + 1, ifAbsent: () => 1);
  }
  return counts.entries.map((e) => '${e.key}x${e.value}').join(',');
}

Object? page(PageInfo p) => {'cur': p.current, 'next': p.hasNext};

Map<String, Object?> poll(ThreadPoll? p) => p == null
    ? {'poll': null}
    : {
        'multiple': p.multiple,
        'max': p.maxChoices,
        'voters': p.participantCount,
        'voted': p.alreadyVoted,
        'closed': p.closed,
        'action': p.action?.toString(),
        'options': [for (final o in p.options) '${o.id}:${o.text}:${o.votes}:${o.mine}'],
      };

Map<String, Object?> form(PostForm? f) => f == null
    ? {'form': null}
    : {
        'action': f.action,
        'formhash': f.formhash.isNotEmpty,
        'hidden': (f.hidden.keys.toList()..sort()),
        'initialMessageLen': f.initialMessage.length,
        'types': f.types.length,
        'requiresSubject': f.requiresSubject,
        'captcha': f.hasCaptcha,
        'upload': f.upload == null
            ? null
            : {'uid': f.upload!.uid, 'hash': f.upload!.hash.isNotEmpty, 'max': f.upload!.maxBytes, 'ext': (f.upload!.extensions.toList()..sort())},
      };

Map<String, Object?> threadSummary(ThreadSummary t) => {
      'tid': t.tid,
      'title': t.title,
      'type': t.typeName,
      'author': t.author,
      'uid': t.authorUid,
      'created': t.createdAtRaw,
      'replies': t.replies,
      'views': t.views,
      'last': t.lastPostUser,
      'lastTime': t.lastPostTimeRaw,
      'img': t.hasImages,
    };

Object? run(String name, String html) {
  final pageUrl = Uri.parse('http://lab/forum.php?mod=viewthread&tid=1');
  switch (name) {
    case 'forum_index' || 'forum_index_guest':
      final c = parseForumIndex(html);
      return {
        'categories': c.length,
        'forums': [for (final g in c) for (final f in g.forums) '${f.fid}:${f.name}:${f.threadCount}:${f.postCount}:${f.lastPostTimeRaw}'],
      };
    case 'forumdisplay':
      final p = parseThreadList(html);
      return {'page': page(p.page), 'threads': [for (final t in p.threads) threadSummary(t)], 'types': parseThreadTypes(html).length};
    case 'thread_p1' || 'thread_p2' || 'thread_tester' || 'thread_guest' || 'thread_author' || 'thread_poll_voted' || 'thread_poll_open':
      final tid = name.startsWith('thread_poll') ? 2 : 1;
      final d = parseThread(html, tid: tid);
      return {
        'title': d.title,
        'fid': d.fid,
        'forum': d.forumName,
        'views': d.viewCount,
        'replies': d.replyCount,
        'favs': d.favoriteCount,
        'cookiePrefix': d.cookiePrefix != null,
        'page': page(d.page),
        'poll': d.poll == null ? null : poll(d.poll),
        'pollStandalone': name.startsWith('thread_poll') ? poll(parseThreadPoll(html, tid: tid)) : null,
        'fastReply': form(parseFastReplyForm(html)),
        'posts': [
          for (final p in d.posts)
            {
              'pid': p.pid,
              'floor': '${p.floor}${p.floorIsKnown ? '' : '?'}',
              'author': p.author,
              'uid': p.authorUid,
              'gid': p.authorGroupId,
              'group': p.authorGroupName,
              'avatar': p.avatarUrl?.replaceAll(RegExp(r'https?://[^/]+'), ''),
              'time': p.timeRaw,
              'hasTime': p.time != null,
              'content': blocks(p.content),
              'images': [for (final b in p.content) if (b is ImageBlock) b.url.replaceAll(RegExp(r'https?://[^/]+'), '')],
              'quote': [for (final b in p.content) if (b is QuoteBlock) '${b.source}|ref=${b.reference != null}'],
              'notes': p.notes.length,
              'rating': p.rating == null ? null : '${p.rating!.summary.join('/')}|entries=${p.rating!.entries.length}|url=${p.rating!.detailsUrl != null}',
              'comments': [for (final c in p.comments) '${c.author}:${c.text}'],
              'actions': {
                'comment': p.actions.commentUrl != null,
                'rate': p.actions.ratingUrl != null,
                'append': p.actions.supplementUrl != null,
              },
            },
        ],
      };
    case 'viewratings':
      return [for (final r in parseRatingDetails(html)) '${r.user}:${r.uid}:${r.score}:${r.reason}:${r.credit}:${r.timeRaw}'];
    case 'guide_new':
      final p = parseGuide(html);
      return {'page': page(p.page), 'threads': [for (final t in p.threads) threadSummary(t)]};
    case 'search':
      final p = parseSearchResult(html);
      return {'page': page(p.page), 'next': p.nextUrl, 'rows': [for (final t in p.rows) threadSummary(t)]};
    case 'tag':
      final p = parseTagThreads(html);
      return {'page': page(p.page), 'items': [for (final t in p.items) threadSummary(t)]};
    case 'archiver':
      final a = parseArchiverThread(html);
      return a == null ? null : {'title': a.title, 'time': a.time?.toIso8601String(), 'author': a.author, 'excerpt': a.excerpt};
    case 'space_tester' || 'space_profile':
      final u = parseUserProfile(html, uid: '2');
      return {
        'name': u.name, 'avatar': u.avatarUrl != null, 'group': u.group, 'gid': u.groupId, 'credits': u.credits,
        'threads': u.threads, 'replies': u.replies, 'friends': u.friends, 'reg': u.registeredAt, 'last': u.lastVisitAt, 'online': u.onlineHours,
      };
    case 'my_threads' || 'my_replies':
      final p = parseMyThreads(html);
      return {
        'page': page(p.page),
        'items': [for (final t in p.items) '${t.tid}:${t.title}:${t.forumName}:${t.forumFid}:${t.replies}:${t.views}:${t.lastUser}:snips=${t.replySnippets.length}'],
      };
    case 'notice_admin' || 'notice_tester' || 'notice_system':
      final p = parseNotices(html);
      return {
        'page': page(p.page),
        'items': [for (final n in p.items) '${n.category}|${n.actor}|${n.actorUid}|${n.action}|${n.title}|${n.tid}|${n.pid}|${n.occurredAtText}|${n.summary}'],
      };
    case 'pm_list':
      final p = parsePmList(html);
      return {'page': page(p.page), 'items': [for (final c in p.items) '${c.peer}|${c.peerUid}|${c.preview}|out=${c.isOutgoing}|${c.timeRaw}|${c.viewUrl}']};
    case 'pm_thread':
      return {
        'messages': [for (final m in parsePmThread(html)) '${m.author}|${m.authorUid}|${m.text}|self=${m.fromSelf}|${m.timeRaw}'],
        'replyForm': form(parsePmReplyForm(html)),
      };
    case 'favorite':
      final p = parseFavorites(html);
      return {'page': page(p.page), 'items': [for (final f in p.items) '${f.favid}|${f.title}|${f.url}|${f.tid}|${f.timeRaw}']};
    case 'medal' || 'medal_log':
      return [for (final m in parseMedals(html)) '${m.id}:${m.name}'];
    case 'credit':
      final c = parseCredit(html);
      return {'summary': c.summary, 'recentRows': c.recent.rows.length};
    case 'usergroup':
      final l = parseUserGroupLevel(html);
      return l?.toString();
    case 'portal_home' || 'portal_feed_p1':
      final h = parsePortalHighlights(html);
      final f = parsePortalFeed(html);
      return {
        'banners': h.banners.length, 'news': h.news.length, 'reviews': h.reviews.length,
        'categories': [for (final c in parsePortalCategories(html)) '${c.catid}:${c.name}'],
        'feed': [for (final a in f.items) '${a.aid}:${a.title}:${a.catid}:${a.timeRaw}:${a.summary}'],
        'page': page(f.page),
      };
    case 'portal_list':
      final f = parsePortalCategoryList(html);
      return {'page': page(f.page), 'items': [for (final a in f.items) '${a.aid}:${a.title}:${a.categoryName}:${a.timeRaw}']};
    case 'article':
      final c = parsePortalContent(html, aid: 1);
      final link = parseArticleThreadLink(html);
      return {
        'type': c.runtimeType.toString(),
        'detail': c is ArticleContent ? {'title': c.detail.title, 'meta': c.detail.metaRaw, 'cat': c.detail.categoryName, 'content': blocks(c.detail.content), 'page': page(c.detail.page)} : c.toString(),
        'threadLink': link?.toString(),
      };
    case 'article_comments':
      final d = parseArticleDiscussion(html, aid: 1);
      return {
        'title': d.title, 'total': d.total, 'forumOnly': d.forumOnly, 'issue': d.replyIssue?.message,
        'items': [for (final c in d.items) '${c.cid}|${c.author}|${c.authorUid}|${c.timeRaw}|${c.text}'],
      };
    case 'newthread_form' || 'reply_quote_form':
      return form(parseAdvancedPostForm(html));
    case 'rate_form':
      final f = parsePostRateForm(html, tid: 1, pid: 5, pageUrl: pageUrl);
      return f == null ? null : {'action': f.action.toString(), 'formhash': f.formhash.isNotEmpty, 'hidden': f.hidden.keys.toList()..sort(), 'scores': [for (final s in f.scoreTypes) '${s.fieldName}:${s.label}:${s.min}..${s.max}:rem=${s.remaining}'], 'reasons': f.reasons.length};
    case 'comment_form':
      final f = parsePostCommentForm(html, tid: 1, pid: 5, pageUrl: pageUrl);
      return f == null ? null : {'action': f.action.toString(), 'formhash': f.formhash.isNotEmpty, 'hidden': f.hidden.keys.toList()..sort(), 'max': f.maxLength};
    case 'postappend_form':
      final f = parsePostSupplementForm(html, tid: 1, pid: 1, pageUrl: pageUrl, sessionIdentity: '');
      return f == null ? {'form': null, 'message': parseInteractionPageError(html)?.message} : {'action': f.action.toString(), 'hidden': f.hidden.keys.toList()..sort(), 'max': f.maxLength};
    case 'favorite_form':
      final f = parseFavoriteForm(html);
      return f == null ? null : {'action': f.action, 'hidden': f.hidden.keys.toList()..sort()};
    case 'nopermission':
      final m = detectPageMessage(html_parser.parse(html));
      return m == null ? null : '${m.kind}:${m.text}';
  }
  return 'NO_PARSER';
}

void main() {
  final root = Platform.environment['X5_CAPTURES'];
  test('x5 probe', () {
    final captures = root!;
    final out = <String, Object?>{};
    for (final ver in ['x35', 'x50']) {
      final dir = Directory('$captures/$ver');
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.html')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final res = <String, Object?>{};
      for (final f in files) {
        final name = f.uri.pathSegments.last.replaceAll('.html', '');
        final html = f.readAsStringSync();
        Object? r;
        try {
          r = run(name, html);
        } catch (e) {
          r = {'EXCEPTION': '${e.runtimeType}: $e'.split('\n').first};
        }
        final header = parseHeaderBadges(html);
        res[name] = {
          'result': r,
          'header': header == null ? null : {'user': header.userName, 'uid': header.uid, 'notices': header.notices, 'pm': header.messages},
          'currentUser': currentUserName(html_parser.parse(html)),
        };
      }
      out[ver] = res;
    }
    File('$captures/probe.json').writeAsStringSync(JsonEncoder.withIndent(' ', (o) => o.toString()).convert(out));
  }, skip: root == null ? '缺少本地 X5_CAPTURES 样本' : false);
}
