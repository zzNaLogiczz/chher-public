/// 依赖入口:一个 ChhClient 负责传输与缓存,仓库按域做解析编排
///
/// 后续复杂化时换 riverpod,当前规模直接用全局实例最直观。
/// 离线开发:flutter run --dart-define=chh_source=file(读 test_data 样本)
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'data/forum_repository.dart';
import 'data/link_preview_repository.dart';
import 'data/message_repository.dart';
import 'data/portal_repository.dart';
import 'data/post_repository.dart';
import 'data/space_repository.dart';
import 'core/app_log.dart';
import 'core/app_paths.dart';
import 'core/appearance.dart';
import 'core/log_store.dart';
import 'network/chh_client.dart';
import 'network/chh_session.dart';
import 'data/image_disk_cache.dart';
import 'data/thread_read_index.dart';
import 'data/favorite_repository.dart';
import 'data/user_group_levels.dart';

final ChhClient chhClient = ChhClient.createDefault();
final ChhSession chhSession = ChhSession(chhClient);
final AppearanceController appearance = AppearanceController();

final ForumRepository forumRepo = ForumRepository(
  chhClient,
  session: chhSession,
);
final PortalRepository portalRepo = PortalRepository(chhClient);
final MessageRepository messageRepo = MessageRepository(chhClient);
final SpaceRepository spaceRepo = SpaceRepository(chhClient);
final UserGroupLevels userGroupLevels = UserGroupLevels(chhClient);
final PostRepository postRepo = PostRepository(chhClient);
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
void setupDependencies() {
  // 进后台时进程随时可能被回收,debounce/周期定时器来不及触发,先把数据落盘
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addObserver(_lifecycleFlusher);
  // 让会话顺带观察每次页面响应,从页头取账号与未读计数,不额外发请求
  chhClient.htmlObserver = chhSession.observeHtml;
  AppLog.i('BOOT', '页头观察已接线');
  // 日志目录靠平台通道异步解析,不能 await 阻塞冷启动;就绪前的日志留在内存缓冲,接线时补写
  unawaited(_attachLogStore());
  // 图片缓存目录同样异步解析,就绪前图片照常直连下载
  unawaited(_attachImageCache());
  // 已读账本放在 filesDir(系统不得回收),同样异步解析;就绪前的标记留在内存,接线时补写
  unawaited(_attachReadIndex());
  unawaited(_attachGroupLevels());
  chhSession.addListener(_favoriteSessionChanged);
  _favoriteStorage = _attachFavoriteIndex();
  _favoriteSessionChanged();
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

Future<void> _attachGroupLevels() async {
  final dir = await AppPaths.instance.subdir('groups');
  if (dir != null) await userGroupLevels.attach(dir);
}

final _lifecycleFlusher = LifecycleFlusher();

/// Flushes the read ledger and the log when the app leaves the foreground.
/// Holds no timer of its own; both flushes are no-ops while nothing is attached.
class LifecycleFlusher with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(threadReadIndex.flush());
      unawaited(favoriteIndex.flush());
      unawaited(AppLog.flush());
    }
  }
}
