/// Single, user-triggered forum interactions bound to the active account.
library;

import '../models/models.dart';
import '../models/post_interaction.dart';
import '../network/chh_client.dart';
import '../parser/post_action_parser.dart';

class PostInteractionException implements Exception {
  final PostResult result;
  const PostInteractionException(this.result);
  @override
  String toString() => result.message;
}

class PostInteractionRepository {
  final ChhClient client;
  final String? Function()? sessionIdentity;
  final bool Function()? loggedIn;
  final int Function()? sessionRevision;
  final _pending = <String>{};
  PostInteractionRepository(
    this.client, {
    this.sessionIdentity,
    this.loggedIn,
    this.sessionRevision,
  });

  String _identity() {
    final value = sessionIdentity == null
        ? '_test-unbound'
        : sessionIdentity!();
    if (value == null || value.isEmpty) {
      if (loggedIn?.call() == true) {
        throw const PostInteractionException(
          PostResult(PostResultKind.failed, '登录信息读取中，请稍后重试'),
        );
      }
      throw const PostInteractionException(
        PostResult(PostResultKind.loginRequired, '请先登录'),
      );
    }
    return value;
  }

  void _checkIdentity(String expected, int? revision) {
    if (_identity() != expected ||
        (sessionRevision != null && sessionRevision!() != revision)) {
      throw const PostInteractionException(
        PostResult(PostResultKind.loginRequired, '账号已变化，请重新打开表单'),
      );
    }
  }

  Uri _page(PostInteractionKind kind, int tid, int pid, Uri? observed) {
    if (tid <= 0 || pid <= 0) throw ArgumentError('无效的帖子或楼层');
    final page = observed ?? interactionPageUrl(kind, tid, pid);
    if (!isInteractionUrl(page, kind, tid, pid) ||
        page.queryParameters['tid'] != '$tid' ||
        page.queryParameters['pid'] != '$pid') {
      throw const PostInteractionException(
        PostResult(PostResultKind.failed, '操作地址无效，请刷新帖子'),
      );
    }
    final handle = kind == PostInteractionKind.comment ? 'comment' : 'rate';
    return page.replace(
      queryParameters: {
        ...page.queryParameters,
        if (kind == PostInteractionKind.comment) 'extra': '',
        'infloat': 'yes',
        'inajax': '1',
        'handlekey': handle,
        'ajaxtarget': 'fwin_content_$handle',
      },
    );
  }

  Future<PostCommentForm> commentForm({
    required int tid,
    required int pid,
    Uri? pageUrl,
  }) async {
    final identity = _identity();
    final revision = sessionRevision?.call();
    final page = _page(PostInteractionKind.comment, tid, pid, pageUrl);
    final raw = await client.getAjaxHtml(page, refresh: true);
    _checkIdentity(identity, revision);
    final form = parsePostCommentForm(
      raw,
      tid: tid,
      pid: pid,
      pageUrl: page,
      sessionIdentity: identity,
      sessionRevision: revision,
    );
    if (form == null) {
      throw PostInteractionException(
        parseInteractionPageError(raw) ??
            const PostResult(PostResultKind.failed, '无法读取点评表单，请重试'),
      );
    }
    return form;
  }

  Future<PostRateForm> rateForm({
    required int tid,
    required int pid,
    Uri? pageUrl,
  }) async {
    final identity = _identity();
    final revision = sessionRevision?.call();
    final page = _page(PostInteractionKind.rating, tid, pid, pageUrl);
    final raw = await client.getAjaxHtml(page, refresh: true);
    _checkIdentity(identity, revision);
    final form = parsePostRateForm(
      raw,
      tid: tid,
      pid: pid,
      pageUrl: page,
      sessionIdentity: identity,
      sessionRevision: revision,
    );
    if (form == null) {
      throw PostInteractionException(
        parseInteractionPageError(raw) ??
            const PostResult(PostResultKind.failed, '无法读取邪恶评分表单，请重试'),
      );
    }
    return form;
  }

  Future<PostResult> submitComment({
    required PostCommentForm form,
    required String message,
  }) async {
    final lock = '${form.sessionIdentity}:comment:${form.tid}:${form.pid}';
    if (!_pending.add(lock)) {
      return const PostResult(PostResultKind.failed, '正在提交，请稍候');
    }
    try {
      _checkIdentity(form.sessionIdentity, form.sessionRevision);
      final fresh = await commentForm(
        tid: form.tid,
        pid: form.pid,
        pageUrl: form.pageUrl,
      );
      if (message.trim().isEmpty || message.length > fresh.maxLength) {
        return PostResult(
          PostResultKind.failed,
          '点评须为 1 至 ${fresh.maxLength} 字',
        );
      }
      return await _post(
        PostInteractionKind.comment,
        fresh.tid,
        fresh.pid,
        fresh.action,
        fresh.sessionIdentity,
        fresh.sessionRevision,
        {
          ...fresh.hidden,
          'formhash': fresh.formhash,
          'handlekey': 'comment',
          'referer': fresh.pageUrl.toString(),
          'message': message,
        },
      );
    } on PostInteractionException catch (e) {
      return e.result;
    } catch (_) {
      return const PostResult(PostResultKind.failed, '读取点评表单失败，请重试');
    } finally {
      _pending.remove(lock);
    }
  }

