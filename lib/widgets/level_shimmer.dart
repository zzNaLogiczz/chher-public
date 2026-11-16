import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/level_tokens.dart';

/// The glyph mask is rasterized once; animation only moves a colored vertex band.
class LevelShimmer extends StatefulWidget {
  const LevelShimmer({
    super.key,
    required this.text,
    required this.style,
    required this.size,
    required this.animation,
    required this.sweep,
  });

  final String text;
  final TextStyle style;
  final Size size;
  final AnimationController animation;
  final Duration sweep;

  @override
  State<LevelShimmer> createState() => _LevelShimmerState();
}

class _LevelShimmerState extends State<LevelShimmer> {
  Object? _maskKey;
  ui.Image? _mask;
  ui.ImageShader? _shader;

  void _prepare(double dpr) {
    final key = (widget.text, widget.style, widget.size, dpr);
    if (key == _maskKey) return;
    _shader?.dispose();
    _mask?.dispose();
    _shader = null;
    _mask = null;
    _maskKey = key;
    if (widget.size.isEmpty) return;
    final text = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: widget.style.copyWith(
          foreground: ui.Paint()..color = LevelTokens.white,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(dpr);
    text.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    _mask = picture.toImageSync(
      (widget.size.width * dpr).ceil().clamp(1, 0x7fffffff),
      (widget.size.height * dpr).ceil().clamp(1, 0x7fffffff),
    );
    picture.dispose();
    text.dispose();
    _shader = ui.ImageShader(
      _mask!,
      ui.TileMode.decal,
      ui.TileMode.decal,
      Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
      filterQuality: FilterQuality.low,
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    _mask?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _prepare(dpr);
    return RepaintBoundary(
      child: CustomPaint(
        size: widget.size,
        painter: _ShimmerPainter(
          shader: _shader,
          dpr: dpr,
          animation: widget.animation,
          sweep: widget.sweep,
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({
    required this.shader,
    required this.dpr,
    required this.animation,
    required this.sweep,
  }) : super(repaint: animation);

  final ui.ImageShader? shader;
  final double dpr;
  final AnimationController animation;
  final Duration sweep;

  @override
  void paint(Canvas canvas, Size size) {
    if (shader == null || !animation.isAnimating || size.isEmpty) return;
    final phase =
        animation.value *
        animation.duration!.inMicroseconds /
        sweep.inMicroseconds;
    if (phase <= 0 || phase >= 1) return;
    final center =
        size.width *
        (LevelTokens.shimmerStart + LevelTokens.shimmerTravel * phase);
    final halfWidth = size.width * LevelTokens.shimmerBandHalfWidth;
    final xs = <double>{
      0,
      size.width,
      (center - halfWidth).clamp(0.0, size.width),
      center.clamp(0.0, size.width),
      (center + halfWidth).clamp(0.0, size.width),
    }.toList()..sort();
    final positions = <Offset>[];
    final texture = <Offset>[];
    final colors = <Color>[];
    for (final x in xs) {
      final alpha = (1 - (x - center).abs() / halfWidth).clamp(0.0, 1.0);
      for (final y in [0.0, size.height]) {
        positions.add(Offset(x, y));
        texture.add(Offset(x * dpr, y * dpr));
        colors.add(
          LevelTokens.highlight.withValues(
            alpha: alpha * LevelTokens.shimmerAlpha,
          ),
        );
      }
    }
    final vertices = ui.Vertices(
      ui.VertexMode.triangleStrip,
      positions,
      textureCoordinates: texture,
      colors: colors,
    );
    canvas.drawVertices(
      vertices,
      ui.BlendMode.modulate,
      Paint()..shader = shader,
    );
    vertices.dispose();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) =>
      old.shader != shader ||
      old.dpr != dpr ||
      old.animation != animation ||
      old.sweep != sweep;
}
