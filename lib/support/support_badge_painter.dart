import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter/rendering.dart' show CustomPainter;

import 'badge_world.dart';
import 'support_actions.dart';
import 'support_badge_sprites.dart';
import 'support_motion.dart';

class SupportBadgeVisuals {
  SupportBadgeVisuals(
    this.badge, {
    required this.dark,
    required this.reducedMotion,
  });

  Badge badge;
  bool dark;
  bool reducedMotion;
  SupportBadgeSprites? sprites;
  MotionVector lightHalfVector = (x: 0, y: -.4, z: .92);
  double frontFlash = -1;
  double backFlash = -1;
  double fade = 1;
}

/// The visual transform and gesture hit test use the same projective plane.
class SupportBadgeProjection {
  SupportBadgeProjection(this.card, {this.perspectiveOrigin = ui.Offset.zero})
    : _basis = cardBasis(card.a, card.pitch, card.yaw),
      _slot = card.slotWorld();

  static const _perspective = 1100.0;

  final BadgeCard card;
  final ui.Offset perspectiveOrigin;
  final ({MotionVector n, MotionVector tx, MotionVector ty}) _basis;
  final (double, double) _slot;

  bool get frontFacing => _basis.n.z >= 0;
  double get _faceDepth => card.w * .01 * (frontFacing ? 1 : -1);

  // Local coordinates start at the eyelet on the card's neutral plane.
  ui.Offset _project(double x, double y, double depth) {
    final (:n, :tx, :ty) = _basis;
    final z = tx.z * x + ty.z * y + n.z * depth + 18 * card.lift;
    final w = 1 - z / _perspective;
    return perspectiveOrigin +
        ui.Offset(
          (_slot.$1 -
                  perspectiveOrigin.dx +
                  tx.x * x +
                  ty.x * y +
                  n.x * depth) /
              w,
          (_slot.$2 -
                  perspectiveOrigin.dy +
                  tx.y * x +
                  ty.y * y +
                  n.y * depth) /
              w,
        );
  }

  ui.Offset? hitLocal(ui.Offset point) {
    final (:n, :tx, :ty) = _basis;
    final depth = _faceDepth;
    final p = point - perspectiveOrigin;
    final w = 1 - (18 * card.lift + n.z * depth) / _perspective;
    final a = tx.x + p.dx * tx.z / _perspective;
    final b = ty.x + p.dx * ty.z / _perspective;
    final c = tx.y + p.dy * tx.z / _perspective;
    final d = ty.y + p.dy * ty.z / _perspective;
    final det = a * d - b * c;
    if (det.abs() < 1e-8) return null;
    final px = p.dx * w - (_slot.$1 - perspectiveOrigin.dx + n.x * depth);
    final py = p.dy * w - (_slot.$2 - perspectiveOrigin.dy + n.y * depth);
    final x = (px * d - b * py) / det;
    final y = (a * py - c * px) / det + card.slot;
    if (x.abs() > card.w / 2 || y < 0 || y > card.h) return null;
    return ui.Offset(frontFacing ? x : -x, y - card.h / 2);
  }

  void _faceTransform(ui.Canvas canvas, Float64List matrix) {
    final (:n, :tx, :ty) = _basis;
    final depth = _faceDepth;
    final sign = frontFacing ? 1 : -1;

    // Columns are the local tangents, depth axis and translated eyelet.
    matrix[0] = sign * tx.x;
    matrix[1] = sign * tx.y;
    matrix[3] = -sign * tx.z / _perspective;
    matrix[4] = ty.x;
    matrix[5] = ty.y;
    matrix[7] = -ty.z / _perspective;
    matrix[12] = _slot.$1 - perspectiveOrigin.dx + depth * n.x;
    matrix[13] = _slot.$2 - perspectiveOrigin.dy + depth * n.y;
    matrix[15] = 1 - (18 * card.lift + n.z * depth) / _perspective;
    canvas.translate(perspectiveOrigin.dx, perspectiveOrigin.dy);
    canvas.transform(matrix);
  }
}

