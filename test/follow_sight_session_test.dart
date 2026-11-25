import 'dart:async';

import 'package:chh_app/data/follow_index.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/space_repository.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _html = '''
<form id="delform">
  <table><tbody id="normalthread_120"><tr>
    <th><a class="xst" href="thread-120-1-1.html">装机主题</a></th>
    <td><a href="forum-22-1.html">电脑硬件</a></td>
    <td class="by"><cite><a href="space-uid-42.html">作者</a></cite>
      <em>2026-11-25 11:00</em>
    </td>
    <td class="num"><a>3</a></td>
  </tr></tbody></table>
</form>
''';

class _Fetcher extends ChhFetcher {
  final response = Completer<ChhResponse>();

  @override
  String get name => '关注测试样例';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) =>
      response.future;
}

void main() {
  final reads = <String, Future<int> Function(ChhClient, FollowIndex)>{
    'forum': (client, index) async => (await ForumRepository(
      client,
      follows: index,
    ).threadList(22)).threads.single.tid,
    'profile': (client, index) async => (await SpaceRepository(
      client,
      follows: index,
    ).threads(uid: '42', type: 'thread')).items.single.tid,
  };

  for (final MapEntry(key: source, value: read) in reads.entries) {
    test(
      'a late $source response cannot add activity to another account',
      () async {
        final index = FollowIndex.forTesting(null);
        addTearDown(index.dispose);
        final fetcher = _Fetcher();
        final client = ChhClient(fetchers: [fetcher]);

        final followedAt = DateTime(2026, 11, 25, 10);
        await index.follow(uid: '42', name: '作者', at: followedAt);
        final previous = read(client, index);
        await index.setUid('901');
        await index.follow(uid: '42', name: '作者', at: followedAt);

        fetcher.response.complete(const ChhResponse(200, _html));
        expect(await previous, 120);
        await Future<void>.delayed(Duration.zero);
        expect(index.activities, isEmpty);
        expect(index.unseenCount, 0);

        expect(await read(client, index), 120);
        await Future<void>.delayed(Duration.zero);
        final activity = index.activities.single;
        final isForum = source == 'forum';
        expect(activity.thread.tid, 120);
        expect(activity.thread.createdAt, isForum ? isNotNull : isNull);
        expect(activity.unseen, isForum);
        expect(index.unseenCount, isForum ? 1 : 0);
        expect(index.all.single.lastTid, 120);
      },
    );
  }
}
