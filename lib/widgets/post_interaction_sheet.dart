/// Real forum forms for per-post comments and ratings; no synthetic limits.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

import '../data/post_interaction_repository.dart';
import '../data/post_interaction_drafts.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/models.dart';
import '../models/post_interaction.dart';
import '../ui/app_button.dart';
import '../ui/editor_touch.dart';
import 'expressive_composer.dart';

Future<PostResult?> showPostInteractionSheet(
  BuildContext context, {
  required PostInteractionKind kind,
  required int tid,
  required Post post,
  required PostInteractionRepository repository,
  required String? Function() sessionIdentity,
  int Function()? sessionRevision,
  Listenable? sessionChanges,
  Future<void> Function()? onCheckResult,
  PostInteractionDraftStore? drafts,
  Uri? pageUrl,
  PostRateForm? initialRatingForm,
}) => showExpressiveComposerRoute(
  context,
  builder: (_) => PostInteractionSheet(
    kind: kind,
    tid: tid,
    post: post,
    repository: repository,
    sessionIdentity: sessionIdentity,
    sessionRevision: sessionRevision,
    sessionChanges: sessionChanges,
    onCheckResult: onCheckResult,
    drafts: drafts,
    pageUrl: pageUrl,
    initialRatingForm: initialRatingForm,
  ),
);

class PostInteractionSheet extends StatefulWidget {
  final PostInteractionKind kind;
  final int tid;
  final Post post;
  final PostInteractionRepository repository;
  final String? Function() sessionIdentity;
  final int Function()? sessionRevision;
  final Listenable? sessionChanges;
  final Future<void> Function()? onCheckResult;
  final PostInteractionDraftStore? drafts;
  final Uri? pageUrl;
  final PostRateForm? initialRatingForm;
  const PostInteractionSheet({
    super.key,
    required this.kind,
    required this.tid,
    required this.post,
    required this.repository,
    required this.sessionIdentity,
    this.sessionRevision,
    this.sessionChanges,
    this.onCheckResult,
    this.drafts,
    this.pageUrl,
    this.initialRatingForm,
  });
  @override
  State<PostInteractionSheet> createState() => _PostInteractionSheetState();
}

class _PostInteractionSheetState extends State<PostInteractionSheet> {
  final _sheet = SheetController();
  final _text = TextEditingController();
  final _reason = TextEditingController();
  final _score = TextEditingController();
  final _focus = FocusNode();
  PostInteractionDraftStore get _drafts =>
      widget.drafts ?? postInteractionDrafts;
  late final String? _actor;
  late final int? _revision;
  late final String _key = PostInteractionDraftStore.key(
    _actor ?? '',
    widget.tid,
    widget.post.pid,
    widget.kind.name,
  );
  PostCommentForm? _comment;
  PostRateForm? _rating;
  bool _loading = true, _busy = false, _uncertain = false, _notify = false;
  bool _checking = false, _ready = false;
  bool _initialRatingUsed = false;
  String? _storageWarning;
  PostResult? _failure;
  int _epoch = 0;
  bool get _isComment => widget.kind == PostInteractionKind.comment;
  String get _title => _isComment ? '点评' : '评分';
  bool get _sameActor =>
      _actor != null &&
      widget.sessionIdentity() == _actor &&
      (widget.sessionRevision == null ||
          widget.sessionRevision!() == _revision);
  RateScoreType? get _evil => _rating?.evilScoreType;
  int? get _scoreValue => int.tryParse(_score.text.trim());
  bool get _canSend {
    if (_loading || _busy || _uncertain || !_sameActor) return false;
    if (_isComment) {
      return _comment != null &&
          _text.text.trim().isNotEmpty &&
          _text.text.length <= _comment!.maxLength;
    }
    final value = _scoreValue;
    return _evil != null &&
        value != null &&
        value != 0 &&
        _evil!.accepts(value);
  }

  String? get _validation {
    if (_isComment) {
      return _comment != null && _text.text.length > _comment!.maxLength
          ? '点评不能超过 ${_comment!.maxLength} 字'
          : null;
    }
    final e = _evil, v = _scoreValue;
    if (e == null || _score.text.trim().isEmpty) return null;
    if (v == null) return '请输入整数分值';
    if (v < e.min || v > e.max) return '分值须在 ${e.min} 至 ${e.max} 之间';
    if (v.abs() > e.remaining) return '超过剩余可用额度 ${e.remaining}';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _actor = widget.sessionIdentity();
    _revision = widget.sessionRevision?.call();
    _focus.addListener(_focusChanged);
    widget.sessionChanges?.addListener(_sessionChanged);
    _text.addListener(_edited);
    _reason.addListener(_edited);
    _score.addListener(_edited);
    _load();
  }

