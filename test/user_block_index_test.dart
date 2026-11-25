import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chh_app/data/user_block_index.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chher-blocks-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'persists stable UID and removal, never matches by display name',
    () async {
      final file = File('${dir.path}/users.json');
      final first = UserBlockIndex.forTesting(file);
      expect(
        await first.block(uid: '0042', name: '同名用户', currentUid: '7'),
        isTrue,
      );
      expect(first.isBlocked('42'), isTrue);
      expect(first.isBlocked('同名用户'), isFalse);
      final restored = UserBlockIndex.forTesting(file);
      await restored.load();
      expect(restored.entries.single.name, '同名用户');
      expect(restored.isBlocked('0042'), isTrue);
      expect(await restored.unblock('42'), isTrue);
      final reopened = UserBlockIndex.forTesting(file);
      await reopened.load();
      expect(reopened.entries, isEmpty);
      first.dispose();
      restored.dispose();
      reopened.dispose();
    },
  );
  test('legacy records without avatar or date remain readable', () async {
    final file = File('${dir.path}/users.json');
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'users': [
          {'uid': '42', 'name': '旧用户'},
          {
            'uid': '43',
            'name': '有时间',
            'at': 1234,
            'avatar': 'https://example.test/a.png',
          },
        ],
      }),
    );
    final index = UserBlockIndex.forTesting(file);
    await index.load();
    expect(index.entries.length, 2);
    final legacy = index.entries.firstWhere((e) => e.uid == '42');
    expect(legacy.avatarUrl, isNull);
    expect(legacy.blockedAt.millisecondsSinceEpoch, 0);
    expect(legacy.note, isNull);
    expect(legacy.src, isNull);
    expect(await index.flush(), isTrue);
    final migrated = jsonDecode(await file.readAsString()) as Map;
    expect(migrated['version'], 2);
    expect((migrated['users'] as List).first, containsPair('note', null));
    expect((migrated['users'] as List).first, containsPair('src', null));
    final known = index.entries.firstWhere((e) => e.uid == '43');
    expect(known.avatarUrl, 'https://example.test/a.png');
    await index.unblock('43');
    await index.block(
      uid: known.uid,
      name: known.name,
      avatarUrl: known.avatarUrl,
      blockedAt: known.blockedAt,
    );
    final reopened = UserBlockIndex.forTesting(file);
    await reopened.load();
    expect(reopened.entries.first.avatarUrl, known.avatarUrl);
    expect(reopened.entries.first.blockedAt, known.blockedAt);
    reopened.dispose();
    index.dispose();
  });

  test(
    'note and source round-trip and editing a note preserves the source',
    () async {
      final file = File('${dir.path}/users-v1.json');
      final index = UserBlockIndex.forTesting(file);
      final family = '👨‍👩‍👧‍👦';
      final note = family * 200;
      final excerpt = family * 100;
      final at = DateTime(2026, 11, 25);
      expect(
        await index.block(
          uid: '0042',
          name: '作者',
          blockedAt: at,
          note: '$note多余文字',
          src: BlockedUserSource(
            tid: 123,
            pid: 456,
            floor: 3,
            title: '帖子标题',
            excerpt: '$excerpt多余文字',
          ),
        ),
        isTrue,
      );
      final reopened = UserBlockIndex.forTesting(file);
      await reopened.load();
      final entry = reopened.entries.single;
      expect(entry.note, note);
      expect(entry.src?.tid, 123);
      expect(entry.src?.pid, 456);
      expect(entry.src?.floor, 3);
      expect(entry.src?.title, '帖子标题');
      expect(entry.src?.excerpt, excerpt);

      expect(await reopened.updateNote('0042', '新备注'), isTrue);
      final edited = UserBlockIndex.forTesting(file);
      await edited.load();
      expect(edited.entries.single.note, '新备注');
      expect(edited.entries.single.src?.excerpt, excerpt);
      expect(edited.entries.single.blockedAt, at);
      expect(await edited.updateNote('42', ''), isTrue);
      expect(edited.entries.single.note, isNull);
      expect(await edited.updateNote('42', '${' ' * 200}正文'), isTrue);
      expect(edited.entries.single.note, isNull);
      index.dispose();
      reopened.dispose();
      edited.dispose();
    },
  );
  test('self and unknown IDs cannot be blocked', () async {
    final index = UserBlockIndex.forTesting(null);
    expect(
      await index.block(uid: '0042', name: '自己', currentUid: '42'),
      isFalse,
    );
    expect(await index.block(uid: '0', name: '未知'), isFalse);
    expect(await index.block(uid: '昵称', name: '昵称'), isFalse);
    expect(index.entries, isEmpty);
    index.dispose();
  });
  test('removal while disk load is pending cannot resurrect a user', () async {
    final gate = Completer<String>();
    final file = File('${dir.path}/users.json');
    final index = UserBlockIndex.forTesting(_DelayedFile(file, gate.future));
    final load = index.load();
    final remove = index.unblock('42');
    gate.complete(
      jsonEncode({
        'version': 1,
        'users': [
          {'uid': '42', 'name': '旧记录', 'at': 1},
        ],
      }),
    );
    await load;
    expect(await remove, isTrue);
    expect(index.entries, isEmpty);
    expect((jsonDecode(await file.readAsString())['users'] as List), isEmpty);
    index.dispose();
  });
  test(
    'concurrent changes are serialized and latest state survives reopening',
    () async {
      final file = File('${dir.path}/users.json');
      final index = UserBlockIndex.forTesting(file);
      await Future.wait([
        index.block(uid: '1', name: '甲'),
        index.block(uid: '2', name: '乙'),
        index.unblock('1'),
      ]);
      final reloaded = UserBlockIndex.forTesting(file);
      await reloaded.load();
      expect(reloaded.entries.map((e) => e.uid), ['2']);
      index.dispose();
      reloaded.dispose();
    },
  );
  test('write failure is reported, not a false saved success', () async {
    final barrier = File('${dir.path}/file');
    await barrier.writeAsString('keep');
    final index = UserBlockIndex.forTesting(File('${barrier.path}/users.json'));
    expect(await index.block(uid: '42', name: '用户'), isFalse);
    expect(index.lastError, isNotNull);
    expect(await barrier.readAsString(), 'keep');
    index.dispose();
  });
  test(
    'unreadable existing data is not overwritten by an empty projection',
    () async {
      final file = File('${dir.path}/users.json');
      await file.writeAsString('malformed');
      final index = UserBlockIndex.forTesting(file);
      await index.load();
      expect(await index.block(uid: '42', name: '用户'), isFalse);
      expect(await file.readAsString(), 'malformed');
      index.dispose();
    },
  );
}

class _DelayedFile implements File {
  final File target;
  final Future<String> read;
  _DelayedFile(this.target, this.read);
  @override
  String get path => target.path;
  @override
  Directory get parent => target.parent;
  @override
  Future<bool> exists() async => true;
  @override
  Future<String> readAsString({Encoding encoding = utf8}) => read;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
