import 'dart:ui';

import 'package:chh_app/design/composer_tokens.dart';
import 'package:chh_app/design/voice_tokens.dart';
import 'package:chh_app/widgets/composer/dictation_controller.dart';
import 'package:chh_app/widgets/composer/voice_goo_motion.dart';
import 'package:chh_app/widgets/composer/voice_liquid_motion.dart';
import 'package:chh_app/widgets/composer/voice_liquid_painter.dart';
import 'package:flutter_test/flutter_test.dart';

const _fullWidth = 374.0;
const _step = 1 / 60;

VoiceLiquidGeometry _geometry({
  double volume = .8,
  double spread = 1,
  double origin = -35,
  double time = .47,
  double width = _fullWidth,
  bool reduced = false,
  VoiceGooMotion? goo,
  List<VoiceRipple> ripples = const [
    (x: -35, time: .23, amplitude: 3.5, speed: 240),
  ],
}) => VoiceLiquidGeometry(
  frame: (
    phase: DictationPhase.hold,
    spread: spread,
    origin: origin,
    volume: volume,
    time: time,
    flow: 0,
    opacity: 1,
    labels: 1,
    pull: 0,
    detached: false,
    reduced: reduced,
  ),
  ripples: ripples,
  fullWidth: width,
  capsuleWidth: width.clamp(0, ComposerTokens.capsuleWidth),
  goo: goo,
);

