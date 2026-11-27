import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/update/update_endpoints.dart';
import 'package:chh_app/update/update_platform.dart';
import 'package:chh_app/update/update_store.dart';
import 'package:chh_app/voice/audio_capture.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/voice/tencent_asr_engine.dart';
import 'package:chh_app/voice/voice_availability.dart';
import 'package:chh_app/voice/voice_service_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _did = '0123456789abcdef0123456789abcdef';
const _url = 'wss://asr.cloud.tencent.com/asr/v2/123?signature=fixture';

class _Platform implements UpdatePlatform {
  var checks = 0;

  @override
  Future<bool> verifySignature(
    Uint8List publicKey,
    Uint8List payload,
    Uint8List signature,
  ) async {
    checks++;
    expect(publicKey, base64Decode(updatePublicKeys['k1']!));
    return utf8.decode(signature) == 'valid';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements HttpClientAdapter {
  final _servers = <String, _Server>{};

  _Server addServer() {
    final origin = 'https://voice-${_servers.length}.example.invalid';
    return _servers[origin] = _Server(origin);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _servers[options.uri.origin]!.reply(options.uri, cancelFuture!);

  @override
  void close({bool force = false}) {}
}

class _Server {
  _Server(this.endpoint);

  final String endpoint;
  final requests = <Uri>[];
  bool enabled = true;
  String signature = 'valid';
  String kid = 'k1';
  String? type;
  String? reason;
  Object issuedAt = 100;
  Object expiresAt = 190;
  Object url = _url;
  int statusCode = 200;
  bool offline = false;
  bool hang = false;
  final cancelled = Completer<void>();

  Future<ResponseBody> reply(Uri uri, Future<void> cancellation) async {
    requests.add(uri);
    if (offline) throw const SocketException('offline');
    if (hang) {
      await cancellation;
      cancelled.complete();
      throw const SocketException('cancelled');
    }
    final ticket = uri.path == '/v1/voice/ticket';
    final payload = {
      'type': type ?? (ticket ? 'voiceTicket' : 'voiceStatus'),
      'issuedAt': issuedAt,
      'enabled': enabled,
      if (ticket && enabled) ...{'url': url, 'expiresAt': expiresAt},
      if (reason != null) 'reason': reason,
    };
    return ResponseBody.fromString(
      jsonEncode({
        'kid': kid,
        'payload': base64Encode(utf8.encode(jsonEncode(payload))),
        'sig': base64Encode(utf8.encode(signature)),
      }),
      statusCode,
    );
  }
}

class _IdleAudio implements AudioCapture {
  final _frames = StreamController<Uint8List>();

  @override
  Future<Stream<Uint8List>> start() async => _frames.stream;

  @override
  Future<void> stop() => _frames.close();

  @override
  Future<void> cancel() => stop();
}

class _HandshakePeer extends StreamView<dynamic> implements WebSocket {
  _HandshakePeer(this._incoming) : super(_incoming.stream);

  final StreamController<dynamic> _incoming;

  @override
  Future<void> close([int? code, String? reason]) => _incoming.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _serviceError = throwsA(
  isA<SpeechException>().having(
    (error) => error.kind,
    'kind',
    SpeechErrorKind.service,
  ),
);

void main() {
  late Directory files;
  late _Platform platform;
  late _Transport transport;
  late DateTime now;
  late UpdateStore store;

  setUp(() async {
    files = await Directory.systemTemp.createTemp('voice-service-test');
    addTearDown(() => files.delete(recursive: true));
    store = UpdateStore.inDirectory(files.path);
    platform = _Platform();
    transport = _Transport();
    now = DateTime.fromMillisecondsSinceEpoch(100000);
  });

  VoiceServiceClient client({
    bool official = true,
    List<String> voice = const [],
    List<String> update = const [],
  }) => VoiceServiceClient(
    filesDir: files.path,
    isOfficial: official,
    platform: platform,
    voiceEndpoints: voice,
    updateEndpoints: update,
    dio: Dio()..httpClientAdapter = transport,
  );

  test(
    'official service tries signed stored endpoints before injected ones',
    () async {
      final stored = transport.addServer();
      final injected = transport.addServer();
      stored.statusCode = HttpStatus.notFound;
      await store.save(
        UpdateState(
          installId: _did,
          endpoints: [' ${stored.endpoint}/ '],
          endpointsIssuedAt: 90,
        ),
      );
      final originalState = await store.file.readAsString();
      final service = client(update: [injected.endpoint]);

      expect(await service.fetchStatus(), isTrue);
      expect((await service.fetchTicket()).url, _url);
      for (final server in [stored, injected]) {
        expect(server.requests.map((uri) => uri.path), [
          '/v1/voice/status',
          '/v1/voice/ticket',
        ]);
        expect(
          server.requests.every((uri) => uri.queryParameters['did'] == _did),
          isTrue,
        );
      }
      expect(platform.checks, 2);
      expect(await store.file.readAsString(), originalState);
    },
  );

  test('explicit voice endpoints take precedence across channels', () async {
    final voice = transport.addServer();
    final update = transport.addServer();
    await store.save(
      UpdateState(
        installId: _did,
        endpoints: [update.endpoint],
        endpointsIssuedAt: 90,
      ),
    );
    for (final official in [true, false]) {
      final service = client(
        official: official,
        voice: [' ${voice.endpoint}/ ', voice.endpoint, 'invalid'],
        update: [update.endpoint],
      );
      expect(await service.fetchStatus(), isTrue);
    }
    expect(update.requests, isEmpty);
    expect(voice.requests, hasLength(2));
  });

  test(
    'preview ignores update endpoints and official ignores unsigned ones',
    () async {
      final server = transport.addServer();
      final stored = UpdateState(installId: _did, endpoints: [server.endpoint]);
      await store.save(stored.copyWith(endpointsIssuedAt: 90));
      final preview = client(official: false, update: [server.endpoint]);
      expect(await preview.fetchStatus(), isNull);
      await expectLater(preview.fetchTicket(), _serviceError);
      await store.save(stored);
      expect(await client().fetchStatus(), isNull);
      expect(server.requests, isEmpty);
    },
  );

  test(
    'voice-only configuration keeps its installation ID across clients',
    () async {
      final server = transport.addServer();
      for (var i = 0; i < 2; i++) {
        expect(await client(voice: [server.endpoint]).fetchStatus(), isTrue);
      }
      final ids = server.requests
          .map((uri) => uri.queryParameters['did'])
          .toSet();
      expect(ids.single, matches(r'^[a-f0-9]{32}$'));
      expect(await store.file.exists(), isFalse);
    },
  );

  test(
    'disabled, quota, non-200 and unreachable ticket responses map to service',
    () async {
      final server = transport.addServer();
      final service = client(voice: [server.endpoint]);
      server.enabled = false;
      expect(await service.fetchStatus(), isFalse);
      for (final reason in ['not_configured', 'quota']) {
        server.reason = reason;
        await expectLater(service.fetchTicket(), _serviceError);
      }
      for (final status in [404, 429, 500, 503]) {
        server.statusCode = status;
        await expectLater(service.fetchTicket(), _serviceError);
      }
      server.offline = true;
      await expectLater(service.fetchTicket(), _serviceError);
    },
  );

  test('untrusted and malformed ticket responses map to service', () async {
    final server = transport.addServer();
    final service = client(voice: [server.endpoint]);
    Future<void> expectServiceError() =>
        expectLater(service.fetchTicket(), _serviceError);
    server.kid = 'unknown';
    await expectServiceError();
    expect(platform.checks, 0);
    server.kid = 'k1';
    server.signature = 'invalid';
    await expectServiceError();
    server.signature = 'valid';
    server.type = 'voiceStatus';
    await expectServiceError();
    server.type = null;
    for (final url in ['', 123]) {
      server.url = url;
      await expectServiceError();
    }
    server.url = _url;
    for (final expired in [99, 100, 190.5, '190']) {
      server.expiresAt = expired;
      await expectServiceError();
    }
    server.expiresAt = 190;
    server.issuedAt = '100';
    await expectServiceError();
  });

  test(
    'ticket has a five-second deadline and cancels the request',
    () async {
      final server = transport.addServer()..hang = true;
      final service = client(voice: [server.endpoint]);
      final stopwatch = Stopwatch()..start();
      await expectLater(service.fetchTicket(), _serviceError);
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(seconds: 5)),
      );
      expect(server.requests.single.path, '/v1/voice/ticket');
      await server.cancelled.future;
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test(
    'signed tickets reach handshake with the phone clock ahead or behind',
    () async {
      final server = transport.addServer();
      final service = client(voice: [server.endpoint]);
      final phoneEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final addresses = <Uri>[];
      for (final skew in [-86400, -3600, 3600, 86400]) {
        // Only the fake server clock shifts. The phone keeps its real clock.
        final issued = phoneEpoch - skew;
        server.issuedAt = issued;
        server.expiresAt = issued + 90;
        final engine = TencentAsrEngine(
          tickets: service,
          audio: _IdleAudio(),
          connect: (address) async {
            addresses.add(address);
            return _HandshakePeer(
              StreamController<dynamic>()..add('{"code":0}'),
            );
          },
        );
        addTearDown(engine.cancel);
        final errors = engine.errors.toList();
        await engine.start();
        await engine.cancel();
        expect(await errors, isEmpty);
      }
      expect(addresses, List.filled(4, Uri.parse(_url)));
      expect(server.requests.map((request) => request.path), [
        for (var i = 0; i < 4; i++) '/v1/voice/ticket',
      ]);
    },
  );

  test('successful status is coalesced and reused for ten minutes', () async {
    final server = transport.addServer();
    final availability = VoiceAvailability(
      service: client(voice: [server.endpoint]),
      now: () => now,
    );
    final firstResult = await Future.wait([
      availability.query(),
      availability.query(),
    ]);
    expect(firstResult.map((result) => result.kind), [
      SpeechEngineKind.tencent,
      SpeechEngineKind.tencent,
    ]);
    expect(server.requests, hasLength(1));
    now = now.add(const Duration(minutes: 9, seconds: 59));
    server.enabled = false;
    expect((await availability.query()).kind, SpeechEngineKind.tencent);
    expect(server.requests, hasLength(1));
    now = now.add(const Duration(seconds: 1));
    expect((await availability.query()).kind, SpeechEngineKind.none);
    expect(server.requests, hasLength(2));
  });

  test(
    'unconfigured status is unavailable and configured failures reuse the last signed result',
    () async {
      final server = transport.addServer();
      final service = client(voice: [server.endpoint]);
      VoiceAvailability fresh() =>
          VoiceAvailability(service: service, now: () => now);
      final availability = fresh();

      server.statusCode = HttpStatus.internalServerError;
      expect((await availability.query()).kind, SpeechEngineKind.none);
      server.statusCode = HttpStatus.ok;
      expect((await availability.query()).kind, SpeechEngineKind.tencent);
      now = now.add(const Duration(minutes: 10));
      server.statusCode = HttpStatus.internalServerError;
      expect((await availability.query()).kind, SpeechEngineKind.tencent);
      expect((await fresh().query()).kind, SpeechEngineKind.tencent);
      expect(
        (await VoiceAvailability(service: client()).query()).kind,
        SpeechEngineKind.none,
      );

      server.statusCode = HttpStatus.ok;
      server.enabled = false;
      expect((await fresh().query()).kind, SpeechEngineKind.none);
      server.statusCode = HttpStatus.internalServerError;
      expect((await fresh().query()).kind, SpeechEngineKind.none);
    },
  );

  test(
    'ticket failure preserves in-memory and persisted availability',
    () async {
      final server = transport.addServer();
      final service = client(voice: [server.endpoint]);
      final availability = VoiceAvailability(service: service, now: () => now);
      final cachedStatus = File('${files.path}/voice/status');
      expect((await availability.query()).kind, SpeechEngineKind.tencent);
      expect(await cachedStatus.readAsString(), 'true');

      server.enabled = false;
      server.reason = 'quota';
      await expectLater(service.fetchTicket(), _serviceError);
      expect((await availability.query()).kind, SpeechEngineKind.tencent);
      expect(await cachedStatus.readAsString(), 'true');
      expect(server.requests.map((request) => request.path), [
        '/v1/voice/status',
        '/v1/voice/ticket',
      ]);
    },
  );
}
