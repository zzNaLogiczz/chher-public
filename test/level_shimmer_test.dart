import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chh_app/widgets/level_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> pixels(
  WidgetTester tester,
  Size size,
  void Function(Canvas canvas) paint,
) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}))!;

void main() {
  testWidgets('shimmer translates a translucent band only inside text glyphs', (
    tester,
  ) async {
    const style = TextStyle(
      fontFamily: 'Ahem',
      fontSize: 40,
      height: 1,
      color: Colors.white,
    );
    final text = TextPainter(
      text: const TextSpan(text: 'A A', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final size = text.size;
    final mask = await pixels(
      tester,
      size,
      (canvas) => text.paint(canvas, Offset.zero),
    );
    text.dispose();
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 2900),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: LevelShimmer(
              text: 'A A',
              style: style,
              size: size,
              animation: animation,
              sweep: const Duration(milliseconds: 1300),
            ),
          ),
        ),
      ),
    );
    final painter = tester
        .widget<CustomPaint>(find.byType(CustomPaint))
        .painter!;
    animation.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 325));
    final first = await pixels(
      tester,
      size,
      (canvas) => painter.paint(canvas, size),
    );
    await tester.pump(const Duration(milliseconds: 650));
    final last = await pixels(
      tester,
      size,
      (canvas) => painter.paint(canvas, size),
    );

    double centroid(Uint8List frame) {
      var alphaSum = 0;
      var weighted = 0;
      var translucent = 0;
      final width = size.width.ceil();
      for (var i = 0; i < frame.length; i += 4) {
        final alpha = frame[i + 3];
        final maskAlpha = mask[i + 3];
        expect(
          alpha,
          lessThanOrEqualTo(maskAlpha + 1),
          reason: 'highlight must preserve the text mask alpha',
        );
        if (maskAlpha == 0) {
          expect(
            alpha,
            0,
            reason: 'spaces and pixels outside glyphs stay transparent',
          );
        }
        alphaSum += alpha;
        weighted += ((i ~/ 4) % width) * alpha;
        if (alpha > 0 && alpha < 255) translucent++;
      }
      expect(
        alphaSum,
        greaterThan(0),
        reason: 'drawVertices must paint visible highlight',
      );
      expect(
        translucent,
        greaterThan(0),
        reason: 'band edges must have partial alpha',
      );
      return weighted / alphaSum;
    }

    expect(centroid(first), lessThan(size.width / 3));
    expect(centroid(last), greaterThan(size.width * 2 / 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      animation.isAnimating,
      isTrue,
      reason: 'burst can continue after text sweep',
    );
    final stopped = await pixels(
      tester,
      size,
      (canvas) => painter.paint(canvas, size),
    );
    expect([
      for (var i = 3; i < stopped.length; i += 4) stopped[i],
    ], everyElement(0));
    await tester.pump(const Duration(milliseconds: 1526));
    expect(animation.isAnimating, isFalse);
    final waiting = await pixels(
      tester,
      size,
      (canvas) => painter.paint(canvas, size),
    );
    expect([
      for (var i = 3; i < waiting.length; i += 4) waiting[i],
    ], everyElement(0));
    await tester.pumpWidget(const SizedBox());
    animation.dispose();
    expect(tester.takeException(), isNull);
  });
}
