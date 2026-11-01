import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../design/feedback.dart';

/// Forward the transparent margins past Column/Wrap's normal bounds checks.
/// Entries still go through PressScale and the enclosing scrollable's hit path.
class HitSlopRegion extends SingleChildRenderObjectWidget {
  const HitSlopRegion({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitSlopRegion();
}

class _RenderHitSlopRegion extends RenderProxyBox {
  final _targets = <_RenderHitSlopTarget>{};

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Actual content takes precedence over a neighbouring capsule's hit margin.
    if (super.hitTest(result, position: position)) return true;
    for (final target in _targets.toList().reversed) {
      if (!target.attached || !target.enabled) continue;
      final hit = result.addWithPaintTransform(
        transform: target.getTransformTo(this),
        position: position,
        hitTest: (result, local) =>
            target.hitTestExpanded(result, position: local),
      );
      if (hit) {
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
    }
    return false;
  }
}

class HitSlopTarget extends SingleChildRenderObjectWidget {
  final bool enabled;

  /// The default preserves the feedback capsules' vertical-only hit margins.
  final EdgeInsets slop;
  const HitSlopTarget({
    super.key,
    required this.enabled,
    this.slop = const EdgeInsets.symmetric(
      vertical: FeedbackMetrics.capsuleHitSlop,
    ),
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    assert(slop.isNonNegative);
    return _RenderHitSlopTarget(enabled, slop);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    assert(slop.isNonNegative);
    (renderObject as _RenderHitSlopTarget)
      ..enabled = enabled
      ..slop = slop;
  }
}

class _RenderHitSlopTarget extends RenderProxyBox {
  bool enabled;
  EdgeInsets slop;
  _RenderHitSlopRegion? _region;
  _RenderHitSlopTarget(this.enabled, this.slop);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (
      RenderObject? ancestor = parent;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      if (ancestor is _RenderHitSlopRegion) {
        _region = ancestor;
        // The outermost region checks all visible siblings before any slop.
        // A nested feedback region must not steal taps from visible post text.
      }
    }
    _region?._targets.add(this);
  }

  @override
  void detach() {
    _region?._targets.remove(this);
    _region = null;
    super.detach();
  }

  bool hitTestExpanded(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      return super.hitTest(result, position: position);
    }
    final bounds = Rect.fromLTRB(
      -slop.left,
      -slop.top,
      size.width + slop.right,
      size.height + slop.bottom,
    );
    if (!enabled || !bounds.contains(position)) return false;
    // Translate the whole pointer sequence, so PressScale keeps its normal
    // gesture arena, movement cancellation, and pressed-state behavior.
    final inside = Offset(
      position.dx < 0 || position.dx >= size.width
          ? size.width / 2
          : position.dx,
      size.height / 2,
    );
    return result.addWithPaintOffset(
      offset: position - inside,
      position: position,
      hitTest: (result, local) => super.hitTest(result, position: local),
    );
  }
}
