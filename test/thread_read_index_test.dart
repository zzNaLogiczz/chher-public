import 'dart:convert';
import 'dart:io';

import 'package:chh_app/data/thread_read_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  final created = <ThreadReadIndex>[];

  ThreadReadIndex make(
    File? f, {
    int capacity = 2000,
    Duration writeDelay = const Duration(seconds: 2),
  }) {
    final index = ThreadReadIndex(
      f,
      capacity: capacity,
      writeDelay: writeDelay,
    );
    created.add(index);
    return index;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chh-read-test-');
    file = File('${directory.path}/threads-v1.json');
  });
  tearDown(() async {
    for (final index in created) {
      index.dispose();
    }
    created.clear();
    await directory.delete(recursive: true);
  });

  test('unrecorded thread is unseen', () {
    expect(make(file).stateOf(1, replies: 10), isA<ThreadReadUnseen>());
  });

  test('opened is seen; grown reply count yields +N', () {
    final index = make(file)..markRead(1, 10);
    expect(index.stateOf(1, replies: 10), isA<ThreadReadSeen>());
    final grown = index.stateOf(1, replies: 13);
    expect((grown as ThreadReadNewReplies).count, 3);
  });

  test('decreased reply count stays seen, never negative', () {
    final index = make(file)..markRead(1, 10);
    expect(index.stateOf(1, replies: 4), isA<ThreadReadSeen>());
  });

  test('seen state survives restart', () async {
    final first = make(file)..markRead(42, 7);
    await first.flush();
    final restarted = make(file);
    await restarted.load();
    expect(restarted.stateOf(42, replies: 7), isA<ThreadReadSeen>());
    expect(restarted.stateOf(42, replies: 9), isA<ThreadReadNewReplies>());
  });

  test('over capacity evicts the oldest', () async {
    final index = make(file, capacity: 50);
    for (var tid = 1; tid <= 60; tid++) {
      index.markRead(tid, 1);
    }
    await index.flush();
    expect(index.stateOf(1, replies: 1), isA<ThreadReadUnseen>());
    expect(index.stateOf(60, replies: 1), isA<ThreadReadSeen>());
    final stored = jsonDecode(await file.readAsString())['threads'] as Map;
    expect(stored.length, 50);
  });

  test('eviction is by at, not by insertion order', () async {
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'threads': {
          '1': {'r': 1, 'at': 9000},
          '2': {'r': 1, 'at': 1000},
          '3': {'r': 1, 'at': 5000},
        },
      }),
    );
    final index = make(file, capacity: 3);
    await index.load();
    index.markRead(4, 1);
    expect(index.stateOf(2, replies: 1), isA<ThreadReadUnseen>());
    expect(index.stateOf(1, replies: 1), isA<ThreadReadSeen>());
  });

  test('corrupt JSON degrades silently to nothing seen', () async {
    await file.writeAsString('not json');
    final index = make(file);
    await index.load();
    expect(index.stateOf(1, replies: 1), isA<ThreadReadUnseen>());
    index.markRead(1, 1);
    expect(index.stateOf(1, replies: 1), isA<ThreadReadSeen>());
    await index.flush();
    expect(jsonDecode(await file.readAsString()), isA<Map>());
  });

  test('wrong version and malformed entries are ignored', () async {
    await file.writeAsString(
      jsonEncode({
        'version': 2,
        'threads': {
          '1': {'r': 1, 'at': 1},
        },
      }),
    );
    final wrong = make(file);
    await wrong.load();
    expect(wrong.stateOf(1, replies: 1), isA<ThreadReadUnseen>());

    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'threads': {
          '1': {'r': null, 'at': 1},
          '2': {'r': -3, 'at': 1},
          'x': {'r': 1, 'at': 1},
          '3': 'oops',
          '4': {'r': 6, 'at': 1},
        },
      }),
    );
    final partial = make(file);
    await partial.load();
    expect(partial.stateOf(1, replies: 1), isA<ThreadReadUnseen>());
    expect(partial.stateOf(2, replies: 1), isA<ThreadReadUnseen>());
    expect(partial.stateOf(3, replies: 1), isA<ThreadReadUnseen>());
    expect(partial.stateOf(4, replies: 6), isA<ThreadReadSeen>());
  });

  test('unwritable storage never throws', () async {
    final blocked = File('${directory.path}/missing/deeper/threads-v1.json');
    // A regular file where the parent directory should be makes IO fail.
    await File('${directory.path}/missing').writeAsString('x');
    final index = make(blocked)..markRead(1, 5);
    await index.load();
    await index.flush();
    expect(index.stateOf(1, replies: 5), isA<ThreadReadSeen>());
  });

  test('null file is pure memory and does not throw', () async {
    final index = make(null)..markRead(1, 5);
    expect(index.stateOf(1, replies: 5), isA<ThreadReadSeen>());
    await index.load();
    await index.flush();
  });

  test('repeated markRead with same value notifies once', () {
    final index = make(file);
    var n = 0;
    index.addListener(() => n++);
    index
      ..markRead(1, 5)
      ..markRead(1, 5);
    expect(n, 1);
    index.markRead(1, 6);
    expect(n, 2);
  });

  test('marks made before load win over disk and are not lost', () async {
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'threads': {
          '1': {'r': 3, 'at': 1},
          '2': {'r': 8, 'at': 1},
        },
      }),
    );
    final index = make(file)..markRead(1, 9);
    await index.load();
    expect(index.stateOf(1, replies: 9), isA<ThreadReadSeen>());
    expect(index.stateOf(2, replies: 8), isA<ThreadReadSeen>());
    await index.flush();
    final stored = jsonDecode(await file.readAsString())['threads'] as Map;
    expect(stored['1']['r'], 9);
    expect(stored['2']['r'], 8);
  });

  test('writes are debounced and coalesced; flush forces them out', () async {
    final index = make(file, writeDelay: const Duration(milliseconds: 100));
    index.markRead(1, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    index.markRead(2, 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      file.existsSync(),
      isFalse,
      reason: 'still inside the debounce window',
    );

    await Future<void>.delayed(const Duration(milliseconds: 600));
    final stored = jsonDecode(await file.readAsString())['threads'] as Map;
    expect(stored.keys.toSet(), {'1', '2'});

    index.markRead(3, 3);
    await index.flush();
    final flushed = jsonDecode(await file.readAsString())['threads'] as Map;
    expect(flushed.containsKey('3'), isTrue);
  });

  test(
    'attach swaps in storage, keeping listeners and earlier marks',
    () async {
      final index = make(null)..markRead(1, 5);
      var n = 0;
      index.addListener(() => n++);
      await index.attach(file);
      expect(index.stateOf(1, replies: 5), isA<ThreadReadSeen>());
      await index.flush();
      final stored = jsonDecode(await file.readAsString())['threads'] as Map;
      expect(stored.containsKey('1'), isTrue);
      index.markRead(2, 1);
      expect(n, greaterThan(0));
    },
  );

  test(
    'repeat open refreshes at without notifying, so it outlives stale',
    () async {
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'threads': {
            '1': {'r': 1, 'at': 1000},
            '2': {'r': 1, 'at': 2000},
          },
        }),
      );
      final index = make(file, capacity: 2);
      await index.load();
      var n = 0;
      index.addListener(() => n++);
      index.markRead(1, 1);
      expect(n, 0);
      index.markRead(3, 1);
      expect(index.stateOf(1, replies: 1), isA<ThreadReadSeen>());
      expect(index.stateOf(2, replies: 1), isA<ThreadReadUnseen>());
    },
  );

  test('future-dated entries cannot evict the one just marked', () async {
    final future = DateTime.now().millisecondsSinceEpoch + 10000000;
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'threads': {
          '1': {'r': 1, 'at': future},
          '2': {'r': 1, 'at': future + 1},
        },
      }),
    );
    final index = make(file, capacity: 2);
    await index.load();
    index.markRead(3, 1);
    expect(index.stateOf(3, replies: 1), isA<ThreadReadSeen>());
    expect(index.stateOf(1, replies: 1), isA<ThreadReadUnseen>());
  });
}
