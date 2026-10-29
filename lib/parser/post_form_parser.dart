/// 发帖与回帖表单(PAGE_SPEC §6.12)
///
/// 快速回复  详情页 #fastpostform → forum.php?mod=post&action=reply&...&replysubmit=yes
/// 高级发帖  forum.php?mod=post&action=newthread&fid=N 的 #postform,action 含 topicsubmit=yes
/// 引用回复  真实楼层回复链接带 repquote / reppost,#postform 的 action 含 replysubmit=yes
///
/// 两个坑:
///   1. #postform 可能包在 #ct 外层,只查 '#ct form' 会得到零个表单,必须全 document 查。
///   2. formhash 每页刷新,所以提交前要重新取表单,不能缓存复用。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

/// 快速回复表单
PostForm? parseFastReplyForm(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final form = doc.querySelector('#fastpostform');
  if (form == null) return null;
  return _formOf(
    form,
    requiresSubject: false,
    upload: parseUploadContext(doc, html),
  );
}

/// 高级发帖 / 引用回复表单
///
/// 同一个 #postform 既可能是发主题也可能是回复,由 action 里的 submit 参数区分。
PostForm? parseAdvancedPostForm(String html) {
  // 全 document 查:#postform 实测可能在 #ct 外层
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final form = doc.querySelector('#postform');
  if (form == null) return null;

  final action = form.attributes['action'] ?? '';
  final isNewThread = action.contains('topicsubmit');
  return _formOf(
    form,
    requiresSubject: isNewThread,
    types: isNewThread ? _types(form) : const [],
    upload: parseUploadContext(doc, html),
  );
}

PostForm? _formOf(
  dom.Element form, {
  required bool requiresSubject,
  List<ThreadType> types = const [],
  UploadContext? upload,
}) {
  final action = form.attributes['action'];
  if (action == null || action.isEmpty) return null;

  // 隐藏字段原样回传。formhash 单独取出,因为每次提交都要用最新值。
  final hidden = <String, String>{};
  String? formhash;
  for (final input in form.querySelectorAll('input[type="hidden"]')) {
    final name = input.attributes['name'];
    final value = input.attributes['value'] ?? '';
    if (name == null || name.isEmpty) continue;
    if (name == 'formhash') {
      formhash = value;
      continue;
    }
    hidden[name] = value;
  }
  if (formhash == null || formhash.isEmpty) return null;

  // 部分模板把引用上下文放进隐藏 textarea；它们同样是表单提交字段。
  for (final field in form.querySelectorAll(
    'textarea[name="noticetrimstr"], textarea[name="noticeauthormsg"]',
  )) {
    hidden[field.attributes['name']!] = field.text;
  }

  return PostForm(
    action: ChhUrls.absolutize(action),
    formhash: formhash,
    hidden: hidden,
    initialMessage: form.querySelector('textarea[name="message"]')?.text ?? '',
    types: types,
    requiresSubject: requiresSubject,
    hasCaptcha: _hasCaptcha(form),
    upload: upload,
  );
}

/// 图片上传参数
///
/// hash 取表单页的 input[name=hash];uid 取页头当前用户,页头缺失时退回页面脚本里的
/// discuz_uid。大小上限与扩展名来自上传控件的脚本配置(file_size_limit 单位为 KB)。
/// 游客页或缺任一凭据时返回 null,不拿半套参数去上传。
UploadContext? parseUploadContext(dom.Document doc, String html) {
  final hash = doc.querySelector('input[name="hash"]')?.attributes['value'];
  if (hash == null || hash.isEmpty) return null;
  final link = doc.querySelector('#um strong.vwmy a')?.attributes['href'];
  final uid =
      (link == null ? null : ChhUrls.uidFromUrl(link)) ??
      RegExp(r"discuz_uid\s*=\s*'(\d+)'").firstMatch(html)?.group(1);
  if (uid == null || uid == '0') return null;
  final limit = int.tryParse(
    RegExp(r'file_size_limit\s*:\s*"(\d+)"').firstMatch(html)?.group(1) ?? '',
  );
  final exts = RegExp(
    r"var\s+imgexts\s*=\s*'([^']+)'",
  ).firstMatch(html)?.group(1);
  return UploadContext(
    uid: uid,
    hash: hash,
    maxBytes: limit == null || limit <= 0 ? null : limit * 1024,
    extensions: {
      for (final e in (exts ?? '').split(','))
        if (e.trim().isNotEmpty) e.trim().toLowerCase(),
    },
  );
}

