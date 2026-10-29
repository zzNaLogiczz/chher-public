/// 依赖入口:一个 ChhClient 负责传输与缓存,仓库按域做解析编排
///
/// 后续复杂化时换 riverpod,当前规模直接用全局实例最直观。
/// 离线开发:flutter run --dart-define=chh_source=file(读 test_data 样本)
library;

import 'dart:async';

import 'data/forum_repository.dart';
import 'data/link_preview_repository.dart';
import 'data/message_repository.dart';
import 'data/portal_repository.dart';
import 'data/post_repository.dart';
import 'data/space_repository.dart';
import 'core/app_log.dart';
import 'core/app_paths.dart';
import 'core/log_store.dart';
import 'network/chh_client.dart';
import 'network/chh_session.dart';
import 'data/image_disk_cache.dart';

final ChhClient chhClient = ChhClient.createDefault();
final ChhSession chhSession = ChhSession(chhClient);

final ForumRepository forumRepo = ForumRepository(chhClient);
final PortalRepository portalRepo = PortalRepository(chhClient);
final MessageRepository messageRepo = MessageRepository(chhClient);
final SpaceRepository spaceRepo = SpaceRepository(chhClient);
final PostRepository postRepo = PostRepository(chhClient);

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
  // 让会话顺带观察每次页面响应,从页头取账号与未读计数,不额外发请求
  chhClient.htmlObserver = chhSession.observeHtml;
  AppLog.i('BOOT', '页头观察已接线');
  // 日志目录靠平台通道异步解析,不能 await 阻塞冷启动;就绪前的日志留在内存缓冲,接线时补写
  unawaited(_attachLogStore());
  // 图片缓存目录同样异步解析,就绪前图片照常直连下载
  unawaited(_attachImageCache());
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
