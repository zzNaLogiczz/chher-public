/// 个人主页与抽屉共用结构化资料和内容入口。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/space_repository.dart';
import '../data/user_group_levels.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
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
  final String uid;
  const UserPage({
    super.key,
    this.repository,
    this.groupLevels,
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
              topPadding:
                  MediaQuery.paddingOf(context).top + NavOverlay.barHeight + 12,
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
  final ValueChanged<UserProfile>? onLoaded;
  final ValueChanged<double>? onIdentityHeight;
  const UserProfileBody({
    super.key,
    this.repository,
    this.groupLevels,
    required this.uid,
    this.topPadding = 12,
    this.onLoaded,
    this.onIdentityHeight,
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
    future: _future,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return StateView.loading();
      }
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final height = _identityKey.currentContext?.size?.height;
        if (height != null) widget.onIdentityHeight?.call(height);
      });
      return ExpressivePageReveal(
        active: true,
        animateOnMount: true,
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: widget.topPadding,
              bottom: 40 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _inset(
                KeyedSubtree(
                  key: _identityKey,
                  child: _IdentityCard(
                    key: UserPage.identityKey,
                    profile: profile,
                    lowerCredits: _lowerCredits,
                  ),
                ),
              ),
              if (profile.onlineHours != null ||
                  profile.credits != null ||
                  profile.evil != null) ...[
                const SizedBox(height: 20),
                _inset(_Statistics(profile: profile)),
              ],
              const SizedBox(height: 12),
              _inset(
                _ThreadsCard(
                  profile: profile,
                  onTap: () => Navigator.of(context).push(
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
        ),
      );
    },
  );

  Widget _inset(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.groupInset),
    child: child,
  );

  List<Widget> _details(UserProfile profile) => [
    if (profile.registeredAt case final value? when value.trim().isNotEmpty)
      GroupedRow(title: '注册时间', value: value),
    if (profile.lastVisitAt case final value? when value.trim().isNotEmpty)
      GroupedRow(title: '最后访问', value: value),
    if (profile.lastPostAt case final value? when value.trim().isNotEmpty)
      GroupedRow(title: '上次发表', value: value),
    if (profile.friends != null)
      GroupedRow(title: '好友', value: '${profile.friends}'),
    if (profile.portalArticles != null && profile.portalArticles! > 0)
      GroupedRow(title: '门户文章', value: '${profile.portalArticles}'),
  ];
}

class _IdentityCard extends StatelessWidget {
  final UserProfile profile;
  final int? lowerCredits;
  const _IdentityCard({super.key, required this.profile, this.lowerCredits});

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
            child: AccountAvatar(url: profile.avatarUrl, size: 88),
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
              DecoratedBox(
                decoration: BoxDecoration(
                  color: t.accentFill,
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.crownStar, size: 13, color: t.accent),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          group,
                          style: AppType.caption.copyWith(color: t.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
      ],
    );
  }
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

class _ProfileCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _ProfileCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: AppTokens.of(context).surface,
      shape: appShape(AppRadii.md),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class _Statistics extends StatelessWidget {
  final UserProfile profile;
  const _Statistics({required this.profile});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final columns = [
      if (profile.onlineHours != null)
        _Statistic(value: profile.onlineHours!, label: '在线时长', suffix: '小时'),
      if (profile.credits != null)
        _Statistic(value: profile.credits!, label: '积分'),
      if (profile.evil != null) _Statistic(value: profile.evil!, label: '邪恶指数'),
    ];
    return _ProfileCard(
      key: UserPage.statsKey,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: AppSpace.hairline,
                  thickness: AppSpace.hairline,
                  color: t.separator,
                ),
              Expanded(child: columns[i]),
            ],
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

class _ThreadsCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onTap;
  const _ThreadsCard({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final subtitle = [
      if (profile.threads != null) '主题 ${profile.threads}',
      if (profile.replies != null) '回帖 ${profile.replies}',
    ].join('，');
    return PressScale(
      key: UserPage.threadsKey,
      onTap: onTap,
      semanticLabel: '主题与回复',
      child: _ProfileCard(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
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
