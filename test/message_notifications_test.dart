import 'dart:async';

import 'package:chh_app/core/message_notifications.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/network/chh_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

String header(int notices, int messages, {String uid = '1001'}) =>
    '<div id="um"><strong class="vwmy"><a href="space-uid-$uid.html">fixture</a></strong>'
    '<a id="myprompt">提醒($notices)</a><a id="pm_ntc">私信($messages)</a></div>';

class Fetcher extends ChhFetcher {
  int calls = 0;
  Completer<ChhResponse>? pending;
  String html = header(2, 1);
  @override
  String get name => 'local';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    calls++;
    return pending == null ? ChhResponse(200, html) : pending!.future;
  }
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chh/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Fetcher fetcher;
  late ChhClient client;
  late ChhSession session;
  late MessageNotifications notifications;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    fetcher = Fetcher();
    client = ChhClient(fetchers: [fetcher]);
    session = ChhSession(client)..loggedIn = true;
    client.htmlObserver = session.observeHtml;
    notifications = MessageNotifications(
      session,
      interval: const Duration(hours: 1),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'requestPermission') return true;
      if (call.method == 'takeLaunch') return false;
      return null;
    });
  });
  tearDown(() {
    notifications.dispose();
    session.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'fresh header checks publish true counts and cached pages cannot rewind them',
    () async {
      notifications.start();
      await settle();
      expect(calls.where((c) => c.method == 'requestPermission'), isNotEmpty);
      final show = calls.lastWhere((c) => c.method == 'show');
      expect(show.arguments, {'uid': '1001', 'notices': 2, 'messages': 1});
      final uri = Uri.parse('https://www.chiphell.com/fixture');
      await client.getHtml(uri); // cache 2/1
      session.observeHtml(header(0, 0));
      calls.clear();
      await client.getHtml(uri);
      expect(session.badges.total, 0);
      expect(calls.where((c) => c.method == 'show'), isEmpty);
    },
  );

  testWidgets(
    'foreground checks do not wait for permission and repeat every 15s',
    (tester) async {
      notifications.dispose();
      notifications = MessageNotifications(session);
      final permission = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'requestPermission') return permission.future;
        return null;
      });
      notifications.start();
      await tester.pump();
      expect(fetcher.calls, greaterThan(0));
      final before = fetcher.calls;
      fetcher.html = header(4, 2);
      await tester.pump(const Duration(seconds: 14));
      expect(fetcher.calls, before);
      await tester.pump(const Duration(seconds: 1));
      expect(fetcher.calls, before + 1);
      expect(session.badges.total, 6);
      notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(fetcher.calls, before + 1);
      notifications.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(fetcher.calls, before + 2);
      permission.complete(false);
      await tester.pump();
      notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
    },
  );

  test(
    'pause stops checks; resume checks immediately; logout cancels native work',
    () async {
      notifications.start();
      await settle();
      notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
      final before = fetcher.calls;
      await notifications.check();
      expect(fetcher.calls, before);
      notifications.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(fetcher.calls, greaterThan(before));
      session.loggedIn = false;
      session.observeHtml(header(0, 0));
      await settle();
      expect(calls.lastWhere((c) => c.method == 'setSession').arguments, {
        'active': false,
      });
      final after = fetcher.calls;
      await notifications.check();
      expect(fetcher.calls, after);
    },
  );

  test(
    'only one check is in flight and invalidated results cannot publish',
    () async {
      notifications.start();
      await settle();
      fetcher.pending = Completer<ChhResponse>();
      final first = notifications.check();
      final before = fetcher.calls;
      await notifications.check();
      expect(fetcher.calls, before);
      client
          .clearCache(); // logout/auth replacement invalidates old network results
      calls.clear();
      fetcher.pending!.complete(ChhResponse(200, header(9, 9)));
      await first;
      expect(session.badges.total, 3);
      expect(calls.where((c) => c.method == 'show'), isEmpty);
    },
  );

  test(
    'permission failure leaves header counters and refresh usable',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'requestPermission') {
          throw PlatformException(code: 'denied');
        }
        return null;
      });
      notifications.start();
      await settle();
      expect(session.badges.total, 3);
      expect(fetcher.calls, greaterThan(0));
    },
  );

  test(
    'older foreground responses cannot replace a newer real header',
    () async {
      final uri = Uri.parse('https://www.chiphell.com/older');
      fetcher.pending = Completer<ChhResponse>();
      final pending = fetcher.pending!;
      final older = client.getHtml(uri);
      fetcher.pending = null;
      fetcher.html = header(0, 0);
      await client.getHtml(Uri.parse('https://www.chiphell.com/newer'));
      pending.complete(ChhResponse(200, header(5, 5)));
      await older;
      expect(session.badges.total, 0);

      fetcher.pending = Completer<ChhResponse>();
      final secondPending = fetcher.pending!;
      final valid = client.getHtml(uri, refresh: true);
      fetcher.pending = null;
      fetcher.html = '<p>Ajax without a header</p>';
      await client.getHtml(Uri.parse('https://www.chiphell.com/ajax'));
      secondPending.complete(ChhResponse(200, header(1, 0)));
      await valid;
      expect(session.badges.total, 1);
    },
  );

  test(
    'notification launch and hot taps request the messages destination',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'takeLaunch',
      );
      notifications.start();
      await settle();
      expect(notifications.openRequests.value, 1);
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('openMessages'),
        ),
        (_) => done.complete(),
      );
      await done.future;
      expect(notifications.openRequests.value, 2);
    },
  );
}
