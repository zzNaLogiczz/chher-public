import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/level_tokens.dart';

// Unit-circle shaders stay fixed: only their canvas transform and paint alpha
// change. Elliptical falloff needs neither a layer nor a blur filter.
final _sparkCore = ui.Gradient.radial(
  Offset.zero,
  1,
  const [LevelTokens.sparkCore, LevelTokens.sparkGold, LevelTokens.sparkEdge],
  const [0, .5, 1],
);
final _sparkHalo = ui.Gradient.radial(Offset.zero, 1, [
  LevelTokens.sparkGlow,
  LevelTokens.sparkGlow.withValues(alpha: 0),
]);
final _flare = ui.Gradient.radial(
  Offset.zero,
  1,
  [LevelTokens.flareColor, LevelTokens.flareColor.withValues(alpha: 0)],
  const [0, LevelTokens.flareStop],
);

void _ellipse(
  Canvas canvas,
  Offset center,
  Offset radii,
  ui.Shader shader,
  double alpha,
) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(radii.dx, radii.dy);
  canvas.drawCircle(
    Offset.zero,
    1,
    Paint()
      ..color = LevelTokens.white.withValues(alpha: alpha)
      ..shader = shader,
  );
  canvas.restore();
}

void _clipPlate(Canvas canvas, Size size, double scale) => canvas.clipRRect(
  RRect.fromRectAndRadius(
    Offset.zero & size,
    Radius.circular(LevelTokens.radius * scale),
  ),
);

/// Static interior light. No listenable, ticker, state or repaint boundary.
class LevelInnerGlowPainter extends CustomPainter {
  LevelInnerGlowPainter({
    required this.tier,
    required this.dark,
    required this.scale,
  }) : spec = LevelTokens.innerGlow(tier, dark, scale);
  final String tier;
  final bool dark;
  final double scale;
  final LevelGlowSpec? spec;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = spec;
    if (glow == null || size.isEmpty) return;
    canvas.save();
    _clipPlate(canvas, size, scale);
    _ellipse(
      canvas,
      glow.center,
      Offset(size.width * glow.radii.dx, size.height * glow.radii.dy),
      ui.Gradient.radial(
        Offset.zero,
        1,
        [glow.color, glow.color.withValues(alpha: 0)],
        [0, glow.stop],
      ),
      1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LevelInnerGlowPainter old) =>
      tier != old.tier || dark != old.dark || scale != old.scale;
}

/// One small retained paint layer for the flare and all embers. Every effect
/// shares the badge's finite controller; waiting frames paint nothing.
class LevelBurstPainter extends CustomPainter {
  LevelBurstPainter({
    required this.animation,
    required this.scale,
    required this.sparkCount,
  }) : super(repaint: animation);
  final AnimationController animation;
  final double scale;
  final int sparkCount;

  Iterable<LevelSparkSpec> get particles => sparkCount == 12
      ? LevelTokens.sparks
      : sparkCount == 8
      ? LevelTokens.sparks.indexed.where((e) => e.$1 % 3 != 2).map((e) => e.$2)
      : const <LevelSparkSpec>[];

  @override
  void paint(Canvas canvas, Size size) {
    if (!animation.isAnimating || sparkCount == 0 || size.isEmpty) return;
    final seconds = animation.value * animation.duration!.inMicroseconds / 1e6;
    canvas.save();
    _clipPlate(canvas, size, scale);
    final flareAlpha = seconds < LevelTokens.flarePeak
        ? seconds / LevelTokens.flarePeak
        : (LevelTokens.flareEnd - seconds) /
              (LevelTokens.flareEnd - LevelTokens.flarePeak);
    if (flareAlpha > 0) {
      _ellipse(
        canvas,
        Offset(
          size.width * LevelTokens.flareCenter.dx,
          size.height * LevelTokens.flareCenter.dy,
        ),
        Offset(
          size.width * LevelTokens.flareRadii.dx,
          size.height * LevelTokens.flareRadii.dy,
        ),
        _flare,
        flareAlpha.clamp(0.0, 1.0),
      );
    }
    for (final spark in particles) {
      final local = seconds - spark.delay;
      if (local <= 0 || local >= LevelTokens.particleLife) continue;
      final fraction = local / LevelTokens.cycleSeconds;
      const bright = LevelTokens.particleBrightAt;
      const dim = LevelTokens.particleDimAt;
      const gone = LevelTokens.particleGoneAt;
      const dimAlpha = LevelTokens.particleDimAlpha;
      final alpha = fraction < bright
          ? fraction / bright
          : fraction < dim
          ? 1 - (1 - dimAlpha) * (fraction - bright) / (dim - bright)
          : dimAlpha * (gone - fraction) / (gone - dim);
      final travel = LevelTokens.particleCurve.transform(
        local / LevelTokens.particleLife,
      );
      final shrink = 1 + (LevelTokens.particleEndScale - 1) * travel;
      final center = Offset(
        size.width * spark.x + spark.dx * scale * travel,
        (spark.y + spark.dy * travel) * scale,
      );
      final coreRadius = spark.size / 2 * scale * shrink;
      final glowRadius =
          (spark.size / 2 + LevelTokens.particleGlowRadius) * scale * shrink;
      _ellipse(
        canvas,
        center,
        Offset(glowRadius, glowRadius),
        _sparkHalo,
        alpha,
      );
      _ellipse(
        canvas,
        center,
        Offset(coreRadius, coreRadius),
        _sparkCore,
        alpha,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LevelBurstPainter old) =>
      animation != old.animation ||
      scale != old.scale ||
      sparkCount != old.sparkCount;
}
