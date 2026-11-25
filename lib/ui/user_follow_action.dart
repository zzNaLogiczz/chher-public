/// Local follow actions shared by profiles, floor menus and the following list.
library;

import 'package:flutter/widgets.dart';

import '../data/follow_index.dart';
import '../data/user_block_index.dart';
import '../di.dart';
import 'feedback.dart';

Future<bool> toggleUserFollow(
  BuildContext context, {
  required String uid,
  required String name,
  String? avatarUrl,
  FollowIndex? index,
  int? lastTid,
}) async {
  final follows = index ?? followIndex;
  final own = follows.uid;
  if (own == null) {
    AppToast.show(context, chhSession.loggedIn ? '账号信息尚未就绪，请稍后重试' : '登录后可关注');
    return false;
  }
  final blocks = userBlockIndex.uid == own ? userBlockIndex : null;
  if (!follows.accountReady || blocks?.accountReady == false) {
    AppToast.show(context, '账号信息尚未就绪，请稍后重试');
    return false;
  }
  final revision = chhSession.identityRevision;
  final epoch = follows.epoch;
  bool isCurrent() =>
      revision == chhSession.identityRevision && epoch == follows.epoch;

  await follows.load();
  await blocks?.load();
  final id = UserBlockIndex.normalizeUid(uid);
  if (!context.mounted ||
      !isCurrent() ||
      id == null ||
      id == own ||
      (blocks?.uid == own && blocks?.isBlocked(id) == true)) {
    return false;
  }
  final followed = follows.isFollowed(id);
  final first = !follows.hasEverFollowed;
  final saved = followed
      ? await follows.unfollow(id)
      : await follows.follow(
          uid: id,
          name: name,
          avatar: avatarUrl,
          lastTid: lastTid,
        );
  if (context.mounted && isCurrent()) {
    AppToast.show(
      context,
      !saved
          ? follows.lastError ?? '关注状态未保存，请重试'
          : followed
          ? '已取消关注'
          : first
          ? '已关注，新帖在「消息」里看'
          : '已关注',
    );
  }
  return saved;
}
