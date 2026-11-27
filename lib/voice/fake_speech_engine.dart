import 'dart:async';

import 'speech_engine.dart';

/// A single session whose inputs and elapsed time are driven by the test.
class FakeSpeechEngine implements SpeechEngine {
  @override
  final SpeechAvailability availability;

  final _text = StreamController<SpeechText>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _errors = StreamController<SpeechErrorKind>.broadcast();
  final _done = Completer<void>();
  var _transcript = const SpeechText(finalized: '', interim: '');
  Duration _elapsed = Duration.zero;
  bool _started = false;

  FakeSpeechEngine({
    this.availability = const SpeechAvailability(SpeechEngineKind.tencent),
  });

  bool get isActive => _started && !_done.isCompleted;
  Duration get elapsed => _elapsed;

  @override
  Stream<SpeechText> get text => _text.stream;

  @override
  Stream<double> get volume => _volume.stream;

  @override
  Stream<SpeechErrorKind> get errors => _errors.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> start() async {
    if (!_done.isCompleted) _started = true;
  }

  void emitText(SpeechText event) {
    if (!isActive) return;
    _transcript = event;
    _text.add(event);
  }

  void emitVolume(double value) {
    if (isActive) _volume.add(value.clamp(0.0, 1.0));
  }

  void emitError(SpeechErrorKind error) {
    if (!isActive) return;
    _errors.add(error);
    _finish();
  }

  void advance(Duration duration) {
    if (duration.isNegative) throw ArgumentError.value(duration, 'duration');
    if (isActive) _elapsed += duration;
  }

  @override
  Future<void> stop() {
    if (!_done.isCompleted) {
      if (_transcript.interim.isNotEmpty) {
        emitText(SpeechText(finalized: _transcript.combined, interim: ''));
      }
      _finish();
    }
    return done;
  }

  @override
  Future<void> cancel() {
    if (!_done.isCompleted) {
      emitText(const SpeechText(finalized: '', interim: ''));
      _finish();
    }
    return done;
  }

  void _finish() {
    unawaited(_text.close());
    unawaited(_volume.close());
    unawaited(_errors.close());
    _done.complete();
  }
}
