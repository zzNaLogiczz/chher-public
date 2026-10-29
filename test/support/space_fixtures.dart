/// Offline samples for account layout checks; no network or source writes.
library;

import 'package:chh_app/data/space_repository.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';

class FixtureSpace extends SpaceRepository {
  FixtureSpace() : super(ChhClient(fetchers: []));
  final favoriteRequests = <FavoriteType>[];
  final threadRequests = <String?>[];
  final settingRequests = <String?>[];
  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) async =>
      UserProfile(
        uid: uid,
        name: '装机爱好者',
        stats: const {'主题': '128', '回复': '3600'},
        profile: const {'个人签名': '记录日常装机与使用体验，交流真实感受', '所在地': '上海'},
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
  @override
  Future<SettingsForm> settings({
    String ac = 'profile',
    String? op,
    bool refresh = false,
  }) async {
    settingRequests.add(op);
    return const SettingsForm(
      title: '账号资料',
      fields: [
        SettingField(name: 'bio', label: '个人签名', value: '分享真实体验，记录每一次升级'),
        SettingField(name: 'place', label: '所在地', value: '上海'),
      ],
    );
  }
}
