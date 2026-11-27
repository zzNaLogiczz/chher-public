import 'dart:async';

import 'package:chh_app/design/voice_tokens.dart';
import 'package:chh_app/voice/fake_speech_engine.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/widgets/composer/dictation_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'replaces interim text, appends finalized text, and undoes the inserted range',
    (tester) async {
      final rig = _Rig(tester);
      rig.controller.start();
      await tester.pump();
      expect(rig.phase, DictationPhase.locked);

      rig.emit(interim: '原');
      await tester.pump();
      expect(rig.editor.text, '左原右');
      expect(
        rig.controller.value.insertedRange,
        const TextRange(start: 1, end: 2),
      );

      rig.emit(interim: '改写');
      await tester.pump();
      expect(rig.editor.text, '左改写右');

      rig.emit(finalized: '改写，', interim: '暂');
      await tester.pump();
      expect(rig.editor.text, '左改写，暂右');
      expect(rig.controller.value.text.finalized, '改写，');

      rig.emit(finalized: '改写，定稿');
      rig.controller.finish();
      expect(rig.phase, DictationPhase.finalizing);
      await tester.pump();
      expect(rig.phase, DictationPhase.review);
      expect(rig.editor.text, '左改写，定稿右');
      expect(rig.editor.selection.baseOffset, 6);

      rig.controller.cancel();
      expect(rig.phase, DictationPhase.canceling);
      expect(rig.editor.text, '左右');
      await tester.pump(const Duration(milliseconds: 160));
      expect(rig.phase, DictationPhase.idle);
      expect(rig.editor.selection, const TextSelection.collapsed(offset: 1));
    },
  );

  testWidgets(
    'replaces a reversed selection and retries at its original start',
    (tester) async {
      final rig = _Rig(tester, text: '左选区右');
      rig.editor.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 1,
      );
      rig.controller.start();
      await tester.pump();
      expect(rig.editor.text, '左选区右');
      rig.emit(interim: '第一句');
      await tester.pump();
      expect(rig.editor.text, '左第一句右');

      rig.controller.finish();
      await tester.pump();
      final first = rig.engine;
      rig.controller.retry();
      await tester.pump();
      expect(rig.engine, isNot(same(first)));
      expect(rig.phase, DictationPhase.locked);
      expect(rig.editor.text, '左右');
      expect(rig.editor.selection.baseOffset, 1);
      rig.emit(finalized: '第二句');
      await tester.pump();
      expect(rig.editor.text, '左第二句右');
      rig.controller.cancel();
      await tester.pump(const Duration(milliseconds: 160));
    },
  );

  testWidgets('an edit ends review without removing any text', (tester) async {
    final rig = _Rig(tester);
    rig.controller.start();
    await tester.pump();
    rig.emit(finalized: '听写');
    rig.controller.finish();
    await tester.pump();
    expect(rig.phase, DictationPhase.review);

    rig.editor.text = '左听写右。';
    expect(rig.phase, DictationPhase.idle);
    expect(rig.controller.canUndo, isFalse);
    rig.controller.cancel();
    expect(rig.editor.text, '左听写右。');
  });

  for (final (error, phase) in [
    (SpeechErrorKind.network, DictationPhase.errorNetwork),
    (SpeechErrorKind.busy, DictationPhase.errorBusy),
    (SpeechErrorKind.service, DictationPhase.errorUnavailable),
  ]) {
    testWidgets('${error.name} preserves both final and queued interim text', (
      tester,
    ) async {
      final rig = _Rig(tester);
      rig.controller.start();
      await tester.pump();

      rig.emit(finalized: '正文', interim: '暂');
      rig.emit(finalized: '正文', interim: '收尾');
      rig.engine.emitError(error);
      await tester.pump();

      expect(rig.phase, phase);
      expect(rig.editor.text, '左正文收尾右');
      expect(rig.controller.canUndo, isTrue);
      rig.controller.cancel();
      expect(rig.editor.text, '左右');
      await tester.pump(VoiceTokens.plainUndo);
    });
  }

  testWidgets('does not run the 60-second limit until recognition is ready', (
    tester,
  ) async {
    final gate = _DelayedEngine();
    final engines = [gate, FakeSpeechEngine()];
    final rig = _Rig(tester, create: () => engines.removeAt(0));
    rig.controller.start(pointer: const Offset(50, 100));
    await tester.pump(const Duration(seconds: 60));
    expect(rig.phase, DictationPhase.press);
    expect(rig.controller.value.seconds, 0);

    gate.ready.complete();
    await tester.pump();
    expect(rig.phase, DictationPhase.hold);
    rig.emit(interim: '听写');
    await tester.pump(const Duration(seconds: 59, milliseconds: 999));
    expect(rig.phase, DictationPhase.hold);
    expect(rig.controller.value.seconds, 59);
    expect(rig.controller.value.hitLimit, isFalse);

    await tester.pump(const Duration(milliseconds: 1));
    expect(rig.phase, DictationPhase.review);
    expect(rig.controller.value.seconds, 60);
    expect(rig.controller.value.hitLimit, isTrue);
    expect(rig.editor.text, '左听写右');

    rig.controller.retry();
    await tester.pump();
    rig.emit(interim: '重说');
    await tester.pump();
    rig.controller.finish();
    await tester.pump();
    expect(rig.phase, DictationPhase.review);
    expect(rig.controller.value.hitLimit, isFalse);
  });

  testWidgets('limit haptics fire once each at 50, 57, 58 and 59 seconds', (
    tester,
  ) async {
    final calls = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final rig = _Rig(tester);
    rig.controller.start(pointer: const Offset(50, 100));
    await tester.pump();
    rig.emit(interim: '听写');
    await tester.pump(const Duration(seconds: 49));
    expect(calls, isEmpty);
    for (var seconds = 50; seconds <= 60; seconds++) {
      await tester.pump(const Duration(milliseconds: 800));
      expect(calls, isEmpty, reason: 'before $seconds seconds');
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, switch (seconds) {
        50 => ['HapticFeedbackType.lightImpact'],
        57 || 58 || 59 => ['HapticFeedbackType.selectionClick'],
        _ => isEmpty,
      }, reason: 'at $seconds seconds');
      calls.clear();
      rig.engine.emitVolume(.7);
      await tester.pump();
      expect(
        calls,
        isEmpty,
        reason: 'repeated publication at $seconds seconds',
      );
    }
  });

  testWidgets('hands-free constant .3 noise ends at about four seconds', (
    tester,
  ) async {
    final rig = _Rig(tester);
    rig.controller.start();
    await tester.pump();
    await _audio(tester, rig, 100, (_) => .3);
    expect(rig.phase, DictationPhase.locked);
    await _audio(tester, rig, 13, (_) => .3);
    expect(rig.phase, DictationPhase.errorSilent);
    expect(rig.editor.text, '左右');
    expect(rig.controller.value.hitLimit, isFalse);
    rig.controller.dismissReview();
  });

  testWidgets('hands-free speech above .3 noise extends audio silence', (
    tester,
  ) async {
    final rig = _Rig(tester);
    rig.controller.start();
    await tester.pump();
    await _audio(tester, rig, 30, (_) => .3);
    await _audio(tester, rig, 150, _speechOverNoise);
    expect(rig.phase, DictationPhase.locked);
    await _audio(tester, rig, 100, (_) => .3);
    expect(rig.phase, DictationPhase.locked);
    await _audio(tester, rig, 10, (_) => .3);
    expect(rig.phase, DictationPhase.errorSilent);
    rig.controller.dismissReview();
  });

  testWidgets('hands-free .05 volume keeps the four-second quiet deadline', (
    tester,
  ) async {
    final rig = _Rig(tester);
    rig.controller.start();
    await tester.pump();
    await _audio(tester, rig, 99, (_) => .05);
    expect(rig.phase, DictationPhase.locked);
    await _audio(tester, rig, 1, (_) => .05);
    expect(rig.phase, DictationPhase.errorSilent);
    rig.controller.dismissReview();
  });

  testWidgets('hands-free smoothing ignores a single loud PCM frame', (
    tester,
  ) async {
    final rig = _Rig(tester);
    rig.controller.start();
    await tester.pump();
    await _audio(tester, rig, 80, (_) => .3);
    await _audio(tester, rig, 1, (_) => .7);
    await _audio(tester, rig, 30, (_) => .3);
    expect(rig.phase, DictationPhase.locked);
    await _audio(tester, rig, 1, (_) => .3);
    expect(rig.phase, DictationPhase.errorSilent);
    rig.controller.dismissReview();
  });

  testWidgets('hands-free noise floor rises when old quiet samples expire', (
    tester,
  ) async {
    final rig = _Rig(tester);
    rig.controller.start();
    await tester.pump();
    await _audio(tester, rig, 1, (_) => .05);
    await _audio(tester, rig, 169, (_) => .3);
    expect(rig.phase, DictationPhase.locked);
    await _audio(tester, rig, 15, (_) => .3);
    expect(rig.phase, DictationPhase.errorSilent);
    rig.controller.dismissReview();
  });

  testWidgets('hands-free final-only text times out despite ongoing voice', (
    tester,
  ) async {
    final rig = _Rig(tester);
    rig.controller.start();
    await tester.pump();
    await _audio(tester, rig, 30, (_) => .3);
    rig.emit(finalized: '只有定稿');
    await tester.pump();
    await _audio(tester, rig, 99, _speechOverNoise);
    expect(rig.phase, DictationPhase.locked);
    await _audio(tester, rig, 1, (_) => .7);
    expect(rig.phase, DictationPhase.review);
    expect(rig.editor.text, '左只有定稿右');
  });

  testWidgets('hands-free text deadline resets only for new recognized words', (
    tester,
  ) async {
    final rig = _Rig(tester);
    rig.controller.start();
    await tester.pump();
    await _audio(tester, rig, 30, (_) => .3);
    rig.emit(interim: '一句');
    await tester.pump();
    await _audio(tester, rig, 50, _speechOverNoise);
    rig.emit(interim: '一句话');
    await tester.pump();
    await _audio(tester, rig, 50, _speechOverNoise);
    rig.emit(finalized: '一句话');
    await tester.pump();
    await _audio(tester, rig, 49, _speechOverNoise);
    expect(rig.phase, DictationPhase.locked);
    await _audio(tester, rig, 1, (_) => .7);
    expect(rig.phase, DictationPhase.review);
    expect(rig.editor.text, '左一句话右');
  });

  testWidgets(
    'hands-free without text stays open while audio indicates voice',
    (tester) async {
      final rig = _Rig(tester);
      rig.controller.start();
      await tester.pump();
      await _audio(tester, rig, 30, (_) => .3);
      await _audio(tester, rig, 250, _speechOverNoise);
      expect(rig.phase, DictationPhase.locked);
      expect(rig.editor.text, '左右');
      rig.controller.cancel();
      await tester.pump(VoiceTokens.plainUndo);
    },
  );

  testWidgets('hold ignores audio and text silence deadlines until release', (
    tester,
  ) async {
    final rig = _Rig(tester);
    rig.controller.start(pointer: const Offset(50, 100));
    await tester.pump();
    rig.emit(interim: '按住');
    await tester.pump();
    await _audio(tester, rig, 150, (_) => .05);
    expect(rig.phase, DictationPhase.hold);
    rig.controller.release();
    await tester.pump();
    expect(rig.phase, DictationPhase.review);
    expect(rig.editor.text, '左按住右');
  });

  testWidgets('four seconds without any sound shows the silent state', (
    tester,
  ) async {
    final rig = _Rig(tester, text: '左选区右');
    rig.editor.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    rig.controller.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(rig.phase, DictationPhase.errorSilent);
    expect(rig.editor.text, '左选区右');
    expect(rig.controller.canUndo, isFalse);
    await tester.pump(const Duration(milliseconds: 2399));
    expect(rig.phase, DictationPhase.errorSilent);
    await tester.pump(const Duration(milliseconds: 1));
    expect(rig.phase, DictationPhase.idle);
  });

  for (final (label, endPress)
      in <(String, void Function(DictationController))>[
        ('release', (controller) => controller.release()),
        (
          'system pointer cancellation',
          (controller) => controller.release(interrupted: true),
        ),
        ('focus loss', (controller) => controller.interrupt()),
      ]) {
    testWidgets('$label during startup defers to hands-free after readiness', (
      tester,
    ) async {
      final gate = _DelayedEngine();
      final rig = _Rig(tester, create: () => gate);
      rig.controller.start(pointer: const Offset(50, 100));
      await tester.pump(const Duration(seconds: 20));
      endPress(rig.controller);
      expect(rig.phase, DictationPhase.press);
      expect(rig.controller.value.seconds, 0);
      expect(gate.isActive, isTrue);

      gate.ready.complete();
      await tester.pump();
      expect(rig.phase, DictationPhase.locked);
      expect(rig.controller.value.seconds, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.controller.value.seconds, 1);
      rig.controller.cancel();
      await tester.pump(const Duration(milliseconds: 160));
    });
  }

  testWidgets(
    'startup detach cancels immediately and drops late engine events',
    (tester) async {
      final previous = _DelayedEngine();
      final next = FakeSpeechEngine();
      final engines = [previous, next].iterator;
      final rig = _Rig(
        tester,
        create: () {
          engines.moveNext();
          return engines.current;
        },
      );
      rig.controller.start(pointer: const Offset(50, 200));
      await tester.pump();
      rig.controller.move(const Offset(50, 100));
      expect(rig.controller.value.detached, isTrue);
      rig.controller.release();
      expect(rig.phase, DictationPhase.canceling);
      expect(previous.cancelRequested, isTrue);

      rig.controller.start();
      await tester.pump();
      rig.emit(interim: '新会话');
      previous.ready.complete();
      previous.emitText(const SpeechText(finalized: '迟到的文字', interim: ''));
      previous.emitError(SpeechErrorKind.permission);
      await tester.pump();
      expect(rig.phase, DictationPhase.locked);
      expect(rig.editor.text, '左新会话右');
      rig.controller.cancel();
      await tester.pump(const Duration(milliseconds: 160));
    },
  );

  testWidgets(
    'IME selection syncs keep the review chip, real edits hand control back',
    (tester) async {
      final rig = _Rig(tester);
      rig.controller.start();
      await tester.pump(const Duration(milliseconds: 300));
      rig.emit(finalized: '识别文字');
      await tester.pump();
      rig.controller.finish();
      await tester.pump();
      expect(rig.phase, DictationPhase.review);
      expect(rig.editor.text, '左识别文字右');
      final kept = rig.editor.value;

      // 键盘敲击、连接重同步只会更新选区或组合区，不应撤掉「撤销 / 重说」。
      rig.editor.value = kept.copyWith(
        selection: const TextSelection.collapsed(offset: 1),
        composing: const TextRange(start: 1, end: 3),
      );
      await tester.pump();
      expect(rig.phase, DictationPhase.review);
      expect(rig.controller.canUndo, isTrue);
      expect(rig.editor.text, '左识别文字右');

      // 用户真正改写正文后撤销区间失准，接管并保留现状。
      rig.editor.value = kept.copyWith(
        text: '左改写右',
        selection: const TextSelection.collapsed(offset: 2),
      );
      await tester.pump();
      expect(rig.phase, DictationPhase.idle);
      expect(rig.controller.canUndo, isFalse);
      expect(rig.editor.text, '左改写右');
    },
  );

  testWidgets('explicit finish during startup returns immediately', (
    tester,
  ) async {
    final gate = _DelayedEngine();
    final rig = _Rig(tester, create: () => gate);
    rig.controller.start();
    expect(rig.phase, DictationPhase.press);
    rig.controller.finish();
    expect(rig.phase, DictationPhase.idle);
    gate.ready.complete();
    await tester.pump();
    expect(rig.phase, DictationPhase.idle);
  });

  testWidgets(
    'interruption after readiness stops and keeps recognized text without awaiting cleanup',
    (tester) async {
      final gate = _DelayedEngine()..ready.complete();
      final rig = _Rig(tester, create: () => gate);
      rig.controller.start(pointer: const Offset(50, 200));
      await tester.pump(const Duration(milliseconds: 300));
      rig.emit(interim: '保留');
      await tester.pump();
      rig.controller.interrupt();
      await tester.pump();

      expect(gate.stopRequested, isTrue);
      expect(gate.cleanup.isCompleted, isFalse);
      expect(rig.phase, DictationPhase.review);
      expect(rig.editor.text, '左保留右');
    },
  );
}

