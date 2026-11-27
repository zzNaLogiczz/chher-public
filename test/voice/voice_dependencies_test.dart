import 'dart:async';
import 'dart:io';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/voice/audio_capture.dart';
import 'package:chh_app/voice/speech_engine.dart';
import 'package:chh_app/voice/tencent_asr_engine.dart';
import 'package:chh_app/voice/voice_availability.dart';
import 'package:chh_app/voice/voice_service_client.dart';
import 'package:chh_app/widgets/composer/composer_dictation_binding.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/widgets/composer/dictation_controller.dart';
import 'package:chh_app/widgets/composer/smiley_editing_controller.dart';
import 'package:chh_app/widgets/composer/voice_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('chh/update');

  tearDown(() {
    voiceOverridesForTesting = null;
    localVoiceSignerForTesting = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'local signing retries with a fresh URL without update or voice API calls',
    () async {
      var platformCalls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        platformCalls++;
        throw MissingPluginException();
      });
      localVoiceSignerForTesting = LocalVoiceSigner.tryCreate(
        appId: '1234',
        secretId: 'fixture-id',
        secretKey: 'fixture-key',
      )!;
      var httpClients = 0;
      final addresses = <Uri>[];
      final peers = [_Peer(4002), _Peer(0)];
      await HttpOverrides.runZoned(
        () async {
          final availability = await queryVoiceAvailability();
          expect(availability.kind, SpeechEngineKind.tencent);
          expect(addresses, isEmpty);
          final engine = createSpeechEngine(
            availability.kind,
            audio: _Audio(),
            connect: (address) async {
              addresses.add(address);
              return peers[addresses.length - 1];
            },
          );
          final errors = engine.errors.toList();
          await engine.start();
          expect(addresses, hasLength(2));
          expect(addresses.map((url) => url.host).toSet(), {
            'asr.cloud.tencent.com',
          });
          expect(
            addresses.map((url) => url.queryParameters['voice_id']).toSet(),
            hasLength(2),
          );
          expect(
            addresses.map((url) => url.queryParameters['signature']).toSet(),
            hasLength(2),
          );
          await engine.cancel();
          expect(await errors, isEmpty);
        },
        createHttpClient: (_) {
          httpClients++;
          throw StateError('Unexpected HTTP request');
        },
      );
      expect(platformCalls, 0);
      expect(httpClients, 0);
    },
  );

  test(
    'uses the app identity once for concurrent unconfigured queries',
    () async {
      var identityRequests = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'appInfo');
        identityRequests++;
        return {
          'packageName': 'com.chhreader.chh_app.preview',
          'filesDir': '/unused-preview-support',
        };
      });

      final results = await Future.wait([
        queryVoiceAvailability(),
        queryVoiceAvailability(),
      ]);
      expect(results.map((value) => value.kind), [
        SpeechEngineKind.none,
        SpeechEngineKind.none,
      ]);
      expect(identityRequests, 1);
      expect(() => createSpeechEngine(results.first.kind), throwsStateError);
    },
  );

  for (final (build, release, package) in [
    ('debug without a package name', false, null),
    ('debug', false, 'com.chhreader.chh_app'),
    ('preview release', true, 'com.chhreader.chh_app.preview'),
    ('official release', true, 'com.chhreader.chh_app'),
    ('renamed release', true, 'example.renamed'),
  ]) {
    testWidgets('$build without endpoints or local keys hides the voice bar', (
      tester,
    ) async {
      expect(LocalVoiceSigner.tryCreate(), isNull);
      final files = Directory.systemTemp.createTempSync('voice-unconfigured');
      addTearDown(() => files.deleteSync(recursive: true));
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'appInfo');
        return {'packageName': package, 'filesDir': files.path};
      });

      final selection = await tester.runAsync(() async {
        final service = (await loadVoiceService(isRelease: release))!;
        return VoiceAvailability(service: service).query();
      });
      expect(selection?.kind, SpeechEngineKind.none);

      final rig = await _openComposer(tester, query: () async => selection!);
      expect(rig.statusQueries, 1);
      expect(find.byType(ComposerToolStrip), findsOneWidget);
      expect(find.byType(VoiceBar), findsNothing);
      expect(find.bySemanticsLabel('语音输入'), findsNothing);
      expect(rig.tickets.calls, 0);
    });
  }

  for (final minutes in [10, 120]) {
    testWidgets(
      'opening the composer does not fetch tickets; after $minutes minutes each press fetches one fresh ticket',
      (tester) async {
        final rig = await _openComposer(tester);
        expect(rig.statusQueries, 1);
        expect(rig.tickets.calls, 0);
        await tester.pump(Duration(minutes: minutes));
        expect(rig.tickets.calls, 0);

        await rig.press(tester);
        expect(rig.tickets.calls, 1);
        expect(rig.binding.controller.value.phase, DictationPhase.locked);
        await rig.finish(tester);

        await rig.press(tester);
        expect(rig.tickets.calls, 2);
        expect(rig.binding.controller.value.phase, DictationPhase.locked);
        expect(rig.addresses.map((url) => url.queryParameters['voice_id']), [
          '1',
          '2',
        ]);
        expect(rig.statusQueries, 1);
        await rig.finish(tester);
      },
    );
  }

  testWidgets(
    'a ticket error is announced and pressing again fetches a fresh ticket',
    (tester) async {
      final rig = await _openComposer(tester);
      rig.tickets.failNext = true;
      await rig.press(tester);
      await tester.pumpAndSettle();

      const label = '语音识别暂不可用';
      final status = find.bySemanticsLabel(label);
      expect(find.text(label), findsOneWidget);
      expect(
        tester
            .getSemantics(status)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(find.bySemanticsLabel('语音输入'), findsOneWidget);
      expect(
        rig.binding.controller.value.phase,
        DictationPhase.errorUnavailable,
      );
      expect(rig.tickets.calls, 1);
      expect(rig.addresses, isEmpty);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text(label), findsOneWidget);

      await rig.press(tester);
      expect(find.text(label), findsNothing);
      expect(rig.tickets.calls, 2);
      expect(rig.addresses.single.queryParameters['voice_id'], '2');
      expect(rig.binding.controller.value.phase, DictationPhase.locked);
      expect(rig.statusQueries, 1);
      await rig.finish(tester);
    },
  );

  testWidgets('a second 4002 shows unavailable and leaves the voice bar', (
    tester,
  ) async {
    final rig = await _openComposer(tester, codes: [4002, 4002]);
    await rig.press(tester);
    await tester.pumpAndSettle();
    expect(rig.tickets.calls, 2);
    expect(rig.addresses.map((url) => url.queryParameters['voice_id']), [
      '1',
      '2',
    ]);
    expect(find.text('语音识别暂不可用'), findsOneWidget);
    expect(find.bySemanticsLabel('语音输入'), findsOneWidget);
  });

  test('asks the platform to open application settings', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return true;
    });

    await openVoiceSettings();

    expect(methods, ['openAppSettings']);
  });
}

