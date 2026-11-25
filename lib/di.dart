/// 依赖入口:一个 ChhClient 负责传输与缓存,仓库按域做解析编排
///
/// 后续复杂化时换 riverpod,当前规模直接用全局实例最直观。
/// 离线开发:flutter run --dart-define=chh_source=file(读 test_data 样本)
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'data/follow_index.dart';
import 'data/follow_poller.dart';
import 'data/forum_repository.dart';
import 'data/history_index.dart';
import 'data/link_preview_repository.dart';
import 'data/message_repository.dart';
import 'data/portal_repository.dart';
import 'data/post_repository.dart';
import 'data/rating_repository.dart';
import 'data/poll_repository.dart';
import 'data/post_interaction_repository.dart';
import 'data/user_block_index.dart';
import 'data/space_repository.dart';
import 'core/accounts.dart';
import 'core/app_log.dart';
import 'core/app_paths.dart';
import 'core/appearance.dart';
import 'core/reading_prefs.dart';
import 'core/log_store.dart';
import 'core/message_notifications.dart';
import 'network/chh_client.dart';
import 'network/chh_session.dart';
import 'data/image_disk_cache.dart';
import 'data/thread_read_index.dart';
import 'data/favorite_repository.dart';
import 'data/user_group_levels.dart';

final ChhClient chhClient = ChhClient.createDefault();
final AccountStore accountStore = AccountStore();
final ChhSession chhSession = ChhSession(chhClient, accounts: accountStore);
final AppearanceController appearance = AppearanceController();
final ReadingPrefsController readingPrefs = ReadingPrefsController();
final MessageNotifications messageNotifications = MessageNotifications(
  chhSession,
);

final ForumRepository forumRepo = ForumRepository(
  chhClient,
  session: chhSession,
  follows: followIndex,
);
final PortalRepository portalRepo = PortalRepository(chhClient);
final MessageRepository messageRepo = MessageRepository(chhClient);
final SpaceRepository spaceRepo = SpaceRepository(
  chhClient,
  follows: followIndex,
);
final UserGroupLevels userGroupLevels = UserGroupLevels(chhClient);
final PollRepository pollRepo = PollRepository(
  chhClient,
  uid: () =>
      chhSession.loggedIn ? int.tryParse(chhSession.badges.uid ?? '') : null,
  sessionRevision: () => chhSession.identityRevision,
);
final PostRepository postRepo = PostRepository(chhClient);
final RatingRepository ratingRepo = RatingRepository(
  chhClient,
  sessionRevision: () => chhSession.identityRevision,
);
final PostInteractionRepository postInteractionRepo = PostInteractionRepository(
  chhClient,
  loggedIn: () => chhSession.loggedIn,
  sessionIdentity: () => chhSession.loggedIn ? chhSession.badges.uid : null,
  sessionRevision: () => chhSession.identityRevision,
);
final FavoriteIndex favoriteIndex = FavoriteIndex(null);
final FavoriteRepository favoriteRepo = FavoriteRepository(
  chhClient,
  favoriteIndex,
);

/// 正文站内卡片的标题与时间;全局一份,翻页、换楼层都能复用缓存
final LinkPreviewRepository linkPreviewRepo = LinkPreviewRepository.live(
  chhClient,
  portalRepo,
);

/// 启动时接线,必须由 main() 显式调用
///
/// 不要用顶层 final 的惰性初始化来做副作用:Dart 只在变量被读取时才初始化它,
/// 没人读就永远不执行 —— 之前页头观察钩子就是这样从未生效,
/// 表现为个人中心始终显示「已登录」而不是账号名。
Future<void> setupDependencies() {
  // 进后台时进程随时可能被回收,debounce/周期定时器来不及触发,先把数据落盘
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addObserver(_lifecycleFlusher);
  accountStore.start();
  // 让会话顺带观察每次页面响应,从页头取账号与未读计数,不额外发请求
  chhClient.htmlObserver = chhSession.observeHtml;
  messageNotifications.start();
  AppLog.i('BOOT', '页头观察已接线');
  // 日志目录靠平台通道异步解析,不能 await 阻塞冷启动;就绪前的日志留在内存缓冲,接线时补写
  unawaited(_attachLogStore());
  // 图片缓存目录同样异步解析,就绪前图片照常直连下载
  unawaited(_attachImageCache());
  chhSession.addListener(_syncMeCache);
  unawaited(_attachMeCache());
  // 已读账本放在 filesDir(系统不得回收),同样异步解析;就绪前的标记留在内存,接线时补写
  unawaited(_attachReadIndex());
  _followPoller ??= FollowPoller(
    index: followIndex,
    fetchThreads: spaceRepo.followedThreads,
  );
  chhSession.addListener(_localAccountSessionChanged);
  _localAccountSessionChanged();
  unawaited(_attachHistory());
  unawaited(_attachGroupLevels());
  pollStorageReady = _attachPollChoices();
  chhSession.addListener(_favoriteSessionChanged);
  _favoriteStorage = _attachFavoriteIndex();
  _favoriteSessionChanged();
  return accountStore.recover();
}

Future<void> _favoriteStorage = Future<void>.value();
int? _favoriteUid;
bool? _favoriteStartup;

