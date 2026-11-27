import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../design/voice_tokens.dart';
import 'dictation_controller.dart';

typedef _RimFrame = ({double offset, double opacity, double cut});

/// A paint-only overlay, positioned relative to the panel's top edge.
class RimGlow extends StatefulWidget {
  const RimGlow({super.key, required this.controller});

  final DictationController controller;

  @override
  State<RimGlow> createState() => _RimGlowState();
}

class _RimGlowState extends State<RimGlow> with SingleTickerProviderStateMixin {
  final _paint = ValueNotifier<_RimFrame>((offset: 0, opacity: 0, cut: 0));
  final _raster = _RimRaster();
  late final Ticker _ticker = createTicker(_tick);
  bool _reduced = false;
  bool _expanded = false;
  bool _cut = false;
  DictationPhase _phase = DictationPhase.idle;
  double _cutMix = 0;
  double _cutFrom = 0;
  Duration _cutElapsed = Duration.zero;
  double _volume = 0;
  double _velocity = 0;
  double _offset = 0;
  double _fadeFrom = 0;
  Duration _fadeElapsed = Duration.zero;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced != reduced) {
      _reduced = reduced;
      _volume = widget.controller.value.volume;
      _velocity = 0;
      _beginFade();
    }
    _sync();
  }

  @override
  void didUpdateWidget(RimGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    final expanded = widget.controller.barExpanded;
    if (expanded != _expanded) {
      _expanded = expanded;
      _beginFade();
    }
    final frame = widget.controller.value;
    final starting =
        frame.phase == DictationPhase.press && _phase != frame.phase;
    _phase = frame.phase;
    final cut = expanded && frame.detached;
    if (_cut != cut) {
      _cut = cut;
      _cutFrom = _cutMix;
      _cutElapsed = Duration.zero;
    }
    if (starting) _cutMix = _cutFrom = 0;
    if (_reduced) _cutMix = _cut ? 1 : 0;
    if (_ticker.isActive || (!_expanded && _paint.value.opacity == 0)) return;
    if (_reduced && _fadeElapsed >= AppMotion.reducedFade) {
      _paint.value = (
        offset: _offset,
        opacity: _brightness(widget.controller.value.volume),
        cut: _cutMix,
      );
    } else {
      _ticker.start();
    }
  }

  void _beginFade() {
    _fadeFrom = _paint.value.opacity;
    _fadeElapsed = Duration.zero;
  }

  double _brightness(double volume) =>
      RimTokens.opacity +
      RimTokens.volumeOpacity * volume.clamp(0, VoiceTokens.maxVolume);

  void _tick(Duration elapsed) {
    final delta = elapsed - _last;
    _last = elapsed;
    final dt = math.min(
      VoiceTokens.maxStep,
      delta.inMicroseconds / Duration.microsecondsPerSecond,
    );
    if (_expanded && !_reduced) {
      _velocity +=
          (VoiceTokens.volumeStiffness *
                  (widget.controller.value.volume - _volume) -
              VoiceTokens.volumeDamping * _velocity) *
          dt;
      _volume = (_volume + _velocity * dt).clamp(0.0, VoiceTokens.maxEnvelope);
      _offset =
          (_offset +
              dt *
                  (RimTokens.speed +
                      RimTokens.volumeSpeed *
                          math.min(VoiceTokens.maxVolume, _volume))) %
          RimTokens.period;
    }
    final duration = _reduced ? AppMotion.reducedFade : RimTokens.fade;
    if (_fadeElapsed < duration) _fadeElapsed += delta;
    final progress = (_fadeElapsed.inMicroseconds / duration.inMicroseconds)
        .clamp(0.0, 1.0);
    final target = _expanded
        ? _brightness(_reduced ? widget.controller.value.volume : _volume)
        : 0.0;
    if (!_reduced && _cutElapsed < RimTokens.cutFade) {
      _cutElapsed += delta;
      final cutProgress =
          (_cutElapsed.inMicroseconds / RimTokens.cutFade.inMicroseconds).clamp(
            0.0,
            1.0,
          );
      _cutMix = ui.lerpDouble(
        _cutFrom,
        _cut ? 1 : 0,
        RimTokens.fadeCurve.transform(cutProgress),
      )!;
    }
    _paint.value = (
      offset: _offset,
      opacity: ui.lerpDouble(
        _fadeFrom,
        target,
        RimTokens.fadeCurve.transform(progress),
      )!,
      cut: _cutMix,
    );
    if (progress == 1 && (!_expanded || _reduced)) {
      _ticker.stop();
      _last = Duration.zero;
      if (!_expanded) _volume = _velocity = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _ticker.dispose();
    _paint.dispose();
    _raster.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _RimPainter(
          frame: _paint,
          raster: _raster,
          colors: RimTokens.colors(AppTokens.of(context)),
          red: VoiceDropPaintTokens.red(AppTokens.of(context)),
          ratio: MediaQuery.devicePixelRatioOf(context),
        ),
      ),
    ),
  );
}

