/// 个人主页与抽屉共用结构化资料和内容入口。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/display_time.dart';
import '../data/follow_index.dart';
import '../data/space_repository.dart';
import '../data/user_group_levels.dart';
import '../widgets/chhers_loading_transition.dart';
import '../widgets/chhers_refresh_indicator.dart';
import '../widgets/level_badge.dart';
import '../design/level_tokens.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../data/user_block_index.dart';
import '../ui/user_block_action.dart';
import '../ui/user_follow_action.dart';
import '../models/models.dart';
import '../ui/chrome_button.dart';
import '../ui/grouped.dart';
import '../ui/nav_bar.dart';
import '../ui/press.dart';
import '../widgets/account_widgets.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/state_view.dart';
import 'my_threads_page.dart';

class UserPage extends StatefulWidget {
  static const identityKey = ValueKey('user-identity');
  static const progressKey = ValueKey('user-level-progress');
  static const statsKey = ValueKey('user-stats');
  static const threadsKey = ValueKey('user-threads');
  final SpaceRepository? repository;
  final UserGroupLevels? groupLevels;
  final UserBlockIndex? blockIndex;
  final BlockedUserSource? blockSource;
  final String uid;
  const UserPage({
    super.key,
    this.repository,
    this.groupLevels,
    this.blockIndex,
    this.blockSource,
    required this.uid,
  });

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final _offset = ValueNotifier<double>(0);
  String _name = '';
  double _collapseAt = double.infinity;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final chromeHeight =
        MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
    return Scaffold(
      backgroundColor: t.grouped,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification.metrics.axis == Axis.vertical) {
                _offset.value = notification.metrics.pixels;
              }
              return false;
            },
            child: UserProfileBody(
              uid: widget.uid,
              repository: widget.repository,
              groupLevels: widget.groupLevels,
              blockIndex: widget.blockIndex,
              blockSource: widget.blockSource,
              topPadding: chromeHeight + 12,
              refreshEdgeOffset: chromeHeight,
              onLoaded: (profile) {
                if (_name != profile.name) {
                  setState(() => _name = profile.name);
                }
              },
              onIdentityHeight: (height) {
                if (_collapseAt != height + 12) {
                  setState(() => _collapseAt = height + 12);
                }
              },
            ),
          ),
          NavOverlay(
            leading: ChromeButton(
              icon: AppIcons.back,
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            inlineTitle: _name,
            scrollOffset: _offset,
            collapseAt: _collapseAt,
            background: t.grouped,
          ),
        ],
      ),
    );
  }
}

/// 整页与抽屉共享加载、刷新和错误状态，外壳只接收真实身份。
class UserProfileBody extends StatefulWidget {
  final SpaceRepository? repository;
  final UserGroupLevels? groupLevels;
  final String uid;
  final double topPadding;
  final double refreshEdgeOffset;
  final ValueChanged<UserProfile>? onLoaded;
  final ValueChanged<double>? onIdentityHeight;
  final UserBlockIndex? blockIndex;
  final BlockedUserSource? blockSource;
  final VoidCallback? onOpenBlockSource;
  const UserProfileBody({
    super.key,
    this.repository,
    this.groupLevels,
    required this.uid,
    this.topPadding = 12,
    this.refreshEdgeOffset = 0,
    this.onLoaded,
    this.onIdentityHeight,
    this.blockIndex,
    this.blockSource,
    this.onOpenBlockSource,
  });

  @override
  State<UserProfileBody> createState() => _UserProfileBodyState();
}

