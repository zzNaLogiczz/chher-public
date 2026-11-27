import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../design/composer_tokens.dart';
import '../../design/tokens.dart';
import '../../design/voice_tokens.dart';
import 'voice_goo_motion.dart';
import 'voice_liquid_motion.dart';

typedef _T = VoiceTokens;
typedef _Drop = VoiceDropPaintTokens;

double _gw(double u) => voiceSechSquared(u / _T.rippleWidth);

void _smoothTo(Path path, List<Offset> points) {
  for (var i = 1; i < points.length - 1; i++) {
    final p = points[i];
    final end = (p + points[i + 1]) / 2;
    path.quadraticBezierTo(p.dx, p.dy, end.dx, end.dy);
  }
  final end = points.last;
  path.lineTo(end.dx, end.dy);
}

Path _smoothPath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  _smoothTo(path, points);
  return path;
}

void _cubicTo(Path path, VoiceCubic cubic, double mid) => path.cubicTo(
  mid + cubic.control1.x,
  cubic.control1.y,
  mid + cubic.control2.x,
  cubic.control2.y,
  mid + cubic.end.x,
  cubic.end.y,
);

/// geom / layout / disp / surf in the prototype. Coordinates are local to
/// the full-width 44 dp hit area, with its center held fixed vertically.
class VoiceLiquidGeometry {
  VoiceLiquidGeometry({
    required this.frame,
    required this.ripples,
    required this.fullWidth,
    required double capsuleWidth,
    this.goo,
  }) {
    final spread = frame.reduced ? 1.0 : frame.spread.clamp(0.0, _T.maxSpread);
    final progress = math.min(spread, 1.0);
    final lv = frame.reduced ? 0.0 : frame.volume;
    final w = math.min(
      ui.lerpDouble(capsuleWidth, fullWidth, spread)!,
      fullWidth + _T.maxOverhang,
    );
    final h = VoiceLiquidMotion.heightFor(frame);
    final mid = fullWidth / 2;
    // The capsule travels from the touch to the center while it widens.
    final available = math.max(0.0, (fullWidth - capsuleWidth) / 2);
    final origin = frame.origin.clamp(-available, available);
    final center = mid + origin * (1 - progress);
    body = Rect.fromCenter(
      center: Offset(center, _T.barHeight / 2),
      width: w,
      height: h,
    );
    radius = math.min(w, h) / 2;
    amplitude = frame.reduced
        ? 0
        : (_T.baseAmplitude + _T.volumeAmplitude * lv) * progress;
  }

  final VoiceLiquidFrame frame;
  final List<VoiceRipple> ripples;
  final double fullWidth;
  final VoiceGooMotion? goo;
  late final Rect body;
  late final double radius;
  late final double amplitude;

  double get leftTangent => body.left + radius;
  double get rightTangent => body.right - radius;
  double get mid => fullWidth / 2;
  Offset position(VoicePoint point) => Offset(mid + point.x, point.y);

  late final neck = _usableNeck();

  VoiceNeck? _usableNeck() {
    final neck = goo?.neck;
    if (neck == null ||
        mid + neck.right.x > rightTangent - _Drop.footInset ||
        mid + neck.left.x < leftTangent + _Drop.footInset) {
      return null;
    }
    return neck;
  }

  double rippleCenter(VoiceRipple ripple) {
    final inset = math.min(fullWidth / 2, _T.rippleInset);
    return (fullWidth / 2 + ripple.x).clamp(inset, fullWidth - inset);
  }

