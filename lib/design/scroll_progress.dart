import 'package:flutter/widgets.dart';

import 'motion.dart';

/// A compact bar's position, driven by scroll pixels without rebuilding its page.
/// Attach after the ScrollPosition exists; dispose before disposing its owner.
class ScrollLinkedProgress extends ValueNotifier<double> {
  ScrollLinkedProgress({
    required this.position,
    required this.start,
    required this.end,
    this.reduced = false,
  }) : assert(end > start),
       super(((position.pixels - start) / (end - start)).clamp(0.0, 1.0)) {
    position.addListener(_update);
    position.isScrollingNotifier.addListener(_idleChanged);
  }

  final ScrollPosition position;
  final double start;
  final double end;
  bool reduced;
  bool _snapping = false;
  bool _disposed = false;

  void _update() {
    value = ((position.pixels - start) / (end - start)).clamp(0.0, 1.0);
  }

  void _idleChanged() {
    // Drag and ballistic activities both report scrolling. Never fight inertia.
    if (position.isScrollingNotifier.value || _snapping) return;
    snapIfIdle();
  }

  Future<void> snapIfIdle() async {
    if (_disposed || _snapping || position.isScrollingNotifier.value) return;
    if (value < .2 || value > .8) return;
    _snapping = true;
    try {
      await AppMotion.scrollTo(
        position,
        value < .5 ? start : end,
        reduced: reduced,
      );
    } finally {
      _snapping = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    position.removeListener(_update);
    position.isScrollingNotifier.removeListener(_idleChanged);
    super.dispose();
  }
}

/// A floating control follows every scroll pixel, then settles only when idle.
class ScrollDeltaProgress extends ValueNotifier<double> {
  ScrollDeltaProgress({required TickerProvider vsync, required this.travel})
    : _spring = AnimationController.unbounded(vsync: vsync),
      super(0) {
    _spring.addListener(_tick);
  }

  final double travel;
  final AnimationController _spring;
  void _tick() => value = _spring.value.clamp(0.0, 1.0);

  void drag(double delta, {bool reduced = false}) {
    _spring.stop();
    final next = (value + delta / travel).clamp(0.0, 1.0);
    _spring.value = reduced ? (delta > 0 ? 1 : 0) : next;
  }

  void stop() => _spring.stop();
  void show() => _spring.value = 0;

  void settle({double velocity = 0, bool reduced = false}) {
    AppMotion.settle(
      _spring,
      target: value < .5 ? 0 : 1,
      velocity: velocity / travel,
      motion: AppMotion.reveal,
      reduced: reduced,
    );
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }
}
