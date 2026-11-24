import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data' show Float64List;

import 'package:flutter/services.dart' show rootBundle;

import '../design/loading_tokens.dart';
import '../widgets/chhers_loader.dart' show paintChhersWordmark;
import 'support_actions.dart';

typedef BadgeSprite = ({Image image, Size size});

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);
const _paperShade = Color(0xFF46321E);
const _paper = Color(0xFFF2ECE0);
const _metalLight = Color(0xFFF4E2B2);
const _metal = Color(0xFFB48F55);
const _metalDark = Color(0xFF644A22);

/// Owns the immutable images for one page layout and color scheme.
class SupportBadgeSprites {
  SupportBadgeSprites._(this._sprites);

  final List<BadgeSprite> _sprites;

  BadgeSprite get front => _sprites[0];
  BadgeSprite get back => _sprites[1];
  BadgeSprite get cap => _sprites[2];
  BadgeSprite get ring => _sprites[3];
  BadgeSprite get eyelet => _sprites[4];
  BadgeSprite get ambient => _sprites[5];
  BadgeSprite get contact => _sprites[6];
  BadgeSprite get gloss => _sprites[7];
  BadgeSprite get flash => _sprites[8];

  static Future<SupportBadgeSprites> load({
    required double width,
    required double height,
    required double slot,
    required double devicePixelRatio,
    required bool dark,
  }) async {
    final face = Size(width, height);
    final unit = width / 15;
    // The reference hardware is dimensioned on the 150px card template.
    final hardwareUnit = width / 150;
    final source = await Future.wait<Image>([
      _loadPaper(),
      renderInkQr(SupportCode.alipay),
      renderInkQr(SupportCode.weChat),
    ], cleanUp: (image) => image.dispose());

    try {
      Future<BadgeSprite> raster(Size size, void Function(Canvas) draw) =>
          _raster(size, devicePixelRatio, draw);
      Future<BadgeSprite> shadow(double blur, double opacity) {
        final pad = (blur * 1.6 + 2).ceilToDouble();
        final bounds = Rect.fromLTWH(pad, pad, width, height);
        return _raster(Size(width + 2 * pad, height + 2 * pad), 1, (canvas) {
          canvas.drawRRect(
            _roundFace(bounds, unit),
            Paint()
              ..color = (dark ? _black : _paperShade).withValues(alpha: opacity)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
          );
        });
      }

      return SupportBadgeSprites._(
        await Future.wait<BadgeSprite>([
          for (final (index, kind) in SupportCode.values.indexed)
            raster(face, (canvas) {
              _drawFace(
                canvas,
                face,
                slot,
                dark,
                kind,
                source[0],
                source[index + 1],
              );
            }),
          raster(
            Size(20 * hardwareUnit, 14.4 * hardwareUnit),
            (canvas) => _drawCap(canvas, hardwareUnit),
          ),
          raster(
            Size(13 * hardwareUnit, 19 * hardwareUnit),
            (canvas) => _drawRing(canvas, hardwareUnit),
          ),
          raster(
            Size.square(2.4 * unit),
            (canvas) => _drawEyelet(canvas, unit, dark),
          ),
          shadow(24, .32),
          shadow(4, .38),
          // These broad gradients are smooth at lower resolution.
          _lightSprite(face * 2.4, 118, .26),
          _lightSprite(face, 105, .9),
        ], cleanUp: (sprite) => sprite.image.dispose()),
      );
    } finally {
      for (final image in source) {
        image.dispose();
      }
    }
  }

  void dispose() {
    for (final sprite in _sprites) {
      sprite.image.dispose();
    }
  }
}

