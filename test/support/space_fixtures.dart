/// Offline samples for account layout checks; no network or source writes.
library;

import 'package:chh_app/data/space_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';

class FixtureSpace extends SpaceRepository {
  FixtureSpace() : super(ChhClient(fetchers: []));
  final favoriteRequests = <FavoriteType>[];
  final threadRequests = <String?>[];
  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) async =>
      UserProfile(
        uid: uid,
        name: '装机爱好者',
        group: '权天使',
        onlineHours: 2845,
        credits: 2329,
        nextLevelCredits: 171,
        evil: 1583,
        threads: 128,
        replies: 3600,
        friends: 15,
        registeredAt: '2013-6-1 21:59',
        lastVisitAt: '2026-10-30 11:43',
        lastPostAt: '2026-10-29 22:46',
        portalArticles: 0,
      );
  @override
  Future<Paged<FavoriteItem>> favorites({
    FavoriteType type = FavoriteType.all,
    int page = 1,
    bool refresh = false,
  }) async {
    favoriteRequests.add(type);
    return const Paged(
      page: PageInfo(current: 1, hasNext: false),
      items: [
        FavoriteItem(
          favid: 'sample-1',
          title: '分享一台安静的小型工作站',
          url: 'https://www.chiphell.com/thread-42-1-1.html',
          tid: 42,
          timeRaw: '2026-10-26',
        ),
        FavoriteItem(
          favid: 'sample-2',
          title: '电脑讨论',
          url: 'https://www.chiphell.com/forum-80-1.html',
          fid: 80,
        ),
      ],
    );
  }

  @override
  Future<Paged<MyThread>> threads({
    String? uid,
    String view = 'me',
    String? type,
    String? filter,
    int page = 1,
    bool refresh = false,
  }) async {
    threadRequests.add(type);
    return const Paged(
      page: PageInfo(current: 1, hasNext: false),
      items: [
        MyThread(
          tid: 42,
          title: '分享一台安静的小型工作站',
          forumName: '电脑讨论',
          replies: 18,
          views: 720,
          replySnippets: [
            MyReplySnippet(
              pid: 4242,
              text: '风道配置和实际噪声表现如何？',
              targetUrl:
                  'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=42&pid=4242',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<SiteTable> creditLog({int page = 1, bool refresh = false}) async =>
      const SiteTable(
        headers: ['操作', '积分变更', '时间'],
        rows: [
          ['发表回复', '+2', '2026-10-26 12:30'],
          ['参与讨论', '+1', '2026-10-25 09:15'],
        ],
      );
  @override
  Future<List<MedalItem>> medals({
    bool mine = false,
    bool refresh = false,
  }) async => const [
    MedalItem(
      id: 'sample-medal',
      name: '社区分享纪念勋章',
      description: '持续分享有价值的原创内容，与大家交流使用心得。',
    ),
  ];
}
