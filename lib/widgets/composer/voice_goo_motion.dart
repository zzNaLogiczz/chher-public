import 'dart:math' as math;

import '../../design/voice_goo_tokens.dart';

typedef _T = VoiceGooTokens;
typedef VoicePoint = math.Point<double>;
typedef VoiceCubic = ({
  VoicePoint control1,
  VoicePoint control2,
  VoicePoint end,
});
typedef VoiceNeck = ({
  VoicePoint left,
  VoicePoint right,
  VoiceCubic toWaistRight,
  VoiceCubic toHeadRight,
  VoiceCubic toWaistLeft,
  VoiceCubic toFootLeft,
  VoicePoint head,
  double radius,
  double squash,
  double arcStart,
  double arcSweep,
});
typedef VoicePartFrame = ({
  VoicePoint center,
  double radiusX,
  double radiusY,
  double rotation,
  double opacity,
  bool red,
});
typedef VoiceBump = ({double x, double height, double width});
typedef VoiceFlat = ({double x, double radius});
typedef VoiceRed = ({VoicePoint center, double radius});
typedef VoiceRing = ({
  VoicePoint center,
  double radius,
  double stroke,
  double opacity,
});

const _origin = VoicePoint(0, 0);
const _up = VoicePoint(0, -1);
const _tau = 2 * math.pi;

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _ease(double t) => t * t * (3 - 2 * t);
double voiceSmoothStep(double a, double b, double x) =>
    _ease(((x - a) / (b - a)).clamp(0.0, 1.0));

double voiceSechSquared(double x) {
  final c = (math.exp(x) + math.exp(-x)) / 2;
  return 1 / (c * c);
}

double voicePullDistance(double upward) {
  final up = math.max(upward, 0.0);
  return up + math.min(up, _T.pullBonusLimit) * _T.pullBonus;
}

bool voiceDetached(double pull, {required bool previous}) =>
    pull > (previous ? _T.rejoinDistance : _T.breakDistance);

// footB / neckShape 583–616. The painter splices this right-to-left section
// directly between the two halves of the baseline contour.
double voiceFootWidth(double thin, double zip) =>
    _lerp(30, 14, voiceSmoothStep(0, _T.breakDistance, thin)) *
    _lerp(.35, 1, zip);

double _footSide(double skew) =>
    1 + (_T.maxFootScale - 1) * math.max(0, skew) - .22 * math.max(0, -skew);