Future<void> _attachFavoriteIndex() async {
  final dir = await AppPaths.instance.subdir('favorites');
  if (dir != null) {
    await favoriteIndex.attach(File('${dir.path}/index-v1.json'));
  }
}

void _favoriteSessionChanged() {
  // uid 常由登录后的首个页头补齐,沿用 Cookie 恢复时的判定。
  if (!chhSession.loggedIn) {
    _favoriteStartup = null;
  } else {
    _favoriteStartup ??= !chhSession.initialRefreshComplete;
  }
  final uid = chhSession.loggedIn
      ? int.tryParse(chhSession.badges.uid ?? '')
      : null;
  if (uid == _favoriteUid) return;
  final startup = _favoriteStartup ?? false;
  _favoriteUid = uid;
  favoriteIndex.setUid(uid);
  if (uid == null) return;
  _favoriteStartup = false;
  unawaited(_syncFavoritesForSession(favoriteIndex.epoch, startup: startup));
}

Future<void> _syncFavoritesForSession(
  int epoch, {
  required bool startup,
}) async {
  await _favoriteStorage;
  await favoriteIndex.load();
  if (epoch != favoriteIndex.epoch || !chhSession.loggedIn) return;
  final last = favoriteIndex.lastSyncedAt;
  if (!startup ||
      last == null ||
      DateTime.now().difference(last) > const Duration(hours: 6)) {
    await favoriteRepo.sync();
  }
}

Future<void> _attachLogStore() async {
  final dir = await AppPaths.instance.subdir('logs');
  if (dir != null) AppLog.attachStore(LogStore(dir));
}

Future<void> _attachImageCache() async {
  final dir = await AppPaths.instance.subdir('imgcache', inCache: true);
  if (dir == null) return;
  final cache = ImageDiskCache(dir);
  imageDiskCache = cache;
  // 目录扫描要逐个 stat,提前在后台预热,避免首批图片的 read 为它买单
  unawaited(cache.totalBytes());
}

Future<void> _attachReadIndex() async {
  final dir = await AppPaths.instance.subdir('read');
  if (dir == null) return;
  await threadReadIndex.attach(File('${dir.path}/threads-v1.json'));
}

bool _meWasLoggedIn = false;
void _syncMeCache() {
  if (chhSession.loggedIn && chhSession.badges.uid != null) {
    spaceRepo.meCache.select(chhSession.badges.uid);
  } else if (_meWasLoggedIn && !chhSession.loggedIn) {
    spaceRepo.meCache.select(null);
  }
  _meWasLoggedIn = chhSession.loggedIn;
}

Future<void> _attachMeCache() async {
  final dir = await AppPaths.instance.subdir('account');
  if (dir != null) {
    await spaceRepo.meCache.attach(File('${dir.path}/me-v1.json'));
  }
}

void _localAccountSessionChanged() {
  final uid = chhSession.loggedIn ? chhSession.badges.uid : null;
  final revision = chhSession.identityRevision;
  unawaited(followIndex.setUid(uid, identityRevision: revision));
  unawaited(userBlockIndex.setUid(uid, identityRevision: revision));
  _updateFollowPoller();
}

FollowPoller? _followPoller;
FollowPoller? get followPoller => _followPoller;

void _updateFollowPoller([AppLifecycleState? state]) {
  final lifecycle = state ?? WidgetsBinding.instance.lifecycleState;
  _followPoller?.update(
    foreground: lifecycle == null || lifecycle == AppLifecycleState.resumed,
    loggedIn:
        followIndex.uid != null &&
        chhSession.loggedIn &&
        !chhSession.accountOperationInProgress &&
        !chhSession.currentExpired,
    sessionRevision: chhSession.identityRevision,
  );
}

Future<void> _attachHistory() async {
  final dir = await AppPaths.instance.subdir('read');
  if (dir != null) {
    await historyIndex.attach(File('${dir.path}/history-v1.json'));
  }
}

Future<void> pollStorageReady = Future<void>.value();

Future<void> _attachPollChoices() async {
  final dir = await AppPaths.instance.subdir('polls');
  if (dir != null) await pollRepo.attach(File('${dir.path}/choices-v1.json'));
}

Future<void> _attachGroupLevels() async {
  final dir = await AppPaths.instance.subdir('groups');
  if (dir != null) await userGroupLevels.attach(dir);
}

final _lifecycleFlusher = LifecycleFlusher();

/// Flushes pending local writes when the app leaves the foreground.
/// Also snapshots the active account once per trip to the background.
class LifecycleFlusher with WidgetsBindingObserver {
  bool _inBackground = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateFollowPoller(state);
    if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      unawaited(accountStore.reload());
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_inBackground) {
        _inBackground = true;
        unawaited(chhSession.captureCurrent());
      }
      unawaited(threadReadIndex.flush());
      unawaited(userBlockIndex.flush());
      unawaited(followIndex.flush());
      unawaited(historyIndex.flush());
      unawaited(favoriteIndex.flush());
      unawaited(spaceRepo.meCache.flush());
      unawaited(pollRepo.flush());
      unawaited(AppLog.flush());
    }
  }
}
