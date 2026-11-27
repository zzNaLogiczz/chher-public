import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/voice/fake_speech_engine.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/widgets/composer/composer_editor.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/widgets/composer/dictation_controller.dart';
import 'package:chh_app/widgets/composer/smiley_editing_controller.dart';
import 'package:chh_app/widgets/composer/voice_bar.dart';
import 'package:chh_app/widgets/composer/voice_liquid_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = ValueKey('voice-frame');
const _step = Duration(microseconds: 16667);
const _screen = Size(390, 320);
const _utterance = '周末去看那台机器';

final _dumpFolder = Platform.environment['CHH_FRAME_DUMP'];
final _phase3DumpFolder = Platform.environment['CHH_PHASE3_FRAME_DUMP'];
final _phase4DumpFolder = Platform.environment['CHH_PHASE4_FRAME_DUMP'];
bool _fontsLoaded = false;

Future<void> _loadCaptureFonts() async {
  if (_fontsLoaded) return;
  final font = [
    if (Platform.environment['CHH_CAPTURE_CJK_FONT'] case final String path)
      path,
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ].map(File.new).where((file) => file.existsSync()).firstOrNull;
  if (font != null) {
    final data = ByteData.sublistView(await font.readAsBytes());
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
  }
  await (FontLoader('packages/solar_icons/SolarIcons')
        ..addFont(rootBundle.load('packages/solar_icons/fonts/SolarIcons.ttf')))
      .load();
  _fontsLoaded = true;
}