VoiceNeck voiceNeckShape({
  required double anchor,
  required double top,
  required VoicePoint drop,
  required double radius,
  required double distance,
  required double zip,
  double? thin,
  double skew = 0,
  double bow = 0,
}) {
  final thicknessDistance = thin ?? distance;
  final progress = voiceSmoothStep(0, _T.breakDistance, thicknessDistance);
  final squash = voiceSmoothStep(0, _T.neckMinDistance, distance);
  final base = VoicePoint(anchor, top);
  final delta = drop - base;
  final length = delta.distanceTo(_origin);
  final blend = voiceSmoothStep(4, 18, distance);
  final direction =
      (length > 0 ? delta * (1 / length) : _origin) * blend + _up * (1 - blend);
  final norm = direction.distanceTo(_origin);
  final u = norm > 0 ? direction * (1 / norm) : _up;
  final n = VoicePoint(u.y, -u.x);
  final effectiveDistance = math.max(distance, _T.neckMinDistance);
  final center = base + u * effectiveDistance;
  final angle = _lerp(72, 42, progress) * math.pi / 180;
  final cs = math.cos(angle);
  final sn = math.sin(angle);
  final foot = voiceFootWidth(thicknessDistance, zip);
  final footLeft = foot * _footSide(-skew);
  final footRight = foot * _footSide(skew);
  final waist = math.max(
    .7,
    _lerp(radius * sn * 1.12, 1.4, math.pow(progress, 1.3).toDouble()) *
        _lerp(.15, 1, zip),
  );
  final attachment = effectiveDistance - radius * cs;
  final waistHeight = math.max(
    math.max(1.6, (n.y * bow + n.y.abs() * waist + 1.6) / -u.y),
    math.min(attachment * .62, (effectiveDistance - radius) * .55 + 2),
  );
  final waistCenter = base + u * waistHeight + n * bow;
  final waistLeft = waistCenter + n * waist;
  final waistRight = waistCenter - n * waist;
  final leftRadius = (n * sn - u * cs) * radius;
  final rightRadius = (n * -sn - u * cs) * radius;
  final headLeft = center + leftRadius;
  final headRight = center + rightRadius;
  final tangentLeft = u * sn + n * cs;
  final tangentRight = u * -sn + n * cs;
  final left = VoicePoint(anchor - footLeft, top);
  final right = VoicePoint(anchor + footRight, top);
  // Keep the foot handles above the surface and the upper handles between
  // the waist and the arc. Their directions still match at every join.
  final l1 = math.min(
    left.distanceTo(waistLeft) / 2.2,
    (top - waistLeft.y) / -u.y,
  );
  final l4 = math.min(
    waistRight.distanceTo(right) / 2.2,
    (top - waistRight.y) / -u.y,
  );
  final upperLimit = math.min(
    (attachment - waistHeight) / (1 + sn),
    radius * sn / cs,
  );
  final l2 = math.min(waistLeft.distanceTo(headLeft) / 2.5, upperLimit);
  final l3 = math.min(headRight.distanceTo(waistRight) / 2.5, upperLimit);
  VoicePoint flatten(VoicePoint p) =>
      VoicePoint(p.x, top + (p.y - top) * squash);
  VoiceCubic cubic(VoicePoint a, VoicePoint b, VoicePoint end) =>
      (control1: flatten(a), control2: flatten(b), end: flatten(end));
  return (
    left: left,
    right: right,
    toWaistRight: cubic(
      right + VoicePoint(-footRight * .55, 0),
      waistRight - u * l4,
      waistRight,
    ),
    toHeadRight: cubic(
      waistRight + u * l3,
      headRight + tangentRight * l3,
      headRight,
    ),
    toWaistLeft: cubic(
      headLeft - tangentLeft * l2,
      waistLeft + u * l2,
      waistLeft,
    ),
    toFootLeft: cubic(
      waistLeft - u * l1,
      left + VoicePoint(footLeft * .55, 0),
      left,
    ),
    head: flatten(center),
    radius: radius,
    squash: squash,
    arcStart: math.atan2(rightRadius.y, rightRadius.x),
    arcSweep: 2 * angle - _tau,
  );
}

// blobR / blobPath / setMode / newBlob / stepBlob.
class VoiceBlob {
  VoiceBlob(this._center, this._velocity);

  VoicePoint _center, _velocity;
  final _modes = List.filled(_T.shapeModes.length, _origin);
  final _modeSpeeds = List.filled(_T.shapeModes.length, _origin);
  double _scale = 1, _scaleSpeed = 0;

  VoicePoint get center => _center;
  VoicePoint get centroid => _center + _modes.first;
  double get radius => _T.blobRadius;
  double get scale => _scale;

  double radiusAt(double angle) {
    var r = radius * scale;
    for (var i = 0; i < _modes.length; i++) {
      final a = angle * (i + 1);
      final mode = _modes[i];
      r += mode.x * math.cos(a) + mode.y * math.sin(a);
    }
    return r;
  }

  ({VoicePoint start, List<VoiceCubic> segments}) outline() {
    const count = _T.blobPoints;
    final samples = List.generate(count, (i) {
      final angle = i / count * _tau;
      return center +
          _polar(math.max(_T.minBlobRadius, radiusAt(angle)), angle);
    }, growable: false);
    return (
      start: samples.first,
      segments: List.generate(count, (i) {
        final p0 = samples[(i - 1) % count];
        final p1 = samples[i];
        final p2 = samples[(i + 1) % count];
        final p3 = samples[(i + 2) % count];
        return (
          control1: p1 + (p2 - p0) * (1 / 6),
          control2: p2 - (p3 - p1) * (1 / 6),
          end: p2,
        );
      }, growable: false),
    );
  }

