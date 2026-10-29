/// Shared editorial writing canvas backed by smooth_sheets, Solar Bold and Motor.
library;

import 'dart:async';
import '../design/motion.dart';

import 'package:flutter/material.dart';
import '../ui/editor_touch.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:solar_icons/solar_icons.dart';

import '../design/tokens.dart';
import 'package:flutter/services.dart';
import '../design/typography.dart';
import '../ui/quote.dart';
import '../ui/app_button.dart';
import '../models/models.dart';
import '../attachments/attachment_controller.dart';
import '../pages/web_post_page.dart';
import 'attachment_bar.dart';

Future<PostResult?> showExpressiveComposerRoute(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final t = AppTokens.of(context);
  return Navigator.of(context).push(
    ModalSheetRoute<PostResult>(
      builder: builder,
      barrierDismissible: true,
      barrierColor: t.scrim,
      barrierLabel: '关闭编辑',
      swipeDismissible: true,
      swipeDismissSensitivity: const SwipeDismissSensitivity(
        minFlingVelocityRatio: 1.6,
        dismissalOffset: SheetOffset(.32),
      ),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.sheetDuration,
      viewportBuilder: (context, child) => SheetViewport(
        padding: EdgeInsets.only(
          top: MediaQuery.viewPaddingOf(context).top + 8,
        ),
        child: child,
      ),
    ),
  );
}

enum _ComposePhase { idle, sending, success, failure }

class ExpressiveComposer extends StatefulWidget {
  final String title;
  final String modeLabel;
  final String hintText;
  final String initialText;
  final String? quoteLabel;
  final String? quoteText;
  final String unknownActionLabel;
  final Future<PostResult> Function(String) onSubmit;
  final ValueChanged<String>? onDraftChanged;
  final Future<void> Function()? onLogin;

  /// 可上传图片时提供;为 null 时不显示图片栏
  final AttachmentController? attachments;

