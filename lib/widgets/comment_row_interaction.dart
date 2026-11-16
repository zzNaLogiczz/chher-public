import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../design/thread_interaction_tokens.dart';
import '../design/tokens.dart';
import '../ui/press.dart';

/// 仅长按打开操作；同一楼层的惰性片段可共享 highlight。
class CommentRowInteraction extends StatefulWidget {
  final Widget child;
  final VoidCallback onLongPress;
  final ValueNotifier<bool>? highlight;

  const CommentRowInteraction({
    super.key,
    required this.child,
    required this.onLongPress,
    this.highlight,
  });

  @override
  State<CommentRowInteraction> createState() => _CommentRowInteractionState();
}

class _CommentRowInteractionState extends State<CommentRowInteraction> {
  final _localHighlight = ValueNotifier(false);
  ValueNotifier<bool> get _highlight => widget.highlight ?? _localHighlight;
  Timer? _tintTimer;
  Offset? _origin;
  int? _pointer;
  ScrollPosition? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (_scroll == scroll) return;
    _scroll?.isScrollingNotifier.removeListener(_scrollChanged);
    _scroll = scroll;
    _scroll?.isScrollingNotifier.addListener(_scrollChanged);
  }

  void _scrollChanged() {
    if (_scroll?.isScrollingNotifier.value == true) _cancel();
  }

  void _cancel() {
    _tintTimer?.cancel();
    _tintTimer = null;
    _pointer = null;
    _origin = null;
    _highlight.value = false;
  }

  @override
  void dispose() {
    _tintTimer?.cancel();
    _scroll?.isScrollingNotifier.removeListener(_scrollChanged);
    _localHighlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      if (_pointer != null) return;
      _pointer = event.pointer;
      _origin = event.position;
      _tintTimer = Timer(ThreadInteractionTokens.holdTintDelay, () {
        if (mounted && _pointer != null) _highlight.value = true;
      });
    },
    onPointerMove: (event) {
      final origin = _origin;
      if (event.pointer == _pointer &&
          origin != null &&
          (event.position - origin).distance > kTouchSlop) {
        _cancel();
      }
    },
    onPointerUp: (event) {
      if (event.pointer == _pointer) _cancel();
    },
    onPointerCancel: (_) => _cancel(),
    child: Semantics(
      container: true,
      onLongPress: widget.onLongPress,
      child: RawGestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: ThreadInteractionTokens.holdMenuDelay,
                ),
                (recognizer) => recognizer
                  ..onLongPress = () {
                    if (_pointer == null) return;
                    _cancel();
                    widget.onLongPress();
                  }
                  ..onLongPressCancel = _cancel,
              ),
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: _highlight,
          child: widget.child,
          builder: (context, highlighted, child) => Stack(
            children: [
              child!,
              if (highlighted)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: AppTokens.of(context).text.withValues(
                        alpha: ThreadInteractionTokens.holdTintOpacity,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 三个细点与时间同色，触区按定稿保持 34 × 28。
class CommentMoreButton extends StatelessWidget {
  final VoidCallback onPressed;
  const CommentMoreButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => PressHighlight(
    semanticLabel: '更多操作',
    onTap: onPressed,
    borderRadius: BorderRadius.circular(ThreadInteractionTokens.moreRadius),
    child: SizedBox(
      width: ThreadInteractionTokens.moreWidth,
      height: ThreadInteractionTokens.moreHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: ThreadInteractionTokens.dotGap),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTokens.of(context).text3,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(
                dimension: ThreadInteractionTokens.dotSize,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
