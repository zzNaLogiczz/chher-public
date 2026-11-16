import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/appearance.dart';
import 'motion.dart';

/// Keeps the old painted frame above a theme that changes in a single build.
class ThemeReveal extends StatefulWidget {
  final AppearanceController appearance;
  final Widget child;

  const ThemeReveal({super.key, required this.appearance, required this.child});

  static void change(
    BuildContext context,
    VoidCallback change, {
    Offset? origin,
  }) {
    context.findAncestorStateOfType<ThemeRevealState>()?._capture(origin);
    change();
  }

  @override
  State<ThemeReveal> createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _boundary = GlobalKey();
  late final AnimationController _progress;
  ui.Image? _image;
  Offset? _origin;
  (Size, double)? _snapshotMetrics;

  @visibleForTesting
  ui.Image? get debugSnapshot => _image;

  @visibleForTesting
  Offset? get debugSnapshotOrigin => _origin;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: AppMotion.fade)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _clear();
      });
    WidgetsBinding.instance.addObserver(this);
  }

  void _capture(Offset? globalOrigin) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _clear();
      return;
    }
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      _clear();
      return;
    }
    final view = View.of(context);
    ui.Image image;
    try {
      image = boundary.toImageSync(pixelRatio: view.devicePixelRatio);
    } catch (_) {
      // A not-yet-painted frame must never prevent changing the preference.
      _clear();
      return;
    }
    _progress.stop();
    final previous = _image;
    setState(() {
      _image = image;
      _snapshotMetrics = (view.physicalSize, view.devicePixelRatio);
      _origin = globalOrigin == null
          ? null
          : boundary.globalToLocal(globalOrigin);
    });
    previous?.dispose();
    _progress.value = 0;
    if (_origin == null) {
      _progress.forward();
    } else {
      AppMotion.settle(
        _progress,
        target: 1,
        motion: AppMotion.reveal,
        velocity: 0,
      );
    }
  }

  void _clear() {
    _progress.stop();
    final image = _image;
    if (image == null) return;
    setState(() {
      _image = null;
      _snapshotMetrics = null;
    });
    image.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (widget.appearance.mode == AppearanceMode.system) _capture(null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _clear();
  }

  @override
  void didChangeMetrics() {
    final view = View.of(context);
    // System bar updates can resend unchanged metrics during a theme switch.
    if (_snapshotMetrics != (view.physicalSize, view.devicePixelRatio)) {
      _clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ThemeBoundary(
    key: _boundary,
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: widget.child),
        if (_image case final image?)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ThemeSnapshot(image, _origin, _progress),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _ThemeBoundary extends RepaintBoundary {
  const _ThemeBoundary({super.key, required super.child});

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _ThemeRenderBoundary();
}

class _ThemeRenderBoundary extends RenderRepaintBoundary {
  // Capture the displayed layer even if a press has queued another paint.
  @override
  ui.Image toImageSync({double pixelRatio = 1}) => (layer! as OffsetLayer)
      .toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
}

class _ThemeSnapshot extends CustomPainter {
  final ui.Image image;
  final Offset? origin;
  final Animation<double> progress;

  _ThemeSnapshot(this.image, this.origin, this.progress)
    : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final value = progress.value.clamp(0.0, 1.0);
    final paint = Paint();
    canvas.save();
    if (origin case final center?) {
      final radius = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ].map((corner) => (corner - center).distance).reduce(math.max);
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect)
          ..addOval(Rect.fromCircle(center: center, radius: radius * value)),
        doAntiAlias: true,
      );
    } else {
      paint.color = paint.color.withValues(alpha: 1 - value);
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThemeSnapshot oldDelegate) =>
      oldDelegate.image != image || oldDelegate.origin != origin;
}
