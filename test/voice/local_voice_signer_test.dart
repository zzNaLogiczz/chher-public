import 'dart:math';

import 'package:chh_app/voice/voice_service_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _appId = '1259221234';
const _secretId = 'fixture-id';
const _secretKey = 'fixture-key-11';
const _engine = '16k_zh_en_2.0';
const _timestamp = 1795651200;

void main() {
  test('local voice URL matches the server golden sample byte for byte', () {
    final url = buildLocalVoiceUrl(
      appId: _appId,
      secretId: _secretId,
      secretKey: _secretKey,
      engine: _engine,
      timestamp: _timestamp,
      expired: 1795651290,
      nonce: 1234567890,
      voiceId: 'fixture-voice-id',
    );
    expect(
      url,
      'wss://asr.cloud.tencent.com/asr/v2/1259221234?engine_model_type=16k_zh_en_2.0'
      '&expired=1795651290&needvad=1&nonce=1234567890&secretid=fixture-id&timestamp=1795651200'
      '&voice_format=1&voice_id=fixture-voice-id&signature=Agl6%2Bxop9RXOeKGx5a%2FCn8bWbdw%3D',
    );
  });

  test(
    'local signer signs each ticket with fresh randomness and time',
    () async {
      var now = DateTime.fromMillisecondsSinceEpoch(_timestamp * 1000 + 999);
      final signer = LocalVoiceSigner.tryCreate(
        appId: _appId,
        secretId: _secretId,
        secretKey: _secretKey,
        engine: '',
        now: () => now,
        random: Random(1),
      )!;
      Future<Map<String, String>> next() async =>
          Uri.parse((await signer.fetchTicket()).url).queryParameters;

      final first = await next();
      final second = await next();
      now = now.add(const Duration(minutes: 10));
      final nextSession = await next();
      for (final ticket in [first, second, nextSession]) {
        expect(ticket['engine_model_type'], _engine);
        expect(ticket['secretid'], _secretId);
        expect(ticket['voice_id'], matches(r'^[0-9a-f]{32}$'));
        expect(int.parse(ticket['nonce']!), inInclusiveRange(1, 4294967296));
        expect(
          int.parse(ticket['expired']!) - int.parse(ticket['timestamp']!),
          Duration.secondsPerDay,
        );
        expect(ticket['signature'], isNotEmpty);
      }
      expect(second['nonce'], isNot(first['nonce']));
      expect(second['voice_id'], isNot(first['voice_id']));
      expect(second['signature'], isNot(first['signature']));
      expect(first['timestamp'], '$_timestamp');
      expect(second['timestamp'], '$_timestamp');
      expect(nextSession['timestamp'], '${_timestamp + 600}');
    },
  );

  test(
    'local signer requires three valid keys and a valid optional engine',
    () async {
      for (final (appId, secretId, secretKey, engine) in [
        ('', '', '', ''),
        ('', _secretId, _secretKey, _engine),
        (_appId, '', _secretKey, _engine),
        (_appId, _secretId, '', _engine),
        ('12a34', _secretId, _secretKey, _engine),
        (_appId, '\n$_secretId', _secretKey, _engine),
        (_appId, _secretId, '$_secretKey\n', _engine),
        (_appId, _secretId, _secretKey, '$_engine/'),
      ]) {
        expect(
          LocalVoiceSigner.tryCreate(
            appId: appId,
            secretId: secretId,
            secretKey: secretKey,
            engine: engine,
          ),
          isNull,
        );
      }
      const model = 'Hy-ASR-3.0_preview~fixture';
      final signer = LocalVoiceSigner.tryCreate(
        appId: _appId,
        secretId: _secretId,
        secretKey: _secretKey,
        engine: model,
      )!;
      expect(
        Uri.parse(
          (await signer.fetchTicket()).url,
        ).queryParameters['engine_model_type'],
        model,
      );
    },
  );
}