  Future<PostResult> submitRating({
    required PostRateForm form,
    required Map<String, int> scores,
    String reason = '',
    bool notify = false,
  }) async {
    final lock = '${form.sessionIdentity}:rating:${form.tid}:${form.pid}';
    if (!_pending.add(lock)) {
      return const PostResult(PostResultKind.failed, '正在提交，请稍候');
    }
    try {
      _checkIdentity(form.sessionIdentity, form.sessionRevision);
      final fresh = await rateForm(
        tid: form.tid,
        pid: form.pid,
        pageUrl: form.pageUrl,
      );
      final allowed = fresh.scoreTypes.map((t) => t.fieldName).toSet();
      if (scores.keys.any((k) => !allowed.contains(k))) {
        return const PostResult(PostResultKind.failed, '评分项目已变化，请重新打开表单');
      }
      final hiddenScore = RegExp(r'^score\d+$');
      if (fresh.hidden.entries.any(
        (e) =>
            hiddenScore.hasMatch(e.key) &&
            !allowed.contains(e.key) &&
            int.tryParse(e.value) != 0,
      )) {
        return const PostResult(PostResultKind.failed, '评分项目已变化，请重新打开表单');
      }
      final values = {
        for (final type in fresh.scoreTypes)
          type.fieldName: scores[type.fieldName] ?? 0,
      };
      if (!values.values.any((s) => s != 0)) {
        return const PostResult(PostResultKind.failed, '请选择评分分值');
      }
      // The UI only exposes evil points. Other required fields must remain zero.
      if (fresh.scoreTypes.any((t) => !t.isEvil && values[t.fieldName] != 0)) {
        return const PostResult(PostResultKind.failed, '仅支持邪恶指数评分');
      }
      if (fresh.scoreTypes.any((t) => !t.accepts(values[t.fieldName]!))) {
        return const PostResult(PostResultKind.failed, '分值或可用额度已变化，请重新读取表单');
      }
      return await _post(
        PostInteractionKind.rating,
        fresh.tid,
        fresh.pid,
        fresh.action,
        fresh.sessionIdentity,
        fresh.sessionRevision,
        {
          for (final e in fresh.hidden.entries)
            if (!hiddenScore.hasMatch(e.key)) e.key: e.value,
          'formhash': fresh.formhash,
          'tid': '${fresh.tid}',
          'pid': '${fresh.pid}',
          'referer': fresh.pageUrl.toString(),
          'handlekey': 'rate',
          'reason': reason,
          for (final e in values.entries) e.key: '${e.value}',
          if (notify) 'sendreasonpm': '1',
        }..removeWhere((k, v) => k == 'sendreasonpm' && !notify),
      );
    } on PostInteractionException catch (e) {
      return e.result;
    } catch (_) {
      return const PostResult(PostResultKind.failed, '读取评分表单失败，请重试');
    } finally {
      _pending.remove(lock);
    }
  }

  Future<PostResult> _post(
    PostInteractionKind kind,
    int tid,
    int pid,
    Uri action,
    String identity,
    int? revision,
    Map<String, String> fields,
  ) async {
    _checkIdentity(identity, revision);
    if (!isInteractionUrl(action, kind, tid, pid, submit: true)) {
      return const PostResult(PostResultKind.failed, '操作地址无效，请刷新帖子');
    }
    final url = action.replace(
      queryParameters: {
        ...action.queryParameters,
        'tid': '$tid',
        'pid': '$pid',
        'infloat': 'yes',
        'inajax': '1',
        if (kind == PostInteractionKind.comment) ...{
          'extra': '',
          'commentsubmit': 'yes',
        } else
          'ratesubmit': 'yes',
      },
    );
    try {
      final response = await client.postAjaxForm(
        url,
        fields,
        retryTransportFailures: false,
      );
      _checkIdentity(identity, revision);
      // No response after a POST may mean it was accepted: never encourage replay.
      if (response.status <= 0 ||
          (response.status >= 300 && response.status < 400)) {
        return const PostResult(PostResultKind.unknown, '提交结果待核对，请刷新确认');
      }
      if (response.rejectedBeforeApp) {
        return const PostResult(PostResultKind.failed, '请求被拦截，请稍后重试');
      }
      final result = parsePostInteractionResult(
        response.body,
        kind,
        status: response.status,
      );
      if (result.isSuccess) client.clearCache();
      return result;
    } on PostInteractionException catch (e) {
      return e.result;
    } catch (_) {
      return const PostResult(PostResultKind.unknown, '提交结果待核对，请刷新确认');
    }
  }
}