Future<_ComposerRig> _openComposer(
  WidgetTester tester, {
  List<int> codes = const [0, 0],
  Future<SpeechAvailability> Function()? query,
}) async {
  final rig = _ComposerRig();
  voiceOverridesForTesting = (
    query: () async {
      rig.statusQueries++;
      if (query != null) return query();
      return const SpeechAvailability(SpeechEngineKind.tencent);
    },
    create: (_) => TencentAsrEngine(
      tickets: rig.tickets,
      audio: _Audio(),
      connect: (address) async {
        rig.addresses.add(address);
        return rig.peer = _Peer(codes[rig.addresses.length - 1]);
      },
    ),
  );
  final editor = SmileyEditingController();
  final revision = ValueNotifier(0);
  rig.binding = ComposerDictationBinding(
    editor: editor,
    onChanged: () => revision.value++,
  );
  addTearDown(() {
    rig.binding.dispose();
    revision.dispose();
    editor.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light, AppearanceStyle.misty),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 390,
            child: ListenableBuilder(
              listenable: revision,
              builder: (_, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  rig.binding.status(enabled: true),
                  ComposerToolStrip(
                    voice: rig.binding.bar(enabled: true),
                    voiceActive: rig.binding.barExpanded,
                    send: const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return rig;
}

class _ComposerRig {
  final tickets = _Tickets();
  final addresses = <Uri>[];
  late ComposerDictationBinding binding;
  late _Peer peer;
  int statusQueries = 0;

  Future<void> press(WidgetTester tester) async {
    await tester.tap(find.byType(VoiceBar));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    peer.incoming.add(
      '{"code":0,"final":1,"result":{"slice_type":2,"index":0,"voice_text_str":"听写"}}',
    );
    await tester.pumpAndSettle();
    expect(binding.controller.value.phase, DictationPhase.review);
  }
}

class _Tickets implements VoiceTicketSource {
  int calls = 0;
  bool failNext = false;

  @override
  Future<VoiceTicket> fetchTicket() async {
    calls++;
    if (failNext) {
      failNext = false;
      throw const SpeechException(SpeechErrorKind.service);
    }
    return VoiceTicket.forTesting(
      'wss://asr.cloud.tencent.com/asr/v2/123?voice_id=$calls',
    );
  }
}

class _Audio implements AudioCapture {
  final _pcm = StreamController<Uint8List>();

  @override
  Future<Stream<Uint8List>> start() async => _pcm.stream;
  @override
  Future<void> stop() => _pcm.close();
  @override
  Future<void> cancel() => _pcm.close();
}

class _Peer extends Fake implements WebSocket {
  final incoming = StreamController<dynamic>();

  _Peer(int code) {
    incoming.add('{"code":$code}');
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<void> close([int? code, String? reason]) => incoming.close();
}
