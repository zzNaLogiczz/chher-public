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
  final ValueChanged<int>? onPreview;
  final VoidCallback? onSettled;
  final Widget Function(BuildContext context, int index) itemBuilder;

  const MessagePager({
    super.key,
    required this.value,
    required this.position,
    required this.onChanged,
    required this.itemBuilder,
    this.onVisit,
    this.onPreview,
    this.onSettled,
  }) : assert(value == 0 || value == 1);

  @override
  State<MessagePager> createState() => _MessagePagerState();
}

class _MessagePagerState extends State<MessagePager>
    with TickerProviderStateMixin {
  late final _motion = AnimationController.unbounded(
    vsync: this,
    value: widget.value.toDouble(),
  )..addListener(_publish);
  late final _fade = AnimationController(
    vsync: this,
    value: widget.value.toDouble(),
  );
  late final _visited = <int>{widget.value};
  late int _target;
  bool _moving = false;
  bool _fading = false;
  bool _dragging = false;
  double _raw = 0;
  double _width = 1;
  int _generation = 0;
  double _interruptedVelocity = 0;
  bool _heldSelection = false;
  bool _publishPending = false;
  int? _previewed;

  @override
  void initState() {
    super.initState();
    _target = widget.value;
    // Force initialization before a reduced-motion dependency update.
    _motion;
    _fade;
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
      _settle(_target, fade: !_moving || _fading);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !_dragging) {
      _motion.value = _target.toDouble();
      _moving = _fading;
    }
  }

  void _visit(int index) {
    if (_visited.add(index)) widget.onVisit?.call(index);
  }

  void _settle(int target, {double? velocity, bool fade = false}) {
    final generation = ++_generation;
    final reduced = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _fading = fade;
      _moving = fade || !reduced;
    });
    final selection = AppMotion.settle(
      _motion,
      target: target.toDouble(),
      motion: AppMotion.select,
      velocity: velocity,
      reduced: reduced,
    );
    final transition = fade
        ? _fade.animateTo(
            target.toDouble(),
            duration: reduced ? AppMotion.reducedFade : AppMotion.fade,
            curve: AppMotion.contentFadeCurve,
          )
        : selection;
    transition.whenCompleteOrCancel(() {
      if (!mounted || generation != _generation) return;
      if (!fade) _fade.value = target.toDouble();
      setState(() => _moving = _fading = false);
      _previewed = null;
      widget.onSettled?.call();
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
    _heldSelection = _fading || !_moving;
    if (!_heldSelection) _generation++;
    _interruptedVelocity = _motion.velocity;
    _motion.stop();
  }

  void _start(DragStartDetails details) {
    _dragging = true;
    if (_fading) {
      _generation++;
      _motion.stop();
      _motion.value = _fade.value;
      _fade.stop();
      _fading = false;
    } else if (_heldSelection) {
      _motion.value = _target.toDouble();
    }
    _heldSelection = false;
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
    if (entering != widget.value && entering != _previewed) {
      _previewed = entering;
      widget.onPreview?.call(entering);
    }
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
    _fade.value = _target.toDouble();
    _settle(_target, velocity: -velocity / _width);
  }

  void _cancel() {
    if (_heldSelection) {
      _heldSelection = false;
      AppMotion.settle(
        _motion,
        target: _target.toDouble(),
        motion: AppMotion.select,
        velocity: _interruptedVelocity,
        reduced: MediaQuery.disableAnimationsOf(context),
      );
      return;
    }
    _dragging = false;
    _fade.value = _target.toDouble();
    _settle(_target, velocity: _interruptedVelocity);
  }

  @override
  void dispose() {
    _generation++;
    _fade.dispose();
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < 2; i++)
                if (_visited.contains(i))
                  AnimatedBuilder(
                    key: ValueKey('message-page-$i'),
                    animation: _fading ? _fade : _motion,
                    builder: (_, child) => Transform.translate(
                      offset: _fading || !_moving
                          ? Offset.zero
                          : Offset((i - _motion.value) * _width, 0),
                      child: Opacity(
                        opacity: !_fading
                            ? 1
                            : (i == 0 ? 1 - _fade.value : _fade.value),
                        child: child,
                      ),
                    ),
                    child: Offstage(
                      offstage: !_moving && i != widget.value,
                      child: IgnorePointer(
                        ignoring: i != widget.value,
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
                  ),
            ],
          ),
        ),
      );
    },
  );
}
