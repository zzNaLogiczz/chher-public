/// 个人中心域读操作:资料、我的帖子、收藏、积分、权限、勋章、设置
library;

import '../core/chh_urls.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/misc_parser.dart';
import '../parser/space_parser.dart';

class SpaceRepository {
  final ChhClient client;
  const SpaceRepository(this.client);

  Future<UserProfile> profile(String uid, {bool refresh = false}) async {
    return parseUserProfile(
      await client.getHtml(ChhUrls.userSpace(uid), refresh: refresh),
      uid: uid,
    );
  }

  /// 我的主题 / 我的回复 / 我的点评 / 好友的帖子
  ///
  /// 个人帖子页是 #delform 下的裸表格,与版块页不是同一个外层结构。
  Future<Paged<MyThread>> threads({
    String? uid,
    String view = 'me',
    String? type,
    String? filter,
    int page = 1,
    bool refresh = false,
  }) async {
    final html = await client.getHtml(
      ChhUrls.spaceThreads(
        uid: uid,
        view: view,
        type: type,
        filter: filter,
        page: page,
      ),
      refresh: refresh,
    );
    return parseMyThreads(html);
  }

  Future<Paged<FavoriteItem>> favorites({
    FavoriteType type = FavoriteType.all,
    int page = 1,
    bool refresh = false,
  }) async {
    final html = await client.getHtml(
      ChhUrls.favorite(type: type.name, page: page),
      refresh: refresh,
    );
    return parseFavorites(html);
  }

  Future<CreditOverview> credit({bool refresh = false}) async {
    return parseCredit(
      await client.getHtml(
        ChhUrls.spacecp(ac: 'credit', op: 'base'),
        refresh: refresh,
      ),
    );
  }

  /// 积分收益记录。几十页,按页取。
  Future<SiteTable> creditLog({int page = 1, bool refresh = false}) async {
    return parseSiteTable(
      await client.getHtml(
        ChhUrls.spacecp(ac: 'credit', op: 'log', page: page),
        refresh: refresh,
      ),
    );
  }

  Future<List<MedalItem>> medals({
    bool mine = false,
    bool refresh = false,
  }) async {
    return parseMedals(
      await client.getHtml(ChhUrls.medal(mine: mine), refresh: refresh),
    );
  }

  /// 设置页只读展示。写操作不在本期范围,所以只解析控件与当前值。
  Future<SettingsForm> settings({
    String ac = 'profile',
    String? op,
    bool refresh = false,
  }) async {
    return parseSettingsForm(
      await client.getHtml(
        ChhUrls.spacecp(ac: ac, op: op),
        refresh: refresh,
      ),
    );
  }
}