class _UserProfileBodyState extends State<UserProfileBody> {
  late Future<UserProfile> _future;
  final _identityKey = GlobalKey();
  int? _lowerCredits;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant UserProfileBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.repository != widget.repository ||
        oldWidget.groupLevels != widget.groupLevels) {
      _future = _load();
    }
  }

  Future<UserProfile> _load({bool refresh = false}) async {
    final generation = ++_generation;
    _lowerCredits = null;
    final profile = await (widget.repository ?? spaceRepo).profile(
      widget.uid,
      refresh: refresh,
    );
    if (mounted && generation == _generation) {
      widget.onLoaded?.call(profile);
      if (profile.group?.trim().isNotEmpty == true &&
          profile.groupId != null &&
          profile.nextLevelCredits != null) {
        unawaited(_loadLowerCredits(profile.groupId!, generation));
      }
    }
    return profile;
  }

  Future<void> _loadLowerCredits(int gid, int generation) async {
    final lower = await (widget.groupLevels ?? userGroupLevels).lowerCredits(
      gid,
    );
    if (mounted && generation == _generation && lower != _lowerCredits) {
      setState(() => _lowerCredits = lower);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load(refresh: true);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfile>(
    key: ValueKey((widget.uid, widget.repository, widget.groupLevels)),
    future: _future,
    builder: (context, snap) => ChhersLoadingTransition(
      animateOnMount: true,
      child: !snap.hasData && snap.connectionState != ConnectionState.done
          ? null
          : _loadedBody(context, snap),
    ),
  );

  Widget _loadedBody(BuildContext context, AsyncSnapshot<UserProfile> snap) {
    final err = snap.error;
    if (err is PageMessage) {
      return StateView.forMessage(
        err,
        onLogin: () async {
          await Navigator.of(context).pushNamed('/login');
          if (mounted) await _reload();
        },
      );
    }
    if (err != null) return StateView.error(err, onRetry: _reload);
    final profile = snap.data!;
    final details = _details(profile);
    final blocks = widget.blockIndex ?? userBlockIndex;
    return ChhersRefreshIndicator(
      edgeOffset: widget.refreshEdgeOffset,
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: widget.topPadding,
          bottom: 40 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Builder(
            builder: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final height = _identityKey.currentContext?.size?.height;
                if (height != null) widget.onIdentityHeight?.call(height);
              });
              return _inset(
                KeyedSubtree(
                  key: _identityKey,
                  child: _IdentityCard(
                    key: UserPage.identityKey,
                    profile: profile,
                    lowerCredits: _lowerCredits,
                    blocks: blocks,
                  ),
                ),
              );
            },
          ),
          _ProfileActions(
            profile: profile,
            blocks: blocks,
            blockSource: widget.blockSource,
            onOpenBlockSource: widget.onOpenBlockSource,
          ),
          const SizedBox(height: 20),
          _inset(
            _Statistics(
              key: UserPage.statsKey,
              profile: profile,
              onThreadsTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MyThreadsPage(
                    uid: profile.uid,
                    title: profile.name,
                    repository: widget.repository,
                  ),
                ),
              ),
            ),
          ),
          if (details.isNotEmpty)
            GroupedSection(header: '资料', children: details),
        ],
      ),
    );
  }

  Widget _inset(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.groupInset),
    child: child,
  );

  List<Widget> _details(UserProfile profile) => [
    if (profile.registeredAt case final value? when value.trim().isNotEmpty)
      GroupedRow(
        title: '注册时间',
        value: formatDisplayTime(raw: value, style: DisplayTimeStyle.dateOnly),
        valueMaxLines: 1,
      ),
    if (profile.lastVisitAt case final value? when value.trim().isNotEmpty)
      GroupedRow(
        title: '最后访问',
        value: formatDisplayTime(raw: value, style: DisplayTimeStyle.dateOnly),
        valueMaxLines: 1,
      ),
    if (profile.lastPostAt case final value? when value.trim().isNotEmpty)
      GroupedRow(
        title: '上次发表',
        value: formatDisplayTime(raw: value, style: DisplayTimeStyle.dateOnly),
        valueMaxLines: 1,
      ),
    if (profile.friends != null)
      GroupedRow(title: '好友', value: '${profile.friends}'),
    if (profile.portalArticles != null && profile.portalArticles! > 0)
      GroupedRow(title: '门户文章', value: '${profile.portalArticles}'),
  ];
}

