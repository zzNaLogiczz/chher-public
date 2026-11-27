import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/chat_tokens.dart';
import '../../design/composer_tokens.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/sheet_tokens.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/voice_tokens.dart';
import '../../ui/press.dart';
import 'dictation_controller.dart';
import 'rim_glow.dart';

/// Bottom-docked editor. The host supplies the editor and submission controls.
class ComposerPanel extends StatefulWidget {
  final String? title;
  final bool showReplyIcon;
  final String? contextLine;
  final VoidCallback? onOpenContext;
  final VoidCallback? onClose;
  final Widget editor;
  final Widget? attachments;
  final Widget? status;
  final Widget toolbar;
  final Widget? voiceStatus;
  final DictationController? dictation;
  final bool inputDocked;

  const ComposerPanel({
    super.key,
    required String this.title,
    this.showReplyIcon = false,
    this.contextLine,
    this.onOpenContext,
    this.onClose,
    required this.editor,
    this.attachments,
    this.status,
    required this.toolbar,
    this.voiceStatus,
    this.dictation,
    this.inputDocked = false,
  });

  const ComposerPanel.docked({
    super.key,
    required this.editor,
    required this.toolbar,
    this.dictation,
    this.inputDocked = false,
  }) : title = null,
       showReplyIcon = false,
       contextLine = null,
       onOpenContext = null,
       onClose = null,
       attachments = null,
       status = null,
       voiceStatus = null;

