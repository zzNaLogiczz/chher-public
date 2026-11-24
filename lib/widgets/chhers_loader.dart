import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../design/loading_tokens.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import 'viewport_ticker_mode.dart';

enum ChhersLoaderSize {
  page(LoadingTokens.pageHeight, LoadingTokens.pageStroke),
  list(LoadingTokens.listHeight, LoadingTokens.listStroke),
  refresh(LoadingTokens.pullHeight, LoadingTokens.pullStroke);

  const ChhersLoaderSize(this.height, this.stroke);

  final double height;
  final double stroke;

  Size get viewSize {
    final scale = height / LoadingTokens.wordmarkHeight;
    return Size(
      LoadingTokens.viewWidth * scale,
      LoadingTokens.viewHeight * scale,
    );
  }
}

class ChhersLoader extends StatelessWidget {
  const ChhersLoader({
    super.key,
    this.size = ChhersLoaderSize.page,
    this.color,
    this.delayed = true,
    this.animate = true,
    this.active = true,
    this.onVisible,
  }) : progress = null;

  const ChhersLoader.progress({
    super.key,
    required double this.progress,
    this.color,
  }) : size = ChhersLoaderSize.refresh,
       delayed = false,
       animate = false,
       active = true,
       onVisible = null;

  final ChhersLoaderSize size;
  final Color? color;
  final bool delayed;
  final bool animate;
  final bool active;
  final double? progress;
  final VoidCallback? onVisible;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final pull = progress?.clamp(0.0, 1.0);
    final ink = color ?? (pull == 1 ? tokens.accent : tokens.text3);
    if (pull != null) {
      return SizedBox.fromSize(
        size: size.viewSize,
        child: Opacity(
          opacity: (LoadingTokens.pullBaseOpacity + pull).clamp(0.0, 1.0),
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _WordmarkPainter(
                size,
                ink,
                cycle: null,
                progress: MediaQuery.disableAnimationsOf(context) ? 1 : pull,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox.fromSize(
      size: size.viewSize,
      child: ViewportTickerMode(
        trackVisibility: active,
        child: _LoadingMotion(
          delayed: delayed,
          animate: animate,
          active: active,
          onVisible: onVisible,
          period: AppMotion.loadingCycle,
          builder: (loop, reduced) {
            final mark = RepaintBoundary(
              child: CustomPaint(
                painter: _WordmarkPainter(
                  size,
                  ink,
                  cycle: reduced ? null : loop,
                  progress: 1,
                ),
              ),
            );
            return reduced
                ? mark
                : FadeTransition(
                    opacity: loop.drive(_cycleOpacity),
                    child: mark,
                  );
          },
        ),
      ),
    );
  }
}

class ChhersSpinner extends StatelessWidget {
  const ChhersSpinner({
    super.key,
    this.size = LoadingTokens.control,
    this.color,
    this.delayed = true,
    this.active = true,
  });

  final double size;
  final Color? color;
  final bool delayed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? AppTokens.of(context).text3;
    return SizedBox.square(
      dimension: size,
      child: ViewportTickerMode(
        trackVisibility: active,
        child: _LoadingMotion(
          delayed: delayed,
          animate: true,
          active: active,
          period: AppMotion.loadingSpin,
          builder: (loop, reduced) {
            final glyph = RepaintBoundary(
              child: CustomPaint(painter: _SpinnerPainter(ink)),
            );
            return reduced
                ? glyph
                : RotationTransition(turns: loop, child: glyph);
          },
        ),
      ),
    );
  }
}

/// Keeps the delay and entrance separate from the looping animation.
class _LoadingMotion extends StatefulWidget {
  const _LoadingMotion({
    required this.delayed,
    required this.animate,
    required this.active,
    required this.period,
    required this.builder,
    this.onVisible,
  });

  final bool delayed;
  final bool animate;
  final bool active;
  final Duration period;
  final VoidCallback? onVisible;
  final Widget Function(Animation<double> loop, bool reduced) builder;

  @override
  State<_LoadingMotion> createState() => _LoadingMotionState();
}

class _LoadingMotionState extends State<_LoadingMotion>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _loop = AnimationController(vsync: this, duration: widget.period);
  late final _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.loadingIn,
    reverseDuration: AppMotion.loadingOut,
    animationBehavior: AnimationBehavior.preserve,
  );
  Timer? _delay;
  bool _ready = false;
  bool _visible = false;
  bool _inViewport = false;
  bool _reduced = false;
  late bool _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);

  bool _isForeground(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entrance.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _visible && !widget.active) {
        setState(() => _visible = false);
      }
    });
    if (widget.active) _wait();
  }

  void _wait() {
    _ready = !widget.delayed;
    if (!_ready) {
      _delay = Timer(AppMotion.loadingDelay, () {
        setState(() => _ready = true);
        _sync();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inViewport = TickerMode.valuesOf(context).enabled;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LoadingMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _delay?.cancel();
      if (widget.active) {
        if (_visible) {
          _ready = true;
          _entrance.stop();
        } else {
          _wait();
        }
      }
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _isForeground(state);
    setState(_sync);
  }

  void _sync() {
    if (!widget.active) {
      _loop.stop();
      if (_visible && _inViewport && _foreground && _entrance.value > 0) {
        if (_entrance.status != AnimationStatus.reverse) _entrance.reverse();
      } else {
        _visible = false;
        _entrance.value = 0;
      }
      return;
    }
    if (!_ready || !_inViewport || !_foreground) {
      _loop.stop();
      _entrance.stop();
      return;
    }
    if (!_visible) {
      _visible = true;
      widget.onVisible?.call();
    }
    if (!_entrance.isAnimating && !_entrance.isCompleted) _entrance.forward();
    if (!_reduced && widget.animate) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _delay?.cancel();
    _loop.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.expand();
    return Semantics(
      label: '正在加载',
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: _reduced
              ? _entrance.drive(
                  Tween(end: LoadingTokens.reducedOpacity, begin: 0),
                )
              : _entrance,
          child: widget.builder(_loop, _reduced),
        ),
      ),
    );
  }
}

