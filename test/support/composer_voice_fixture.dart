import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:chh_app/design/composer_tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/voice/fake_speech_engine.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/widgets/composer/dictation_controller.dart';
import 'package:chh_app/widgets/composer/voice_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FakeSpeechEngine installVoiceFixture({FakeSpeechEngine? engine}) {
  final speech = engine ?? FakeSpeechEngine();
  voiceOverridesForTesting = (
    query: () async => const SpeechAvailability(SpeechEngineKind.tencent),
    create: (kind) {
      expect(kind, SpeechEngineKind.tencent);
      return speech;
    },
  );
  addTearDown(() => voiceOverridesForTesting = null);
  return speech;
}

Future<void> expectHostDictation(
  WidgetTester tester,
  FakeSpeechEngine engine,
  Finder field,
) async {
  TextField editor() => tester.widget<TextField>(field);
  final controller = editor().controller!;
  await tester.enterText(field, '前后');
  controller.selection = const TextSelection.collapsed(offset: 1);
  await tester.pump();

  final press = await tester.startGesture(
    tester.getCenter(find.byType(VoiceBar)),
  );
  await tester.pump();
  expect(engine.isActive, isTrue);
  expect(editor().readOnly, isFalse);

  engine.emitText(const SpeechText(finalized: '', interim: '听写'));
  await tester.pump(const Duration(milliseconds: 300));
  expect(controller.text, '前听写后');
  await press.up();
  await tester.pumpAndSettle();
  expect(editor().readOnly, isFalse);
  expect(controller.text, '前听写后');

  await tester.tap(find.text('撤销'));
  await tester.pumpAndSettle();
  expect(controller.text, '前后');
  expect(controller.selection, const TextSelection.collapsed(offset: 1));
  expect(find.text('撤销'), findsNothing);
}