double _speechOverNoise(int frame) => frame % 50 < 20 ? .3 : .7;

Future<void> _audio(
  WidgetTester tester,
  _Rig rig,
  int frames,
  double Function(int frame) volume,
) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    rig.engine.emitVolume(volume(frame));
    await tester.pump();
  }
}

class _Rig {
  final TextEditingController editor;
  late final DictationController controller;
  late FakeSpeechEngine engine;

  _Rig(
    WidgetTester tester, {
    String text = '左右',
    FakeSpeechEngine Function()? create,
  }) : editor = TextEditingController.fromValue(
         TextEditingValue(
           text: text,
           selection: const TextSelection.collapsed(offset: 1),
         ),
       ) {
    controller = DictationController(
      editor: editor,
      createEngine: () => engine = create?.call() ?? FakeSpeechEngine(),
      clock: _TestClock(tester),
    );
    addTearDown(() {
      controller.dispose();
      editor.dispose();
    });
  }

  DictationPhase get phase => controller.value.phase;

  void emit({String finalized = '', String interim = ''}) =>
      engine.emitText(SpeechText(finalized: finalized, interim: interim));
}

class _DelayedEngine extends FakeSpeechEngine {
  final ready = Completer<void>();
  final cleanup = Completer<void>();
  bool cancelRequested = false;
  bool stopRequested = false;

  @override
  Future<void> start() async {
    await super.start();
    await ready.future;
  }

  @override
  Future<void> stop() {
    stopRequested = true;
    unawaited(super.stop());
    return cleanup.future;
  }

  @override
  Future<void> cancel() {
    cancelRequested = true;
    return cleanup.future;
  }
}

class _TestClock implements SpeechClock {
  final WidgetTester tester;
  final DateTime _origin;

  _TestClock(this.tester) : _origin = tester.binding.clock.now();

  @override
  Duration get elapsed => tester.binding.clock.now().difference(_origin);

  @override
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}
