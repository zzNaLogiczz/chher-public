/// 私信气泡、菜单与消息到达动效（规格 §6.12）
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../design/chat_tokens.dart';
import '../core/chh_urls.dart';
import '../models/models.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../widgets/rich_content_text.dart';
import 'press.dart';

/// Only known source timestamps can establish a ten-minute gap.
bool chatShowsTimestamp(PmMessage current, PmMessage? previous) {
  if (current.timeRaw.isEmpty) return false;
  if (previous == null) return true;
  final now = DateTime.now();
  final at = ChhUrls.parseTime(current.timeRaw, now: now);
  final before = ChhUrls.parseTime(previous.timeRaw, now: now);
  return at != null &&
      before != null &&
      at.difference(before) > const Duration(minutes: 10);
}

class ChatBubble extends StatefulWidget {
  final String text;
  final List<InlineNode> nodes;
  final bool mine;
  final bool joinsPrevious;
  final bool joinsNext;
  final bool pending;
  const ChatBubble({
    super.key,
    required this.text,
    this.nodes = const [],
    required this.mine,
    this.joinsPrevious = false,
    this.joinsNext = false,
    this.pending = false,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  late final _scale = SingleMotionController(
    vsync: this,
    motion: AppMotion.reveal,
    initialValue: 1,
  );
  final _bubbleKey = GlobalKey();
  bool _holding = false;

  void _press(bool pressed) {
    if (_holding) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scale.value = 1;
    } else {
      _scale.animateTo(pressed ? ChatTokens.heldScale : 1);
    }
  }

  Future<void> _copyMenu() async {
    if (_holding) return;
    final box = _bubbleKey.currentContext!.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    _holding = true;
    _scale.value = MediaQuery.disableAnimationsOf(context)
        ? 1
        : ChatTokens.heldScale;
    final t = AppTokens.of(context);
    // The dialog must retain the source font metrics as well as its decoration.
    final menu = InheritedTheme.captureAll(
      context,
      _ChatCopyMenu(rect: rect, bubble: _content(t, 1), text: widget.text),
    );
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭复制菜单',
      barrierColor: t.scrim,
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => menu,
    );
    if (!mounted) return;
    _holding = false;
    _press(false);
  }

  Widget _content(AppTokens t, double alpha) {
    const round = Radius.circular(ChatTokens.bubbleRadius);
    const joined = Radius.circular(ChatTokens.joinedRadius);
    final style = AppType.body.copyWith(
      fontSize: ChatTokens.bodySize,
      height: 1.5,
      color: (widget.mine ? ChatTokens.outgoingForeground(t) : t.text)
          .withValues(alpha: alpha),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (widget.mine ? t.accent : t.surface).withValues(alpha: alpha),
        boxShadow: widget.mine ? null : ChatTokens.bubbleShadow(t),
        borderRadius: BorderRadius.only(
          topLeft: !widget.mine && widget.joinsPrevious ? joined : round,
          topRight: widget.mine && widget.joinsPrevious ? joined : round,
          bottomLeft: !widget.mine && widget.joinsNext ? joined : round,
          bottomRight: widget.mine && widget.joinsNext ? joined : round,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: widget.nodes.isEmpty
            ? Text(widget.text, style: style)
            : RichContentText(
                block: TextBlock(widget.text, nodes: widget.nodes),
                style: style,
              ),
      ),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      onLongPress: _copyMenu,
      child: RawGestureDetector(
        key: _bubbleKey,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: ChatTokens.hold),
                (recognizer) {
                  recognizer.onLongPressDown = (_) => _press(true);
                  recognizer.onLongPressCancel = () => _press(false);
                  recognizer.onLongPress = _copyMenu;
                  recognizer.onLongPressUp = () => _press(false);
                },
              ),
        },
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: widget.pending ? ChatTokens.pendingAlpha : 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? AppMotion.reducedFade
                : AppMotion.fade,
            builder: (_, alpha, _) =>
                RepaintBoundary(child: _content(t, alpha)),
          ),
        ),
      ),
    );
  }
}

class _ChatCopyMenu extends StatefulWidget {
  final Rect rect;
  final Widget bubble;
  final String text;
  const _ChatCopyMenu({
    required this.rect,
    required this.bubble,
    required this.text,
  });
  @override
  State<_ChatCopyMenu> createState() => _ChatCopyMenuState();
}

class _ChatCopyMenuState extends State<_ChatCopyMenu>
    with SingleTickerProviderStateMixin {
  late final _pop = SingleMotionController(
    vsync: this,
    motion: AppMotion.pop,
    initialValue: 0,
  );
  Timer? _dismiss;
  bool _copied = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _pop.value = 1;
      } else {
        _pop.animateTo(1);
      }
    });
  }

  Future<void> _copy() async {
    if (_copied) return;
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _dismiss = Timer(AppMotion.successHold, () async {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) await _pop.animateTo(0);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final size = MediaQuery.sizeOf(context);
    final rect = widget.rect;
    final top = (rect.top - 58).clamp(
      MediaQuery.paddingOf(context).top,
      size.height - 48,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
          ),
        ),
        Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: Transform.scale(
              scale: MediaQuery.disableAnimationsOf(context)
                  ? 1
                  : ChatTokens.heldScale,
              child: widget.bubble,
            ),
          ),
        ),
        Positioned(
          top: top,
          left: (rect.center.dx - 50).clamp(8, size.width - 108),
          child: AnimatedBuilder(
            animation: _pop,
            builder: (_, child) =>
                Transform.scale(scale: _pop.value, child: child),
            child: PressScale(
              onTap: _copy,
              semanticLabel: _copied ? '已复制' : '复制',
              child: Container(
                constraints: const BoxConstraints(minWidth: 100, minHeight: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: ChatTokens.menu(t),
                  borderRadius: BorderRadius.circular(
                    ChatTokens.composerRadius,
                  ),
                ),
                child: Text(
                  _copied ? '已复制' : '复制',
                  style: AppType.body.copyWith(color: ChatTokens.menuText(t)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Only a newly submitted row yields height; existing rows keep their layout.
class ChatArrival extends StatefulWidget {
  final Widget child;
  final double? originY;
  final bool animate;
  final VoidCallback onSettled;
  const ChatArrival({
    super.key,
    required this.child,
    required this.originY,
    required this.animate,
    required this.onSettled,
  });
  @override
  State<ChatArrival> createState() => _ChatArrivalState();
}

class _ChatArrivalState extends State<ChatArrival>
    with TickerProviderStateMixin {
  late final _reveal = AnimationController(
    vsync: this,
    value: widget.animate ? 0 : 1,
  );
  late final _rise = AnimationController.unbounded(vsync: this, value: 0);
  final _key = GlobalKey();
  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduced = MediaQuery.disableAnimationsOf(context);
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      _rise.value = reduced || box == null || widget.originY == null
          ? 0
          : widget.originY! - box.localToGlobal(Offset.zero).dy;
      AppMotion.settle(
        _rise,
        target: 0,
        motion: AppMotion.select,
        reduced: reduced,
      );
      AppMotion.settle(
        _reveal,
        target: 1,
        motion: AppMotion.reveal,
        reduced: reduced,
      ).whenComplete(() {
        if (mounted) widget.onSettled();
      });
    });
  }

  @override
  void dispose() {
    _reveal.dispose();
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_reveal, _rise]),
    child: RepaintBoundary(key: _key, child: widget.child),
    builder: (_, child) => Align(
      alignment: Alignment.topCenter,
      heightFactor: _reveal.value.clamp(0, 1),
      child: Transform.translate(offset: Offset(0, _rise.value), child: child),
    ),
  );
}
