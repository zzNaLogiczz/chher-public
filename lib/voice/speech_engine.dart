import 'dart:async';

enum SpeechEngineKind { tencent, none }

enum SpeechErrorKind { network, busy, service, permission, silent }

class SpeechAvailability {
  final SpeechEngineKind kind;
  const SpeechAvailability(this.kind);

  bool get isAvailable => kind != SpeechEngineKind.none;
}

/// An error from an engine dependency. Session errors are reported on [SpeechEngine.errors].
class SpeechException implements Exception {
  final SpeechErrorKind kind;
  const SpeechException(this.kind);
}

class SpeechText {
  final String finalized;
  final String interim;
  const SpeechText({required this.finalized, required this.interim});

  String get combined => joinSpeechText(finalized, interim);
}

final _latinOrDigitAtEnd = RegExp(r'[a-zA-Z0-9]$');
final _latinOrDigitAtStart = RegExp(r'^[a-zA-Z0-9]');

String joinSpeechText(String left, String right) {
  final space =
      _latinOrDigitAtEnd.hasMatch(left) && _latinOrDigitAtStart.hasMatch(right);
  return space ? '$left $right' : '$left$right';
}

/// A single-use dictation session. Subscribe before starting.
/// Terminal errors arrive on [errors]. The text and error streams close once
/// recognition ends, before any remaining resource cleanup completes.
abstract interface class SpeechEngine {
  SpeechAvailability get availability;
  Stream<SpeechText> get text;
  Stream<double> get volume;
  Stream<SpeechErrorKind> get errors;

  /// Completes when the session ends, including unsolicited server termination.
  Future<void> get done;

  /// Returns when ready to recognize or when startup terminates.
  Future<void> start();

  /// Stops the input and waits for recognition and cleanup to finish.
  Future<void> stop();

  /// Discards this session and waits for cleanup.
  Future<void> cancel();
}

/// Monotonic time and one-shot scheduling for session deadlines and frame pacing.
abstract interface class SpeechClock {
  Duration get elapsed;
  Timer schedule(Duration delay, void Function() callback);
}

class SystemSpeechClock implements SpeechClock {
  final _stopwatch = Stopwatch()..start();

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}