  void _snap(double direction) {
    for (var i = 0; i < _modes.length; i++) {
      _modes[i] = _polar(
        _T.tear[i] * radius * _T.snapTear,
        (i + 1) * direction,
      );
    }
    _scale = _T.snapScale;
  }

  void _step(double dt, double time, VoicePoint target, bool reduced) {
    if (reduced) {
      _center = target;
      _velocity = _origin;
      _modes.fillRange(0, _modes.length, _origin);
      _modeSpeeds.fillRange(0, _modeSpeeds.length, _origin);
      _scale = 1;
      _scaleSpeed = 0;
      return;
    }
    const spring = _T.blobSpring;
    final a = (target - center) * spring.k - _velocity * spring.c;
    _velocity += a * dt;
    _center += _velocity * dt;
    final speed = _velocity.distanceTo(_origin);
    final acceleration = a.distanceTo(_origin);
    final pv = math.atan2(_velocity.y, _velocity.x);
    final pa = math.atan2(a.y, a.x);
    final tear = radius * (speed / 1300).clamp(0.0, .32);
    final elongation = radius * (speed / 1100).clamp(0.0, .2);
    final bulge = radius * (acceleration / 12000).clamp(0.0, .2);
    final targets = [
      _polar(-_T.tear[0] * tear, pv) + _polar(-_T.tear[0] * bulge, pa),
      _polar(_T.tear[1] * tear + elongation, 2 * pv) +
          _polar(_T.tear[1] * bulge, 2 * pa) +
          _polar(.05 * radius, -1.1 * time),
      _polar(-_T.tear[2] * tear, 3 * pv) +
          _polar(-_T.tear[2] * bulge, 3 * pa) +
          _polar(.035 * radius, 1.7 * time - 1),
    ];
    for (var i = 0; i < _modes.length; i++) {
      final spring = _T.shapeModes[i];
      _modeSpeeds[i] +=
          ((targets[i] - _modes[i]) * spring.k - _modeSpeeds[i] * spring.c) *
          dt;
      _modes[i] += _modeSpeeds[i] * dt;
    }
    const scaleSpring = _T.scaleSpring;
    _scaleSpeed +=
        (scaleSpring.k * (1 - scale) - scaleSpring.c * _scaleSpeed) * dt;
    _scale += _scaleSpeed * dt;
  }
}

VoicePoint _polar(double radius, double angle) =>
    VoicePoint(radius * math.cos(angle), radius * math.sin(angle));

class _Part {
  _Part(
    this.center,
    this.velocity,
    this.radius,
    this.life,
    this.gravity,
    this.drag,
  );
  VoicePoint center, velocity;
  final double radius, life, gravity, drag;
  double age = 0;

  VoicePartFrame get frame {
    final q = age / life;
    final speed = velocity.distanceTo(_origin);
    final r = radius * (1 - .5 * q);
    return (
      center: center,
      radiusX: r * (1 + math.min(speed / 380, .9)),
      radiusY: r * (1 - math.min(speed / 1400, .3)),
      rotation: math.atan2(velocity.y, velocity.x),
      opacity: 1 - q * q,
      red: true,
    );
  }
}

/// `stepGoo`, `stepAttached`, `anchor`, `breakDrop`, `rejoin`, `stepParts`,
/// `drawRing`, `drawRed`, `drawLabel`, `clearGoo` and `pop`.
/// Positions are relative to the full-width bar center and base top.
class VoiceGooMotion {
  VoiceGooMotion(this._ripple, this._random);

