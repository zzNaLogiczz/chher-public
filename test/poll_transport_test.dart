import 'dart:convert';
import 'dart:typed_data';

import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/network/direct_fetcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Capture implements HttpClientAdapter {
  final int status;
  _Capture([this.status = 200]);
  final bodies = <String>[];
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    bodies.add(await utf8.decoder.bind(requestStream!).join());
    return ResponseBody.fromString(
      'local response',
      status,
      headers: status == 302
          ? {
              'location': ['/blocked-landing'],
            }
          : {},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RepeatedFake extends ChhFetcher implements FormFieldsFetcher {
  final ChhResponse response;
  int posts = 0;
  _RepeatedFake(this.response);
  @override
  String get name => 'poll fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      const ChhResponse(200, 'local page');
  @override
  Future<ChhResponse> postFormFields(
    Uri url,
    List<MapEntry<String, String>> fields,
  ) async {
    posts++;
    return response;
  }
}

void main() {
  final url = Uri.parse(
    'https://www.chiphell.com/forum.php?mod=misc&action=votepoll',
  );
  const fields = [
    MapEntry('formhash', 'fresh & local'),
    MapEntry('pollanswers[]', 'one'),
    MapEntry('pollanswers[]', 'two'),
    MapEntry('pollsubmit', 'true'),
  ];
  test(
    'direct transport sends repeated array names and escapes values',
    () async {
      final capture = _Capture();
      final direct = DirectFetcher(dio: Dio()..httpClientAdapter = capture);
      final client = ChhClient(fetchers: [direct]);
      final result = await client.postFormFields(
        url,
        fields,
        retryTransportFailures: false,
      );
      expect(result.status, 200);
      expect(
        capture.bodies.single,
        'formhash=fresh+%26+local&pollanswers%5B%5D=one&pollanswers%5B%5D=two&pollsubmit=true',
      );
      expect(
        Uri(query: capture.bodies.single).queryParametersAll['pollanswers[]'],
        ['one', 'two'],
      );
      expect(capture.requests.single.headers['Referer'], '$url');
      await direct.dispose();
    },
  );
  test(
    'unknown transport result never replays a poll through fallback',
    () async {
      final first = _RepeatedFake(ChhResponse.timeout);
      final fallback = _RepeatedFake(const ChhResponse(200, 'should not post'));
      final result = await ChhClient(
        fetchers: [first, fallback],
      ).postFormFields(url, fields, retryTransportFailures: false);
      expect(result.status, -1);
      expect(first.posts, 1);
      expect(fallback.posts, 0);
    },
  );
  test('poll redirect returns before landing GET and cannot replay', () async {
    final capture = _Capture(302);
    final direct = DirectFetcher(
      dio: Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = capture,
    );
    final fallback = _RepeatedFake(const ChhResponse(200, 'should not post'));
    final result = await ChhClient(
      fetchers: [direct, fallback],
    ).postFormFields(url, fields, retryTransportFailures: false);
    expect(result.status, 302);
    expect(capture.requests.map((request) => request.method), ['POST']);
    expect(fallback.posts, 0);
    await direct.dispose();
  });
}
