import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chh_app/data/follow_index.dart';
import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory followsDir;
  late Directory blocksDir;
  late FollowIndex follows;
  late UserBlockIndex blocks;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chh-account-indexes-');
    followsDir = await Directory('${root.path}/follows').create();
    blocksDir = await Directory('${root.path}/blocks').create();
    follows = FollowIndex(directory: () async => followsDir);
    blocks = UserBlockIndex(directory: () async => blocksDir);
  });

  tearDown(() async {
    follows.dispose();
    blocks.dispose();
    await root.delete(recursive: true);
  });

  Future<void> switchTo(String? uid, {int? revision}) => Future.wait([
    follows.setUid(uid, identityRevision: revision),
    blocks.setUid(uid, identityRevision: revision),
  ]);

  File followFile(String uid) =>
      File('${followsDir.path}/$uid/follows-v1.json');
  File blockFile(String uid) => File('${blocksDir.path}/$uid/users-v1.json');

  test(
    'each account restores its own follows, activities and blocks',
    () async {
      await switchTo(' 0010 ');
      final followedAt = DateTime(2026, 11, 25, 10);
      await follows.follow(
        uid: '42',
        name: '关注甲',
        at: followedAt,
        lastTid: 100,
      );
      await follows.sightThreads([
        ThreadSummary(
          tid: 101,
          title: '甲的新帖',
          author: '关注甲',
          authorUid: '42',
          createdAt: DateTime(2026, 11, 25, 11),
          replies: 0,
          views: 0,
          forumFid: 22,
        ),
      ]);
      await blocks.block(uid: '70', name: '屏蔽甲', note: '甲的备注');
      expect(follows.unseenCount, 1);
      expect(follows.hasEverFollowed, isTrue);

      final switching = switchTo('20');
      expect(follows.all, isEmpty);
      expect(follows.activities, isEmpty);
      expect(follows.unseenCount, 0);
      expect(follows.hasEverFollowed, isFalse);
      expect(blocks.entries, isEmpty);
      await switching;
      await follows.follow(uid: '42', name: '关注乙');
      await blocks.block(uid: '70', name: '屏蔽乙', note: '乙的备注');
      expect(follows.activities, isEmpty);
      expect(blocks.entries.single.note, '乙的备注');

      await switchTo('10');
      expect(follows.all.single.name, '关注甲');
      expect(follows.activities.single.thread.title, '甲的新帖');
      expect(follows.unseenCount, 1);
      expect(follows.hasEverFollowed, isTrue);
      expect(blocks.entries.single.note, '甲的备注');

      await switchTo('20');
      expect(follows.all.single.name, '关注乙');
      expect(blocks.entries.single.note, '乙的备注');
      expect(follows.activities, isEmpty);
      expect(await followFile('10').exists(), isTrue);
      expect(await followFile('20').exists(), isTrue);
      expect(await blockFile('10').exists(), isTrue);
      expect(await blockFile('20').exists(), isTrue);
    },
  );

  test('legacy files move once to the first identified account', () async {
    final legacyFollows = File('${followsDir.path}/follows-v1.json');
    final legacyBlocks = File('${blocksDir.path}/users-v1.json');
    await legacyFollows.writeAsString(
      '{"version":1,"users":[{"uid":"42","name":"旧关注"}]}',
    );
    await legacyBlocks.writeAsString(
      '{"version":1,"users":[{"uid":"43","name":"旧黑名单"}]}',
    );
    await switchTo(null, revision: 1);
    expect(await legacyFollows.exists(), isTrue);
    expect(await legacyBlocks.exists(), isTrue);

    final first = switchTo('10', revision: 2);
    final second = switchTo('20', revision: 3);
    await Future.wait([first, second]);
    expect(follows.all, isEmpty);
    expect(blocks.entries, isEmpty);
    expect(await legacyFollows.exists(), isFalse);
    expect(await legacyBlocks.exists(), isFalse);
    expect(await followFile('20').exists(), isFalse);
    expect(await blockFile('20').exists(), isFalse);

    final reopenedFollows = FollowIndex(directory: () async => followsDir);
    final reopenedBlocks = UserBlockIndex(directory: () async => blocksDir);
    addTearDown(reopenedFollows.dispose);
    addTearDown(reopenedBlocks.dispose);
    await reopenedFollows.setUid('20');
    await reopenedBlocks.setUid('20');
    expect(reopenedFollows.all, isEmpty);
    expect(reopenedBlocks.entries, isEmpty);

    await reopenedFollows.setUid('10');
    await reopenedBlocks.setUid('10');
    expect(reopenedFollows.all.single.name, '旧关注');
    expect(reopenedBlocks.entries.single.name, '旧黑名单');
    final epoch = reopenedFollows.epoch;
    await reopenedFollows.setUid('10');
    expect(reopenedFollows.epoch, epoch);
  });

  test(
    'a preexisting account file is preserved across migration and restart',
    () async {
      final scoped = followFile('10');
      await scoped.parent.create();
      await scoped.writeAsString('{"version":1,"users":[{"uid":"42"}]}');
      final legacy = File('${followsDir.path}/follows-v1.json');
      await legacy.writeAsString('{"version":1,"users":[{"uid":"43"}]}');
      await follows.setUid('10');
      expect(follows.all.single.uid, '42');

      final reopened = FollowIndex(directory: () async => followsDir);
      addTearDown(reopened.dispose);
      await reopened.setUid('20');
      expect(reopened.all, isEmpty);
      expect(await followFile('20').exists(), isFalse);
      expect(await legacy.exists(), isTrue);
    },
  );

  test('logout shows empty state and blocks mutations and writes', () async {
    await switchTo('10');
    await follows.follow(uid: '42', name: '已关注');
    await blocks.block(uid: '43', name: '已屏蔽');
    final beforeFollows = await followFile('10').readAsString();
    final beforeBlocks = await blockFile('10').readAsString();

    await switchTo(null, revision: 2);
    expect(follows.all, isEmpty);
    expect(follows.activities, isEmpty);
    expect(follows.hasEverFollowed, isFalse);
    expect(follows.unseenCount, 0);
    expect(blocks.entries, isEmpty);
    expect(await follows.follow(uid: '99', name: '游客关注'), isFalse);
    expect(await follows.unfollow('42'), isFalse);
    expect(await blocks.block(uid: '99', name: '游客屏蔽'), isFalse);
    expect(await blocks.unblock('43'), isFalse);
    expect(await blocks.updateNote('43', '游客备注'), isFalse);
    await Future.wait([follows.flush(), blocks.flush()]);
    expect(await followsDir.list().map((e) => e.path).toList(), [
      followFile('10').parent.path,
    ]);
    expect(await blocksDir.list().map((e) => e.path).toList(), [
      blockFile('10').parent.path,
    ]);
    expect(await followFile('10').readAsString(), beforeFollows);
    expect(await blockFile('10').readAsString(), beforeBlocks);
  });

  test(
    'switching waits for both pending writes to the original account',
    () async {
      await switchTo('10');
      final staged = Completer<void>();
      follows.addListener(() {
        if (follows.isFollowed('42') && !staged.isCompleted) staged.complete();
      });
      final followWrite = follows.follow(uid: '42', name: '旧账号关注');
      await staged.future;
      final blockWrite = blocks.block(uid: '43', name: '旧账号拉黑');
      final switching = switchTo('20');
      await switching;
      expect(await followWrite, isTrue);
      expect(await blockWrite, isTrue);
      expect(follows.all, isEmpty);
      expect(blocks.entries, isEmpty);
      expect(await followFile('20').exists(), isFalse);
      expect(await blockFile('20').exists(), isFalse);
      expect(
        jsonDecode(
          await followFile('10').readAsString(),
        )['users'].single['uid'],
        '42',
      );
      expect(
        jsonDecode(await blockFile('10').readAsString())['users'].single['uid'],
        '43',
      );
    },
  );

  test(
    'a same-UID identity change rejects pre-switch async mutations',
    () async {
      await switchTo('10', revision: 1);
      await blocks.block(uid: '43', name: '已屏蔽', note: '旧备注');
      final previousEpoch = follows.epoch;
      final staleFollow = follows.follow(uid: '42', name: '旧操作');
      final staleNote = blocks.updateNote('43', '旧操作');
      await switchTo('10', revision: 2);
      expect(follows.epoch, greaterThan(previousEpoch));
      expect(await staleFollow, isFalse);
      expect(await staleNote, isFalse);
      expect(follows.all, isEmpty);
      expect(blocks.entries.single.note, '旧备注');
    },
  );

  test(
    'a failed write remains bound to its account and can be retried',
    () async {
      final obstruction = File(followFile('10').parent.path);
      await obstruction.writeAsString('x');
      await follows.setUid('10');
      expect(await follows.follow(uid: '42', name: '待保存'), isFalse);
      await follows.setUid('20');
      expect(follows.all, isEmpty);
      await obstruction.delete();
      await follows.setUid('10');
      expect(follows.all.single.name, '待保存');
      expect(await follows.flush(), isTrue);
      await follows.setUid('20');
      await follows.setUid('10');
      expect(follows.all.single.name, '待保存');
    },
  );
}
