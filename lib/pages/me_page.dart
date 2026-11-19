/// 我的页：身份、跨缝入口浮卡和工具卡。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../data/space_repository.dart';
import '../core/chh_urls.dart';
import '../parser/header_parser.dart';
import '../di.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/lacquer_tab_scaffold.dart';
import '../widgets/account_widgets.dart';
import '../widgets/level_badge.dart';
import '../design/level_tokens.dart';
import '../design/brand.dart';
import '../design/tokens.dart';
import '../design/icons.dart';
import '../design/shapes.dart';
import '../design/typography.dart';
import '../ui/grouped.dart';
import '../ui/press.dart';
import '../update/update_controller.dart';
import 'favorites_page.dart';
import 'blocked_users_page.dart';
import 'medals_page.dart';
import 'my_threads_page.dart';
import 'credit_log_page.dart';
import 'user_page.dart';

class MePage extends StatelessWidget {
  const MePage({super.key, this.repository});
  final SpaceRepository? repository;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const PageStorageKey('me-tab-scroll'),
    child: _ProfileMe(repository: repository ?? spaceRepo),
  );
}

/// 推送路由用的纸面版本(二级页不上漆)
class MeFallbackPage extends StatelessWidget {
  const MeFallbackPage({super.key, this.repository});
  final SpaceRepository? repository;
  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '我的',
    surface: AppSurface.grouped,
    body: MeBody(withIdentity: true, repository: repository),
  );
}

/// 漆面身份资料与独立的主页或登录入口。
class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.me, required this.logged, this.profile});
  final UserProfile? profile;
  final HeaderBadges me;
  final bool logged;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final name = logged ? (me.userName ?? '已登录') : '登录 CHH';
    final onTap = !logged
        ? () => Navigator.of(context).pushNamed('/login')
        : me.uid == null
        ? null
        : () => _push(context, UserPage(uid: me.uid!));
    final action = onTap == null
        ? null
        : PressScale(
            onTap: onTap,
            semanticLabel: logged ? '主页' : '登录',
            child: SizedBox(
              height: 44,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: MeTokens.glass(t),
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          logged ? '主页' : '登录',
                          style: AppType.footnote.copyWith(
                            color: t.onLac,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(AppIcons.forward, size: 12, color: t.onLac2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        MeTokens.identityTitleGap,
        AppSpace.screen,
        MeTokens.headerTail,
      ),
      child: Row(
        key: const ValueKey('me-identity-row'),
        children: [
          AccountAvatar(
            name: name,
            url: logged ? me.avatarUrl : null,
            size: MeTokens.avatar,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.title1.copyWith(
                    fontSize: MeTokens.nameSize,
                    height: 1.15,
                    color: t.onLac,
                  ),
                ),
                if (logged && me.uid != null) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: MeTokens.metadataGap,
                    runSpacing: MeTokens.labelGap,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'UID ${me.uid}',
                        style: AppType.footnote.copyWith(color: t.onLac2),
                      ),
                      if (LevelDefinition.lookup(profile?.groupId) != null)
                        LevelBadge(gid: profile!.groupId, onLacquer: true),
                    ],
                  ),
                ],
                if (large && action != null) action,
              ],
            ),
          ),
          if (!large && action != null) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }
}

/// Both identities consume profile data. A session change invalidates
/// pending reads before a different account can be painted.
class _ProfileMe extends StatefulWidget {
  const _ProfileMe({required this.repository, this.fallback = false});
  final SpaceRepository repository;
  final bool fallback;
  @override
  State<_ProfileMe> createState() => _ProfileMeState();
}

