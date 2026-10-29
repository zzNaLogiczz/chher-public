/// 论坛域读操作:版块目录、帖子列表、帖子详情、导读流、搜索、标签
library;

import '../core/chh_urls.dart';
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
  const ForumRepository(this.client);

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
