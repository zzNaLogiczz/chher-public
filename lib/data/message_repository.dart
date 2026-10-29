/// 消息域读操作:提醒与私信
///
/// 提醒(#myprompt)与私信(#pm_ntc)是站点里两套独立体系,这里按用户心智合成一个域。
/// 未读状态没有可靠证据(PAGE_SPEC §6.1),所以本层不产出未读标记,只给条目与时间。
library;

import '../core/chh_urls.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/post_form_parser.dart';
import '../parser/pm_parser.dart';
import '../parser/notice_parser.dart';

class MessageRepository {
  final ChhClient client;
  const MessageRepository(this.client);

  /// 提醒列表。category 用当前筛选参数,取不到时解析器回退到屏蔽链接的 type。
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) async {
    final html = await client.getHtml(
      ChhUrls.notice(view: view.name, type: type, page: page),
      refresh: refresh,
    );
    return parseNotices(html, filterCategory: type);
  }

  /// 沿用站点生成的下一页地址,不自己拼 isread 等参数
  Future<Paged<Notice>> noticesNext(
    Paged<Notice> prev, {
    bool refresh = false,
  }) async {
    final next = prev.nextUrl;
    if (next == null) return prev;
    return parseNotices(
      await client.getHtml(Uri.parse(next), refresh: refresh),
    );
  }

  Future<Paged<PmConversation>> conversations({
    PmFilter filter = PmFilter.privatePm,
    int page = 1,
    bool refresh = false,
  }) async {
    final name = filter == PmFilter.privatePm ? 'privatepm' : 'announcepm';
    final html = await client.getHtml(
      ChhUrls.pmList(filter: name, page: page),
      refresh: refresh,
    );
    return parsePmList(html, filter: filter);
  }

  /// 会话详情。地址来自列表项的 viewUrl,因为 plid 与 pmid 不可互推。
  ///
  /// 新消息可能追加到已有会话,所以不能只按会话 ID 判断有无更新。
  Future<List<PmMessage>> conversation(
    String viewUrl, {
    bool refresh = true,
  }) async {
    return parsePmThread(
      await client.getHtml(Uri.parse(viewUrl), refresh: refresh),
    );
  }

  /// 回复会话
  ///
  /// 与发帖同样的纪律:提交前重新取表单(formhash 每页刷新),
  /// 只做用户主动触发的单次提交,不自动重试。
  Future<PostResult> reply({
    required String viewUrl,
    required String message,
  }) async {
    final html = await client.getHtml(Uri.parse(viewUrl), refresh: true);
    final form = parsePmReplyForm(html);
    if (form == null) {
      return const PostResult(PostResultKind.failed, '这个会话当前无法回复');
    }

    final resp = await client.postForm(Uri.parse(form.action), {
      ...form.hidden,
      'formhash': form.formhash,
      'message': message,
    });
    if (resp.isBlocked) {
      return const PostResult(PostResultKind.failed, '请求被拦截,详情见运行日志');
    }
    return parsePostResult(resp.body, status: resp.status);
  }
}
