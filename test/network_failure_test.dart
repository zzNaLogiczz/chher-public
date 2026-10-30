import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/network/direct_fetcher.dart';
import 'package:chh_app/widgets/state_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _HandshakeAdapter implements HttpClientAdapter {
  _HandshakeAdapter({this.redirect = false});
  final bool redirect;
  final methods = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    methods.add(options.method);
    if (redirect && options.method == 'POST') {
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['/landing'],
          'set-cookie': ['received=fixture'],
        },
      );
    }
    final data = options.data;
    final fields = data is FormData
        ? data.fields.map((entry) => entry.value).join(' ')
        : data is Map
        ? data.values.join(' ')
        : '';
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: HandshakeException(
        'CERTIFICATE_VERIFY_FAILED ${options.headers['Cookie']} $fields',
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FailureFetcher extends ChhFetcher {
  _FailureFetcher(this.name, this.response);
  @override
  final String name;
  final ChhResponse response;
  int postCalls = 0;

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      response;

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async {
    postCalls++;
    return response;
  }
}

Future<ChhAllBlockedError> _failure(List<ChhResponse> responses) async {
  final client = ChhClient(
    fetchers: [
      for (var i = 0; i < responses.length; i++)
        _FailureFetcher('channel$i', responses[i]),
    ],
  );
  try {
    await client.getHtml(Uri.parse('https://example.test/thread?token=SECRET'));
  } on ChhAllBlockedError catch (error) {
    return error;
  }
  throw StateError('Expected all channels to fail');
}

void main() {
  for (final method in ['GET', 'POST', 'multipart', 'redirect']) {
    test(
      'DirectFetcher preserves TLS failure for $method without cookies',
      () async {
        final dio = Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = _HandshakeAdapter(
            redirect: method == 'redirect',
          );
        final fetcher = DirectFetcher(dio: dio)
          ..sessionCookies = {'auth': 'COOKIE_SENTINEL'};
        addTearDown(fetcher.dispose);
        final url = Uri.parse('https://example.test/forum.php');
        final response = switch (method) {
          'GET' => await fetcher.getHtml(url),
          'multipart' => await fetcher.postMultipart(
            url,
            {'password': 'FORM_SENTINEL'},
            const UploadFile(
              field: 'file',
              filename: 'fixture.txt',
              contentType: 'text/plain',
              bytes: [1, 2],
            ),
          ),
          _ => await fetcher.postForm(url, {'password': 'FORM_SENTINEL'}),
        };
        expect(response.status, method == 'redirect' ? 302 : -1);
        if (method == 'redirect') {
          expect(response.setCookies, ['received=fixture']);
        }
        expect(response.error, contains('CERTIFICATE_VERIFY_FAILED'));
        expect(response.error, contains('HandshakeException'));
        expect(response.error, isNot(contains('COOKIE_SENTINEL')));
        expect(response.error, isNot(contains('FORM_SENTINEL')));
        expect(response.error!.length, lessThanOrEqualTo(200));
      },
    );
  }

  test('landing TLS failure after accepted POST never resubmits', () async {
    final adapter = _HandshakeAdapter(redirect: true);
    final direct = DirectFetcher(
      dio: Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter,
    );
    addTearDown(direct.dispose);
    final fallback = _FailureFetcher(
      'fallback',
      const ChhResponse(200, 'must not be called'),
    );
    final response = await ChhClient(fetchers: [direct, fallback]).postForm(
      Uri.parse('https://example.test/post.php'),
      {'message': 'fixture content'},
    );
    expect(adapter.methods, ['POST', 'GET']);
    expect(fallback.postCalls, 0);
    expect(response.status, 302);
    expect(response.setCookies, ['received=fixture']);
    expect(response.error, contains('CERTIFICATE_VERIFY_FAILED'));
    expect(response.rejectedBeforeApp, isFalse);
  });

  test('failure reason applies existing URL privacy rules before truncating', () {
    final text = AppLog.failureReason(
      'failed https://user:PASS@example.test/p?token=TICKET#FRAGMENT ${'x' * 210}',
    );
    expect(text, contains('/p?token(6)'));
    for (final secret in ['PASS', 'TICKET', 'FRAGMENT']) {
      expect(text, isNot(contains(secret)));
    }
    expect(text.length, 200);
  });

  testWidgets(
    'transport failures show connection copy and preserve each reason',
    (tester) async {
      AppLog.instance.clear();
      final error = await _failure([
        const ChhResponse(-1, '', error: 'CERTIFICATE_VERIFY_FAILED'),
        const ChhResponse(
          -1,
          '',
          error:
              'SocketException https://user:PASS@example.test/p?token=TICKET#FRAGMENT',
        ),
      ]);
      expect(error.isConnectionFailure, isTrue);
      final entries = AppLog.instance.entries;
      expect(entries.where((e) => e.level == LogLevel.warn).length, 2);
      expect(
        entries.last.message,
        contains('channel0 status=-1 error=CERTIFICATE_VERIFY_FAILED'),
      );
      expect(
        entries.last.message,
        contains('channel1 status=-1 error=SocketException'),
      );
      expect(entries.last.message, isNot(contains('SECRET')));
      for (final secret in ['PASS', 'TICKET', 'FRAGMENT']) {
        expect(AppLog.instance.dump(), isNot(contains(secret)));
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(body: StateView.error(error)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('无法连接论坛，请稍后重试'), findsOneWidget);
    },
  );

  for (final response in [
    const ChhResponse(567, ''),
    const ChhResponse(-1, 'remote_addr'),
    const ChhResponse(200, 'Invalid Request'),
    const ChhResponse(200, '.a1{margin:0'),
  ]) {
    testWidgets(
      'WAF evidence ${response.status}/${response.body} shows blocked copy',
      (tester) async {
        final error = await _failure([
          const ChhResponse(-1, '', error: 'SocketException'),
          response,
        ]);
        expect(error.isConnectionFailure, isFalse);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(body: StateView.error(error)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('网络被拦截，请稍后重试'), findsOneWidget);
      },
    );
  }
}
