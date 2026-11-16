import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chh_app/design/image_stack_tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/widgets/image_stack_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('well fill uses relative error strictly below four percent', () {
    expect(ImageStackPhoto.fillsWell(1.5, 1.5), isTrue);
    expect(ImageStackPhoto.fillsWell(1.55, 1.5), isTrue);
    expect(ImageStackPhoto.fillsWell(1.57, 1.5), isFalse);
    expect(ImageStackPhoto.fillsWell(.7, 1.5), isFalse);
  });

  test('mount keeps twelve pixel mat and raises photo at most eight', () {
    for (final ratio in [.4, .7, 1.0, 1.8, 3.0]) {
      const well = Size(330, 280);
      final rect = ImageStackPhoto.mountedRect(well, ratio);
      expect(rect.width / rect.height, closeTo(ratio, .0001));
      expect(rect.left, greaterThanOrEqualTo(12));
      expect(rect.top, greaterThanOrEqualTo(12));
      expect(well.width - rect.right, greaterThanOrEqualTo(12));
      expect(well.height - rect.bottom, greaterThanOrEqualTo(12));
      expect(
        (well.height - rect.height) / 2 - rect.top,
        inInclusiveRange(0, 8),
      );
    }
  });

  test('white screenshots have no glow; coverage sets strength', () {
    final neutral = Uint8List.fromList([
      255,
      255,
      255,
      255,
      180,
      180,
      180,
      255,
      0,
      0,
      0,
      255,
    ]);
    expect(PhotoAtmosphere.sampleColor(neutral).strength, 0);
    final colored = Uint8List.fromList([
      255,
      255,
      255,
      255,
      180,
      180,
      180,
      255,
      220,
      30,
      40,
      255,
    ]);
    final sample = PhotoAtmosphere.sampleColor(colored);
    expect(sample.strength, closeTo(1 / 3, .0001));
    expect(sample.color, const Color(0xffdc1e28));
  });

  test(
    'dominant hue comes from the photo rather than mixing opposite colors',
    () {
      final sample = PhotoAtmosphere.sampleColor(
        Uint8List.fromList([
          220,
          30,
          40,
          255,
          220,
          30,
          40,
          255,
          20,
          220,
          60,
          255,
        ]),
      );
      expect(sample.strength, 1);
      expect(sample.color, const Color(0xffdc1e28));
    },
  );

  testWidgets('prebaked atmosphere is cached and limited to 48 pixels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xffdc1e28), BlendMode.src);
      final picture = recorder.endRecording();
      final source = await picture.toImage(300, 120);
      final first = PhotoAtmosphere.fromImage('sample-red', source);
      final same = PhotoAtmosphere.fromImage('sample-red', source);
      expect(identical(first, same), isTrue);
      source.dispose();
      picture.dispose();
      final atmosphere = await first;
      expect(atmosphere.strength, 1);
      final codec = await ui.instantiateImageCodec(atmosphere.backdropBytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 48);
      expect(frame.image.height, 19);
      frame.image.dispose();
      codec.dispose();
    });
  });

  testWidgets('long photo is top aligned with hint only while stacked', (
    tester,
  ) async {
    final image = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xffdc1e28), BlendMode.src);
      final picture = recorder.endRecording();
      final source = await picture.toImage(20, 100);
      final png = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      picture.dispose();
      return MemoryImage(png!.buffer.asUint8List());
    });
    Future<void> mount(bool expanded) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: ImageStackPhoto(
              provider: image!,
              ratio: .2,
              expanded: expanded,
            ),
          ),
        ),
      ),
    );
    await mount(false);
    expect(find.text('长图，点开看全部'), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).alignment,
      Alignment.topCenter,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    await mount(true);
    expect(find.text('长图，点开看全部'), findsNothing);
  });

  test('both theme styles use exact light and dark mist opacity', () {
    for (final tokens in [AppTokens.cinnabarLight, AppTokens.mistyLight]) {
      expect(ImageStackTokens.mist(tokens).a, closeTo(.64, .0001));
      expect(ImageStackTokens.paper(tokens), Radix.whiteA12);
    }
    for (final tokens in [AppTokens.cinnabarDark, AppTokens.mistyDark]) {
      expect(ImageStackTokens.mist(tokens).a, closeTo(.62, .0001));
      expect(ImageStackTokens.paper(tokens), tokens.surface);
    }
    expect(
      ImageStackTokens.compactPaperRadius - ImageStackTokens.compactBorder,
      ImageStackTokens.compactWellRadius,
    );
    expect(
      ImageStackTokens.paperRadius - ImageStackTokens.border,
      ImageStackTokens.wellRadius,
    );
  });
}
