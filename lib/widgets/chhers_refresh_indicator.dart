import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/refresh_tokens.dart';
import 'chhers_loader.dart';

/// Keeps the scrollable's physics and position while revealing the wordmark.
class ChhersRefreshIndicator extends StatefulWidget {
  const ChhersRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
    this.onRefreshAtEnd,
    this.endEdgeOffset = 0,
  });

  final Future<void> Function() onRefresh;
  final Future<void> Function()? onRefreshAtEnd;
  final Widget child;
  final double edgeOffset;
  final double endEdgeOffset;

  @override
  State<ChhersRefreshIndicator> createState() => ChhersRefreshIndicatorState();
}

class ChhersRefreshIndicatorState extends State<ChhersRefreshIndicator>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _extent = AnimationController.unbounded(vsync: this);
  late final _opacity = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  final _overscroll = ValueNotifier(0.0);
  late final _geometry = Listenable.merge([_extent, _overscroll]);
  Future<void>? _refresh;
  AxisDirection? _dragDirection;
  bool _dragAtTop = false;
  bool _dragAtEnd = false;
  bool _atTop = true;
  bool _armed = false;
  bool _dismissing = false;
  bool _tickerEnabled = true;
  double _pixels = 0;
  double _progress = 0;

  static const _endThreshold = 48.0;
  static const _endMaxExtent = 56.0;
  double get _holdExtent => _atTop ? RefreshTokens.holdExtent : 44;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  bool get _active =>
      _tickerEnabled &&
      switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed => true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _settleHidden();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _settleHidden();

  void _settleHidden() {
    if (_active) return;
    _dragDirection = null;
    if (_dismissing) {
      _finishDismiss();
    } else {
      _extent.value = _refresh == null ? 0 : _holdExtent;
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 ||
        metrics.axis != Axis.vertical ||
        metrics.viewportDimension <= 0) {
      return false;
    }

    // Bouncing physics already exposes space at either edge.
    final normal = metrics.axisDirection == AxisDirection.down;
    final before = math.max(0.0, metrics.minScrollExtent - metrics.pixels);
    final after = math.max(0.0, metrics.pixels - metrics.maxScrollExtent);
    if (_dragDirection != null || _extent.value > 0) {
      final offset = normal ? before - after : after - before;
      if (offset != _overscroll.value) {
        final binding = WidgetsBinding.instance;
        if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          binding.addPostFrameCallback((_) {
            if (mounted) _overscroll.value = offset;
          });
        } else {
          _overscroll.value = offset;
        }
      }
    }

    if (!_active || _refresh != null || _dismissing) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragAtTop = (normal ? metrics.extentBefore : metrics.extentAfter) == 0;
      _dragAtEnd =
          widget.onRefreshAtEnd != null &&
          (normal ? metrics.extentAfter : metrics.extentBefore) <= 1;
      _dragDirection = _dragAtTop || _dragAtEnd ? metrics.axisDirection : null;
      _armed = false;
      _pixels = 0;
      return false;
    }
    final direction = _dragDirection;
    if (direction == null) return false;
    if (direction != metrics.axisDirection) {
      unawaited(_dismiss());
      return false;
    }

    if (notification is ScrollEndNotification) {
      if (_armed) {
        unawaited(show(atTop: _atTop));
      } else {
        unawaited(_dismiss());
      }
    } else {
      if (notification is ScrollUpdateNotification &&
          notification.dragDetails == null) {
        // At the end the reader restores its anchor after the bounce settles.
        if (_atTop && _armed) unawaited(show());
        return false;
      }
      final delta = switch (notification) {
        ScrollUpdateNotification() => notification.scrollDelta,
        OverscrollNotification(:final overscroll, dragDetails: _?) =>
          overscroll,
        _ => null,
      };
      if (delta != null && delta != 0) {
        final towardTop = normal ? -delta : delta;
        if (_pixels == 0 && !_armed) {
          _atTop = _dragAtTop && (!_dragAtEnd || towardTop > 0);
        }
        var distance = _atTop ? towardTop : -towardTop;
        if (!_atTop && notification is ScrollUpdateNotification) {
          if ((normal ? metrics.extentAfter : metrics.extentBefore) > 1) {
            _armed = false;
            _pixels = 0;
          }
          if (distance > 0) {
            distance = math.min(distance, normal ? after : before);
          }
        }
        _pixels = math.max(0.0, _pixels + distance);
        final threshold = _atTop
            ? metrics.viewportDimension * RefreshTokens.thresholdFraction
            : _endThreshold;
        final pull = _pixels / threshold;
        _armed = _armed || pull >= 1;
        setState(() {
          _progress = _armed ? 1 : pull.clamp(0.0, 1.0);
          final armedExtent = _atTop ? RefreshTokens.armedExtent : _holdExtent;
          final maxExtent = _atTop ? RefreshTokens.maxExtent : _endMaxExtent;
          _extent.value = (armedExtent * (_armed ? math.max(1.0, pull) : pull))
              .clamp(0.0, maxExtent);
        });
      }
    }
    return false;
  }

  bool _handleGlow(OverscrollIndicatorNotification notification) {
    final direction = _dragDirection;
    if (notification.depth == 0 &&
        direction != null &&
        (notification.leading == (direction == AxisDirection.down)
            ? _dragAtTop
            : _dragAtEnd)) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  TickerFuture _moveTo(double extent) => _extent.animateTo(
    extent,
    duration: _reduced || !_active
        ? Duration.zero
        : AppMotion.scrollChrome.duration,
    curve: AppMotion.refreshSettleCurve,
  );

  /// Runs the same refresh as an armed drag, independently of scroll position.
  Future<void> show({bool atTop = true}) {
    if (_refresh case final pending?) return pending;
    if (_dismissing) return Future<void>.value();
    _dragDirection = null;
    _atTop = atTop;
    final callback = atTop
        ? widget.onRefresh
        : widget.onRefreshAtEnd ?? widget.onRefresh;
    final refresh = Future<void>.microtask(callback).whenComplete(() {
      if (mounted) unawaited(_dismiss());
    });
    setState(() {
      _refresh = refresh;
    });
    unawaited(_moveTo(_holdExtent));
    return refresh;
  }

  Future<void> _dismiss() async {
    _dragDirection = null;
    if (_extent.value <= 0 && _refresh == null) {
      _armed = false;
      return;
    }
    if (!_active) {
      _finishDismiss();
      return;
    }
    setState(() => _dismissing = true);
    try {
      if (_refresh != null) {
        await _opacity.animateTo(0, duration: AppMotion.loadingOut).orCancel;
      }
      if (mounted) await _moveTo(0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted) _finishDismiss();
  }

  void _finishDismiss() {
    setState(() {
      _extent.value = 0;
      _refresh = null;
      _dismissing = false;
      _armed = false;
      _progress = 0;
      _opacity.value = 1;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _extent.dispose();
    _opacity.dispose();
    _overscroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wordmark = _refresh == null
        ? ChhersLoader.progress(progress: _progress)
        : ChhersLoader(
            size: ChhersLoaderSize.refresh,
            delayed: false,
            animate: !_dismissing,
          );
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleGlow,
        child: AnimatedBuilder(
          animation: _geometry,
          child: widget.child,
          builder: (context, child) {
            final extent = _extent.value;
            final offset =
                extent -
                math.max(0.0, _atTop ? _overscroll.value : -_overscroll.value);
            final translation = _atTop || extent == 0
                ? math.max(0.0, offset)
                : offset;
            return ClipRect(
              clipBehavior: extent > 0 ? Clip.hardEdge : Clip.none,
              child: Stack(
                children: [
                  Transform.translate(
                    offset: Offset(0, _atTop ? translation : -translation),
                    child: child,
                  ),
                  if (extent > 0)
                    Positioned(
                      top: _atTop ? widget.edgeOffset : null,
                      bottom: _atTop ? null : widget.endEdgeOffset,
                      left: 0,
                      right: 0,
                      height: extent,
                      child: IgnorePointer(
                        child: ClipRect(
                          child: FadeTransition(
                            opacity: _opacity,
                            child: OverflowBox(
                              minWidth: 0,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: wordmark,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
