import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_capture.dart';
import 'speech_engine.dart';
import 'voice_service_client.dart';

typedef VoiceSocketConnector = Future<WebSocket> Function(Uri);

class TencentAsrEngine implements SpeechEngine {
  static const _frameTime = Duration(milliseconds: 40);
  static const _frameSize = 1280;
  static const _preHandshakeFrames = 75;
  static const _ticketLimit = Duration(seconds: 5);
  static const _handshakeLimit = Duration(seconds: 6);

  final VoiceTicketSource _tickets;
  final AudioCapture _audio;
  final VoiceSocketConnector? _connect;
  final SpeechClock _clock;

  final _text = StreamController<SpeechText>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _errors = StreamController<SpeechErrorKind>.broadcast();
  final _ready = Completer<void>();
  final _done = Completer<void>();

  final _frames = Queue<Uint8List>();
  Uint8List _partial = Uint8List(_frameSize);
  int _partialLength = 0;
  bool _discardedOddByte = false;

  final _finalized = SplayTreeMap<int, String>();
  int? _interimIndex;
  String _interim = '';

  StreamSubscription<Uint8List>? _audioSubscription;
  HttpClient? _upgradeClient;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _handshakeTimer;
  Timer? _ticketTimer;
  Timer? _sendTimer;
  Timer? _finalTimer;
  Duration? _handshakeDeadline;
  Duration _nextSendAt = Duration.zero;
  Future<void>? _audioStop;

  bool _started = false;
  bool _handshaken = false;
  bool _retried = false;
  bool _stopping = false;
  bool _recordingStopped = false;
  bool _endSent = false;
  bool _closed = false;

  TencentAsrEngine({
    required this._tickets,
    required this._audio,
    this._connect,
    SpeechClock? clock,
  }) : _clock = clock ?? SystemSpeechClock();

  @override
  SpeechAvailability get availability =>
      const SpeechAvailability(SpeechEngineKind.tencent);
  @override
  Stream<SpeechText> get text => _text.stream;
  @override
  Stream<double> get volume => _volume.stream;
  @override
  Stream<SpeechErrorKind> get errors => _errors.stream;
  @override
  Future<void> get done => _done.future;

  @override
  Future<void> start() {
    if (_started || _closed) return _ready.future;
    _started = true;
    unawaited(_beginCapture());
    return _ready.future;
  }

  Future<void> _beginCapture() async {
    try {
      final pcm = await _audio.start();
      if (_closed) return;
      _audioSubscription = pcm.listen(
        _record,
        onError: (Object error) => _fail(error, SpeechErrorKind.service),
        onDone: () => unawaited(stop()),
      );
      _handshakeDeadline = _clock.elapsed + _handshakeLimit;
      _handshakeTimer = _clock.schedule(_handshakeLimit, _networkFailure);
      unawaited(_open());
    } catch (error) {
      _fail(error, SpeechErrorKind.service);
    }
  }

  Future<void> _open() async {
    final ticketDeadline = _clock.elapsed + _ticketLimit;
    final Uri? address;
    _ticketTimer = _clock.schedule(_ticketLimit, _ticketFailure);
    try {
      final ticket = await _tickets.fetchTicket();
      if (_closed) return;
      if (_handshakeExpired) return _networkFailure();
      if (_clock.elapsed >= ticketDeadline) return _ticketFailure();
      address = _trustedAddress(ticket.url);
    } catch (_) {
      return _ticketFailure();
    } finally {
      _ticketTimer?.cancel();
    }
    if (address == null) return _ticketFailure();

    try {
      final socket = await (_connect ?? _connectTencent)(address);
      if (_closed) {
        await socket.close();
        return;
      }
      _socket = socket;
      if (_handshakeExpired) return _networkFailure();
      _socketSubscription = socket.listen(
        (message) {
          if (_socket == socket) _receive(message);
        },
        onError: (Object _) {
          if (_socket == socket) _networkFailure();
        },
        onDone: () {
          if (_socket == socket) _networkFailure();
        },
      );
    } catch (_) {
      _networkFailure();
    }
  }