  final void Function(double x, double amplitude, double speed) _ripple;
  final double Function() _random;
  final _particles = <_Part>[];
  VoicePoint? _attached;
  VoicePoint _velocity = _origin, _direction = _up;
  VoicePoint? _label;
  VoicePoint _labelVelocity = _origin;
  VoicePoint? _redCenter, _ringCenter;
  double _redRadius = 0, _redTarget = 0, _ringStart = 0;
  double _time = 0, _width = 0, _top = 0, _cutAt = 0;
  double? _labelFadeAt;
  double _anchor = 0, _cutAnchor = 0, _distance = 0, _lift = 0, _pull = 0;
  double? _fixedAnchor;
  double _tail = 0, _tailSpeed = 0, _zip = 1, _zipSpeed = 0, _radiusBoost = 0;
  bool _retracting = false, _flying = false, _reduced = false;
  VoiceBlob? _blob;

  bool get retracting => _retracting;
  bool get busy =>
      _retracting ||
      _labelFadeAt != null ||
      _particles.isNotEmpty ||
      _ringCenter != null ||
      _redCenter != null;
  VoiceBlob? get blob => _blob;
  VoicePoint? get label => _label;
  double get cutAge => _time - _cutAt;
  double get labelOpacity {
    final fadeAt = _labelFadeAt;
    if (_label == null) return 0;
    if (_reduced) return fadeAt == null ? 1 : 0;
    final age = fadeAt == null ? cutAge : _T.labelFade - (_time - fadeAt);
    return (age / _T.labelFade).clamp(0.0, 1.0);
  }

  VoiceRed? get red {
    final center = _redCenter;
    return center == null ? null : (center: center, radius: _redRadius);
  }

  Iterable<VoicePartFrame> get parts => _particles.map((part) => part.frame);
  VoiceRing? get ring {
    final center = _ringCenter;
    if (center == null) return null;
    final q = (_time - _ringStart) / _T.ringLife;
    final ease = 1 - math.pow(1 - q, 3).toDouble();
    return (
      center: center,
      radius: _T.blobRadius * .9 + 30 * ease,
      opacity: (1 - q) * .6,
      stroke: 2.2 * (1 - q) + .4,
    );
  }

  double get _thin => _lerp(_lift, _distance, .5);

  VoiceFlat? get flat =>
      _attached == null || _distance <= _T.neckVisibleDistance
      ? null
      : (
          x: _anchor,
          radius: voiceFootWidth(_thin, _zip) * _T.maxFootScale + _T.flatMargin,
        );

  VoiceNeck? get neck {
    final attached = _attached;
    if (attached == null || _distance <= _T.neckVisibleDistance) return null;
    final q =
        ((_pull / _T.breakDistance - _T.trembleStart) / (1 - _T.trembleStart))
            .clamp(0.0, 1.0);
    final tremble = _reduced
        ? 0.0
        : q * _T.trembleAmplitude * math.sin(_time * _T.trembleFrequency);
    final n = VoicePoint(_direction.y, -_direction.x);
    final normalSpeed = _velocity.x * n.x + _velocity.y * n.y;
    final bow = _reduced
        ? 0.0
        : (-normalSpeed * .022).clamp(-10.0, 10.0) *
              voiceSmoothStep(8, 40, _distance);
    final skew = _reduced
        ? 0.0
        : (_direction.x * 1.4).clamp(-1.0, 1.0) * voiceSmoothStep(6, 40, _lift);
    final center = _contourCenter(attached);
    final radius = _radius(_distance);
    return voiceNeckShape(
      anchor: _anchor,
      top: _top,
      drop: _contourCenter(center + VoicePoint(tremble, 0)),
      // Leave room for the neck if the newly rejoined head is pulled back
      // down before its extra radius has decayed.
      radius: math.min(radius + _radiusBoost, math.max(radius, _lift * .55)),
      distance: _distance,
      zip: _zip,
      thin: _thin,
      skew: skew,
      bow: bow,
    );
  }

  VoiceBump? get _tailBump => _tail.abs() > .2
      ? (x: _cutAnchor, height: _tail, width: _T.tailWidth)
      : null;

