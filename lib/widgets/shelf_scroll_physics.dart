import 'package:flutter/widgets.dart';

import '../design/motion.dart';

/// Native drag/rubber banding, followed by a velocity-aware tile snap.
class ShelfScrollPhysics extends BouncingScrollPhysics {
  final double itemExtent;
  final bool reducedMotion;
  const ShelfScrollPhysics({
    required this.itemExtent,
    this.reducedMotion = false,
    super.parent,
  });

  @override
  ShelfScrollPhysics applyTo(ScrollPhysics? ancestor) => ShelfScrollPhysics(
    itemExtent: itemExtent,
    reducedMotion: reducedMotion,
    parent: buildParent(ancestor),
  );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);
    var page = position.pixels / itemExtent;
    if (velocity.abs() > tolerance.velocity) page += velocity.sign * .5;
    final target = (page.round() * itemExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    if (reducedMotion) return _ImmediateSnap(target);
    return ScrollSpringSimulation(
      AppMotion.select.description,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

/// Keep native drag ownership, but settle in one frame when motion is reduced.
class _ImmediateSnap extends Simulation {
  final double target;
  _ImmediateSnap(this.target);
  @override
  double x(double time) => target;
  @override
  double dx(double time) => 0;
  @override
  bool isDone(double time) => time > 0;
}