/// 分类选项来自 #typeid;站点没给就是这个版块不分类
List<ThreadType> _types(dom.Element form) {
  final select = form.querySelector('#typeid, select[name="typeid"]');
  if (select == null) return const [];

  final out = <ThreadType>[];
  for (final option in select.querySelectorAll('option')) {
    final id = int.tryParse(option.attributes['value'] ?? '');
    final name = cleanText(option.text);
    if (id == null || id == 0 || name.isEmpty) continue;
    out.add(
      ThreadType(
        typeid: id,
        name: name,
        active: option.attributes.containsKey('selected'),
      ),
    );
  }
  return out;
}

/// 验证码控件探测
///
/// 站点的验证码由 updateseccode 脚本异步插入:原始 HTML 里只有 span#seccode_{hash}
/// 占位和加载脚本,没有输入框。只认输入框会把需要验证的版块误判成免验证,
/// 直接提交就会被站点回「验证码填写错误」。
bool _hasCaptcha(dom.Element form) {
  return form.querySelector(
            'input[name="seccodeverify"], #seccodeverify, #TencentCaptcha, '
            '[id^="seccode_"], input[name="seccodehash"], #tencentcloudcaptcha',
          ) !=
          null ||
      form.innerHtml.contains('updateseccode(');
}

/// 提交响应判定
///
/// 站点成功与失败的响应形态没做过受控验证,所以只在能确证时判成功,
/// 其余保留原文交给用户,不编造结果。
PostResult parsePostResult(String html, {int status = 200}) {
  // 写操作成功后站点常以 3xx 跳转收尾,空响应体本身就是受理信号
  if (html.trim().isEmpty && status >= 300 && status < 400) {
    return const PostResult(PostResultKind.success, '已发布');
  }

  final doc = html_parser.parse(html);
  // 提示页把「返回上一页」的脚本放在 #messagetext 里,取文字前先去掉,否则源码会混进提示
  for (final e in doc.querySelectorAll('script, style')) {
    e.remove();
  }
  final text = cleanText(doc.querySelector('#messagetext')?.text ?? '');
  final whole = cleanText(doc.body?.text ?? '');

  // Discuz 成功后用 script 跳回帖子页,这是最可靠的成功信号
  final jump = RegExp(
    r'''(?:location\.href|succeedhandle)[^'"]*['"]([^'"]*thread[^'"]*)['"]''',
  ).firstMatch(html)?.group(1);
  if (jump != null) {
    return PostResult(
      PostResultKind.success,
      text.isEmpty ? '发布成功' : text,
      tid: ChhUrls.tidFromUrl(jump),
      pid: int.tryParse(RegExp(r'pid=(\d+)').firstMatch(jump)?.group(1) ?? ''),
    );
  }
  if (text.contains('成功') || whole.contains('发布成功')) {
    return PostResult(PostResultKind.success, text.isEmpty ? '发布成功' : text);
  }

  // 跟随跳转后落在帖子页上,且没有任何提示信息 —— 这就是发布成功
  if (text.isEmpty &&
      (doc.querySelector('#postlist') != null ||
          doc.querySelector('[id^="postmessage_"]') != null)) {
    return const PostResult(PostResultKind.success, '已发布');
  }

  final body = text.isEmpty ? whole : text;
  if (body.contains('验证码')) {
    return PostResult(PostResultKind.needCaptcha, body);
  }
  if (doc.querySelector('#messagelogin') != null || body.contains('请先登录')) {
    return PostResult(PostResultKind.loginRequired, body);
  }
  if (body.contains('没有权限') || body.contains('权限不足')) {
    return PostResult(PostResultKind.permissionDenied, body);
  }
  if (body.contains('间隔') || body.contains('重复') || body.contains('过于频繁')) {
    return PostResult(PostResultKind.throttled, body);
  }
  if (text.isNotEmpty) {
    return PostResult(PostResultKind.failed, text);
  }
  return PostResult(PostResultKind.unknown, body.isEmpty ? '响应无法判定' : body);
}
