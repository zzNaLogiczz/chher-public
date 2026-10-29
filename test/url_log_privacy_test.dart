import 'dart:io';

import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/core/log_store.dart';
import 'package:chh_app/core/web_post_diagnostics.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fetcher extends ChhFetcher {
  _Fetcher(this.status);
  final int status;
  @override
  String get name => 'fixture';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      ChhResponse(status, 'fixture response');
  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async =>
      ChhResponse(status, 'fixture response');
}

void main() {
  test(
    'request and WebPost URL sentinels never reach persistent full export',
    () async {
      final dir = await Directory.systemTemp.createTemp('url-privacy');
      AppLog.instance.clear();
      AppLog.attachStore(LogStore(dir));
      addTearDown(() async {
        AppLog.detachStoreForTesting();
        AppLog.instance.clear();
        await dir.delete(recursive: true);
      });
      const secrets = [
        'PASS_SENTINEL',
        'COOKIE_SENTINEL',
        'TICKET_SENTINEL',
        'HASH_SENTINEL',
        'FRAGMENT_SENTINEL',
        'REPEATED_SENTINEL',
      ];
      final url = Uri.parse(
        'https://user:PASS_SENTINEL@example.test/post.php?'
        'password=PASS_SENTINEL&cookie=COOKIE_SENTINEL&codeVerifyTicket=TICKET_SENTINEL&'
        'formhash=HASH_SENTINEL&token=TICKET_SENTINEL&token=REPEATED_SENTINEL#FRAGMENT_SENTINEL',
      );
      await ChhClient(fetchers: [_Fetcher(200)]).getHtml(url);
      await ChhClient(fetchers: [_Fetcher(567), _Fetcher(200)]).getHtml(url);
      await expectLater(
        ChhClient(fetchers: [_Fetcher(567)]).getHtml(url),
        throwsA(isA<ChhAllBlockedError>()),
      );
      await ChhClient(
        fetchers: [_Fetcher(200)],
      ).postForm(url, {'password': secrets.first});
      WebPostDiagnostics.opened(url, {'codeVerifyTicket': secrets[2]});
      WebPostDiagnostics.loaded(url.toString(), url.toString());
      WebPostDiagnostics.filled({
        'action': url.toString(),
        'names': secrets[2],
        'seccode': 2,
        'verifyButton': true,
        'tcaptcha': 'function',
      });
      WebPostDiagnostics.filled({
        'action': 'http://[TICKET_SENTINEL',
        'seccode': 0,
      });
      WebPostDiagnostics.consoleError(url.toString());
      WebPostDiagnostics.loadError(url, 'CONNECTION_RESET');
      await AppLog.flush();
      final export = File('${dir.path}/export.txt');
      await AppLog.writeFullLog(export);
      final persisted = await AppLog.history().join('\n');
      for (final contents in [persisted, await export.readAsString()]) {
        for (final secret in secrets) {
          expect(contents, isNot(contains(secret)));
        }
        expect(contents, contains('status=567'));
        expect(contents, contains('status=200'));
        expect(contents, contains('type=CONNECTION_RESET'));
        expect(contents, contains('codeVerifyTicket(15)'));
        expect(contents, contains('token(15) token(17)'));
        expect(contents, contains('<invalid URL>'));
        expect(contents, contains('verifyButton=true'));
      }
    },
  );
}