  VoiceBump? get _approachBump {
    final blob = _blob;
    if (blob == null ||
        _flying ||
        _distance >= _T.rejoinDistance + _T.approachDistance) {
      return null;
    }
    final q = (1 - (_distance - _T.rejoinDistance) / _T.approachDistance).clamp(
      0.0,
      1.0,
    );
    return (
      x: _clampX(blob.center.x, _T.blobEdgeInset),
      height: _T.approachHeight * q * q,
      width: _T.approachWidth,
    );
  }

  double shapeSurface(double x, double wave) {
    final region = flat;
    var height = region == null
        ? wave
        : wave *
              voiceSmoothStep(
                region.radius,
                region.radius + _T.flatFade,
                (x - region.x).abs(),
              );
    if (_blob == null || _reduced) return height;
    final tail = _tailBump;
    final approach = _approachBump;
    if (tail != null) {
      height += tail.height * voiceSechSquared((x - tail.x) / tail.width);
    }
    if (approach != null) {
      height +=
          approach.height * voiceSechSquared((x - approach.x) / approach.width);
    }
    return height;
  }

  void step({
    required double dt,
    required double time,
    required double width,
    required double top,
    required double finger,
    required double pull,
    required bool follow,
    required bool detached,
    required bool reduced,
    double? fingerY,
    double? labelFloor,
  }) {
    _time = time;
    _width = width;
    _top = top;
    _pull = pull;
    _reduced = reduced;
    if (follow && !_retracting && !_flying) {
      _attached ??= _blob == null && (pull > 0 || detached)
          ? VoicePoint(finger, top + 2)
          : null;
      if (_attached != null && detached) {
        // A pointer event can cross the threshold between frames. Start the
        // snap at the break plane even if the rendered neck has not caught up.
        if (_distance < _T.breakDistance) {
          final anchor = _fixedAnchor ??= _clampX(finger, _T.anchorInset);
          final maxLead = _T.breakDistance / math.sqrt2;
          final dx = (finger - anchor).clamp(-maxLead, maxLead);
          final dy = math.sqrt(
            math.max(0.0, _T.breakDistance * _T.breakDistance - dx * dx),
          );
          _attached = VoicePoint(finger, top - dy);
          _updateAnchor(follow: false);
        }
        _breakDrop();
      } else if (_blob != null && !detached) {
        _rejoin();
      }
    }
    if (_attached != null && (follow || _retracting)) {
      _stepAttached(dt, VoicePoint(finger, top - pull));
      _updateAnchor(follow: follow && !_retracting);
      if (_retracting && _distance < _T.retractContactDistance) {
        _ripple(_anchor, 4, 230);
        clear();
      }
    }
    final blob = _blob;
    if (blob != null) {
      final target = _flying || !follow
          ? blob.center
          : VoicePoint(
              finger,
              fingerY == null ? top - pull : fingerY - _T.fingerOffset,
            );
      blob._step(dt, time, target, reduced);
      final x = _clampX(blob.center.x, _T.blobEdgeInset);
      _distance = blob.center.y < top
          ? blob.center.distanceTo(VoicePoint(x, top))
          : 0;
      const spring = _T.tailSpring;
      if (reduced) {
        _tail = _tailSpeed = 0;
      } else if (_tail != 0 || _tailSpeed != 0) {
        // Keep the prototype's undershoot visible at 60 Hz as well as 120 Hz.
        final steps = math.max(1, (dt / _T.tailStep).ceil());
        final h = dt / steps;
        for (var i = 0; i < steps; i++) {
          _tailSpeed += (-spring.k * _tail - spring.c * _tailSpeed) * h;
          _tail += _tailSpeed * h;
        }
        if (_tail.abs() < .2 && _tailSpeed.abs() < 2) _tail = _tailSpeed = 0;
      }
      _stepLabel(dt, blob, labelFloor);
    }
    _stepParticles(dt);
    final fadeAt = _labelFadeAt;
    if (fadeAt != null && time - fadeAt >= _T.labelFade) {
      _label = null;
      _labelFadeAt = null;
    }
    if (_ringCenter != null && time - _ringStart >= _T.ringLife) {
      _ringCenter = null;
    }
    if (_redCenter != null) {
      final rate = _redTarget > _redRadius ? _T.redSpeed : _T.redRetreatSpeed;
      _redRadius = reduced
          ? _redTarget
          : _lerp(_redRadius, _redTarget, 1 - math.exp(-dt * rate));
      if (_redTarget == 0 && _redRadius < 1) _redCenter = null;
    }
  }

