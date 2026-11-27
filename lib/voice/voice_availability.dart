import 'dart:io';

import 'speech_engine.dart';
import 'voice_service_client.dart';

/// Reuse across composer openings to share the status cache and pending request.
class VoiceAvailability {
  static const _ttl = Duration(minutes: 10);

  final VoiceServiceClient _service;
  final DateTime Function() _now;
  final File _file;
  DateTime? _checkedAt;
  bool? _lastKnown;
  Future<SpeechAvailability>? _pending;

  VoiceAvailability({
    required VoiceServiceClient service,
    DateTime Function()? now,
  }) : _service = service,
       _now = now ?? DateTime.now,
       _file = File('${service.filesDir}/voice/status');

  Future<SpeechAvailability> query() {
    final checkedAt = _checkedAt;
    if (checkedAt != null) {
      final age = _now().difference(checkedAt);
      if (age >= Duration.zero && age < _ttl) {
        return Future.value(_selection(_lastKnown!));
      }
    }
    return _pending ??= _refresh().whenComplete(() => _pending = null);
  }

  Future<SpeechAvailability> _refresh() async {
    bool? enabled;
    try {
      enabled = await _service.fetchStatus();
    } on SpeechException {
      _lastKnown ??= await _readCache();
      return _selection(_lastKnown ?? false);
    }
    if (enabled == null) {
      return const SpeechAvailability(SpeechEngineKind.none);
    }
    _lastKnown = enabled;
    _checkedAt = _now();
    try {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString('$enabled', flush: true);
      await temporary.rename(_file.path);
    } on FileSystemException {
      // A successful response still updates the in-memory result.
    }
    return _selection(enabled);
  }

  Future<bool?> _readCache() async {
    try {
      return switch (await _file.readAsString()) {
        'true' => true,
        'false' => false,
        _ => null,
      };
    } on FileSystemException {
      return null;
    }
  }

  SpeechAvailability _selection(bool enabled) => SpeechAvailability(
    enabled ? SpeechEngineKind.tencent : SpeechEngineKind.none,
  );
}