void hostDictationKeyboardTests(
  String hostName,
  Future<Finder> Function(WidgetTester) open,
) {
  final bar = find.byType(VoiceBar);

  DictationController dictation(WidgetTester tester) =>
      tester.widget<VoiceBar>(bar).controller;

  testWidgets('$hostName dictation does not focus an unfocused editor', (
    tester,
  ) async {
    final engine = installVoiceFixture();
    final field = await open(tester);
    final editor = tester.widget<TextField>(field);
    final focus = editor.focusNode!;
    focus.unfocus();
    await tester.pumpAndSettle();
    final ime = tester.testTextInput;
    expect(ime.isVisible, isFalse);
    expect(ime.hasAnyClients, isFalse);
    ime.log.clear();

    final origin = tester.getCenter(bar);
    final press = await tester.startGesture(origin);
    await tester.pump();
    engine.emitText(const SpeechText(finalized: '听写', interim: ''));
    await tester.pump(ComposerTokens.voiceHoldDelay);
    expect(tester.getCenter(bar), origin);
    expect(focus.hasFocus, isFalse);
    await press.up();
    await tester.pumpAndSettle();

    expect(dictation(tester).value.phase, DictationPhase.review);
    expect(editor.controller!.text, '听写');
    expect(tester.getCenter(bar), origin);
    expect(focus.hasFocus, isFalse);
    expect(ime.isVisible, isFalse);
    expect(ime.hasAnyClients, isFalse);
    expect(
      ime.log.map((call) => call.method),
      isNot(contains(anyOf('TextInput.setClient', 'TextInput.show'))),
    );
  });

  for (final keyboardOpen in [true, false]) {
    final keyboard = keyboardOpen ? 'visible IME' : 'hidden IME';
    testWidgets('$hostName $keyboard stays in place through pull-to-cancel', (
      tester,
    ) async {
      final engine = installVoiceFixture();
      final field = await open(tester);
      final editor = tester.widget<TextField>(field);
      final text = editor.controller!;
      final focus = editor.focusNode!;
      final input = tester.testTextInput;
      await tester.enterText(field, '原文');
      if (keyboardOpen) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
      } else {
        input.hide();
      }
      await tester.pumpAndSettle();
      expect(input.isVisible, keyboardOpen);
      expect(focus.hasFocus, isTrue);
      expect(input.hasAnyClients, isTrue);
      input.log.clear();
      final origin = tester.getCenter(bar);
      final controller = dictation(tester);

      void checkKeyboardAndBar() {
        expect(tester.getCenter(bar), origin);
        expect(tester.widget<TextField>(field).readOnly, isFalse);
        expect(focus.hasFocus, isTrue);
        expect(input.hasAnyClients, isTrue);
        expect(input.isVisible, keyboardOpen);
        expect(
          input.log.map((call) => call.method),
          isNot(
            contains(
              anyOf(
                'TextInput.hide',
                'TextInput.show',
                'TextInput.clearClient',
                'TextInput.setClient',
              ),
            ),
          ),
        );
      }

      // A mouse press would normally unfocus a field when it lands outside.
      final press = await tester.startGesture(
        origin,
        kind: keyboardOpen ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(controller.value.phase, DictationPhase.press);
      checkKeyboardAndBar();

      engine.emitText(const SpeechText(finalized: '听写', interim: ''));
      await tester.pump(ComposerTokens.voiceHoldDelay);
      expect(controller.value.phase, DictationPhase.hold);
      expect(text.text, '原文听写');
      checkKeyboardAndBar();

      await press.moveTo(origin - const Offset(0, 60));
      await tester.pump();
      expect(controller.value.pull, greaterThan(0));
      expect(controller.value.detached, isFalse);
      checkKeyboardAndBar();

      await press.moveTo(origin - const Offset(0, 110));
      await tester.pump();
      expect(controller.value.detached, isTrue);
      checkKeyboardAndBar();

      await press.up();
      await tester.pump();
      expect(controller.value.phase, DictationPhase.canceling);
      expect(controller.editorLocked, isTrue);
      expect(text.text, '原文');
      checkKeyboardAndBar();
      final beforeEdit = text.value;
      input.enterText('原文误触');
      await tester.pump();
      expect(text.value, beforeEdit);
      expect(input.editingState, beforeEdit.toJSON());
      checkKeyboardAndBar();
      input.updateEditingValue(
        text.value.copyWith(composing: const TextRange(start: 0, end: 1)),
      );
      await tester.pump();
      checkKeyboardAndBar();
      expect(controller.value.phase, DictationPhase.canceling);
      expect(text.value, beforeEdit);
      expect(input.editingState, beforeEdit.toJSON());

      // Sample the drop flight and liquid tail at frame intervals.
      for (
        var frame = 0;
        tester.binding.hasScheduledFrame && frame < 120;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
        checkKeyboardAndBar();
      }
      expect(controller.value.phase, DictationPhase.idle);
      checkKeyboardAndBar();
      input.enterText('原文继续');
      await tester.pump();
      expect(text.text, '原文继续');
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  for (final phase in [
    DictationPhase.press,
    DictationPhase.hold,
    DictationPhase.locked,
    DictationPhase.finalizing,
  ]) {
    final composingOnly = phase == DictationPhase.hold;
    final editKind = composingOnly ? 'composing update' : 'commit';
    testWidgets(
      '$hostName IME $editKind in ${phase.name} takes over dictation',
      (tester) async {
        final engine = _DelayedEndEngine();
        installVoiceFixture(engine: engine);
        final field = await open(tester);
        final ime = tester.testTextInput;
        final text = tester.widget<TextField>(field).controller!;
        final controller = dictation(tester);
        await tester.showKeyboard(field);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        const draft = TextEditingValue(
          text: '原nia文',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 1, end: 3),
        );
        ime.updateEditingValue(draft);
        await tester.pumpAndSettle();
        expect(text.value, draft);
        ime.log.clear();

        final origin = tester.getCenter(bar);
        final press = await tester.startGesture(origin);
        await tester.pump();
        expect(text.value, draft.copyWith(composing: TextRange.empty));
        expect(ime.editingState, text.value.toJSON());
        expect(
          ime.log.where((call) => call.method == 'TextInput.setEditingState'),
          isNotEmpty,
        );
        engine.emitText(const SpeechText(finalized: '定稿', interim: '听'));
        if (phase == DictationPhase.locked) await press.up();
        await tester.pump(
          phase == DictationPhase.hold || phase == DictationPhase.finalizing
              ? ComposerTokens.voiceHoldDelay
              : null,
        );
        if (composingOnly) {
          // A caret move alone is allowed during listening.
          await tester.tapAt(tester.getTopLeft(field) + const Offset(2, 8));
          await tester.pump();
          expect(text.selection, const TextSelection.collapsed(offset: 0));
          expect(controller.value.phase, DictationPhase.hold);
        }
        engine.emitText(const SpeechText(finalized: '定稿', interim: '听写'));
        await tester.pump();
        if (phase == DictationPhase.finalizing) {
          await press.up();
          await tester.pump();
        }
        expect(controller.value.phase, phase);
        expect(
          controller.value.insertedRange,
          const TextRange(start: 3, end: 7),
        );
        final stopCalls = phase == DictationPhase.finalizing ? 1 : 0;
        expect(engine.stopCalls, stopCalls);

        final recognized = text.value;
        expect(recognized.text, '原ni定稿听写a文');
        expect(recognized.selection, const TextSelection.collapsed(offset: 7));
        final edit = composingOnly
            // The text already contains the inline pinyin. Only mark its range.
            ? recognized.copyWith(
                selection: const TextSelection.collapsed(offset: 8),
                composing: const TextRange(start: 7, end: 8),
              )
            : const TextEditingValue(
                text: '原ni定稿听写啊a文',
                selection: TextSelection.collapsed(offset: 8),
              );
        ime.log.clear();
        final phases = <DictationPhase>[];
        void recordPhase() => phases.add(controller.value.phase);
        controller.addListener(recordPhase);
        ime.updateEditingValue(edit);
        await tester.pump();
        expect(text.value, edit);
        expect(phases, [DictationPhase.idle]);
        expect(controller.value.insertedRange, TextRange.empty);
        expect(controller.canUndo, isFalse);
        expect(controller.editorLocked, isFalse);
        expect(engine.stopCalls, stopCalls);
        expect(engine.cancelCalls, 1);
        expect(find.text('撤销'), findsNothing);
        expect(find.text('重说'), findsNothing);
        expect(
          ime.log
              .where((call) => call.method == 'TextInput.setEditingState')
              .map((call) => call.arguments),
          everyElement(edit.toJSON()),
        );
        expect(tester.getCenter(bar), origin);
        expect(tester.widget<TextField>(field).readOnly, isFalse);

        if (phase == DictationPhase.press || phase == DictationPhase.hold) {
          await press.up();
        }
        // The fake can still deliver events while engine cleanup is pending.
        expect(engine.isActive, isTrue);
        engine.emitText(const SpeechText(finalized: '晚到的定稿', interim: ''));
        engine.emitVolume(0.9);
        await tester.pump(const Duration(seconds: 5));
        expect(text.value, edit);
        expect(controller.value.volume, 0);
        expect(phases, [DictationPhase.idle]);

        engine.finishCancel.complete();
        engine.finishStop.complete();
        await tester.pumpAndSettle();
        expect(engine.isActive, isFalse);
        expect(text.value, edit);
        expect(phases, [DictationPhase.idle]);
        controller.removeListener(recordPhase);
        expect(tester.getCenter(bar), origin);
        expect(ime.isVisible, isTrue);
        expect(ime.hasAnyClients, isTrue);
        expect(
          ime.log.map((call) => call.method),
          isNot(
            contains(
              anyOf(
                'TextInput.hide',
                'TextInput.clearClient',
                'TextInput.setClient',
              ),
            ),
          ),
        );
        ime.enterText('${edit.text}继续');
        await tester.pumpAndSettle();
        expect(text.text, '${edit.text}继续');
        expect(controller.value.phase, DictationPhase.idle);
      },
    );
  }
}

class _DelayedEndEngine extends FakeSpeechEngine {
  final finishStop = Completer<void>();
  final finishCancel = Completer<void>();
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> stop() async {
    stopCalls++;
    await finishStop.future;
    await super.stop();
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    await finishCancel.future;
    await super.cancel();
  }
}
