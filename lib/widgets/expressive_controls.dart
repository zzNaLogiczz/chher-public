/// Shared visual language for the expressive interaction layouts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
        border: visible
            ? Border.all(color: t.accent, width: AppSpace.focusWidth)
            : null,
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
  final bool startOnFirstFrame;

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
    this.startOnFirstFrame = false,
    this.fade = true,
    this.revision,
    this.sliver = false,
  });
  @override
  State<ExpressivePageReveal> createState() => _ExpressivePageRevealState();
}

class _ExpressivePageRevealState extends State<ExpressivePageReveal>
    with SingleTickerProviderStateMixin {
  bool _mountRevealStarted = false;
  late final _progress = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: widget.animateOnMount && widget.fade ? 0 : 1,
  );
  void _reveal() {
    if (!widget.fade) {
      _progress.value = 1;
      return;
    }
    _progress.duration = MediaQuery.disableAnimationsOf(context)
        ? AppMotion.reducedFade
        : AppMotion.fade;
    // Paint the start of the fade on the frame that lays out the content.
    _progress.forward(from: widget.startOnFirstFrame ? 1 / 12 : 0);
  }

  @override
  void initState() {
    super.initState();
    if (widget.animateOnMount && !widget.startOnFirstFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _reveal();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ExpressivePageReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _progress.value = 1;
    if (widget.active &&
        (!oldWidget.active || oldWidget.revision != widget.revision)) {
      _reveal();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _progress.isAnimating) {
      _progress.value = 1;
    }
    if (!_mountRevealStarted && widget.startOnFirstFrame) {
      _mountRevealStarted = true;
      if (widget.animateOnMount && widget.active) _reveal();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fade a single solid cover instead of alpha-compositing the whole list.
    final background =
        context.findAncestorWidgetOfExactType<Scaffold>()?.backgroundColor ??
        Theme.of(context).scaffoldBackgroundColor;
    return AnimatedBuilder(
      animation: _progress,
      child: widget.sliver
          ? widget.child
          : RepaintBoundary(child: widget.child),
      builder: (_, child) {
        final color = background.withValues(
          alpha: widget.fade ? 1 - _progress.value : 0,
        );
        return widget.sliver
            ? _SliverArrivalCover(color: color, child: child!)
            : _ArrivalCover(color: color, child: child!);
      },
    );
  }
}

/// Reveals already laid out content by clearing a flat paint cover, with no
/// offscreen alpha layer for long replies or lists.
class ContentFade extends StatelessWidget {
  final Animation<double> opacity;
  final Color background;
  final Widget child;
  const ContentFade({
    super.key,
    required this.opacity,
    required this.background,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: opacity,
    child: child,
    builder: (_, child) => _ArrivalCover(
      color: background.withValues(alpha: 1 - opacity.value.clamp(0.0, 1.0)),
      child: child!,
    ),
  );
}

class _ArrivalCover extends SingleChildRenderObjectWidget {
  final Color color;
  const _ArrivalCover({required this.color, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArrivalCover(color);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderArrivalCover renderObject,
  ) {
    renderObject.color = color;
  }
}

class _RenderArrivalCover extends RenderProxyBox {
  _RenderArrivalCover(this._color);
  Color _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_color.a > 0) {
      context.canvas.drawRect(offset & size, Paint()..color = _color);
    }
  }
}

class _SliverArrivalCover extends SingleChildRenderObjectWidget {
  final Color color;
  const _SliverArrivalCover({required this.color, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSliverArrivalCover(color);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverArrivalCover renderObject,
  ) {
    renderObject.color = color;
  }
}

class _RenderSliverArrivalCover extends RenderProxySliver {
  _RenderSliverArrivalCover(this._color);
  Color _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_color.a > 0 && geometry!.visible) {
      final vertical = constraints.axis == Axis.vertical;
      final origin =
          offset +
          (vertical
              ? Offset(0, geometry!.paintOrigin)
              : Offset(geometry!.paintOrigin, 0));
      final size = vertical
          ? Size(constraints.crossAxisExtent, geometry!.paintExtent)
          : Size(geometry!.paintExtent, constraints.crossAxisExtent);
      context.canvas.drawRect(origin & size, Paint()..color = _color);
    }
  }
}
