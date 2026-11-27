import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/voice/audio_capture.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/voice/tencent_asr_engine.dart';
import 'package:chh_app/voice/voice_service_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _ticketPrefix = 'wss://asr.cloud.tencent.com/asr/v2/1234';
const _frameInterval = Duration(milliseconds: 40);
const _millisecond = Duration(milliseconds: 1);

void main() {
  test(
    'waits past both deadlines for permission and recognizes buffered PCM',
    () async {
      final ticket = Completer<VoiceTicket>();
      final session = await _Session.open(readTicket: (_) => ticket.future);
      final permission = Completer<bool>();
      session.audio.permission = permission.future;
      var started = false;
      final starting = session.engine.start().then((_) => started = true);
      expect(session.audio.starts, 1);
      expect(session.clock._scheduled, isEmpty);
      session.clock.advance(const Duration(seconds: 20));
      expect(session.ticketCalls, 0);
      expect(session.requestedUrls, isEmpty);
      expect(session.errors, isEmpty);
      expect(started, isFalse);

      permission.complete(true);
      await _until(
        () => session.audio.pcm.hasListener && session.ticketCalls == 1,
      );
      session.audio.pcm.add(_pcm(42));
      expect(session.requestedUrls, isEmpty);
      expect(started, isFalse);

      ticket.complete(
        const VoiceTicket.forTesting('$_ticketPrefix?voice_id=1'),
      );
      final peer = await session.connection(0);
      session.clock.advance(const Duration(seconds: 1));
      expect(peer.received, isEmpty);
      expect(started, isFalse);

      peer.acknowledge();
      await starting;
      session.clock.advance(_frameInterval);
      await peer.waitForMessages(1);
      expect(peer.received.single, orderedEquals(_pcm(42)));
      peer.slice(2, 0, '缓冲语音');
      await _until(() => session.texts.isNotEmpty);
      expect(session.texts.single.combined, '缓冲语音');
      expect(session.engine.availability.kind, SpeechEngineKind.tencent);
      expect(session.errors, isEmpty);
      await session.engine.cancel();
    },
  );

  test(
    'bounds ticket fetch to five seconds and handshake to six overall',
    () async {
      final ticket = Completer<VoiceTicket>();
      final waitingForTicket = await _Session.open(
        readTicket: (_) => ticket.future,
      );
      final ticketStartup = waitingForTicket.engine.start();
      await _until(() => waitingForTicket.ticketCalls == 1);
      waitingForTicket.clock.advance(const Duration(milliseconds: 4999));
      expect(waitingForTicket.errors, isEmpty);
      waitingForTicket.clock.advance(_millisecond);
      await ticketStartup;
      await waitingForTicket.engine.done;
      expect(waitingForTicket.errors, [SpeechErrorKind.service]);
      expect(waitingForTicket.requestedUrls, isEmpty);

      final waitingForHandshake = await _Session.open();
      final handshakeStartup = waitingForHandshake.engine.start();
      final peer = await waitingForHandshake.connection(0);
      waitingForHandshake.clock.advance(const Duration(milliseconds: 5999));
      expect(waitingForHandshake.errors, isEmpty);
      waitingForHandshake.clock.advance(const Duration(milliseconds: 2));
      await handshakeStartup;
      await waitingForHandshake.engine.done;
      expect(waitingForHandshake.errors, [SpeechErrorKind.network]);
      expect(peer.received, isEmpty);
    },
  );

  test(
    'keeps only three seconds before handshake and drains at 1:1 pace',
    () async {
      final session = await _Session.open();
      final starting = session.engine.start();
      final peer = await session.connection(0);
      await _until(() => session.audio.pcm.hasListener);

      for (var index = 0; index < 80; index++) {
        final frame = _pcm(index + 100);
        session.audio.pcm.add(Uint8List.sublistView(frame, 0, 357));
        session.audio.pcm.add(Uint8List.sublistView(frame, 357));
      }
      expect(peer.received, isEmpty);
      peer.acknowledge();
      await starting;

      final stopping = session.engine.stop();
      await _until(() => session.audio.stops == 1);
      for (var index = 0; index < 75; index++) {
        final due = index == 12
            ? const Duration(milliseconds: 210)
            : _frameInterval;
        session.clock.advance(due);
        await peer.waitForMessages(index + 1);
        final frame = peer.received[index];
        expect(frame, isA<List<int>>());
        expect(frame, orderedEquals(_pcm(index + 100)));
      }
      final arrivalTimes = peer.arrivalTimes.take(75).toList();
      for (final (index, at) in arrivalTimes.indexed) {
        if (index > 0) {
          expect(
            at - arrivalTimes[index - 1],
            greaterThanOrEqualTo(_frameInterval),
          );
        }
        final window = arrivalTimes
            .skip(index)
            .takeWhile((next) => next - at < const Duration(seconds: 1));
        expect(window.length, lessThanOrEqualTo(25));
      }

      await peer.waitForMessages(76);
      expect(jsonDecode(peer.received.last as String), {'type': 'end'});
      peer.finalize();
      await stopping;
      expect(session.errors, isEmpty);
    },
  );

  test('revises slice 0/1 and joins slice 2 in index order', () async {
    final session = await _Session.open();
    final peer = await session.start();
    final slices = [
      (0, 1, '45', '', '45', '45'),
      (1, 1, '456', '', '456', '456'),
      (2, 1, '456', '456', '', '456'),
      (0, 0, 'RT', '456', 'RT', '456 RT'),
      (2, 0, 'RTX', 'RTX 456', '', 'RTX 456'),
      (1, 2, '显', 'RTX 456', '显', 'RTX 456显'),
      (2, 2, '显卡', 'RTX 456显卡', '', 'RTX 456显卡'),
      (2, 3, 'GTX', 'RTX 456显卡GTX', '', 'RTX 456显卡GTX'),
    ];
    for (final (index, slice) in slices.indexed) {
      final (type, sentence, text, finalized, interim, combined) = slice;
      peer.slice(type, sentence, text);
      await _until(() => session.texts.length > index);
      final event = session.texts[index];
      expect(event.finalized, finalized);
      expect(event.interim, interim);
      expect(event.combined, combined);
    }
    peer.finalize();
    await session.engine.done;
    expect(session.errors, isEmpty);
  });

  test(
    'stop pads trailing PCM, sends end after audio and waits for final',
    () async {
      final session = await _Session.open();
      final peer = await session.start();
      await _until(() => session.audio.pcm.hasListener);
      session.audio.pcm.add(Uint8List.fromList([1, 2, 3, 4]));
      var stopped = false;
      final stopping = session.engine.stop().then((_) => stopped = true);
      await _until(
        () => session.audio.stops == 1 && session.volumes.isNotEmpty,
      );
      session.clock.advance(_frameInterval);
      await peer.waitForMessages(2);
      expect(
        peer.received.first,
        orderedEquals([1, 2, 3, 4, ...List.filled(1276, 0)]),
      );
      expect(jsonDecode(peer.received.last as String), {'type': 'end'});
      expect(stopped, isFalse);

      peer.send(
        jsonEncode({
          'code': 0,
          'result': {'slice_type': 2, 'index': 0, 'voice_text_str': '完成'},
          'final': 1,
        }),
      );
      await stopping;
      await peer.closed.future;
      expect(session.texts.last.combined, '完成');
      expect(session.errors, isEmpty);
    },
  );

  test(
    'stop times out four seconds after end and preserves recognized text',
    () async {
      final session = await _Session.open();
      final peer = await session.start();
      peer.slice(2, 0, '定稿');
      await _until(() => session.texts.isNotEmpty);
      var stopped = false;
      final stopping = session.engine.stop().then((_) => stopped = true);
      await peer.waitForMessages(1);
      expect(jsonDecode(peer.received.single as String), {'type': 'end'});
      session.clock.advance(const Duration(milliseconds: 3999));
      expect(stopped, isFalse);
      session.clock.advance(_millisecond);
      await stopping;
      await peer.closed.future;
      expect(session.texts.last.combined, '定稿');
      expect(session.errors, isEmpty);
    },
  );

  test('cancel closes without end while the handshake is pending', () async {
    final session = await _Session.open();
    final starting = session.engine.start();
    final peer = await session.connection(0);
    await session.engine.cancel();
    await starting;
    await peer.closed.future;
    expect(peer.received, isEmpty);
    expect(session.audio.cancels, 1);
    expect(session.errors, isEmpty);
  });

  test('cancel discards recognition and queued audio', () async {
    final session = await _Session.open();
    final peer = await session.start();
    peer.slice(1, 0, '丢弃');
    await _until(() => session.texts.isNotEmpty);
    session.audio.pcm.add(_pcm(100));
    await session.engine.cancel();
    await peer.closed.future;
    session.clock.advance(const Duration(seconds: 10));
    expect(peer.received.whereType<String>(), isEmpty);
    expect(session.texts.last.combined, isEmpty);
    expect(session.audio.cancels, 1);
    expect(session.errors, isEmpty);
  });

  test('converts RMS dBFS to a clamped volume for each PCM frame', () async {
    final session = await _Session.open();
    final peer = await session.start();
    await _until(() => session.audio.pcm.hasListener);
    for (final sample in [0, 10, 1036, 10362, 32767]) {
      session.audio.pcm.add(_pcm(sample));
      session.clock.advance(_frameInterval);
    }
    await peer.waitForMessages(5);
    await _until(() => session.volumes.length >= 5);
    expect(session.volumes.take(5), [
      0,
      0,
      closeTo(0.5, 0.001),
      closeTo(1, 0.001),
      1,
    ]);
  });

  for (final (code, error) in [
    (4000, SpeechErrorKind.network),
    (4001, SpeechErrorKind.service),
    (4002, SpeechErrorKind.service),
    (4003, SpeechErrorKind.service),
    (4004, SpeechErrorKind.service),
    (4005, SpeechErrorKind.service),
    (4006, SpeechErrorKind.busy),
    (4007, SpeechErrorKind.network),
    (4009, SpeechErrorKind.network),
    (4010, SpeechErrorKind.network),
    (5000, SpeechErrorKind.service),
    (5001, SpeechErrorKind.service),
    (5002, SpeechErrorKind.service),
    (6001, SpeechErrorKind.network),
  ]) {
    test('ASR code $code emits ${error.name} and preserves text', () async {
      final session = await _Session.open();
      final peer = await session.start();
      peer.slice(2, 0, '定稿');
      peer.slice(1, 1, '临时');
      await _until(() => session.texts.length == 2);
      peer.fail(code);
      await session.engine.done;
      expect(session.errors, [error]);
      expect(session.texts.last.combined, '定稿临时');
      expect(session.ticketCalls, 1);
    });
  }

  test('4008 is a clean server termination', () async {
    final session = await _Session.open();
    final peer = await session.start();
    peer.slice(2, 0, '保留');
    await _until(() => session.texts.isNotEmpty);
    peer.fail(4008);
    await session.engine.done;
    expect(session.errors, isEmpty);
    expect(session.texts.last.combined, '保留');
  });

  for (final code in [4002, 5000, 5001, 5002]) {
    test('handshake code $code fetches a fresh ticket and retries', () async {
      final session = await _Session.open();
      final starting = session.engine.start();
      final first = await session.connection(0);
      first.fail(code);
      final second = await session.connection(1);
      second.acknowledge();
      await starting;
      expect(session.ticketCalls, 2);
      expect(session.audio.starts, 1);
      expect(session.requestedUrls.map((uri) => uri.query), [
        'voice_id=1',
        'voice_id=2',
      ]);
      expect(session.errors, isEmpty);
    });
  }

  for (final (first, second) in [(4002, 4002), (4002, 5000), (5001, 4002)]) {
    test('$first then $second exhausts the shared handshake retry', () async {
      final session = await _Session.open();
      final starting = session.engine.start();
      (await session.connection(0)).fail(first);
      (await session.connection(1)).fail(second);
      await starting;
      await session.engine.done;
      expect(session.ticketCalls, 2);
      expect(session.errors, [SpeechErrorKind.service]);
    });
  }

  test('4002 retry preserves queued PCM and a partial frame', () async {
    final ticket = Completer<VoiceTicket>();
    final session = await _Session.open(
      readTicket: (call) => call == 1
          ? Future.value(
              const VoiceTicket.forTesting('$_ticketPrefix?voice_id=1'),
            )
          : ticket.future,
    );
    final starting = session.engine.start();
    final first = await session.connection(0);
    final crossingFrame = _pcm(27);
    session.audio.pcm.add(_pcm(42));
    session.audio.pcm.add(Uint8List.sublistView(crossingFrame, 0, 141));
    first.fail(4002);
    await first.closed.future;
    expect(session.ticketCalls, 2);
    expect(first.received, isEmpty);
    session.audio.pcm.add(Uint8List.sublistView(crossingFrame, 141));
    session.audio.pcm.add(_pcm(13));

    ticket.complete(const VoiceTicket.forTesting('$_ticketPrefix?voice_id=2'));
    final second = await session.connection(1);
    second.acknowledge();
    await starting;
    for (final (index, sample) in [42, 27, 13].indexed) {
      session.clock.advance(_frameInterval);
      await second.waitForMessages(index + 1);
      expect(second.received[index], orderedEquals(_pcm(sample)));
    }
    expect(session.errors, isEmpty);
  });

  test('retry handshake shares the original six-second deadline', () async {
    final session = await _Session.open();
    final starting = session.engine.start();
    final first = await session.connection(0);
    session.clock.advance(const Duration(seconds: 5));
    first.fail(4002);
    final second = await session.connection(1);
    session.clock.advance(const Duration(seconds: 1));
    await starting;
    await session.engine.done;
    expect(second.received, isEmpty);
    expect(session.ticketCalls, 2);
    expect(session.errors, [SpeechErrorKind.network]);
  });

  test(
    'does not restart a completed handshake before the first text',
    () async {
      final session = await _Session.open();
      final peer = await session.start();
      peer.fail(5000);
      await session.engine.done;
      expect(session.ticketCalls, 1);
      expect(session.errors, [SpeechErrorKind.service]);
    },
  );

  for (final url in [
    'ws://asr.cloud.tencent.com/asr/v2/1234',
    'wss://asr.cloud.tencent.com.example.com/asr/v2/1234',
    'wss://asr.cloud.tencent.com/asr/v1/1234',
    'wss://asr.cloud.tencent.com/asr/v2/../1234',
    'wss://fake@asr.cloud.tencent.com/asr/v2/1234',
    'wss://asr.cloud.tencent.com:9999/asr/v2/1234',
    '$_ticketPrefix#fragment',
  ]) {
    test('rejects invalid ticket URL before connecting: $url', () async {
      final session = await _Session.open(
        readTicket: (_) async => VoiceTicket.forTesting(url),
      );
      await session.engine.start();
      await session.engine.done;
      expect(session.requestedUrls, isEmpty);
      expect(session.errors, [SpeechErrorKind.service]);
    });
  }

  for (final (failure, error) in [
    ('unreachable', const SocketException('fixture')),
    ('timeout', TimeoutException('fixture')),
    ('invalid signature or payload', const FormatException('fixture')),
    ('disabled or missing', const SpeechException(SpeechErrorKind.service)),
    (
      'rate limited or unavailable',
      const SpeechException(SpeechErrorKind.busy),
    ),
    ('transport failure', const SpeechException(SpeechErrorKind.network)),
  ]) {
    test('ticket $failure is service before connecting', () async {
      final session = await _Session.open(readTicket: (_) async => throw error);
      await session.engine.start();
      await session.engine.done;
      expect(session.ticketCalls, 1);
      expect(session.requestedUrls, isEmpty);
      expect(session.errors, [SpeechErrorKind.service]);
    });
  }

  test('failure while fetching a replacement ticket is service', () async {
    final session = await _Session.open(
      readTicket: (call) async {
        if (call == 2) throw const SocketException('fixture');
        return const VoiceTicket.forTesting('$_ticketPrefix?voice_id=1');
      },
    );
    final starting = session.engine.start();
    (await session.connection(0)).fail(4002);
    await starting;
    await session.engine.done;
    expect(session.ticketCalls, 2);
    expect(session.requestedUrls, hasLength(1));
    expect(session.errors, [SpeechErrorKind.service]);
  });

  test('connection failure is network', () async {
    final session = await _Session.open(
      connect: (_) async =>
          throw const SpeechException(SpeechErrorKind.service),
    );
    await session.engine.start();
    await session.engine.done;
    expect(session.errors, [SpeechErrorKind.network]);
  });

  test('unexpected disconnect is network and preserves text', () async {
    final session = await _Session.open();
    final peer = await session.start();
    peer.slice(2, 0, '保留');
    await _until(() => session.texts.isNotEmpty);
    await peer.close();
    await session.engine.done;
    expect(session.texts.last.combined, '保留');
    expect(session.errors, [SpeechErrorKind.network]);
  });

  test('permission rejection ends startup with a permission error', () async {
    final ticket = Completer<VoiceTicket>();
    final session = await _Session.open(readTicket: (_) => ticket.future);
    session.audio.permission = Future.value(false);
    await session.engine.start();
    await session.engine.done;
    expect(session.errors, [SpeechErrorKind.permission]);
    expect(session.ticketCalls, 0);
    expect(session.requestedUrls, isEmpty);
  });

  test(
    'microphone startup failure is service before fetching a ticket',
    () async {
      final session = await _Session.open();
      session.audio.permission = Future.error(StateError('fixture'));
      await session.engine.start();
      await session.engine.done;
      expect(session.errors, [SpeechErrorKind.service]);
      expect(session.ticketCalls, 0);
    },
  );
}

