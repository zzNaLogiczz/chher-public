/// Shared reply and comment editor, including draft and submission state.
library;

import 'dart:async';
import '../data/smiley_store.dart';
import '../design/composer_tokens.dart';
import '../design/motion.dart';
import '../design/sheet_tokens.dart';
import '../ui/sheet_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:solar_icons/solar_icons.dart';

import '../design/tokens.dart';
import 'package:flutter/services.dart';
import '../ui/quote.dart';
import '../ui/app_button.dart';
import '../models/models.dart';
import '../attachments/attachment_controller.dart';
import '../pages/web_post_page.dart';
import 'attachment_bar.dart';
import 'composer/composer_dictation_binding.dart';
import 'composer/composer_editor.dart';
import 'composer/composer_panel.dart';
import 'composer/composer_tool_strip.dart';
import 'composer/composer_emoji_input.dart';
import 'composer/smiley_editing_controller.dart';

Future<PostResult?> showExpressiveComposerRoute(
  BuildContext context, {
  required WidgetBuilder builder,
  bool docked = false,
}) {
  final t = AppTokens.of(context);
  return Navigator.of(context).push(
    AppSheetRoute<PostResult>(
      builder: builder,
      barrierColor: t.scrim,
      barrierLabel: '关闭编辑',
      reduced: MediaQuery.disableAnimationsOf(context),
      holdViewInsetsOnExit: true,
      docked: docked,
    ),
  );
}

enum _ComposePhase { idle, sending, success, failure }

class ExpressiveComposer extends StatefulWidget {
  final String title;
  final String hintText;
  final String initialText;
  final bool expandableQuote;
  final String? contextLine;
  final bool showReplyIcon;
  final bool emojiAvailable;
  final SmileyStore? smilies;
  final String unknownActionLabel;
  final Future<PostResult> Function(String) onSubmit;
  final ValueChanged<String>? onDraftChanged;
  final Future<void> Function()? onLogin;

  /// 可上传图片时提供;为 null 时不显示图片栏
  final AttachmentController? attachments;

  const ExpressiveComposer({
    super.key,
    required this.title,
    required this.hintText,
    required this.onSubmit,
    this.initialText = '',
    this.expandableQuote = false,
    this.contextLine,
    this.showReplyIcon = false,
    this.emojiAvailable = true,
    this.smilies,
    this.unknownActionLabel = '返回阅读确认',
    this.onDraftChanged,
    this.onLogin,
    this.attachments,
  });

  @override
  State<ExpressiveComposer> createState() => _ExpressiveComposerState();
}

