import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../update/update_client.dart';
import '../update/update_endpoints.dart';
import '../update/update_platform.dart';
import '../update/update_store.dart';
import 'speech_engine.dart';

part 'local_voice_signer.dart';

/// Supplies an address from a verified voice response or a local signature.
abstract interface class VoiceTicketSource {
  Future<VoiceTicket> fetchTicket();
}

final class VoiceTicket {
  final String url;
  const VoiceTicket._trusted(this.url);

  @visibleForTesting
  const VoiceTicket.forTesting(this.url);
}

class VoiceServiceClient implements VoiceTicketSource {
  static const _timeout = Duration(seconds: 5);
  static const _injectedVoiceEndpoints = String.fromEnvironment(
    'CHH_VOICE_ENDPOINTS',
  );
  static List<String> get injectedVoiceEndpoints =>
      normalizeEndpoints(_injectedVoiceEndpoints.split(','));

  final String filesDir;
  final bool isOfficial;
  final List<String> _voiceEndpoints;
  final List<String> _updateEndpoints;
  final UpdateStore _updateStore;
  final UpdateClient _verifier;
  final Dio _dio;
  late final Future<String> _installId = _readInstallId();

  VoiceServiceClient({
    required this.filesDir,
    required this.isOfficial,
    required UpdatePlatform platform,
    Iterable<String>? voiceEndpoints,
    Iterable<String>? updateEndpoints,
    Dio? dio,
  }) : _voiceEndpoints = voiceEndpoints == null
           ? injectedVoiceEndpoints
           : normalizeEndpoints(voiceEndpoints),
       _updateEndpoints = normalizeEndpoints(
         updateEndpoints ?? injectedUpdateEndpoints,
       ),
       _updateStore = UpdateStore.inDirectory(filesDir),
       _dio = dio ?? Dio(),
       _verifier = UpdateClient(platform: platform);

  /// Null indicates that the current channel has no configured endpoint.
  Future<bool?> fetchStatus() => _request(
    'status',
    'voiceStatus',
    (payload) => payload['enabled'] as bool,
  );

  @override
  Future<VoiceTicket> fetchTicket() async {
    final ticket = await _request('ticket', 'voiceTicket', (payload) {
      if (payload['enabled'] == false) return null;
      final url = payload['url'];
      final expiresAt = payload['expiresAt'];
      if (url is! String ||
          url.isEmpty ||
          expiresAt is! int ||
          expiresAt <= (payload['issuedAt'] as int)) {
        throw const FormatException('voice ticket');
      }
      return VoiceTicket._trusted(url);
    });
    return ticket ?? (throw const SpeechException(SpeechErrorKind.service));
  }

  Future<List<String>> _endpoints() async {
    if (_voiceEndpoints.isNotEmpty || !isOfficial) return _voiceEndpoints;
    final stored = await _updateStore.load();
    return normalizeEndpoints([
      if (stored.endpointsIssuedAt > 0) ...stored.endpoints,
      ..._updateEndpoints,
    ]);
  }

  Future<String> _readInstallId() async {
    if (await _updateStore.file.exists()) {
      return (await _updateStore.load()).installId;
    }
    // Voice can be configured while the updater is disabled.
    final file = File('$filesDir/voice/install-id');
    try {
      final value = await file.readAsString();
      if (RegExp(r'^[0-9a-f]{32}$').hasMatch(value)) return value;
    } on FileSystemException {
      // First run or inaccessible storage.
    }
    final id = UpdateState.newInstallId();
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.$id.tmp');
      await temporary.writeAsString(id, flush: true);
      await temporary.rename(file.path);
    } on FileSystemException {
      // Reuse the generated ID for this process when storage is unavailable.
    }
    return id;
  }

  Future<T?> _request<T>(
    String resource,
    String type,
    T? Function(Map<String, dynamic>) parse,
  ) {
    final cancel = CancelToken();
    return _requestAcrossEndpoints(resource, type, parse, cancel).timeout(
      _timeout,
      onTimeout: () {
        cancel.cancel();
        throw const SpeechException(SpeechErrorKind.service);
      },
    );
  }

  Future<T?> _requestAcrossEndpoints<T>(
    String resource,
    String type,
    T? Function(Map<String, dynamic>) parse,
    CancelToken cancel,
  ) async {
    final endpoints = await _endpoints();
    if (endpoints.isEmpty) return null;
    final query = Uri(queryParameters: {'did': await _installId}).query;
    for (final endpoint in endpoints) {
      if (cancel.isCancelled) break;
      try {
        final response = await _dio.get<String>(
          '$endpoint/v1/voice/$resource?$query',
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (_) => true,
          ),
        );
        if (response.statusCode != 200) continue;
        final payload = await _verifier.verifySignedResponse(
          response.data ?? '',
        );
        if (payload['type'] != type ||
            payload['issuedAt'] is! int ||
            payload['enabled'] is! bool) {
          throw const FormatException('voice response');
        }
        return parse(payload);
      } on Exception {
        // Try the next endpoint without exposing response content.
      }
    }
    throw const SpeechException(SpeechErrorKind.service);
  }
}
