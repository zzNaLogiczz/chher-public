/// 个人中心域读操作:资料、我的帖子、收藏、积分、权限、勋章
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/chh_urls.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/misc_parser.dart';
import '../parser/space_parser.dart';
import 'follow_index.dart';
import 'me_profile_cache.dart';

UserProfile _parseProfile(({String html, String uid}) request) =>
    parseUserProfile(request.html, uid: request.uid);

class SpaceRepository {
  final ChhClient client;
  final FollowIndex? follows;
  const SpaceRepository(this.client, {this.follows});
  static final _meCaches = Expando<MeProfileCache>();
  MeProfileCache get meCache => _meCaches[this] ??= MeProfileCache();

  Future<UserProfile> profile(String uid, {bool refresh = false}) async {
    final html = await client.getHtml(ChhUrls.userSpace(uid), refresh: refresh);
    return compute(_parseProfile, (html: html, uid: uid));
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
    final index = follows;
    final followEpoch = index?.epoch;
    final result = await _threads(
      ChhUrls.spaceThreads(
        uid: uid,
        view: view,
        type: type,
        filter: filter,
        page: page,
      ),
      refresh: refresh,
    );
    if (index != null &&
        index.epoch == followEpoch &&
        uid != null &&
        type == 'thread') {
      unawaited(index.sightThreads(_followSummaries(uid, result.items)));
    }
    return result;
  }

  Future<List<ThreadSummary>> followedThreads(
    String uid,
    bool Function() shouldContinue,
  ) async {
    final page = await _threads(
      ChhUrls.spaceThreads(uid: uid, type: 'thread'),
      refresh: true,
      fallback: false,
      shouldContinue: shouldContinue,
    );
    return _followSummaries(uid, page.items);
  }

  List<ThreadSummary> _followSummaries(String uid, List<MyThread> threads) => [
    for (final item in threads)
      ThreadSummary(
        tid: item.tid,
        title: item.title,
        author: '',
        authorUid: uid,
        forumName: item.forumName,
        forumFid: item.forumFid,
        replies: item.replies,
        views: item.views ?? 0,
        // The space list only shows the last reply time. With zero replies
        // it is still the time of the opening post.
        createdAtRaw: item.replies == 0 ? item.lastTimeRaw : null,
      ),
  ];

  Future<Paged<MyThread>> _threads(
    Uri url, {
    required bool refresh,
    bool fallback = true,
    bool Function()? shouldContinue,
  }) async => parseMyThreads(
    await client.getHtml(
      url,
      refresh: refresh,
      fallback: fallback,
      shouldContinue: shouldContinue,
    ),
  );

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
}
