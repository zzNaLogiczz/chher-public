/// 我的页:漆面身份卡 + 纸面四列入口行 + 工具分组(朱漆红 v2)
///
/// 一级页结构照真机:身份卡住进漆面(头像/昵称/UID),纸面上是
/// 无底色的四列入口行与黑名单/设置分组;等级与统计属于用户主页。
library;

import 'package:flutter/material.dart';
import '../di.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/lac_scaffold.dart';
import '../widgets/account_widgets.dart';
import '../widgets/expressive_controls.dart';
import '../design/tokens.dart';
import '../ui/grouped.dart';
import '../update/update_controller.dart';
import 'favorites_page.dart';
import 'blocked_users_page.dart';
import 'medals_page.dart';
import 'my_threads_page.dart';
import 'credit_log_page.dart';
import 'user_page.dart';

/// 一级页入口(底栏"我的"):漆面骨架。
class MePage extends StatelessWidget {
  const MePage({super.key});
  @override
  Widget build(BuildContext context) => LacScaffold(
    title: '我的',
    mast: const _MemberCard(),
    // 整头固定(用户定稿):身份卡与大标题不许上收,正文在纸面内独立滚动
    pinned: true,
    body: const MeBody(),
  );
}

/// 推送路由用的纸面版本(二级页不上漆)
class MeFallbackPage extends StatelessWidget {
  const MeFallbackPage({super.key});
  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '我的',
    surface: AppSurface.grouped,
    body: const MeBody(withIdentity: true),
  );
}

/// 漆面身份卡:头像/昵称/UID,点进个人主页(或登录)
class _MemberCard extends StatelessWidget {
  const _MemberCard();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: chhSession,
    builder: (context, _) {
      final me = chhSession.badges;
      final logged = chhSession.loggedIn;
      return AccountIdentityRow(
        name: logged ? (me.userName ?? '已登录') : '登录 CHH',
        avatarUrl: logged ? me.avatarUrl : null,
        detail: logged
            ? (me.uid == null ? null : 'UID ${me.uid}')
            : '收藏内容，参与讨论',
        onLac: true,
        onTap: !logged
            ? () => Navigator.of(context).pushNamed('/login')
            : me.uid == null
            ? null
            : () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => UserPage(uid: me.uid!))),
      );
    },
  );
}

/// 纸面内容:四列入口行 + 工具分组。[withIdentity] 供推送路由补身份行。
class MeBody extends StatelessWidget {
  final bool withIdentity;
  const MeBody({super.key, this.withIdentity = false});

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
            if (withIdentity)
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
            // 定稿入口行:无卡片无底色,直接排在纸面上
            if (logged)
              EntryRow(
                cells: [
                  EntryCell(
                    icon: AppIcons.article,
                    tint: AppTokens.of(context).tintZhu,
                    label: '我的帖子',
                    onTap: () => _push(context, const MyThreadsPage()),
                  ),
                  EntryCell(
                    icon: AppIcons.bookmark,
                    tint: AppTokens.of(context).tintDai,
                    label: '我的收藏',
                    onTap: () => _push(context, const FavoritesPage()),
                  ),
                  EntryCell(
                    icon: AppIcons.credits,
                    tint: AppTokens.of(context).tintTan,
                    label: '积分记录',
                    onTap: () => _push(context, const CreditLogPage()),
                  ),
                  EntryCell(
                    icon: AppIcons.medal,
                    tint: AppTokens.of(context).tintZhe,
                    label: '勋章',
                    onTap: () => _push(context, const MedalsPage()),
                  ),
                ],
              ),
            GroupedSection(
              children: [
                GroupedRow(
                  title: '黑名单',
                  icon: const IconTile(
                    icon: AppIcons.forbidden,
                    tint: IconTints.gray,
                  ),
                  onTap: () => _push(context, const BlockedUsersPage()),
                ),
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