class _ProfileMeState extends State<_ProfileMe> {
  UserProfile? _profile;
  String? _uid;
  int _auth = -1;
  int _request = 0;
  bool _logged = false;
  bool _loading = false;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    chhSession.addListener(_sessionChanged);
    widget.repository.meCache.addListener(_cacheLoaded);
    _syncSession(initial: true);
  }

  void _cacheLoaded() {
    if (!mounted || _profile != null || _uid == null) return;
    final cached = widget.repository.meCache.forUser(_uid!);
    if (cached != null) setState(() => _profile = cached);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (active && !_active && _uid != null) {
      _profile = widget.repository.meCache.forUser(_uid!) ?? _profile;
      if (!_loading) unawaited(_load(refresh: true, background: true));
    }
    _active = active;
  }

  void _syncSession({bool initial = false}) {
    final logged = chhSession.loggedIn;
    final auth = chhSession.authenticationRevision;
    final uid = logged
        ? chhSession.badges.uid ?? (auth == _auth ? _uid : null)
        : null;
    if (logged == _logged && uid == _uid && auth == _auth) return;
    final sameAccount = logged && _logged && uid != null && uid == _uid;
    _logged = logged;
    _uid = uid;
    _auth = auth;
    _request++;
    if (!logged || uid != null) widget.repository.meCache.select(uid);
    _profile = sameAccount
        ? _profile
        : (uid == null ? null : widget.repository.meCache.forUser(uid));
    _loading = false;
    if (uid != null) {
      unawaited(_load(refresh: !initial || _profile != null, background: true));
    }
  }

  void _sessionChanged() {
    _syncSession();
    if (mounted) setState(() {});
  }

  Future<void> _load({required bool refresh, bool background = false}) async {
    final uid = _uid;
    if (uid == null) return;
    final auth = _auth;
    final repository = widget.repository;
    final generation = repository.client.cacheGeneration;
    final request = ++_request;
    _loading = true;
    try {
      final profile = await repository.profile(uid, refresh: refresh);
      if (request != _request ||
          generation != repository.client.cacheGeneration ||
          auth != chhSession.authenticationRevision ||
          !chhSession.loggedIn ||
          (chhSession.badges.uid != null && chhSession.badges.uid != uid)) {
        return;
      }
      if (profile.uid != uid) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      repository.meCache.put(profile);
      if (!mounted) return;
      setState(() {
        if (!background || _profile == null) _profile = profile;
        _loading = false;
      });
    } catch (_) {
      // A failed background read leaves the displayed snapshot unchanged.
    } finally {
      if (mounted && request == _request && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refresh() async {
    // Header hydration still goes through the existing session observer.
    // Even if it fails, give profile data its own refresh attempt.
    try {
      await chhClient.getHtml(ChhUrls.forumIndex(), refresh: true);
    } finally {
      if (mounted) {
        final pending = _load(refresh: true);
        setState(() {});
        await pending;
      }
    }
  }

  @override
  void dispose() {
    widget.repository.meCache.removeListener(_cacheLoaded);
    chhSession.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = chhSession.badges;
    final me = _logged && _uid != null
        ? HeaderBadges(
            notices: header.notices,
            messages: header.messages,
            uid: _uid,
            userName: header.userName ?? _profile?.name,
          )
        : header;
    final logged = _logged;
    if (!widget.fallback &&
        AppTokens.of(context).style != AppearanceStyle.misty) {
      return Stack(
        children: [
          LacquerTabScaffold(
            mistyCompact: true,
            mistyContentGap: TabChromeTokens.mistyEntriesGap,
            title: '我的',
            headerBody: _MemberCard(me: me, logged: logged, profile: _profile),
            compactTitle: SlidingCompactTitle(
              title: logged ? (me.userName ?? '已登录') : '登录 CHH',
              discussion: false,
            ),
            compactLeading: logged
                ? AccountAvatar(
                    name: me.userName ?? '已登录',
                    url: me.avatarUrl,
                    size: MeTokens.compactAvatar,
                  )
                : null,
            seamOverlap: logged ? MeTokens.overlap : 0,
            onRefresh: _refresh,
            slivers: [
              if (logged)
                const SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpace.groupInset,
                  ),
                  sliver: SliverToBoxAdapter(child: _Entries()),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.groupInset,
                  MeTokens.cardGap,
                  AppSpace.groupInset,
                  0,
                ),
                sliver: const SliverToBoxAdapter(child: _Tools()),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: MeTokens.colophonClearance),
              ),
            ],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: MeTokens.colophonBottom,
            child: IgnorePointer(child: _Colophon(fixed: true)),
          ),
        ],
      );
    }
    final identity = _MistyIdentity(
      me: me,
      logged: _logged,
      profile: _profile,
      loading: _loading,
    );
    final cards = <Widget>[
      identity,
      if (_logged) ...[
        const SizedBox(height: MeTokens.cardGap),
        const _Entries(),
      ],
      const SizedBox(height: MeTokens.cardGap),
      const _Tools(),
    ];
    if (widget.fallback) {
      return ListView(
        padding: const EdgeInsets.all(AppSpace.groupInset),
        children: [...cards, const _Colophon()],
      );
    }
    return Stack(
      children: [
        LacquerTabScaffold(
          mistyCompact: true,
          mistyContentGap: MeTokens.cardGap,
          headerBody: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.groupInset,
              MeTokens.identityTitleGap,
              AppSpace.groupInset,
              0,
            ),
            child: identity,
          ),
          title: '我的',
          compactTitle: SlidingCompactTitle(
            title: _logged ? (me.userName ?? '已登录') : '未登录',
            discussion: false,
          ),
          compactLeading: _logged
              ? AccountAvatar(
                  name: me.userName ?? '已登录',
                  url: me.avatarUrl,
                  size: MeTokens.compactAvatar,
                )
              : null,
          onRefresh: _refresh,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.groupInset,
              ),
              sliver: SliverList.list(
                children: [
                  if (_logged) ...[
                    const _Entries(),
                    const SizedBox(height: MeTokens.cardGap),
                  ],
                  const _Tools(),
                ],
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: MeTokens.colophonClearance),
            ),
          ],
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: MeTokens.colophonBottom,
          child: IgnorePointer(child: _Colophon(fixed: true)),
        ),
      ],
    );
  }
}