  const ExpressiveComposer({
    super.key,
    required this.title,
    required this.modeLabel,
    required this.hintText,
    required this.onSubmit,
    this.initialText = '',
    this.quoteLabel,
    this.quoteText,
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
  final _sheet = SheetController();
  final _focus = FocusNode();
  final _hasText = ValueNotifier<bool>(false);
  final _expanded = ValueNotifier<bool>(false);
  late final _input = TextEditingController(text: widget.initialText);
  late String _lastText = widget.initialText;
  _ComposePhase _phase = _ComposePhase.idle;
  PostResult? _failure;
  bool _keyboardVisible = false;
  double _fullExtent = 1;

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
    _sheet.addListener(_sheetChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _fullExtent = (media.size.height - media.viewPadding.top - 8).clamp(
      1.0,
      double.infinity,
    );
    final visible = media.viewInsets.bottom > 0;
    if (visible && !_keyboardVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sheet.hasClient) _moveSheet(expand: true);
      });
    }
    _keyboardVisible = visible;
  }

  void _textChanged() {
    if (_lastText == _input.text) return;
    _lastText = _input.text;
    widget.onDraftChanged?.call(_input.text);
    final filled = _input.text.trim().isNotEmpty;
    if (_hasText.value != filled) _hasText.value = filled;
  }

  void _sheetChanged() {
    final expanded = (_sheet.value ?? 0) > _fullExtent * .84;
    if (_expanded.value != expanded) _expanded.value = expanded;
  }

  void _moveSheet({required bool expand}) {
    if (_busy || !_sheet.hasClient) return;
    if (!expand) _focus.unfocus();
    _sheet.animateTo(
      SheetOffset(expand ? 1 : .62),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.revealDuration,
      curve: AppMotion.revealCurve,
    );
  }

  void _close([PostResult? result]) {
    if (_busy) return;
    _focus.unfocus();
    Navigator.of(context).pop(result);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_busy || _uncertain || !_canSend) return;
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
    _successHold.dispose();
    _input.dispose();
    _focus.dispose();
    _hasText.dispose();
    _expanded.dispose();
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final hasViewport =
        context.findAncestorWidgetOfExactType<SheetViewport>() != null;
    final sheet = PopScope(
      canPop: !_busy,
      child: SheetKeyboardDismissible(
        dismissBehavior: const SheetKeyboardDismissBehavior.onDragDown(
          isContentScrollAware: false,
        ),
        child: Sheet(
          controller: _sheet,
          initialOffset: SheetOffset(hasViewport ? .62 : 1),
          snapGrid: const SheetSnapGrid(
            snaps: [SheetOffset(.62), SheetOffset(1)],
          ),
          dragConfiguration: _busy
              ? SheetDragConfiguration.disabled
              : const SheetDragConfiguration(),
          scrollConfiguration: _busy
              ? SheetScrollConfiguration.disabled
              : const SheetScrollConfiguration(),
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
            bottomBarVisibility: const BottomBarVisibility.always(
              ignoreBottomInset: true,
            ),
            // 图片横栏贴在可视区域底部:sheet 让出键盘高度,横栏随键盘上移
            bottomBar: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _footer(t),
                if (widget.attachments != null)
                  AttachmentBar(
                    controller: widget.attachments!,
                    enabled: !_busy,
                  ),
              ],
            ),
            body: SizedBox.expand(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.quoteLabel != null ||
                        (widget.quoteText?.isNotEmpty ?? false))
                      QuoteView(
                        author: widget.quoteLabel ?? '引用内容',
                        text: widget.quoteText ?? '',
                      ),
                    const SizedBox(height: 8),
                    EditorTouchGuard(
                      focusNode: _focus,
                      enabled: !_busy,
                      notifyOnUserEntry: true,
                      builder: (context, editorFocus, onEditorTap) => TextField(
                        focusNode: editorFocus,
                        onTapAlwaysCalled: true,
                        onTap: onEditorTap,
                        key: const ValueKey('composer-canvas'),
                        controller: _input,

                        autofocus: true,
                        readOnly: _busy,
                        minLines: 5,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                          fontSize: AppType.sizeBody,
                          height: 1.8,
                          color: t.text,
                          letterSpacing: 0,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: TextStyle(
                            color: t.text3,
                            fontSize: AppType.sizeBody,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (hasViewport) return sheet;
    // Public constructors are also embeddable in a page/preview, not only a modal.
    return SheetViewport(
      padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top + 8),
      child: sheet,
    );
  }

  /// 头部一行:左取消、中间标题、右发送。键盘弹出时发送始终在视线内(规格 §6.11)
  Widget _header(AppTokens t) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        label: '拖动展开或收起编辑',
        child: SizedBox(
          key: const ValueKey('composer-drag-handle'),
          height: 21,
          width: double.infinity,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.fill2,
                borderRadius: BorderRadius.circular(AppRadii.bar),
              ),
              child: const SizedBox(width: 36, height: 5),
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
              onPressed: _busy ? null : () => _close(),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.headline.copyWith(color: t.text),
                  ),
                  Text(
                    widget.modeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.footnote.copyWith(color: t.text3),
                  ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([_hasText, ?widget.attachments]),
              builder: (context, _) => AppButton(
                key: const ValueKey('composer-send'),
                // 文字随状态变化,忙碌与成功时在同一个胶囊里变形
                label: switch (_phase) {
                  _ComposePhase.success => '已发送',
                  _ComposePhase.sending => '发送中',
                  _ComposePhase.failure when !_uncertain => '重试发送',
                  _ => '发送',
                },
                small: true,
                state: switch (_phase) {
                  _ComposePhase.sending => AppButtonState.busy,
                  _ComposePhase.success => AppButtonState.success,
                  _ => AppButtonState.idle,
                },
                onPressed: _busy || _uncertain || !_canSend ? null : _send,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// 底部只在失败、需要登录或结果未知时出现,说明状态与下一步;草稿保留
  Widget _footer(AppTokens t) => _failure == null
      ? const SizedBox.shrink()
      : DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.separator, width: .5)),
          ),
          child: SafeArea(
            top: false,
            // 下面还有图片横栏时,底部安全区由横栏负责
            bottom: widget.attachments == null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_failure != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            SolarIconsBold.dangerTriangle,
                            color: t.red,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _failureMessage(_failure!),
                                style: TextStyle(
                                  fontSize: AppType.sizeFootnote,
                                  color: t.red,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_failure?.kind == PostResultKind.loginRequired &&
                      widget.onLogin != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: '登录',
                        variant: AppButtonVariant.plain,
                        onPressed: widget.onLogin,
                      ),
                    ),
                  if (_uncertain)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: widget.unknownActionLabel,
                        variant: AppButtonVariant.plain,
                        onPressed: () => _close(_failure),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
}
