import 'dart:io';

import 'package:chh_app/data/follow_index.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chh-follows-');
    file = File('${directory.path}/follows-v1.json');
  });

  tearDown(() => directory.delete(recursive: true));

  FollowIndex open(File? storage) {
    final index = FollowIndex.forTesting(storage);
    addTearDown(index.dispose);
    return index;
  }

  test(
    'sight counts only newer topics and seen counts survive restart',
    () async {
      final index = open(file);
      final followedAt = DateTime(2026, 11, 24);
      final checkedAt = DateTime(2026, 11, 25);
      expect(await index.follow(uid: '0', name: '无效'), isFalse);
      expect(
        await index.follow(
          uid: ' 0042 ',
          name: ' 用户 ',
          avatar: 'avatar.png',
          at: followedAt,
          lastTid: 100,
        ),
        isTrue,
      );
      expect(index.isFollowed('42'), isTrue);
      await index.sight(uid: '42', tid: 100, fid: 22);
      await index.sight(uid: '42', tid: 99, fid: 22);
      await index.sight(uid: '7', tid: 101, fid: 22);
      expect(index.unseenCount, 0);

      await index.sight(uid: '0042', tid: 101, fid: 22);
      await index.sight(uid: '42', tid: 101, fid: 22);
      await index.sight(uid: '42', tid: 104, fid: 22);
      await index.sight(uid: '42', tid: 103, fid: 22);
      expect(index.unseenCount, 2);
      expect(index.all.single.lastCheck, isNull);
      await index.recordCheck('42', at: checkedAt);

      final reopened = open(file);
      await reopened.load();
      final entry = reopened.all.single;
      expect(entry.uid, '42');
      expect(entry.name, '用户');
      expect(entry.avatar, 'avatar.png');
      expect(entry.at, followedAt);
      expect(entry.lastCheck, checkedAt);
      expect(entry.lastTid, 104);
      expect(entry.unseen, 2);

      await reopened.markAllSeen();
      final seen = open(file);
      await seen.load();
      await seen.sight(uid: '42', tid: 104, fid: 22);
      expect(seen.unseenCount, 0);
      expect(seen.all.single.lastTid, 104);
      await seen.sight(uid: '42', tid: 110, fid: 22);
      expect(seen.unseenCount, 1);
      await seen.unfollow('0042');
      expect(seen.unseenCount, 0);
      final removed = open(file);
      await removed.load();
      expect(removed.isFollowed('42'), isFalse);
    },
  );

  test('trading sightings advance the watermark and count as unseen', () async {
    final index = open(file);
    await index.follow(uid: '42', name: '用户');
    await index.sight(uid: '42', tid: 105, fid: 26);
    await index.sight(uid: '42', tid: 106, fid: 328);
    await index.sight(uid: '42', tid: 107, fid: 0);
    expect(index.all.single.lastTid, 106);
    expect(index.unseenCount, 2);
  });

  test('a corrupt follows file is preserved and memory stays usable', () async {
    await file.writeAsString('invalid');
    final index = open(file);
    expect(await index.follow(uid: '42', name: '用户'), isFalse);
    expect(index.isFollowed('42'), isTrue);
    expect(index.lastError, isNotNull);
    expect(await file.readAsString(), 'invalid');
  });

  test('首次检查建立基线，活动详情和逐帖已见状态可重启恢复', () async {
    final index = open(file);
    final followedAt = DateTime(2026, 11, 25, 10);
    final checkedAt = DateTime(2026, 11, 25, 11);
    await index.follow(uid: '42', name: '装机爱好者', at: followedAt);
    await index.recordThreadCheck(index.all.single, [
      _topic(103, 26, at: checkedAt),
      _topic(104, 328, at: checkedAt),
      _topic(101, 22, at: followedAt),
      _topic(100, 22),
      _topic(102, 22, at: checkedAt),
    ], at: checkedAt);
    expect(index.activities.map((item) => item.thread.tid), [
      104,
      103,
      102,
      101,
      100,
    ]);
    expect(index.unseenCount, 3);

    final reopened = open(file);
    await reopened.load();
    expect(reopened.activities.first.thread.title, '主题 104');
    expect(reopened.activities.first.thread.forumName, '电脑硬件');
    expect(reopened.activities.first.thread.replies, 3);
    expect(reopened.activities.where((item) => item.unseen).length, 3);
    await reopened.markAllSeen();
    await reopened.sightThreads([_topic(102, 22, at: checkedAt)]);
    final seen = open(file);
    await seen.load();
    expect(seen.activities.any((item) => item.unseen), isFalse);
    expect(seen.unseenCount, 0);
    await seen.unfollow('42');
    expect(seen.activities, isEmpty);
    expect(seen.hasEverFollowed, isTrue);
  });

  test('已知创作时间的两条动态按发布顺序倒序排列', () async {
    final index = open(null);
    final earlier = DateTime(2026, 11, 24);
    final later = DateTime(2026, 11, 25);
    await index.follow(uid: '42', name: '装机爱好者', at: earlier);
    await index.sightThreads([
      _topic(100, 22, at: earlier),
      _topic(101, 22, at: later),
    ]);

    expect(index.activities.map((item) => item.thread.tid), [101, 100]);
    expect(index.activities.map((item) => item.at), [later, earlier]);
  });

  test('后续批次捕获的无时间老帖排在高 tid 主题之后', () async {
    final index = open(null);
    final firstCheck = DateTime(2026, 11, 24);
    final secondCheck = DateTime(2026, 11, 25);
    await index.follow(uid: '42', name: '装机爱好者', at: firstCheck);
    await index.recordThreadCheck(index.all.single, [
      _topic(102, 22, at: firstCheck),
    ], at: firstCheck);
    expect(index.activities.single.thread.tid, 102);

    await index.recordThreadCheck(index.all.single, [
      _topic(101, 22),
    ], at: secondCheck);

    expect(index.activities.map((item) => item.thread.tid), [102, 101]);
    expect(index.activities.last.thread.createdAt, isNull);
    expect(index.activities.last.at, secondCheck);
  });

  test('动态超过 200 条时丢弃捕获较晚但 tid 最小的主题', () async {
    final index = open(file);
    final firstCheck = DateTime(2026, 11, 24);
    final secondCheck = DateTime(2026, 11, 25);
    await index.follow(uid: '42', name: '装机爱好者', at: firstCheck);
    await index.recordThreadCheck(index.all.single, [
      for (var tid = 2; tid <= 201; tid++) _topic(tid, 22, at: firstCheck),
    ], at: firstCheck);
    expect(index.activities, hasLength(200));

    await index.recordThreadCheck(index.all.single, [
      _topic(1, 22),
    ], at: secondCheck);

    final retainedTids = [for (var tid = 201; tid >= 2; tid--) tid];
    expect(index.activities.map((item) => item.thread.tid), retainedTids);
    final reopened = open(file);
    await reopened.load();
    expect(reopened.activities.map((item) => item.thread.tid), retainedTids);
  });

  test('版块仓库顺带收录关注者的新主题，包括交易区，且不发额外请求', () async {
    final index = open(null);
    await index.follow(uid: '42', name: '装机爱好者', at: DateTime(2026));
    final fetcher = _ThreadListFixture();
    final repo = ForumRepository(
      ChhClient(fetchers: [fetcher]),
      follows: index,
    );
    await repo.threadList(26);
    await repo.threadList(328);
    await repo.threadList(22);
    await Future<void>.delayed(Duration.zero);
    expect(fetcher.requests, 3);
    expect(index.activities.first.thread.forumName, '电脑硬件');
    expect(index.activities.map((item) => item.thread.forumFid), [22, 328, 26]);
    expect(index.unseenCount, 3);
  });

  test('旧预览保存的交易区动态正常恢复并保留未读', () async {
    await file.writeAsString('''
      {"version":1,"users":[{"uid":"42","unseen":3,"lastTid":103}],
       "activities":[
        {"uid":"42","tid":101,"fid":26,"title":"旧交易区主题","at":0,"unseen":true},
        {"uid":"42","tid":102,"fid":328,"title":"交易区主题","at":1,"unseen":true},
        {"uid":"42","tid":103,"fid":22,"title":"普通主题","at":2,"unseen":true}
       ]}
    ''');
    final index = open(file);
    await index.load();
    expect(index.isFollowed('42'), isTrue);
    expect(index.activities.map((item) => item.thread.tid), [103, 102, 101]);
    expect(index.activities.every((item) => item.unseen), isTrue);
    expect(index.unseenCount, 3);

    await index.markAllSeen();
    expect(index.unseenCount, 0);
    expect(index.activities.every((item) => !item.unseen), isTrue);
  });
}

ThreadSummary _topic(int tid, int fid, {DateTime? at}) => ThreadSummary(
  tid: tid,
  title: '主题 $tid',
  author: '',
  authorUid: '42',
  createdAt: at,
  forumFid: fid,
  forumName: '电脑硬件',
  replies: 3,
  views: 0,
);

class _ThreadListFixture extends ChhFetcher {
  int requests = 0;

  @override
  String get name => '关注测试样例';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    requests++;
    final fid = url.queryParameters['fid'];
    final tid = 119 + requests;
    final forum = fid == '22' ? '电脑硬件' : '交易区';
    return ChhResponse(200, '''
      <div id="pt"><a href="forum-$fid-1.html">$forum</a></div>
      <table><tbody id="normalthread_$tid"><tr>
        <th><a class="xst" href="thread-$tid-1-1.html">主题 $tid</a></th>
        <td class="by"><cite><a href="space-uid-42.html">装机爱好者</a></cite>
          <em>2026-11-25 10:00</em>
        </td>
      </tr></tbody></table>
    ''');
  }
}