class _IdentityCard extends StatelessWidget {
  final UserProfile profile;
  final int? lowerCredits;
  final UserBlockIndex blocks;
  const _IdentityCard({
    super.key,
    required this.profile,
    this.lowerCredits,
    required this.blocks,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final group = profile.group;
    final remaining = profile.nextLevelCredits;
    final progress =
        lowerCredits != null && profile.credits != null && remaining != null
        ? userGroupProgress(
            lowerCredits: lowerCredits!,
            credits: profile.credits!,
            remainingCredits: remaining,
          )
        : null;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            boxShadow: t.shadowE1,
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: AccountAvatar(
              name: profile.name,
              url: profile.avatarUrl,
              size: 88,
              refreshable: true,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          profile.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppType.title1.copyWith(color: t.text),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'UID ${profile.uid}',
              style: AppType.footnote.copyWith(color: t.text3),
            ),
            if (group != null && group.trim().isNotEmpty) ...[
              if (LevelDefinition.lookup(profile.groupId) != null)
                LevelBadge(gid: profile.groupId)
              else
                Text(group, style: AppType.footnote.copyWith(color: t.text2)),
              if (remaining != null) ...[
                _LevelProgress(remaining: remaining, progress: progress),
                Text(
                  '差 $remaining 积分',
                  style: AppType.caption.copyWith(color: t.text3),
                ),
              ],
            ],
          ],
        ),
        ListenableBuilder(
          listenable: blocks,
          builder: (context, _) {
            final entry = blocks.entryFor(profile.uid);
            final note = entry?.note;
            return ExpressiveVisibility(
              key: ValueKey(blocks.epoch),
              visible: entry != null,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.warnBg,
                        borderRadius: BorderRadius.circular(AppRadii.xs),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(
                          '已加入黑名单',
                          style: AppType.footnote.copyWith(color: t.warn),
                        ),
                      ),
                    ),
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          note,
                          textAlign: TextAlign.center,
                          style: AppType.subhead.copyWith(color: t.text2),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ProfileActions extends StatelessWidget {
  final UserProfile profile;
  final UserBlockIndex blocks;
  final BlockedUserSource? blockSource;
  final VoidCallback? onOpenBlockSource;
  const _ProfileActions({
    required this.profile,
    required this.blocks,
    this.blockSource,
    this.onOpenBlockSource,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([chhSession, followIndex, blocks]),
    builder: (context, _) {
      final uid = UserBlockIndex.normalizeUid(profile.uid);
      if (uid == null ||
          uid == UserBlockIndex.normalizeUid(chhSession.badges.uid) ||
          !followIndex.accountReady ||
          !blocks.accountReady) {
        return const SizedBox.shrink();
      }
      final followEpoch = followIndex.epoch;
      final blockEpoch = blocks.epoch;
      bool isCurrent() =>
          followEpoch == followIndex.epoch && blockEpoch == blocks.epoch;
      final t = AppTokens.of(context);
      final blocked = blocks.isBlocked(uid);
      final followed = followIndex.isFollowed(uid);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.groupInset,
          18,
          AppSpace.groupInset,
          0,
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            if (!blocked)
              _ProfilePill(
                label: followed ? '已关注' : '关注',
                icon: followed ? AppIcons.userCheck : AppIcons.userPlus,
                foreground: followed ? t.text2 : t.accent,
                background: followed ? t.fill : t.accentFill,
                onTap: () {
                  if (!isCurrent()) return;
                  toggleUserFollow(
                    context,
                    uid: uid,
                    name: profile.name,
                    avatarUrl: profile.avatarUrl,
                  );
                },
              ),
            _ProfilePill(
              label: blocked ? '解除黑名单' : '加入黑名单',
              foreground: blocked
                  ? t.accent
                  : (t.isDark ? Radix.red11Dark : Radix.red11Light),
              background: blocked ? t.fill : null,
              outlined: !blocked,
              onTap: () {
                if (!isCurrent()) return;
                toggleUserBlock(
                  context,
                  uid: uid,
                  name: profile.name,
                  avatarUrl: profile.avatarUrl,
                  index: blocks,
                  src: blockSource,
                  onOpenSource: onOpenBlockSource,
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class _ProfilePill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color foreground;
  final Color? background;
  final bool outlined;
  final VoidCallback onTap;
  const _ProfilePill({
    required this.label,
    this.icon,
    required this.foreground,
    this.background,
    this.outlined = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: background,
      shape: appShape(AppRadii.full).copyWith(
        side: outlined
            ? BorderSide(color: foreground, width: AppSpace.hairline)
            : BorderSide.none,
      ),
    ),
    child: PressHighlight(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(AppRadii.full),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.singleLineHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: AppType.subhead.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LevelProgress extends StatelessWidget {
  final int remaining;
  final double? progress;
  const _LevelProgress({required this.remaining, this.progress});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      key: UserPage.progressKey,
      label: '升级进度',
      value: '差 $remaining 积分',
      child: SizedBox(
        width: 56,
        height: 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xs),
          child: ColoredBox(
            color: t.fill,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress ?? 0),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.revealDuration,
              curve: AppMotion.revealCurve,
              builder: (context, value, child) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0, 1),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Statistics extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onThreadsTap;
  const _Statistics({
    super.key,
    required this.profile,
    required this.onThreadsTap,
  });

  @override
  Widget build(BuildContext context) {
    final columns = [
      if (profile.onlineHours != null)
        _Statistic(value: profile.onlineHours!, label: '在线时长', suffix: '小时'),
      if (profile.credits != null)
        _Statistic(value: profile.credits!, label: '积分'),
      if (profile.evil != null) _Statistic(value: profile.evil!, label: '邪恶指数'),
    ];
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppTokens.of(context).surface,
        shape: appShape(UserProfileTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UserProfileTokens.cardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (columns.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: UserProfileTokens.statisticsHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Center(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final column in columns) Expanded(child: column),
                      ],
                    ),
                  ),
                ),
              ),
            _ThreadsRow(profile: profile, onTap: onThreadsTap),
          ],
        ),
      ),
    );
  }
}

class _Statistic extends StatelessWidget {
  final int value;
  final String label;
  final String? suffix;
  const _Statistic({required this.value, required this.label, this.suffix});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  '$value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.title2.copyWith(color: t.text),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 2),
                Text(suffix!, style: AppType.footnote.copyWith(color: t.text2)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppType.footnote.copyWith(color: t.text2),
          ),
        ],
      ),
    );
  }
}

class _ThreadsRow extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onTap;
  const _ThreadsRow({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final subtitle = [
      if (profile.threads != null) '主题 ${profile.threads}',
      if (profile.replies != null) '回帖 ${profile.replies}',
    ].join('，');
    return PressHighlight(
      key: UserPage.threadsKey,
      onTap: onTap,
      semanticLabel: '主题与回复',
      borderRadius: BorderRadius.circular(UserProfileTokens.rowRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: UserProfileTokens.threadsHeight,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '主题与回复',
                      style: AppType.headline.copyWith(color: t.text),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: AppType.footnote.copyWith(color: t.text2),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.forward, size: 13, color: t.text3),
            ],
          ),
        ),
      ),
    );
  }
}
