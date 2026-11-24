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
  final requests = <Uri>[];
  Map<String, String>? pmHeaders;
  ChhResponse pmResponse = const ChhResponse(503, '');
  Completer<ChhResponse>? pendingPm;
  Completer<ChhResponse>? pending;
  String html = header(2, 1);
  @override
  String get name => 'local';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests.add(url);
    if (url.queryParameters['op'] == 'getpmuser') {
      pmHeaders = headers;
      return pendingPm?.future ?? pmResponse;
    }
    calls++;
    return pending == null ? ChhResponse(200, html) : pending!.future;
  }
}

ChhResponse pmResponse(List<int> ids) {
  final rows = ids
      .map(
        (id) =>
            "$id:{'uid':$id, 'username':'fixture', 'avatar':'/a', "
            "'plid':$id, 'isnew':3, 'daterange':1}",
      )
      .join(',');
  return ChhResponse(200, "<root><![CDATA[{'userdata':{$rows}}]]></root>");
}

String promptHeader() =>
    header(2, 0).replaceFirst('私信(0)', '<em class="prompt_news"></em>私信');

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
      expect(show.arguments, {
        'uid': '1001',
        'notices': 2,
        'messages': 1,
        'pmHasCount': false,
      });
      final uri = Uri.parse('https://www.chiphell.com/fixture');
      await client.getHtml(uri); // cache 2/1
      session.observeHtml(header(0, 0));
      calls.clear();
      await client.getHtml(uri);
      expect(session.badges.total, 0);
      expect(calls.where((c) => c.method == 'show'), isEmpty);
    },
  );

  test(
    'checks the header before PM and publishes exact and fallback counts',
    () async {
      fetcher.html = promptHeader();
      fetcher.pmResponse = pmResponse([11, 22, 33]);
      notifications.start();
      await settle();
      expect(fetcher.requests.map((uri) => uri.path), [
        '/forum.php',
        '/home.php',
      ]);
      expect(fetcher.requests.last.queryParameters, {
        'mod': 'spacecp',
        'ac': 'pm',
        'op': 'getpmuser',
        'inajax': '1',
      });
      expect(fetcher.pmHeaders?['X-Requested-With'], 'XMLHttpRequest');
      expect(session.badges.messages, 3);
      expect(session.badges.total, 5);
      expect(calls.lastWhere((c) => c.method == 'show').arguments, {
        'uid': '1001',
        'notices': 2,
        'messages': 3,
        'pmHasCount': true,
      });

      session.markPmRead('22');
      expect(session.badges.messages, 2);

      fetcher.pmResponse = pmResponse([]);
      await notifications.check();
      expect(session.badges.messages, 0); // Known zero takes precedence.

      final revision = client.freshHeaderRevision;
      fetcher.pmResponse = const ChhResponse(
        200,
        '<html><body><div id="hd"><form id="lsform"></form></div></body></html>',
      );
      await notifications.check();
      expect(client.freshHeaderRevision, revision + 1);
      expect(session.currentExpired, isFalse);
      expect(session.badges.messages, 1);
      expect(calls.lastWhere((c) => c.method == 'show').arguments, {
        'uid': '1001',
        'notices': 2,
        'messages': 1,
        'pmHasCount': false,
      });
    },
  );

  testWidgets(
    'browsing retries a positive header at most once per 30 seconds',
    (tester) async {
      notifications.dispose();
      session.dispose();
      client = ChhClient(fetchers: [fetcher], now: tester.binding.clock.now);
      session = ChhSession(client)..loggedIn = true;
      client.htmlObserver = session.observeHtml;
      notifications = MessageNotifications(
        session,
        interval: const Duration(hours: 1),
      )..start();
      await tester.pump();
      int pmReads() => fetcher.requests
          .where((uri) => uri.queryParameters['op'] == 'getpmuser')
          .length;
      expect(pmReads(), 1);
      fetcher.html = promptHeader();
      final browse = Uri.parse('https://www.chiphell.com/browse');
      await tester.pump(const Duration(seconds: 29));
      await client.getHtml(browse, refresh: true);
      expect(pmReads(), 1);
      await tester.pump(const Duration(seconds: 1));
      fetcher.pmResponse = pmResponse([11, 22]);
      await client.getHtml(browse, refresh: true);
      await tester.pump();
      expect(pmReads(), 2);
      expect(session.badges.messages, 2);
      await tester.pump(const Duration(seconds: 30));
      await client.getHtml(browse, refresh: true);
      expect(pmReads(), 2); // Known positive counts do not trigger supplements.
      notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
    },
  );

  test('an in-flight check cannot undo a locally read conversation', () async {
    fetcher.pmResponse = pmResponse([11]);
    notifications.start();
    await settle();
    expect(session.badges.messages, 1);

    fetcher.pendingPm = Completer<ChhResponse>();
    final check = notifications.check();
    await settle();
    session.markPmRead('11');
    fetcher.pendingPm!.complete(pmResponse([11]));
    await check;
    expect(session.badges.messages, 0);
  });

  testWidgets(
    'foreground checks do not wait for permission and repeat every 15s',
    (tester) async {
      notifications.dispose();
      session.dispose();
      client = ChhClient(fetchers: [fetcher], now: tester.binding.clock.now);
      session = ChhSession(client)..loggedIn = true;
      client.htmlObserver = session.observeHtml;
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

  testWidgets(
    'fresh unchanged headers defer checks; cached and headerless pages do not',
    (tester) async {
      notifications.dispose();
      session.dispose();
      client = ChhClient(fetchers: [fetcher], now: tester.binding.clock.now);
      session = ChhSession(client)..loggedIn = true;
      client.htmlObserver = session.observeHtml;
      notifications = MessageNotifications(session)..start();
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      final business = Uri.parse('https://www.chiphell.com/business');
      await client.getHtml(
        business,
      ); // Same counts still constitute a new header.
      final fresh = client.lastFreshHeaderAt;
      final before = fetcher.calls;
      await tester.pump(const Duration(seconds: 5));
      expect(fetcher.calls, before);
      await client.getHtml(business); // Cache must not extend the deadline.
      fetcher.html = '<p>no header</p>';
      await client.getHtml(Uri.parse('https://www.chiphell.com/ajax'));
      expect(client.lastFreshHeaderAt, fresh);
      fetcher.html = header(4, 1);
      await tester.pump(const Duration(seconds: 9));
      expect(fetcher.calls, before + 1);
      await tester.pump(const Duration(seconds: 1));
      expect(fetcher.calls, before + 2);
      expect(session.badges.total, 5);
      notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
    },
  );

  testWidgets(
    'missing headers back off within five minutes and real headers reset retries',
    (tester) async {
      notifications.dispose();
      session.dispose();
      client = ChhClient(fetchers: [fetcher], now: tester.binding.clock.now);
      session = ChhSession(client)..loggedIn = true;
      client.htmlObserver = session.observeHtml;
      notifications = MessageNotifications(session)..start();
      await tester.pump();
      fetcher.html = '<p>session header unavailable</p>';
      await tester.pump(const Duration(seconds: 15));
      for (final seconds in [30, 60, 120, 240, 300, 300]) {
        final before = fetcher.calls;
        await tester.pump(Duration(seconds: seconds - 1));
        expect(fetcher.calls, before);
        await tester.pump(const Duration(seconds: 1));
        expect(fetcher.calls, before + 1);
      }
      fetcher.html = header(1, 0);
      await client.getHtml(Uri.parse('https://www.chiphell.com/recovered'));
      final before = fetcher.calls;
      await tester.pump(const Duration(seconds: 15));
      expect(fetcher.calls, before + 1);
      notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
    },
  );

  testWidgets('expired guest headers back off until the member header returns', (
    tester,
  ) async {
    notifications.dispose();
    session.dispose();
    client = ChhClient(fetchers: [fetcher], now: tester.binding.clock.now);
    session = ChhSession(client)..loggedIn = true;
    client.htmlObserver = session.observeHtml;
    notifications = MessageNotifications(session)..start();
    await tester.pump();

    fetcher.html =
        '<html><body><div id="hd"><form id="lsform"></form></div></body></html>';
    final memberRevision = client.freshHeaderRevision;
    final beforeExpiry = fetcher.calls;
    await tester.pump(const Duration(seconds: 15));
    expect(fetcher.calls, beforeExpiry + 1);
    expect(session.currentExpired, isTrue);
    expect(client.freshHeaderRevision, greaterThan(memberRevision));

    for (final seconds in [30, 60, 120, 240, 300, 300]) {
      final before = fetcher.calls;
      await tester.pump(Duration(seconds: seconds - 1));
      expect(fetcher.calls, before);
      // A guest page from another read still advances the watermark.
      await client.getHtml(
        Uri.parse('https://www.chiphell.com/guest'),
        refresh: true,
      );
      expect(fetcher.calls, before + 1);
      await tester.pump(const Duration(seconds: 1));
      expect(fetcher.calls, before + 2);
    }

    fetcher.html = header(1, 0);
    await client.getHtml(Uri.parse('https://www.chiphell.com/recovered'));
    expect(session.currentExpired, isFalse);
    final afterRecovery = fetcher.calls;
    await tester.pump(const Duration(seconds: 14));
    expect(fetcher.calls, afterRecovery);
    await tester.pump(const Duration(seconds: 1));
    expect(fetcher.calls, afterRecovery + 1);
    notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
  });

  testWidgets('clock rollback cannot keep a future-dated header fresh', (
    tester,
  ) async {
    notifications.dispose();
    session.dispose();
    var wallClock = DateTime.utc(2026, 11, 12, 12);
    client = ChhClient(fetchers: [fetcher], now: () => wallClock);
    session = ChhSession(client)..loggedIn = true;
    client.htmlObserver = session.observeHtml;
    notifications = MessageNotifications(session)..start();
    await tester.pump();
    final before = fetcher.calls;
    wallClock = wallClock.subtract(const Duration(hours: 1));
    await tester.pump(const Duration(seconds: 15));
    expect(fetcher.calls, before + 1);
    expect(client.lastFreshHeaderAt, wallClock);
    notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
  });

  testWidgets('clock rollback cannot extend an existing retry deadline', (
    tester,
  ) async {
    notifications.dispose();
    session.dispose();
    var wallClock = DateTime.utc(2026, 11, 12, 12);
    client = ChhClient(fetchers: [fetcher], now: () => wallClock);
    session = ChhSession(client)..loggedIn = true;
    client.htmlObserver = session.observeHtml;
    notifications = MessageNotifications(session)..start();
    await tester.pump();
    fetcher.html = '<p>no header</p>';
    await notifications.check(); // First failure uses a 30-second retry.
    final before = fetcher.calls;
    wallClock = wallClock.subtract(const Duration(hours: 1));
    client
        .clearCache(); // Reschedule while the existing wall-clock deadline is ahead.
    await tester.pump(const Duration(seconds: 29));
    expect(fetcher.calls, before);
    await tester.pump(const Duration(seconds: 1));
    expect(fetcher.calls, before + 1);
    notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
  });

  testWidgets('a concurrent valid header wins over a failing poll', (
    tester,
  ) async {
    notifications.dispose();
    session.dispose();
    client = ChhClient(fetchers: [fetcher], now: tester.binding.clock.now);
    session = ChhSession(client)..loggedIn = true;
    client.htmlObserver = session.observeHtml;
    notifications = MessageNotifications(session)..start();
    await tester.pump();
    fetcher.pending = Completer<ChhResponse>();
    final pending = fetcher.pending!;
    final check = notifications.check();
    fetcher.pending = null;
    await tester.pump(const Duration(seconds: 2));
    await client.getHtml(Uri.parse('https://www.chiphell.com/new-header'));
    pending.completeError(StateError('offline fixture'));
    await check;
    final before = fetcher.calls;
    await tester.pump(const Duration(seconds: 15));
    expect(fetcher.calls, before + 1);
    notifications.didChangeAppLifecycleState(AppLifecycleState.paused);
  });

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

  test('notification launch and hot taps carry action and account', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'takeLaunch'
          ? {'action': 'messages', 'uid': '1001'}
          : null,
    );
    notifications.start();
    await settle();
    expect(
      notifications.openRequests.value?.action,
      NotificationAction.messages,
    );
    expect(notifications.openRequests.value?.uid, '1001');
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('openNotification', {
          'action': 'relogin',
          'uid': '1002',
        }),
      ),
      (_) => done.complete(),
    );
    await done.future;
    expect(
      notifications.openRequests.value?.action,
      NotificationAction.relogin,
    );
    expect(notifications.openRequests.value?.uid, '1002');
  });
}