class SupportBadgePainter extends CustomPainter {
  SupportBadgePainter({required this.visuals, required Listenable repaint})
    : super(repaint: repaint);

  final SupportBadgeVisuals visuals;
  final _matrix = Float64List(16)..[10] = 1;
  final _imagePaint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  final _sidePaint = ui.Paint();
  final _blueSide = ui.Path();
  final _greenSide = ui.Path();
  final _faceClip = ui.Path();
  ({double width, double height, double slot})? _clipGeometry;
  _StrapMesh? _mesh;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final sprites = visuals.sprites;
    if (sprites == null) return;
    final badge = visuals.badge;
    final card = badge.card;
    final projection = SupportBadgeProjection(
      card,
      perspectiveOrigin: ui.Offset(size.width / 2, size.height * .34),
    );
    final unit =
        card.w / 150; // The hardware uses the prototype's smaller unit.
    _drawShadows(canvas, projection, sprites);
    if (_mesh?.segments != badge.strap.n) _mesh = _StrapMesh(badge.strap.n);
    _mesh!.draw(
      canvas,
      badge.strap,
      visuals.dark,
      visuals.lightHalfVector,
      width: card.w * .05,
      yaw: visuals.reducedMotion ? 0 : card.yaw,
      tuckedLength: 23 * unit,
    );
    _drawSides(canvas, projection);
    _drawFace(canvas, projection, sprites);
    _drawMetal(canvas, projection, badge.strap, sprites, unit);
  }

  void _drawShadows(
    ui.Canvas canvas,
    SupportBadgeProjection projection,
    SupportBadgeSprites sprites,
  ) {
    final card = projection.card;
    final (x, y) = projection._slot;
    final squashX = math.max(math.cos(card.yaw).abs(), .06);
    final squashY = math.cos(card.pitch);
    final depth = 9 + card.lift * 16 + math.max(0, card.pitch) * 26;

    void shadow(BadgeSprite sprite, double dx, double dy, double alpha) {
      final pad = (sprite.size.width - card.w) / 2;
      canvas.save();
      canvas.translate(x + dx, y + dy);
      canvas.rotate(card.a);
      canvas.scale(squashX, squashY);
      _drawSprite(
        canvas,
        sprite,
        ui.Offset(-sprite.size.width / 2, -card.slot - pad),
        alpha,
      );
      canvas.restore();
    }

    shadow(sprites.ambient, depth * .3, depth, .9 - card.lift * .25);
    shadow(sprites.contact, 1.2, 2.6, math.max(0, .85 - card.lift * 1.2));
  }

  void _drawSides(ui.Canvas canvas, SupportBadgeProjection p) {
    final card = p.card;
    final left = -card.w / 2, right = card.w / 2;
    final top = -card.slot, bottom = card.h - card.slot;
    final depth = card.w * .01;
    final radius = card.w / 15 * .95;
    _blueSide.reset();
    _greenSide.reset();

    void edge(double x0, double y0, double x1, double y1) {
      final near0 = p._project(x0, y0, depth);
      final near1 = p._project(x1, y1, depth);
      final far0 = p._project(x0, y0, -depth);
      final far1 = p._project(x1, y1, -depth);
      final along = near1 - near0, across = far0 - near0;
      if (along.dx * across.dy - along.dy * across.dx >= 0) return;
      final mid0 = p._project(x0, y0, 0);
      final mid1 = p._project(x1, y1, 0);
      _blueSide.addPolygon([near0, near1, mid1, mid0], true);
      _greenSide.addPolygon([mid0, mid1, far1, far0], true);
    }

    edge(left + radius, top, right - radius, top);
    edge(right, top + radius, right, bottom - radius);
    edge(right - radius, bottom, left + radius, bottom);
    edge(left, bottom - radius, left, top + radius);
    canvas.drawPath(_blueSide, _sidePaint..color = SupportCode.alipay.ink);
    canvas.drawPath(_greenSide, _sidePaint..color = SupportCode.weChat.ink);
  }

  void _drawFace(
    ui.Canvas canvas,
    SupportBadgeProjection p,
    SupportBadgeSprites sprites,
  ) {
    final card = p.card;
    final topLeft = ui.Offset(-card.w / 2, -card.slot);
    final center = ui.Offset(0, card.h / 2 - card.slot);
    final front = p.frontFacing;
    final image = front ? sprites.front : sprites.back;
    final fade = visuals.fade;
    canvas.save();
    p._faceTransform(canvas, _matrix);
    if (fade < 1) {
      _drawSprite(canvas, front ? sprites.back : sprites.front, topLeft);
    }
    _drawSprite(canvas, image, topLeft, fade);

    final geometry = (width: card.w, height: card.h, slot: card.slot);
    if (_clipGeometry != geometry) {
      final unit = card.w / 15;
      _faceClip
        ..reset()
        ..fillType = ui.PathFillType.evenOdd
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            topLeft & ui.Size(card.w, card.h),
            ui.Radius.circular(.95 * unit),
          ),
        )
        ..addOval(
          ui.Rect.fromCircle(center: ui.Offset.zero, radius: .34 * unit),
        );
      _clipGeometry = geometry;
    }

    canvas.save();
    canvas.clipPath(_faceClip);
    final (:n, :tx, :ty) = p._basis;
    final half = visuals.lightHalfVector;
    final sign = front ? 1 : -1;
    final hx = _dot(half, tx) * sign;
    final hy = _dot(half, ty);
    final hn = _dot(half, n) * sign;
    final intensity = ((hn - .78) / .22).clamp(0.0, 1.0);
    final glossCenter =
        center + ui.Offset(-hx * card.w * 1.25, -(hy + .42) * card.h * .9);
    _drawCentered(
      canvas,
      sprites.gloss,
      glossCenter,
      (.16 + .62 * intensity * intensity) * (visuals.dark ? .24 : .32),
    );
    final flash = front ? visuals.frontFlash : visuals.backFlash;
    if (flash >= 0 && flash < 1) {
      final reduced = visuals.reducedMotion;
      _drawCentered(
        canvas,
        sprites.flash,
        reduced
            ? center
            : center + ui.Offset((2 * flash - 1) * 1.2 * card.w, 0),
        reduced ? 1 - (2 * flash - 1).abs() : 1 - flash,
      );
    }
    canvas.restore();
    _drawCentered(canvas, sprites.eyelet, ui.Offset.zero);
    canvas.restore();
  }

  void _drawMetal(
    ui.Canvas canvas,
    SupportBadgeProjection p,
    BadgeStrap strap,
    SupportBadgeSprites sprites,
    double unit,
  ) {
    final end = p._project(0, 0, p._faceDepth);
    final (x, y) = p._slot;
    final angle = math.atan2(
      strap.x[strap.n - 2] - x,
      y - strap.y[strap.n - 2],
    );
    canvas.save();
    canvas.translate(end.dx, end.dy);
    canvas.rotate(angle);
    _drawSprite(
      canvas,
      sprites.cap,
      ui.Offset(-sprites.cap.size.width / 2, -24.6 * unit),
    );
    canvas.scale(.35 + .65 * math.cos(p.card.yaw).abs(), 1);
    _drawSprite(
      canvas,
      sprites.ring,
      ui.Offset(-sprites.ring.size.width / 2, -14.1 * unit),
    );
    canvas.restore();
  }

  void _drawCentered(
    ui.Canvas canvas,
    BadgeSprite sprite,
    ui.Offset center, [
    double alpha = 1,
  ]) => _drawSprite(
    canvas,
    sprite,
    center - sprite.size.center(ui.Offset.zero),
    alpha,
  );

  void _drawSprite(
    ui.Canvas canvas,
    BadgeSprite sprite,
    ui.Offset origin, [
    double alpha = 1,
  ]) {
    if (alpha <= 0) return;
    final image = sprite.image;
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      origin & sprite.size,
      _imagePaint
        ..color = ui.Color.fromARGB((255 * alpha).round(), 255, 255, 255),
    );
  }

  @override
  bool shouldRepaint(covariant SupportBadgePainter oldDelegate) =>
      oldDelegate.visuals != visuals;
}

