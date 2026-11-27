import 'package:chh_app/voice/fake_speech_engine.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the test drives text, volume, errors and session time', () async {
    final engine = FakeSpeechEngine();
    final text = <SpeechText>[];
    final volume = <double>[];
    final errors = <SpeechErrorKind>[];
    engine.text.listen(text.add);
    engine.volume.listen(volume.add);
    engine.errors.listen(errors.add);

    await engine.start();
    expect(engine.isActive, isTrue);
    const transcript = SpeechText(finalized: 'Hello', interim: 'world');
    engine.emitText(transcript);
    engine.emitVolume(.45);
    engine.advance(const Duration(seconds: 3));
    expect(engine.elapsed, const Duration(seconds: 3));

    engine.emitError(SpeechErrorKind.network);
    await engine.done;
    expect(engine.isActive, isFalse);
    expect(text, [transcript]);
    expect(volume, [.45]);
    expect(errors, [SpeechErrorKind.network]);

    engine.advance(const Duration(seconds: 3));
    expect(engine.elapsed, const Duration(seconds: 3));
  });

  test('stop commits interim text and cancel clears the transcript', () async {
    for (final cancel in [false, true]) {
      final engine = FakeSpeechEngine();
      final transcript = engine.text.toList();
      await engine.start();
      engine.emitText(const SpeechText(finalized: 'Hello', interim: 'world'));

      await (cancel ? engine.cancel() : engine.stop());
      final text = await transcript;
      expect(text.last.finalized, cancel ? '' : 'Hello world');
      expect(text.last.interim, '');
    }
  });
}