void main() {
  for (final appearance in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      final themeName = '${appearance.name}-${brightness.name}';
      testWidgets('liquid frames paint in $themeName', (tester) async {
        final capturePhase3 =
            appearance == AppearanceStyle.misty &&
            brightness == Brightness.light;
        final capturePhase4 =
            appearance == AppearanceStyle.misty &&
            (_phase4DumpFolder?.isNotEmpty ?? false);
        if ((_dumpFolder?.isNotEmpty ?? false) ||
            (capturePhase3 && (_phase3DumpFolder?.isNotEmpty ?? false)) ||
            capturePhase4) {
          await tester.runAsync(_loadCaptureFonts);
        }
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = _screen * 3;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        late FakeSpeechEngine engine;
        final editor = SmileyEditingController();
        final focus = FocusNode();
        final controller = DictationController(
          editor: editor,
          createEngine: () => engine = FakeSpeechEngine(),
          clock: capturePhase4 ? _CaptureClock(tester) : null,
        );
        addTearDown(() {
          controller.dispose();
          editor.dispose();
          focus.dispose();
        });
        // The navigator overlays share a capture boundary with the editor and
        // strip so the top of the drop and the flying text stay in the image.
        await tester.pumpWidget(
          RepaintBoundary(
            key: _capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(brightness, appearance),
              home: Scaffold(
                backgroundColor: tokensFor(brightness, appearance).surface,
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (_, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VoiceStatus(controller: controller, chat: true),
                          ComposerEditor(
                            controller: editor,
                            dictation: controller,
                            focusNode: focus,
                            chat: true,
                            readOnly: controller.active,
                            hintText: '写私信',
                          ),
                          ComposerToolStrip(
                            voice: VoiceBar(controller: controller),
                            voiceActive: controller.barExpanded,
                            send: const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final voice = find.byType(VoiceBar);
        final painter = find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is VoiceLiquidPainter,
        );

        VoiceLiquidPainter liquidPainter() =>
            tester.widget<CustomPaint>(painter).painter! as VoiceLiquidPainter;

        Future<void> advance(int frames) async {
          for (var i = 0; i < frames; i++) {
            await tester.pump(_step);
          }
        }

        Future<void> capture(
          String stage, {
          Rect? crop,
          int scale = 3,
          bool liquid = true,
          bool checkPixels = false,
          String? phase,
        }) async {
          expect(painter, liquid ? findsOneWidget : findsNothing);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_capture),
          );
          expect(boundary.debugNeedsPaint, isFalse);
          final folder = switch (phase) {
            'phase3' => _phase3DumpFolder,
            'phase4' => _phase4DumpFolder,
            _ => _dumpFolder,
          };
          final shouldWrite = folder != null && folder.isNotEmpty;
          if (!shouldWrite && !checkPixels) return;
          final bounds = crop ?? Offset.zero & _screen;
          final center = tester.getCenter(voice) - bounds.topLeft;
          await tester.runAsync(() async {
            final image = await (boundary.debugLayer! as OffsetLayer).toImage(
              bounds,
              pixelRatio: scale.toDouble(),
            );
            try {
              expect(
                (image.width, image.height),
                ((bounds.width * scale).ceil(), (bounds.height * scale).ceil()),
              );
              if (checkPixels) {
                final raw = await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                );
                expect(raw, isNotNull);
                int pixel(int x, int y) =>
                    raw!.getUint32((y * image.width + x) * 4);
                expect(
                  pixel(
                    (center.dx * scale).round(),
                    (center.dy * scale).round(),
                  ),
                  isNot(pixel(5, 5)),
                );
              }
              if (shouldWrite) {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final output = Directory(folder)..createSync(recursive: true);
                final filename = switch (phase) {
                  'phase3' => 'phase3-$stage',
                  'phase4' => 'phase4-$stage-${brightness.name}',
                  _ => '$themeName-$stage',
                };
                File(
                  '${output.path}/$filename.png',
                ).writeAsBytesSync(png!.buffer.asUint8List());
              }
            } finally {
              image.dispose();
            }
          });
        }

        final origin = tester.getCenter(voice) - const Offset(31, 0);
        var press = await tester.startGesture(origin);

        // Inverse of the gesture conversion p + min(p, 24) / 2.
        Future<void> pull(
          double distance, {
          double dx = 0,
          int frames = 20,
        }) async {
          final up = distance <= 36 ? distance / 1.5 : distance - 12;
          await press.moveTo(origin + Offset(dx, -up));
          await advance(frames);
          expect(controller.value.pull, closeTo(distance, .001));
        }

        final stripCrop = Rect.fromLTWH(
          0,
          _screen.height - 72,
          _screen.width,
          72,
        );
        await tester.pump();
        await advance(5);
        await capture('01-press', crop: stripCrop, checkPixels: true);
        // Move horizontally to enter hold without activating the water drop.
        await press.moveBy(const Offset(11, 0));
        await tester.pump();
        expect(controller.value.phase, DictationPhase.hold);
        engine.emitVolume(.16);
        await advance(26);
        await capture('02-low', crop: stripCrop);
        engine.emitVolume(.97);
        await advance(11);
        await capture('03-high', crop: stripCrop);
        await advance(9);
        await capture('04-ripple', crop: stripCrop);

        engine.emitText(const SpeechText(finalized: '', interim: _utterance));
        await advance(6);
        await capture('05-interim-rise');
        await advance(30);
        engine.emitText(const SpeechText(finalized: _utterance, interim: ''));
        await advance(5);
        await capture('06-final-sweep');

        if (capturePhase3) {
          Future<void> captureDrop(String stage) async {
            final goo = liquidPainter().motion.goo;
            final neck = goo.neck!;
            final flat = goo.flat!;
            if (_phase3DumpFolder?.isNotEmpty ?? false) {
              final waist = (neck.toWaistRight.end + neck.toWaistLeft.end) * .5;
              debugPrint(
                'phase3-$stage pull=${controller.value.pull} flat=$flat '
                'head=${neck.head} feet=${neck.left},${neck.right} waist=$waist',
              );
            }
            await capture(stage, phase: 'phase3');
          }

          await pull(80, frames: 80);
          final anchor = liquidPainter().motion.goo.flat!.x;
          await captureDrop('vertical');
          await pull(80, dx: 70, frames: 4);
          expect(liquidPainter().motion.goo.flat!.x, anchor);
          await captureDrop('horizontal-motion');
          await advance(80);
          expect(liquidPainter().motion.goo.flat!.x, anchor);
          await captureDrop('tilted-rest');
          await pull(120, dx: 70, frames: 12);
          await pull(79, dx: 70, frames: 80);
          final center = liquidPainter().motion.goo.blob!.center;
          await pull(78, dx: 70, frames: 0);
          await tester.pump();
          final goo = liquidPainter().motion.goo;
          expect(goo.blob, isNull);
          expect(goo.flat!.x, closeTo(center.x, 1e-6));
          await captureDrop('rejoin');
          await pull(0, frames: 80);
        }

        for (final distance in [20, 60, 100, 109]) {
          await pull(distance.toDouble());
          expect(controller.value.detached, isFalse);
          expect(liquidPainter().motion.goo.neck, isNotNull);
          await capture('pull-${distance}dp');
        }
        await capture(
          'pull-109dp-edge-6x',
          crop: Rect.fromLTWH(origin.dx - 50, origin.dy - 159, 100, 158),
          scale: 6,
        );
        await pull(111, frames: 2);
        expect(controller.value.detached, isTrue);
        expect(liquidPainter().motion.goo.blob, isNotNull);
        expect(liquidPainter().motion.goo.parts, isNotEmpty);
        await capture('pull-111dp-snap');
        await capture(
          'pull-111dp-edge-6x',
          crop: Rect.fromLTWH(origin.dx - 50, origin.dy - 167, 100, 166),
          scale: 6,
        );

        await pull(136, dx: 46, frames: 6);
        expect(controller.value.detached, isTrue);
        await capture('detached-follow');
        await pull(78, dx: 0, frames: 6);
        expect(controller.value.detached, isFalse);
        expect(liquidPainter().motion.goo.blob, isNull);
        expect(liquidPainter().motion.goo.neck, isNotNull);
        await capture('rejoin');

        await pull(60);
        await press.up();
        await advance(4);
        expect(controller.value.retracting, isTrue);
        await capture('retract');
        for (
          var frame = 0;
          frame < 30 && controller.value.retracting;
          frame++
        ) {
          await advance(1);
        }
        expect(controller.value.retracting, isFalse);
        expect(liquidPainter().motion.ripples.last.amplitude, 4);
        await advance(2);
        await capture('retract-ripple');
        await advance(60);
        expect(controller.value.phase, DictationPhase.review);
        expect(editor.text, _utterance);
        expect(tester.binding.transientCallbackCount, 0);

        // Starting again clears the review, but leaves its accepted text intact.
        editor.clear();
        press = await tester.startGesture(origin);
        await tester.pump();
        await advance(20);
        engine.emitText(const SpeechText(finalized: _utterance, interim: ''));
        engine.emitVolume(.35);
        await advance(15);
        await pull(109);
        await pull(122, frames: 15);
        expect(controller.value.detached, isTrue);
        await press.up();
        await advance(2);
        expect(controller.value.phase, DictationPhase.canceling);
        expect(editor.text, isEmpty);
        expect(liquidPainter().motion.holdingForFly, isTrue);
        await capture('undo-intake-early');
        await advance(17);
        await capture('undo-intake-middle');
        await advance(9);
        expect(liquidPainter().motion.holdingForFly, isTrue);
        await capture('undo-intake-late');
        await advance(12);
        expect(liquidPainter().motion.goo.blob, isNull);
        expect(liquidPainter().motion.goo.parts, hasLength(11));
        await capture('undo-pop');
        await advance(6);
        expect(liquidPainter().motion.frame.origin, 0);
        await capture('undo-bar-return');
        await advance(45);
        expect(controller.value.phase, DictationPhase.idle);
        expect(tester.binding.transientCallbackCount, 0);
        expect(find.text('按住说话'), findsOneWidget);
        await capture('undo-complete', liquid: false);

        if (capturePhase4) {
          press = await tester.startGesture(origin);
          await tester.pump();
          engine.emitVolume(.44);
          engine.emitText(const SpeechText(finalized: _utterance, interim: ''));
          // Advance normal frames through expansion, then jump the recognition
          // clock to each capture without rendering thousands of frames.
          await advance(30);
          await tester.pump(const Duration(seconds: 30) - _step * 30);
          expect(controller.value.phase, DictationPhase.hold);
          expect(find.text('0:30'), findsOneWidget);
          await capture('30s', crop: stripCrop, phase: 'phase4');

          await tester.pump(const Duration(seconds: 25));
          await advance(39);
          expect(find.text('还能说 5 秒'), findsOneWidget);
          await capture('55s', crop: stripCrop, phase: 'phase4');

          await tester.pump(const Duration(seconds: 5) - _step * 39);
          await press.up();
          await advance(45);
          expect(controller.value.phase, DictationPhase.review);
          final status = find.text('已到 60 秒');
          expect(status, findsOneWidget);
          await capture(
            'limit',
            crop: Rect.fromLTWH(
              0,
              tester.getCenter(status).dy - stripCrop.height / 2,
              _screen.width,
              stripCrop.height,
            ),
            liquid: false,
            phase: 'phase4',
          );
        }
      });
    }
  }
}

class _CaptureClock implements SpeechClock {
  final WidgetTester tester;
  final DateTime _origin;

  _CaptureClock(this.tester) : _origin = tester.binding.clock.now();

  @override
  Duration get elapsed => tester.binding.clock.now().difference(_origin);

  @override
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}
