import 'dart:io';
import 'dart:math' as math;

import 'package:chh_app/support/badge_world.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 390.0, _height = 844.0;
const _cardWidth = 150.0, _cardHeight = 212.0, _slot = 12.0;
const _dt = 1 / 120;

BadgeWorld _makeWorld() {
  final w = BadgeWorld();
  const gap = 28;
  const ax1 = _width / 2 - (_cardWidth + gap) / 2;
  const ax2 = _width / 2 + (_cardWidth + gap) / 2;
  w.addBadge('wechat', ax1, -40, 195, _cardWidth, _cardHeight, _slot);
  w.addBadge('alipay', ax2, -40, 221, _cardWidth, _cardHeight, _slot);
  w.setWalls(6, _width - 6, 52, _height - 8);
  w.setGravity(0, w.g, 0, 0);
  return w;
}

String _fmt(num v) => v.abs() < 1e-3 ? '0' : v.toStringAsFixed(2);
double _hypot(double x, double y) => math.sqrt(x * x + y * y);
double _stretchPercent(double stretch) => stretch * 100 - 100;

bool _finite(BadgeWorld w) {
  for (final b in w.badges) {
    final c = b.card;
    if ([
      c.x,
      c.y,
      c.a,
      c.vx,
      c.vy,
      c.va,
      c.yaw,
      c.pitch,
    ].any((v) => !v.isFinite)) {
      return false;
    }
    for (var i = 0; i <= b.strap.n; i++) {
      if (!b.strap.x[i].isFinite || !b.strap.y[i].isFinite) return false;
    }
  }
  return true;
}

double _stretch(Badge b) {
  final (sx, sy) = b.card.slotWorld();
  return _hypot(sx - b.strap.ax, sy - b.strap.ay) / b.strap.length;
}

double _strapGap(Badge b) {
  final (sx, sy) = b.card.slotWorld();
  final st = b.strap;
  return _hypot(sx - st.x[st.n], sy - st.y[st.n]);
}

double _overlap(BadgeWorld w) {
  final a = w.badges[0].card, b = w.badges[1].card;
  return a.w - (b.x - a.x).abs();
}

double _maxValue(Iterable<double> values) => values.reduce(math.max);