class _ExpressiveComposerState extends State<ExpressiveComposer>
    with SingleTickerProviderStateMixin {
  final _focus = FocusNode();
  final _hasText = ValueNotifier<bool>(false);
  late final _input = SmileyEditingController(text: widget.initialText);
  ComposerEmojiInput? _emoji;
  late final ComposerDictationBinding _dictation;
  late String _lastText = widget.initialText;
  _ComposePhase _phase = _ComposePhase.idle;
  PostResult? _failure;
  static const _backChannel = MethodChannel('chh/composer_back');
  // Outgoing sheets remain mounted during their exit animation. Only the
  // current owner may release the platform callback.
  static _ExpressiveComposerState? _nativeBackOwner;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool _keyboardVisible = false;

  /// 成功后对勾的停留:用动画计时而不是裸定时器,停留期间按帧推进
  late final AnimationController _successHold;

  bool get _busy =>
      _phase == _ComposePhase.sending || _phase == _ComposePhase.success;
  bool get _uncertain => _failure?.kind == PostResultKind.unknown;

  /// 有字或有已上传的图都可以发;图片还在处理或有失败未处理时先不发
  bool get _canSend {
    final images = widget.attachments;
    if (images != null && (images.busy || images.hasFailed)) return false;
    return _hasText.value || (images?.aids.isNotEmpty ?? false);
  }

  @override
  void initState() {
    super.initState();
    // 在 initState 创建:若留到 dispose 才惰性创建,会在已失效的元素上找 TickerMode
    _successHold = AnimationController(vsync: this);
    _hasText.value = _input.text.trim().isNotEmpty;
    _input.addListener(_textChanged);
    _dictation = ComposerDictationBinding(
      editor: _input,
      onChanged: () => setState(() {}),
    );
    _focus.addListener(_syncCurrentNativeBack);
    if (widget.emojiAvailable) {
      _emoji = ComposerEmojiInput(
        input: _input,
        focus: _focus,
        store: widget.smilies ?? smileyStore,
        onChanged: _emojiChanged,
      );
    }
  }

  void _emojiChanged() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    _emoji?.updateMedia(context);
  }

  void _syncCurrentNativeBack() {
    _syncNativeBack(
      (_focus.hasFocus || _keyboardVisible || _emoji?.isOpen == true) &&
          ModalRoute.isCurrentOf(context) == true,
    );
  }

  void _syncNativeBack(bool enabled) {
    if (!_android) return;
    if (enabled) {
      if (identical(_nativeBackOwner, this)) return;
      _nativeBackOwner = this;
      _backChannel.setMethodCallHandler((call) async {
        if (call.method == 'back' &&
            mounted &&
            identical(_nativeBackOwner, this) &&
            ModalRoute.of(context)?.isCurrent == true &&
            !_busy) {
          if (_emoji?.isOpen == true) {
            _emoji!.dismiss();
          } else {
            await Navigator.of(context).maybePop();
          }
        }
      });
    } else {
      if (!identical(_nativeBackOwner, this)) return;
      _nativeBackOwner = null;
      _backChannel.setMethodCallHandler(null);
    }
    unawaited(
      _backChannel
          .invokeMethod<void>('setEnabled', enabled)
          .catchError(
            (
              Object _,
            ) {}, // Other platforms and old hosts retain normal route back.
          ),
    );
  }

  void _textChanged() {
    if (_lastText == _input.text) return;
    _lastText = _input.text;
    widget.onDraftChanged?.call(_input.text);
    final filled = _input.text.trim().isNotEmpty;
    if (_hasText.value != filled) _hasText.value = filled;
  }

  void _close([PostResult? result]) {
    if (_busy || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_busy || _dictation.active || _uncertain || !_canSend) return;
    _dictation.controller.dismissReview();
    setState(() {
      _phase = _ComposePhase.sending;
      _failure = null;
    });
    try {
      var result = await widget.onSubmit(text);
      if (!mounted) return;
      // 站点要求人机验证:转到站点页面完成,结果照常处理
      result = await completeOnWeb(context, result);
      if (!mounted) return;
      if (result.isSuccess) {
        // This state is entered only after a confirmed response from onSubmit.
        widget.onDraftChanged?.call('');
        HapticFeedback.lightImpact();
        setState(() => _phase = _ComposePhase.success);
        // 对勾停留片刻再收起,让"已发送"被看见(规格 §6.3)
        final delay = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.successHold;
        _successHold
          ..duration = delay
          ..forward(from: 0).whenComplete(() {
            if (mounted) Navigator.of(context).pop(result);
          });
      } else {
        setState(() {
          _phase = _ComposePhase.failure;
          _failure = result;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _ComposePhase.failure;
        _failure = const PostResult(
          PostResultKind.unknown,
          '暂时无法确认发送结果，内容已保留。请先返回阅读确认。',
        );
      });
    }
  }

  String _failureMessage(PostResult result) => switch (result.kind) {
    PostResultKind.loginRequired => '请先登录，内容已保留',
    PostResultKind.permissionDenied => '没有发布权限，内容已保留',
    PostResultKind.unknown => '提交状态未知，内容已保留。请先返回确认。',
    _ => result.message.isEmpty ? '暂时无法发送，内容已保留' : result.message,
  };

  @override
  void dispose() {
    _syncNativeBack(false);
    _focus.removeListener(_syncCurrentNativeBack);
    _successHold.dispose();
    _emoji?.dispose();
    _dictation.dispose();
    _input.dispose();
    _focus.dispose();
    _hasText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncCurrentNativeBack();
    final t = AppTokens.of(context);
    final hasViewport =
        context.findAncestorWidgetOfExactType<SheetViewport>() != null;
    final emoji = _emoji;
    final panel = ComposerPanel(
      title: widget.title,
      showReplyIcon: widget.showReplyIcon,
      contextLine: widget.contextLine,
      onOpenContext: !_busy && widget.expandableQuote ? _openContext : null,
      onClose: _busy ? null : _close,
      inputDocked: emoji?.reservesSpace ?? false,
      editor: ComposerEditor(
        fieldKey: const ValueKey('composer-canvas'),
        controller: _input,
        dictation: _dictation.controller,
        focusNode: _focus,
        hintText: widget.hintText,
        notifyOnUserEntry: true,
        autofocus: true,
        readOnly: _busy,
        onTap: _dictation.active ? null : emoji?.showKeyboard,
        textCapitalization: TextCapitalization.sentences,
      ),
      attachments: widget.attachments == null
          ? null
          : AttachmentBar(
              controller: widget.attachments!,
              enabled: !_busy && !_dictation.active,
              showAdd: false,
            ),
      status: _footer(t),
      voiceStatus: _dictation.status(enabled: !_busy),
      dictation: _dictation.controller,
      toolbar: _toolStrip(),
    );
    final sheet = PopScope<PostResult>(
      canPop: !_busy && emoji?.isOpen != true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _syncNativeBack(false);
        } else if (!_busy && emoji?.isOpen == true) {
          emoji!.dismiss();
        }
      },
      child: Sheet(
        dragConfiguration: SheetDragConfiguration.disabled,
        child: _dictation.scope(
          enabled: !_busy,
          emoji == null
              ? panel
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(child: panel),
                    emoji.dock(context, enabled: !_busy && !_dictation.active),
                  ],
                ),
        ),
      ),
    );
    if (hasViewport) return sheet;
    // A Scaffold embedding this editor already consumes the keyboard inset.
    final media = MediaQuery.of(context);
    return SheetViewport(
      padding: EdgeInsets.only(
        top: media.viewPadding.top + AppSheetTokens.inset,
        bottom: media.viewInsets.bottom,
      ),
      child: sheet,
    );
  }

  void _openContext() {
    showAppSheet<void>(
      context,
      builder: (_) => SheetScaffold(
        title: '引用评论',
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: ComposerTokens.editorInset,
          ),
          child: QuoteView(author: widget.title, text: widget.contextLine!),
        ),
      ),
    );
  }

  Widget _toolStrip() => ListenableBuilder(
    listenable: Listenable.merge([_hasText, ?widget.attachments]),
    builder: (context, _) {
      final images = widget.attachments;
      return ComposerToolStrip(
        leading: _emoji?.tool(enabled: !_busy && !_dictation.active),
        voice: _dictation.bar(enabled: !_busy),
        voiceActive: _dictation.barExpanded,
        image: images == null
            ? null
            : ComposerImageTool(
                key: const ValueKey('attachment-add'),
                onPressed: !_busy && !_dictation.active && images.remaining > 0
                    ? images.pick
                    : null,
                semanticLabel: images.remaining > 0
                    ? '添加图片'
                    : '最多 ${images.limit} 张图片',
              ),
        send: _sendButton(),
      );
    },
  );

  Widget _sendButton() => AppButton(
    key: const ValueKey('composer-send'),
    // 文字随状态变化,忙碌与成功时在同一个胶囊里变形
    label: switch (_phase) {
      _ComposePhase.success => '已发送',
      _ComposePhase.sending => '发送中',
      _ComposePhase.failure when !_uncertain => '重试发送',
      _ => '发送',
    },
    variant: AppButtonVariant.composerSend,
    state: switch (_phase) {
      _ComposePhase.sending => AppButtonState.busy,
      _ComposePhase.success => AppButtonState.success,
      _ => AppButtonState.idle,
    },
    onPressed: _busy || _dictation.active || _uncertain || !_canSend
        ? null
        : _send,
  );

  /// 底部只在失败、需要登录或结果未知时出现,说明状态与下一步;草稿保留
  Widget? _footer(AppTokens t) {
    final failure = _failure;
    if (failure == null) return null;
    return Padding(
      padding: ComposerTokens.statusPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                SolarIconsBold.dangerTriangle,
                color: t.red,
                size: ComposerTokens.statusIcon,
              ),
              const SizedBox(width: ComposerTokens.statusIconGap),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _failureMessage(failure),
                    style: ComposerTokens.statusText.copyWith(color: t.red),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ComposerTokens.statusActionGap),
          if (failure.kind == PostResultKind.loginRequired &&
              widget.onLogin != null)
            AppButton(
              label: '登录',
              variant: AppButtonVariant.plain,
              onPressed: widget.onLogin,
            ),
          if (_uncertain)
            AppButton(
              label: widget.unknownActionLabel,
              variant: AppButtonVariant.plain,
              onPressed: () => _close(failure),
            ),
        ],
      ),
    );
  }
}