class _MistyIdentity extends StatelessWidget {
  const _MistyIdentity({
    required this.me,
    required this.logged,
    required this.profile,
    required this.loading,
  });
  final HeaderBadges me;
  final bool logged;
  final UserProfile? profile;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final name = logged ? (me.userName ?? '已登录') : '未登录';
    final canOpen = logged && me.uid != null;
    final group = profile?.group?.trim();
    final complete =
        profile?.credits != null &&
        profile?.threads != null &&
        profile?.replies != null;
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final action = logged
        ? canOpen
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '主页',
                      style: MeTokens.homeLabel.copyWith(color: t.text2),
                    ),
                    const SizedBox(width: MeTokens.labelGap),
                    Icon(
                      AppIcons.forward,
                      size: MeTokens.homeChevron,
                      color: t.text3,
                    ),
                  ],
                )
              : const SizedBox.shrink()
        : PressScale(
            semanticLabel: '登录',
            onTap: () => Navigator.of(context).pushNamed('/login'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: MeTokens.actionTarget,
              ),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: MeTokens.loginHeight,
                  ),
                  padding: MeTokens.loginPadding,
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                  child: Text(
                    '登录',
                    style: MeTokens.loginLabel.copyWith(color: t.onAccent),
                  ),
                ),
              ),
            ),
          );
    final content = DecoratedBox(
      key: const ValueKey('me-identity-card'),
      decoration: ShapeDecoration(
        color: t.surface,
        shape: appShape(MeTokens.cardRadius),
        shadows: MeTokens.cardShadow(t),
      ),
      child: Padding(
        padding: const EdgeInsets.all(MeTokens.identityInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              key: const ValueKey('me-identity-row'),
              children: [
                KeyedSubtree(
                  key: const ValueKey('me-identity-avatar'),
                  child: AccountAvatar(
                    name: name,
                    url: logged ? me.avatarUrl : null,
                    size: MeTokens.identityAvatar,
                  ),
                ),
                const SizedBox(width: MeTokens.identityGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: MeTokens.identityName.copyWith(color: t.text),
                      ),
                      if (logged) ...[
                        const SizedBox(height: MeTokens.labelGap),
                        Wrap(
                          spacing: MeTokens.metadataGap,
                          runSpacing: MeTokens.labelGap,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (me.uid != null)
                              Text(
                                'UID ${me.uid}',
                                style: MeTokens.identityMeta.copyWith(
                                  color: t.text3,
                                ),
                              ),
                            if (group != null && group.isNotEmpty)
                              if (LevelDefinition.lookup(profile?.groupId) !=
                                  null)
                                LevelBadge(gid: profile!.groupId)
                              else
                                Text(
                                  group,
                                  style: MeTokens.groupLabel.copyWith(
                                    color: t.text2,
                                  ),
                                ),
                          ],
                        ),
                      ],
                      if (large)
                        Align(alignment: Alignment.centerLeft, child: action),
                    ],
                  ),
                ),
                if (!large) ...[
                  const SizedBox(width: MeTokens.metadataGap),
                  action,
                ],
              ],
            ),
            if (logged && (loading || complete)) ...[
              const SizedBox(height: MeTokens.statsGap),
              if (!complete)
                SizedBox(
                  key: const ValueKey('me-stats-placeholder'),
                  height:
                      MeTokens.statsHeight *
                      MediaQuery.textScalerOf(context).scale(1),
                )
              else
                ConstrainedBox(
                  key: const ValueKey('me-stats'),
                  constraints: BoxConstraints(
                    minHeight:
                        MeTokens.statsHeight *
                        MediaQuery.textScalerOf(context).scale(1),
                  ),
                  child: Row(
                    children: [
                      for (final stat in [
                        ('积分', profile!.credits!),
                        ('主题', profile!.threads!),
                        ('回帖', profile!.replies!),
                      ])
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${stat.$2}',
                                style: MeTokens.statNumber.copyWith(
                                  color: t.text,
                                ),
                              ),
                              const SizedBox(height: MeTokens.labelGap),
                              Text(
                                stat.$1,
                                style: MeTokens.statLabel.copyWith(
                                  color: t.text3,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    return canOpen
        ? PressScale(
            onTap: () => _push(context, UserPage(uid: me.uid!)),
            semanticLabel: '主页',
            scale: AppPressScale.card,
            child: content,
          )
        : content;
  }
}

class _Entries extends StatelessWidget {
  const _Entries();

  @override
  Widget build(BuildContext context) {
    return LacEntryStrip(
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
    );
  }
}

class _Tools extends StatelessWidget {
  const _Tools();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      key: const ValueKey('me-tools'),
      decoration: ShapeDecoration(
        color: t.surface,
        shape: appShape(MeTokens.cardRadius),
        shadows: MeTokens.cardShadow(t),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppClip(
              radius: MeTokens.innerRadius,
              child: GroupedRow(
                title: '黑名单',
                leading: const IconTile(icon: AppIcons.forbiddenBold),
                onTap: () => _push(context, const BlockedUsersPage()),
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([appUpdater, appearance]),
              builder: (context, _) => AppClip(
                radius: MeTokens.innerRadius,
                child: GroupedRow(
                  key: const ValueKey('me-settings'),
                  title: '设置',
                  leading: const IconTile(icon: AppIcons.settingsBold),
                  dot: appUpdater.hasUpdate || !appearance.styleDotSeen,
                  onTap: () => Navigator.of(context).pushNamed('/settings'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级路由仍保留原有纸面身份与四个入口。
class MeBody extends StatelessWidget {
  final bool withIdentity;
  const MeBody({super.key, this.withIdentity = false, this.repository});
  final SpaceRepository? repository;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: chhSession,
    builder: (context, _) {
      final me = chhSession.badges;
      final logged = chhSession.loggedIn;
      if (withIdentity &&
          AppTokens.of(context).style == AppearanceStyle.misty) {
        return _ProfileMe(fallback: true, repository: repository ?? spaceRepo);
      }
      return ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (withIdentity)
            GroupedSection(
              children: [
                AccountIdentityRow(
                  name: logged ? (me.userName ?? '已登录') : '登录 CHH',
                  avatarUrl: logged ? me.avatarUrl : null,
                  detail: logged
                      ? (me.uid == null ? null : 'UID ${me.uid}')
                      : null,
                  onTap: !logged
                      ? () => Navigator.of(context).pushNamed('/login')
                      : me.uid == null
                      ? null
                      : () => _push(context, UserPage(uid: me.uid!)),
                ),
              ],
            ),
          if (logged && withIdentity)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: EntryGrid(
                tiles: [
                  EntryTile(
                    icon: AppIcons.articleBold,
                    label: '我的帖子',
                    onTap: () => _push(context, const MyThreadsPage()),
                  ),
                  EntryTile(
                    icon: AppIcons.bookmarkFilled,
                    label: '我的收藏',
                    onTap: () => _push(context, const FavoritesPage()),
                  ),
                  EntryTile(
                    icon: AppIcons.creditsBold,
                    label: '积分记录',
                    onTap: () => _push(context, const CreditLogPage()),
                  ),
                  EntryTile(
                    icon: AppIcons.medalBold,
                    label: '勋章',
                    onTap: () => _push(context, const MedalsPage()),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.groupInset,
              MeTokens.cardGap,
              AppSpace.groupInset,
              0,
            ),
            child: _Tools(),
          ),
          const _Colophon(),
        ],
      );
    },
  );
}

class _Colophon extends StatelessWidget {
  const _Colophon({this.fixed = false});
  final bool fixed;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: fixed
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          appDisplayName,
          style: AppType.caption.copyWith(
            color: AppTokens.of(context).text3.withValues(alpha: .55),
            letterSpacing: 3.2,
          ),
        ),
      ),
    ),
  );
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
