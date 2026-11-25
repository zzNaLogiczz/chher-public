import 'dart:async';

import 'package:chh_app/data/follow_index.dart';
import 'package:chh_app/data/follow_poller.dart';
import 'package:chh_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _newTopic = ThreadSummary(
  tid: 101,
  title: '新主题',
  author: '用户',
  replies: 0,
  views: 0,
  forumFid: 22,
);

class _Transport {
  final calls = <String>[];
  final pending =
      <({bool Function() current, Completer<List<ThreadSummary>> response})>[];

  Future<List<ThreadSummary>> fetch(String uid, bool Function() current) {
    calls.add(uid);
    final response = Completer<List<ThreadSummary>>();
    pending.add((current: current, response: response));
    return response.future;
  }

  void succeed([List<ThreadSummary> threads = const []]) {
    pending.removeAt(0).response.complete(threads);
  }

  void fail() => pending.removeAt(0).response.completeError(StateError('read'));
}

bool Function() _watchCompletion(Future<void> done) {
  var completed = false;
  unawaited(
    done.then((_) {
      completed = true;
    }),
  );
  return () => completed;
}

void main() {
  late FollowIndex index;
  late FollowPoller poller;
  late _Transport transport;

  void setup(WidgetTester tester) {
    index = FollowIndex.forTesting(null);
    transport = _Transport();
    poller = FollowPoller(
      index: index,
      fetchThreads: transport.fetch,
      now: tester.binding.clock.now,
    );
  }

  void update({
    bool foreground = true,
    bool loggedIn = true,
    int revision = 1,
  }) {
    poller.update(
      foreground: foreground,
      loggedIn: loggedIn,
      sessionRevision: revision,
    );
  }

  Future<void> follow(int uid, {DateTime? at}) async {
    await index.follow(uid: '$uid', name: '用户', at: at, lastTid: 100);
  }

  void dispose() {
    poller.dispose();
    index.dispose();
  }

  testWidgets('only runs in foreground and serializes requests with a gap', (
    tester,
  ) async {
    setup(tester);
    await follow(1);
    await follow(2, at: DateTime.now().add(const Duration(seconds: 1)));
    update(foreground: false);
    await tester.pump(Duration.zero);
    update(loggedIn: false);
    await tester.pump(Duration.zero);
    expect(transport.calls, isEmpty);

    update();
    await tester.pump(Duration.zero);
    expect(transport.calls, ['1']);
    await tester.pump(const Duration(seconds: 5));
    expect(transport.calls, ['1']);

    transport.succeed([_newTopic]);
    await tester.pump(Duration.zero);
    expect(index.unseenCount, 1);
    await tester.pump(const Duration(milliseconds: 999));
    expect(transport.calls, ['1']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(transport.calls, ['1', '2']);

    update(foreground: false);
    expect(transport.pending.single.current(), isFalse);
    transport.succeed([_newTopic]);
    await tester.pump(FollowIndex.checkInterval);
    expect(transport.calls, ['1', '2']);
    expect(index.all.firstWhere((user) => user.uid == '2').lastCheck, isNull);
    expect(index.unseenCount, 1);
    dispose();
  });

  testWidgets('switching accounts cancels a request and drops the old round', (
    tester,
  ) async {
    setup(tester);
    await follow(1);
    await follow(2, at: DateTime.now().add(const Duration(seconds: 1)));
    update();
    await tester.pump(Duration.zero);
    expect(transport.calls, ['1']);

    final switching = index.setUid('901');
    update(revision: 2);
    await switching;
    await follow(1);
    expect(transport.pending.single.current(), isFalse);
    await tester.pump(Duration.zero);
    expect(transport.calls, ['1']);

    transport.succeed([_newTopic]);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(index.unseenCount, 0);
    expect(transport.calls, ['1', '1']);
    expect(transport.pending.single.current(), isTrue);
    transport.succeed([_newTopic]);
    await tester.pump(Duration.zero);
    expect(index.unseenCount, 1);
    dispose();
  });

  testWidgets('an account switch restarts polling after a previous failure', (
    tester,
  ) async {
    setup(tester);
    await follow(1);
    update();
    await tester.pump(Duration.zero);
    transport.fail();
    await tester.pump(Duration.zero);

    final switching = index.setUid('901');
    update(revision: 2);
    await switching;
    await follow(2);
    await tester.pump(Duration.zero);
    expect(transport.calls, ['1', '2']);
    dispose();
  });

  testWidgets('failure completes the forced round and keeps the check time', (
    tester,
  ) async {
    setup(tester);
    final lastCheck = tester.binding.clock.now().subtract(
      FollowIndex.checkInterval,
    );
    await follow(1);
    await follow(2);
    await index.recordCheck('1', at: lastCheck);
    await index.recordCheck(
      '2',
      at: lastCheck.add(const Duration(milliseconds: 1)),
    );
    update();
    await tester.pump(Duration.zero);
    expect(transport.calls, ['1']);
    final completed = _watchCompletion(poller.forceCheck()!.done);
    expect(completed(), isFalse);

    transport.fail();
    await tester.pump(Duration.zero);
    expect(completed(), isTrue);
    await tester.pump(FollowIndex.checkInterval);
    expect(transport.calls, ['1']);
    expect(
      index.all.firstWhere((user) => user.uid == '1').lastCheck,
      lastCheck,
    );

    update(foreground: false);
    update();
    await tester.pump(Duration.zero);
    expect(transport.calls, ['1', '1']);
    transport.succeed();
    await tester.pump(Duration.zero);
    expect(
      index.all.firstWhere((user) => user.uid == '1').lastCheck,
      tester.binding.clock.now(),
    );
    dispose();
  });

  testWidgets('checks at most 20 oldest eligible users before the next round', (
    tester,
  ) async {
    setup(tester);
    final start = tester.binding.clock.now();
    for (var uid = 22; uid >= 1; uid--) {
      await follow(uid);
      await index.recordCheck(
        '$uid',
        at: start
            .subtract(FollowIndex.checkInterval)
            .subtract(Duration(seconds: 21 - uid)),
      );
    }
    update();
    await tester.pump(Duration.zero);
    for (var uid = 1; uid <= FollowIndex.maxChecksPerRound; uid++) {
      expect(transport.calls.last, '$uid');
      transport.succeed();
      await tester.pump(Duration.zero);
      await tester.pump(FollowIndex.betweenChecks);
    }
    expect(transport.calls, hasLength(20));
    expect(transport.pending, isEmpty);
    final untilNext = start
        .add(FollowIndex.checkInterval)
        .difference(tester.binding.clock.now());
    await tester.pump(untilNext - const Duration(milliseconds: 1));
    expect(transport.calls, hasLength(20));
    await tester.pump(const Duration(milliseconds: 1));
    expect(transport.calls, hasLength(21));
    expect(transport.calls.last, '21');
    dispose();
  });

  testWidgets('force takes over a scheduled timer and keeps the round limit', (
    tester,
  ) async {
    setup(tester);
    final start = tester.binding.clock.now();
    for (var uid = 1; uid <= 22; uid++) {
      await follow(uid);
      if (uid > 1) {
        await index.recordCheck(
          '$uid',
          at: start.subtract(Duration(seconds: 22 - uid)),
        );
      }
    }
    update();
    expect(poller.forceCheck(), isNotNull);
    expect(transport.calls, ['1']);
    await tester.pump(const Duration(seconds: 2));
    expect(transport.calls, ['1']);

    for (var uid = 1; uid <= FollowIndex.maxChecksPerRound; uid++) {
      expect(transport.calls.last, '$uid');
      transport.succeed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 999));
      expect(transport.calls, hasLength(uid));
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(transport.calls, hasLength(20));
    expect(transport.pending, isEmpty);
    dispose();
  });

  testWidgets('forced waiters finish together when the timed round ends', (
    tester,
  ) async {
    setup(tester);
    await follow(1);
    await follow(2);
    await follow(3);
    final start = tester.binding.clock.now();
    await index.recordCheck('2', at: start.subtract(FollowIndex.checkInterval));
    await index.recordCheck('3', at: start);
    update();
    await tester.pump(Duration.zero);
    expect(transport.calls, ['1']);

    transport.succeed();
    await tester.pump();
    final entryCompleted = _watchCompletion(poller.forceCheck()!.done);
    final refreshCompleted = _watchCompletion(poller.forceCheck()!.done);
    await tester.pump(FollowIndex.betweenChecks);
    expect(transport.calls, ['1', '2']);
    transport.succeed();
    await tester.pump();
    await tester.pump(FollowIndex.betweenChecks);
    expect(transport.calls, ['1', '2', '3']);
    expect(entryCompleted(), isFalse);
    expect(refreshCompleted(), isFalse);
    transport.succeed([_newTopic]);
    await tester.pump();
    expect(entryCompleted(), isTrue);
    expect(refreshCompleted(), isTrue);
    expect(index.unseenCount, 1);
    expect(transport.pending, isEmpty);
    dispose();
  });

  testWidgets('only the latest owner can cancel and release both waiters', (
    tester,
  ) async {
    setup(tester);
    await follow(1);
    await follow(2);
    update();
    final entry = poller.forceCheck()!;
    final refresh = poller.forceCheck()!;
    final entryCompleted = _watchCompletion(entry.done);
    final refreshCompleted = _watchCompletion(refresh.done);

    entry.cancel();
    await tester.pump();
    expect(entryCompleted(), isFalse);
    expect(refreshCompleted(), isFalse);
    expect(transport.pending.single.current(), isTrue);

    refresh.cancel();
    await tester.pump();
    expect(entryCompleted(), isTrue);
    expect(refreshCompleted(), isTrue);
    expect(transport.pending.single.current(), isFalse);

    transport.succeed([_newTopic]);
    await tester.pump(FollowIndex.betweenChecks);
    expect(index.activities, isEmpty);
    expect(index.all.every((user) => user.lastCheck == null), isTrue);
    expect(transport.calls, hasLength(1));
    dispose();
  });

  for (final switchAccount in [false, true]) {
    testWidgets('a forced round completes and discards a late response after '
        '${switchAccount ? 'an account switch' : 'backgrounding'}', (
      tester,
    ) async {
      setup(tester);
      final start = tester.binding.clock.now();
      await follow(1);
      await follow(2);
      await index.recordCheck('1', at: start);
      await index.recordCheck('2', at: start);
      update();
      final completed = _watchCompletion(poller.forceCheck()!.done);
      expect(transport.calls, hasLength(1));
      expect(completed(), isFalse);

      if (switchAccount) {
        final switching = index.setUid('901');
        update(revision: 2);
        await switching;
        await follow(1);
        await index.recordCheck('1', at: start);
      } else {
        update(foreground: false);
      }
      await tester.pump();
      expect(completed(), isTrue);
      expect(transport.pending.single.current(), isFalse);
      transport.succeed([_newTopic]);
      await tester.pump(FollowIndex.betweenChecks);
      expect(index.unseenCount, 0);
      expect(index.activities, isEmpty);
      expect(index.all.every((user) => user.lastCheck == start), isTrue);
      expect(transport.calls, hasLength(1));
      dispose();
    });
  }
}