  double displacement(double x) {
    if (frame.reduced) return 0;
    final edge =
        voiceSmoothStep(leftTangent, leftTangent + _T.edgeFade, x) *
        voiceSmoothStep(rightTangent, rightTangent - _T.edgeFade, x);
    if (edge <= 0) return 0;
    final t = frame.time;
    // Prototype coordinates start at the strip's left, 8dp before this bar.
    final px = x + ComposerTokens.stripInset;
    var slowWave = 0.0;
    for (final wave in _T.surfaceWaves) {
      slowWave +=
          wave.weight *
          math.sin(wave.frequency * px + wave.speed * t + wave.phase);
    }
    var value = amplitude * slowWave;
    for (final ripple in ripples) {
      final age = t - ripple.time;
      if (age < 0) continue;
      final travel = ripple.speed * age;
      final local = x - rippleCenter(ripple);
      value +=
          ripple.amplitude *
          math.exp(-age * _T.rippleDecay) *
          (_gw(local - travel) + _gw(local + travel));
    }
    return (goo?.shapeSurface(x - mid, value) ?? value) * edge;
  }

  List<Offset> surface(double from, double to, {double depth = 0}) {
    final count = math.max(1, ((to - from).abs() / _T.surfaceStep).round());
    return [
      for (var i = 0; i <= count; i++)
        _surfacePoint(ui.lerpDouble(from, to, i / count)!, depth),
    ];
  }

  Offset _surfacePoint(double x, double depth) =>
      Offset(x, body.top - displacement(x) + depth);

  Path outline({bool includeNeck = true}) {
    if (body.width <= body.height) {
      return Path()
        ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)));
    }
    final x0 = leftTangent, x1 = rightTangent;
    final left = Rect.fromCircle(
      center: Offset(x0, body.center.dy),
      radius: radius,
    );
    final right = left.shift(Offset(x1 - x0, 0));
    final path = Path()
      ..moveTo(x0, body.bottom)
      ..lineTo(x1, body.bottom)
      ..arcTo(right, math.pi / 2, -math.pi, false);
    final join = includeNeck ? neck : null;
    if (join == null) {
      _smoothTo(path, surface(x1, x0));
    } else {
      _smoothTo(path, surface(x1, mid + join.right.x));
      _cubicTo(path, join.toWaistRight, mid);
      _cubicTo(path, join.toHeadRight, mid);
      path.arcTo(
        Rect.fromCenter(
          center: position(join.head),
          width: join.radius * 2,
          height: join.radius * join.squash * 2,
        ),
        join.arcStart,
        join.arcSweep,
        false,
      );
      _cubicTo(path, join.toWaistLeft, mid);
      _cubicTo(path, join.toFootLeft, mid);
      _smoothTo(path, surface(mid + join.left.x, x0));
    }
    return path
      ..arcTo(left, -math.pi / 2, -math.pi, false)
      ..close();
  }
}

/// Shaders are fixed for a theme and width. The painter moves their coordinate
/// spaces under the current path using canvas transforms.
class VoiceLiquidPaints {
  VoiceLiquidPaints(
    AppTokens tokens,
    double width, {
    TextStyle baseTextStyle = const TextStyle(),
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
    double pixelRatio = 1,
  }) : _label = _DropLabel(
         tokens,
         width,
         baseTextStyle,
         textScaler,
         textDirection,
         pixelRatio,
       ),
       red = _Drop.red(tokens),
       redMask = ui.Gradient.radial(Offset.zero, 1, [
         _Drop.red(tokens),
         _Drop.red(tokens),
         _Drop.red(tokens).withValues(alpha: 0),
       ], _Drop.redStops),
       gloss = ui.Gradient.radial(_Drop.glossCenter, _Drop.glossRadius, [
         for (final alpha in _Drop.glossAlpha)
           _T.light.withValues(alpha: alpha),
       ], _Drop.glossStops),
       fill = ui.Gradient.linear(
         Offset.zero,
         Offset(_T.liquidPeriod * width, 0),
         [tokens.ai1, tokens.ai3, tokens.ai2, tokens.ai1],
         _T.liquidStops,
         TileMode.repeated,
       ),
       shade = ui.Gradient.linear(
         const Offset(0, -_T.shadeFade),
         const Offset(0, 1),
         [
           _T.light.withValues(alpha: 0),
           _T.light.withValues(alpha: _T.shadeTop),
           _T.light.withValues(alpha: 0),
           _T.dark.withValues(alpha: _T.shadeBottom),
         ],
         _T.shadeStops,
       ),
       sheen = ui.Gradient.linear(Offset.zero, const Offset(1, 0), [
         _T.light.withValues(alpha: 0),
         _T.light,
         _T.light,
         _T.light.withValues(alpha: 0),
       ], _T.sheenStops),
       accent = ui.Gradient.radial(Offset.zero, _T.rippleWidth, [
         tokens.ai3,
         tokens.ai3.withValues(alpha: 0),
       ]);

