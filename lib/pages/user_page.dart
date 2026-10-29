/// Real profile identity and statistics, with content one action away.
library;

import 'package:flutter/material.dart';
import '../design/shapes.dart';
import '../design/typography.dart';
import '../ui/grouped.dart';
import '../di.dart';
import '../data/space_repository.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/expressive_controls.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../widgets/account_widgets.dart';
import '../widgets/state_view.dart';
import 'my_threads_page.dart';

class UserPage extends StatefulWidget {
  static const statsKey = ValueKey('user-stats');
  final SpaceRepository? repository;
  final String uid;
  const UserPage({super.key, this.repository, required this.uid});
  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  late Future<UserProfile> _future = (widget.repository ?? spaceRepo).profile(
    widget.uid,
  );
  Future<void> _reload() async {
    setState(
      () => _future = (widget.repository ?? spaceRepo).profile(
        widget.uid,
        refresh: true,
      ),
    );
    await _future;
  }

  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '个人主页',
    surface: AppSurface.grouped,
    body: FutureBuilder<UserProfile>(
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
        final t = AppTokens.of(context);
        return ExpressivePageReveal(
          active: true,
          animateOnMount: true,
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                // 居中身份:头像、名字、UID
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screen,
                    8,
                    AppSpace.screen,
                    0,
                  ),
                  child: Column(
                    children: [
                      AccountAvatar(url: profile.avatarUrl, size: 84),
                      const SizedBox(height: 10),
                      Text(
                        profile.name,
                        textAlign: TextAlign.center,
                        style: AppType.title1.copyWith(color: t.text),
                      ),
                      Text(
                        'UID ${profile.uid}',
                        style: AppType.footnote.copyWith(color: t.text3),
                      ),
                    ],
                  ),
                ),
                // 统计条只取源站给出的前三项;其余进入资料分组,没有统计就不显示
                if (profile.stats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.groupInset,
                      16,
                      AppSpace.groupInset,
                      0,
                    ),
                    child: _StatsBar(
                      key: UserPage.statsKey,
                      entries: profile.stats.entries.take(3).toList(),
                    ),
                  ),
                if (profile.stats.length > 3 || profile.profile.isNotEmpty)
                  GroupedSection(
                    header: '资料',
                    children: [
                      for (final entry in profile.stats.entries.skip(3))
                        GroupedRow(title: entry.key, value: entry.value),
                      for (final entry in profile.profile.entries)
                        GroupedRow(title: entry.key, value: entry.value),
                    ],
                  ),
                GroupedSection(
                  children: [
                    GroupedRow(
                      title: '主题与回复',
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
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 三栏统计:数字在上、名称在下,栏间细竖线
class _StatsBar extends StatelessWidget {
  final List<MapEntry<String, String>> entries;
  const _StatsBar({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: t.surface,
        shape: appShape(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0)
                  VerticalDivider(
                    width: AppSpace.hairline,
                    thickness: AppSpace.hairline,
                    color: t.separator,
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        entries[i].value,
                        style: AppType.title2.copyWith(color: t.text),
                      ),
                      Text(
                        entries[i].key,
                        textAlign: TextAlign.center,
                        style: AppType.footnote.copyWith(color: t.text3),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