  double _clampX(double x, double inset) {
    final room = math.max(0.0, _width / 2 - inset);
    return x.clamp(-room, room);
  }

  double _radius(double distance) =>
      (_T.neckRadiusBase + distance * _T.neckRadiusGain).clamp(
        _T.neckRadiusBase,
        _T.blobRadius,
      );

  void _updateAnchor({required bool follow}) {
    final drop = _attached!;
    _lift = math.max(0.0, _top - drop.y);
    final clamped = _clampX(drop.x, _T.anchorInset);
    if (_lift > _T.anchorLockLift) {
      _fixedAnchor ??= clamped;
    } else if (follow && _lift < _T.anchorReleaseLift) {
      _fixedAnchor = null;
    }
    _anchor = _fixedAnchor ?? clamped;
    final delta = _contourCenter(drop) - VoicePoint(_anchor, _top);
    _distance = _lift > 0 ? delta.distanceTo(_origin) : 0;
    if (_distance > 1) _direction = delta * (1 / _distance);
  }

  VoicePoint _contourCenter(VoicePoint drop) {
    // A nearly horizontal skim can fold the prototype's neck across itself.
    final lift = math.max(0.0, _top - drop.y);
    final lead = (drop.x - _anchor).clamp(-lift, lift);
    return VoicePoint(_anchor + lead, drop.y);
  }

  void _stepAttached(double dt, VoicePoint follow) {
    final target = _retracting
        ? VoicePoint(_anchor, _top + _T.retractTarget)
        : follow;
    if (_radiusBoost > 0) {
      _radiusBoost *= math.exp(-dt * _T.neckRadiusDecay);
      if (_radiusBoost < .1) _radiusBoost = 0;
    }
    if (_zip < 1) {
      const spring = _T.zipSpring;
      _zipSpeed += (spring.k * (1 - _zip) - spring.c * _zipSpeed) * dt;
      _zip = math.min(1, _zip + _zipSpeed * dt);
    }
    if (_reduced) {
      _attached = target;
      _velocity = _origin;
      _zip = 1;
      return;
    }
    final spring = _retracting ? _T.retractSpring : _T.attachedSpring;
    _velocity += ((target - _attached!) * spring.k - _velocity * spring.c) * dt;
    _attached = _attached! + _velocity * dt;
  }

  void _breakDrop() {
    _cutAt = _time;
    _labelFadeAt = null;
    _cutAnchor = _anchor;
    final blob = _blob = VoiceBlob(
      _attached!,
      _velocity + _direction * _T.snapVelocity,
    );
    _attached = null;
    _label = null;
    final pinch = VoicePoint(_anchor, _top) + _direction * (_distance * .5);
    _redCenter = pinch;
    _redTarget = _T.redRadius;
    _redRadius = _reduced ? _T.redRadius : 0;
    if (_reduced) return;
    blob._snap(math.atan2(-_direction.y, -_direction.x));
    _tail = _T.tailInitial;
    _tailSpeed = 0;
    for (var i = 0; i < _T.splashCount; i++) {
      final angle = -math.pi / 2 + (i - 2.5) * .5 + (_random() - .5) * .3;
      final speed = 80 + 80 * _random();
      _particles.add(
        _Part(
          pinch,
          _polar(speed, angle) + const VoicePoint(0, -20),
          1.3 + 1.3 * _random(),
          _T.splashLife,
          _T.splashGravity,
          0,
        ),
      );
    }
    _ripple(_anchor, 4.5, 230);
  }

