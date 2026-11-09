library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import '../core/chh_urls.dart';
import '../models/models.dart';
import '../models/post_interaction.dart';
import 'dom_utils.dart';

String interactionHtml(String raw) {
  final sections = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').allMatches(raw);
  if (sections.isNotEmpty) return sections.map((m) => m.group(1)!).join();
  // Some AJAX responses encode the HTML as XML text rather than CDATA.
  final root = html.parse(raw).querySelector('root');
  return root != null && root.children.isEmpty ? root.text : raw;
}

dom.Document _document(String raw) => html.parse(interactionHtml(raw));
Uri interactionPageUrl(PostInteractionKind kind, int tid, int pid) => Uri.parse(
  '${ChhUrls.base}/forum.php?mod=misc&action=${kind == PostInteractionKind.comment ? 'comment' : 'rate'}&tid=$tid&pid=$pid&infloat=yes&inajax=1${kind == PostInteractionKind.rating ? '&handlekey=rate&ajaxtarget=fwin_content_rate' : '&extra=&handlekey=comment&ajaxtarget=fwin_content_comment'}',
);
Uri interactionSubmitUrl(
  PostInteractionKind kind,
  int tid,
  int pid,
) => Uri.parse(
  kind == PostInteractionKind.comment
      ? '${ChhUrls.base}/forum.php?mod=post&action=reply&comment=yes&tid=$tid&pid=$pid&extra=&commentsubmit=yes&infloat=yes&inajax=1'
      : '${ChhUrls.base}/forum.php?mod=misc&action=rate&ratesubmit=yes&infloat=yes&inajax=1',
);

bool isInteractionUrl(
  Uri uri,
  PostInteractionKind kind,
  int tid,
  int pid, {
  bool submit = false,
}) {
  final base = Uri.parse(ChhUrls.base);
  if (uri.scheme != 'https' ||
      uri.host != base.host ||
      uri.hasPort && uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.path != '/forum.php') {
    return false;
  }
  final q = uri.queryParameters;
  if ((q.containsKey('tid') && q['tid'] != '$tid') ||
      (q.containsKey('pid') && q['pid'] != '$pid')) {
    return false;
  }
  if (kind == PostInteractionKind.rating) {
    if (q['mod'] != 'misc' || q['action'] != 'rate') return false;
    return submit || !q.containsKey('ratesubmit');
  }
  if (submit) {
    return q['mod'] == 'post' &&
        q['action'] == 'reply' &&
        q['comment'] == 'yes';
  }
  return q['mod'] == 'misc' &&
      q['action'] == 'comment' &&
      !q.containsKey('commentsubmit');
}

