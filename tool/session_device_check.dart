/// Offline Android process-restart check. Build only as a separate application
/// ID; it writes synthetic cookies and never contacts or logs in to the forum.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_session.dart';
import 'package:chh_app/network/direct_fetcher.dart';
import 'package:chh_app/network/login_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<String> runCheck() async {
  final marker = File('${Directory.systemTemp.path}/chh-session-check-stage');
  final stage = await marker.exists() ? await marker.readAsString() : '0';
  final direct = DirectFetcher();
  final session = ChhSession(ChhClient(fetchers: [direct]));
  try {
    if (stage == '0') {
      final loaded = Completer<void>();
      late InAppWebViewController controller;
      final browser = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(
          data:
              '<html><body><input type="checkbox" name="cookietime" value="2592000"></body></html>',
          baseUrl: WebUri(
            'https://www.chiphell.com/member.php?mod=logging&action=login&mobile=2',
          ),
          historyUrl: WebUri(
            'https://www.chiphell.com/member.php?mod=logging&action=login&mobile=2',
          ),
        ),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: rememberLoginScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          ),
        ]),
        onWebViewCreated: (value) => controller = value,
        onLoadStop: (_, _) {
          if (!loaded.isCompleted) loaded.complete();
        },
      );
      await browser.run();
      try {
        await loaded.future.timeout(const Duration(seconds: 15));
        check(
          await controller.evaluateJavascript(
                source: 'document.querySelector("input").checked',
              ) ==
              true,
          'remember-login default',
        );
        await controller.evaluateJavascript(
          source: '''
          document.querySelector('input').checked = false;
          document.body.appendChild(document.createElement('span'));
          document.cookie = 'chh_device_check_auth=synthetic; Max-Age=86400; Path=/; Secure';
          document.cookie = 'chh_device_check_saltkey=synthetic; Max-Age=86400; Path=/; Secure';
        ''',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        check(
          await controller.evaluateJavascript(
                source: 'document.querySelector("input").checked',
              ) ==
              false,
          'user choice overwritten',
        );
        await session.refresh();
        check(
          session.loggedIn && direct.sessionCookies != null,
          'initial login',
        );
        await marker.writeAsString('1', flush: true);
        return 'PASS 1/3: saved; remember-login choice preserved';
      } finally {
        await browser.dispose();
      }
    }
    await session.refresh();
    if (stage == '1') {
      check(
        session.loggedIn &&
            direct.sessionCookies?['chh_device_check_auth'] == 'synthetic',
        'cold restart restore',
      );
      await session.logout();
      check(!session.loggedIn && direct.sessionCookies == null, 'logout clear');
      await marker.writeAsString('2', flush: true);
      return 'PASS 2/3: cold restart restored; logout saved';
    }
    check(
      !session.loggedIn && direct.sessionCookies == null,
      'logout persisted across restart',
    );
    return 'PASS 3/3: cold restart stays logged out';
  } finally {
    session.dispose();
    await direct.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String result;
  try {
    result = await runCheck();
  } catch (error) {
    result = 'FAIL: $error';
  }
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(result))),
    ),
  );
}