Future<Image> _loadPaper() async {
  final bytes = await rootBundle.load('assets/support/paper_texture.png');
  final codec = await instantiateImageCodec(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<BadgeSprite> _raster(
  Size size,
  double scale,
  void Function(Canvas) draw,
) async {
  final pixelWidth = (size.width * scale).ceil();
  final pixelHeight = (size.height * scale).ceil();
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(pixelWidth / size.width, pixelHeight / size.height);
  try {
    draw(canvas);
  } catch (_) {
    recorder.endRecording().dispose();
    rethrow;
  }
  final picture = recorder.endRecording();
  try {
    return (image: await picture.toImage(pixelWidth, pixelHeight), size: size);
  } finally {
    picture.dispose();
  }
}

RRect _roundFace(Rect rect, double unit) =>
    RRect.fromRectAndRadius(rect, Radius.circular(.95 * unit));

void _drawFace(
  Canvas canvas,
  Size size,
  double slot,
  bool dark,
  SupportCode kind,
  Image texture,
  Image ink,
) {
  final unit = size.width / 15;
  final bounds = Offset.zero & size;
  final shell = _roundFace(bounds, unit);
  final hole = Offset(size.width / 2, slot);
  final paint = Paint();
  canvas.save();
  canvas.clipPath(
    Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(shell)
      ..addOval(Rect.fromCircle(center: hole, radius: .34 * unit)),
  );

  canvas.drawRect(
    bounds,
    paint
      ..shader = Gradient.radial(
        Offset(size.width * .42, size.height * .26),
        size.height * .80,
        const [Color(0xFFF9F6EE), _paper, Color(0xFFE6DECF)],
        const [0, .68, 1],
      ),
  );
  const tileSide = 160.0;
  final tile = ImageShader(
    texture,
    TileMode.repeated,
    TileMode.repeated,
    // 320 texture pixels span 160 logical pixels.
    Float64List.fromList([
      tileSide / texture.width,
      0,
      0,
      0,
      0,
      tileSide / texture.height,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    ]),
    filterQuality: FilterQuality.low,
  );
  canvas.drawRect(bounds, paint..shader = tile);
  canvas.drawRect(
    bounds,
    paint
      ..shader = Gradient.linear(
        Offset.zero,
        bounds.topRight,
        [
          _paperShade.withValues(alpha: .06),
          _paperShade.withValues(alpha: 0),
          _paperShade.withValues(alpha: 0),
          _paperShade.withValues(alpha: .06),
        ],
        const [0, .15, .85, 1],
      ),
  );
  canvas.drawRect(
    bounds,
    paint
      ..shader = Gradient.linear(
        Offset.zero,
        bounds.bottomLeft,
        [
          _white.withValues(alpha: .22),
          _paperShade.withValues(alpha: 0),
          _paperShade.withValues(alpha: 0),
          _paperShade.withValues(alpha: .05),
        ],
        const [0, .26, .8, 1],
      ),
  );
  paint.shader = null;

  final secondary = Color.lerp(const Color(0xFF7A7064), kind.ink, .62)!;
  final inset = 1.35 * unit;
  const words = 'SUPPORT PASS';
  final markHeight = .9 * unit;
  final markWidth =
      markHeight * LoadingTokens.viewWidth / LoadingTokens.viewHeight;
  final mark = Rect.fromLTWH(inset, 2.95 * unit, markWidth, markHeight);
  paintChhersWordmark(
    canvas,
    mark.shift(const Offset(0, .7)),
    _white.withValues(alpha: .85),
  );
  paintChhersWordmark(
    canvas,
    mark.shift(const Offset(0, -.4)),
    _paperShade.withValues(alpha: .2),
  );
  paintChhersWordmark(canvas, mark, kind.ink);
  _print(
    canvas,
    words,
    x: size.width - inset,
    y: 3.15 * unit,
    fontSize: .5 * unit,
    color: secondary,
    tracking: .15 * unit,
    right: true,
    mono: true,
  );

  final panel = Rect.fromLTWH(
    size.width / 2 - 4.8 * unit,
    4.65 * unit,
    9.6 * unit,
    9.6 * unit,
  );
  final modules = Rect.fromLTWH(
    0,
    0,
    ink.width.toDouble(),
    ink.height.toDouble(),
  );
  canvas.drawImageRect(
    ink,
    modules,
    panel.deflate(.6 * unit),
    paint..filterQuality = FilterQuality.none,
  );
  _drawQrCorners(canvas, panel.inflate(.42 * unit), unit, kind.ink);

  final nameTop = 15.4 * unit;
  final dot = Offset(inset + .25 * unit, nameTop + .875 * unit);
  canvas.drawCircle(
    dot,
    .32 * unit,
    paint..color = _white.withValues(alpha: .35),
  );
  canvas.drawCircle(dot, .25 * unit, paint..color = kind.brandColor);
  final name = _print(
    canvas,
    kind.label,
    x: inset + .92 * unit,
    y: nameTop,
    fontSize: 1.75 * unit,
    color: kind.ink,
    tracking: .0875 * unit,
    bold: true,
  );
  final alipay = kind == SupportCode.alipay;
  _print(
    canvas,
    alipay ? 'ALIPAY' : 'WECHAT',
    x: inset + 1.34 * unit + name.width,
    y: nameTop + name.baseline,
    fontSize: .5 * unit,
    color: secondary,
    tracking: .14 * unit,
    mono: true,
    baseline: true,
  );

  _seal(canvas, Offset(size.width - inset - 1.05 * unit, 16.1 * unit), unit);

  _print(
    canvas,
    alipay ? '好帖常有，Chhers 常在。' : '每一次更新，都有你的一份。',
    x: inset,
    y: 17.75 * unit,
    fontSize: .76 * unit,
    color: secondary,
    tracking: .038 * unit,
  );
  final footerTop = size.height - 1.61 * unit;
  _print(
    canvas,
    words,
    x: inset,
    y: footerTop,
    fontSize: .46 * unit,
    color: secondary,
    tracking: .12 * unit,
    mono: true,
  );
  _print(
    canvas,
    alipay ? '背面 · 微信' : '背面 · 支付宝',
    x: size.width - inset,
    y: footerTop,
    fontSize: .46 * unit,
    color: secondary,
    tracking: .12 * unit,
    right: true,
    mono: true,
  );

  canvas.drawRect(
    bounds,
    paint
      ..color = _white.withValues(alpha: .60)
      ..shader = tile,
  );
  tile.dispose();
  paint
    ..shader = null
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = kind.ink.withValues(alpha: .9);
  canvas.drawRRect(shell.deflate(.5), paint);
  paint
    ..strokeWidth = .06 * unit
    ..color = _white.withValues(alpha: .55);
  canvas.drawCircle(hole, 1.32 * unit, paint);
  paint
    ..strokeWidth = .30 * unit
    ..color = _paperShade.withValues(alpha: .08);
  canvas.drawCircle(hole, 1.15 * unit, paint);

  if (dark) {
    canvas.drawRect(
      bounds,
      paint
        ..style = PaintingStyle.fill
        ..color = _black.withValues(alpha: .1),
    );
  }
  canvas.restore();
}

({double width, double baseline}) _print(
  Canvas canvas,
  String text, {
  required double x,
  required double y,
  required double fontSize,
  required Color color,
  required double tracking,
  bool right = false,
  bool mono = false,
  bool bold = false,
  bool baseline = false,
}) {
  final paragraph =
      (ParagraphBuilder(
              ParagraphStyle(
                fontSize: fontSize,
                height: 1,
                fontWeight: bold
                    ? FontWeight.w700
                    : (mono ? FontWeight.w600 : FontWeight.w400),
                fontFamily: mono ? 'monospace' : null,
              ),
            )
            ..pushStyle(
              TextStyle(
                color: color,
                letterSpacing: tracking,
                shadows: [
                  Shadow(
                    color: _white.withValues(alpha: .85),
                    offset: const Offset(0, .7),
                    blurRadius: .3,
                  ),
                  Shadow(
                    color: _paperShade.withValues(alpha: .2),
                    offset: const Offset(0, -.4),
                    blurRadius: .4,
                  ),
                ],
              ),
            )
            ..addText(text))
          .build()
        ..layout(const ParagraphConstraints(width: 1024));
  try {
    final width = paragraph.longestLine;
    final ascent = paragraph.alphabeticBaseline;
    canvas.drawParagraph(
      paragraph,
      Offset(right ? x - width : x, baseline ? y - ascent : y),
    );
    return (width: width, baseline: ascent);
  } finally {
    paragraph.dispose();
  }
}

void _drawQrCorners(Canvas canvas, Rect rect, double unit, Color color) {
  final path = Path();
  for (final (corner, sx, sy) in [
    (rect.topLeft, 1.0, 1.0),
    (rect.topRight, -1.0, 1.0),
    (rect.bottomLeft, 1.0, -1.0),
    (rect.bottomRight, -1.0, -1.0),
  ]) {
    path
      ..moveTo(corner.dx, corner.dy + sy * unit)
      ..lineTo(corner.dx, corner.dy + sy * .36 * unit)
      ..quadraticBezierTo(
        corner.dx,
        corner.dy,
        corner.dx + sx * .36 * unit,
        corner.dy,
      )
      ..lineTo(corner.dx + sx * unit, corner.dy);
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..strokeWidth = .16 * unit
      ..style = PaintingStyle.stroke,
  );
}

void _seal(Canvas canvas, Offset center, double unit) {
  final paint = Paint();
  canvas.drawCircle(
    center + Offset(.05 * unit, .07 * unit),
    1.06 * unit,
    paint
      ..color = _paperShade.withValues(alpha: .15)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, .09 * unit),
  );
  canvas.drawCircle(
    center - Offset(.04 * unit, .06 * unit),
    1.05 * unit,
    paint..color = _white.withValues(alpha: .85),
  );
  paint.maskFilter = null;
  final bounds = Rect.fromCircle(center: center, radius: 1.05 * unit);
  canvas.drawOval(
    bounds,
    paint
      ..shader = Gradient.linear(
        bounds.topLeft,
        bounds.bottomRight,
        const [Color(0xFFF9F6EE), _paper, Color(0xFFDCD2BF)],
        const [0, .52, 1],
      ),
  );
  final inner = bounds.deflate(.27 * unit);
  canvas.drawOval(
    inner,
    paint
      ..shader = Gradient.linear(inner.topLeft, inner.bottomRight, [
        _paperShade.withValues(alpha: .2),
        _white.withValues(alpha: .82),
      ])
      ..style = PaintingStyle.stroke
      ..strokeWidth = .055 * unit,
  );
  paint
    ..style = PaintingStyle.fill
    ..shader = null;
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(unit);
  final heart = Path()
    ..moveTo(0, .38)
    ..cubicTo(-.2, .24, -.43, .05, -.43, -.13)
    ..cubicTo(-.43, -.37, -.14, -.45, 0, -.25)
    ..cubicTo(.14, -.45, .43, -.37, .43, -.13)
    ..cubicTo(.43, .05, .2, .24, 0, .38)
    ..close();
  canvas.drawPath(
    heart.shift(const Offset(.045, .05)),
    paint..color = _paperShade.withValues(alpha: .2),
  );
  canvas.drawPath(
    heart.shift(const Offset(-.04, -.05)),
    paint..color = _white.withValues(alpha: .92),
  );
  canvas.drawPath(heart, paint..color = _paper);
  canvas.restore();
}

Shader _brass(Rect rect, List<Color> colors, List<double> stops) =>
    Gradient.linear(rect.topLeft, rect.topRight, colors, stops);

void _drawCap(Canvas canvas, double unit) {
  final cylinder = Rect.fromLTWH(unit, .6 * unit, 18 * unit, 10 * unit);
  final neck = Rect.fromCenter(
    center: Offset(cylinder.center.dx, cylinder.bottom + 1.5 * unit),
    width: 3.2 * unit,
    height: 3.4 * unit,
  );
  final paint = Paint();
  canvas.drawRRect(
    RRect.fromRectAndRadius(neck, Radius.circular(.8 * unit)),
    paint
      ..shader = _brass(
        neck,
        const [_metalDark, _metalLight, _metalDark],
        const [0, .4, 1],
      ),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(cylinder, Radius.circular(1.8 * unit)),
    paint
      ..shader = _brass(
        cylinder,
        const [_metalDark, _metal, _metalLight, _metal, _metalDark, _metal],
        const [0, .22, .36, .5, .8, 1],
      ),
  );
  paint.shader = null;
  canvas.drawRect(
    Rect.fromLTWH(
      cylinder.left,
      cylinder.bottom - 1.6 * unit,
      cylinder.width,
      .5 * unit,
    ),
    paint..color = _black.withValues(alpha: .28),
  );
  canvas.drawRect(
    Rect.fromLTWH(
      cylinder.left,
      cylinder.bottom - 1.1 * unit,
      cylinder.width,
      .3 * unit,
    ),
    paint..color = _white.withValues(alpha: .45),
  );
}

void _drawRing(Canvas canvas, double unit) {
  final bounds = Rect.fromCenter(
    center: Offset(6.5 * unit, 9.5 * unit),
    width: 9.2 * unit,
    height: 14.8 * unit,
  );
  final paint = Paint()
    ..shader = _brass(
      bounds,
      const [_metalDark, _metalLight, _metal, _metalDark],
      const [0, .3, .55, 1],
    )
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5 * unit;
  canvas.drawOval(bounds, paint);
  canvas.drawArc(
    bounds,
    math.pi * 1.08,
    math.pi * .34,
    false,
    paint
      ..shader = null
      ..strokeWidth = .6 * unit
      ..strokeCap = StrokeCap.round
      ..color = _white.withValues(alpha: .7),
  );
}

void _drawEyelet(Canvas canvas, double unit, bool dark) {
  final center = Offset(1.2 * unit, 1.2 * unit);
  final silhouette = Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Rect.fromCircle(center: center, radius: unit))
    ..addOval(Rect.fromCircle(center: center, radius: .34 * unit));
  canvas.save();
  canvas.clipPath(silhouette);
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(math.pi * 2 / 3);
  final paint = Paint()
    ..shader = Gradient.sweep(
      Offset.zero,
      const [_metalLight, _metal, _metalDark, _metal, _metalLight, _metal],
      const [0, .22, .42, .62, .82, 1],
    );
  canvas.drawCircle(Offset.zero, unit, paint);
  canvas.restore();
  paint.shader = null;
  canvas.drawCircle(
    center,
    .975 * unit,
    paint
      ..color = _white.withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .05 * unit,
  );
  canvas.drawCircle(
    center,
    .40 * unit,
    paint
      ..color = _black.withValues(alpha: .35)
      ..strokeWidth = .09 * unit,
  );
  if (dark) {
    canvas.drawPath(
      silhouette,
      paint
        ..color = _black.withValues(alpha: .1)
        ..style = PaintingStyle.fill,
    );
  }
  canvas.restore();
}

Future<BadgeSprite> _lightSprite(Size size, double degrees, double peak) =>
    _raster(size, .5, (canvas) {
      final bounds = Offset.zero & size;
      final radians = degrees * math.pi / 180;
      final axis = Offset(math.sin(radians), -math.cos(radians));
      final extent =
          (size.width * axis.dx.abs() + size.height * axis.dy.abs()) / 2;
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = Gradient.linear(
            bounds.center - axis * extent,
            bounds.center + axis * extent,
            [
              _white.withValues(alpha: 0),
              _white.withValues(alpha: peak),
              _white.withValues(alpha: 0),
            ],
            const [.28, .50, .72],
          ),
      );
    });
