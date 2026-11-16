import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chh_app/widgets/level_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> render(
  WidgetTester tester,
  CustomPainter painter,
  Size size,
) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(10, 10);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    size.width.ceil() + 20,
    size.height.ceil() + 20,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}))!;

void expectClipped(Uint8List frame, Size size) {
  final width = size.width.ceil() + 20;
  for (var i = 3; i < frame.length; i += 4) {
    final x = (i ~/ 4) % width;
    final y = (i ~/ 4) ~/ width;
    if (x < 10 || x >= width - 10 || y < 10 || y >= size.height + 10) {
      expect(frame[i], 0, reason: 'no glow or particles outside plate ($x,$y)');
    }
  }
  expect(
    [
      for (var i = 3; i < frame.length; i += 4) frame[i],
    ].any((alpha) => alpha > 0),
    isTrue,
  );
}

void main() {
  testWidgets('static inner flames and light stay inside the rounded plate', (
    tester,
  ) async {
    for (final tier in ['ruby', 'fiend', 'fiendG', 'gold', 'champ']) {
      for (final dark in [false, true]) {
        const size = Size(80, 20);
        final frame = await render(
          tester,
          LevelInnerGlowPainter(tier: tier, dark: dark, scale: 1),
          size,
        );
        expectClipped(frame, size);
        expect(
          frame[((10 * 100 + 10) * 4) + 3],
          0,
          reason: 'rounded top-left corner is clipped',
        );
      }
    }
  });

  testWidgets(
    'burst is clipped while active and completely empty while waiting',
    (tester) async {
      final animation = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 2900),
      );
      final painter = LevelBurstPainter(
        animation: animation,
        scale: 1,
        sparkCount: 12,
      );
      animation.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      const size = Size(80, 20);
      expectClipped(await render(tester, painter, size), size);
      await tester.pump(const Duration(milliseconds: 2201));
      expect(animation.isAnimating, isFalse);
      final waiting = await render(tester, painter, size);
      expect([
        for (var i = 3; i < waiting.length; i += 4) waiting[i],
      ], everyElement(0));
      animation.dispose();
    },
  );
}