void main() {
  test('the touch anchors the capsule before it grows toward the center', () {
    final first = _geometry(spread: 0);
    final middle = _geometry(spread: .5);
    final full = _geometry();
    expect(first.body.center.dx, _fullWidth / 2 - 35);
    expect(first.body.width, ComposerTokens.capsuleWidth);
    expect(middle.body.center.dx, closeTo(_fullWidth / 2 - 17.5, 1e-10));
    expect(middle.body.width, greaterThan(first.body.width));
    expect(full.body.center.dx, _fullWidth / 2);
    expect(full.body.width, _fullWidth);
    expect(_geometry(spread: 1.08).body.width, _fullWidth + 8);
  });

  test(
    'the nominal liquid height is 44–47 dp and reduced motion stays at 44',
    () {
      expect(_geometry(volume: 0).body.height, 44);
      expect(_geometry(volume: 1).body.height, 47);
      expect(_geometry(volume: 1, spread: 1.08).body.height, 47);
      final reduced = _geometry(volume: 1, reduced: true, spread: .2);
      expect(reduced.body.size, const Size(_fullWidth, 44));
      expect(reduced.displacement(_fullWidth / 2), 0);
    },
  );

  test('waves join both round ends with zero displacement and slope', () {
    final g = _geometry();
    for (final (edge, direction) in [
      (g.leftTangent, 1),
      (g.rightTangent, -1),
    ]) {
      expect(g.displacement(edge), 0);
      expect(g.displacement(edge - direction), 0);
      expect(g.displacement(edge + direction * .001), closeTo(0, 1e-6));
    }
    final outline = g.outline();
    expect(outline.computeMetrics().single.isClosed, isTrue);
    expect(outline.getBounds().left, closeTo(g.body.left, 1e-4));
    expect(outline.getBounds().right, closeTo(g.body.right, 1e-4));
    expect(outline.getBounds().bottom, closeTo(g.body.bottom, 1e-4));
  });

  test('sampled surface advances continuously above the capsule bottom', () {
    for (final width in [80.0, _fullWidth]) {
      for (final spread in [.01, .45, 1.0, 1.08]) {
        final g = _geometry(width: width, spread: spread);
        final points = g.surface(g.rightTangent, g.leftTangent);
        expect(points.first, Offset(g.rightTangent, g.body.top));
        expect(points.last, Offset(g.leftTangent, g.body.top));
        for (var i = 1; i < points.length; i++) {
          final step = points[i - 1] - points[i];
          expect(step.dx, inInclusiveRange(0, 3.2));
          expect(step.dy.abs(), lessThan(3.5));
          expect(points[i].dy, lessThan(g.body.bottom));
        }
        expect(g.outline().contains(g.body.center), isTrue);
      }
    }
  });

  test('bowed neck and waved bar share one closed outline with flat joins', () {
    final top = _geometry().body.top;
    for (final width in [240.0, _fullWidth]) {
      for (final sign in [-1, 1]) {
        final goo = VoiceGooMotion((_, _, _) {}, () => .5);
        final start = sign * (width / 2 - 70);
        for (var i = 0; i < 64; i++) {
          goo.step(
            dt: _step,
            time: i * _step,
            width: width,
            top: top,
            finger: i < 60 ? start : start + sign * 70,
            pull: 60,
            follow: true,
            detached: false,
            reduced: false,
          );
        }
        final g = _geometry(width: width, goo: goo);
        final neck = g.neck!;
        final flat = goo.flat!;
        expect(flat.x, start);
        expect((neck.right.x + neck.left.x - 2 * flat.x).sign, sign);
        for (final foot in [neck.left, neck.right]) {
          expect((foot.x - flat.x).abs() + 4, lessThanOrEqualTo(flat.radius));
          final x = g.mid + foot.x;
          expect(g.displacement(x - 4), 0);
          expect(g.displacement(x), 0);
          expect(g.displacement(x + 4), 0);
        }
        final right = g.surface(g.rightTangent, g.mid + neck.right.x);
        final left = g.surface(g.mid + neck.left.x, g.leftTangent);
        expect(right.last, g.position(neck.right));
        expect(right[right.length - 2].dy, right.last.dy);
        expect(left.first, g.position(neck.left));
        expect(left[1].dy, left.first.dy);
        final outline = g.outline();
        expect(outline.computeMetrics().single.isClosed, isTrue);
        expect(outline.contains(g.position(neck.head)), isTrue);
        expect(outline.contains(g.body.center), isTrue);
      }
    }
  });

  test('sech² ripple is centered at the touch and propagates both ways', () {
    const ripple = (x: -35.0, time: 0.0, amplitude: 3.5, speed: 240.0);
    double rippleAt(double x, double time) =>
        _geometry(time: time, ripples: [ripple]).displacement(x) -
        _geometry(time: time, ripples: []).displacement(x);
    const center = _fullWidth / 2 - 35;
    expect(rippleAt(center, 0), closeTo(7, 1e-10));
    final left = rippleAt(center - 48, .2);
    final right = rippleAt(center + 48, .2);
    expect(left, closeTo(right, 1e-10));
    expect(left, greaterThan(rippleAt(center, .2)));
  });

  test('accents follow the latest touch and maintain a 0.34 s gap', () {
    final motion = VoiceLiquidMotion(17);
    addTearDown(motion.dispose);
    void update(double volume, double? finger) => motion.update(
      phase: DictationPhase.hold,
      listening: true,
      volume: volume,
      finger: finger,
      pull: 0,
      detached: false,
    );
    update(.1, -45);
    expect(motion.ripples.single.x, -45);
    for (var frame = 0; frame < 19; frame++) {
      motion.advance(_step);
    }
    update(.93, 29);
    motion.advance(_step);
    expect(motion.ripples, hasLength(1));
    for (var frame = 0; frame < 30; frame++) {
      motion.advance(_step);
    }
    expect(motion.ripples, hasLength(3));
    expect(motion.ripples[1].x, 29);
    for (var i = 1; i < motion.ripples.length; i++) {
      expect(
        motion.ripples[i].time - motion.ripples[i - 1].time,
        greaterThanOrEqualTo(VoiceTokens.accentInterval),
      );
    }
  });
  test('hands-free ripple placement matches the prototype seeded RNG', () {
    final motion = VoiceLiquidMotion(17);
    addTearDown(motion.dispose);
    motion.update(
      phase: DictationPhase.locked,
      listening: true,
      volume: .9,
      finger: null,
      pull: 0,
      detached: false,
    );
    for (var frame = 0; frame < 30; frame++) {
      motion.advance(_step);
    }
    expect(motion.ripples, hasLength(2));
    expect(motion.ripples.last.x, closeTo(24.801041446626186, 1e-9));
  });
}
