/// Personal space keeps the account and frequent destinations within reach.
library;

import 'package:flutter/material.dart';
import '../di.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/account_widgets.dart';
import '../design/tokens.dart';
import '../ui/grouped.dart';
import '../update/update_controller.dart';
import 'favorites_page.dart';
import 'medals_page.dart';
import 'my_threads_page.dart';
import 'credit_log_page.dart';
import 'user_page.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});
  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '我的',
    surface: AppSurface.grouped,
    body: const MeBody(),
  );
}

class MeBody extends StatelessWidget {
  const MeBody({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: chhSession,
    builder: (context, _) {
      final me = chhSession.badges;
      final logged = chhSession.loggedIn;
      return ExpressivePageReveal(
        active: true,
        revision: (logged, me.uid),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 112),
          children: [
            // 身份一行:已登录进个人主页,未登录进登录页
            GroupedSection(
              children: [
                AccountIdentityRow(
                  name: logged ? (me.userName ?? '已登录') : '登录 CHH',
                  avatarUrl: logged ? me.avatarUrl : null,
                  detail: logged
                      ? (me.uid == null ? null : 'UID ${me.uid}')
                      : '收藏内容，参与讨论',
                  onTap: !logged
                      ? () => Navigator.of(context).pushNamed('/login')
                      : me.uid == null
                      ? null
                      : () => _push(context, UserPage(uid: me.uid!)),
                ),
              ],
            ),
            // 常用的四个入口做成方块;设置留在下方列表
            if (logged) ...[
              const SizedBox(height: 16),
              EntryGrid(
                tiles: [
                  EntryTile(
                    icon: AppIcons.article,
                    tint: IconTints.blue,
                    label: '我的帖子',
                    onTap: () => _push(context, const MyThreadsPage()),
                  ),
                  EntryTile(
                    icon: AppIcons.bookmark,
                    tint: IconTints.orange,
                    label: '我的收藏',
                    onTap: () => _push(context, const FavoritesPage()),
                  ),
                  EntryTile(
                    icon: AppIcons.credits,
                    tint: IconTints.green,
                    label: '积分记录',
                    onTap: () => _push(context, const CreditLogPage()),
                  ),
                  EntryTile(
                    icon: AppIcons.medal,
                    tint: IconTints.violet,
                    label: '勋章',
                    onTap: () => _push(context, const MedalsPage()),
                  ),
                ],
              ),
            ],
            GroupedSection(
              children: [
                // 有新版本时带红点,关于在设置里
                ListenableBuilder(
                  listenable: appUpdater,
                  builder: (context, _) => GroupedRow(
                    key: const ValueKey('me-settings'),
                    title: '设置',
                    icon: const IconTile(
                      icon: AppIcons.settings,
                      tint: IconTints.gray,
                    ),
                    dot: appUpdater.hasUpdate,
                    onTap: () => Navigator.of(context).pushNamed('/settings'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}