  bool get _handshakeExpired => _clock.elapsed >= _handshakeDeadline!;

  static Uri? _trustedAddress(String value) {
    const prefix = 'wss://asr.cloud.tencent.com/asr/v2/';
    if (!value.startsWith(prefix)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'wss' ||
        uri.authority != 'asr.cloud.tencent.com' ||
        !uri.path.startsWith('/asr/v2/') ||
        uri.pathSegments.length != 3 ||
        uri.pathSegments.last.isEmpty ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }

  void _receive(dynamic message) {
    if (!_handshaken && _handshakeExpired) return _networkFailure();
    try {
      final response = jsonDecode(message as String) as Map<String, dynamic>;
      final code = response['code'] as int;
      if (code != 0) {
        _handleCode(code);
        return;
      }
      if (!_handshaken) {
        _handshaken = true;
        _handshakeTimer?.cancel();
        _nextSendAt = _clock.elapsed + _frameTime;
        _ready.complete();
        _pump();
      }
      final result = response['result'];
      if (result is Map<String, dynamic>) _acceptText(result);
      if (response['final'] == 1) _finish();
    } catch (_) {
      _networkFailure();
    }
  }

  void _handleCode(int code) {
    if (code == 4008) {
      _finish();
      return;
    }
    final canRetry = code == 4002 || (code >= 5000 && code <= 5002);
    if (canRetry && !_handshaken && !_retried) {
      _retried = true;
      unawaited(_disconnect());
      unawaited(_open());
      return;
    }
    _finish(
      error: switch (code) {
        4006 => SpeechErrorKind.busy,
        >= 4001 && <= 4005 || >= 5000 && <= 5002 => SpeechErrorKind.service,
        _ => SpeechErrorKind.network,
      },
    );
  }

  void _acceptText(Map<String, dynamic> result) {
    final index = result['index'] as int;
    final slice = result['slice_type'] as int;
    final value = result['voice_text_str'] as String;
    switch (slice) {
      case 0 || 1:
        if (_finalized.containsKey(index) || index < (_interimIndex ?? 0)) {
          return;
        }
        _interimIndex = index;
        _interim = value;
      case 2:
        _finalized[index] = value;
        if (_interimIndex == index) {
          _interimIndex = null;
          _interim = '';
        }
      default:
        return;
    }
    _text.add(_snapshot());
  }

  SpeechText _snapshot() => SpeechText(
    finalized: _finalized.values.fold('', joinSpeechText),
    interim: _interim,
  );

  void _record(Uint8List chunk) {
    if (_closed || _recordingStopped || chunk.isEmpty) return;
    var offset = 0;
    if (_discardedOddByte) {
      offset = 1;
      _discardedOddByte = false;
    }
    while (offset < chunk.length) {
      if (!_handshaken && _frames.length >= _preHandshakeFrames) {
        // Discard complete samples, even if the plugin emits odd-sized chunks.
        _discardedOddByte = (chunk.length - offset).isOdd;
        break;
      }
      final count = math.min(
        _frameSize - _partialLength,
        chunk.length - offset,
      );
      _partial.setRange(_partialLength, _partialLength + count, chunk, offset);
      _partialLength += count;
      offset += count;
      if (_partialLength == _frameSize) _queueFrame();
    }
    _pump();
  }

  void _queueFrame() {
    _volume.add(_pcmFrameVolume(_partial));
    _frames.add(_partial);
    _partial = Uint8List(_frameSize);
    _partialLength = 0;
  }

  void _pump() {
    if (_closed || !_handshaken || _endSent || _sendTimer != null) return;
    if (_frames.isNotEmpty) {
      final delay = _nextSendAt - _clock.elapsed;
      _sendTimer = _clock.schedule(
        delay.isNegative ? Duration.zero : delay,
        _sendFrame,
      );
    } else if (_recordingStopped) {
      _sendEnd();
    }
  }

  void _sendFrame() {
    _sendTimer = null;
    if (_closed) return;
    try {
      if (_clock.elapsed >= _nextSendAt) {
        _socket!.add(_frames.removeFirst());
        _nextSendAt = _clock.elapsed + _frameTime;
      }
      _pump();
    } catch (_) {
      _networkFailure();
    }
  }

  void _sendEnd() {
    _endSent = true;
    try {
      _socket!.add('{"type":"end"}');
      _finalTimer = _clock.schedule(const Duration(seconds: 4), _finish);
    } catch (_) {
      _networkFailure();
    }
  }

  @override
  Future<void> stop() {
    if (_closed || _stopping) return done;
    if (_audioSubscription == null) {
      _finish();
      return done;
    }
    _stopping = true;
    _audioStop = _stopCapture();
    return done;
  }

  Future<void> _stopCapture() async {
    try {
      await Future.sync(_audio.stop);
      if (_closed) return;
      _recordingStopped = true;
      if (_partialLength > 0) _queueFrame();
      _pump();
    } catch (error) {
      _fail(error, SpeechErrorKind.service);
    }
  }

  @override
  Future<void> cancel() {
    _finish(discard: true);
    return done;
  }

  void _networkFailure() => _finish(error: SpeechErrorKind.network);

  void _ticketFailure() => _finish(error: SpeechErrorKind.service);

  void _fail(Object error, SpeechErrorKind fallback) =>
      _finish(error: error is SpeechException ? error.kind : fallback);

  void _finish({SpeechErrorKind? error, bool discard = false}) {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    _ticketTimer?.cancel();
    _sendTimer?.cancel();
    _finalTimer?.cancel();
    _upgradeClient?.close(force: true);
    _frames.clear();
    _partial = Uint8List(0);
    if (discard) {
      _finalized.clear();
      _interim = '';
      _text.add(_snapshot());
    } else if (error == null && _interim.isNotEmpty) {
      final combined = _snapshot().combined;
      _interim = '';
      _text.add(SpeechText(finalized: combined, interim: ''));
    }
    if (error != null) _errors.add(error);
    if (!_ready.isCompleted) _ready.complete();
    unawaited(_text.close());
    unawaited(_volume.close());
    unawaited(_errors.close());
    unawaited(_cleanup());
  }

  Future<void> _disconnect() async {
    final socket = _socket;
    final subscription = _socketSubscription;
    _socket = null;
    _socketSubscription = null;
    try {
      await socket?.close();
    } catch (_) {
      // The connection may already have ended.
    } finally {
      try {
        await subscription?.cancel();
      } catch (_) {
        // The subscription may already have ended.
      }
    }
  }

  Future<void> _cleanup() async {
    try {
      await Future.wait([
        _disconnect(),
        if (_audioSubscription case final subscription?) subscription.cancel(),
        if (_started) _audioStop ?? Future.sync(_audio.cancel),
      ]);
    } catch (_) {
      // A failed dependency is already represented by the terminal event.
    } finally {
      _done.complete();
    }
  }

  Future<WebSocket> _connectTencent(Uri address) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    _upgradeClient = client;
    try {
      return await WebSocket.connect(
        address.toString(),
        customClient: _DirectUpgradeClient(client),
        compression: CompressionOptions.compressionOff,
      );
    } finally {
      _upgradeClient = null;
      client.close(force: true);
    }
  }
}

double _pcmFrameVolume(Uint8List pcm) {
  final data = ByteData.sublistView(pcm);
  final samples = data.lengthInBytes ~/ 2;
  double total = 0;
  for (var i = 0; i < samples; i++) {
    final normalized = data.getInt16(i * 2, Endian.little) / 32768;
    total += normalized * normalized;
  }
  if (total == 0) return 0;
  final db = 10 * math.log(total / samples) / math.ln10;
  return ((db + 50) / 40).clamp(0.0, 1.0);
}

/// WebSocket.connect uses HttpClient.openUrl for the upgrade. Do not let the
/// HTTP client follow redirects with the signed ticket in the request.
class _DirectUpgradeClient implements HttpClient {
  final HttpClient _client;
  _DirectUpgradeClient(this._client);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      (await _client.openUrl(method, url))..followRedirects = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