  final ui.Shader fill, shade, sheen, accent, redMask, gloss;
  final Color red;
  final _DropLabel _label;

  void dispose() {
    fill.dispose();
    shade.dispose();
    sheen.dispose();
    accent.dispose();
    redMask.dispose();
    gloss.dispose();
    _label.dispose();
  }
}

class _DropLabel {
  _DropLabel(
    this.tokens,
    this.width,
    this.baseTextStyle,
    this.textScaler,
    this.textDirection,
    this.pixelRatio,
  );

  final AppTokens tokens;
  final double width, pixelRatio;
  final TextStyle baseTextStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;
  ui.Image? _image;
  Rect _bounds = Rect.zero;

  void _rasterize() {
    final padding = _Drop.labelPadding * 2;
    final text = TextPainter(
      text: TextSpan(
        text: _Drop.label,
        style: baseTextStyle
            .merge(_Drop.labelFont)
            .copyWith(color: _Drop.red(tokens)),
      ),
      textScaler: textScaler,
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(1, width - padding));
    final height = math.max(_Drop.labelHeight, text.height);
    _bounds = Rect.fromLTWH(0, 0, text.width + padding, height);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    canvas.drawRRect(
      RRect.fromRectAndRadius(_bounds, Radius.circular(height / 2)),
      Paint()..color = _Drop.labelFill(tokens),
    );
    text.paint(canvas, Offset(_Drop.labelPadding, (height - text.height) / 2));
    text.dispose();
    final picture = recorder.endRecording();
    _image = picture.toImageSync(
      (_bounds.width * pixelRatio).ceil(),
      (_bounds.height * pixelRatio).ceil(),
    );
    picture.dispose();
  }

  void paint(
    Canvas canvas,
    Offset position,
    double age,
    double opacity,
    bool reduced,
  ) {
    if (opacity <= 0) return;
    if (_image == null) _rasterize();
    final image = _image!;
    final left =
        (_bounds.width / 2 + _Drop.labelInset - ComposerTokens.stripInset)
            .clamp(0.0, width / 2);
    final x = position.dx.clamp(left, width - left);
    final progress = reduced
        ? 1.0
        : _Drop.labelCurve.transform(
            (age *
                    Duration.microsecondsPerSecond /
                    _Drop.labelPop.inMicroseconds)
                .clamp(0.0, 1.0),
          );
    final scale = ui.lerpDouble(_Drop.labelMinScale, 1, progress)!;
    final y = position.dy + _Drop.labelLift * (1 - progress);
    final destination = Rect.fromLTWH(
      x - _bounds.width * scale / 2,
      y + _bounds.height * (1 - scale),
      _bounds.width * scale,
      _bounds.height * scale,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        0,
        0,
        _bounds.width * pixelRatio,
        _bounds.height * pixelRatio,
      ),
      destination,
      Paint()
        ..color = _T.light.withValues(alpha: opacity)
        ..filterQuality = FilterQuality.low,
    );
  }

  void dispose() => _image?.dispose();
}

class VoiceLiquidPainter extends CustomPainter {
  VoiceLiquidPainter({
    required this.motion,
    required this.paints,
    required this.fullWidth,
    required this.capsuleWidth,
    required this.lineLeft,
    required this.lineRight,
    required this.listeningElapsed,
    this.headroom = _T.paintHeadroom,
    this.sideRoom = _T.maxOverhang / 2,
  }) : super(repaint: motion);