Uint8List _pcm(int sample) {
  final frame = Uint8List(1280);
  final pcm = ByteData.sublistView(frame);
  for (var offset = 0; offset < frame.length; offset += 2) {
    pcm.setInt16(offset, sample, Endian.little);
  }
  return frame;
}

Future<void> _until(bool Function() condition) async {
  final timeout = Stopwatch()..start();
  while (!condition()) {
    if (timeout.elapsed > const Duration(seconds: 3)) {
      fail('Timed out waiting for a fake socket or engine event');
    }
    await Future<void>.delayed(_millisecond);
  }
}

class _Session implements VoiceTicketSource {
  final Future<VoiceTicket> Function(int)? readTicket;
  final audio = _Audio();
  final clock = _Clock();
  final peers = <_Peer>[];
  final requestedUrls = <Uri>[];
  final texts = <SpeechText>[];
  final volumes = <double>[];
  final errors = <SpeechErrorKind>[];
  int ticketCalls = 0;
  late final TencentAsrEngine engine;

  _Session(this.readTicket, VoiceSocketConnector? connect) {
    engine = TencentAsrEngine(
      tickets: this,
      audio: audio,
      clock: clock,
      connect: (url) async {
        requestedUrls.add(url);
        if (connect != null) return connect(url);
        final peer = _Peer(clock, StreamController<dynamic>());
        peers.add(peer);
        return peer;
      },
    );
    engine.text.listen(texts.add);
    engine.volume.listen(volumes.add);
    engine.errors.listen(errors.add);
  }

