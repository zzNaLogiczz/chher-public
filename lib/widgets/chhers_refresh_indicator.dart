import 'dart:async';
import 'dart:math' as math;

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
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final double edgeOffset;

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
  final _leadingOverscroll = ValueNotifier(0.0);
  late final _geometry = Listenable.merge([_extent, _leadingOverscroll]);
  Future<void>? _refresh;
  AxisDirection? _dragDirection;
  bool _atTop = true;
  bool _armed = false;
  bool _dismissing = false;
  bool _tickerEnabled = true;
  double _pixels = 0;
  double _progress = 0;

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
      _extent.value = _refresh == null ? 0 : RefreshTokens.holdExtent;
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 ||
        metrics.axis != Axis.vertical ||
        metrics.viewportDimension <= 0) {
      return false;
    }

    // Bouncing scroll views already displace their child by the leading
    // overscroll. Compensate for that displacement so the gap only opens once.
    final overscroll = metrics.axisDirection == AxisDirection.down
        ? metrics.minScrollExtent - metrics.pixels
        : metrics.pixels - metrics.maxScrollExtent;
    _leadingOverscroll.value = math.max(0.0, overscroll);

    if (!_active || _refresh != null || _dismissing) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        (metrics.axisDirection == AxisDirection.down
                ? metrics.extentBefore
                : metrics.extentAfter) ==
            0) {
      _dragDirection = metrics.axisDirection;
      _atTop = true;
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

    if (notification is ScrollUpdateNotification &&
        _armed &&
        notification.dragDetails == null) {
      // Bouncing physics reports the first ballistic update before ScrollEnd.
      unawaited(show());
    } else if (notification is ScrollEndNotification) {
      if (_armed) {
        unawaited(show());
      } else {
        unawaited(_dismiss());
      }
    } else {
      final delta = switch (notification) {
        ScrollUpdateNotification() => notification.scrollDelta,
        OverscrollNotification() => notification.overscroll,
        _ => null,
      };
      if (delta != null) {
        _pixels += direction == AxisDirection.down ? -delta : delta;
        final threshold =
            metrics.viewportDimension * RefreshTokens.thresholdFraction;
        final pull = _pixels / threshold;
        _armed = _armed || pull >= 1;
        setState(() {
          _progress = _armed ? 1 : pull.clamp(0.0, 1.0);
          _extent.value =
              (RefreshTokens.armedExtent *
                      (_armed ? math.max(1.0, pull) : pull))
                  .clamp(0.0, RefreshTokens.maxExtent);
        });
      }
    }
    return false;
  }

  bool _handleGlow(OverscrollIndicatorNotification notification) {
    if (notification.depth == 0 &&
        notification.leading &&
        _dragDirection != null) {
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
    final refresh = Future<void>.microtask(widget.onRefresh).whenComplete(() {
      if (mounted) unawaited(_dismiss());
    });
    setState(() {
      _refresh = refresh;
    });
    unawaited(_moveTo(RefreshTokens.holdExtent));
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
    _leadingOverscroll.dispose();
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
            final translation = math.max(
              0.0,
              extent - _leadingOverscroll.value,
            );
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
                      bottom: _atTop ? null : widget.edgeOffset,
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