  final VoiceLiquidMotion motion;
  final VoiceLiquidPaints paints;
  final double fullWidth, capsuleWidth, lineLeft, lineRight;
  final double headroom, sideRoom;
  final ValueGetter<Duration> listeningElapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = motion.frame;
    if (fullWidth <= 0) return;
    final goo = motion.goo;
    final g = VoiceLiquidGeometry(
      frame: frame,
      ripples: motion.ripples,
      fullWidth: fullWidth,
      capsuleWidth: capsuleWidth,
      goo: goo,
    );
    final bodyPath = g.outline();
    final blob = goo.blob;
    final blobPath = blob == null ? null : _blobPath(blob, g);
    final dropOpacity = motion.dropOpacity;
    final opacity = frame.opacity;
    canvas.save();
    canvas.translate(sideRoom, headroom);

    final period = _T.liquidPeriod * fullWidth;
    final fillX = g.body.left - frame.flow % period;
    _paintFill(canvas, bodyPath, fillX, opacity);
    if (blobPath != null) _paintFill(canvas, blobPath, fillX, dropOpacity);
    if (goo.red case final red?) {
      final center = g.position(red.center);
      _paintRed(canvas, bodyPath, center, red.radius, opacity);
      if (blobPath != null) {
        _paintRed(canvas, blobPath, center, red.radius, dropOpacity);
      }
    }

    if (opacity > 0) {
      canvas.save();
      canvas.clipPath(bodyPath);
      _paintShade(canvas, g);
      _paintCapacity(canvas, g, bodyPath);
      _paintRippleAccent(canvas, g);
      _paintSheen(canvas, g);
      _paintLines(canvas, g);
      canvas.restore();
    }
    if (blobPath != null) {
      _paintGloss(canvas, blobPath, dropOpacity);
    } else if (g.neck case final neck?) {
      if (neck.squash > _Drop.glossMinSquash &&
          neck.radius > _Drop.glossMinRadius) {
        canvas.save();
        canvas.clipPath(bodyPath);
        _paintGloss(
          canvas,
          Path()..addOval(
            Rect.fromCenter(
              center: g.position(neck.head),
              width: 2 * neck.radius,
              height: 2 * neck.radius * neck.squash,
            ),
          ),
          opacity,
        );
        canvas.restore();
      }
    }