double _dot(MotionVector a, MotionVector b) =>
    a.x * b.x + a.y * b.y + a.z * b.z;

class _StrapMesh {
  _StrapMesh(this.segments)
    : _x = Float64List(segments * _subdivisions + 1),
      _y = Float64List(segments * _subdivisions + 1),
      _distance = Float64List(segments * _subdivisions + 1),
      _edgeX = Float64List(segments * _subdivisions + 1),
      _edgeY = Float64List(segments * _subdivisions + 1),
      _positions = Float32List((segments * _subdivisions + 1) * _lanes * 2),
      _colors = Int32List((segments * _subdivisions + 1) * _lanes),
      _indices = Uint16List(segments * _subdivisions * (2 * _lanes + 2) - 2) {
    var k = 0;
    for (var row = 0; row < segments * _subdivisions; row++) {
      if (row > 0) {
        _indices[k] = _indices[k - 1];
        _indices[k + 1] = row * _lanes;
        k += 2;
      }
      for (var lane = 0; lane < _lanes; lane++) {
        _indices[k++] = row * _lanes + lane;
        _indices[k++] = (row + 1) * _lanes + lane;
      }
    }
  }

  static const _subdivisions = 4;
  static const _offsets = [-1.0, -.84, -.42, -.12, .12, .42, .84, 1.0];
  static const _negativeShine = [0.0, 0.0, .2, .14, 0.0, 0.0, 0.0, 0.0];
  static const _lanes = 8;
  static const _front = 0xFFCFC2A8;
  static const _back = 0xFFB6A88C;
  static const _frontDark = 0xFFBCAF95;
  static const _backDark = 0xFFA3957A;

