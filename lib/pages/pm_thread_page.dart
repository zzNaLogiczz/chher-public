/// Private conversations keep drafts on failed or uncertain sends.
library;

import 'package:flutter/material.dart';
import '../ui/editor_touch.dart';
import '../ui/app_button.dart';
import '../ui/bottom_bar.dart';
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
  List<PmMessage> _messages = const [];
  bool _loading = false;
  bool _sending = false;
  bool _loaded = false;
  Object? _loadError;
  PostResult? _sendError;
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
        _messages = result;
        _loaded = true;
      });
      if (scrollToEnd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            if (animateScroll && !MediaQuery.disableAnimationsOf(context)) {
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: AppMotion.revealDuration,
                curve: AppMotion.revealCurve,
              );
            } else {
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          if (e is PageMessage &&
              (e.kind == PageMessageKind.loginRequired ||
                  e.kind == PageMessageKind.permissionDenied)) {
            _messages = const [];
            _loaded = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || _loading || !_loaded || _announcement || text.isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final result = await _repository.reply(
        viewUrl: widget.conversation.viewUrl,
        message: text,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        _input.clear();
        _focus.unfocus();
        AppToast.show(context, '已发送');
        await _load(scrollToEnd: true, animateScroll: true);
      } else {
        setState(() => _sendError = result);
      }
    } on PageMessage catch (e) {
      if (mounted) {
        setState(
          () => _sendError = PostResult(
            e.kind == PageMessageKind.loginRequired
                ? PostResultKind.loginRequired
                : e.kind == PageMessageKind.permissionDenied
                ? PostResultKind.permissionDenied
                : PostResultKind.failed,
            e.text,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _sendError = const PostResult(
            PostResultKind.failed,
            '发送未完成，输入内容已保留',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _login() async {
    await Navigator.of(context).pushNamed('/login');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: t.bg,
        toolbarHeight:
            56 +
            (MediaQuery.textScalerOf(context).scale(AppType.sizeBody) -
                    AppType.sizeBody) *
                2,
        leading: Navigator.canPop(context)
            ? ChromeButton(
                icon: AppIcons.back,
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        // 对方名字居中(规格 §7 私信会话),安卓默认标题靠左
        centerTitle: true,
        title: Column(
          children: [
            Text(
              widget.conversation.peer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.sizeBody,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
            Text(
              _announcement ? '公共消息' : '私人消息',
              style: TextStyle(fontSize: AppType.sizeFootnote, color: t.text2),
            ),
          ],
        ),
        actions: [
          ChromeButton(
            tooltip: '刷新会话',
            icon: AppIcons.refresh,
            onPressed: _loading ? null : () => _load(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ExpressivePageReveal(
              active: true,
              revision: _loaded,
              child: _body(t),
            ),
          ),
          if (!_announcement)
            ExpressiveVisibility(visible: _loaded, child: _composer(t)),
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        itemCount: _messages.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            if (_messages.isEmpty) {
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
          final message = _messages[index - 1];
          final selfUid = chhSession.badges.uid;
          return _ConversationMessage(
            message: message,
            // 源站标"您"的就是自己;否则用作者 UID 与当前账号比对
            isMine:
                message.fromSelf ||
                (selfUid != null && message.authorUid == selfUid),
          );
        },
      ),
    );
  }

  Widget _composer(AppTokens t) => BottomBar(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExpressiveVisibility(
          visible: _sendError != null,
          child: _sendError == null
              ? const SizedBox.shrink()
              : _failure(t, _sendError!),
        ),
        Row(
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
                  style: TextStyle(
                    fontSize: AppType.sizeBody,
                    height: 1.5,
                    color: t.text,
                  ),
                  // 胶囊输入框,没有边框和聚焦描边
                  decoration: InputDecoration(
                    hintText: '回复 ${widget.conversation.peer}',
                    filled: true,
                    fillColor: t.fill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      borderSide: BorderSide.none,
                    ),
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
                onPressed: _loading || value.text.trim().isEmpty ? null : _send,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _failure(AppTokens t, PostResult result) {
    final login = result.kind == PostResultKind.loginRequired;
    final text = result.kind == PostResultKind.unknown
        ? '发送结果未确认，请刷新会话'
        : result.message;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: AppType.sizeFootnote,
                  height: 1.5,
                  color: t.warn,
                ),
              ),
            ),
          ),
          AppButton(
            label: login ? '登录' : '刷新',
            variant: AppButtonVariant.plain,
            onPressed: _sending
                ? null
                : login
                ? _login
                : () => _load(),
          ),
        ],
      ),
    );
  }
}

class _ConversationMessage extends StatelessWidget {
  final PmMessage message;
  final bool isMine;
  const _ConversationMessage({required this.message, required this.isMine});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .74,
        ),
        margin: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.fromLTRB(3, 0, 3, 7),
                child: Text(
                  message.author,
                  style: TextStyle(
                    fontSize: AppType.sizeFootnote,
                    height: 1.5,
                    color: t.text2,
                  ),
                ),
              ),
            ChatBubble(text: message.text, mine: isMine),
            if (message.timeRaw.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(3, 6, 3, 0),
                child: Text(
                  message.timeRaw,
                  style: TextStyle(
                    fontSize: AppType.sizeFootnote,
                    height: 1.4,
                    color: t.text3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
