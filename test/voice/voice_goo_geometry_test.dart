import 'dart:math' as math;

import 'package:chh_app/design/voice_goo_tokens.dart';
import 'package:chh_app/widgets/composer/voice_goo_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'anchor locks above 6dp, stays through 70dp drag, releases below 2dp',
    () {
      final simulation = _Simulation(reduced: true);
      final goo = simulation.goo;
      simulation.advance(pull: 6, finger: -25);
      expect(goo.flat!.x, -25);
      simulation.advance(pull: 6.01, finger: -20);
      expect(goo.flat!.x, -20);
      simulation.advance(pull: 60, finger: 50);
      expect(goo.flat!.x, -20);
      expect(goo.neck!.head.x, closeTo(40, 1e-9));
      simulation.advance(pull: 2, finger: 50);
      expect(goo.flat!.x, -20);
      simulation.advance(pull: 1.99, finger: 50);
      expect(goo.flat!.x, 50);
      simulation.advance(pull: 3, finger: 145);
      expect(goo.flat!.x, 374 / 2 - 70);
      simulation.advance(pull: 8, finger: -145);
      expect(goo.flat!.x, -374 / 2 + 70);
    },
  );

  test('rejoin locks under the current blob, clamped 70dp from the edge', () {
    for (final finger in [75.0, 150.0]) {
      final simulation = _Simulation();
      final goo = simulation.goo;
      simulation.advance(pull: 80, frames: 90);
      simulation.advance(pull: 130, finger: finger, frames: 15);
      final center = goo.blob!.center;
      final anchor = center.x.clamp(-117.0, 117.0);
      expect(anchor, isNot(0));
      simulation.advance(pull: 78, finger: -50, dt: 0);
      expect(goo.blob, isNull);
      expect(goo.flat!.x, anchor);
      if (anchor == center.x) expect(goo.neck!.head.x, closeTo(center.x, 1e-9));
      simulation.advance(pull: 75, finger: -50, frames: 20);
      expect(goo.flat!.x, anchor);
    }
  });

  test(
    'a diagonal neck over 110dp only trembles and breaks according to pull',
    () {
      final simulation = _Simulation();
      final goo = simulation.goo;
      simulation.advance(pull: 89, frames: 90);
      simulation.advance(pull: 89, finger: 70, frames: 90);
      expect(goo.blob, isNull);
      final neck = goo.neck!;
      final base = VoicePoint(goo.flat!.x, _Simulation.top);
      expect(neck.head.distanceTo(base), greaterThan(110));
      expect(neck.head.x, closeTo(70, 1e-6));
      simulation.time = math.pi / 144;
      simulation.advance(pull: 89, finger: 70, dt: 0);
      expect(goo.neck, neck);
      simulation.advance(pull: 100, finger: 70, dt: 0);
      expect(goo.neck!.head.x, greaterThan(neck.head.x));
      simulation.advance(pull: 111, finger: 70, dt: 0);
      expect(goo.neck, isNull);
      expect(goo.blob, isNotNull);
      expect(simulation.ripples.last.$1, base.x);
    },
  );

  test(
    'attached drop follows the 420/25 spring and preserves the retract spring',
    () {
      expect(VoiceGooTokens.attachedSpring, (k: 420.0, c: 25.0));
      expect(VoiceGooTokens.retractSpring, (k: 700.0, c: 40.0));
      final simulation = _Simulation();
      const dt = 1 / 30;
      const pull = 60.0;
      var y = 2.0;
      var vy = 0.0;
      for (var i = 0; i < 5; i++) {
        vy += (420 * (-pull - y) - 25 * vy) * dt;
        y += vy * dt;
        simulation.advance(pull: pull, dt: dt);
        expect(simulation.goo.neck!.head.y, closeTo(_Simulation.top + y, 1e-9));
      }
      expect(y, lessThan(-pull));
    },
  );

  test(
    'side drag widens its foot, bows against velocity and relaxes at rest',
    () {
      final simulation = _Simulation();
      final goo = simulation.goo;
      const lift = 80.0;
      simulation.advance(pull: lift, frames: 90);
      simulation.advance(pull: lift, finger: 70, frames: 4);
      var x = 0.0, vx = 0.0;
      for (var i = 0; i < 4; i++) {
        vx += (420 * (70 - x) - 25 * vx) / 60;
        x += vx / 60;
      }
      VoiceNeck expected(double x, double vx) {
        final distance = math.sqrt(x * x + lift * lift);
        final thin = (lift + distance) / 2;
        expect(
          goo.flat!.radius,
          closeTo(voiceFootWidth(thin, 1) * 1.4 + 4, 1e-6),
        );
        return _neck(
          distance,
          direction: math.atan2(x, lift),
          thin: thin,
          skew: (x / distance * 1.4).clamp(-1, 1),
          bow: (vx * lift / distance * .022).clamp(-10, 10),
        );
      }

      final moving = goo.neck!;
      final predicted = expected(x, vx);
      expect(moving.right.x, closeTo(predicted.right.x, 1e-6));
      expect(moving.left.x, closeTo(predicted.left.x, 1e-6));
      expect(
        moving.toWaistRight.end.distanceTo(predicted.toWaistRight.end),
        lessThan(1e-6),
      );
      final straight = expected(x, 0);
      expect(moving.toWaistRight.end.x, lessThan(straight.toWaistRight.end.x));
      simulation.advance(pull: lift, finger: 70, frames: 120);
      final settled = expected(70, 0);
      expect(
        goo.neck!.toWaistRight.end.distanceTo(settled.toWaistRight.end),
        lessThan(1e-6),
      );
    },
  );

  test('reduced motion follows directly with symmetric feet and no bow', () {
    final simulation = _Simulation(reduced: true);
    simulation.advance(pull: 80, dt: 0);
    simulation.advance(pull: 80, finger: 60, dt: 0);
    final goo = simulation.goo;
    final actual = goo.neck!;
    final straight = _neck(100, direction: math.atan2(60, 80), thin: 90);
    expect(actual.head.x, closeTo(60, 1e-9));
    expect(actual.head.y, closeTo(_Simulation.top - 80, 1e-9));
    expect(actual.left.x, -actual.right.x);
    expect(
      actual.toWaistRight.end.distanceTo(straight.toWaistRight.end),
      lessThan(1e-9),
    );
    expect(
      actual.toWaistLeft.end.distanceTo(straight.toWaistLeft.end),
      lessThan(1e-9),
    );
  });

  test('optional neck parameters preserve the symmetric default shape', () {
    expect(_neck(60), _neck(60, thin: 60, bow: 0, skew: 0));
    expect(_neck(60).left.x, -voiceFootWidth(60, 1));
    expect(_neck(60).right.x, voiceFootWidth(60, 1));
  });

  test('thin drives taper while skew sets separate feet and foot handles', () {
    const distance = 80.0;
    const thin = 70.0;
    const skew = .8;
    final neck = _neck(distance, thin: thin, skew: skew);
    final foot = voiceFootWidth(thin, 1);
    final left = foot * (1 - .22 * skew);
    final right = foot * (1 + .4 * skew);
    expect(neck.left.x, closeTo(-left, 1e-9));
    expect(neck.right.x, closeTo(right, 1e-9));
    expect(neck.toWaistRight.control1.x, closeTo(right * .45, 1e-9));
    expect(neck.toFootLeft.control2.x, closeTo(-left * .45, 1e-9));
    expect(neck.head, _neck(distance).head);
    expect(neck.arcSweep, _neck(thin).arcSweep);
    final progress = voiceSmoothStep(0, 110, thin);
    final radius = neck.radius;
    final angle = (neck.arcSweep + 2 * math.pi) / 2;
    final wide = radius * math.sin(angle) * 1.12;
    final waist = wide + (1.4 - wide) * math.pow(progress, 1.3);
    final waistWidth = neck.toWaistRight.end.x - neck.toWaistLeft.end.x;
    expect(waistWidth, closeTo(waist * 2, 1e-9));
  });

  test('neck joins the flat surface with two horizontal tangents', () {
    final simulation = _Simulation();
    simulation.advance(pull: 60, finger: 145, frames: 60);
    final neck = simulation.goo.neck!;
    for (final foot in [neck.left, neck.right]) {
      expect(foot.y, _Simulation.top);
      expect(simulation.goo.shapeSurface(foot.x, 8), 0);
      expect(simulation.goo.shapeSurface(foot.x + .1, 8), 0);
    }
    expect(neck.toWaistRight.control1.y, neck.right.y);
    expect(neck.toFootLeft.control2.y, neck.left.y);
    expect(neck.toWaistRight.control1.x, lessThan(neck.right.x));
    expect(neck.toFootLeft.control2.x, greaterThan(neck.left.x));
  });

  test(
    'neck contour is simple from lift to near-break, including a rejoin',
    () {
      for (final distance in [2.0, 6.0, 13.9, 14.0, 20.0, 60.0, 100.0, 109.0]) {
        for (final direction in [-.6, 0.0, .6]) {
          for (final zip in [.0, .5, 1.0]) {
            final neck = _neck(distance, direction: direction, zip: zip);
            expect(
              _crosses(_sampleNeck(neck)),
              isFalse,
              reason: 'distance $distance, direction $direction, zip $zip',
            );
          }
        }
      }
    },
  );

  test('sideways skims leave the full surface contour simple', () {
    for (final finger in [-185.0, 185.0]) {
      final simulation = _Simulation();
      for (final pull in [1.0, 3.0, 8.0, 12.0, 16.0, 20.0]) {
        simulation.advance(pull: pull, finger: finger, frames: 40);
        final neck = simulation.goo.neck!;
        final points = [
          const VoicePoint(187, _Simulation.top),
          ..._sampleNeck(neck),
          const VoicePoint(-187, _Simulation.top),
        ];
        expect(_crosses(points), isFalse, reason: 'finger $finger, pull $pull');
      }
    }
  });

  test(
    'bowed and skewed necks stay above the surface and join tangentially',
    () {
      for (final distance in [
        1.0,
        6.0,
        12.0,
        14.0,
        18.0,
        24.0,
        32.0,
        40.0,
        75.0,
        109.0,
        150.0,
      ]) {
        for (final direction in [-math.pi / 4, -.4, 0.0, .4, math.pi / 4]) {
          final lift = distance * math.cos(direction);
          final skew = math.sin(direction) * 1.4 * voiceSmoothStep(6, 40, lift);
          final thin = (lift + distance) / 2;
          for (final zip in [0.0, .5, 1.0]) {
            for (final bend in [-10.0, 0.0, 10.0]) {
              final bow = bend * voiceSmoothStep(8, 40, distance);
              final neck = _neck(
                distance,
                direction: direction,
                zip: zip,
                thin: thin,
                skew: skew,
                bow: bow,
              );
              final reason =
                  'distance $distance, angle $direction, zip $zip, bow $bow';
              final points = _sampleNeck(neck);
              expect(
                points.every((p) => p.x.isFinite && p.y.isFinite),
                isTrue,
                reason: reason,
              );
              expect(
                points.every((p) => p.y <= _Simulation.top + 1e-9),
                isTrue,
                reason: reason,
              );
              expect(_crosses(points), isFalse, reason: reason);
              expect(neck.toWaistRight.control1.y, neck.right.y);
              expect(neck.toFootLeft.control2.y, neck.left.y);
              expect(neck.toFootLeft.end, neck.left);

              VoicePoint arcPoint(double a) =>
                  neck.head +
                  VoicePoint(
                    neck.radius * math.cos(a),
                    neck.radius * neck.squash * math.sin(a),
                  );
              VoicePoint arcTangent(double a) =>
                  VoicePoint(math.sin(a), -neck.squash * math.cos(a));
              final start = neck.arcStart;
              final end = start + neck.arcSweep;
              expect(
                neck.toHeadRight.end.distanceTo(arcPoint(start)),
                lessThan(1e-9),
              );
              _expectTangent(
                neck.toWaistRight,
                neck.toHeadRight.control1 - neck.toWaistRight.end,
              );
              _expectTangent(neck.toHeadRight, arcTangent(start));
              final outgoingArc = neck.toWaistLeft.control1 - arcPoint(end);
              expect(outgoingArc.distanceTo(VoicePoint(0, 0)), greaterThan(0));
              expect(_cosine(arcTangent(end), outgoingArc), closeTo(1, 1e-9));
              _expectTangent(
                neck.toWaistLeft,
                neck.toFootLeft.control1 - neck.toWaistLeft.end,
              );
            }
          }
        }
      }
    },
  );

  test('small pulls flatten and reopen continuously at 14dp', () {
    const top = _Simulation.top;
    final empty = _neck(0);
    expect(empty.squash, 0);
    expect(
      _sampleNeck(empty).every((point) => (point.y - top).abs() < 1e-9),
      isTrue,
    );
    final half = _neck(7);
    expect(half.squash, .5);
    expect(half.head.y, top - 7);
    final before = _sampleNeck(_neck(13.999));
    final after = _sampleNeck(_neck(14.001));
    for (var i = 0; i < before.length; i++) {
      expect(before[i].distanceTo(after[i]), lessThan(.005));
    }
  });

  test('hysteresis uses 110dp to break and returns at 78dp', () {
    expect(voicePullDistance(-12), 0);
    expect(voicePullDistance(16), 24);
    expect(voicePullDistance(98), 110);
    expect(voiceDetached(110, previous: false), isFalse);
    expect(voiceDetached(110.01, previous: false), isTrue);
    expect(voiceDetached(78.01, previous: true), isTrue);
    expect(voiceDetached(78, previous: true), isFalse);
  });

  test('snap is a closed round tail that relaxes to the breathing circle', () {
    final simulation = _Simulation();
    simulation.advance(pull: 109, frames: 60);
    simulation.advance(pull: 111, dt: 0);
    final blob = simulation.goo.blob!;
    expect(
      blob.radiusAt(math.pi / 2),
      greaterThan(blob.radiusAt(-math.pi / 2)),
    );
    expect(blob.outline().segments.length, 40);
    expect(blob.outline().segments.last.end, blob.outline().start);
    final points = [blob.outline().start];
    for (final curve in blob.outline().segments) {
      _sampleCubic(points, curve);
    }
    expect(_crosses(points), isFalse);
    simulation.advance(pull: 150, finger: 75, frames: 120);
    expect(blob.center.x, closeTo(75, .01));
    expect(blob.center.y, closeTo(_Simulation.top - 150, .01));
    expect(blob.scale, closeTo(1, .001));
    final radii = List.generate(40, (i) => blob.radiusAt(i * math.pi / 20));
    expect(radii.every((r) => (r - blob.radius).abs() < 1.8), isTrue);
    expect(radii.toSet().length, greaterThan(1));
  });

  test('surface tail rounds off and dips once after the six-bead splash', () {
    final simulation = _Simulation();
    simulation.advance(pull: 111, dt: 0);
    final goo = simulation.goo;
    expect(goo.parts.length, VoiceGooTokens.splashCount);
    expect(goo.shapeSurface(0, 0), greaterThan(15));
    expect(goo.shapeSurface(11, 0), lessThan(goo.shapeSurface(0, 0)));
    var dipped = false;
    for (var i = 0; i < 24; i++) {
      simulation.advance(pull: 150);
      dipped |= goo.shapeSurface(0, 0) < 0;
    }
    expect(dipped, isTrue);
    simulation.advance(pull: 150, frames: 12);
    expect(goo.parts, isEmpty);
    expect(goo.shapeSurface(0, 0), 0);
  });

  test(
    'rejoin narrows the red field toward the break and rebuilds the neck',
    () {
      final simulation = _Simulation();
      simulation.advance(pull: 115, frames: 30);
      final goo = simulation.goo;
      final expanded = goo.red!;
      simulation.advance(pull: 78, finger: 10, dt: 0);
      expect(goo.blob, isNull);
      final thin = goo.neck!;
      expect(thin.right.x - thin.left.x, lessThan(12));
      simulation.advance(pull: 78, finger: 10, frames: 6);
      final retreat = goo.red!;
      expect(retreat.center, (thin.left + thin.right) * .5);
      expect(retreat.radius, lessThan(expanded.radius));
      final joining = goo.neck!;
      expect(joining.right.x - joining.left.x, greaterThan(12));
      simulation.advance(pull: 78, finger: 10, frames: 90);
      expect(goo.red, isNull);
    },
  );

  test('released neck hits the bar and gives a ripple before completion', () {
    final simulation = _Simulation();
    simulation.advance(pull: 55, frames: 45);
    final goo = simulation.goo;
    expect(goo.retract(), isTrue);
    simulation.advance(pull: 0, follow: false, frames: 40);
    expect(goo.retracting, isFalse);
    expect(goo.neck, isNull);
    expect(simulation.ripples, [(0.0, 4.0, 230.0)]);
    expect(goo.busy, isFalse);
  });

  test(
    'gulp stretches the drop, then pop creates eleven beads and one ring',
    () {
      final simulation = _Simulation();
      simulation.advance(pull: 115, frames: 45);
      final goo = simulation.goo;
      goo.holdForFly();
      goo.gulp();
      simulation.advance(pull: 115, follow: false, frames: 2);
      expect(goo.blob!.scale, greaterThan(1));
      goo.pop(simulation.time, reduced: false);
      expect(goo.blob, isNull);
      expect(goo.parts.length, VoiceGooTokens.popCount);
      final ring = goo.ring!;
      simulation.advance(pull: 0, follow: false, frames: 6);
      expect(goo.ring!.radius, greaterThan(ring.radius));
      expect(goo.ring!.opacity, lessThan(ring.opacity));
      simulation.advance(pull: 0, follow: false, frames: 60);
      goo.dismissRed();
      expect(goo.ring, isNull);
      expect(goo.parts, isEmpty);
      expect(goo.busy, isFalse);
    },
  );

  test('reduced motion skips jelly modes, tremble and particles', () {
    final simulation = _Simulation(reduced: true);
    simulation.advance(pull: 109, dt: 0);
    final goo = simulation.goo;
    expect(goo.neck!.head.x, 0);
    simulation.advance(pull: 111, finger: 7, dt: 0);
    final blob = goo.blob!;
    expect(blob.center.x, 7);
    expect(blob.radiusAt(.33), blob.radius);
    expect(goo.parts, isEmpty);
    expect(goo.shapeSurface(0, 0), 0);
    expect(goo.red!.radius, VoiceGooTokens.redRadius);
    goo.pop(simulation.time, reduced: true);
    expect(goo.ring, isNull);
    expect(goo.parts, isEmpty);
  });
}