    for (final part in goo.parts) {
      final center = g.position(part.center);
      final oval = Rect.fromCenter(
        center: Offset.zero,
        width: 2 * part.radiusX,
        height: 2 * part.radiusY,
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(part.rotation);
      if (part.red) {
        canvas.drawOval(
          oval,
          Paint()..color = paints.red.withValues(alpha: part.opacity),
        );
      } else {
        _paintFill(
          canvas,
          Path()..addOval(oval),
          fillX - center.dx,
          part.opacity,
        );
      }
      canvas.restore();
    }
    if (goo.ring case final ring?) {
      canvas.drawCircle(
        g.position(ring.center),
        ring.radius,
        Paint()
          ..color = paints.red.withValues(alpha: ring.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.stroke,
      );
    }
    final cutAge = goo.cutAge;
    final cutAlpha = frame.reduced
        ? dropOpacity
        : dropOpacity * (cutAge / VoiceGooTokens.labelFade).clamp(0.0, 1.0);
    if (blob != null && cutAlpha > 0) {
      _paintCross(canvas, g.position(blob.centroid), blob.scale, cutAlpha);
    }
    if (goo.label case final label?) {
      paints._label.paint(
        canvas,
        g.position(label),
        cutAge,
        dropOpacity * (frame.reduced ? 1 : goo.labelOpacity),
        frame.reduced,
      );
    }
    canvas.restore();
  }

  Path _blobPath(VoiceBlob blob, VoiceLiquidGeometry g) {
    final outline = blob.outline();
    final start = g.position(outline.start);
    final path = Path()..moveTo(start.dx, start.dy);
    for (final cubic in outline.segments) {
      _cubicTo(path, cubic, g.mid);
    }
    return path..close();
  }

  void _paintFill(Canvas canvas, Path path, double x, double opacity) {
    if (opacity <= 0) return;
    canvas.save();
    canvas.translate(x, 0);
    canvas.drawPath(
      path.shift(Offset(-x, 0)),
      Paint()
        ..shader = paints.fill
        ..color = _T.light.withValues(alpha: opacity),
    );
    canvas.restore();
  }

  void _paintRed(
    Canvas canvas,
    Path path,
    Offset center,
    double radius,
    double opacity,
  ) {
    if (radius <= 0 || opacity <= 0) return;
    final inv = 1 / radius;
    final normalized = path.transform(
      (Matrix4.diagonal3Values(
        inv,
        inv,
        1,
      )..setTranslationRaw(-center.dx * inv, -center.dy * inv, 0)).storage,
    );
    final paint = Paint()
      ..shader = paints.redMask
      ..color = _T.light.withValues(alpha: opacity);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radius);
    canvas.drawPath(normalized, paint);
    // The 1.2dp stroke overlaps the base fill's antialiased edge.
    canvas.drawPath(
      normalized,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = _Drop.redStroke * inv
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  void _paintGloss(Canvas canvas, Path path, double opacity) {
    if (opacity <= 0) return;
    final bounds = path.getBounds();
    canvas.save();
    canvas.clipPath(path);
    canvas.translate(bounds.left, bounds.top);
    canvas.scale(bounds.width, bounds.height);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()
        ..shader = paints.gloss
        ..color = _T.light.withValues(alpha: opacity),
    );
    canvas.restore();
  }

  void _paintCross(Canvas canvas, Offset center, double scale, double opacity) {
    const r = _Drop.crossHalfSize;
    final cross = Path()
      ..moveTo(-r, -r)
      ..lineTo(r, r)
      ..moveTo(r, -r)
      ..lineTo(-r, r);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.drawPath(cross, _stroke(_Drop.crossStroke, opacity));
    canvas.restore();
  }

  void _paintShade(Canvas canvas, VoiceLiquidGeometry g) {
    final body = g.body;
    final shadeTop = body.top - _T.shadeHeadroom;
    canvas.save();
    canvas.translate(0, shadeTop);
    canvas.scale(1, body.bottom - shadeTop);
    canvas.drawRect(
      Rect.fromLTRB(body.left, -_T.shadeFade, body.right, 1),
      Paint()
        ..shader = paints.shade
        ..color = _T.light.withValues(alpha: g.frame.opacity),
    );
    canvas.restore();
  }

  void _paintCapacity(Canvas canvas, VoiceLiquidGeometry g, Path bodyPath) {
    final elapsed = listeningElapsed();
    if (elapsed <= Duration.zero) return;
    const limit = Duration(seconds: _T.secondsPerMinute);
    final fraction = (elapsed.inMicroseconds / limit.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    final color = elapsed.inSeconds >= _T.warningSecond
        ? _T.capacityWarningFill
        : _T.capacityFill;
    final path = g.neck == null ? bodyPath : g.outline(includeNeck: false);
    canvas.save();
    if (g.neck != null) canvas.clipPath(path);
    canvas.drawRect(
      Rect.fromLTRB(
        g.body.left,
        path.getBounds().top,
        g.body.left + g.body.width * fraction,
        g.body.bottom,
      ),
      Paint()..color = color.withValues(alpha: color.a * g.frame.opacity),
    );
    canvas.restore();
  }

  void _paintRippleAccent(Canvas canvas, VoiceLiquidGeometry g) {
    if (g.frame.reduced) return;
    for (final ripple in g.ripples) {
      final age = g.frame.time - ripple.time;
      if (age < 0) continue;
      final travel = ripple.speed * age;
      final center = g.rippleCenter(ripple);
      final alpha =
          g.frame.opacity *
          _T.lineGlowOpacity *
          math.exp(-age * _T.rippleDecay);
      final tint = Paint()
        ..shader = paints.accent
        ..color = _T.light.withValues(alpha: alpha);
      for (final x in [center - travel, center + travel]) {
        canvas.save();
        canvas.translate(x, g.body.top);
        canvas.drawCircle(Offset.zero, _T.rippleWidth, tint);
        canvas.restore();
      }
    }
  }

  void _paintSheen(Canvas canvas, VoiceLiquidGeometry g) {
    final start = g.leftTangent + _T.sheenTrim;
    final end = g.rightTangent - _T.sheenTrim;
    final neck = g.neck;
    if (neck == null) {
      _paintSheenSegment(canvas, g, start, end);
    } else {
      _paintSheenSegment(
        canvas,
        g,
        start,
        g.mid + neck.left.x - _Drop.sheenNeckGap,
      );
      _paintSheenSegment(
        canvas,
        g,
        g.mid + neck.right.x + _Drop.sheenNeckGap,
        end,
      );
    }
  }

  void _paintSheenSegment(
    Canvas canvas,
    VoiceLiquidGeometry g,
    double start,
    double end,
  ) {
    if (end - start < _T.sheenMinLength) return;
    final a = g.leftTangent + _T.sheenInset;
    final span = g.rightTangent - _T.sheenInset - a;
    final points = g.surface(start, end, depth: _T.sheenDepth);
    final halfWidth = _T.sheenWidth / 2;
    // Fill a narrow ribbon in gradient coordinates so its thickness stays
    // constant while the horizontal extent of the fixed shader scales.
    final upper = [
      for (final point in points)
        Offset((point.dx - a) / span, point.dy - halfWidth),
    ];
    final path = _smoothPath(upper);
    final lower = [
      for (final point in points.reversed)
        Offset((point.dx - a) / span, point.dy + halfWidth),
    ];
    final cap = Radius.elliptical(halfWidth / span, halfWidth);
    path.arcToPoint(lower.first, radius: cap);
    _smoothTo(path, lower);
    path
      ..arcToPoint(upper.first, radius: cap)
      ..close();
    canvas.save();
    canvas.translate(a, 0);
    canvas.scale(span, 1);
    canvas.drawPath(
      path,
      Paint()
        ..shader = paints.sheen
        ..color = _T.light.withValues(alpha: g.frame.opacity * _T.sheenOpacity),
    );
    canvas.restore();
  }

  void _paintLines(Canvas canvas, VoiceLiquidGeometry g) {
    final left = math.max(lineLeft, g.body.left + _T.lineInset);
    final right = math.min(lineRight, g.body.right - _T.lineInset);
    if (right - left < _T.lineMinLength) return;
    final mid = g.body.center.dy + _T.lineCenterOffset;
    final amplitude = g.body.height / 2 - _T.lineAmplitudeInset;
    final volume = g.frame.reduced ? 0.0 : g.frame.volume;
    final time = g.frame.reduced ? 0.0 : g.frame.time;
    for (final (index, line) in _T.lines.indexed) {
      final points = <Offset>[];
      for (
        var x = left;
        x <= right + _T.lineSampleTolerance;
        x += _T.lineStep
      ) {
        final att = math.sin(math.pi * (x - left) / (right - left));
        final phase =
            line.frequency * (x + ComposerTokens.stripInset) -
            line.speed * time +
            line.phase;
        final y =
            mid +
            (amplitude * volume * line.amplitude + _T.lineAmplitudeBase) *
                att *
                att *
                math.sin(phase);
        points.add(Offset(x, y));
      }
      final path = _smoothPath(points);
      if (index == 0) {
        canvas.drawPath(
          path,
          _stroke(_T.lineGlowWidth, g.frame.opacity * _T.lineGlowOpacity),
        );
      }
      canvas.drawPath(
        path,
        _stroke(line.width, g.frame.opacity * line.opacity),
      );
    }
  }

  Paint _stroke(double width, double alpha) => Paint()
    ..color = _T.light.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  bool shouldRepaint(VoiceLiquidPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.paints != paints ||
      oldDelegate.fullWidth != fullWidth ||
      oldDelegate.capsuleWidth != capsuleWidth ||
      oldDelegate.lineLeft != lineLeft ||
      oldDelegate.lineRight != lineRight ||
      oldDelegate.listeningElapsed != listeningElapsed ||
      oldDelegate.headroom != headroom ||
      oldDelegate.sideRoom != sideRoom;
}