  void _focusChanged() {
    if (!_focus.hasFocus || !_sheet.hasClient || !mounted) return;
    _sheet.animateTo(
      const SheetOffset(1),
      // smooth_sheets requires a positive duration even for reduced motion.
      duration: MediaQuery.disableAnimationsOf(context)
          ? AppMotion.immediateSheet
          : AppMotion.revealDuration,
      curve: AppMotion.revealCurve,
    );
  }

  void _sessionChanged() {
    if (_sameActor || !mounted) return;
    _epoch++;
    _focus.unfocus();
    setState(() {
      _busy = false;
      _loading = false;
      _comment = null;
      _rating = null;
      _failure = const PostResult(
        PostResultKind.loginRequired,
        '账号已变化，请关闭后重新打开',
      );
    });
  }

  PostInteractionDraft _snapshot({bool? uncertain}) => PostInteractionDraft(
    text: _text.text,
    scores: {
      if (_evil != null && _scoreValue != null) _evil!.fieldName: _scoreValue!,
    },
    reason: _reason.text,
    notify: _notify,
    uncertain: uncertain ?? _uncertain,
  );
  void _edited() {
    if (!_ready || !mounted || _busy || _checking) return;
    unawaited(
      _drafts.put(_key, _snapshot()).then((ok) {
        if (!ok && mounted && _storageWarning == null) {
          setState(() => _storageWarning = '草稿暂未保存到本机');
        }
      }),
    );
    setState(() {});
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _comment = null;
      _rating = null;
    });
    try {
      await _drafts.load();
      if (!mounted || epoch != _epoch) return;
      if (!_sameActor) {
        _sessionChanged();
        return;
      }
      final saved = _drafts.get(_key);
      if (!_ready) {
        _text.text = saved?.text ?? '';
        _reason.text = saved?.reason ?? '';
        _notify = saved?.notify ?? false;
        _uncertain = saved?.uncertain ?? false;
      }
      if (_isComment) {
        _comment = await widget.repository.commentForm(
          tid: widget.tid,
          pid: widget.post.pid,
          pageUrl: widget.pageUrl,
        );
      } else {
        final initial = !_initialRatingUsed ? widget.initialRatingForm : null;
        _initialRatingUsed = true;
        final form =
            initial != null &&
                initial.tid == widget.tid &&
                initial.pid == widget.post.pid &&
                initial.sessionIdentity == _actor &&
                initial.sessionRevision == _revision
            ? initial
            : await widget.repository.rateForm(
                tid: widget.tid,
                pid: widget.post.pid,
                pageUrl: widget.pageUrl,
              );
        if (!mounted || epoch != _epoch || !_sameActor) return;
        _rating = form;
        if (!_ready) {
          _score.text = '${saved?.scores[form.evilScoreType?.fieldName] ?? 0}';
        }
      }
      if (!mounted || epoch != _epoch) return;
      if (!_sameActor) {
        _sessionChanged();
        return;
      }
      setState(() {
        _loading = false;
        _ready = true;
        _failure = null;
      });
    } on PostInteractionException catch (e) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _loading = false;
          _failure = e.result;
        });
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _loading = false;
          _failure = const PostResult(PostResultKind.failed, '读取表单失败，请重试');
        });
      }
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final epoch = _epoch;
    _focus.unfocus();
    setState(() => _busy = true);
    // Persist uncertainty before a request can reach the forum. A killed process
    // must not reopen an apparently unsent draft and encourage a duplicate POST.
    final persisted = await _drafts.put(_key, _snapshot(uncertain: true));
    if (!mounted || epoch != _epoch || !_sameActor) return;
    if (!persisted) {
      setState(() {
        _busy = false;
        _failure = const PostResult(PostResultKind.failed, '无法保存提交状态，请稍后重试');
      });
      return;
    }
    PostResult result;
    try {
      result = _isComment
          ? await widget.repository.submitComment(
              form: _comment!,
              message: _text.text.trim(),
            )
          : await widget.repository.submitRating(
              form: _rating!,
              scores: {
                ..._rating!.initialScores,
                _evil!.fieldName: _scoreValue!,
              },
              reason: _reason.text,
              notify: _notify,
            );
    } catch (_) {
      result = const PostResult(PostResultKind.unknown, '暂时无法确认提交结果，请先核对');
    }
    if (!mounted || epoch != _epoch || !_sameActor) return;
    if (result.isSuccess) {
      await _drafts.remove(_key);
      if (mounted) Navigator.of(context).pop(result);
      return;
    }
    _uncertain = result.kind == PostResultKind.unknown;
    await _drafts.put(_key, _snapshot());
    if (mounted) {
      setState(() {
        _busy = false;
        _failure = result;
      });
    }
  }

  Future<void> _check() async {
    if (_busy || _checking) return;
    setState(() => _checking = true);
    try {
      await widget.onCheckResult?.call();
      if (mounted) {
        Navigator.of(
          context,
        ).pop(const PostResult(PostResultKind.unknown, '已刷新目标内容，请核对是否发表成功'));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _failure = const PostResult(PostResultKind.unknown, '暂时无法核对，请稍后重试');
        });
      }
    }
  }

  Future<void> _acknowledgeNotPosted() async {
    if (_busy || _checking || !_sameActor) return;
    setState(() => _checking = true);
    final ok = await _drafts.put(_key, _snapshot(uncertain: false));
    if (!mounted) return;
    if (!ok) {
      await _drafts.put(_key, _snapshot(uncertain: true));
      if (mounted) {
        setState(() {
          _checking = false;
          _storageWarning = '无法保存核对状态，请稍后重试';
        });
      }
      return;
    }
    setState(() {
      _checking = false;
      _uncertain = false;
      _failure = null;
    });
    await _load();
  }

  @override
  void dispose() {
    widget.sessionChanges?.removeListener(_sessionChanged);
    _text.dispose();
    _reason.dispose();
    _score.dispose();
    _focus.dispose();
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final embedded =
        context.findAncestorWidgetOfExactType<SheetViewport>() != null;
    final content = PopScope(
      canPop: !_busy && !_checking,
      child: SheetKeyboardDismissible(
        dismissBehavior: const SheetKeyboardDismissBehavior.onDragDown(
          isContentScrollAware: false,
        ),
        child: Sheet(
          controller: _sheet,
          // Keep the form usable before and after its asynchronous load.
          initialOffset: const SheetOffset(1),
          snapGrid: const SheetSnapGrid.single(snap: SheetOffset(1)),
          dragConfiguration: _busy || _checking
              ? SheetDragConfiguration.disabled
              : const SheetDragConfiguration(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          decoration: MaterialSheetDecoration(
            size: SheetSize.stretch,
            color: t.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadii.xl),
            ),
          ),
          child: SheetContentScaffold(
            backgroundColor: t.surface,
            topBar: _header(t),
            body: SizedBox.expand(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${widget.post.author} / ${widget.post.floorIsKnown && widget.post.floor == 1
                          ? '主帖'
                          : widget.post.floorIsKnown
                          ? '#${widget.post.floor}'
                          : '原帖'}',
                      style: AppType.footnote.copyWith(color: t.text2),
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      if (_failure != null) _message(t, _failure!.message),
                      if (_storageWarning != null)
                        _message(t, _storageWarning!),
                      if (_isComment && _comment != null) _commentEditor(t),
                      if (!_isComment && _rating != null) _ratingEditor(t),
                      if (_validation != null) _message(t, _validation!),
                      if (_uncertain) ...[
                        _message(t, '提交结果待核对，暂不能再次发送'),
                        AppButton(
                          label: _checking ? '核对中' : '核对结果',
                          onPressed: _checking ? null : _check,
                          variant: AppButtonVariant.tinted,
                        ),
                        AppButton(
                          label: '我已确认未发表，重新编辑',
                          variant: AppButtonVariant.quiet,
                          onPressed: _checking ? null : _acknowledgeNotPosted,
                        ),
                      ] else if ((_isComment
                              ? _comment == null
                              : _rating == null) ||
                          _failure?.kind == PostResultKind.permissionDenied ||
                          _failure?.kind == PostResultKind.loginRequired)
                        AppButton(
                          label: '重新读取',
                          onPressed: _busy || !_sameActor ? null : _load,
                          variant: AppButtonVariant.tinted,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (embedded) return content;
    return SheetViewport(
      padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top + 8),
      child: content,
    );
  }

  Widget _header(AppTokens t) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 21,
        child: Center(
          child: Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: t.fill2,
              borderRadius: BorderRadius.circular(AppRadii.bar),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 12, 10),
        child: Row(
          children: [
            AppButton(
              label: '取消',
              variant: AppButtonVariant.quiet,
              onPressed: _busy || _checking
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                _title,
                textAlign: TextAlign.center,
                style: AppType.headline.copyWith(color: t.text),
              ),
            ),
            AppButton(
              key: const ValueKey('interaction-send'),
              label: _busy ? '发送中' : '发送',
              small: true,
              state: _busy ? AppButtonState.busy : AppButtonState.idle,
              onPressed: _canSend ? _send : null,
            ),
          ],
        ),
      ),
    ],
  );
  Widget _message(AppTokens t, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(text, style: AppType.footnote.copyWith(color: t.warn)),
    ),
  );
  Widget _commentEditor(AppTokens t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EditorTouchGuard(
        focusNode: _focus,
        enabled: !_busy && !_uncertain,
        notifyOnUserEntry: true,
        builder: (context, focus, onTap) => TextField(
          key: const ValueKey('interaction-comment'),
          controller: _text,
          focusNode: focus,
          onTapAlwaysCalled: true,
          onTap: onTap,
          readOnly: _busy || _uncertain,
          minLines: 5,
          maxLines: null,
          style: AppType.body.copyWith(color: t.text),
          decoration: const InputDecoration(
            hintText: '写下简短的点评',
            border: InputBorder.none,
            filled: false,
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          '${_text.text.length} / ${_comment!.maxLength}',
          style: AppType.footnote.copyWith(color: t.text2),
        ),
      ),
    ],
  );
  Widget _ratingEditor(AppTokens t) {
    final evil = _evil;
    if (evil == null) return _message(t, '当前表单没有可用的邪恶指数评分项');
    final locked = _busy || _uncertain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(evil.label, style: AppType.headline.copyWith(color: t.text)),
        const SizedBox(height: 8),
        Text(
          '范围 ${evil.min} 至 ${evil.max}，可用 ${evil.remaining}',
          style: AppType.footnote.copyWith(color: t.text2),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: '减少分值',
              onPressed: locked
                  ? null
                  : () => _score.text = '${(_scoreValue ?? 0) - 1}',
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: TextField(
                key: const ValueKey('interaction-score'),
                controller: _score,
                readOnly: locked,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: t.text),
                decoration: const InputDecoration(labelText: '分值'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '增加分值',
              onPressed: locked
                  ? null
                  : () => _score.text = '${(_scoreValue ?? 0) + 1}',
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (evil.options.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final n in evil.options)
                AppButton(
                  label: n > 0 ? '+$n' : '$n',
                  small: true,
                  variant: AppButtonVariant.tinted,
                  onPressed: locked ? null : () => _score.text = '$n',
                ),
            ],
          ),
        const SizedBox(height: 20),
        Text('评分理由', style: AppType.headline.copyWith(color: t.text)),
        EditorTouchGuard(
          focusNode: _focus,
          enabled: !locked,
          builder: (context, focus, onTap) => TextField(
            key: const ValueKey('interaction-reason'),
            controller: _reason,
            focusNode: focus,
            onTap: onTap,
            onTapAlwaysCalled: true,
            readOnly: locked,
            minLines: 2,
            maxLines: null,
            style: AppType.body.copyWith(color: t.text),
            decoration: const InputDecoration(
              hintText: '填写理由',
              border: InputBorder.none,
              filled: false,
            ),
          ),
        ),
        if (_rating!.reasons.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final reason in _rating!.reasons)
                AppButton(
                  label: reason,
                  small: true,
                  variant: AppButtonVariant.tinted,
                  onPressed: locked ? null : () => _reason.text = reason,
                ),
            ],
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '通知对方评分理由',
            style: AppType.footnote.copyWith(color: t.text2),
          ),
          value: _notify,
          onChanged: locked
              ? null
              : (v) {
                  setState(() => _notify = v ?? false);
                  _edited();
                },
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }
}