PostActionCapabilities parsePostActionCapabilities(
  dom.Element table, {
  required int tid,
  required int pid,
}) {
  Uri? comment, rating;
  var hasReplyToolbar = false;
  final base = Uri.parse(ChhUrls.base);
  for (final a in table.querySelectorAll('a')) {
    bool belongs = false;
    var inToolbar = false;
    for (var parent = a.parent; parent != null; parent = parent.parent) {
      if (parent.id.startsWith('postmessage_') ||
          parent.id.startsWith('signature') ||
          parent.classes.contains('quote') ||
          parent.classes.contains('sign') ||
          parent.localName == 'pre' ||
          parent.localName == 'code') {
        break;
      }
      inToolbar =
          inToolbar ||
          parent.classes.contains('po') ||
          parent.classes.contains('pob');
      if (parent == table) {
        belongs = true;
        break;
      }
      if (parent.localName == 'table' && parent.id.startsWith('pid')) break;
    }
    if (!belongs) continue;
    // Some official templates carry the window URL in onclick, not href.
    // Read quoted URL literals only; never execute site JavaScript.
    final candidates = <String>[
      a.attributes['href'] ?? '',
      ...RegExp(
        r"""['"]((?:https://www\.chiphell\.com/|/)?forum\.php\?[^'"\s]+)['"]""",
      ).allMatches(a.attributes['onclick'] ?? '').map((m) => m.group(1)!),
    ];
    for (final raw in candidates) {
      final uri = Uri.tryParse(raw);
      if (uri == null) continue;
      final url = base.resolveUri(uri);
      if (url.scheme != 'https' ||
          url.host != base.host ||
          url.userInfo.isNotEmpty ||
          (url.hasPort && url.port != 443) ||
          url.path != '/forum.php') {
        continue;
      }
      final q = url.queryParameters;
      if (url.queryParametersAll.values.any((v) => v.length != 1) ||
          (q.containsKey('tid') && q['tid'] != '$tid') ||
          (q.containsKey('ptid') && q['ptid'] != '$tid') ||
          (q.containsKey('pid') && q['pid'] != '$pid') ||
          (q.containsKey('repquote') && q['repquote'] != '$pid')) {
        continue;
      }
      final targetsPost = q['pid'] == '$pid' || q['repquote'] == '$pid';
      if (inToolbar &&
          q['mod'] == 'post' &&
          q['action'] == 'reply' &&
          q['comment'] != 'yes' &&
          (targetsPost || q['tid'] == '$tid')) {
        hasReplyToolbar = true;
      }
      if (!targetsPost) continue;
      final normalized = url.replace(
        queryParameters: {...q, 'tid': '$tid', 'pid': '$pid'},
      );
      if (inToolbar &&
          isInteractionUrl(normalized, PostInteractionKind.comment, tid, pid)) {
        comment = normalized;
      }
      if (isInteractionUrl(normalized, PostInteractionKind.rating, tid, pid)) {
        rating = normalized;
      }
    }
  }
  // ReSource scans the complete post for rate links, not just its reply bar.
  // Their absence is not a server denial: allow a fresh form GET to decide.
  return PostActionCapabilities(
    comment: comment != null
        ? PostActionPermission.allowed
        : hasReplyToolbar
        ? PostActionPermission.denied
        : PostActionPermission.unknown,
    rating: rating != null
        ? PostActionPermission.allowed
        : PostActionPermission.unknown,
    commentUrl: comment,
    ratingUrl: rating,
  );
}

Map<String, String> _hidden(dom.Element form) => {
  for (final input in form.querySelectorAll('input[type=hidden][name]'))
    if (!input.attributes.containsKey('disabled'))
      input.attributes['name']!: input.attributes['value'] ?? '',
};

({dom.Element form, Uri action, String hash, Map<String, String> hidden})?
_form(dom.Document doc, PostInteractionKind kind, int tid, int pid) {
  final forms = doc.querySelectorAll('form');
  // ReSource ev1.X reads the AJAX fragment at document scope. Discuz may
  // return the form contents without a wrapping form element. Only use the
  // canonical action when no explicit form exists; never bypass a bad action.
  final candidates = forms.isEmpty && kind == PostInteractionKind.rating
      ? <dom.Element>[doc.body!]
      : forms;
  for (final f in candidates) {
    final hash = f
        .querySelector('input[name=formhash]')
        ?.attributes['value']
        ?.trim();
    if (hash == null || hash.isEmpty) continue;
    if (kind == PostInteractionKind.comment &&
        f.querySelector('textarea[name=message], input[name=message]') ==
            null) {
      continue;
    }
    if (kind == PostInteractionKind.rating &&
        f.querySelector('input[name^=score]') == null) {
      continue;
    }
    final raw = f.attributes['action']?.trim() ?? '';
    final relative = Uri.tryParse(raw);
    if (relative == null) continue;
    final action = raw.isEmpty
        ? interactionSubmitUrl(kind, tid, pid)
        : Uri.parse(ChhUrls.base).resolveUri(relative);
    if (!isInteractionUrl(action, kind, tid, pid, submit: true)) continue;
    final hidden = _hidden(f);
    if (hidden.containsKey('tid') && hidden['tid'] != '$tid' ||
        hidden.containsKey('pid') && hidden['pid'] != '$pid') {
      continue;
    }
    return (form: f, action: action, hash: hash, hidden: hidden);
  }
  return null;
}