  final int segments;
  final Float64List _x, _y, _distance, _edgeX, _edgeY;
  final Float32List _positions;
  final Int32List _colors;
  final Uint16List _indices;
  final _fill = ui.Paint();
  final _weave = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = .7;
  final _lightRibs = ui.Path();
  final _darkRibs = ui.Path();

  void draw(
    ui.Canvas canvas,
    BadgeStrap strap,
    bool dark,
    MotionVector light, {
    required double width,
    required double yaw,
    required double tuckedLength,
  }) {
    final last = segments * _subdivisions;
    for (var segment = 0; segment < segments; segment++) {
      final i0 = math.max(0, segment - 1);
      final i2 = segment + 1;
      final i3 = math.min(segment + 2, segments);
      for (var sub = 0; sub < _subdivisions; sub++) {
        final t = sub / _subdivisions;
        final row = segment * _subdivisions + sub;
        _x[row] = _catmull(
          strap.x[i0],
          strap.x[segment],
          strap.x[i2],
          strap.x[i3],
          t,
        );
        _y[row] = _catmull(
          strap.y[i0],
          strap.y[segment],
          strap.y[i2],
          strap.y[i3],
          t,
        );
      }
    }
    _x[last] = strap.x[segments];
    _y[last] = strap.y[segments];
    for (var row = 1; row <= last; row++) {
      _distance[row] =
          _distance[row - 1] +
          _length(_x[row] - _x[row - 1], _y[row] - _y[row - 1]);
    }

    final total = _distance[last];
    final end = total - tuckedLength;
    if (end <= 0) return;
    var lastVisible = 0;
    for (var row = 0; row <= last; row++) {
      final before = math.max(0, row - 1), after = math.min(row + 1, last);
      final dx = _x[after] - _x[before], dy = _y[after] - _y[before];
      final distance = _length(dx, dy);
      final nx = distance == 0 ? -1.0 : -dy / distance;
      final ny = distance == 0 ? 0.0 : dx / distance;
      final s = math.min(_distance[row], end);
      if (_distance[row] > end) {
        final t =
            (end - _distance[before]) / (_distance[row] - _distance[before]);
        _x[row] = _lerp(_x[before], _x[row], t);
        _y[row] = _lerp(_y[before], _y[row], t);
        _distance[row] = s;
      }
      final cosine = math.cos(yaw * s / total);
      final halfWidth = width * math.max(cosine.abs(), .14);
      _edgeX[row] = nx * halfWidth;
      _edgeY[row] = ny * halfWidth;
      final shade = .62 + .38 * cosine.abs();
      final base = cosine >= 0
          ? (dark ? _frontDark : _front)
          : (dark ? _backDark : _back);
      final litSide = ((1 + nx * light.x + ny * light.y) * .5).clamp(0.0, 1.0);
      for (var lane = 0; lane < _lanes; lane++) {
        final i = row * _lanes + lane;
        final offset = _offsets[lane];
        _positions[2 * i] = _x[row] + _edgeX[row] * offset;
        _positions[2 * i + 1] = _y[row] + _edgeY[row] * offset;
        final edgeShade = offset.abs() == 1 ? shade * .84 : shade;
        final shine = _lerp(
          _negativeShine[lane],
          _negativeShine[_lanes - lane - 1],
          litSide,
        );
        _colors[i] = _strapColor(base, edgeShade, shine * cosine.abs());
      }
      lastVisible = row;
      if (s >= end) break;
    }

    final vertexCount = (lastVisible + 1) * _lanes;
    final mesh = ui.Vertices.raw(
      ui.VertexMode.triangleStrip,
      Float32List.sublistView(_positions, 0, vertexCount * 2),
      colors: Int32List.sublistView(_colors, 0, vertexCount),
      indices: Uint16List.sublistView(
        _indices,
        0,
        lastVisible * (2 * _lanes + 2) - 2,
      ),
    );
    canvas.drawVertices(mesh, ui.BlendMode.dst, _fill);
    mesh.dispose();
    _drawWeave(canvas, end, lastVisible);
  }

