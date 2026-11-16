import 'package:chh_app/widgets/shelf_scroll_physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const physics = ShelfScrollPhysics(itemExtent: 264);
  FixedScrollMetrics metrics(double offset) => FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 1000,
    pixels: offset,
    viewportDimension: 360,
    axisDirection: AxisDirection.right,
    devicePixelRatio: 1,
  );
  test('release velocity selects the adjacent tile and stops at the edge', () {
    expect(
      physics.createBallisticSimulation(metrics(100), 900)!.x(10),
      closeTo(264, .01),
    );
    expect(
      physics.createBallisticSimulation(metrics(180), -900)!.x(10),
      closeTo(0, .01),
    );
    expect(
      physics.createBallisticSimulation(metrics(900), 900)!.x(10),
      closeTo(1000, .01),
    );
    expect(physics.createBallisticSimulation(metrics(264), 0), isNull);
  });
  test(
    'reduced motion snaps inside bounds in one frame including overscroll',
    () {
      const reduced = ShelfScrollPhysics(itemExtent: 264, reducedMotion: true);
      for (final (offset, target) in [
        (-50.0, 0.0),
        (1050.0, 1000.0),
        (180.0, 264.0),
      ]) {
        final snap = reduced.createBallisticSimulation(metrics(offset), 0)!;
        expect(snap.x(0), target);
        expect(snap.isDone(1 / 120), isTrue);
        expect(snap.dx(1 / 120), 0);
      }
      expect(reduced.createBallisticSimulation(metrics(264), 0), isNull);
    },
  );

  test('rest chooses nearest tile and overscroll retains rubber banding', () {
    expect(
      physics.createBallisticSimulation(metrics(180), 0)!.x(10),
      closeTo(264, .01),
    );
    expect(
      physics.createBallisticSimulation(metrics(-30), 0)!.x(10),
      closeTo(0, .01),
    );
    expect(
      physics.applyTo(const AlwaysScrollableScrollPhysics()),
      isA<ShelfScrollPhysics>(),
    );
  });
}