void main() {
  // The scenarios and thresholds match the prototype's physics-test.cjs.
  test('rest position holds for five seconds', () {
    final w = _makeWorld();
    final y0 = w.badges.map((b) => b.card.y).toList();
    for (var t = 0.0; t < 5; t += _dt) {
      w.step(_dt);
    }
    final drift = _maxValue([
      for (var i = 0; i < w.badges.length; i++)
        (w.badges[i].card.y - y0[i]).abs(),
    ]);
    stdout.writeln(
      'Rest drift ${_fmt(drift)} px, speed ${_fmt(w.speed())} px/s, calm ${_fmt(w.calmFor)} s',
    );
    expect(_finite(w), isTrue);
    expect(drift, lessThan(1.5));
  });

  test('swing period, decay and eventual ticker stop', () {
    final w = _makeWorld();
    final b = w.badges[0];
    w.badges.removeAt(1);
    b.card.vx = 700;
    for (var i = 1; i <= b.strap.n; i++) {
      b.strap.vx[i] = 700 * (i / b.strap.n);
    }
    var previous = b.card.x - b.strap.ax, maxAmplitude = 0.0;
    final crossings = <double>[], amplitudes = <double>[];
    for (var t = 0.0; t < 12; t += _dt) {
      w.step(_dt);
      final x = b.card.x - b.strap.ax;
      maxAmplitude = math.max(maxAmplitude, x.abs());
      if (previous < 0 && x >= 0) {
        crossings.add(t);
        amplitudes.add(maxAmplitude);
        maxAmplitude = 0;
      }
      previous = x;
    }
    final periods = [
      for (var i = 1; i < crossings.length; i++)
        crossings[i] - crossings[i - 1],
    ];
    final period = periods.fold(0.0, (a, b) => a + b) / periods.length;
    stdout.writeln(
      'Swing period ${_fmt(period)} s, amplitudes ${amplitudes.map(_fmt).join(' / ')} px',
    );
    expect(period, allOf(greaterThan(1.1), lessThan(1.7)));
    var calmAt = double.infinity;
    for (var t = 0.0; t < 20; t += _dt) {
      w.step(_dt);
      if (w.calmFor > 2) {
        calmAt = t;
        break;
      }
    }
    stdout.writeln('Swing calm after another ${_fmt(calmAt)} s');
    expect(calmAt, lessThan(20));
  });

  test('two badges drop, reveal the back and settle without stretching', () {
    final w = _makeWorld();
    final a = w.badges[0], b = w.badges[1];
    double above(Badge b) =>
        (-10 - (b.card.h - b.card.slot) - b.strap.ay) / b.strap.length;
    w.placeForDrop(a, -14, above(a), 0, 0);
    w.placeForDrop(b, 16, above(b), 0.12, 22);
    var stretch = 0.0, gap = 0.0, yaw = 0.0, calmAt = double.infinity;
    for (var t = 0.0; t < 14; t += _dt) {
      w.step(_dt);
      stretch = math.max(stretch, _maxValue(w.badges.map(_stretch)));
      gap = math.max(gap, _maxValue(w.badges.map(_strapGap)));
      yaw = math.max(yaw, b.card.yaw.abs());
      if (w.calmFor > 2 && calmAt.isInfinite) calmAt = t;
    }
    stdout.writeln(
      'Two-badge drop stretch ${_fmt(_stretchPercent(stretch))}%, gap ${_fmt(gap)} px, yaw ${_fmt(yaw)} rad, calm at ${_fmt(calmAt)} s',
    );
    expect(stretch, lessThan(1.012));
    expect(yaw, allOf(greaterThan(1.66), lessThan(2.8)));
    expect(calmAt, lessThan(14));
    expect(_finite(w), isTrue);
  });

  test('single double-sided badge rebounds, reveals the back and settles', () {
    final w = BadgeWorld();
    const cw = 218.0, ch = 308.0, slot = 17.4;
    final b = w.addBadge('pass', _width / 2, -40, 330, cw, ch, slot);
    w.setWalls(6, _width - 6, 52, _height - 8);
    w.setGravity(0, w.g, 0, 0);
    const above = (-10 - (ch - slot) + 40) / 330;
    w.placeForDrop(b, 18, above, 0, 27);
    var stretch = 0.0, yaw = 0.0, backTime = 0.0, minVy = 0.0;
    var calmAt = double.infinity;
    for (var t = 0.0; t < 14; t += _dt) {
      w.step(_dt);
      stretch = math.max(stretch, _stretch(b));
      yaw = math.max(yaw, b.card.yaw.abs());
      if (b.card.yaw.abs() > math.pi / 2) backTime += _dt;
      minVy = math.min(minVy, b.card.vy);
      if (w.calmFor > 2 && calmAt.isInfinite) calmAt = t;
    }
    stdout.writeln(
      'Single drop rebound ${_fmt(-minVy)} px/s, stretch ${_fmt(_stretchPercent(stretch))}%, yaw ${_fmt(yaw)} rad, back ${_fmt(backTime)} s, calm at ${_fmt(calmAt)} s',
    );
    expect(minVy, lessThan(-150));
    expect(backTime, allOf(greaterThan(0.2), lessThan(0.9)));
    expect(calmAt, lessThan(12));
    expect(_finite(w), isTrue);
  });

  test('hard shaking keeps badges and straps constrained', () {
    final w = _makeWorld();
    var seed = 7;
    double rnd() {
      seed = (seed * 16807) % 2147483647;
      return (seed / 2147483647) * 2 - 1;
    }

    var stretch = 0.0, overlap = -1e9, events = 0, maxWall = 0.0;
    for (var t = 0.0; t < 20; t += _dt) {
      final shake = math.sin(t * 38) * 14 + rnd() * 4;
      final tilt = math.sin(t * 0.7) * 0.9;
      const g = 9.81, s = 640.0;
      w.setGravity(
        (math.sin(tilt) * g + shake) * s,
        (math.cos(tilt) * g + rnd() * 3) * s,
        -3 * s,
        rnd() * 3 * s,
      );
      w.setRotationRates(rnd() * 2, rnd());
      w.step(_dt);
      stretch = math.max(stretch, _maxValue(w.badges.map(_stretch)));
      overlap = math.max(overlap, _overlap(w));
      events += w.takeEvents().length;
      for (final b in w.badges) {
        for (final (x, _) in w.corners(b.card, 4)) {
          maxWall = math.max(maxWall, math.max(6 - x, x - (_width - 6)));
        }
      }
    }
    stdout.writeln(
      'Shake stretch ${_fmt(_stretchPercent(stretch))}%, overlap ${_fmt(overlap)} px, wall penetration ${_fmt(maxWall)} px, events $events',
    );
    expect(_finite(w), isTrue);
    expect(stretch, lessThan(1.03));
    expect(overlap, lessThan(40));
    expect(maxWall, lessThan(6));
  });

  test('60 degree tilt stabilizes', () {
    final w = _makeWorld();
    const s = 640, g = 9.81, tilt = 60 * math.pi / 180;
    w.setGravity(math.sin(tilt) * g * s, math.cos(tilt) * g * s, 0, 0);
    for (var t = 0.0; t < 10; t += _dt) {
      w.step(_dt);
    }
    final angles = w.badges.map((b) => b.card.a * 180 / math.pi);
    stdout.writeln(
      'Tilt angles ${angles.map(_fmt).join(' / ')} degrees, speed ${_fmt(w.speed())} px/s',
    );
    expect(_finite(w), isTrue);
    expect(w.speed(), lessThan(30));
  });

  test('inverted badges stay below the ceiling', () {
    final w = _makeWorld();
    w.setGravity(0, -9.81 * 640, 0, 0);
    var minTop = double.infinity;
    for (var t = 0.0; t < 6; t += _dt) {
      w.step(_dt);
      for (final b in w.badges) {
        for (final (_, y) in w.corners(b.card, 4)) {
          minTop = math.min(minTop, y);
        }
      }
    }
    stdout.writeln('Inverted highest corner y=${_fmt(minTop)} px');
    expect(_finite(w), isTrue);
    expect(minTop, greaterThan(52 - 6));
  });

  test('grab enforces strap length and release retains reasonable speed', () {
    final w = _makeWorld();
    final a = w.badges[0];
    final (gx, gy) = a.card.toWorld(0, 40);
    w.startGrab('wechat', gx, gy);
    var stretch = 0.0;
    for (var t = 0.0; t < 1.5; t += _dt) {
      w.moveGrab(gx + t * 240, gy + t * 260);
      w.step(_dt);
      stretch = math.max(stretch, _stretch(a));
    }
    w.endGrab();
    var maxV = 0.0;
    for (var t = 0.0; t < 2; t += _dt) {
      w.step(_dt);
      maxV = math.max(maxV, _hypot(a.card.vx, a.card.vy));
    }
    stdout.writeln(
      'Grab stretch ${_fmt(_stretchPercent(stretch))}%, release peak ${_fmt(maxV)} px/s',
    );
    expect(stretch, lessThan(1.015));
    expect(maxV, allOf(greaterThan(150), lessThan(2500)));
    expect(_finite(w), isTrue);
  });

  test('flips settle promptly without overshoot and return to the front', () {
    final w = _makeWorld();
    final b = w.badges[1];
    w.flip('alipay', 1);
    var settle = double.infinity, overshoot = 0.0;
    for (var t = 0.0; t < 8; t += _dt) {
      w.step(_dt);
      overshoot = math.max(overshoot, b.card.yaw - math.pi);
      if (settle.isInfinite &&
          (b.card.yaw - math.pi).abs() < 0.03 &&
          b.card.yawRate.abs() < 0.1) {
        settle = t;
      }
    }
    w.flip('alipay');
    for (var t = 0.0; t < 8; t += _dt) {
      w.step(_dt);
    }
    stdout.writeln(
      'Flip settle ${_fmt(settle)} s, overshoot ${_fmt(overshoot * 180 / math.pi)} degrees, return yaw ${_fmt(b.card.yaw)} rad',
    );
    expect(settle, lessThan(1.5));
    expect(overshoot, lessThan(0.44));
    expect(b.card.yaw.abs(), lessThan(0.05));
  });

  test('60-second simulation stays under the prototype performance budget', () {
    final w = _makeWorld();
    final clock = Stopwatch()..start();
    var steps = 0;
    for (var t = 0.0; t < 60; t += _dt) {
      steps += w.step(_dt);
    }
    clock.stop();
    final ms = clock.elapsedMicroseconds / 1000;
    stdout.writeln(
      '60-second simulation ${ms.toStringAsFixed(1)} ms, $steps substeps, ${(clock.elapsedMicroseconds / 60 / 120).toStringAsFixed(1)} µs/frame',
    );
    expect(ms, lessThan(400));
  });
}
