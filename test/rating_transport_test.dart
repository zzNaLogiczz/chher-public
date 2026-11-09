import 'dart:typed_data';
import 'package:chh_app/network/direct_fetcher.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CaptureAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      'ok',
      200,
      headers: {
        'set-cookie': ['rating_session=updated; Path=/'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RedirectThenBlockedAdapter implements HttpClientAdapter {
  final methods = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    methods.add(options.method);
    if (options.method == 'POST') {
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['/landing'],
          'set-cookie': ['rating_session=committed; Path=/'],
        },
      );
    }
    return ResponseBody.fromString('remote_addr', 567);
  }

  @override
  void close({bool force = false}) {}
}

class _Fallback extends ChhFetcher {
  int posts = 0;
  @override
  String get name => 'fallback';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      const ChhResponse(200, 'local fixture');
  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    posts++;
    return const ChhResponse(200, 'unexpected replay');
  }
}

void main() {
  test(
    'rating preflight GET uses synchronized cookies and XHR without POST',
    () async {
      final adapter = _CaptureAdapter();
      final direct = DirectFetcher(dio: Dio()..httpClientAdapter = adapter)
        ..sessionCookies = {'fixture_auth': 'authenticated'};
      final client = ChhClient(fetchers: [direct]);
      await client.getAjaxHtml(
        Uri.parse(
          'https://www.chiphell.com/forum.php?mod=misc&action=rate&tid=10&pid=20&inajax=1',
        ),
        refresh: true,
      );
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(request.headers['Cookie'], contains('fixture_auth=authenticated'));
      await direct.dispose();
    },
  );
  test(
    'rating POST redirect never follows a blocked landing page or falls back',
    () async {
      final adapter = _RedirectThenBlockedAdapter();
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter;
      final direct = DirectFetcher(dio: dio);
      final fallback = _Fallback();
      final client = ChhClient(fetchers: [direct, fallback]);
      final result = await client.postAjaxForm(
        Uri.parse(
          'https://www.chiphell.com/forum.php?mod=misc&action=rate&ratesubmit=yes',
        ),
        {'score1': '1'},
        retryTransportFailures: false,
      );
      expect(result.status, 302);
      expect(adapter.methods, ['POST']);
      expect(fallback.posts, 0);
      expect(result.setCookies, contains('rating_session=committed; Path=/'));
      expect(direct.jar.all['rating_session'], 'committed');
      await direct.dispose();
    },
  );
  test(
    'rating adds XHR and form referer while ordinary POST remains unchanged',
    () async {
      final adapter = _CaptureAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final fetcher = DirectFetcher(dio: dio)
        ..sessionCookies = {'login': 'fixture'};
      final url = Uri.parse(
        'https://www.chiphell.com/forum.php?mod=misc&action=rate&ratesubmit=yes',
      );
      const referer =
          'https://www.chiphell.com/forum.php?mod=misc&action=rate&tid=10&pid=20';
      final result = await fetcher.postAjaxForm(url, {
        'referer': referer,
        'score1': '1',
      });
      await fetcher.postForm(url, {'message': 'local fixture'});
      expect(
        adapter.requests.first.headers['X-Requested-With'],
        'XMLHttpRequest',
      );
      expect(adapter.requests.first.headers['Referer'], referer);
      expect(
        adapter.requests.first.headers['Cookie'],
        contains('login=fixture'),
      );
      expect(result.setCookies, contains('rating_session=updated; Path=/'));
      expect(fetcher.jar.all['rating_session'], 'updated');
      expect(adapter.requests.last.headers['X-Requested-With'], isNull);
      expect(adapter.requests.last.headers['Referer'], url.toString());
      await fetcher.dispose();
    },
  );
}
