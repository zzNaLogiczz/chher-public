/// 统一按压反馈
///
/// 块状控件用 [PressScale](整体缩小),整行用 [PressHighlight](底色变深)。
/// 两者共享同一套按压核心:按下立即反馈、移动超过 touch slop 取消、
/// Enter/Space 触发、仅键盘焦点显示焦点环。
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../widgets/expressive_controls.dart' show ActionFocusRing;

/// 按压核心:只负责手势、键盘、语义与焦点环,反馈由 [builder] 与 [onPressedChanged] 决定。
class _PressCore extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final ValueChanged<bool> onPressedChanged;
  final Widget Function(BuildContext context, Widget ringed) builder;
  final Widget child;

  const _PressCore({
    required this.onTap,
    required this.onLongPress,
    required this.semanticLabel,
    required this.onPressedChanged,
    required this.builder,
    required this.child,
  });

  @override
  State<_PressCore> createState() => _PressCoreState();
}

class _PressCoreState extends State<_PressCore> {
  Offset? _origin;
  bool _down = false;
  bool _showFocus = false;

  void _press(bool down) {
    if (!mounted || _down == down || (down && widget.onTap == null)) return;
    _down = down;
    widget.onPressedChanged(down);
  }

  @override
  void didUpdateWidget(covariant _PressCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 按压中途被禁用:立刻释放反馈
    if (widget.onTap == null && _down) {
      _origin = null;
      _press(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (value) {
          if (mounted && value != _showFocus) {
            setState(() => _showFocus = value);
          }
        },
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            _origin = event.position;
            _press(true);
          },
          onPointerMove: (event) {
            final origin = _origin;
            if (origin != null &&
                (event.position - origin).distanceSquared >
                    kTouchSlop * kTouchSlop) {
              _press(false);
            }
          },
          onPointerUp: (_) {
            _origin = null;
            _press(false);
          },
          onPointerCancel: (_) {
            _origin = null;
            _press(false);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onTapCancel: () => _press(false),
            child: widget.builder(
              context,
              ActionFocusRing(
                visible: _showFocus && enabled,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 块状控件的按压:按下整体缩小,松手以 [AppMotion.tap] 弹回。
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.semanticLabel,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final _scale = SingleMotionController(
    motion: AppMotion.tap,
    vsync: this,
    initialValue: 1,
  );
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) _scale.value = 1;
  }

  void _onPressed(bool down) {
    if (_reduced) {
      _scale.value = 1;
    } else {
      _scale.animateTo(down ? widget.scale : 1);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PressCore(
    onTap: widget.onTap,
    onLongPress: widget.onLongPress,
    semanticLabel: widget.semanticLabel,
    onPressedChanged: _onPressed,
    builder: (_, ringed) => AnimatedBuilder(
      animation: _scale,
      child: ringed,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
    ),
    child: widget.child,
  );
}

/// 整行列表项的按压:按下立即铺上 `pressed` 底色,松手 200ms 淡回透明,不缩放。
class PressHighlight extends StatefulWidget {
  /// 松手后底色淡回的时长(规格 §5.7 规则 3 规定,允许的非弹簧例外)
  static const fadeBack = Duration(milliseconds: 200);

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final String? semanticLabel;

  /// 按下底色,默认 `pressed`;浮动胶囊内的格子用 `fill`(规格 §6.2)
  final Color? color;

  const PressHighlight({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.semanticLabel,
    this.color,
  });

  @override
  State<PressHighlight> createState() => _PressHighlightState();
}

class _PressHighlightState extends State<PressHighlight>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: PressHighlight.fadeBack,
  );

  void _onPressed(bool down) {
    if (down) {
      _fade.value = 1;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _fade.value = 0;
    } else {
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = widget.color ?? AppTokens.of(context).pressed;
    return _PressCore(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      semanticLabel: widget.semanticLabel,
      onPressedChanged: _onPressed,
      builder: (_, ringed) => AnimatedBuilder(
        animation: _fade,
        child: ringed,
        builder: (_, child) {
          final tint = ColoredBox(
            color: Color.lerp(
              pressed.withValues(alpha: 0),
              pressed,
              _fade.value,
            )!,
            child: child,
          );
          final radius = widget.borderRadius;
          return radius == null
              ? tint
              : ClipRRect(borderRadius: radius, child: tint);
        },
      ),
      child: widget.child,
    );
  }
}