double _cosine(VoicePoint a, VoicePoint b) =>
    (a.x * b.x + a.y * b.y) / (a.magnitude * b.magnitude);

void _expectTangent(VoiceCubic curve, VoicePoint outgoing) =>
    expect(_cosine(curve.end - curve.control2, outgoing), closeTo(1, 1e-9));

VoiceNeck _neck(
  double distance, {
  double direction = 0,
  double zip = 1,
  double? thin,
  double skew = 0,
  double bow = 0,
}) => voiceNeckShape(
  anchor: 0,
  top: _Simulation.top,
  drop: VoicePoint(
    distance * math.sin(direction),
    _Simulation.top - distance * math.cos(direction),
  ),
  radius: math.min(19, 6 + distance * .13),
  distance: distance,
  zip: zip,
  thin: thin,
  skew: skew,
  bow: bow,
);

List<VoicePoint> _sampleNeck(VoiceNeck neck) {
  final points = [neck.right];
  _sampleCubic(points, neck.toWaistRight);
  _sampleCubic(points, neck.toHeadRight);
  for (var i = 1; i <= 24; i++) {
    final a = neck.arcStart + neck.arcSweep * i / 24;
    points.add(
      neck.head +
          VoicePoint(
            neck.radius * math.cos(a),
            neck.radius * neck.squash * math.sin(a),
          ),
    );
  }
  _sampleCubic(points, neck.toWaistLeft);
  _sampleCubic(points, neck.toFootLeft);
  return points;
}

