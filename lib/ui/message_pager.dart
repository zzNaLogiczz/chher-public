import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../design/message_tokens.dart';
import '../design/motion.dart';

/// Pixel velocity is positive when the finger moves right.
int messageSwipeTarget({
  required int start,
  required double position,
  required double velocity,
}) {
  if (velocity.abs() > MessageTokens.swipeVelocity) {
    return (start + (velocity < 0 ? 1 : -1)).clamp(0, 1);
  }
  final distance = position - start;
  return distance.abs() > MessageTokens.swipeThreshold
      ? (start + distance.sign.toInt()).clamp(0, 1)
      : start;
}

/// Two lazy, preserved scroll pages driven by the same position as both selectors.
class MessagePager extends StatefulWidget {
  final int value;
  final ValueNotifier<double> position;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onVisit;
  final Widget Function(BuildContext context, int index) itemBuilder;

  const MessagePager({
    super.key,
    required this.value,
    required this.position,
    required this.onChanged,
    required this.itemBuilder,
    this.onVisit,
  }) : assert(value == 0 || value == 1);

  @override
  State<MessagePager> createState() => _MessagePagerState();
}

class _MessagePagerState extends State<MessagePager>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController.unbounded(
    vsync: this,
    value: widget.value.toDouble(),
  )..addListener(_publish);
  late final _visited = <int>{widget.value};
  late int _target;
  bool _moving = false;
  bool _dragging = false;
  double _raw = 0;
  double _width = 1;
  int _generation = 0;
  double _interruptedVelocity = 0;
  bool _publishPending = false;

  @override
  void initState() {
    super.initState();
    _target = widget.value;
    // Force initialization before a reduced-motion dependency update.
    _motion;
  }

  void _publish() {
    // Reduced-motion dependency updates can happen after a sibling selector built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_publishPending) return;
      _publishPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _publishPending = false;
        if (mounted) widget.position.value = _motion.value;
      });
    } else {
      widget.position.value = _motion.value;
    }
  }

  @override
  void didUpdateWidget(MessagePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _target) {
      _target = widget.value;
      _visit(_target);
      _settle(_target);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !_dragging) {
      _motion.value = _target.toDouble();
      _moving = false;
    }
  }

  void _visit(int index) {
    if (_visited.add(index)) widget.onVisit?.call(index);
  }

  void _settle(int target, {double? velocity}) {
    final generation = ++_generation;
    final reduced = MediaQuery.disableAnimationsOf(context);
    setState(() => _moving = !reduced);
    AppMotion.settle(
      _motion,
      target: target.toDouble(),
      motion: AppMotion.select,
      velocity: velocity,
      reduced: reduced,
    ).whenCompleteOrCancel(() {
      if (!mounted || generation != _generation) return;
      setState(() => _moving = false);
    });
  }

  double _resist(double raw) {
    if (raw >= 0 && raw <= 1) return raw;
    final edge = raw < 0 ? 0.0 : 1.0;
    final distance = raw - edge;
    return edge +
        distance / (1 + distance.abs() / MessageTokens.overscrollLimit);
  }

  void _down(DragDownDetails details) {
    _generation++;
    _interruptedVelocity = _motion.velocity;
    _motion.stop();
  }

  void _start(DragStartDetails details) {
    _dragging = true;
    _raw = _motion.value;
    if (_raw < 0 || _raw > 1) {
      final edge = _raw < 0 ? 0.0 : 1.0;
      final distance = _raw - edge;
      _raw =
          edge +
          distance / (1 - distance.abs() / MessageTokens.overscrollLimit);
    }
    setState(() => _moving = true);
  }

  void _update(DragUpdateDetails details) {
    _raw -= details.delta.dx / _width;
    // Build the next page as soon as it enters the viewport, after direction lock.
    final entering = _raw > widget.value ? 1 : 0;
    if (!_visited.contains(entering)) {
      setState(() => _visit(entering));
    }
    _motion.value = _resist(_raw);
  }

  void _end(DragEndDetails details) {
    _dragging = false;
    final velocity = details.velocity.pixelsPerSecond.dx;
    _target = messageSwipeTarget(
      start: widget.value,
      position: _motion.value,
      velocity: velocity,
    );
    _visit(_target);
    if (_target != widget.value) widget.onChanged(_target);
    _settle(_target, velocity: -velocity / _width);
  }

  void _cancel() {
    _dragging = false;
    _settle(_target, velocity: _interruptedVelocity);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragDown: _down,
        onHorizontalDragStart: _start,
        onHorizontalDragUpdate: _update,
        onHorizontalDragEnd: _end,
        onHorizontalDragCancel: _cancel,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: _width * 2,
            maxWidth: _width * 2,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, child) => Transform.translate(
                offset: Offset(-_motion.value * _width, 0),
                child: child,
              ),
              child: SizedBox(
                width: _width * 2,
                height: constraints.maxHeight,
                child: Stack(
                  children: [
                    for (var i = 0; i < 2; i++)
                      if (_visited.contains(i))
                        Positioned(
                          key: ValueKey('message-page-$i'),
                          left: i * _width,
                          width: _width,
                          top: 0,
                          bottom: 0,
                          child: Offstage(
                            offstage: !_moving && i != widget.value,
                            child: ExcludeFocus(
                              excluding: i != widget.value,
                              child: ExcludeSemantics(
                                excluding: i != widget.value,
                                child: TickerMode(
                                  enabled: _moving || i == widget.value,
                                  child: RepaintBoundary(
                                    child: widget.itemBuilder(context, i),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
