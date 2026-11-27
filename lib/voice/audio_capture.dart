import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'speech_engine.dart';

/// One recording of signed 16-bit little-endian PCM at 16 kHz, mono.
/// Both termination methods may be called while [start] is pending.
abstract interface class AudioCapture {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> cancel();
}

class RecordAudioCapture implements AudioCapture {
  AudioRecorder? _recorder;
  Future<Stream<Uint8List>>? _starting;
  Future<void>? _ending;
  bool _capturing = false;

  @override
  Future<Stream<Uint8List>> start() {
    if (_ending != null) return Future.value(const Stream.empty());
    return _starting ??= _start();
  }

  Future<Stream<Uint8List>> _start() async {
    final recorder = _recorder = AudioRecorder();
    final permitted = await recorder.hasPermission();
    if (!permitted) throw const SpeechException(SpeechErrorKind.permission);
    if (_ending != null) return const Stream.empty();
    _capturing = true;
    return recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: false,
        noiseSuppress: false,
        autoGain: false,
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
      ),
    );
  }

  @override
  Future<void> stop() => _ending ??= _end(discard: false);

  @override
  Future<void> cancel() => _ending ??= _end(discard: true);

  Future<void> _end({required bool discard}) async {
    final recorder = _recorder;
    if (recorder == null) return;
    try {
      await _starting;
      if (!_capturing) return;
      if (discard) {
        await recorder.cancel();
      } else {
        await recorder.stop();
      }
    } finally {
      await recorder.dispose();
    }
  }
}