final _cycleOpacity = TweenSequence<double>([
  TweenSequenceItem(
    tween: ConstantTween(1),
    weight: AppMotion.loadingFadeStart,
  ),
  TweenSequenceItem(
    tween: Tween(begin: 1, end: 0),
    weight: AppMotion.loadingFadeEnd - AppMotion.loadingFadeStart,
  ),
  TweenSequenceItem(
    tween: ConstantTween(0),
    weight: 1 - AppMotion.loadingFadeEnd,
  ),
]);

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter(
    this.variant,
    this.color, {
    required this.cycle,
    required this.progress,
  }) : super(repaint: cycle);

  final ChhersLoaderSize variant;
  final Color color;
  final Animation<double>? cycle;
  final double progress;
  static final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final nominal = variant.viewSize;
    final fit = math.min(
      size.width / nominal.width,
      size.height / nominal.height,
    );
    if (fit <= 0) return;
    final scale = fit * variant.height / LoadingTokens.wordmarkHeight;
    final phase = cycle?.value;
    _paint
      ..color = color
      ..strokeWidth = variant.stroke * fit / scale;

    canvas.save();
    canvas.translate(
      (size.width - nominal.width * fit) / 2,
      (size.height - nominal.height * fit) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-LoadingTokens.viewLeft, -LoadingTokens.viewTop);
    for (final stroke in _strokes) {
      final fraction = phase == null
          ? ((progress * _totalLength - stroke.offset) / stroke.metric.length)
                .clamp(0.0, 1.0)
          : AppMotion.loadingStrokeCurve.transform(
              ((phase - stroke.start) / (stroke.end - stroke.start)).clamp(
                0.0,
                1.0,
              ),
            );
      if (fraction == 0) break;
      canvas.drawPath(
        fraction == 1
            ? stroke.path
            : stroke.metric.extractPath(0, fraction * stroke.metric.length),
        _paint,
      );
      if (fraction < 1) break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) =>
      variant != oldDelegate.variant ||
      color != oldDelegate.color ||
      cycle != oldDelegate.cycle ||
      progress != oldDelegate.progress;
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color);

  final Color color;

  static final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final _arc = Path()
    ..addArc(
      Rect.fromCircle(center: Offset.zero, radius: LoadingTokens.spinnerRadius),
      -math.pi / 4,
      -3 * math.pi / 2,
    );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / LoadingTokens.spinnerViewSize;
    if (scale == 0) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.drawPath(
      _arc,
      _paint
        ..color = color
        ..strokeWidth = LoadingTokens.spinnerStroke / scale,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => color != oldDelegate.color;
}