class _RimRaster {
  double? _width;
  double? _ratio;
  ui.Image? _image;
  ui.ImageShader? _shader;

  ui.ImageShader shader(double width, double ratio) {
    if (_width == width && _ratio == ratio) return _shader!;
    dispose();
    _width = width;
    _ratio = ratio;

    final r = math.min(RimTokens.radius, width / 2);
    const top = RimTokens.top;
    const bottom = top + RimTokens.legBottom;
    final path = Path()
      ..moveTo(0, bottom)
      ..lineTo(0, top + r)
      ..arcTo(Rect.fromLTWH(0, top, r * 2, r * 2), math.pi, math.pi / 2, false)
      ..lineTo(width - r, top)
      ..arcTo(
        Rect.fromLTWH(width - r * 2, top, r * 2, r * 2),
        -math.pi / 2,
        math.pi / 2,
        false,
      )
      ..lineTo(width, bottom);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = RimTokens.haloStroke
        ..color = VoiceTokens.light.withValues(alpha: RimTokens.haloOpacity)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          RimTokens.haloSigma,
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = RimTokens.stroke
        ..color = VoiceTokens.light,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, RimTokens.height),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(0, RimTokens.height),
          const [VoiceTokens.light, VoiceTokens.light, Colors.transparent],
          const [0, RimTokens.fadeStart, 1],
        ),
    );
    final picture = recorder.endRecording();
    final image = _image = picture.toImageSync(
      (width * ratio).ceil(),
      (RimTokens.height * ratio).ceil(),
    );
    picture.dispose();
    return _shader = ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.low,
    );
  }

  void dispose() {
    _shader?.dispose();
    _image?.dispose();
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.frame,
    required this.raster,
    required this.colors,
    required this.red,
    required this.ratio,
  }) : super(repaint: frame);

  final ValueListenable<_RimFrame> frame;
  final _RimRaster raster;
  final List<Color> colors;
  final Color red;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final (:offset, :opacity, :cut) = frame.value;
    if (opacity == 0 || size.isEmpty) return;
    final shader = raster.shader(size.width, ratio);
    // Only the gradient stop positions move. Texture coordinates stay aligned
    // to the pre-rasterized stroke and halo all round the two fixed corners.
    final positions = <Offset>[];
    final texture = <Offset>[];
    final vertexColors = <Color>[];
    final first = offset - RimTokens.period;
    final last = size.width + RimTokens.period;
    for (var x = first; x <= last; x += RimTokens.period) {
      for (var i = 0; i < RimTokens.periodStops.length; i++) {
        final stop = x + RimTokens.period * RimTokens.periodStops[i];
        final color = Color.lerp(
          colors[i],
          red,
          cut,
        )!.withValues(alpha: opacity);
        final top = Offset(stop, 0);
        final bottom = Offset(stop, size.height);
        positions.addAll([top, bottom]);
        texture.addAll([top * ratio, bottom * ratio]);
        vertexColors.addAll([color, color]);
      }
    }
    final vertices = ui.Vertices(
      VertexMode.triangleStrip,
      positions,
      textureCoordinates: texture,
      colors: vertexColors,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawVertices(vertices, BlendMode.modulate, Paint()..shader = shader);
    canvas.restore();
    vertices.dispose();
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      ratio != oldDelegate.ratio ||
      red != oldDelegate.red ||
      !listEquals(colors, oldDelegate.colors);
}