void _sampleCubic(List<VoicePoint> points, VoiceCubic curve) {
  final start = points.last;
  for (var i = 1; i <= 12; i++) {
    final t = i / 12;
    final u = 1 - t;
    points.add(
      start * (u * u * u) +
          curve.control1 * (3 * u * u * t) +
          curve.control2 * (3 * u * t * t) +
          curve.end * (t * t * t),
    );
  }
}

bool _crosses(List<VoicePoint> points) {
  double side(VoicePoint a, VoicePoint b, VoicePoint c) =>
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i], b = points[i + 1];
    for (var j = i + 2; j < points.length - 1; j++) {
      final c = points[j], d = points[j + 1];
      if (side(a, b, c) * side(a, b, d) < -1e-12 &&
          side(c, d, a) * side(c, d, b) < -1e-12) {
        return true;
      }
    }
  }
  return false;
}

class _Simulation {
  _Simulation({this.reduced = false});
  static const top = -1.5;
  final bool reduced;
  final ripples = <(double, double, double)>[];
  late final goo = VoiceGooMotion(
    (x, amplitude, speed) => ripples.add((x, amplitude, speed)),
    math.Random(47).nextDouble,
  );
  double time = 0;
  bool detached = false;

  void advance({
    required double pull,
    double finger = 0,
    bool follow = true,
    double dt = 1 / 60,
    int frames = 1,
  }) {
    detached = voiceDetached(pull, previous: detached);
    for (var i = 0; i < frames; i++) {
      time += dt;
      goo.step(
        dt: dt,
        time: time,
        width: 374,
        top: top,
        finger: finger,
        pull: pull,
        follow: follow,
        detached: detached,
        reduced: reduced,
      );
    }
  }
}