class _Stroke {
  const _Stroke(this.path, this.metric, this.offset, this.start, this.end);

  final Path path;
  final PathMetric metric;
  final double offset;
  final double start;
  final double end;
}

/// Paints the complete wordmark fitted within [bounds].
void paintChhersWordmark(Canvas canvas, Rect bounds, Color color) {
  final scale = math.min(
    bounds.width / LoadingTokens.viewWidth,
    bounds.height / LoadingTokens.viewHeight,
  );
  if (scale <= 0) return;
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 4.6;
  canvas.save();
  canvas.translate(
    bounds.center.dx - LoadingTokens.viewWidth * scale / 2,
    bounds.center.dy - LoadingTokens.viewHeight * scale / 2,
  );
  canvas.scale(scale);
  canvas.translate(-LoadingTokens.viewLeft, -LoadingTokens.viewTop);
  for (final path in _paths) {
    canvas.drawPath(path, paint);
  }
  canvas.restore();
}

// R2b-wordmark.svg geometry, in the original loading animation stroke order.
final _paths = <Path>[
  Path()
    ..moveTo(23.05, -3.05)
    ..arcToPoint(
      const Offset(23.05, 16.05),
      radius: const Radius.circular(13.5),
      largeArc: true,
      clockwise: false,
    ),
  Path()
    ..moveTo(32.25, -7)
    ..lineTo(32.25, 20),
  Path()
    ..moveTo(32.25, 7.2)
    ..arcToPoint(const Offset(46.65, 7.2), radius: const Radius.circular(7.2))
    ..lineTo(46.65, 20),
  Path()
    ..moveTo(57.65, -7)
    ..lineTo(57.65, 20),
  Path()
    ..moveTo(57.65, 7.2)
    ..arcToPoint(const Offset(72.05, 7.2), radius: const Radius.circular(7.2))
    ..lineTo(72.05, 20),
  Path()
    ..moveTo(81.85, 10)
    ..lineTo(101.85, 10),
  Path()
    ..moveTo(101.85, 10)
    ..arcToPoint(
      const Offset(99.51, 16.43),
      radius: const Radius.circular(10),
      largeArc: true,
      clockwise: false,
    ),
  Path()
    ..moveTo(110.05, 0)
    ..lineTo(110.05, 20),
  Path()
    ..moveTo(110.05, 8.28)
    ..arcToPoint(const Offset(118.33, 0), radius: const Radius.circular(8.28))
    ..lineTo(120.43, 0),
  Path()
    ..moveTo(139.93, 2.2)
    ..cubicTo(138.93, .7, 137.03, 0, 134.83, 0)
    ..cubicTo(131.23, 0, 128.63, 2.1, 128.63, 5)
    ..cubicTo(128.63, 8.4, 132.03, 9.2, 135.03, 9.9)
    ..cubicTo(138.23, 10.6, 141.43, 11.5, 141.43, 14.9)
    ..cubicTo(141.43, 18, 138.63, 20, 134.83, 20)
    ..cubicTo(132.23, 20, 129.83, 19, 128.43, 17.2),
];
final _metrics = [for (final path in _paths) path.computeMetrics().single];
final _totalLength = _metrics.fold(0.0, (sum, metric) => sum + metric.length);
final _strokes = _scheduleStrokes();

List<_Stroke> _scheduleStrokes() {
  final writingTime =
      AppMotion.loadingWriteEnd - AppMotion.loadingStrokeGap * _paths.length;
  var offset = 0.0;
  var start = 0.0;
  return List.generate(_paths.length, (index) {
    final metric = _metrics[index];
    final end = start + writingTime * metric.length / _totalLength;
    final stroke = _Stroke(_paths[index], metric, offset, start, end);
    offset += metric.length;
    start = end + AppMotion.loadingStrokeGap;
    return stroke;
  }, growable: false);
}