PostCommentForm? parsePostCommentForm(
  String raw, {
  required int tid,
  required int pid,
  required Uri pageUrl,
  String sessionIdentity = '',
  int? sessionRevision,
}) {
  final doc = _document(raw);
  if (parseInteractionPageError(raw) != null) return null;
  final data = _form(doc, PostInteractionKind.comment, tid, pid);
  if (data == null) return null;
  final field = data.form.querySelector('[name=message]');
  final max = int.tryParse(field?.attributes['maxlength'] ?? '');
  return PostCommentForm(
    tid: tid,
    pid: pid,
    action: data.action,
    pageUrl: pageUrl,
    formhash: data.hash,
    hidden: Map.unmodifiable(data.hidden),
    sessionIdentity: sessionIdentity,
    sessionRevision: sessionRevision,
    maxLength: max != null && max > 0 ? max : 200,
  );
}

PostRateForm? parsePostRateForm(
  String raw, {
  required int tid,
  required int pid,
  required Uri pageUrl,
  String sessionIdentity = '',
  int? sessionRevision,
}) {
  final doc = _document(raw);
  if (parseInteractionPageError(raw) != null) return null;
  final data = _form(doc, PostInteractionKind.rating, tid, pid);
  if (data == null) return null;
  final types = <RateScoreType>[];
  final fields = <String>{};
  for (final row in data.form.querySelectorAll('table.dt tr')) {
    final cells = row.children.where((c) => c.localName == 'td').toList();
    final input = row.querySelector('input[name^=score]');
    final name = input?.attributes['name'];
    if (cells.length < 3 ||
        name == null ||
        !RegExp(r'^score\d+$').hasMatch(name) ||
        !fields.add(name)) {
      continue;
    }
    final label = cleanText(cells.first.text);
    final range = RegExp(r'(-?\d+)\s*~\s*(-?\d+)').firstMatch(row.text);
    final min = int.tryParse(range?.group(1) ?? '');
    final max = int.tryParse(range?.group(2) ?? '');
    final remaining = int.tryParse(cells.last.text.trim());
    // Missing bounds are not invented or converted into a usable range.
    if (label.isEmpty ||
        min == null ||
        max == null ||
        min > max ||
        remaining == null ||
        remaining < 0) {
      continue;
    }
    final options =
        doc
            .getElementById('scoreoption${name.substring(5)}')
            ?.querySelectorAll('li') ??
        [];
    types.add(
      RateScoreType(
        fieldName: name,
        label: label,
        min: min,
        max: max,
        remaining: remaining,
        options: List.unmodifiable(
          options
              .map((e) => int.tryParse(e.text.trim().replaceAll('+', '')))
              .whereType<int>(),
        ),
      ),
    );
  }
  if (types.isEmpty || !types.any((t) => t.isEvil)) return null;
  return PostRateForm(
    tid: tid,
    pid: pid,
    action: data.action,
    pageUrl: pageUrl,
    formhash: data.hash,
    hidden: Map.unmodifiable(data.hidden),
    sessionIdentity: sessionIdentity,
    sessionRevision: sessionRevision,
    scoreTypes: List.unmodifiable(types),
    reasons: List.unmodifiable(
      doc
          .querySelectorAll('ul#reasonselect li, ul.reasonselect li')
          .map((e) => e.text.trim())
          .where((s) => s.isNotEmpty)
          .toSet(),
    ),
  );
}

