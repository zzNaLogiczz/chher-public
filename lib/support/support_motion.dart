import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

typedef MotionVector = ({double x, double y, double z});
typedef RotationRates = ({double yaw, double pitch});
typedef MotionSample = ({
  MotionVector gravity,
  MotionVector shake,
  RotationRates rotation,
});
typedef BadgeInput = ({
  double gx,
  double gy,
  double gz,
  double shakeZ,
  RotationRates rotation,
  MotionVector lightHalfVector,
});

const standardGravity = 9.81;
const _pixelsPerMeter = 640.0;
const _shakeGain = 1.35;
const _zero = (x: 0.0, y: 0.0, z: 0.0);
const restingMotion = (
  gravity: (x: 0.0, y: standardGravity, z: 0.0),
  shake: _zero,
  rotation: (yaw: 0.0, pitch: 0.0),
);

/// The page owns the subscription and cancels it when it stops being visible
/// or resumed, or when TickerMode or the reduced-motion preference disables it.
abstract final class SupportMotion {
  static final _events = const EventChannel(
    'chh/motion',
  ).receiveBroadcastStream();

  static StreamSubscription<MotionSample> listen(
    void Function(MotionSample) onSample, {
    void Function(Object, StackTrace)? onError,
  }) {
    var sample = restingMotion;
    return _events
        .map((event) {
          final data = event as Map<Object?, Object?>;
          double read(String key) => (data[key] as num).toDouble();
          sample = filterMotion(
            previousGravity: sample.gravity,
            accelerometer: (x: read('ax'), y: read('ay'), z: read('az')),
            gyroscope: (x: read('gx'), y: read('gy'), z: read('gz')),
            displayRotation: data['rotation'] as int,
          );
          return sample;
        })
        .listen(onSample, onError: onError);
  }
}

/// Rotate the right-handed Android sensor axes to the current display.
MotionVector _rotate(MotionVector v, int displayRotation) =>
    switch (displayRotation) {
      1 => (x: v.y, y: -v.x, z: v.z),
      2 => (x: -v.x, y: -v.y, z: v.z),
      3 => (x: -v.y, y: v.x, z: v.z),
      _ => v,
    };

/// Screen coordinates are right, down and toward the viewer.
MotionVector screenGravity(MotionVector accelerometer, int displayRotation) {
  final axes = _rotate(accelerometer, displayRotation);
  return (x: -axes.x, y: axes.y, z: -axes.z);
}

MotionSample filterMotion({
  required MotionVector previousGravity,
  required MotionVector accelerometer,
  required MotionVector gyroscope,
  required int displayRotation,
}) {
  final raw = screenGravity(accelerometer, displayRotation);
  final gravity = (
    x: previousGravity.x + (raw.x - previousGravity.x) * .12,
    y: previousGravity.y + (raw.y - previousGravity.y) * .12,
    z: previousGravity.z + (raw.z - previousGravity.z) * .12,
  );
  final gyro = _rotate(gyroscope, displayRotation);
  return (
    gravity: gravity,
    shake: _difference(raw, gravity),
    rotation: (yaw: gyro.y, pitch: -gyro.x),
  );
}

BadgeInput badgeInput(MotionSample sample) {
  final (:gravity, :shake, :rotation) = sample;
  final flatFloor = .55 * standardGravity;
  final inPlane = math.sqrt(gravity.x * gravity.x + gravity.y * gravity.y);
  final weak = (1 - inPlane / flatFloor).clamp(0.0, 1.0);
  final bx = gravity.x;
  final by = gravity.y + weak * flatFloor;
  final magnitude = math.sqrt(bx * bx + by * by);
  final angle = math.atan2(bx, by);
  const maxAngle = .45;
  final exponential = math.exp(2 * .6 * angle.abs() / maxAngle);
  final soft = angle.sign * maxAngle * (exponential - 1) / (exponential + 1);

  return (
    gx: (magnitude * math.sin(soft) + shake.x * _shakeGain) * _pixelsPerMeter,
    gy: (magnitude * math.cos(soft) + shake.y * _shakeGain) * _pixelsPerMeter,
    gz: gravity.z * _pixelsPerMeter,
    shakeZ: shake.z * _pixelsPerMeter * _shakeGain,
    rotation: (yaw: _deadZone(rotation.yaw), pitch: _deadZone(rotation.pitch)),
    lightHalfVector: lightHalfVector(gravity),
  );
}

MotionVector lightHalfVector(MotionVector gravity) {
  final length = _length(gravity);
  final scale = .8 / (length == 0 ? 1 : length);
  final light = _normalized((
    x: -gravity.x * scale - .18,
    y: -gravity.y * scale,
    z: -gravity.z * scale + .6,
  ));
  return _normalized((x: light.x, y: light.y, z: light.z + 1));
}

bool shouldWakeBadge(MotionSample sample, MotionVector sleepingGravity) =>
    _length(_difference(sample.gravity, sleepingGravity)) > .25 ||
    _length(sample.shake) > .35 ||
    sample.rotation.yaw.abs() > .1 ||
    sample.rotation.pitch.abs() > .1;

double _deadZone(double value) => value.abs() < .05 ? 0 : value;

double _length(MotionVector v) => math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);

MotionVector _difference(MotionVector a, MotionVector b) =>
    (x: a.x - b.x, y: a.y - b.y, z: a.z - b.z);

MotionVector _normalized(MotionVector v) {
  final length = _length(v);
  // When the light points exactly away from the viewer, its half-vector is undefined.
  if (length == 0) return (x: 0, y: 0, z: 1);
  return (x: v.x / length, y: v.y / length, z: v.z / length);
}
