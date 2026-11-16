/// Private conversations keep drafts on failed or uncertain sends.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/compact_scaffold.dart';
import '../ui/editor_touch.dart';
import '../ui/app_button.dart';
import '../design/chat_tokens.dart';
import '../widgets/avatar_image.dart';
import '../ui/chrome_button.dart';
import '../design/motion.dart';
import '../design/typography.dart';
import '../ui/feedback.dart';
import '../ui/chat.dart';

import '../data/message_repository.dart';
import '../di.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../widgets/state_view.dart';
import '../widgets/expressive_controls.dart';

class PmThreadPage extends StatefulWidget {
  final PmConversation conversation;
  final MessageRepository? repository;
  const PmThreadPage({super.key, required this.conversation, this.repository});
  @override
  State<PmThreadPage> createState() => _PmThreadPageState();
}

class _PmThreadPageState extends State<PmThreadPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _composerKey = GlobalKey();
  List<PmMessage> _messages = const [];
  List<PmMessage> _serverMessages = const [];
  final _localReplies = <_LocalReply>[];
  // Preserve the bubble's state when a server ID replaces a local receipt.
  final _receiptKeys = <Object, _LocalReply>{};
  final _receipts = <PmMessage, _LocalReply>{};
  bool _loading = false;
  bool _sending = false;
  bool _loaded = false;
  Object? _loadError;
  bool get _hasUnconfirmedReply => _localReplies.any(
    (reply) => reply.result?.kind == PostResultKind.unknown,
  );
  MessageRepository get _repository => widget.repository ?? messageRepo;
  bool get _announcement =>
      Uri.tryParse(widget.conversation.viewUrl)?.queryParameters['subop'] ==
      'viewg';

  @override
  void initState() {
    super.initState();
    _load(scrollToEnd: true);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({
    bool scrollToEnd = false,
    bool animateScroll = false,
  }) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await _repository.conversation(
        widget.conversation.viewUrl,
        refresh: true,
      );
      if (!mounted) return;
      setState(() {
        _reconcile(result);
        _loaded = true;
      });
      if (scrollToEnd) _scrollToEnd(animate: animateScroll);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          if (e is PageMessage &&
              (e.kind == PageMessageKind.loginRequired ||
                  e.kind == PageMessageKind.permissionDenied)) {
            _messages = const [];
            _serverMessages = const [];
            _localReplies.clear();
            _receiptKeys.clear();
            _receipts.clear();
            _loaded = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isMine(PmMessage message) =>
      message.fromSelf ||
      (chhSession.badges.uid != null &&
          message.authorUid == chhSession.badges.uid);

  String _matchingText(String text) =>
      text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();

  Map<Object, PmMessage> _keyedMessages(List<PmMessage> messages) {
    final occurrences = <Object, int>{};
    final keyed = <Object, PmMessage>{};
    for (final m in messages) {
      final content = (m.authorUid, m.author, m.text, m.timeRaw, m.fromSelf);
      final occurrence = occurrences.update(
        content,
        (n) => n + 1,
        ifAbsent: () => 0,
      );
      keyed[m.pmid ?? (content, occurrence)] = m;
    }
    return keyed;
  }

  void _reconcile(List<PmMessage> messages) {
    final incoming = _keyedMessages(messages);
    final matched = <Object>{};
    _localReplies.removeWhere((reply) {
      for (final entry in incoming.entries) {
        if (!reply.knownMessages.contains(entry.key) &&
            !matched.contains(entry.key) &&
            _isMine(entry.value) &&
            _matchingText(entry.value.text) ==
                _matchingText(reply.message.text)) {
          matched.add(entry.key);
          if (reply.result?.kind == PostResultKind.unknown &&
              _input.text.trim() == reply.message.text) {
            _input.clear();
          }
          reply.observed = true;
          _receiptKeys[entry.key] = reply;
          return true;
        }
      }
      return false;
    });
    // 同一条源站消息只能替代一个本地回显；历史同文消息也不能误匹配。
    for (final reply in _localReplies) {
      reply.knownMessages.addAll(matched);
    }
    _receipts.clear();
    for (final entry in incoming.entries) {
      final receipt = _receiptKeys[entry.key];
      if (receipt != null) _receipts[entry.value] = receipt;
    }
    _serverMessages = messages;
    _messages = [...messages, ..._localReplies.map((r) => r.message)];
  }

  void _scrollToEnd({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        AppMotion.scrollTo(_scroll.position, _scroll.position.maxScrollExtent);
      } else {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send([_LocalReply? retry]) async {
    final text = retry?.message.text ?? _input.text.trim();
    if (_sending ||
        !_loaded ||
        _announcement ||
        text.isEmpty ||
        _hasUnconfirmedReply) {
      return;
    }
    final previousFailure = _localReplies
        .where(
          (r) =>
              r.result != null &&
              !r.result!.isSuccess &&
              r.message.text == text,
        )
        .firstOrNull;
    final box = _composerKey.currentContext?.findRenderObject() as RenderBox?;
    final reply =
        retry ??
        previousFailure ??
        _LocalReply(
          PmMessage(author: '您', fromSelf: true, text: text, timeRaw: ''),
          _keyedMessages(_serverMessages).keys.toSet(),
          originY: box?.localToGlobal(Offset.zero).dy,
        );
    setState(() {
      _sending = true;
      reply.result = null;
      if (!_localReplies.contains(reply)) _localReplies.add(reply);
      _reconcile(_serverMessages);
    });
    _scrollToEnd(animate: true);
    PostResult result;
    try {
      result = await _repository.reply(
        viewUrl: widget.conversation.viewUrl,
        message: text,
      );
    } on PageMessage catch (e) {
      result = PostResult(
        e.kind == PageMessageKind.loginRequired
            ? PostResultKind.loginRequired
            : e.kind == PageMessageKind.permissionDenied
            ? PostResultKind.permissionDenied
            : PostResultKind.failed,
        e.text,
      );
    } catch (_) {
      // A transport exception does not establish whether the server accepted it.
      result = const PostResult(PostResultKind.unknown, '发送结果未确认，请刷新会话');
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      reply.result = result;
      _reconcile(_serverMessages);
    });
    if (result.isSuccess || reply.observed) {
      if (_input.text.trim() == text) _input.clear();
      _focus.unfocus();
      _scrollToEnd(animate: true);
      AppToast.show(context, '已发送');
      unawaited(_load(scrollToEnd: true, animateScroll: true));
    }
  }

  Future<void> _login() async {
    await Navigator.of(context).pushNamed('/login');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return CompactScaffold(
      title: widget.conversation.peer,
      background: t.grouped,
      centerTitle: true,
      titleWidget: Row(
        key: const ValueKey('compact-scaffold-title'),
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarImage(
            url: widget.conversation.avatarUrl,
            name: widget.conversation.peer,
            size: ChatTokens.headerAvatar,
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              widget.conversation.peer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.headline.copyWith(color: t.text),
            ),
          ),
        ],
      ),
      showBack: Navigator.canPop(context),
      resizeToAvoidBottomInset: true,
      actions: [
        ChromeButton(
          tooltip: '刷新会话',
          icon: AppIcons.refresh,
          onPressed: _loading || _sending ? null : () => _load(),
        ),
        const SizedBox(width: 8),
      ],
      body: Column(
        children: [
          Expanded(
            child: ExpressivePageReveal(
              active: true,
              fade: false,
              revision: _loaded,
              child: _body(t),
            ),
          ),
          if (_announcement)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(ChatTokens.composerInset),
                child: Container(
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(
                      ChatTokens.composerRadius,
                    ),
                  ),
                  child: Text(
                    '公共消息不能回复',
                    style: AppType.footnote.copyWith(color: t.text3),
                  ),
                ),
              ),
            )
          else if (_loaded)
            _composer(t),
        ],
      ),
    );
  }

  Widget _body(AppTokens t) {
    if (_loading && !_loaded) return StateView.loading();
    final error = _loadError;
    if (error != null && !_loaded) {
      if (error is PageMessage) {
        final login = error.kind == PageMessageKind.loginRequired;
        return StateView(
          icon: login ? AppIcons.lock : AppIcons.info,
          message: login ? '登录后查看消息' : error.text,
          actionLabel: login ? '登录' : '重试',
          onAction: login ? _login : () => _load(),
        );
      }
      return StateView.error(error, onRetry: () => _load());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
        itemCount: _messages.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            if (_messages.isEmpty) {
              if (_announcement) {
                return SizedBox(
                  height: 280,
                  child: StateView(
                    icon: AppIcons.info,
                    message: '暂时无法显示公共消息',
                    actionLabel: '刷新',
                    onAction: () => _load(),
                  ),
                );
              }
              return const SizedBox(
                height: 280,
                child: Center(child: Text('这里还没有消息')),
              );
            }
            if (error != null) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: AppButton(
                  label: '刷新未完成，轻点重试',
                  variant: AppButtonVariant.plain,
                  icon: AppIcons.refresh,
                  onPressed: () => _load(),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          final i = index - 1;
          final message = _messages[i];
          final mine = _isMine(message);
          final stamp = chatShowsTimestamp(
            message,
            i > 0 ? _messages[i - 1] : null,
          );
          final previous = i > 0 && !stamp && _isMine(_messages[i - 1]) == mine;
          final next =
              i + 1 < _messages.length &&
              !chatShowsTimestamp(_messages[i + 1], message) &&
              _isMine(_messages[i + 1]) == mine;
          final local =
              _localReplies
                  .where((r) => identical(r.message, message))
                  .firstOrNull ??
              _receipts[message];
          final row = _ConversationMessage(
            key: ValueKey(
              local ?? message.pmid ?? (message.text, message.timeRaw, i),
            ),
            message: message,
            isMine: mine,
            showTime: stamp,
            joinsPrevious: previous,
            joinsNext: next,
            avatarUrl: widget.conversation.avatarUrl,
            peer: widget.conversation.peer,
            pending:
                local != null &&
                !local.observed &&
                (local.result == null || !local.result!.isSuccess),
            failure:
                local?.result != null &&
                    !local!.observed &&
                    !local.result!.isSuccess
                ? local.result
                : null,
            onRetry: _sending ? null : () => _send(local),
            onRefresh: () => _load(),
            onLogin: _login,
          );
          return local == null
              ? row
              : ChatArrival(
                  key: ObjectKey(local),
                  originY: local.originY,
                  animate: !local.arrived,
                  onSettled: () {
                    local.arrived = true;
                    _scrollToEnd(animate: true);
                  },
                  child: row,
                );
        },
      ),
    );
  }

  Widget _composer(AppTokens t) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(ChatTokens.composerInset),
      child: Container(
        key: _composerKey,
        padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(ChatTokens.composerRadius),
          boxShadow: ChatTokens.composerShadow(t),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: EditorTouchGuard(
                focusNode: _focus,
                builder: (context, editorFocus, onEditorTap) => TextField(
                  focusNode: editorFocus,
                  onTapAlwaysCalled: true,
                  onTap: onEditorTap,
                  key: const ValueKey('pm-input'),
                  controller: _input,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 5,
                  style: AppType.body.copyWith(
                    fontSize: ChatTokens.bodySize,
                    height: 1.5,
                    color: t.text,
                  ),
                  decoration: InputDecoration(
                    hintText: '回复 ${widget.conversation.peer}',
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (context, value, _) => ChatSendButton(
                key: const ValueKey('pm-send'),
                visible: value.text.trim().isNotEmpty,
                sending: _sending,
                onPressed: value.text.trim().isEmpty || _hasUnconfirmedReply
                    ? null
                    : _send,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LocalReply {
  final PmMessage message;
  final Set<Object> knownMessages;
  final double? originY;
  PostResult? result;
  bool observed = false;
  bool arrived = false;
  _LocalReply(this.message, this.knownMessages, {this.originY});
}

class _ConversationMessage extends StatelessWidget {
  final PmMessage message;
  final bool isMine, showTime, joinsPrevious, joinsNext, pending;
  final String? avatarUrl;
  final String peer;
  final PostResult? failure;
  final VoidCallback? onRetry;
  final VoidCallback onRefresh, onLogin;
  const _ConversationMessage({
    super.key,
    required this.message,
    required this.isMine,
    required this.showTime,
    required this.joinsPrevious,
    required this.joinsNext,
    required this.avatarUrl,
    required this.peer,
    required this.pending,
    required this.failure,
    required this.onRetry,
    required this.onRefresh,
    required this.onLogin,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final unknown = failure?.kind == PostResultKind.unknown;
    final login = failure?.kind == PostResultKind.loginRequired;
    final denied = failure?.kind == PostResultKind.permissionDenied;
    final errorText = unknown
        ? '发送结果未确认，请刷新会话'
        : login || denied
        ? failure!.message
        : '未送达，轻点重试';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTime)
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 12),
            child: Text(
              chatTimestamp(message.timeRaw),
              textAlign: TextAlign.center,
              key: ValueKey('pm-time-${message.timeRaw}'),
              style: AppType.footnote.copyWith(color: t.text3),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: joinsPrevious ? 3 : 12),
          child: Row(
            mainAxisAlignment: isMine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMine) ...[
                if (!joinsNext)
                  AvatarImage(
                    url: avatarUrl,
                    name: peer,
                    size: ChatTokens.avatar,
                  )
                else
                  const SizedBox(width: ChatTokens.avatar),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .74,
                  ),
                  child: ChatBubble(
                    text: message.text,
                    mine: isMine,
                    joinsPrevious: joinsPrevious,
                    joinsNext: joinsNext,
                    pending: pending,
                  ),
                ),
              ),
            ],
          ),
        ),
        // The reveal only lays out this newly introduced failure row.
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.revealDuration,
          curve: AppMotion.revealCurve,
          alignment: Alignment.topRight,
          child: failure == null
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (unknown || login || denied)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              errorText,
                              style: AppType.footnote.copyWith(color: t.warn),
                            ),
                          ),
                        AppButton(
                          label: unknown
                              ? '刷新'
                              : login
                              ? '登录'
                              : denied
                              ? '刷新'
                              : errorText,
                          variant: AppButtonVariant.plain,
                          onPressed: unknown || denied
                              ? onRefresh
                              : login
                              ? onLogin
                              : onRetry,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
