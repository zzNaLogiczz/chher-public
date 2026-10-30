/// 论坛域读操作:版块目录、帖子列表、帖子详情、导读流、搜索、标签
library;

import 'package:html/parser.dart' as html;

import '../core/chh_urls.dart';
import '../core/md5.dart';
import '../network/chh_session.dart';
import '../network/cookie_jar.dart';
import '../parser/dom_utils.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/forum_index_parser.dart';
import '../parser/guide_parser.dart';
import '../parser/misc_parser.dart';
import '../parser/search_result_parser.dart';
import '../parser/thread_list_parser.dart';
import '../parser/thread_parser.dart';

class ForumRepository {
  final ChhClient client;
  final ChhSession? session;
  const ForumRepository(this.client, {this.session});

  String? get cookiePrefix => session?.cookiePrefix;

  Future<void> unlockPost({
    required int pid,
    required String password,
    required String cookiePrefix,
  }) async {
    if (cookiePrefix.isEmpty) throw StateError('缺少 Cookie 前缀');
    await (session ?? ChhSession(client)).setSiteCookie(
      '${cookiePrefix}postpw_$pid',
      md5(password),
    );
  }

  Future<bool> verifyForumPassword(int fid, String password) async {
    final url = ChhUrls.threadList(fid);
    final page = await client.getHtml(url, refresh: true);
    final doc = html.parse(page);
    final form = doc.querySelector('form[action*="action=pwverify"]');
    if (form == null) return false;
    final action = url.resolve(form.attributes['action'] ?? '');
    // 密码只提交给站点实际给出的同站表单。
    if (action.origin != url.origin ||
        action.queryParameters['fid'] != '$fid') {
      return false;
    }
    final response = await client.postForm(action, {
      'formhash':
          form.querySelector('input[name="formhash"]')?.attributes['value'] ??
          '',
      'pw': password,
      'loginsubmit': 'true',
    });
    if (response.isBlocked || response.status >= 400) return false;
    final result = html.parse(response.body);
    if (result.querySelector('form[action*="action=pwverify"]') != null) {
      return false;
    }
    final message = detectPageMessage(result);
    if (message != null &&
        (message.kind != PageMessageKind.message ||
            !message.text.contains('成功'))) {
      return false;
    }
    final prefixes = [
      RegExp(r"cookiepre\s*=\s*'([^']*)'").firstMatch(page)?.group(1),
      RegExp(r"cookiepre\s*=\s*'([^']*)'").firstMatch(response.body)?.group(1),
      cookiePrefix,
    ];
    final prefix = prefixes
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .firstOrNull;
    if (prefix == null) throw StateError('缺少 Cookie 前缀');
    final name = '${prefix}fidpw$fid';
    String? value;
    for (final raw in response.setCookies) {
      final cookie = CookieJar.parseSetCookie(raw);
      if (cookie?.name == name) value = cookie!.value;
    }
    await (session ?? ChhSession(client)).setSiteCookie(
      name,
      value ?? Uri.encodeComponent(password),
    );
    return true;
  }

  Future<List<ForumCategory>> forumIndex({bool refresh = false}) async {
    return parseForumIndex(
      await client.getHtml(ChhUrls.forumIndex(), refresh: refresh),
    );
  }

  /// 版块帖子列表。typeid 走分类筛选,filter 走精华与排序。
  ///
  /// 越界页码会被站点静默回落到第 1 页,所以解析结果里的 current 才是真相。
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async {
    final url = ChhUrls.threadListFiltered(
      fid,
      page: page,
      typeid: typeid,
      filter: filter,
      orderby: orderby,
    );
    return parseThreadList(await client.getHtml(url, refresh: refresh));
  }

  /// 版块的分类标签。与帖子列表同一个页面,这里单独取一次供筛选条使用。
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async {
    final html = await client.getHtml(
      ChhUrls.threadList(fid),
      refresh: refresh,
    );
    return parseThreadTypes(html);
  }

  /// 帖子详情。authorUid 非空即「只看作者」,页面结构与常规详情页全同构。
  Future<ThreadDetail> thread(
    int tid, {
    int page = 1,
    String? authorUid,
    bool refresh = false,
  }) async {
    final url = authorUid == null
        ? ChhUrls.thread(tid, page: page)
        : ChhUrls.threadByAuthor(tid, authorUid, page: page);
    return parseThread(
      await client.getHtml(url, refresh: refresh),
      tid: tid,
      fallbackPage: page,
    );
  }

  /// 按站点给出的跳转地址取帖子
  ///
  /// 提醒里的 `goto=findpost&ptid=X&pid=Y` 会跳到目标楼层所在的那一页。
  /// 不要假设回复在第一页,也不能自己算页码 —— 跟随跳转,再以落地页的分页为准。
  Future<ThreadDetail> threadAtUrl(
    String url, {
    required int tid,
    bool refresh = true,
  }) async {
    final html = await client.getHtml(Uri.parse(url), refresh: refresh);
    return parseThread(html, tid: tid, fallbackPage: 1);
  }

  /// 导读流。view=new / hot 游客可用,view=my 需登录,否则站点返回登录提示页。
  Future<ThreadListPage> guide({
    String view = 'new',
    String? type,
    int page = 1,
    bool refresh = false,
  }) async {
    final html = await client.getHtml(
      ChhUrls.guide(view: view, type: type, page: page),
      refresh: refresh,
    );
    return parseGuide(html);
  }

  /// 搜索。站点先 302 到 searchid 页,由 fetcher 自动跟随。
  Future<SearchResultPage> search(
    String keyword, {
    bool refresh = false,
  }) async {
    return parseSearchResult(
      await client.getHtml(ChhUrls.search(keyword), refresh: refresh),
    );
  }

  /// 翻页必须沿用站点给出的 nextUrl,它带着 searchid 与排序参数
  Future<SearchResultPage> searchNext(
    SearchResultPage prev, {
    bool refresh = false,
  }) async {
    final next = prev.nextUrl;
    if (next == null) return prev;
    return parseSearchResult(
      await client.getHtml(Uri.parse(next), refresh: refresh),
    );
  }

  Future<Paged<ThreadSummary>> tag(int id, {bool refresh = false}) async {
    return parseTagThreads(
      await client.getHtml(ChhUrls.tag(id), refresh: refresh),
    );
  }
}