  void _rejoin() {
    final blob = _blob!;
    _attached = blob.center;
    _velocity = blob._velocity;
    _blob = null;
    _fadeLabel();
    _tail = _tailSpeed = _zip = _zipSpeed = 0;
    _fixedAnchor = _clampX(blob.center.x, _T.anchorInset);
    _updateAnchor(follow: false);
    _radiusBoost = math.max(
      0,
      _T.blobRadius - (_T.neckRadiusBase + _distance * _T.neckRadiusGain),
    );
    if (_redCenter != null) {
      _redTarget = 0;
      _redCenter = VoicePoint(_anchor, _top);
    }
    if (!_reduced) _ripple(_anchor, 3.5, 220);
  }

  void _stepLabel(double dt, VoiceBlob blob, double? floor) {
    final radius = blob.radius * blob.scale;
    final x = _clampX(blob.center.x, _T.labelWidth / 2 + _T.labelEdgeInset);
    var y = blob.center.y - radius - _T.labelAbove;
    if (floor != null && y < floor) y = blob.center.y + radius + _T.labelBelow;
    final target = VoicePoint(x, y);
    final label = _label;
    if (label == null || dt == 0 || _reduced) {
      _label = target;
      _labelVelocity = _origin;
      return;
    }
    const spring = _T.labelSpring;
    _labelVelocity +=
        ((target - label) * spring.k - _labelVelocity * spring.c) * dt;
    _label = label + _labelVelocity * dt;
  }

  void _stepParticles(double dt) {
    if (_reduced) {
      _particles.clear();
      _ringCenter = null;
      return;
    }
    _particles.removeWhere((part) => (part.age += dt) >= part.life);
    for (final part in _particles) {
      part.velocity =
          part.velocity * math.exp(-part.drag * dt) +
          VoicePoint(0, part.gravity * dt);
      part.center += part.velocity * dt;
    }
  }

  bool retract() {
    if (_reduced || _attached == null || _distance <= _T.neckVisibleDistance) {
      return false;
    }
    return _retracting = true;
  }

  void holdForFly() => _flying = true;

  void _fadeLabel() {
    if (_reduced) {
      _label = null;
    } else if (_label != null) {
      _labelFadeAt = _time - (1 - labelOpacity) * _T.labelFade;
    }
  }

  void gulp() {
    final blob = _blob;
    if (blob != null) blob._scaleSpeed += _T.gulpImpulse;
  }

  void pop(double time, {required bool reduced}) {
    final blob = _blob;
    if (blob != null && !reduced) {
      for (var i = 0; i < _T.popCount; i++) {
        final angle = i / _T.popCount * _tau + _random() * .4;
        final speed = 120 + 110 * _random();
        _particles.add(
          _Part(
            blob.center + _polar(blob.radius * .8, angle),
            _polar(speed, angle) + blob._velocity * .2,
            1.8 + 2.2 * _random(),
            _T.popLife,
            _T.popGravity,
            _T.popDrag,
          ),
        );
      }
      _ringCenter = blob.center;
      _ringStart = time;
    }
    final label = _label;
    clear(keepRed: !reduced);
    if (!reduced) {
      _label = label;
      _fadeLabel();
    }
  }

  void clear({bool immediate = false, bool keepRed = false}) {
    _attached = _blob = null;
    _fixedAnchor = null;
    _label = null;
    _labelFadeAt = null;
    _retracting = _flying = false;
    _velocity = _origin;
    _direction = _up;
    _distance = _tail = _tailSpeed = _radiusBoost = _zipSpeed = 0;
    _zip = 1;
    if (!keepRed) _redTarget = 0;
    if (immediate) {
      _redCenter = _ringCenter = null;
      _redRadius = _redTarget = 0;
      _particles.clear();
    }
  }

  /// `loop` clears the red field when the bar has returned to the center.
  void dismissRed() {
    if (_blob != null) return;
    _redCenter = null;
    _redRadius = _redTarget = 0;
  }
}