  static Future<_Session> open({
    Future<VoiceTicket> Function(int)? readTicket,
    VoiceSocketConnector? connect,
  }) async {
    final session = _Session(readTicket, connect);
    addTearDown(session.engine.cancel);
    return session;
  }

  @override
  Future<VoiceTicket> fetchTicket() async {
    final call = ++ticketCalls;
    return readTicket?.call(call) ??
        VoiceTicket.forTesting('$_ticketPrefix?voice_id=$call');
  }

  Future<_Peer> connection(int index) async {
    await _until(() => peers.length > index);
    return peers[index];
  }

  Future<_Peer> start() async {
    final starting = engine.start();
    final peer = await connection(0);
    peer.acknowledge();
    await starting;
    return peer;
  }
}

class _Peer extends StreamView<dynamic> implements WebSocket {
  final SpeechClock clock;
  final StreamController<dynamic> _incoming;
  final received = <Object?>[];
  final arrivalTimes = <Duration>[];
  final closed = Completer<void>();

  _Peer(this.clock, this._incoming) : super(_incoming.stream);

  @override
  void add(dynamic data) {
    arrivalTimes.add(clock.elapsed);
    received.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_incoming.isClosed) return;
    unawaited(_incoming.close());
    closed.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void send(String message) => _incoming.add(message);
  void acknowledge() =>
      send('{"code":0,"message":"success","voice_id":"test"}');
  void finalize() => send('{"code":0,"final":1}');
  void fail(int code) => send(jsonEncode({'code': code}));

