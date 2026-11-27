import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/voice/fake_speech_engine.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/widgets/composer/composer_editor.dart';
import 'package:chh_app/widgets/composer/dictation_controller.dart';
import 'package:chh_app/widgets/composer/smiley_editing_controller.dart';
import 'package:chh_app/widgets/composer/voice_fly_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fly reverses the four groups and arrives at the drop center', () {
    expect(
      [for (var i = 0; i < 8; i++) voiceFlyGroup(i, 8)],
      [3, 3, 2, 2, 1, 1, 0, 0],
    );
    for (final (actual, expected) in voiceFlyArrivals(
      8,
    ).indexed.map((e) => (e.$2, [.387, .432, .477, .522][e.$1]))) {
      expect(actual, closeTo(expected, 1e-12));
    }
    expect(voiceFlyPopTime(8), closeTo(.592, 1e-12));
    expect(voiceFlyPopTime(0), .05);
    final pose = voiceFlyPose(
      elapsed: .4,
      delay: 0,
      x0: 29,
      y0: 15,
      x2: 120,
      y2: 97,
      side: -1,
      bend: 24,
      rotation: 12,
    );
    expect((pose.x, pose.y, pose.opacity), (120, 97, 0));
    expect(pose.scale, closeTo(.22, 1e-12));
  });

  testWidgets('interim and commit take over glyphs and restore editable text', (
    tester,
  ) async {
    final rig = await _mount(tester);
    rig.editor.text = '前后';
    rig.editor.selection = const TextSelection.collapsed(offset: 1);
    rig.voice.start();
    await tester.pump();
    rig.engines.last.emitText(const SpeechText(finalized: '', interim: '听写'));
    await tester.pump();
    expect(rig.editor.text, '前听写后');
    expect(_style(tester, '听写')?.color, Colors.transparent);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      _style(tester, '听写')?.color,
      AppTokens.of(tester.element(find.byType(TextField))).text3,
    );
    expect(tester.binding.transientCallbackCount, 0);

    rig.engines.last.emitText(const SpeechText(finalized: '听写', interim: '测试'));
    await tester.idle();
    await tester.pump();
    expect(_style(tester, '听写测试')?.color, Colors.transparent);
    rig.engines.last.emitText(const SpeechText(finalized: '听写', interim: '替换'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(rig.editor.text, '前听写替换后');
    expect(_style(tester, '听写替换')?.color, Colors.transparent);
    await tester.pump(const Duration(milliseconds: 370));
    expect(_style(tester, '前听写')?.color, isNull);
    expect(_style(tester, '替换')?.color, isNot(Colors.transparent));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await rig.dispose();
  });

  testWidgets(
    'undo clears the value synchronously and a new session clears the old overlay',
    (tester) async {
      final rig = await _mount(tester);
      rig.voice.start();
      await tester.pump();
      rig.engines.last.emitText(const SpeechText(finalized: '撤销', interim: ''));
      await tester.pump();
      rig.voice.finish();
      await tester.pump();
      expect(rig.voice.value.phase, DictationPhase.review);
      expect(
        _style(tester, '撤销')?.backgroundColor,
        AppTokens.of(tester.element(find.byType(TextField))).accentFill,
      );
      rig.voice.cancel();
      expect(rig.editor.text, isEmpty);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        isNull,
      );
      rig.voice.start();
      await tester.pump();
      expect(rig.engines.length, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        '草稿',
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await rig.dispose();
    },
  );

  testWidgets(
    'reduce motion uses one finite interim fade and skips commit motion',
    (tester) async {
      final rig = await _mount(tester, reduced: true);
      rig.voice.start();
      await tester.pump();
      rig.engines.last.emitText(const SpeechText(finalized: '', interim: '轻量'));
      await tester.idle();
      await tester.pump();
      expect(_style(tester, '轻量')?.color, Colors.transparent);
      await tester.pump(const Duration(milliseconds: 150));
      expect(_style(tester, '轻量')?.color, isNot(Colors.transparent));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      rig.engines.last.emitText(const SpeechText(finalized: '轻量', interim: ''));
      await tester.idle();
      await tester.pump();
      expect(_style(tester, '轻量')?.color, isNot(Colors.transparent));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await rig.dispose();
    },
  );
}

TextStyle? _style(WidgetTester tester, String value) {
  final render = tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable;
  TextStyle? style;
  render.text!.visitChildren((span) {
    if (span is TextSpan && span.text == value) {
      style = span.style;
      return false;
    }
    return true;
  });
  return style;
}

Future<
  ({
    SmileyEditingController editor,
    DictationController voice,
    List<FakeSpeechEngine> engines,
    Future<void> Function() dispose,
  })
>
_mount(WidgetTester tester, {bool reduced = false}) async {
  final editor = SmileyEditingController();
  final focus = FocusNode();
  final engines = <FakeSpeechEngine>[];
  final voice = DictationController(
    editor: editor,
    createEngine: () {
      final engine = FakeSpeechEngine();
      engines.add(engine);
      return engine;
    },
  );
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    voice.dispose();
    focus.dispose();
    editor.dispose();
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: Scaffold(
            body: ComposerEditor(
              controller: editor,
              focusNode: focus,
              dictation: voice,
              hintText: '草稿',
            ),
          ),
        ),
      ),
    ),
  );
  return (editor: editor, voice: voice, engines: engines, dispose: dispose);
}