PostResult? parseInteractionPageError(String raw) {
  final doc = _document(raw);
  final errors = doc
      .querySelectorAll(
        '#messagetext, .alert_error, .alert_info, .alert_warning',
      )
      .where((e) {
        for (dom.Element? p = e; p != null; p = p.parent) {
          if (p.classes.contains('alert_right')) return false;
        }
        return true;
      });
  String text = cleanText(
    errors.map((e) => textWithout(e, ['script', 'style'])).join(' '),
  );
  final errorScript = RegExp(
    r'''errorhandle_[\w]*\s*\(\s*['"]([^'"]+)['"]''',
  ).firstMatch(interactionHtml(raw));
  if (text.isEmpty && errorScript != null) {
    text = html.parseFragment(errorScript.group(1)!).text ?? '';
  }
  if (doc.querySelector(
        'form input[name=seccodeverify], form input[name=secqaaverify], form [id^=seccode_]',
      ) !=
      null) {
    return const PostResult(PostResultKind.needCaptcha, '需要完成验证，请在原网页操作');
  }
  if (doc.querySelector('#messagelogin, form#loginform') != null) {
    return const PostResult(PostResultKind.loginRequired, '请先登录');
  }
  if (text.isEmpty) return null;
  if (text.contains('请先登录') ||
      text.contains('登录后') ||
      text.contains('尚未登录') ||
      doc.querySelector('#messagelogin') != null) {
    return PostResult(PostResultKind.loginRequired, text);
  }
  if (text.contains('验证码') || text.contains('人机验证') || text.contains('安全验证')) {
    return PostResult(PostResultKind.needCaptcha, text);
  }
  if (RegExp(
    r'(?:不能|无法|不允许|不可).*(?:自己|本人).*(?:评分)|(?:不能|无法|不允许|不可).*评分.*(?:自己|本人)',
  ).hasMatch(text)) {
    return PostResult(PostResultKind.selfRating, text);
  }
  if (RegExp(
    r'(?:评分|积分|额度).*(?:用完|用尽|不足|超过|超出)|(?:超过|超出).*(?:评分|积分|额度)',
  ).hasMatch(text)) {
    return PostResult(PostResultKind.ratingQuotaExhausted, text);
  }
  // A temporary restriction is not a permission denial, even when the
  // message also says that rating is currently unavailable.
  if (text.contains('间隔') || text.contains('太频繁') || text.contains('稍后再试')) {
    return PostResult(PostResultKind.throttled, text);
  }
  if (text.contains('无法进行此操作') ||
      text.contains('没有权限') ||
      text.contains('无权') ||
      text.contains('权限不足') ||
      text.contains('不能评分') ||
      text.contains('不能点评')) {
    return PostResult(PostResultKind.permissionDenied, text);
  }
  return PostResult(PostResultKind.failed, text);
}

PostResult parsePostInteractionResult(
  String raw,
  PostInteractionKind kind, {
  int status = 200,
}) {
  final doc = _document(raw);
  if (doc.getElementById('thread_subject') != null ||
      doc.querySelector('td[id^=postmessage_]') != null) {
    return const PostResult(PostResultKind.unknown, '提交结果待核对，请刷新确认');
  }
  final error = parseInteractionPageError(raw);
  if (error != null) return error;
  final scripts = doc.querySelectorAll('script').map((e) => e.text).join('\n');
  final script = RegExp(
    r'''succeedhandle_[\w]+\s*\(\s*['"][^'"]*['"]\s*,\s*['"]([^'"]+)['"]''',
  ).firstMatch(scripts);
  final message = cleanText(
    script?.group(1) ?? doc.querySelector('.alert_right')?.text,
  );
  final accepted = kind == PostInteractionKind.comment
      ? ['点评成功', '点评发表成功']
      : ['评分成功', '评分完成', '感谢您的参与'];
  if (status >= 200 &&
      status < 300 &&
      message.isNotEmpty &&
      accepted.any(message.contains)) {
    return PostResult(PostResultKind.success, message);
  }
  return const PostResult(PostResultKind.unknown, '提交结果待核对，请刷新确认');
}
