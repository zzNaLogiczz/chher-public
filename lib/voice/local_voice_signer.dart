part of 'voice_service_client.dart';

/// Builds the Tencent ASR address using Go url.Values.Encode query ordering.
String buildLocalVoiceUrl({
  required String appId,
  required String secretId,
  required String secretKey,
  required String engine,
  required int timestamp,
  required int expired,
  required int nonce,
  required String voiceId,
}) {
  final query = Uri(
    queryParameters: {
      'engine_model_type': engine,
      'expired': '$expired',
      'needvad': '1',
      'nonce': '$nonce',
      'secretid': secretId,
      'timestamp': '$timestamp',
      'voice_format': '1',
      'voice_id': voiceId,
    },
  ).query;
  final unsigned = 'asr.cloud.tencent.com/asr/v2/$appId?$query';
  final mac = Hmac(sha1, utf8.encode(secretKey)).convert(utf8.encode(unsigned));
  final signature = Uri.encodeQueryComponent(base64Encode(mac.bytes));
  return 'wss://$unsigned&signature=$signature';
}

final class LocalVoiceSigner implements VoiceTicketSource {
  static final _appIdFormat = RegExp(r'^[0-9]+$');
  static final _tokenFormat = RegExp(r'^[A-Za-z0-9._~-]+$');
  static const _defaultEngine = '16k_zh_en_2.0';

  final String _appId;
  final String _secretId;
  final String _secretKey;
  final String _engine;
  final DateTime Function() _now;
  final Random _random;

  LocalVoiceSigner._(
    this._appId,
    this._secretId,
    this._secretKey,
    this._engine,
    this._now,
    this._random,
  );

  static LocalVoiceSigner? tryCreate({
    String appId = const String.fromEnvironment('CHH_VOICE_APP_ID'),
    String secretId = const String.fromEnvironment('CHH_VOICE_SECRET_ID'),
    String secretKey = const String.fromEnvironment('CHH_VOICE_SECRET_KEY'),
    String engine = const String.fromEnvironment('CHH_VOICE_ENGINE'),
    DateTime Function()? now,
    Random? random,
  }) {
    final model = engine.isEmpty ? _defaultEngine : engine;
    if (!_appIdFormat.hasMatch(appId) ||
        !_tokenFormat.hasMatch(secretId) ||
        !_tokenFormat.hasMatch(secretKey) ||
        !_tokenFormat.hasMatch(model)) {
      return null;
    }
    return LocalVoiceSigner._(
      appId,
      secretId,
      secretKey,
      model,
      now ?? DateTime.now,
      random ?? Random.secure(),
    );
  }

  @override
  Future<VoiceTicket> fetchTicket() async {
    final timestamp = _now().millisecondsSinceEpoch ~/ 1000;
    final nonce = _random.nextInt(0x100000000) + 1;
    final voiceId = List.generate(
      32,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    return VoiceTicket._trusted(
      buildLocalVoiceUrl(
        appId: _appId,
        secretId: _secretId,
        secretKey: _secretKey,
        engine: _engine,
        timestamp: timestamp,
        expired: timestamp + Duration.secondsPerDay,
        nonce: nonce,
        voiceId: voiceId,
      ),
    );
  }
}
