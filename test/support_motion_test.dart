import 'dart:math' as math;

import 'package:chh_app/support/support_motion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('remaps accelerometer and gyroscope for every display rotation', () {
    const readings = (x: 2.0, y: 3.0, z: 4.0);
    const gravities = [
      (x: -2.0, y: 3.0, z: -4.0),
      (x: -3.0, y: -2.0, z: -4.0),
      (x: 2.0, y: -3.0, z: -4.0),
      (x: 3.0, y: 2.0, z: -4.0),
    ];
    const rotations = [
      (yaw: 3.0, pitch: -2.0),
      (yaw: -2.0, pitch: -3.0),
      (yaw: -3.0, pitch: 2.0),
      (yaw: 2.0, pitch: 3.0),
    ];
    for (var rotation = 0; rotation < 4; rotation++) {
      expect(screenGravity(readings, rotation), gravities[rotation]);
      final sample = filterMotion(
        previousGravity: gravities[rotation],
        accelerometer: readings,
        gyroscope: readings,
        displayRotation: rotation,
      );
      expect(sample.rotation, rotations[rotation]);
    }
  });

  test('low-pass and shake are complementary with a factor of .12', () {
    final sample = filterMotion(
      previousGravity: (x: 0, y: 10, z: 0),
      accelerometer: (x: -5, y: 5, z: -10),
      gyroscope: (x: 0, y: 0, z: 0),
      displayRotation: 0,
    );
    expect(sample.gravity, (x: .6, y: 9.4, z: 1.2));
    expect(sample.shake.x, closeTo(4.4, 1e-12));
    expect(sample.shake.y, closeTo(-4.4, 1e-12));
    expect(sample.shake.z, closeTo(8.8, 1e-12));
  });

  test('flat gravity keeps a .55 g floor and shake applies to all axes', () {
    final flat = _sample(gravity: (x: 0, y: 0, z: -standardGravity));
    final input = badgeInput(flat);
    expect(input.gx, 0);
    expect(input.gy, closeTo(.55 * standardGravity * 640, 1e-9));
    expect(input.gz, -standardGravity * 640);
    expect(input.shakeZ, 0);
    final shaken = badgeInput((
      gravity: flat.gravity,
      shake: (x: 1, y: -2, z: 3),
      rotation: flat.rotation,
    ));
    expect(shaken.gx, closeTo(1.35 * 640, 1e-9));
    expect(shaken.gy - input.gy, closeTo(-2 * 1.35 * 640, 1e-9));
    expect(shaken.gz, input.gz);
    expect(shaken.shakeZ, closeTo(3 * 1.35 * 640, 1e-9));
  });

  test('soft tilt preserves magnitude, eases at .6, and caps at .45 rad', () {
    for (final angle in [.001, math.pi / 3, -math.pi / 3, math.pi]) {
      final input = badgeInput(
        _sample(
          gravity: (
            x: standardGravity * math.sin(angle),
            y: standardGravity * math.cos(angle),
            z: 0,
          ),
        ),
      );
      final soft = math.atan2(input.gx, input.gy);
      expect(soft.abs(), lessThan(.45));
      expect(soft.sign, angle.sign);
      expect(
        math.sqrt(input.gx * input.gx + input.gy * input.gy),
        closeTo(standardGravity * 640, 1e-9),
      );
      if (angle == .001) expect(soft / angle, closeTo(.6, 1e-6));
      if (angle == math.pi / 3) expect(soft, closeTo(.398043583, 1e-7));
    }
  });

  test('gyro dead zone is strict and wake checks use raw rotation rates', () {
    expect(badgeInput(_sample(rotation: (yaw: -.049, pitch: .05))).rotation, (
      yaw: 0.0,
      pitch: .05,
    ));
    const origin = (x: 0.0, y: 0.0, z: 0.0);
    expect(
      shouldWakeBadge(
        _sample(
          gravity: (x: .25, y: 0, z: 0),
          shake: (x: 0, y: 0, z: .35),
          rotation: (yaw: -.1, pitch: .1),
        ),
        origin,
      ),
      isFalse,
    );
    for (final sample in [
      _sample(gravity: (x: .2, y: .2, z: 0)),
      _sample(shake: (x: .25, y: -.25, z: 0)),
      _sample(rotation: (yaw: -.101, pitch: 0)),
      _sample(rotation: (yaw: 0, pitch: .101)),
    ]) {
      expect(shouldWakeBadge(sample, origin), isTrue);
    }
  });

  test(
    'light half vector follows the reference world-up and forward blend',
    () {
      final upright = lightHalfVector(restingMotion.gravity);
      expect(upright.x, closeTo(-.099326540, 1e-7));
      expect(upright.y, closeTo(-.441451290, 1e-7));
      expect(upright.z, closeTo(.891770709, 1e-7));
      final flat = lightHalfVector((x: 0, y: 0, z: -standardGravity));
      expect(flat.y, 0);
      expect(flat.z, greaterThan(upright.z));
    },
  );

  test(
    'listening and cancelling attach and detach the native stream',
    () async {
      const channel = MethodChannel('chh/motion');
      const codec = StandardMethodCodec();
      final messenger = binding.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final samples = <MotionSample>[];
      final subscription = SupportMotion.listen(samples.add);
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeSuccessEnvelope({
          'ax': 0.0,
          'ay': 9.81,
          'az': 0.0,
          'gx': 0.0,
          'gy': 0.0,
          'gz': 0.0,
          'rotation': 0,
        }),
        null,
      );
      expect(samples, [restingMotion]);
      await subscription.cancel();
      expect(calls, ['listen', 'cancel']);
    },
  );
}

MotionSample _sample({
  MotionVector gravity = (x: 0, y: 0, z: 0),
  MotionVector shake = (x: 0, y: 0, z: 0),
  RotationRates rotation = (yaw: 0, pitch: 0),
}) => (gravity: gravity, shake: shake, rotation: rotation);
