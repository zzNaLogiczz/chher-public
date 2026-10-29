/// 写操作域:回帖与发主题
///
/// 三条纪律:
///   1. POST 走传输层的统一通道:直连优先、WebView 兜底。安卓 WebView 会被站点
///      防护当成移动端机器人(Chromium 客户端提示改不掉),POST 体在挑战跳转中丢失。
///   2. formhash 每页刷新,所以每次提交前重新取表单,不缓存。
///   3. 只做用户主动触发的单次提交,不自动重试、不批量操作。
library;

import '../core/app_log.dart';
import '../core/chh_urls.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../network/chh_fetcher.dart';
import '../parser/post_form_parser.dart';
import '../parser/upload_parser.dart';

class PostRepository {
  final ChhClient client;
  const PostRepository(this.client);

  /// 取快速回复表单。拿不到表单说明这个帖子当前不可回复(权限、关闭、登录墙)。
  Future<PostForm?> replyForm(int tid, {int page = 1}) async {
    final html = await client.getHtml(
      ChhUrls.thread(tid, page: page),
      refresh: true,
    );
    return parseFastReplyForm(html);
  }

  /// 回帖
  ///
  /// [quotePid] 非空即取该楼的高级引用表单，保留站点生成的引用和通知字段。
  /// [images] 是已上传图片的附件编号:快速回复表单没有附件字段,带图时同样走完整回复表单。
  Future<PostResult> reply({
    required int tid,
    required int fid,
    required String message,
    int? quotePid,
    int page = 1,
    List<String> images = const [],
  }) async {
    // 引用回复与快速回复用的是两套表单,先按场景取对应的那一套
    final advanced = quotePid != null || images.isNotEmpty;
    final pageUrl = _replyPage(tid: tid, fid: fid, pid: quotePid, page: page);
    final form = advanced
        ? parseAdvancedPostForm(await client.getHtml(pageUrl, refresh: true))
        : await replyForm(tid, page: page);
    if (form == null) {
      return const PostResult(PostResultKind.failed, '当前无法回复这个帖子');
    }

    var body = message;
    if (quotePid != null) {
      final quote = form.hidden['noticetrimstr'] ?? '';
      final initial = form.initialMessage;
      final target = form.hidden['reppid'];
      if ((target != null && target != '$quotePid') ||
          (quote.trim().isEmpty && initial.trim().isEmpty)) {
        return const PostResult(PostResultKind.failed, '引用加载失败，请重试');
      }
      // noticetrimstr 由服务端拼接；正文预填引用则由客户端保留，只发送一次。
      if (initial.trim().isNotEmpty && initial.trim() != quote.trim()) {
        body = '${initial.trimRight()}\n\n$message';
      }
    }

    return _submit(form, page: pageUrl, {
      'message': withImages(body, images),
      'subject': form.hidden['subject'] ?? '',
      'usesig': form.hidden['usesig'] ?? '1',
      'replysubmit': 'yes',
      if (advanced) ..._plainText,
      ...attachmentFields(images),
    });
  }

  /// 完整回复页。地址形态来自真实楼层的回复链接;[pid] 非空时是引用回复。
  Uri _replyPage({
    required int tid,
    required int fid,
    int? pid,
    int page = 1,
  }) => Uri.parse(
    '${ChhUrls.base}/forum.php?mod=post&action=reply'
    '&fid=$fid&tid=$tid${pid == null ? '' : '&repquote=$pid'}&extra=&page=$page',
  );

  /// 回帖时上传图片要用的参数,来自完整回复页
  Future<UploadContext?> replyUploadContext({
    required int tid,
    required int fid,
  }) async {
    final html = await client.getHtml(_replyPage(tid: tid, fid: fid));
    return parseAdvancedPostForm(html)?.upload;
  }