  void _drawWeave(ui.Canvas canvas, double end, int last) {
    _lightRibs.reset();
    _darkRibs.reset();
    var row = 0;
    var light = true;
    for (var s = .9; s < end; s += 1.8) {
      while (row < last - 1 && _distance[row + 1] <= s) {
        row++;
      }
      final span = _distance[row + 1] - _distance[row];
      final t = span == 0 ? 0.0 : (s - _distance[row]) / span;
      final x = _lerp(_x[row], _x[row + 1], t);
      final y = _lerp(_y[row], _y[row + 1], t);
      final edgeX = .9 * _lerp(_edgeX[row], _edgeX[row + 1], t);
      final edgeY = .9 * _lerp(_edgeY[row], _edgeY[row + 1], t);
      (light ? _lightRibs : _darkRibs)
        ..moveTo(x - edgeX, y - edgeY)
        ..lineTo(x + edgeX, y + edgeY);
      light = !light;
    }
    canvas.drawPath(_lightRibs, _weave..color = const ui.Color(0x1FFFFFFF));
    canvas.drawPath(_darkRibs, _weave..color = const ui.Color(0x1A3C2814));
  }

  static double _catmull(double a, double b, double c, double d, double t) =>
      b +
      .5 *
          t *
          (-a +
              c +
              t * (2 * a - 5 * b + 4 * c - d + t * (-a + 3 * b - 3 * c + d)));

  static double _length(double x, double y) => math.sqrt(x * x + y * y);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static int _strapColor(int base, double shade, double shine) {
    int channel(int shift) =>
        _lerp(((base >> shift) & 255) * shade, 255, shine).round();
    return 0xff000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
  }
}
