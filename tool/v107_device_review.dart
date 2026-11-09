/// Isolated device smoke target. Every transport is a local fixture.
library;

import 'package:flutter/material.dart';
import 'package:chh_app/data/user_block_index.dart';
import 'package:chh_app/data/post_interaction_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/models/post_interaction.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/blocked_users_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/app_button.dart';

const _actor = '999999991';
final _blocks = UserBlockIndex(null);
final _interactions = PostInteractionRepository(
  chhClient,
  sessionIdentity: () => _actor,
  sessionRevision: () => chhSession.identityRevision,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  chhClient.fetchers
    ..clear()
    ..add(_Fixtures());
  chhSession.loggedIn = true;
  chhSession.badges = const HeaderBadges(
    notices: 0,
    messages: 0,
    uid: _actor,
    userName: '离线示例账号',
  );
  runApp(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: const _ReviewHome(),
      builder: (context, child) => Column(
        children: [
          Material(
            color: AppTokens.of(context).accentFill,
            child: SafeArea(
              bottom: false,
              child: const SizedBox(
                height: 32,
                child: Center(
                  child: Text('离线验收 / 不会发送到论坛', style: TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ),
          Expanded(child: child!),
        ],
      ),
    ),
  );
}

class _ReviewHome extends StatelessWidget {
  const _ReviewHome();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('v1.0.7 离线验收')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: '黑名单搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlockedUsersPage(index: _blocks),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: '点评与评分',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ThreadDetailPage(
                  tid: 900007,
                  title: '离线验收讨论',
                  blockIndex: _blocks,
                  interactions: _interactions,
                  loadPage: (page, uid, refresh) async => ThreadDetail(
                    tid: 900007,
                    title: '离线验收讨论',
                    fid: 1,
                    posts: const [
                      Post(
                        pid: 900071,
                        floor: 1,
                        author: '示例楼主',
                        authorUid: '987001',
                        timeRaw: '12:00',
                        content: [TextBlock('本页仅使用离线样例。可从更多菜单检查点评和评分输入。')],
                        actions: PostActionCapabilities(
                          comment: PostActionPermission.allowed,
                          rating: PostActionPermission.allowed,
                        ),
                      ),
                      Post(
                        pid: 900072,
                        floor: 2,
                        author: '示例回复者',
                        authorUid: '987002',
                        timeRaw: '12:01',
                        content: [TextBlock('示例回复。')],
                        actions: PostActionCapabilities(
                          comment: PostActionPermission.allowed,
                          rating: PostActionPermission.allowed,
                        ),
                      ),
                    ],
                    page: const PageInfo(current: 1, hasNext: false),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Fixtures implements ChhFetcher {
  @override
  String get name => 'offline-v107';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    final q = url.queryParameters;
    final tid = q['tid'] ?? '900007', pid = q['pid'] ?? '900071';
    if (q['action'] == 'comment') {
      return ChhResponse(
        200,
        '''<form method="post" action="forum.php?mod=post&amp;action=reply&amp;comment=yes&amp;tid=$tid&amp;pid=$pid&amp;commentsubmit=yes"><input type="hidden" name="formhash" value="offline-fixture"><textarea name="message" maxlength="200"></textarea></form>''',
      );
    }
    if (q['action'] == 'rate') {
      return ChhResponse(
        200,
        '''<form method="post" action="forum.php?mod=misc&amp;action=rate&amp;ratesubmit=yes"><input type="hidden" name="formhash" value="offline-fixture"><table class="dt"><tr><td>邪恶指数</td><td><input name="score1" value="0"> -10 ~ 10 <ul id="scoreoption1"><li>+1</li><li>+5</li></ul></td><td>6</td></tr></table><ul id="reasonselect"></ul></form>''',
      );
    }
    return const ChhResponse(200, '<div id="messagetext">离线验收不访问此页面</div>');
  }

  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) async =>
      const ChhResponse(403, '<div id="messagetext">离线验收不执行发送</div>');
  @override
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) async => throw UnsupportedError('offline');
  @override
  Future<void> dispose() async {}
}
