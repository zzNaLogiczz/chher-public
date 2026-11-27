import 'dart:ui' as ui;

import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/voice_tokens.dart';
import 'package:chh_app/voice/fake_speech_engine.dart';
import 'package:chh_app/widgets/composer/dictation_controller.dart';
import 'package:chh_app/widgets/composer/rim_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'rim paints both corners and stops its ticker (reduced: $reduced)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        final engine = FakeSpeechEngine();
        final editor = TextEditingController();
        final controller = DictationController(
          editor: editor,
          createEngine: () => engine,
        );
        addTearDown(() {
          controller.dispose();
          editor.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: Center(
                  child: SizedBox(
                    width: RimTokens.period,
                    height: RimTokens.height,
                    child: RimGlow(controller: controller),
                  ),
                ),
              ),
            ),
          ),
        );

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.descendant(
            of: find.byType(RimGlow),
            matching: find.byType(RepaintBoundary),
          ),
        );
        Future<List<int>> sample(List<(int, int)> points) async {
          final image = boundary.toImageSync();
          final pixels = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          final result = [
            for (final (x, y) in points)
              pixels.getUint32((y * image.width + x) * 4),
          ];
          image.dispose();
          return result;
        }

        const points = [(195, 19), (2, 38), (387, 38), (195, 10), (195, 40)];
        expect(tester.binding.transientCallbackCount, 0);
        expect(await sample(points), everyElement(0));

        controller.start(pointer: const Offset(195, 110));
        await tester.pump();
        final fade = reduced ? AppMotion.reducedFade : RimTokens.fade;
        await tester.pump(fade);
        final resting = await sample(points);
        expect(resting.take(4), everyElement(isPositive));
        expect(resting.last, 0);
        expect(tester.binding.transientCallbackCount, reduced ? 0 : 1);

        await tester.pump(const Duration(milliseconds: 16));
        final next = await sample(points);
        if (reduced) {
          expect(next, resting);
        } else {
          expect(next, isNot(resting));
        }

        engine.emitVolume(.95);
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final loud = await sample(points);
        expect(loud.first & 0xff, greaterThan(resting.first & 0xff));
        expect(tester.binding.transientCallbackCount, reduced ? 0 : 1);

        controller.move(const Offset(195, 10));
        await tester.pump();
        await tester.pump(RimTokens.cutFade);
        final cut = (await sample(points)).first;
        expect(cut >> 24, greaterThan((cut >> 8) & 0xff));

        controller.move(const Offset(195, 44));
        await tester.pump();
        await tester.pump(RimTokens.cutFade);
        expect((await sample(points)).first, isNot(cut));

        controller.cancel();
        await tester.pump();
        await tester.pump(fade);
        expect(await sample(points), everyElement(0));
        expect(tester.binding.transientCallbackCount, 0);
        if (reduced) await tester.pump(VoiceTokens.plainUndo - fade);
      },
    );
  }
}
