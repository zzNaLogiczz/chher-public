import 'dart:async';

import 'package:chh_app/voice/audio_capture.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/voice/tencent_asr_engine.dart';
import 'package:chh_app/voice/voice_service_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.llfbandit.record/messages');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Completer<bool> permission;
  late Completer<void> permissionRequested;
  late List<MethodChannel> events;

  setUp(() {
    calls = [];
    events = [];
    permission = Completer<bool>();
    permissionRequested = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') {
        final id = call.arguments['recorderId'] as String;
        for (final name in ['events', 'eventsRecord']) {
          final event = MethodChannel('com.llfbandit.record/$name/$id');
          events.add(event);
          messenger.setMockMethodCallHandler(event, (_) async => null);
        }
      }
      if (call.method == 'hasPermission') {
        permissionRequested.complete();
        return permission.future;
      }
      if (call.method == 'isRecording') return false;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    for (final event in events) {
      messenger.setMockMethodCallHandler(event, null);
    }
  });

  test('requests permission on start and opens only a PCM stream', () async {
    final capture = RecordAudioCapture();
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);

    final starting = capture.start();
    await permissionRequested.future;
    expect(calls.last.arguments['request'], true);
    permission.complete(true);
    final stream = await starting;
    final ended = stream.drain<void>();

    final config = calls.singleWhere((call) => call.method == 'startStream');
    expect(config.arguments, containsPair('encoder', 'pcm16bits'));
    expect(config.arguments, containsPair('sampleRate', 16000));
    expect(config.arguments, containsPair('numChannels', 1));
    expect(config.arguments, containsPair('autoGain', false));
    expect(config.arguments, containsPair('echoCancel', false));
    expect(config.arguments, containsPair('noiseSuppress', false));
    expect(
      config.arguments['androidConfig'],
      containsPair('audioSource', 'mic'),
    );
    expect(config.arguments.containsKey('path'), false);

    await capture.stop();
    await ended;
    expect(
      calls.map((call) => call.method),
      containsAllInOrder(['stop', 'dispose']),
    );
  });

  test('denial reaches the engine as a permission error', () async {
    final capture = RecordAudioCapture();
    permission.complete(false);
    await expectLater(
      capture.start(),
      throwsA(
        isA<SpeechException>().having(
          (error) => error.kind,
          'kind',
          SpeechErrorKind.permission,
        ),
      ),
    );
    await expectLater(capture.cancel(), throwsA(isA<SpeechException>()));
    expect(calls.map((call) => call.method), isNot(contains('startStream')));
    expect(calls.last.method, 'dispose');
  });

  for (final cancel in [true, false]) {
    test(
      '${cancel ? 'cancel' : 'stop'} during permission skips network and disposes the recorder',
      () async {
        final tickets = _Tickets();
        var connections = 0;
        final engine = TencentAsrEngine(
          audio: RecordAudioCapture(),
          tickets: tickets,
          connect: (_) async {
            connections++;
            throw StateError('Unexpected WebSocket connection');
          },
        );
        final errors = engine.errors.toList();
        final texts = engine.text.toList();
        final starting = engine.start();
        await permissionRequested.future;
        final terminating = cancel ? engine.cancel() : engine.stop();

        await starting;
        expect(await errors, isEmpty);
        expect((await texts).every((text) => text.combined.isEmpty), isTrue);
        expect(calls.last.method, 'hasPermission');

        permission.complete(true);
        await terminating;
        expect(tickets.calls, 0);
        expect(connections, 0);
        expect(calls.map((call) => call.method), [
          'create',
          'hasPermission',
          'isRecording',
          'dispose',
        ]);
      },
    );
  }
}

class _Tickets implements VoiceTicketSource {
  int calls = 0;

  @override
  Future<VoiceTicket> fetchTicket() async {
    calls++;
    return const VoiceTicket.forTesting(
      'wss://asr.cloud.tencent.com/asr/v2/1234',
    );
  }
}