  @override
  State<ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<ComposerPanel>
    with SingleTickerProviderStateMixin {
  final _content = GlobalKey();
  late final _offset = AnimationController.unbounded(vsync: this);
  bool _fullLayout = false;
  bool _expanded = false;
  bool _dragging = false;
  bool _draggedPastDock = false;
  double _available = 0;
  double _motionGap = 0;
  double _dragDistance = 0;
  double _dockHeight = 0;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.title != null && _reduced && _offset.isAnimating) {
      _fullLayout = _expanded;
      _draggedPastDock = false;
      _offset.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant ComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onClose == null && _dragging) {
      _dragging = false;
      _draggedPastDock = false;
      _fullLayout = _expanded;
      _offset.value = 0;
    }
  }

  @override
  void dispose() {
    if (widget.title != null) _offset.dispose();
    super.dispose();
  }

  void _prepareMotion() {
    final naturalHeight = _content.currentContext!.size!.height;
    _motionGap = math.max(0.0, _available - naturalHeight);
    if (!_fullLayout) {
      _offset.value = _motionGap;
      setState(() => _fullLayout = true);
    }
  }

  void _settle({required bool expand, double? velocity}) {
    _expanded = expand;
    AppMotion.settle(
      _offset,
      target: expand ? 0 : _motionGap,
      velocity: velocity,
      motion: AppMotion.sheet,
      reduced: _reduced,
    ).whenComplete(() {
      if (!mounted) return;
      _draggedPastDock = false;
      if (_expanded) return;
      setState(() => _fullLayout = false);
      _offset.value = 0;
    });
  }

  void _toggle() {
    _prepareMotion();
    _settle(expand: !_expanded);
  }

  void _startDrag() {
    _dockHeight = context.size!.height - (_fullLayout ? _motionGap : 0);
    _offset.stop();
    _prepareMotion();
    _dragDistance = 0;
    _dragging = true;
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_dragging || widget.onClose == null) return;
    final delta = details.primaryDelta!;
    _dragDistance += delta;
    final limit = _motionGap + (_expanded ? 0 : _dockHeight);
    final next = (_offset.value + delta).clamp(0.0, limit);
    if (next > _motionGap) _draggedPastDock = true;
    _offset.value = next;
  }

  void _endDrag(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final pastDock = _offset.value - _motionGap;
    if (!_expanded &&
        pastDock > 0 &&
        (velocity > AppSheetTokens.dismissVelocity ||
            pastDock > _dockHeight * AppSheetTokens.dismissFraction)) {
      widget.onClose?.call();
      return;
    }
    final expand = _expanded
        ? _dragDistance <= 0 && velocity <= 0
        : _offset.value < _motionGap && (_dragDistance < 0 || velocity < 0);
    _settle(expand: expand, velocity: velocity);
  }

  void _cancelDrag() {
    if (!_dragging) return;
    _dragging = false;
    _settle(expand: _expanded);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const radius = BorderRadius.vertical(
      top: Radius.circular(ComposerTokens.panelRadius),
    );
    if (widget.title == null) return _docked(t, radius);
    final canMove = widget.onClose != null;
    final body = Column(
      key: _content,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onVerticalDragStart: canMove ? (_) => _startDrag() : null,
          onVerticalDragUpdate: canMove ? _updateDrag : null,
          onVerticalDragEnd: canMove ? _endDrag : null,
          onVerticalDragCancel: canMove ? _cancelDrag : null,
          excludeFromSemantics: true,
          child: PressScale(
            scale: 1,
            semanticLabel: '展开或收起编辑区',
            onTap: canMove ? _toggle : null,
            child: SizedBox(
              key: const ValueKey('composer-drag-handle'),
              height: ComposerTokens.grabber,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.fill2,
                    borderRadius: BorderRadius.circular(
                      ComposerTokens.grabberRadius,
                    ),
                  ),
                  child: const SizedBox(
                    width: ComposerTokens.grabberWidth,
                    height: ComposerTokens.grabberThickness,
                  ),
                ),
              ),
            ),
          ),
        ),
        _heading(t),
        if (widget.contextLine case final line? when line.isNotEmpty)
          _contextLine(t, line),
        Flexible(child: widget.editor),
      ],
    );

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: _offset,
          // The footer remains docked while the top and editor move. Layout only
          // changes at the endpoints, or when the content or IME changes size.
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              _draggedPastDock ? math.max(0, _offset.value - _motionGap) : 0,
            ),
            child: child,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                fit: _fullLayout ? FlexFit.tight : FlexFit.loose,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _available = constraints.maxHeight;
                    return ClipRect(
                      clipper: widget.dictation == null
                          ? null
                          : const _RimPanelClipper(),
                      child: AnimatedBuilder(
                        animation: _offset,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, _offset.value.clamp(0, _motionGap)),
                          child: child,
                        ),
                        child: _withRim(
                          AppClip.borderRadius(
                            borderRadius: radius,
                            child: ColoredBox(
                              color: t.surface,
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: 1,
                                child: body,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _footer(t, constraints.maxHeight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _docked(AppTokens t, BorderRadius radius) => _withRim(
    DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: ChatTokens.composerShadow(t),
      ),
      child: AppClip.borderRadius(
        borderRadius: radius,
        child: Material(
          color: t.surface,
          child: SafeArea(
            top: false,
            bottom: !widget.inputDocked,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(
              top: ComposerTokens.chatPanelTopInset,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [widget.editor, widget.toolbar],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _withRim(Widget content) {
    final controller = widget.dictation;
    if (controller == null) return content;
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(
          left: 0,
          right: 0,
          top: -RimTokens.top,
          height: RimTokens.height,
          child: RimGlow(controller: controller),
        ),
      ],
    );
  }

  Widget _footer(AppTokens t, double panelLimit) {
    final media = MediaQuery.of(context);
    final safeBottom = !widget.inputDocked && media.viewInsets.bottom == 0
        ? media.padding.bottom
        : 0.0;
    // Keep long notices and accessibility text from pushing the editor or send
    // off screen, even when a keyboard takes up most of the available height.
    final detailsLimit = math.max(
      0.0,
      (panelLimit - ComposerTokens.strip - safeBottom) / 2,
    );
    return ColoredBox(
      color: t.surface,
      child: Padding(
        padding: EdgeInsets.only(bottom: safeBottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.attachments != null ||
                widget.status != null ||
                widget.voiceStatus != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: detailsLimit),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?widget.attachments,
                      ?widget.status,
                      ?widget.voiceStatus,
                    ],
                  ),
                ),
              ),
            widget.toolbar,
          ],
        ),
      ),
    );
  }

  Widget _heading(AppTokens t) => Padding(
    padding: const EdgeInsets.only(
      left: ComposerTokens.editorInset,
      right: ComposerTokens.headerEndInset,
    ),
    child: Row(
      children: [
        if (widget.showReplyIcon) ...[
          Icon(AppIcons.reply, size: ComposerTokens.replyIcon, color: t.text3),
          const SizedBox(width: ComposerTokens.headerGap),
        ],
        Expanded(
          child: Text(
            widget.title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ComposerTokens.title.copyWith(color: t.text),
          ),
        ),
        PressHighlight(
          onTap: widget.onClose,
          borderRadius: BorderRadius.circular(ComposerTokens.cancelRadius),
          color: t.fill,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ComposerTokens.headerHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ComposerTokens.cancelInset,
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  '取消',
                  style: ComposerTokens.cancel.copyWith(
                    color: widget.onClose == null ? t.text3 : t.text2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _contextLine(AppTokens t, String line) {
    final text = Text(
      line,
      key: const ValueKey('composer-context'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppType.footnote.copyWith(color: t.text3),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.showReplyIcon
            ? ComposerTokens.quoteInset
            : ComposerTokens.editorInset,
        0,
        ComposerTokens.contextEndInset,
        ComposerTokens.contextBottomInset,
      ),
      child: widget.onOpenContext == null
          ? text
          : PressHighlight(
              onTap: widget.onOpenContext,
              semanticLabel: '查看引用',
              child: Align(alignment: Alignment.centerLeft, child: text),
            ),
    );
  }
}

class _RimPanelClipper extends CustomClipper<Rect> {
  const _RimPanelClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -RimTokens.top, size.width, size.height);

  @override
  bool shouldReclip(_RimPanelClipper oldClipper) => false;
}
