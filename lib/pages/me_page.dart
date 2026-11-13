/// 我的页:漆面身份卡与深漆凹槽入口,纸面保留黑名单/设置分组。
///
/// 朱砂整头固定;薄暮使用统一名片,推送路由保留纸面入口方块。
/// 等级与统计属于用户主页。
library;

import 'package:flutter/material.dart';
import '../di.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/lac_scaffold.dart';
import '../widgets/account_widgets.dart';
import '../widgets/expressive_controls.dart';
import '../design/tokens.dart';
import '../design/shapes.dart';
import '../design/typography.dart';
import '../ui/grouped.dart';
import '../update/update_controller.dart';
import 'favorites_page.dart';
import 'blocked_users_page.dart';
import 'medals_page.dart';
import 'my_threads_page.dart';
import 'credit_log_page.dart';
import 'user_page.dart';

/// 一级页入口(底栏"我的"):按风格选骨架。
class MePage extends StatelessWidget {
  const MePage({super.key});
  @override
  Widget build(BuildContext context) {
    // 薄暮:身份与四个入口合为一张纸面名片。
    if (AppTokens.of(context).style == AppearanceStyle.misty) {
      return LargeTitleScaffold(
        title: '我的',
        showBack: false,
        surface: AppSurface.grouped,
        body: const MeBody(withIdentity: true, unifiedIdentity: true),
      );
    }
    return LacScaffold(
      title: '我的',
      mast: const _MemberCard(),
      fitMast: true,
      markFade: true,
      seamGap: 24,
      // 整头固定(用户定稿):身份卡与大标题不许上收,正文在纸面内独立滚动
      pinned: true,
      surface: AppSurface.grouped,
      body: const MeBody(),
    );
  }
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

/// 漆面身份区:身份行下方 22dp 放置登录后可用的四列入口。
class _MemberCard extends StatelessWidget {
  const _MemberCard();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: chhSession,
    builder: (context, _) {
      final me = chhSession.badges;
      final logged = chhSession.loggedIn;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountIdentityRow(
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
                : () => _push(context, UserPage(uid: me.uid!)),
          ),
          if (logged) ...[
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
              child: LacEntryStrip(
                cells: [
                  LacEntryCell(
                    icon: AppIcons.articleBold,
                    label: '我的帖子',
                    onTap: () => _push(context, const MyThreadsPage()),
                  ),
                  LacEntryCell(
                    icon: AppIcons.bookmarkFilled,
                    label: '我的收藏',
                    onTap: () => _push(context, const FavoritesPage()),
                  ),
                  LacEntryCell(
                    icon: AppIcons.creditsBold,
                    label: '积分记录',
                    onTap: () => _push(context, const CreditLogPage()),
                  ),
                  LacEntryCell(
                    icon: AppIcons.medalBold,
                    label: '勋章',
                    onTap: () => _push(context, const MedalsPage()),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// 纸面内容:薄暮统一名片,推送路由保留身份行与入口方块。
class MeBody extends StatelessWidget {
  final bool withIdentity;
  final bool unifiedIdentity;
  const MeBody({
    super.key,
    this.withIdentity = false,
    this.unifiedIdentity = false,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    // 外观偏好也在监听里:朱砂上线引导红点(设置行)消费后立即消失
    animation: Listenable.merge([chhSession, appearance]),
    builder: (context, _) {
      final me = chhSession.badges;
      final logged = chhSession.loggedIn;
      final t = AppTokens.of(context);
      final content = <Widget>[
        if (unifiedIdentity)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.groupInset, 12, AppSpace.groupInset, 0,
            ),
            child: MistyAccountHub(
              name: logged ? (me.userName ?? '已登录') : '登录 CHH',
              avatarUrl: logged ? me.avatarUrl : null,
              detail: logged
                  ? (me.uid == null ? null : 'UID ${me.uid}')
                  : '收藏内容，参与讨论',
              onIdentityTap: !logged
                  ? () => Navigator.of(context).pushNamed('/login')
                  : me.uid == null
                  ? null
                  : () => _push(context, UserPage(uid: me.uid!)),
              entries: logged
                  ? [
                      MistyAccountEntry(
                        icon: AppIcons.articleBold,
                        tint: t.mistyBlue,
                        label: '我的帖子',
                        onTap: () => _push(context, const MyThreadsPage()),
                      ),
                      MistyAccountEntry(
                        icon: AppIcons.bookmarkFilled,
                        tint: t.mistyOrange,
                        label: '我的收藏',
                        onTap: () => _push(context, const FavoritesPage()),
                      ),
                      MistyAccountEntry(
                        icon: AppIcons.creditsBold,
                        tint: t.mistyGreen,
                        label: '积分记录',
                        onTap: () => _push(context, const CreditLogPage()),
                      ),
                      MistyAccountEntry(
                        icon: AppIcons.medalBold,
                        tint: t.mistyViolet,
                        label: '勋章',
                        onTap: () => _push(context, const MedalsPage()),
                      ),
                    ]
                  : const [],
            ),
          ),
        if (withIdentity && !unifiedIdentity)
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
        // 推送路由保留原有纸面入口。
        if (logged && withIdentity && !unifiedIdentity)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: EntryGrid(
              tiles: [
                EntryTile(
                  icon: AppIcons.article,
                  tint: IconTints.mistyBlue,
                  label: '我的帖子',
                  onTap: () => _push(context, const MyThreadsPage()),
                ),
                EntryTile(
                  icon: AppIcons.bookmark,
                  tint: IconTints.mistyOrange,
                  label: '我的收藏',
                  onTap: () => _push(context, const FavoritesPage()),
                ),
                EntryTile(
                  icon: AppIcons.credits,
                  tint: IconTints.mistyGreen,
                  label: '积分记录',
                  onTap: () => _push(context, const CreditLogPage()),
                ),
                EntryTile(
                  icon: AppIcons.medal,
                  tint: IconTints.mistyViolet,
                  label: '勋章',
                  onTap: () => _push(context, const MedalsPage()),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.groupInset, 14, AppSpace.groupInset, 0,
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: t.surface,
              shape: appShape(AppRadii.md),
            ),
            child: AppClip(
              radius: AppRadii.md,
              child: Column(
                children: [
                  GroupedRow(
                    title: '黑名单',
                    leading: const AccountToolWell(icon: AppIcons.forbiddenBold),
                    onTap: () => _push(context, const BlockedUsersPage()),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpace.rowInset + 30 + 12,
                    ),
                    child: Divider(
                      height: AppSpace.hairline,
                      thickness: AppSpace.hairline,
                      color: t.separator.withValues(alpha: .42),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: appUpdater,
                    builder: (context, _) => GroupedRow(
                      key: const ValueKey('me-settings'),
                      title: '设置',
                      leading: const AccountToolWell(
                        icon: AppIcons.settingsBold,
                        accent: true,
                      ),
                      dot: appUpdater.hasUpdate || !appearance.styleDotSeen,
                      onTap: () => Navigator.of(context).pushNamed('/settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
      return ExpressivePageReveal(
        active: true,
        revision: (logged, me.uid),
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 40)
                      .clamp(0.0, double.infinity)
                      .toDouble(),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...content,
                      const Spacer(),
                      ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'CHHER',
                              style: AppType.caption.copyWith(
                                color: t.text3.withValues(alpha: .22),
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
