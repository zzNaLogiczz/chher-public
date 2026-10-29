/// Shared visual language for the expressive interaction layouts.
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

export '../design/icons.dart';

/// Keyboard-only affordance; the outline does not change layout or pointer hits.
class ActionFocusRing extends StatelessWidget {
  final bool visible;
  final Widget child;
  const ActionFocusRing({
    super.key,
    required this.visible,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: visible ? Border.all(color: t.accent, width: .5) : null,
      ),
      child: child,
    );
  }
}

/// A collapsing control retains State but stops accepting input when hidden.
class ExpressiveVisibility extends StatelessWidget {
  final bool visible;
  final Axis axis;
  final Widget child;
  const ExpressiveVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.axis = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: visible ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.tapDuration,
    curve: AppMotion.revealCurve,
    builder: (_, progress, child) => ClipRect(
      child: Align(
        alignment: Alignment.topRight,
        widthFactor: axis == Axis.horizontal ? progress : 1,
        heightFactor: axis == Axis.vertical ? progress : 1,
        child: Opacity(opacity: progress, child: child),
      ),
    ),
    child: ExcludeFocus(
      excluding: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: IgnorePointer(ignoring: !visible, child: child),
      ),
    ),
  );
}

/// A cached destination keeps its State while only its presentation layer moves.
class ExpressivePageReveal extends StatefulWidget {
  final bool active;
  final bool animateOnMount;

  /// Large cached destinations can move without an offscreen opacity layer.
  final bool fade;

  /// Replay presentation after a content change without recreating its State.
  final Object? revision;
  final bool sliver;
  final Widget child;
  const ExpressivePageReveal({
    super.key,
    required this.active,
    required this.child,
    this.animateOnMount = false,
    this.fade = true,
    this.revision,
    this.sliver = false,
  });
  @override
  State<ExpressivePageReveal> createState() => _ExpressivePageRevealState();
}

class _ExpressivePageRevealState extends State<ExpressivePageReveal>
    with SingleTickerProviderStateMixin {
  late final _progress = SingleMotionController(
    motion: AppMotion.reveal,
    vsync: this,
    initialValue: widget.animateOnMount ? 0 : 1,
  );
  void _reveal() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _progress.value = 1;
    } else {
      _progress.value = 0;
      _progress.animateTo(1);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.animateOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _reveal();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ExpressivePageReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (!oldWidget.active || oldWidget.revision != widget.revision)) {
      _reveal();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _progress.value = 1;
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    child: widget.sliver ? widget.child : RepaintBoundary(child: widget.child),
    builder: (_, child) {
      final value = _progress.value.clamp(0.0, 1.0);
      if (widget.sliver) {
        return SliverOpacity(opacity: widget.fade ? value : 1, sliver: child);
      }
      final translated = Transform.translate(
        offset: Offset(0, (1 - value) * 8),
        child: child,
      );
      return widget.fade
          ? Opacity(opacity: value, child: translated)
          : translated;
    },
  );
}