  /// 上传一张已处理好的图片,成功返回附件编号
  ///
  /// 只上传、不发布:附件要等正文提交时带上 attachnew 字段才归入帖子。
  Future<UploadOutcome> uploadImage(
    UploadContext context, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final url = Uri.parse(
      '${ChhUrls.base}/misc.php?mod=swfupload&operation=upload'
      '&uid=${context.uid}&hash=${context.hash}&simple=1&type=image',
    );
    final resp = await client.postMultipart(
      url,
      {'uid': context.uid, 'hash': context.hash},
      UploadFile(
        field: 'Filedata',
        filename: filename,
        contentType: contentType,
        bytes: bytes,
      ),
    );
    if (resp.rejectedBeforeApp) {
      return UploadFailed(resp.status <= 0 ? '网络不可用，图片没有上传' : '上传请求被拦截，请稍后重试');
    }
    final outcome = parseUploadResponse(resp.body, status: resp.status);
    if (outcome is UploadFailed) AppLog.w('UPLOAD', outcome.message);
    return outcome;
  }

  Uri _newThreadPage(int fid) =>
      Uri.parse('${ChhUrls.base}/forum.php?mod=post&action=newthread&fid=$fid');

  /// 取发主题表单。顺带给出这个版块的分类选项。
  Future<PostForm?> newThreadForm(int fid) async => parseAdvancedPostForm(
    await client.getHtml(_newThreadPage(fid), refresh: true),
  );

  /// 发主题
  Future<PostResult> createThread({
    required int fid,
    required String subject,
    required String message,
    int? typeid,
    List<String> images = const [],
  }) async {
    final form = await newThreadForm(fid);
    if (form == null) {
      return const PostResult(PostResultKind.failed, '当前版块无法发表主题');
    }

    return _submit(form, page: _newThreadPage(fid), {
      'subject': subject,
      'message': withImages(message, images),
      if (typeid != null && typeid > 0) 'typeid': '$typeid',
      'topicsubmit': 'yes',
      ..._plainText,
      ...attachmentFields(images),
    });
  }

  /// 正文是纯文本 BBCode,不是编辑器的所见即所得 HTML;否则站点会按 HTML 转换,换行丢失
  static const _plainText = {'wysiwyg': '0'};

  /// 统一提交路径
  ///
  /// [entered] 是用户填写的字段,其余隐藏字段照表单原样回传。
  /// 需要验证码时不直连提交:腾讯滑块的票据离开验证页面就失效,只能在站点真实页面
  /// [page] 里填好这些字段、由用户完成验证后提交,结果里带上这次提交交给界面层。
  Future<PostResult> _submit(
    PostForm form,
    Map<String, String> entered, {
    required Uri page,
  }) async {
    if (form.hasCaptcha) {
      return PostResult(
        PostResultKind.needCaptcha,
        '需要完成人机验证',
        web: WebSubmission(page, entered),
      );
    }

    final resp = await client.postForm(Uri.parse(form.action), {
      ...form.hidden,
      ...entered,
      'formhash': form.formhash,
    });
    if (resp.rejectedBeforeApp) {
      AppLog.e(
        'POST',
        '被拦 ${AppLog.response(resp.status, resp.body)} err=${resp.error ?? '-'}',
      );
      return const PostResult(PostResultKind.failed, '请求被拦截,详情见运行日志');
    }

    // 提交成功会改变帖子内容,清掉缓存避免用户看到旧页面
    final result = parsePostResult(resp.body, status: resp.status);
    AppLog.i('POST', '结果 ${result.kind.name} ${result.message}');
    if (result.isSuccess) client.clearCache();
    // 表单里没认出验证码、站点却要求验证:这次没有发出去,同样改到真实页面完成
    if (result.kind == PostResultKind.needCaptcha) {
      return PostResult(
        PostResultKind.needCaptcha,
        result.message,
        web: WebSubmission(page, entered),
      );
    }
    return result;
  }
}

/// 把已上传的图片接在正文后面,按选择顺序排列
String withImages(String message, List<String> aids) {
  if (aids.isEmpty) return message;
  final tags = aids.map((aid) => '[attachimg]$aid[/attachimg]').join('\n');
  final text = message.trimRight();
  return text.isEmpty ? tags : '$text\n\n$tags';
}

/// 提交正文时声明这些附件归入本帖
Map<String, String> attachmentFields(List<String> aids) => {
  for (final aid in aids) 'attachnew[$aid][description]': '',
};
