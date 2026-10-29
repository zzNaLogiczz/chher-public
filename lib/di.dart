/// 依赖入口:一个 ChhClient 负责传输与缓存,仓库按域做解析编排
///
/// 后续复杂化时换 riverpod,当前规模直接用全局实例最直观。
/// 离线开发:flutter run --dart-define=chh_source=file(读 test_data 样本)
library;

import 'data/forum_repository.dart';
import 'data/link_preview_repository.dart';
import 'data/message_repository.dart';
import 'data/portal_repository.dart';
import 'data/post_repository.dart';
import 'data/space_repository.dart';
import 'core/app_log.dart';
import 'network/chh_client.dart';
import 'network/chh_session.dart';

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
}
