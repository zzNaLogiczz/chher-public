import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderProxyBox;

/// Retained animated images must stop decoding when clipped out of view.
class ViewportTickerMode extends StatefulWidget {
  final Widget child;
  final bool initiallyVisible;
  final bool trackVisibility;
  const ViewportTickerMode({
    super.key,
    required this.child,
    this.initiallyVisible = false,
    this.trackVisibility = true,
  });

  @override
  State<ViewportTickerMode> createState() => _ViewportTickerModeState();
}

class _ViewportTickerModeState extends State<ViewportTickerMode> {
  final _positions = <ScrollPosition>{};
  List<Animation<double>> _routeAnimations = const [];
  bool _scheduled = false;
  late bool _visible = widget.initiallyVisible;
  bool _active = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _updateListeners();
  }

  @override
  void didUpdateWidget(covariant ViewportTickerMode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackVisibility != oldWidget.trackVisibility) _updateListeners();
  }

  void _updateListeners() {
    _removeListeners();
    if (!widget.trackVisibility) return;
    final route = ModalRoute.of(context);
    _routeAnimations = [?route?.animation, ?route?.secondaryAnimation];
    for (final animation in _routeAnimations) {
      animation.addListener(_checkAfterLayout);
    }
    Scrollable.maybeOf(context);
    context.visitAncestorElements((ancestor) {
      if (ancestor is StatefulElement && ancestor.state is ScrollableState) {
        _positions.add((ancestor.state as ScrollableState).position);
      }
      return true;
    });
    for (final position in _positions) {
      position.addListener(_checkAfterLayout);
    }
    _checkAfterLayout();
  }

  void _checkAfterLayout() {
    if (!widget.trackVisibility || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final view = View.of(context);
      final viewBounds =
          Offset.zero & (view.physicalSize / view.devicePixelRatio);
      var visible =
          !box.size.isEmpty &&
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            box.paintBounds,
          ).overlaps(viewBounds);
      for (
        var ancestor = box.parent;
        visible && ancestor != null;
        ancestor = ancestor.parent
      ) {
        if (ancestor is! RenderAbstractViewport) continue;
        final RenderObject viewport = ancestor;
        if (viewport is RenderBox && viewport.hasSize) {
          visible = MatrixUtils.transformRect(
            box.getTransformTo(viewport),
            box.paintBounds,
          ).overlaps(viewport.paintBounds);
        }
      }
      if (visible != _visible) setState(() => _visible = visible);
    });
  }

  void _removeListeners() {
    for (final position in _positions) {
      position.removeListener(_checkAfterLayout);
    }
    _positions.clear();
    for (final animation in _routeAnimations) {
      animation.removeListener(_checkAfterLayout);
    }
    _routeAnimations = const [];
  }

  @override
  void dispose() {
    _removeListeners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LayoutCheck(
    onLayout: _checkAfterLayout,
    child: TickerMode(enabled: _active && _visible, child: widget.child),
  );
}

class _LayoutCheck extends SingleChildRenderObjectWidget {
  final VoidCallback onLayout;
  const _LayoutCheck({required this.onLayout, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutCheck(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLayoutCheck renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderLayoutCheck extends RenderProxyBox {
  VoidCallback onLayout;
  _RenderLayoutCheck(this.onLayout);

  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}