  void slice(int type, int index, String text) => send(
    jsonEncode({
      'code': 0,
      'result': {'slice_type': type, 'index': index, 'voice_text_str': text},
    }),
  );

  Future<void> waitForMessages(int count) =>
      _until(() => received.length >= count);
}

class _Audio implements AudioCapture {
  final pcm = StreamController<Uint8List>.broadcast(sync: true);
  Future<bool>? permission;
  int starts = 0;
  int cancels = 0;
  int stops = 0;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    if (await permission == false) {
      throw const SpeechException(SpeechErrorKind.permission);
    }
    return pcm.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    await pcm.close();
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await pcm.close();
  }
}

class _Clock implements SpeechClock {
  @override
  Duration elapsed = Duration.zero;
  final _scheduled = <_Timer>[];

  @override
  Timer schedule(Duration delay, void Function() callback) {
    final timer = _Timer(elapsed + delay, callback);
    _scheduled.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    elapsed += duration;
    // A late timer sees the current monotonic time, including timers it queues.
    while (true) {
      _scheduled.removeWhere((timer) => !timer.isActive);
      _scheduled.sort((left, right) => left.deadline.compareTo(right.deadline));
      if (_scheduled.isEmpty || _scheduled.first.deadline > elapsed) return;
      _scheduled.removeAt(0).fire();
    }
  }
}

class _Timer implements Timer {
  final Duration deadline;
  final void Function() callback;

  @override
  bool isActive = true;

  @override
  int tick = 0;

  _Timer(this.deadline, this.callback);

  @override
  void cancel() => isActive = false;

  void fire() {
    isActive = false;
    tick++;
    callback();
  }
}
